# frozen_string_literal: true

module Flow
  module Workshops
    # El cierre del vínculo es PEREZOSO: nada se engancha en `advance!` —eso le
    # daría a un evento poder sobre el motor, y un taller olvidado abierto
    # dejaría un desafío trabado—. Esto es lo que lo materializa, y ocurre
    # cuando alguien entra a la sala.
    #
    # Sin esto, tras cualquier avance el vínculo quedaba `open` con su
    # `challenge_step` ya `completed`: la sala no lo dibujaba en ninguna cara
    # —salía EN BLANCO— y el armado lo listaba sin motivo. Un fallback de vista
    # no alcanza: dejaría la base diciendo `open` y el armado sin el motivo.
    class MaterializeClosures
      def initialize(workshop)
        @workshop = workshop
      end

      # Devuelve los vínculos que cerró.
      def call
        # Sólo un taller ABIERTO tiene vínculos que se venzan. En borrador el
        # `challenge_step_id` todavía es nulo a propósito —lo resuelve `Open`—,
        # así que sin esta guarda entrar al armado los cerraba a todos con «El
        # desafío no tiene ningún módulo en curso». Y uno cerrado ya pasó por
        # `Close`.
        return [] unless @workshop.open?

        stale = @workshop.workshop_challenges.includes(:challenge, :challenge_step)
                         .select { |link| link.open? && !link.workable? }
        return [] if stale.empty?

        closed = []
        @workshop.with_lock do
          stale.each do |link|
            # Releído bajo lock: dos pestañas entrando a la vez no escriben dos
            # motivos distintos sobre el mismo vínculo.
            link.reload
            next unless link.open? && !link.workable?

            link.update!(status: "closed", closed_at: Time.current, closed_reason: reason_for(link))
            closed << link
          end
        end
        closed
      end

      private

      # El desafío pudo avanzar a una fase que el taller TAMBIÉN sabe trabajar
      # (idear → evolución). El vínculo se cierra igual —el modo de trabajo de
      # una mesa no puede cambiar debajo de sus pies a mitad de sesión—, y ése
      # es el único caso que `Open.reason_for` no tiene: al abrir nunca se
      # rechaza un desafío trabajable. Los otros dos salen de allá.
      def reason_for(link)
        step = link.challenge.pipeline.active_step
        return Open.reason_for(step) unless step && WorkshopChallenge::WORKABLE_KINDS.include?(step.kind)

        "El desafío avanzó a #{I18n.t("flow.kinds.#{step.kind}")} («#{step.name}»): " \
          "para acompañar esa fase hay que volver a vincularlo."
      end
    end
  end
end
