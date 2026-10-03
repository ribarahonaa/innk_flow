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
  end
end
