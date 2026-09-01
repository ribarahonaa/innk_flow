# frozen_string_literal: true

module Flow
  module Scales
    # Sí / no. Es la forma de un veredicto —"¿es viable?", "¿tiene riesgo
    # legal?"— y también el resultado de un criterio automático.
    class Boolean < Base
      TRUTHY = %w[1 true sí si yes pass passed].freeze

      def numeric(raw)
        return nil if raw.nil? || raw.to_s.strip.empty?

        TRUTHY.include?(raw.to_s.strip.downcase) ? 1.to_d : 0.to_d
      end

      def normalize(value) = inverted? ? 1 - value : value

      def options
        [[config["true_label"].presence || "Sí", "1"],
         [config["false_label"].presence || "No", "0"]]
      end

      # `direction: lower_better` para criterios donde el "sí" es lo malo:
      # "¿tiene riesgo legal?".
      def inverted? = config["direction"].to_s == "lower_better"
    end
  end
end
