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
        raise Flow::Errors::StepNotReady, reasons.join(". ") unless ready

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

      def skip!(reason: nil)
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
