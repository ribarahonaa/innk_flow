# frozen_string_literal: true

module Flow
  module AI
    module Tasks
      # Genera ideas candidatas desde el brief. Entran al pipeline como
      # cualquier otra, marcadas origin: "ai".
      class GenerateIdeas < Base
        DEFAULT_COUNT = 5

        def messages
          [
            { role: "system", content: <<~TXT.squish },
              Generás ideas candidatas para un desafío de innovación. Cada idea responde
              los campos del formulario. Son concretas y accionables, no consignas
              genéricas. No repetís ideas ya existentes.
            TXT
            { role: "user", content: <<~TXT }
              Desafío: #{challenge.name}
              Brief: #{challenge.brief}
              Cantidad: #{count}
              Campos del formulario: #{field_keys.join(', ')}
              Ideas existentes: #{existing_titles.presence&.join(' | ') || '(ninguna)'}
            TXT
          ]
        end

        def schema
          {
            "type" => "object",
            "required" => ["ideas"],
            "properties" => {
              "ideas" => {
                "type" => "array",
                "minItems" => 1,
                "items" => {
                  "type" => "object",
                  "required" => %w[title payload],
                  "properties" => {
                    "title" => { "type" => "string" },
                    "payload" => { "type" => "object" }
                  }
                }
              }
            }
          }
        end

        def target_attributes = { challenge_step: step }

        def apply!(payload, suggestion:)
          keys = field_keys

          payload["ideas"].each do |attributes|
            idea = challenge.ideas.create!(
              author: suggestion.reviewed_by || suggestion.ai_run.requested_by || fallback_author,
              status: "draft",
              origin: "ai"
            )

            Flow::Ideas::PublishVersion.new(
              idea,
              payload: attributes["payload"].slice(*keys),
              actor_type: "ai",
              source_step: step,
              change_note: "Generada por IA",
              title: attributes["title"]
            ).call

            # Se postulan solas: si el dueño no las quiere, las descarta desde
            # la bandeja. Que naden en borrador invisible sería peor.
            idea.update!(submitted_at: Time.current)
          end

          [true, []]
        end

        def preview(payload)
          payload["ideas"].map { |i| i["title"] }.join(" · ")
        end

        def context_snapshot = { "count" => count }

        private

        def count = context.fetch(:count, DEFAULT_COUNT)
        def field_keys = step.form_fields.ordered.map(&:key)
        def existing_titles = challenge.ideas.includes(:current_version).map(&:title).first(20)
        def fallback_author = challenge.company.users.first
      end
    end
  end
end
