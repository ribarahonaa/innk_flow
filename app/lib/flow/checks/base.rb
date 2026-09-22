# frozen_string_literal: true

module Flow
  module Checks
    # Un criterio AUTOMÁTICO: lo verifica el sistema sobre la idea, sin que
    # nadie lo puntúe.
    #
    # Devuelve verdadero o falso, que se normaliza a 1.0 / 0.0 — así un
    # criterio automático puede sumar puntaje en una evaluación con el mismo
    # peso que uno manual, y actuar como filtro en una selección.
    class Base
      TYPES = %w[field_present contributors_count version_count feedback_addressed
                 has_attachment testing_passed].freeze

      Result = Data.define(:passed, :detail) do
        def passed? = passed
      end

      def self.for(criterion)
        type = criterion.source_config.to_h["check"].to_s
        klass = "Flow::Checks::#{type.camelize}".safe_constantize
        raise Flow::Errors::UnknownCheck, "verificación desconocida: #{type.presence || '(vacía)'}" if klass.nil?

        klass.new(criterion)
      end

      def self.label(type) = I18n.t("flow.checks.#{type}.label", default: type.humanize)

      def initialize(criterion)
        @criterion = criterion
      end

      attr_reader :criterion

      def config = criterion.source_config.to_h

      # => Result
      def call(idea) = raise NotImplementedError

      # Texto legible de lo que verifica, para la UI.
      def description = raise NotImplementedError

      # Errores de configuración, para validar el criterio.
      def config_errors = []

      protected

      def pass(detail = nil) = Result.new(passed: true, detail: detail)
      def fail(detail = nil) = Result.new(passed: false, detail: detail)
    end
  end
end
