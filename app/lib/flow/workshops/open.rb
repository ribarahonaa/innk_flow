# frozen_string_literal: true

module Flow
  module Workshops
    # Abrir un taller resuelve, de una vez, contra qué módulo trabaja en cada
    # desafío. Es el mismo late binding del pipeline: `config` guarda la
    # intención y `resolved_config` se escribe una vez al arrancar.
    #
    # La fase se verifica ACÁ y no al sumar el desafío: entre que el taller se
    # arma y se abre, el desafío pudo avanzar.
    class Open
      Result = Data.define(:ok, :rejected, :errors) do
        def ok? = ok
      end

      def initialize(workshop)
        @workshop = workshop
      end

      def call
        return Result.new(ok: false, rejected: [], errors: ["El taller ya no está en borrador."]) unless @workshop.draft?

        rejected = []

        @workshop.with_lock do
          @workshop.workshop_challenges.includes(:challenge).each do |link|
            step = link.challenge.pipeline.active_step

            if step && WorkshopChallenge::WORKABLE_KINDS.include?(step.kind)
              link.update!(challenge_step: step, status: "open")
            else
              link.update!(status: "closed", closed_at: Time.current, closed_reason: reason_for(step))
              rejected << link
            end
          end

          # Un taller sin una sola sala no es un taller: abrirlo dejaría una
          # pantalla vacía con estado «abierto», que es peor que el error. El
          # rollback deja TODO como estaba —también los vínculos que se
          # acababan de cerrar en este mismo intento—, para no dejar un taller
          # a medio abrir.
          raise ActiveRecord::Rollback if @workshop.workshop_challenges.reload.none?(&:open?)

          @workshop.update!(status: "open")
        end

        return Result.new(ok: false, rejected: rejected, errors: [no_workable_challenges]) unless @workshop.reload.open?

        Result.new(ok: true, rejected: rejected, errors: [])
      end

      private

      def reason_for(step)
        return "El desafío no tiene ningún módulo en curso." if step.nil?

        "El desafío está en #{I18n.t("flow.kinds.#{step.kind}")}, " \
          "y un taller sólo trabaja sobre idear o evolución."
      end

      def no_workable_challenges = "Ningún desafío del taller está en idear ni en evolución."
    end
  end
end
