# frozen_string_literal: true

module Flow
  module AI
    module Tasks
      # Propone la secuencia de módulos a partir del brief.
      class ProposePipeline < Base
        # Anotación corta solo para los tipos que un nombre de kind no explica
        # solo: `ideation` porque es el único con una restricción real (una
        # sola vez, obligatorio) y `testing` porque el modelo no tiene de dónde
        # más sacar qué hace. Los demás se listan tal cual.
        NOTAS_POR_KIND = {
          "ideation" => "una sola vez, obligatorio",
          "testing" => "prueba la idea contra situaciones concretas de ejecución y dictamina si es factible"
        }.freeze

        def messages
          [
            { role: "system", content: <<~TXT.squish },
              Sos un diseñador de procesos de innovación. Proponés un flujo de módulos
              para un desafío. Tipos disponibles: #{tipos_disponibles}. El flujo debe
              empezar por ideation y toda selection debe tener una evaluation antes.
              Cada paso puede traer un config con las claves que el schema declara
              para su tipo; lo que no pongas queda con el valor por defecto, así que
              incluí solo lo que el brief justifique cambiar.
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
                # Una variante por kind, para que el `config` de cada paso sea el
                # de SU kind. Declararlo `object` a secas no dejaba proponer
                # nada con el proveedor real: el adapter de Anthropic cierra
                # todo objeto con `additionalProperties: false`, y un objeto
                # cerrado sin propiedades no admite ninguna clave.
                "items" => { "anyOf" => ChallengeStep::KINDS.map { |kind| paso(kind) } }
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

          # El `config` pasa por el mismo filtro que el de `steps#update`. El
          # schema de arriba declara las claves de cada kind, pero sólo el
          # pedido a Anthropic cierra los objetos: el schema local deja pasar
          # claves de más, y una sugerencia editada a mano
          # (`ApplySuggestion` con `payload:`) no se valida contra ninguno.
          payload["steps"].each do |attributes|
            result = pipeline.insert(
              kind: attributes["kind"],
              after: :end,
              name: attributes["name"],
              ai_mode: attributes["ai_mode"].presence,
              config: Flow::StepSettings.filtrar(attributes["kind"], attributes["config"])
            )
            errors << result.error_sentence unless result.ok?
          end

          [errors.empty?, errors]
        end

        def preview(payload)
          payload["steps"].map { |s| s["name"] }.join(" → ")
        end

        private

        # Deriva la lista de `ChallengeStep::KINDS` en vez de escribirla a
        # mano: un kind nuevo sin nota entra igual, con su nombre pelado, y no
        # hace falta acordarse de tocar este prompt.
        def tipos_disponibles
          ChallengeStep::KINDS.map { |kind| NOTAS_POR_KIND[kind] ? "#{kind} (#{NOTAS_POR_KIND[kind]})" : kind }.join(", ")
        end

        def paso(kind)
          {
            "type" => "object",
            "required" => %w[kind name],
            "properties" => {
              "kind" => { "const" => kind },
              "name" => { "type" => "string" },
              "ai_mode" => { "enum" => Challenge::AI_MODES + [nil] },
              "config" => Flow::StepSettings.json_schema(kind)
            }
          }
        end
      end
    end
  end
end
