# frozen_string_literal: true

# Mantenedor de criterios de la empresa.
class CriteriaSetsController < ApplicationController
  before_action :set_criteria_set, only: %i[show edit destroy promote]

  def index
    @sets = policy_scope(CriteriaSet).library.current.includes(:criteria).order(:name)
  end

  # El set nace VACÍO. Antes traía dos criterios ya puestos, que la mitad de
  # las veces había que borrar: el editor ofrece plantillas de arranque, que es
  # lo mismo pero elegido.
  def new
    @set = CriteriaSet.new(name: "")
    authorize @set
    @props = CriteriaSetPresenter.new(@set, membership: current_membership).as_json
  end

  def show
    authorize @set
  end

  def edit
    authorize @set
    @props = CriteriaSetPresenter.new(@set, membership: current_membership).as_json
  end

  def destroy
    authorize @set
    @set.destroy!
    redirect_to criteria_sets_path, notice: "Set eliminado."
  end

  def promote
    authorize @set, :create?
    copy = @set.promote_to_library!
    redirect_to edit_criteria_set_path(copy), notice: "Copiado a la biblioteca."
  end

  private

  def set_criteria_set
    @set = CriteriaSet.find(params[:id])
  end
end
