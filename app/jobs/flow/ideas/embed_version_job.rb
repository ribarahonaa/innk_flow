# frozen_string_literal: true

module Flow
  module Ideas
    # El vector de una versión se calcula fuera del request: llama a un
    # servicio externo y publicar una idea no puede depender de que responda.
    class EmbedVersionJob < ApplicationJob
      queue_as :flow_ai
      retry_on Flow::Errors::EmbeddingFailed, attempts: 3, wait: :polynomially_longer

      def perform(company_id, version_id)
        company = Flow::Tenant.bypass! { Company.find_by(id: company_id) }
        return if company.nil?

        Flow::Tenant.with(company) do
          version = IdeaVersion.find_by(id: version_id)
          Flow::Ideas::EmbedVersion.call(version)
        end
      end
    end
  end
end
