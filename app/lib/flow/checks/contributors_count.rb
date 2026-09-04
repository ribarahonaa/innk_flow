# frozen_string_literal: true

module Flow
  module Checks
    # La idea tiene al menos N personas involucradas, contando al autor.
    class ContributorsCount < Base
      def call(idea)
        total = idea.people_count
        return pass("#{total} personas") if total >= minimum

        fail("#{total} de #{minimum}")
      end

      def description = "participan al menos #{Flow::Texto.contar(minimum, "persona")}"

      def config_errors
        return ["el mínimo debe ser al menos 1"] if minimum < 1

        []
      end

      private

      def minimum = (config["minimum"] || 2).to_i
    end
  end
end
