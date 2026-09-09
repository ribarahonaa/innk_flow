# frozen_string_literal: true

# Los criterios de UN módulo, definidos sin salir del desafío.
#
# Antes el único camino era la biblioteca: para puntuar había que irse del
# builder, crear una "plantilla reusable" con nombre propio aunque fuera para
# un solo módulo, y volver. El modelo ya soportaba sets `inline` —atados a un
# módulo— pero nada los creaba salvo `Evaluation#before_resolve_config!`, es
# decir recién al activar, cuando su dueño ya no los ve venir.
class StepCriteriaController < ApplicationController
  before_action :set_step

  # Los criterios se configuran en la pantalla del módulo. Esta URL vivía en
  # links, marcadores y `back_url`, así que redirige en vez de dar 404: un 404
  # acá se lee como una función que se perdió.
  def show
    authorize @step, :manage_criteria?

    redirect_to challenge_step_path(@challenge, @step), status: :moved_permanently
  end

  # Crea el set propio del módulo. `from` decide con qué arranca:
  #
  #   defaults  los tres genéricos, para no empezar en blanco
  #   library   una copia del set de la biblioteca que el módulo tenía
  #   blank     vacío
  #
  # Copiar en vez de apuntar es deliberado: editar los criterios de un módulo
  # no puede reescribir la plantilla que comparten otros desafíos.
  def create
    authorize @step, :manage_criteria?

    return redirect_to(step_criteria_path, alert: "Este módulo ya se ejecutó.") if @step.touched?

    set = build_set
    @step.update!(criteria_set_id: set.id)

    redirect_to step_criteria_path, notice: "Listo: estos criterios son de este módulo."
  end

  private

  def set_step
    @challenge = policy_scope(Challenge).find_by!(slug: params[:challenge_id])
    @step = @challenge.steps.find(params[:step_id])
    raise ActiveRecord::RecordNotFound unless @step.evaluation? || @step.selection?
  end

  def build_set
    source = @step.criteria_set

    if params[:from] == "library" && source&.library?
      copy = source.promote_to_library!(name: "Criterios de «#{@step.name}»")
      copy.update!(scope: "inline", owner_step_id: @step.id)
      return copy
    end

    set = CriteriaSet.create!(
      name: "Criterios de «#{@step.name}»", scope: "inline", owner_step_id: @step.id,
      description: "Propios de este módulo. No afectan a otros desafíos."
    )
    seed_defaults(set) if params[:from] == "defaults"
    set.refresh_status!
    set
  end

  def seed_defaults(set)
    Flow::Handlers::Evaluation::DEFAULT_CRITERIA.each { |attributes| set.criteria.create!(**attributes) }
  end

  def step_criteria_path = challenge_step_criteria_path(@challenge, @step)
end
