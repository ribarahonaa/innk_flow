# frozen_string_literal: true

# Convocar y desconvocar gente de un taller. Convocar es sumar a una mesa
# (`Flow::Workshops::Convoke`); desconvocar es sacarla de la que esté, sin
# importar cuál.
class WorkshopConvocationsController < ApplicationController
  before_action :set_workshop

  def create
    authorize @workshop, :manage_groups?
    user = User.find_by(id: params[:user_id])
    group = @workshop.workshop_groups.find_by(id: params[:workshop_group_id])
    result = Flow::Workshops::Convoke.new(@workshop, user, group: group).call

    if result.ok?
      redirect_to workshop_path(@workshop), notice: "Convocada a la mesa."
    else
      redirect_to workshop_path(@workshop), alert: result.errors.to_sentence
    end
  end

  def destroy
    authorize @workshop, :manage_groups?
    WorkshopGroupMember.joins(:workshop_group)
                        .where(workshop_groups: { workshop_id: @workshop.id }, user_id: params[:user_id])
                        .destroy_all
    redirect_to workshop_path(@workshop), notice: "Ya no está convocada."
  end

  private

  # `policy_scope(...).find_by!` y no `Workshop.find_by!`: así lo que no se ve
  # da 404 y no 403, que sería un oráculo de existencia.
  def set_workshop = @workshop = policy_scope(Workshop).find_by!(id: params[:id])
end
