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
    # **Son dos pasos y se llaman por separado a propósito.**
    #
    # `unassign!` va DENTRO de la transacción de quien lo llama, junto con la
    # escritura que dejó huérfanas a las asignaciones. Si se separan, una falla
    # en el medio deja la membresía borrada y las asignaciones a medio soltar
    # —y ahí **no queda ningún camino de UI para volver a disparar esto**,
    # justamente porque la membresía ya no existe—. Juntas, o la baja no pasó y
    # se vuelve a apretar.
    #
    # `recompute!` va AFUERA. Es aritmética derivada y recuperable: si falla,
    # las entries muestran el número calculado con el fantasma adentro, y el
    # siguiente cambio de peso, de asignación o de evaluación las recalcula.
    # Atarla a la transacción haría que una cuenta rota impidiera una baja.
    #
    # Contra el tenant en contexto, porque `StepAssignment` es `TenantScoped`:
    # la misma persona puede seguir evaluando en otra empresa.
    class Release
      def initialize(user_id)
        @user_id = user_id
        @steps = []
      end

      # Suelta lo que corresponda y se guarda los módulos tocados para el
      # recompute de después. Devuelve cuántos soltó.
      def unassign!
        @steps = @user_id.blank? ? [] : sueltas
        @steps.size
      end

      def recompute!
        @steps.each { |step| step.reload.handler.recompute_entries! }
        @steps.size
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
    end
  end
end
