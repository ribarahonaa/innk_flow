# frozen_string_literal: true

module Flow
  module AI
    module Tasks
      # Propone los campos del formulario de postulación según el brief.
      class SuggestFormFields < Base
        def messages
          [
            { role: "system", content: <<~TXT.squish },
              Proponés los campos del formulario con el que la gente postula ideas a un
              desafío. Entre 3 y 7 campos. Tipos: text, textarea, number, date, select,
              multi_select. Exactamente uno lleva is_title true.
            TXT
            { role: "user", content: "Desafío: #{challenge.name}\n\nBrief: #{challenge.brief}" }
          ]
        end

        def schema
          {
            "type" => "object",
            "required" => ["fields"],
            "properties" => {
              "fields" => {
                "type" => "array",
                "minItems" => 2,
                "maxItems" => 10,
                "items" => {
                  "type" => "object",
                  "required" => %w[key label field_type],
                  "properties" => {
                    "key" => { "type" => "string", "pattern" => "^[a-z][a-z0-9_]*$" },
                    "label" => { "type" => "string" },
                    "hint" => { "type" => "string" },
                    "field_type" => { "enum" => FormField::TYPES },
                    "required" => { "type" => "boolean" },
                    "is_title" => { "type" => "boolean" },
                    "options" => { "type" => "array", "items" => { "type" => "string" } }
                  }
                }
              }
            }
          }
        end

        def target_attributes = { challenge_step: step }

        def apply!(payload, suggestion:)
          # Reemplaza el formulario, no lo mezcla: si ya hay respuestas, el
          # módulo está activo y el formulario no se toca.
          return [false, ["ya hay ideas postuladas: el formulario no se cambia"]] if ideas_submitted?

          step.form_fields.destroy_all
          payload["fields"].each_with_index do |field, index|
            step.form_fields.create!(
              key: field["key"],
              label: field["label"],
              hint: field["hint"],
              field_type: field["field_type"],
              required: field.fetch("required", false),
              position: index,
              config: { "is_title" => field["is_title"] == true, "options" => field["options"] }.compact
            )
          end
          [true, []]
        end

        def preview(payload)
          payload["fields"].map { |f| f["label"] }.join(" · ")
        end

        private

        def ideas_submitted? = step.challenge.ideas.submitted.exists?
      end
    end
  end
end
