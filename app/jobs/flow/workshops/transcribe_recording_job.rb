# frozen_string_literal: true

module Flow
  module Workshops
    # Transcribir llama a un servicio externo y parar una grabación no puede
    # depender de que responda. Calcado de `EmbedVersionJob`, incluido el
    # `bypass!` para encontrar la empresa antes de entrar a su tenant.
    class TranscribeRecordingJob < ApplicationJob
      queue_as :flow_ai
      retry_on Flow::Errors::TranscriptionFailed, attempts: 3, wait: :polynomially_longer

      def perform(company_id, recording_id)
        company = Flow::Tenant.bypass! { Company.find_by(id: company_id) }
        return if company.nil?

        Flow::Tenant.with(company) do
          recording = WorkshopRecording.find_by(id: recording_id)
          next if recording.nil?

          Flow::Workshops::TranscribeRecording.call(recording)
        end
      end
    end
  end
end
