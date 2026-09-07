# frozen_string_literal: true

module Flow
  module AI
    module Tasks
      # Una tarea = un propósito. Define qué se le pide al modelo, con qué
      # contrato de salida, y cómo se aplica el resultado al dominio.
      #
      # La aplicación al dominio vive acá y no en el controller porque es la
      # misma para los tres modos: `ai_auto` la corre sola, `ai_assisted` la
      # corre cuando una persona acepta.
      class Base
        class << self
          def purpose = name.demodulize.underscore

          # Sobre QUÉ actúa la tarea. Es lo único que necesitan el controller
          # y la política para saber quién puede pedirla y quién puede aceptar
          # lo que proponga, sin que ninguno de los dos lleve su propia lista
          # de propósitos —que era como quedaban desincronizados—.
          #
          #   :challenge  configura el desafío         → quien administra
          #   :idea       trabaja sobre una idea       → quien puede editarla
          #   :feedback   comenta una idea             → quien puede comentarla
          #   :assessment evalúa una idea              → quien puede evaluarla
          def actua_sobre = :challenge

          def scope_of(purpose)
            klass = "Flow::AI::Tasks::#{purpose.to_s.camelize}".safe_constantize
            klass.respond_to?(:actua_sobre) ? klass.actua_sobre : :challenge
          end

          def for(purpose, **context)
            klass = "Flow::AI::Tasks::#{purpose.to_s.camelize}".safe_constantize
            raise ArgumentError, "propósito desconocido: #{purpose}" if klass.nil?

            klass.new(**context)
          end
        end

        def initialize(**context)
          @context = context
        end

        attr_reader :context

        def purpose = self.class.purpose

        # Mensajes al modelo. Sin estado: función pura del contexto, para que
        # el hash del prompt sea estable y el fixture reproducible.
        def messages = raise NotImplementedError

        # JSON Schema de la salida.
        def schema = raise NotImplementedError

        # Objetivo de la sugerencia: { challenge: } / { challenge_step: } / { idea: }
        def target_attributes = raise NotImplementedError

        # Aplica el payload al dominio. Se llama al aceptar.
        def apply!(payload, suggestion:) = raise NotImplementedError

        # Resumen legible de lo que propone, para la UI de revisión.
        def preview(payload) = payload.to_json.truncate(280)

        # Contexto que NO se deduce de los ids del run y que hace falta para
        # reconstruir la tarea al aceptar la sugerencia más tarde (qué campo se
        # estaba redactando, cuántas ideas se pidieron).
        #
        # Se persiste en ai_runs.prompt["context"]: sin esto, aceptar una
        # sugerencia en modo assisted falla porque la tarea se rearma sin sus
        # parámetros.
        def context_snapshot = {}

        # ¿Pedir esta tarea a mano equivale a aceptarla?
        #
        # Por defecto NO: en `ai_assisted` la IA propone y una persona decide.
        # La excepción son las tareas ADITIVAS —agregan una opinión sin tocar
        # lo que ya existe— donde apretar el botón ya es la decisión y pedir
        # una confirmación extra sería burocracia.
        def applies_on_request? = false

        # Dos pedidos idénticos no deben producir dos llamadas.
        def idempotency_key
          Digest::SHA256.hexdigest([purpose, JSON.generate(messages)].join(":"))[0, 32]
        end

        protected

        def challenge = context[:challenge]
        def step = context[:step]
        def idea = context[:idea]
      end
    end
  end
end
