# frozen_string_literal: true

module Flow
  module AI
    # Una llamada al proveedor = un job. Nunca fan-out dentro del request.
    #
    # Idempotente por `ai_runs.idempotency_key`: un retry no duplica la llamada
    # ni las sugerencias.
    class RunJob < ApplicationJob
      queue_as :flow_ai
      retry_on Flow::Errors::Error, attempts: 3, wait: :polynomially_longer

      def perform(company_id, purpose, context_ids = {}, mode: nil, requested_by_id: nil)
        company = Flow::Tenant.bypass! { Company.find_by(id: company_id) }
        return if company.nil?

        Flow::Tenant.with(company) do
          context = resolve_context(context_ids)
          return if context[:challenge].nil? && context[:step].nil? && context[:idea].nil?

          task = Flow::AI::Tasks::Base.for(purpose, **context)
          Flow::AI::Runner.call(
            task,
            mode: mode || effective_mode(context),
            requested_by: requested_by_id && User.find_by(id: requested_by_id),
            challenge: context[:challenge], step: context[:step], idea: context[:idea]
          )
        end
      end

      private

      def resolve_context(ids)
        step = ids["step_id"] && ChallengeStep.find_by(id: ids["step_id"])
        idea = ids["idea_id"] && Idea.find_by(id: ids["idea_id"])
        challenge = ids["challenge_id"] && Challenge.find_by(id: ids["challenge_id"])
        field = ids["field_key"] && step&.form_fields&.find_by(key: ids["field_key"])

        { challenge: challenge || step&.challenge || idea&.challenge,
          step: step, idea: idea, field: field,
          count: ids["count"], pass: ids["pass"] }.compact
      end

      def effective_mode(context)
        context[:step]&.effective_ai_mode || context[:challenge]&.ai_default_mode || "ai_assisted"
      end
    end
  end
end
