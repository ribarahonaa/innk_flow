# frozen_string_literal: true

module Flow
  module Scales
    # Nota entre min y max. `direction: lower_better` invierte la escala —
    # sirve para criterios donde menos es mejor (costo, esfuerzo, riesgo).
    class Numeric < Base
      DEFAULT_MIN = 1
      DEFAULT_MAX = 10

      def numeric(raw)
        return nil if raw.blank?

        Float(raw).to_d
      rescue ArgumentError, TypeError
        nil
      end

      def normalize(value)
        span = max - min
        return 0.to_d if span.zero?

        ratio = (value - min) / span
        lower_better? ? 1 - ratio : ratio
      end

      def options = (min.to_i..max.to_i).step(step).to_a

      def config_errors
        errors = []
        errors << "el máximo debe ser mayor que el mínimo" if max <= min
        errors << "el paso debe ser positivo" unless step.positive?
        errors
      end

      def min = (config["min"] || DEFAULT_MIN).to_d
      def max = (config["max"] || DEFAULT_MAX).to_d
      def step = (config["step"] || 1).to_i
      def lower_better? = config["direction"].to_s == "lower_better"
    end
  end
end
