# frozen_string_literal: true

module Flow
  module AI
    module Tasks
      # Compara una idea contra las existentes del desafío.
      #
      # A diferencia del resto, esta tarea NO llama a #complete: usa #embed y
      # calcula similitud coseno localmente. Con el proveedor de fixtures los
      # embeddings son deterministas pero sin semántica real — el flujo se
      # ejercita entero, la utilidad requiere un proveedor de verdad.
      class DetectDuplicates < Base
        THRESHOLD = 0.82

        def messages
          [{ role: "system", content: "similitud por embeddings" },
           { role: "user", content: text_of(idea) }]
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
                    "idea_id" => { "type" => "string" },
                    "title" => { "type" => "string" },
                    "similarity" => { "type" => "number" }
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

          matches.map { |m| "#{(m['similarity'] * 100).round}% · #{m['title']}" }.join(" · ")
        end

        # Camino propio: no pasa por Provider#complete.
        def run_locally(provider)
          others = challenge.ideas.where.not(id: idea.id).includes(:current_version).to_a
          return { "matches" => [] } if others.empty?

          vectors = provider.embed(texts: [text_of(idea)] + others.map { |o| text_of(o) })
          mine = vectors.first

          matches = others.each_with_index.filter_map do |other, index|
            similarity = cosine(mine, vectors[index + 1])
            next if similarity < THRESHOLD

            { "idea_id" => other.id, "title" => other.title, "similarity" => similarity.round(4) }
          end

          { "matches" => matches.sort_by { |m| -m["similarity"] }.first(5) }
        end

        private

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
