# frozen_string_literal: true

# Confirmar el corte de un módulo de selección, y repescar.
class SelectionsController < ApplicationController
  before_action :set_context

  def update
    authorize @step, :advance?
    advancing = Array(params[:advancing_idea_ids]).reject(&:blank?)

    @step.handler.decide!(advancing, decided_by: current_user, reason: params[:reason])

    redirect_to challenge_step_path(@challenge, @step),
                notice: "Corte confirmado: avanzan #{advancing.size} #{'idea'.pluralize(advancing.size)}."
  end

  def reinstate
    authorize @step, :advance?
    idea = @challenge.ideas.find(params[:idea_id])

    @step.handler.reinstate!(idea, decided_by: current_user, reason: params[:reason])

    redirect_to challenge_step_path(@challenge, @step),
                notice: "«#{idea.title}» vuelve al flujo."
  end

  private

  def set_context
    @challenge = Challenge.find_by!(slug: params[:challenge_id])
    @step = @challenge.steps.find(params[:step_id])
  end
end
