# frozen_string_literal: true

module Flow
  module AI
    module Tasks
      # La IA responde los filtros de sí/no de una selección, para una idea.
      #
      # Un filtro sin responder deja a la idea en el limbo y el módulo no
      # cierra (`Selection#can_complete?`). Con la selección en «Solo IA» eso
      # era un callejón sin salida: el módulo prometía correr solo y se quedaba
      # esperando a una persona.
      #
      # Se responden todos los filtros de veredicto de una idea en UNA consulta
      # —son la misma lectura del mismo texto— y queda un `ai_run` por idea.
      class DecideVerdicts < Base
        def messages
          [
            { role: "system", content: <<~TXT.squish },
              Decidís si una idea cumple o no cada condición que te dan, para dejarla pasar a la
              etapa siguiente de un desafío de innovación. Cada condición se responde sí o no,
              con una justificación breve citando lo que la idea dice. Si la idea no trae la
              información necesaria para saberlo, la condición NO se cumple y lo explicás: no
              supongas lo que no está escrito.
            TXT
            { role: "user", content: <<~TXT }
              Desafío: #{challenge.name}
              Brief: #{challenge.brief}

              Idea: #{idea.title}
              #{idea.payload.map { |k, v| "#{k}: #{v}" }.join("\n")}

              Condiciones:
              #{gates_prompt}
            TXT
          ]
        end

        def schema
          {
            "type" => "object",
            "required" => %w[verdicts],
            "properties" => {
              "verdicts" => {
                "type" => "array",
                "minItems" => 1,
                "items" => {
                  "type" => "object",
                  "required" => %w[criterion_key passed reason],
                  "properties" => {
                    "criterion_key" => { "type" => "string" },
                    "passed" => { "type" => "boolean" },
                    "reason" => { "type" => "string" }
                  }
                }
              }
            }
          }
        end

        def target_attributes = { idea: idea }

        # A diferencia de una evaluación —que agrega una opinión más al
        # promedio— un veredicto ES la respuesta del filtro: decide si la idea
        # sigue o queda afuera. No se aplica por pedirlo; alguien lo acepta.
        def applies_on_request? = false

        # Un veredicto decide quién queda afuera del corte.
        def requires_active_step? = true

        def context_snapshot = { "criterion_keys" => pending_gates.map { _1["key"] } }

        def apply!(payload, suggestion:)
          handler = step.handler
          decidibles = pending_gates.map { _1["key"] }
          filas = payload["verdicts"].select { |v| decidibles.include?(v["criterion_key"]) }

          if filas.empty?
            devueltas = payload["verdicts"].map { _1["criterion_key"] }
            return [false, ["la IA no respondió ninguno de los filtros pendientes de este " \
                            "módulo (esperaba #{decidibles.join(', ')}; respondió #{devueltas.join(', ')})"]]
          end

          filas.each do |fila|
            handler.record_verdict!(
              idea: idea, criterion_key: fila["criterion_key"], passed: fila["passed"],
              note: fila["reason"], ai_run_id: suggestion.ai_run_id
            )
          end

          [true, []]
        end

        def preview(payload)
          payload["verdicts"].map do |v|
            "#{v['criterion_key']}: #{v['passed'] ? '✓' : '✗'} — #{v['reason'].to_s.truncate(90)}"
          end.join(" · ")
        end

        private

        # Los filtros que todavía no respondió una persona. La IA no pisa un
        # veredicto humano: quien lo puso ya miró la idea y decidió.
        def pending_gates
          humanos = SelectionVerdict.where(challenge_step_id: step.id, idea_id: idea.id,
                                           actor_type: "human").pluck(:criterion_key)

          step.handler.verdict_gates.reject { |gate| humanos.include?(gate["key"]) }
        end

        def gates_prompt
          pending_gates.map do |gate|
            "- #{gate['key']} (#{gate['name']}): #{gate['description'].presence || 'sin descripción'}"
          end.join("\n")
        end
      end
    end
  end
end
