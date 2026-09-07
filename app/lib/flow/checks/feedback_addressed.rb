# frozen_string_literal: true

module Flow
  module Checks
    # La idea atendió el feedback de su ÚLTIMA ronda de evolución.
    #
    # Un desafío puede tener varias rondas, y cada comentario pertenece a la
    # suya. Mirando todas, lo que quedó abierto en una ronda vieja bloqueaba a
    # la idea para siempre aunque hubiera atendido todo lo de la ronda actual —
    # y nadie vuelve a cerrar comentarios de una conversación que ya terminó.
    #
    # «La última» es la ronda más reciente que LE DIO feedback a esta idea: no
    # se puede tener sin atender lo que nadie comentó.
    class FeedbackAddressed < Base
      def call(idea)
        items = FeedbackItem.where(idea_id: idea.id).includes(:challenge_step).to_a
        return pass("sin feedback recibido") if items.empty?

        ronda = items.map(&:challenge_step).compact.max_by { |paso| paso.position.to_d }
        return pass("sin feedback recibido") if ronda.nil?

        de_la_ronda = items.select { |item| item.challenge_step_id == ronda.id }
        abiertos = de_la_ronda.count(&:open?)

        return pass("#{de_la_ronda.size} atendidos en «#{ronda.name}»") if abiertos.zero?

        fail("#{abiertos} sin atender en «#{ronda.name}»")
      end

      def description = "atendió el feedback de su última ronda de evolución"
    end
  end
end
