# frozen_string_literal: true

module Flow
  module AI
    module Tasks
      # Propone la secuencia de módulos a partir del brief.
      class ProposePipeline < Base
        def messages
          [
            { role: "system", content: <<~TXT.squish },
              Sos un diseñador de procesos de innovación. Proponés un flujo de módulos
              para un desafío. Tipos disponibles: ideation (una sola vez, obligatorio),
              evolution, evaluation, selection, reporting. El flujo debe empezar por
              ideation y toda selection debe tener una evaluation antes.
            TXT
            { role: "user", content: "Desafío: #{challenge.name}\n\nBrief: #{challenge.brief}" }
          ]
        end

        def schema
          {
            "type" => "object",
            "required" => %w[steps rationale],
            "properties" => {
              "rationale" => { "type" => "string" },
              "steps" => {
                "type" => "array",
                "minItems" => 2,
                "items" => {
                  "type" => "object",
                  "required" => %w[kind name],
                  "properties" => {
                    "kind" => { "enum" => ChallengeStep::KINDS },
                    "name" => { "type" => "string" },
                    "ai_mode" => { "enum" => Challenge::AI_MODES + [nil] },
                    "config" => { "type" => "object" }
                  }
                }
              }
            }
          }
        end

        def target_attributes = { challenge: challenge }

        def apply!(payload, suggestion:)
          pipeline = challenge.pipeline
          # Solo sobre un desafío en borrador: aplicar una propuesta sobre un
          # flujo en curso violaría la regla del insertion floor.
          return [false, ["el flujo ya arrancó: la propuesta no se puede aplicar"]] unless challenge.draft?

          errors = []
          challenge.steps.destroy_all

          payload["steps"].each do |attributes|
            result = pipeline.insert(
              kind: attributes["kind"],
              after: :end,
              name: attributes["name"],
              ai_mode: attributes["ai_mode"].presence,
              config: attributes["config"] || {}
            )
            errors << result.error_sentence unless result.ok?
          end

          [errors.empty?, errors]
        end

        def preview(payload)
          payload["steps"].map { |s| s["name"] }.join(" → ")
        end
      end
    end
  end
end
