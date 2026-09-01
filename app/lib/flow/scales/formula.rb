# frozen_string_literal: true

module Flow
  module Scales
    # Criterio DERIVADO: no lo completa el evaluador, se calcula a partir de
    # los otros criterios del mismo set.
    #
    # Sirve para modelos tipo ICE/RICE: `(impacto * confianza) / esfuerzo`.
    class Formula < Base
      def derived? = true

      # No se tipea: siempre llega calculado.
      def numeric(raw) = raw.blank? ? nil : raw.to_d

      def normalize(value)
        span = max - min
        return 0.to_d if span.zero?

        (value - min) / span
      end

      def config_errors
        errors = Flow::Formula::Validator.new(criterion).errors
        errors << "el máximo de salida debe ser mayor que el mínimo" if max <= min
        errors
      end

      # Calcula con los valores de los criterios hermanos.
      def compute(bindings)
        Flow::Formula::Calculator.new(expression).evaluate(bindings)
      end

      def expression = config["expression"].to_s
      def min = (config.dig("output", "min") || 0).to_d
      def max = (config.dig("output", "max") || 10).to_d
    end
  end
end
