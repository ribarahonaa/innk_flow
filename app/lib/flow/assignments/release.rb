# frozen_string_literal: true

module Flow
  module Assignments
    # Suelta las asignaciones a evaluar de quien dejó de poder evaluar en esta
    # empresa: le sacaron la membresía, le cambiaron el rol a uno que no evalúa,
    # o dejó de acompañar el desafío del que colgaba su elegibilidad.
    #
    # No es sólo un nombre de más en la lista. `min_assessments_for` cuenta a
    # los ASIGNADOS para saber cuántas evaluaciones hacen falta, así que una
    # asignación fantasma —de alguien que ya no llega ni a la pantalla, porque
    # `AssessmentPolicy#create?` le pide llegar al desafío— sube ese mínimo sin
    # sumar a nadie que pueda escribirlas: el módulo queda esperando una
    # evaluación imposible.
    #
    # Dos reglas del repo que esto NO rompe, y son las mismas que ya tiene
    # `StepAssignmentsController#destroy`:
    #
    #   · quien ya evaluó no se desasigna — su nota está puesta y sigue
    #     contando, y sacarlo la dejaría sin quién la respalde;
    #   · con el módulo cerrado no se toca nada — cambiar quién evalúa
    #     reescribiría un resultado.
    #
    # Corre DESPUÉS de la baja o del cambio de rol, no antes: la elegibilidad
    # se pregunta contra el estado ya escrito. Y contra el tenant en contexto,
    # porque `StepAssignment` es `TenantScoped`: la misma persona puede seguir
    # evaluando en otra empresa.
    class Release
      def initialize(user_id)
        @user_id = user_id
      end

      def call
        return 0 if @user_id.blank?

        pasos = sueltas
        pasos.each { |step| recompute!(step) }
        pasos.size
      end

      private

      def sueltas
        StepAssignment.where(user_id: @user_id).includes(challenge_step: :challenge)
                      .filter_map do |asignacion|
          step = asignacion.challenge_step
          next unless releasable?(step)

          asignacion.destroy!
          step
        end
      end

      def releasable?(step)
        return false unless step.evaluation?
        return false if step.completed? || step.skipped?
        return false if StepAssignment.eligible?(step, @user_id)

        # Su nota ya está puesta: la asignación es lo que la respalda.
        !step.assessments.current.where(evaluator_id: @user_id).exists?
      end

      # Quiénes están asignados decide el mínimo de evaluaciones por idea, así
      # que el estado de cada entry se calculó con el fantasma adentro. Es la
      # misma razón por la que tocar un peso recalcula el módulo entero.
      def recompute!(step)
        handler = step.reload.handler
        step.step_entries.includes(:idea).each { |entry| handler.recompute_entry!(entry) }
      end
    end
  end
end
