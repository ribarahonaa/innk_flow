# frozen_string_literal: true

module Flow
  module Checks
    # La idea acompaña un archivo, opcionalmente en un campo puntual.
    class HasAttachment < Base
      def call(idea)
        version = idea.current_version
        return fail("sin versión") if version.nil?

        attachments = version.attachments
        attachments = attachments.select { |a| a.field_key == field_key } if field_key.present?

        return pass("#{attachments.size} adjuntos") if attachments.any?

        fail("sin adjunto")
      end

      def description
        return "adjuntó un archivo en «#{field_key}»" if field_key.present?

        "adjuntó al menos un archivo"
      end

      private

      def field_key = config["field_key"].to_s
    end
  end
end
