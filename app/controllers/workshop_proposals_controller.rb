# frozen_string_literal: true

# Lo que una mesa propone sobre una idea ya existente, en una ronda de
# evolución. Nace `pending`: el autor la acepta o la rechaza (otra tarea).
class WorkshopProposalsController < ApplicationController
  before_action :set_link

  def create
    authorize @workshop, :work?
    return reject_room unless @link.workable? && @link.kind == "evolution"

    payload = payload_params
    return reject_payload if payload.nil? && params.key?(:payload)

    group = @workshop.group_of(current_user)
    return reject_without_group unless group
    return reject_arrival if group.arrival?

    # Acá el filtro NO es `policy_scope(Idea)`: ese scope deja ver a quien
    # participa sólo lo que creó o comparte él, y la mesa trabaja lo de
    # CUALQUIERA de sus integrantes (`WorkshopGroup#workable_ideas`). El 404 se
    # conserva igual: una idea fuera de ese conjunto no se distingue de una
    # inexistente, así que no confirma que exista.
    idea = group.workable_ideas(@link.challenge).find_by!(id: params[:idea_id])

    WorkshopProposal.create!(
      workshop_group: group, idea: idea, challenge_step: @link.challenge_step,
      payload: payload || {}, status: "pending"
    )

    redirect_to workshop_path(@workshop), notice: "Propuesta enviada a quien es autor."
  end

  private

  def set_link
    @workshop = policy_scope(Workshop).find_by!(id: params[:workshop_id])
    @link = @workshop.workshop_challenges.find_by!(id: params[:sala_id])
  end

  # Contra el formulario del módulo de ideación: es el payload de una futura
  # versión, y una clave que no es de un campo se descarta.
  def payload_params
    step = @link.challenge.pipeline.ideation_step
    keys = step ? step.form_fields.map(&:key) : []
    raw = params[:payload]
    raw.respond_to?(:permit!) ? raw.permit!.to_h.slice(*keys) : nil
  end

  def reject_room
    redirect_to workshop_path(@workshop),
                alert: "Esta sala ya no admite trabajo: el desafío avanzó de fase."
  end

  def reject_payload
    redirect_to workshop_path(@workshop), alert: "La propuesta llegó mal formada: probá de nuevo desde el formulario."
  end

  def reject_without_group
    redirect_to workshop_path(@workshop), alert: "Sólo se propone desde una mesa: no estás en ninguna de este taller."
  end

  # La mesa de llegada no trabaja. El rechazo es explícito y con su mensaje: un
  # 404 pelado en una sala que debería decir «tu mesa todavía no se armó» es el
  # control que no responde.
  def reject_arrival
    redirect_to workshop_path(@workshop),
                alert: "Tu mesa todavía no se armó: esperá el reparto para trabajar."
  end
end
