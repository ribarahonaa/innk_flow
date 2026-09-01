# frozen_string_literal: true

# Mantenedor de criterios de la empresa.
class CriteriaSetsController < ApplicationController
  before_action :set_criteria_set, only: %i[show edit update destroy promote]

  def index
    @sets = policy_scope(CriteriaSet).library.includes(:criteria).order(:name)
  end

  def new
    @set = CriteriaSet.new(name: "Nuevo set")
    authorize @set
    @set.criteria.build(name: "Impacto", weight: 0.5, source: "manual", scale_type: "numeric",
                        scale_config: { "min" => 1, "max" => 10 }, position: 0)
    @set.criteria.build(name: "Factibilidad", weight: 0.5, source: "manual", scale_type: "numeric",
                        scale_config: { "min" => 1, "max" => 10 }, position: 1)
  end

  def create
    @set = CriteriaSet.new(criteria_set_params)
    authorize @set

    if @set.save
      @set.refresh_status!
      redirect_to criteria_sets_path, notice: "Set creado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    authorize @set
  end

  def edit
    authorize @set
  end

  def update
    authorize @set

    if @set.update(criteria_set_params)
      @set.refresh_status!
      redirect_to criteria_sets_path, notice: "Set actualizado."
    else
      render :edit, status: :unprocessable_entity
    end
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

  def criteria_set_params
    params.require(:criteria_set).permit(
      :name, :description,
      criteria_attributes: [:id, :key, :name, :description, :weight, :source, :scale_type,
                            :position, :active, :_destroy,
                            { scale_config: {}, source_config: {} }]
    )
  end
end
