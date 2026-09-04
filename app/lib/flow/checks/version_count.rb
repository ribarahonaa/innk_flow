# frozen_string_literal: true

module Flow
  module Checks
    # La idea fue actualizada al menos N veces. Con mínimo 2, exige que haya
    # evolucionado respecto de su versión original.
    class VersionCount < Base
      def call(idea)
        total = idea.versions.size
        return pass("#{total} versiones") if total >= minimum

        fail("#{total} de #{minimum}")
      end

      def description = "tiene al menos #{Flow::Texto.contar(minimum, "versión")}"

      def config_errors
        return ["el mínimo debe ser al menos 1"] if minimum < 1

        []
      end

      private

      def minimum = (config["minimum"] || 2).to_i
    end
  end
end
