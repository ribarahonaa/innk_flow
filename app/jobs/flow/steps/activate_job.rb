# frozen_string_literal: true

module Flow
  module Steps
    # Activación de un módulo: materializa el cohorte y dispara los efectos
    # del handler.
    #
    # HOY NO LO ENCOLA NADIE. `Pipeline` activa en línea —`start!` y
    # `open_next_or_close!` llaman a `Handlers::Base#activate!` directo—, así
    # que esta clase respeta el contrato del handler y espera a que alguien la
    # use. Está pensada para Sidekiq porque activar es O(cantidad de ideas) y
    # puede encolar una llamada a la IA por idea, pero eso es la razón por la
    # que existe, no algo que esté pasando.
    #
    # El tenant viaja en el payload y se abre a mano: un job no tiene request
    # que haya establecido Current.company.
    class ActivateJob < ApplicationJob
      queue_as :flow_steps

      def perform(company_id, step_id)
        company = Flow::Tenant.bypass! { Company.find_by(id: company_id) }
        return if company.nil?

        Flow::Tenant.with(company) do
          step = ChallengeStep.find_by(id: step_id)
          return if step.nil? || step.completed? || step.skipped?

          Flow::Handlers::Base.for(step).activate!
        end
      end
    end
  end
end
