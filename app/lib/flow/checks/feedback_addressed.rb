# frozen_string_literal: true

module Flow
  module Checks
    # La idea atendió el feedback que recibió: no le quedan comentarios
    # abiertos de un módulo de evolución.
    class FeedbackAddressed < Base
      def call(idea)
        items = FeedbackItem.where(idea_id: idea.id)
        return pass("sin feedback recibido") if items.empty?

        open_items = items.count { |item| !item.addressed }
        return pass("#{items.size} atendidos") if open_items.zero?

        fail("#{open_items} sin atender")
      end

      def description = "atendió todo el feedback recibido"
    end
  end
end
