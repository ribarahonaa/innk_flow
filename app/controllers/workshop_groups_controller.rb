# frozen_string_literal: true

# Alta y baja de mesas. Poblarlas —convocar gente— es de
# `WorkshopConvocationsController`; acá sólo se arma y se borra la mesa.
class WorkshopGroupsController < ApplicationController
  before_action :set_workshop

  def create
    authorize @workshop, :manage_groups?
    return reject_closed if @workshop.closed?

    @workshop.workshop_groups.create!(name: params[:name].presence || next_name)
    redirect_to workshop_path(@workshop), notice: "Mesa creada."
  end

  def destroy
    authorize @workshop, :manage_groups?
    return reject_closed if @workshop.closed?

    @workshop.workshop_groups.find_by!(id: params[:id]).destroy!
    redirect_to workshop_path(@workshop), notice: "Mesa eliminada."
  end

  private

  # `policy_scope(...).find_by!` y no `Workshop.find_by!`: así lo que no se ve
  # da 404 y no 403, que sería un oráculo de existencia.
  def set_workshop = @workshop = policy_scope(Workshop).find_by!(id: params[:workshop_id])

  # Armar mesas y convocar quedan VIVOS con el taller ABIERTO, y es
  # DELIBERADO: llegó alguien tarde a la sesión y hay que moverlo de mesa, que
  # es el caso real de un taller. Lo que se cierra es el taller CERRADO:
  # borrar una mesa cascadea sus `workshop_proposals` —incluidas las
  # aceptadas, y con ellas la procedencia de versiones ya publicadas—, y sobre
  # un taller cerrado eso es puro daño.
  def reject_closed
    redirect_to workshop_path(@workshop), alert: "Este taller ya cerró: las mesas no se tocan."
  end

  def next_name = "Mesa #{@workshop.workshop_groups.count + 1}"
end
