# frozen_string_literal: true

# La sala de UN desafío del taller: la pantalla donde la mesa trabaja.
#
# `workshops#show` es el selector —qué desafíos hay y de qué tratan— y esto es
# el trabajo. Antes las dos cosas vivían en la misma pantalla, con un
# formulario por desafío apilado y sin nada que dijera de qué trataba cada uno.
class WorkshopRoomsController < ApplicationController
  def show
    # `policy_scope(...).find_by!` y no `Workshop.find_by!`: lo que no se ve da
    # 404 y no 403, que sería un oráculo de existencia.
    @workshop = policy_scope(Workshop).find_by!(id: params[:workshop_id])
    # El mismo predicado que los dos POST de la sala, no uno nuevo. Incluye a
    # quien administra sin estar sentado (`work?` da true por
    # `administers_any?`): entra, y la cara le dice que no tiene mesa.
    authorize @workshop, :work?

    # ANTES de leer el vínculo. El cierre es perezoso —nada se engancha en
    # `advance!`— y entrar a la sala es justo lo que hace que el taller se
    # entere de que el desafío avanzó. Sin esto la sala dibuja trabajo sobre un
    # módulo que ya cerró.
    Flow::Workshops::MaterializeClosures.new(@workshop).call

    @link = @workshop.workshop_challenges.find_by!(id: params[:id])
    @group = @workshop.group_of(current_user)
    @rooms = Flow::Workshops::Rooms.new(@workshop)

    # Las ideas de la mesa, según la cara. En idear es lo que la mesa YA creó;
    # en evolución llega en la Task 5.
    #
    # `policy_scope(Idea)` y NO `group.workable_ideas`, por dos razones: ese
    # método filtra con `Idea.alive` (o sea `active`) y no trae borradores, y su
    # comentario documenta que exponer a toda la mesa el borrador que un
    # integrante creó AFUERA del taller fue una fuga ya arreglada. Con
    # `policy_scope` la fuga es imposible: el borrador creado en la sala lleva a
    # la mesa entera como `idea_contributors`, así que cada integrante lo ve por
    # `IdeaPolicy::Scope`, y el privado de alguien sigue siendo sólo suyo.
    #
    # Va en el CONTROLLER a propósito: `spec/lint/ideas_por_policy_scope_spec.rb`
    # sólo mira controllers. Escondida en un presenter no la ve nadie.
    @mesa_ideas =
      if @link.room_state == :ideation
        policy_scope(Idea).where(challenge_id: @link.challenge_id, status: %w[draft active])
                          .includes(:author, :current_version, idea_contributors: :user)
                          .order(created_at: :desc).to_a
      else
        []
      end
  end
end
