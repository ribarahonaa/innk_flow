# frozen_string_literal: true

module Flow
  module AI
    module Tasks
      # Genera ideas candidatas desde el brief. Entran al pipeline como
      # cualquier otra, marcadas origin: "ai".
      class GenerateIdeas < Base
        DEFAULT_COUNT = 3

        # Un tope duro: cada idea son cientos de tokens de salida, y pedir
        # veinte de una es una factura sorpresa. Quien quiera más, pide de
        # nuevo.
        MAX_COUNT = 5

        def messages
          [
            { role: "system", content: <<~TXT.squish },
              Generás ideas candidatas para un desafío de innovación, respondiendo el
              formulario de postulación tal como lo haría una persona que trabaja en esa
              empresa. Cada idea ataca el problema concreto del brief: si el brief habla
              de merma en bodega, no proponés algo que serviría para cualquier empresa.
              Son accionables —se entiende quién hace qué— y distintas entre sí, no
              variaciones de la misma. Respondés TODOS los campos del formulario, cada
              uno con lo que esa pregunta pide.
            TXT
            { role: "user", content: <<~TXT }
              Desafío: #{challenge.name}

              Brief: #{challenge.brief}

              Generá #{count} ideas.

              El formulario que tenés que responder:
              #{field_briefing}

              Ideas que ya existen (no las repitas):
              #{existing_titles.presence&.join(' | ') || '(ninguna)'}
            TXT
          ]
        end

        # Las CLAVES no son las preguntas. Mandar `titulo, problema, solucion` deja al
        # modelo adivinando qué se espera en cada una; mandar la etiqueta, el tipo y la
        # ayuda es mandarle el formulario que ve una persona.
        def field_briefing
          answerable_fields.map do |field|
            line = +"- #{field.key}: «#{field.label}»"
            line << " (#{I18n.t("flow.field_types.#{field.field_type}").downcase})"
            line << " — #{field.hint}" if field.hint.present?
            line << " Opciones: #{field.options.join(', ')}." if field.options.any?
            line << " Obligatorio." if field.required
            line
          end.join("\n")
        end

        # El schema nombra los campos REALES del formulario.
        #
        # Antes `payload` era un objeto libre: cualquier cosa validaba, y el `slice`
        # de abajo se quedaba con la intersección — que podía ser vacía. La idea se
        # creaba igual, sin una sola respuesta, y se auto-postulaba. Nombrar las
        # claves es lo que hace que la salida estructurada las garantice.
        def schema
          {
            "type" => "object",
            "required" => ["ideas"],
            "properties" => {
              "ideas" => {
                "type" => "array",
                "minItems" => 1,
                "maxItems" => MAX_COUNT,
                "items" => {
                  "type" => "object",
                  "required" => ["payload"],
                  "properties" => {
                    "title" => { "type" => "string" },
                    "payload" => payload_schema
                  }
                }
              }
            }
          }
        end

        def payload_schema
          {
            "type" => "object",
            # TODOS los campos, no solo los obligatorios del formulario: una
            # persona puede dejar uno en blanco, pero una idea generada que
            # deja campos vacíos es media idea.
            "required" => answerable_fields.map(&:key),
            "properties" => answerable_fields.to_h { |field| [field.key, property_for(field)] }
          }
        end

        def property_for(field)
          case field.field_type
          when "number" then { "type" => "number" }
          when "select" then { "type" => "string", "enum" => field.options }
          when "multi_select" then { "type" => "array", "items" => { "type" => "string", "enum" => field.options } }
          else { "type" => "string" }
          end
        end

        def target_attributes = { challenge_step: step }

        # Crea ideas y las postula. `Flow::Cohort.sync!` arma las
        # `step_entries` al ACTIVAR el módulo, así que una idea que entre
        # después de que cerró no tiene fila en ningún lado.
        def requires_active_step? = true

        def apply!(payload, suggestion:)
          keys = answerable_fields.map(&:key)
          obligatorios = answerable_fields.select(&:required).map(&:key)
          creadas = 0
          errores = []

          # El pedido de cantidad es una instrucción del prompt, y el modelo puede
          # devolver de más. Se respeta lo que pidió el dueño: si pidió 3, entran 3.
          payload["ideas"].first(count).each_with_index do |attributes, index|
            respuestas = attributes["payload"].to_h.slice(*keys).reject { |_, v| v.blank? }
            faltan = obligatorios - respuestas.keys

            # Una idea sin las respuestas obligatorias no se crea. Antes se creaba
            # vacía y se postulaba sola: quedaba en la bandeja como una idea real,
            # sin contenido, y nadie se enteraba de por qué.
            if faltan.any?
              errores << "la idea #{index + 1} no respondió #{faltan.join(', ')}"
              next
            end

            idea = challenge.ideas.create!(
              author: suggestion.reviewed_by || suggestion.ai_run.requested_by || fallback_author,
              status: "draft",
              origin: "ai"
            )

            Flow::Ideas::PublishVersion.new(
              idea, payload: respuestas, actor_type: "ai", source_step: step,
              change_note: "Generada por IA"
            ).call

            # Se postulan solas: si el dueño no las quiere, las descarta desde
            # la bandeja. Que naden en borrador invisible sería peor.
            idea.update!(submitted_at: Time.current)
            creadas += 1
          end

          return [false, errores] if creadas.zero?

          [true, errores]
        end

        def preview(payload)
          payload["ideas"].map { |i| i["title"] }.join(" · ")
        end

        def context_snapshot = { "count" => count }

        private

        def count = context.fetch(:count, DEFAULT_COUNT).to_i.clamp(1, MAX_COUNT)

        # Un adjunto no se puede generar: pedirlo es pedir algo imposible y
        # ensuciar el resto de la respuesta.
        def answerable_fields = step.form_fields.ordered.reject { |f| f.field_type == "file" }
        def existing_titles = challenge.ideas.includes(:current_version).map(&:title).first(20)
        def fallback_author = challenge.company.users.first
      end
    end
  end
end
