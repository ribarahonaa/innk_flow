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
          resueltos = @workshop.workshop_challenges.includes(:challenge).map do |link|
            [link, link.challenge.pipeline.active_step]
          end

          # La fase se verifica ACÁ y sobre TODO junto, que es lo que ningún
          # otro lugar puede hacer: en borrador `challenge_step` es nil, así que
          # una validación de modelo no tiene fase con la que comparar.
          #
          # Va antes de escribir nada: rechazar después de cerrar vínculos
          # dejaría el taller a medio abrir hasta que el rollback lo deshaga, y
          # el motivo del rechazo se leería sobre un estado que ya no existe.
          trabajables = resueltos.select { |_, step| step && WorkshopChallenge::WORKABLE_KINDS.include?(step.kind) }
          if trabajables.map { |_, step| step.kind }.uniq.size > 1
            @error = mixed_phases(trabajables)
            raise ActiveRecord::Rollback
          end

          resueltos.each do |link, step|
            if trabajables.any? { |l, _| l.id == link.id }
              link.update!(challenge_step: step, status: "open")
            else
              link.update!(status: "closed", closed_at: Time.current, closed_reason: self.class.reason_for(step))
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

        # Acá el rollback ya deshizo los `update!` a "closed": informar esos
        # vínculos como rechazados sería mentir sobre lo que quedó en la
        # base. El motivo de la falla ya viaja en `errors`.
        return Result.new(ok: false, rejected: [], errors: [@error || no_workable_challenges]) unless @workshop.reload.open?

        Result.new(ok: true, rejected: rejected, errors: [])
      end

      # Por qué un taller no puede trabajar contra el módulo que hoy corre en
      # ese desafío. Público y de clase porque lo reusa el cierre perezoso de
      # la sala (`MaterializeClosures`): dos textos para lo mismo divergen, y
      # el día que difieran uno estaría mintiendo.
      def self.reason_for(step)
        return "El desafío no tiene ningún módulo en curso." if step.nil?

        "El desafío está en #{I18n.t("flow.kinds.#{step.kind}")}, " \
          "y un taller sólo trabaja sobre idear o evolución."
      end

      private

      def no_workable_challenges = "Ningún desafío del taller está en idear ni en evolución."

      # Nombra qué desafío está en cuál fase: «el taller mezcla fases» sin los
      # nombres deja a quien lo lee abriendo los desafíos de a uno.
      def mixed_phases(trabajables)
        por_fase = trabajables.group_by { |_, step| step.kind }
        detalle = por_fase.map do |kind, pares|
          "#{I18n.t("flow.kinds.#{kind}")}: #{pares.map { |link, _| "«#{link.challenge.name}»" }.to_sentence}"
        end
        "Un taller trabaja sobre una sola fase, y este mezcla dos. #{detalle.join(' · ')}."
      end
    end
  end
end
