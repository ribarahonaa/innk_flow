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

  def skip
    authorize @step, :skip?
    @step.handler.skip!(reason: params[:reason])
    @step.challenge.pipeline.advance! if @step.challenge.pipeline.active_step.nil?
    redirect_to challenge_path(@step.challenge), notice: "Módulo salteado."
  end

  private

  def set_step
    @challenge = Challenge.find_by!(slug: params[:challenge_id])
    @step = @challenge.steps.find(params[:id])
  end
end
