# frozen_string_literal: true

# La sala de UN desafío del taller: la pantalla donde la mesa trabaja.
#
# `workshops#show` es el selector —qué desafíos hay y de qué tratan— y esto es
# el trabajo. Antes las dos cosas vivían en la misma pantalla, con un
# formulario por desafío apilado y sin nada que dijera de qué trataba cada uno.
class WorkshopRoomsController < ApplicationController
  include ActsOnAGroup

  def show
    # `policy_scope(...).find_by!` y no `Workshop.find_by!`: lo que no se ve da
    # 404 y no 403, que sería un oráculo de existencia.
    @workshop = policy_scope(Workshop).find_by!(id: params[:workshop_id])
    # El mismo predicado que los dos POST de la sala, no uno nuevo. Incluye a
    # quien administra sin estar sentado (`work?` da true por
    # `administers_any?`): entra, y si no nombra una mesa por parámetro la cara
    # le dice que no tiene.
    authorize @workshop, :work?

    # ANTES de leer el vínculo. El cierre es perezoso —nada se engancha en
    # `advance!`— y entrar a la sala es justo lo que hace que el taller se
    # entere de que el desafío avanzó. Sin esto la sala dibuja trabajo sobre un
    # módulo que ya cerró.
    Flow::Workshops::MaterializeClosures.new(@workshop).call

    @link = @workshop.workshop_challenges.find_by!(id: params[:id])
    # «Sobre qué mesa actúo», no «cuál es mi mesa»: quien administra ESE desafío
    # puede nombrar una.
    @group = acting_group(@workshop, @link)
    # Si la mesa salió del parámetro y no del asiento, los títulos no pueden
    # decir «tu mesa»: es la misma fuga que `load_ideation` documenta, con el
    # título mintiendo en vez del scope. `own_group` está memoizado, así que
    # esto no paga una segunda consulta.
    @mesa_propia = @group.present? && @group == own_group(@workshop)
    @rooms = Flow::Workshops::Rooms.new(@workshop)

    case @link.room_state
    when :ideation then load_ideation
    when :evolution then load_evolution
    end

    # Las de ESTA mesa y nada más. El filtro por mesa es PORTANTE y no
    # prolijidad: quien administra no es `participant`, así que un scope por
    # policy le devolvería todo, y vería la conversación de las otras mesas bajo
    # un título que dice que es la suya. Es la misma trampa que `load_ideation`
    # documenta para las ideas. Y desde la llegada no se lista nada: ahí están
    # sentados los treinta que esperan.
    @recordings = load_recordings
  end

  private

  def load_recordings
    return WorkshopRecording.none if @group.nil? || @group.arrival?

    # La precarga va acá, en el punto de uso, igual que la del borrador de
    # evolución. La tarjeta lee `recorded_by.name` y `file.attached?` por fila,
    # y el segundo es una consulta por fila: una mesa con quince grabaciones
    # hacía treinta consultas que no se ven en ninguna pantalla.
    @group.workshop_recordings.where(workshop_challenge: @link)
          .includes(:recorded_by, file_attachment: :blob).recent_first
  end

  # Las ideas de la mesa en este desafío. `policy_scope(Idea)` y NO
  # `workable_ideas`: ese método filtra con `Idea.alive` (o sea `active`) y no
  # trae borradores, y su comentario documenta que exponer a la mesa el
  # borrador que un integrante creó AFUERA del taller fue una fuga ya
  # arreglada. Con `policy_scope` la fuga es imposible por construcción.
  #
  # Y el filtro por integrantes va ADENTRO del scope, no en vez de él: para
  # quien administra, `IdeaPolicy::Scope` devuelve `all`, así que sin esto el
  # bloque listaba las ideas de las OTRAS mesas bajo un título que dice que
  # son de ésta.
  #
  # Va en el CONTROLLER a propósito: el lint sólo mira controllers.
  def load_ideation
    @mesa_ideas =
      if @group && !@group.arrival?
        member_ids = @group.workshop_group_members.select(:user_id)
        visibles = policy_scope(Idea).where(challenge_id: @link.challenge_id, status: %w[draft active])
        visibles.where(author_id: member_ids)
                .or(visibles.where(id: IdeaContributor.where(user_id: member_ids).select(:idea_id)))
                .includes(:author, :current_version, idea_contributors: :user)
                .order(created_at: :desc).to_a
      else
        []
      end

    # El borrador es de la MESA: se lee por `@group.workshop_drafts` y no por una
    # búsqueda global. Así la mesa lo ata por construcción, igual que
    # `@group.workshop_proposals`, y no hace falta una policy para el borrador.
    @draft = @group.workshop_drafts.includes(:updated_by).find_by(workshop_challenge: @link, idea_id: nil) if @group && !@group.arrival?
  end

  # Acá SÍ es `workable_ideas`: es el método que existe para esto —la unión
  # sobre los integrantes de la mesa— y ya excluye la mesa de llegada, lo
  # eliminado y lo retirado.
  def load_evolution
    @workable_ideas =
      if @group
        @group.workable_ideas(@link.challenge)
              .includes(:author, :current_version, idea_contributors: :user)
              .order(created_at: :desc).to_a
      else
        []
      end

    # Fuera del conjunto trabajable es `nil`, igual que un id inexistente: no
    # confirma que exista. Se busca en el array ya cargado y no con otra
    # consulta. Con una sola idea se preselecciona: es un DEFAULT, no un
    # redirect, así que no hay bucle posible.
    @selected_idea = @workable_ideas.detect { |idea| idea.id == params[:idea] }
    @selected_idea ||= @workable_ideas.first if @workable_ideas.one?

    @mesa_proposals =
      if @group && @selected_idea
        @group.workshop_proposals.where(idea_id: @selected_idea.id)
              .includes(:challenge_step).order(created_at: :desc).to_a
      else
        []
      end

    # La precarga va acá, en el punto de uso: el sello nombra a quien tocó
    # último (`workshop_rooms/_draft_stamp` lee `updated_by`) y el aviso compara
    # la versión (`_evolution` lee `based_on_version`). Sacar este `includes`
    # por peso muerto son dos consultas más por render sin que nada se ponga rojo.
    @draft =
      if @group && !@group.arrival? && @selected_idea
        @group.workshop_drafts.includes(:updated_by, :based_on_version)
              .find_by(workshop_challenge: @link, idea: @selected_idea)
      end
  end
end
