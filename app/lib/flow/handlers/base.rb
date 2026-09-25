# frozen_string_literal: true

module Flow
  module Handlers
    # Un handler por tipo de módulo. Toda la lógica específica de un `kind`
    # vive en su handler; el Pipeline solo orquesta el orden.
    #
    # `activate!` y `complete!` son IDEMPOTENTES: el job que los invoca puede
    # reintentar, y la repesca vuelve a llamar a Cohort.sync! sobre un step ya
    # activo.
    class Base
      Progress = Data.define(:done, :total, :label) do
        def pct = total.to_i.zero? ? 0 : ((done.to_f / total) * 100).round
        def complete? = total.to_i.positive? && done >= total
      end

      def self.for(step)
        raise ArgumentError, "step nulo" if step.nil?

        const_get("Flow::Handlers::#{step.kind.camelize}").new(step)
      end

      def initialize(step)
        @step = step
      end

      attr_reader :step

      delegate :challenge, :settings, :effective_ai_mode, to: :step

      # ── Contrato ───────────────────────────────────────────────────────────

      # ¿Están dadas las precondiciones para arrancar este módulo?
      # => [bool, [razones]]
      def can_activate? = [true, []]

      def activate!
        return step if step.touched?

        ready, reasons = can_activate?
        # EL NOMBRE DEL MÓDULO LO PONE ACÁ, no cada handler. Éste es el único
        # lugar donde una negativa se vuelve excepción, así que un handler nuevo
        # que se niegue no puede olvidarse —que es lo que pasó con `Evaluation`,
        # cuyos motivos salen de `CriteriaSet#validation_errors` y no saben de
        # módulos: con dos evaluaciones en el flujo, el aviso no decía cuál—.
        # Sus razones dicen el PORQUÉ; el «cuál» es de quien avisa.
        #
        # Y va en el MENSAJE y no en un atributo de la excepción:
        # `Flow::Steps::ActivateJob` la deja escapar a propósito, y en el log de
        # un job nadie arma una frase mejor.
        raise Flow::Errors::StepNotReady, "«#{step.name}» no está listo para arrancar: #{reasons.join('. ')}" unless ready

        step.transaction do
          resolve_config!
          step.update!(status: "active", started_at: Time.current)
          sync_cohort!
          on_activate
        end
        step
      end

      # => Progress, para la barra de la UI
      def progress = Progress.new(done: 0, total: 0, label: nil)

      # => [bool, [razones legibles]]
      def can_complete? = [true, []]

      def complete!
        return step if step.completed?

        step.transaction do
          on_complete
          step.update!(status: "completed", completed_at: Time.current)
        end
        step
      end

      # Saltear un módulo que TODAVÍA no terminó. Uno completado o ya salteado
      # no se reescribe: pisarle el `status` le hacía decir que nunca corrió
      # —con sus evaluaciones y sus entries intactas debajo— y encima le movía
      # el `completed_at` y el motivo.
      #
      # Lo alcanza la ruta: `ChallengeStepPolicy#skip?` es
      # `administers?(challenge)` y no mira el estado del módulo.
      #
      # Devuelve `false` cuando se niega, y ésa es la ÚNICA copia de la regla:
      # el controller lee la respuesta en vez de repetir el predicado, que es
      # como las dos se desincronizarían.
      #
      # Ojo con el contrato, que NO es el de sus hermanos: `activate!` y
      # `complete!` devuelven el step también cuando no hacen nada, porque ahí
      # la repetición es idempotencia —pedir de nuevo lo mismo—. Sobre un
      # módulo completado saltear no es repetir, es otra operación, y por eso
      # se contesta que no. Sobre uno ya salteado sí es el caso idempotente
      # puro y aun así devuelve `false`, para que el mensaje sea uno solo. Un
      # `paso = handler.skip!` futuro revienta con NoMethodError sobre `false`;
      # los tres llamadores de hoy leen la respuesta o la ignoran a sabiendas.
      def skip!(reason: nil)
        return false if step.completed? || step.skipped?

        step.transaction do
          merged = (step.resolved_config || step.config || {}).merge("skip_reason" => reason)
          step.update!(status: "skipped", resolved_config: merged, completed_at: Time.current)
        end
        step
      end

      # Props que la vista pasa a la isla Vue del módulo.
      def view_model = { kind: step.kind, slug: step.slug, settings: settings }

      protected

      # Late binding: congela la intención del autor en ids concretos, UNA sola
      # vez. Después de esto, reordenar el pipeline no puede cambiar de dónde
      # sale el insumo de este módulo.
      def resolve_config!
        step.resolved_config = (step.config || {}).deep_dup
      end

      # Materializa la participación del cohorte vivo. Los step_entries llegan
      # en Fase 4 (junto con Idea); hasta entonces es un no-op.
      def sync_cohort!
        Flow::Cohort.sync!(step)
      end

      def on_activate; end
      def on_complete; end
    end
  end
end
