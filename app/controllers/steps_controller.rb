# frozen_string_literal: true

# Pantalla de un módulo. Despacha por `kind` a la vista que corresponde.
#
# Un controller y no cinco: el flujo (encontrar el step, autorizar, resolver
# el handler) es idéntico; lo único que cambia es qué se renderiza.
class StepsController < ApplicationController
  before_action :set_step

  def show
    authorize @step, :show?
    @handler = @step.handler
    @pending_suggestions = AiSuggestion.pending_review.where(challenge_step_id: @step.id).recent
    @assignable = @step.evaluation? ? assignable_users : []
    render "steps/#{@step.kind}"
  end

  def advance
    authorize @step, :advance?
    result = @step.challenge.pipeline.advance!

    if result.ok?
      notice = result.step ? "Avanzaste a «#{result.step.name}»." : "El desafío terminó su flujo."
      redirect_to challenge_path(@step.challenge), notice: notice
    else
      redirect_to challenge_step_path(@step.challenge, @step), alert: result.error_sentence
    end
  end

  # Ajustes que no reescriben la historia: el nombre y el modo de IA.
  def update
    authorize @step, :advance?

    if @step.update(step_params)
      redirect_to challenge_step_path(@step.challenge, @step),
                  notice: "Módulo actualizado: la IA queda en «#{t("flow.ai_modes.#{@step.effective_ai_mode}")}»."
    else
      redirect_to challenge_step_path(@step.challenge, @step),
                  alert: @step.errors.full_messages.to_sentence
    end
  end

  def skip
    authorize @step, :skip?
    @step.handler.skip!(reason: params[:reason])
    @step.challenge.pipeline.advance! if @step.challenge.pipeline.active_step.nil?
    redirect_to challenge_path(@step.challenge), notice: "Módulo salteado."
  end

  private

  # Quién puede sumarse a evaluar este módulo.
  #
  # Evaluar depende de la ASIGNACIÓN y no del rol, así que la lista es amplia:
  # quien evalúa, quien administra, y los gestores asignados a este desafío —no
  # todos los de la empresa, porque un gestor solo alcanza lo que se le asignó.
  def assignable_users
    roles = Membership.where(role: %w[evaluator admin]).pluck(:user_id)
    gestores = ChallengeGestor.where(challenge_id: @step.challenge_id).pluck(:user_id)
    ya_estan = @step.step_assignments.pluck(:user_id)

    User.where(id: (roles + gestores).uniq - ya_estan).order(:name)
  end

  def set_step
    @challenge = policy_scope(Challenge).find_by!(slug: params[:challenge_id])
    @step = @challenge.steps.find(params[:id])
  end

  def step_params
    params.require(:challenge_step).permit(*ChallengeStep::ADJUSTABLE_ATTRIBUTES)
  end
end
