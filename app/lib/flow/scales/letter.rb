# frozen_string_literal: true

module Flow
  module Scales
    # Escala cualitativa: A-F, Alto/Medio/Bajo, lo que el dueño defina.
    # Cada nivel lleva su valor numérico, y de ahí sale la normalización.
    class Letter < Base
      DEFAULT_LEVELS = [
        { "key" => "A", "label" => "A", "value" => 4 },
        { "key" => "B", "label" => "B", "value" => 3 },
        { "key" => "C", "label" => "C", "value" => 2 },
        { "key" => "D", "label" => "D", "value" => 1 },
        { "key" => "F", "label" => "F", "value" => 0 }
      ].freeze

      def numeric(raw)
        return nil if raw.blank?

        level = levels.find { |l| l["key"].to_s == raw.to_s }
        level && level["value"].to_d
      end

      def normalize(value)
        top = max_value
        top.zero? ? 0.to_d : value / top
      end

      def options
        levels.map { |l| [l["label"] || l["key"], l["key"]] }
      end

      def config_errors
        return ["la escala necesita al menos dos niveles"] if levels.size < 2
        return ["los niveles necesitan un valor numérico"] if levels.any? { |l| l["value"].nil? }

        []
      end

      def levels
        list = config["levels"]
        list.presence || DEFAULT_LEVELS
      end

      def max_value = levels.map { |l| l["value"].to_d }.max || 0.to_d
    end
  end
end
