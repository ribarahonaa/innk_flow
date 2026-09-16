# frozen_string_literal: true

class FeedbackItemsController < ApplicationController
  before_action :set_context

  def create
    @feedback = FeedbackItem.new(
      challenge_step: @step, idea: @idea,
      idea_version_id: @idea.current_version_id,
      author: current_user, actor_type: "human",
      kind: params[:kind].presence || "suggestion",
      body: params[:body]
    )
    authorize @feedback, :create?

    if @feedback.save
      redirect_back fallback_location: challenge_step_path(@challenge, @step), notice: "Feedback registrado."
    else
      redirect_back fallback_location: challenge_step_path(@challenge, @step),
                    alert: @feedback.errors.full_messages.to_sentence
    end
  end

  # Cerrar un comentario a mano, sin tener que editar la idea.
  def resolve
    @feedback = FeedbackItem.find(params[:id])
    authorize @feedback, :resolve?

    @feedback.resolve!(
      resolution: params[:resolution],
      user: current_user,
      note: params[:note]
    )

    redirect_back fallback_location: challenge_step_path(@challenge, @step),
                  notice: "Comentario marcado como «#{@feedback.resolution_label.downcase}»."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: challenge_step_path(@challenge, @step),
                  alert: e.record.errors.full_messages.to_sentence
  end

  # Reabrir: la resolución fue apresurada.
  def reopen
    @feedback = FeedbackItem.find(params[:id])
    authorize @feedback, :resolve?

    @feedback.update!(resolution: nil, resolved_by: nil, resolved_at: nil,
                      resolution_note: nil, addressed_by_version_id: nil)

    redirect_back fallback_location: challenge_step_path(@challenge, @step),
                  notice: "Comentario reabierto."
  end

  private

  def set_context
    @challenge = policy_scope(Challenge).find_by!(slug: params[:challenge_id])
    @step = @challenge.steps.find(params[:step_id])
    # Por `policy_scope` y no `@challenge.ideas`: a quien participa, una idea
    # ajena le daba 403 y un id inexistente 404, y esa diferencia confirma que
    # existe. Lo que no ve, no existe.
    @idea = policy_scope(@challenge.ideas).find(params[:idea_id]) if params[:idea_id].present?
  end
end
