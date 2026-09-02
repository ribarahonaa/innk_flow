# frozen_string_literal: true

module Flow
  module Notifications
    # ÚNICO escritor de notificaciones.
    #
    # Un solo camino para que sumar un canal —mail, push— sea tocar acá y nada
    # más, y para que la deduplicación no dependa de que cada call site se
    # acuerde.
    class Notify
      def self.call(...) = new(...).call

      def initialize(kind:, user:, challenge: nil, step: nil, idea: nil, payload: {})
        @kind = kind.to_s
        @user = user
        @challenge = challenge || step&.challenge || idea&.challenge
        @step = step
        @idea = idea
        @payload = payload
      end

      def call
        return nil if @user.nil?
        return nil if duplicate?

        Notification.create!(
          user: @user, kind: @kind, challenge: @challenge,
          challenge_step: @step, idea: @idea, payload: @payload.stringify_keys
        )
      end

      private

      # Avisar dos veces lo mismo mientras lo primero sigue sin leerse entrena
      # a la gente a ignorar la campana. Una vez leído, un aviso nuevo sobre lo
      # mismo sí tiene sentido: pasó otra vez.
      def duplicate?
        Notification.unread.exists?(
          user_id: @user.id, kind: @kind,
          challenge_step_id: @step&.id, idea_id: @idea&.id
        )
      end
    end
  end
end
