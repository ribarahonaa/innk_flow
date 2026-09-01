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

  private

  def set_context
    @challenge = Challenge.find_by!(slug: params[:challenge_id])
    @step = @challenge.steps.find(params[:step_id])
    @idea = @challenge.ideas.find(params[:idea_id])
  end
end
