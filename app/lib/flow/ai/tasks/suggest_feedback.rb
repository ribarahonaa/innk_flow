# frozen_string_literal: true

module Flow
  module AI
    module Tasks
      # Feedback estructurado sobre una versión de la idea.
      class SuggestFeedback < Base
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

        def preview(payload)
          payload["items"].map { |i| "#{i['kind']}: #{i['body'].to_s.truncate(80)}" }.join(" · ")
        end
      end
    end
  end
end
