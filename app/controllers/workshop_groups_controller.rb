# frozen_string_literal: true

# Alta y baja de mesas. Poblarlas —convocar gente— es de
# `WorkshopConvocationsController`; acá sólo se arma y se borra la mesa.
class WorkshopGroupsController < ApplicationController
  before_action :set_workshop

  def create
    authorize @workshop, :manage_groups?
    @workshop.workshop_groups.create!(name: params[:name].presence || next_name)
    redirect_to workshop_path(@workshop), notice: "Mesa creada."
  end

  def destroy
    authorize @workshop, :manage_groups?
    @workshop.workshop_groups.find_by!(id: params[:id]).destroy!
    redirect_to workshop_path(@workshop), notice: "Mesa eliminada."
  end

  private

  # `policy_scope(...).find_by!` y no `Workshop.find_by!`: así lo que no se ve
  # da 404 y no 403, que sería un oráculo de existencia.
  def set_workshop = @workshop = policy_scope(Workshop).find_by!(id: params[:workshop_id])

  def next_name = "Mesa #{@workshop.workshop_groups.count + 1}"
end
