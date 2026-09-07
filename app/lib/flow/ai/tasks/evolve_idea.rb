# frozen_string_literal: true

module Flow
  module AI
    module Tasks
      # La IA reescribe una idea atendiendo el feedback que recibió.
      #
      # Es lo que faltaba del otro lado del módulo de evolución: la IA sabía
      # PROPONER feedback (`suggest_feedback`) y no sabía ayudar a responderlo.
      # Quien postula veía tres comentarios y la única
      # salida era reescribir la idea a mano.
      #
      # No es `coauthor_field`, que mejora un campo suelto sin saber que hay
      # feedback: acá el material de trabajo son los comentarios abiertos, y la
      # respuesta es una versión nueva de la idea entera.
      class EvolveIdea < Base
        def self.actua_sobre = :idea

        def messages
          [
            { role: "system", content: <<~TXT.squish },
              Reescribís una idea postulada a un desafío de innovación atendiendo los
              comentarios que recibió. Mantenés lo que ya estaba bien y cambiás lo que el
              feedback pide: si piden un dato que la idea no tiene, lo decís explícitamente en
              vez de inventarlo. No cambias de idea: la mejorás. Devolvés TODOS los campos, y
              una nota breve en primera persona que diga qué cambiaste y por qué.
            TXT
            { role: "user", content: <<~TXT }
              Desafío: #{challenge.name}
              Brief: #{challenge.brief}

              La idea, como está hoy:
              #{campos_actuales}

              Comentarios sin atender:
              #{comentarios}
            TXT
          ]
        end

        def schema
          {
            "type" => "object",
            "required" => campos.map(&:key) + ["change_note"],
            "properties" => campos.to_h { |f| [f.key, { "type" => "string" }] }
                                  .merge("change_note" => { "type" => "string" })
          }
        end

        def target_attributes = { idea: idea }

        # Publicar una versión de la idea de otra persona no es aditivo: es su
        # idea. Se propone y su autor acepta.
        def applies_on_request? = false

        def context_snapshot
          { "feedback_ids" => abiertos.map(&:id), "campos" => campos.map(&:key) }
        end

        def apply!(payload, suggestion:)
          nuevo = campos.to_h { |f| [f.key, payload[f.key].to_s] }
          return [false, ["la IA no devolvió ningún campo del formulario"]] if nuevo.values.all?(&:blank?)

          result = Flow::Ideas::PublishVersion.new(
            idea, payload: idea.payload.merge(nuevo),
            author: suggestion.reviewed_by || idea.author, actor_type: "ai",
            source_step: step, change_note: payload["change_note"].presence || "Reescrita con IA"
          ).call
          return [false, result.errors] unless result.ok?

          # Publicar una versión responde el feedback abierto del módulo: es el
          # mismo camino que cuando la persona lo reescribe a mano.
          step.handler.record_response!(idea, result.version) if step&.evolution?

          [true, []]
        end

        def preview(payload)
          nota = payload["change_note"].to_s
          cambios = campos.filter_map do |f|
            "#{f.label}: #{payload[f.key].to_s.truncate(110)}" if payload[f.key].present?
          end

          ([nota.presence] + cambios).compact.join("\n")
        end

        private

        # Los campos que se pueden reescribir. Un adjunto no se reescribe con
        # texto, así que queda afuera y se arrastra solo al publicar.
        def campos
          @campos ||= challenge.pipeline.ideation_step&.form_fields&.ordered&.reject { |f| f.field_type == "file" } || []
        end

        # Lo que está sin atender EN ESTA RONDA.
        #
        # Sin atender, porque un comentario ya cerrado no es una instrucción
        # pendiente y volver a pedirlo reescribiría de más. Y de esta ronda,
        # porque cada comentario pertenece a su módulo: arrastrar lo que quedó
        # abierto en una ronda anterior mezcla dos conversaciones distintas.
        def abiertos
          @abiertos ||= FeedbackItem.where(idea_id: idea.id, challenge_step_id: step&.id, resolution: nil)
                                    .chronological.includes(:author).to_a
        end

        def campos_actuales
          campos.map { |f| "#{f.label} (#{f.key}): #{idea.payload[f.key]}" }.join("\n")
        end

        def comentarios
          return "No hay comentarios sin atender." if abiertos.empty?

          abiertos.map { |i| "- [#{I18n.t("flow.feedback_kinds.#{i.kind}")}] #{i.body}" }.join("\n")
        end
      end
    end
  end
end
