# frozen_string_literal: true

# Confirmar el corte de un módulo de selección, y repescar.
class SelectionsController < ApplicationController
  before_action :set_context

  def update
    authorize @step, :advance?
    advancing = Array(params[:advancing_idea_ids]).reject(&:blank?)

    @step.handler.decide!(advancing, decided_by: current_user, reason: params[:reason])

    redirect_to challenge_step_path(@challenge, @step),
                notice: "Corte confirmado: avanzan #{Flow::Texto.contar(advancing.size, "idea")}."
  end

  # Un filtro de sí/no resuelto por una persona.
  def verdict
    authorize @step, :advance?
    idea = policy_scope(@challenge.ideas).find(params[:idea_id])

    @step.handler.record_verdict!(
      idea: idea,
      criterion_key: params[:criterion_key],
      passed: params[:passed].to_s == "true",
      decided_by: current_user,
      note: params[:note].presence
    )

    redirect_to challenge_step_path(@challenge, @step),
                notice: "Veredicto registrado para «#{idea.title.truncate(40)}»."
  end

  def reinstate
    authorize @step, :advance?
    idea = policy_scope(@challenge.ideas).find(params[:idea_id])

    @step.handler.reinstate!(idea, decided_by: current_user, reason: params[:reason])

    redirect_to challenge_step_path(@challenge, @step),
                notice: "«#{idea.title}» vuelve al flujo."
  end

  private

  def set_context
    @challenge = policy_scope(Challenge).find_by!(slug: params[:challenge_id])
    @step = @challenge.steps.find(params[:step_id])
  end
end
