# frozen_string_literal: true

module Flow
  module AI
    module Tasks
      # Compara una idea contra las demás del desafío y avisa cuáles son la
      # misma idea con otras palabras.
      #
      # Tiene DOS caminos, y quién los elige es el proveedor, no la tarea:
      #
      #   con embeddings   similitud coseno, local, determinista y barata.
      #   sin embeddings   se le pregunta al modelo, que además explica POR QUÉ
      #                    se parecen — que es lo que una persona necesita para
      #                    decidir si fusiona o no.
      #
      # Anthropic no tiene endpoint de embeddings, así que con el proveedor
      # real el primer camino no existe. Antes eso era una excepción en la cara
      # del usuario; ahora es el segundo camino.
      class DetectDuplicates < Base
        THRESHOLD = 0.82

        # Tope de lo que entra en la comparación. Más que esto no es un
        # problema de prompt sino de búsqueda: ahí hace falta pgvector con un
        # proveedor de embeddings, no una lista más larga.
        MAX_CANDIDATES = 40

        def messages
          [
            { role: "system", content: <<~TXT.squish },
              Decís cuáles de las ideas que te dan son LA MISMA idea que la primera, escrita con
              otras palabras. Que compartan tema no alcanza: tienen que atacar el mismo problema
              con el mismo enfoque, al punto de que trabajarlas por separado sea trabajo repetido.
              Para cada coincidencia devolvés qué tanto son la misma idea, de 0 a 1, y en una
              frase qué comparten. Si ninguna lo es, devolvés la lista vacía.
            TXT
            { role: "user", content: <<~TXT }
              Desafío: #{challenge.name}

              Idea a comparar:
              #{describe(idea)}

              Ideas existentes:
              #{candidates.map { |other| "[#{other.id}] (#{I18n.t("flow.idea_statuses.#{other.status}")})\n#{describe(other)}" }.join("\n\n")}
            TXT
          ]
        end

        def schema
          {
            "type" => "object",
            "required" => ["matches"],
            "properties" => {
              "matches" => {
                "type" => "array",
                "items" => {
                  "type" => "object",
                  "required" => %w[idea_id similarity title],
                  "properties" => {
                    # Enum con los ids reales: el modelo no puede inventar una
                    # idea que no existe ni señalar una de otro desafío.
                    "idea_id" => { "type" => "string", "enum" => candidates.map(&:id) },
                    "title" => { "type" => "string" },
                    "similarity" => { "type" => "number" },
                    # Solo el camino del modelo lo produce; el de embeddings no
                    # tiene con qué explicarse.
                    "reason" => { "type" => "string" }
                  }
                }
              }
            }
          }
        end

        def target_attributes = { idea: idea }

        # Es puramente informativa: aceptarla no muta nada del dominio. La
        # decisión (fusionar, descartar, seguir) es de la persona.
        def apply!(payload, suggestion:) = [true, []]

        def preview(payload)
          matches = payload["matches"]
          return "sin coincidencias" if matches.blank?

          estados = candidates.index_by(&:id)

          matches.map do |m|
            otra = estados[m["idea_id"]]
            # El estado no lo devuelve el modelo: lo sabe la app, y es lo que
            # cambia qué hacer con la coincidencia. «Ya se propuso y no avanzó»
            # no se responde igual que «hay otra igual en carrera».
            estado = otra && !otra.active? ? " (#{I18n.t("flow.idea_statuses.#{otra.status}").downcase})" : ""
            texto = "#{(m['similarity'] * 100).round}% · #{m['title']}#{estado}"
            m["reason"].present? ? "#{texto} — #{m['reason']}" : texto
          end.join(" · ")
        end

        def context_snapshot
          { "candidates" => candidates.size, "compared_by" => Flow::AI.provider.embeddings? ? "embeddings" : "modelo" }
        end

        # Con embeddings la comparación es local: no hay nada que pedirle al
        # modelo. Sin ellos vale el camino de siempre (#complete), y así los
        # tokens de esa llamada quedan contados en el run como cualquier otra.
        # Y sin nada con qué comparar tampoco hay consulta que hacer: se
        # resuelve acá en vez de gastar una llamada preguntando por una lista
        # vacía.
        def local?(provider) = candidates.empty? || provider.embeddings?

        def run_locally(provider)
          return { "matches" => [] } if candidates.empty?

          vectors = provider.embed(texts: [text_of(idea)] + candidates.map { |o| text_of(o) })
          mine = vectors.first

          matches = candidates.each_with_index.filter_map do |other, index|
            similarity = cosine(mine, vectors[index + 1])
            next if similarity < THRESHOLD

            { "idea_id" => other.id, "title" => other.title, "similarity" => similarity.round(4) }
          end

          { "matches" => matches.sort_by { |m| -m["similarity"] }.first(5) }
        end

        private

        # TODAS las demás ideas del desafío, las más recientes primero.
        #
        # Los borradores entran porque avisar sirve sobre todo mientras se
        # escribe, que es cuando todavía se puede sumar a la otra en vez de
        # duplicarla. Y las eliminadas también: «esto ya se propuso y no
        # avanzó» es de las cosas más útiles que este chequeo puede decir. Por
        # eso cada coincidencia viaja con el estado de la idea con la que se
        # parece, y no se filtra por él.
        def candidates
          @candidates ||= challenge.ideas.where.not(id: idea.id)
                                   .includes(:current_version)
                                   .order(created_at: :desc)
                                   .limit(MAX_CANDIDATES).to_a
        end

        def describe(record)
          [record.title, record.payload.map { |k, v| "#{k}: #{v}" }.join("\n")].join("\n").truncate(600)
        end

        def text_of(record) = [record.title, record.payload.values.join(" ")].join(" ").to_s

        def cosine(a, b)
          return 0.0 if a.blank? || b.blank?

          dot = a.each_with_index.sum { |value, i| value * b[i].to_f }
          magnitude = Math.sqrt(a.sum { |v| v**2 }) * Math.sqrt(b.sum { |v| v**2 })
          magnitude.zero? ? 0.0 : dot / magnitude
        end
      end
    end
  end
end
