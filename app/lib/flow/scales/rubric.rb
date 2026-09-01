# frozen_string_literal: true

module Flow
  module Scales
    # Rúbrica = escala de niveles con un descriptor que guía al evaluador
    # ("3 = impacto en un área", "5 = impacto en toda la empresa").
    #
    # Hereda de Letter a propósito: la matemática es idéntica, lo único que
    # agrega es prosa. Un motor menos que mantener.
    class Rubric < Letter
      DEFAULT_LEVELS = [
        { "key" => "1", "label" => "1", "value" => 1, "descriptor" => "Sin impacto medible" },
        { "key" => "3", "label" => "3", "value" => 3, "descriptor" => "Impacto en un área" },
        { "key" => "5", "label" => "5", "value" => 5, "descriptor" => "Impacto en toda la empresa" }
      ].freeze

      def options
        levels.map do |level|
          label = [level["label"] || level["key"], level["descriptor"]].compact.join(" · ")
          [label, level["key"]]
        end
      end

      def descriptors = levels.map { |l| [l["key"], l["descriptor"]] }.to_h
    end
  end
end
