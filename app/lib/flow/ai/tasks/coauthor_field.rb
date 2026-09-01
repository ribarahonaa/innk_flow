# frozen_string_literal: true

module Flow
  module AI
    module Tasks
      # Copiloto de redacción: sugiere cómo mejorar un campo puntual.
      #
      # No escribe sobre la idea: produce texto que la persona acepta, edita o
      # descarta. Aceptar publica una versión nueva, como cualquier edición.
      class CoauthorField < Base
        def messages
          [
            { role: "system", content: <<~TXT.squish },
              Ayudás a alguien a redactar su postulación a un desafío. Mejorás el campo
              indicado sin inventar datos que la persona no dio. Si el campo está vacío,
              proponés un borrador a partir del resto de la idea.
            TXT
            { role: "user", content: <<~TXT }
              Desafío: #{challenge.name}
              Brief: #{challenge.brief}
              Campo a trabajar: #{field.label} (#{field.key})
              Contenido actual: #{current_value.presence || '(vacío)'}
              Resto de la idea: #{other_answers}
            TXT
          ]
        end

        def schema
          {
            "type" => "object",
            "required" => %w[suggestion reason],
            "properties" => {
              "suggestion" => { "type" => "string" },
              "reason" => { "type" => "string" }
            }
          }
        end

        def target_attributes = { idea: idea }

        def apply!(payload, suggestion:)
          merged = idea.payload.merge(field.key => payload["suggestion"])

          result = Flow::Ideas::PublishVersion.new(
            idea,
            payload: merged,
            author: suggestion.reviewed_by,
            actor_type: suggestion.reviewed_by ? "human" : "ai",
            source_step: step,
            change_note: "Sugerencia de IA aplicada a «#{field.label}»"
          ).call

          [result.ok?, result.errors]
        end

        def preview(payload) = payload["suggestion"].to_s.truncate(200)

        def context_snapshot = { "field_key" => field.key }

        private

        def field = context.fetch(:field)
        def current_value = idea.payload[field.key]

        def other_answers
          idea.payload.except(field.key).map { |k, v| "#{k}: #{v}" }.join(" | ").truncate(600)
        end
      end
    end
  end
end
