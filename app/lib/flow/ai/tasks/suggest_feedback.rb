# frozen_string_literal: true

module Flow
  module AI
    module Tasks
      # Feedback estructurado sobre una versión de la idea.
      class SuggestFeedback < Base
        def self.actua_sobre = :feedback

        def messages
          [
            { role: "system", content: <<~TXT.squish },
              Das feedback constructivo sobre una idea postulada a un desafío. Señalás
              lo que falta o está flojo, sin reescribir la idea por su autor. Cada punto
              es accionable. Tipos: suggestion (mejora), question (falta información),
              issue (problema que la haría inviable).
            TXT
            { role: "user", content: <<~TXT }
              Desafío: #{challenge.name}
              Brief: #{challenge.brief}
              Idea: #{idea.title}
              Contenido: #{idea.payload.map { |k, v| "#{k}: #{v}" }.join(' | ')}
            TXT
          ]
        end

        def schema
          {
            "type" => "object",
            "required" => ["items"],
            "properties" => {
              "items" => {
                "type" => "array",
                "minItems" => 1,
                "items" => {
                  "type" => "object",
                  "required" => %w[kind body],
                  "properties" => {
                    "kind" => { "enum" => FeedbackItem::KINDS },
                    "body" => { "type" => "string" }
                  }
                }
              }
            }
          }
        end

        def target_attributes = { idea: idea }

        def apply!(payload, suggestion:)
          payload["items"].each do |item|
            FeedbackItem.create!(
              challenge_step: step, idea: idea,
              idea_version_id: idea.current_version_id,
              actor_type: "ai", kind: item["kind"], body: item["body"],
              ai_run_id: suggestion.ai_run_id
            )
          end
          [true, []]
        end

        # El tipo traducido y el texto entero de cada comentario: la lista
        # cruda («question: … · suggestion: …») era un volcado del payload, no
        # algo que alguien pudiera leer para decidir si lo aplica.
        def preview(payload)
          payload["items"].map do |item|
            tipo = I18n.t("flow.feedback_kinds.#{item['kind']}", default: item["kind"].to_s.humanize)
            "#{tipo}: #{item['body'].to_s.truncate(140)}"
          end.join("\n")
        end
      end
    end
  end
end
