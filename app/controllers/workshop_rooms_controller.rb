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

    # Las ideas de la mesa en este desafío. `policy_scope(Idea)` y NO
    # `workable_ideas`: ese método filtra con `Idea.alive` (o sea `active`) y no
    # trae borradores, y su comentario documenta que exponer a la mesa el
    # borrador que un integrante creó AFUERA del taller fue una fuga ya
    # arreglada. Con `policy_scope` la fuga es imposible por construcción.
    #
    # Y el filtro por integrantes va ADENTRO del scope, no en vez de él: para
    # quien administra, `IdeaPolicy::Scope` devuelve `all`, así que sin esto el
    # bloque listaba las ideas de las OTRAS mesas bajo un título que dice que
    # son de ésta. En evolución llega en la Task 5.
    #
    # Va en el CONTROLLER a propósito: el lint sólo mira controllers.
    @mesa_ideas =
      if @link.room_state == :ideation && @group && !@group.arrival?
        member_ids = @group.workshop_group_members.select(:user_id)
        visibles = policy_scope(Idea).where(challenge_id: @link.challenge_id, status: %w[draft active])
        visibles.where(author_id: member_ids)
                .or(visibles.where(id: IdeaContributor.where(user_id: member_ids).select(:idea_id)))
                .includes(:author, :current_version, idea_contributors: :user)
                .order(created_at: :desc).to_a
      else
        []
      end
  end
end
