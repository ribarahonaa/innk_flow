# frozen_string_literal: true

class ChallengesController < ApplicationController
  before_action :set_challenge, only: %i[show builder start close]

  def index
    @challenges = policy_scope(Challenge).includes(:steps).order(created_at: :desc)
  end

  def new
    @challenge = Challenge.new(ai_default_mode: "ai_assisted")
    authorize @challenge
  end

  def create
    @challenge = Challenge.new(challenge_params)
    authorize @challenge

    if @challenge.save
      redirect_to builder_challenge_path(@challenge), notice: "Desafío creado. Armá su flujo."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    authorize @challenge
    @pipeline = @challenge.pipeline
    @report = @pipeline.validate
    @pending_suggestions = AiSuggestion.pending_review.where(challenge_id: @challenge.id).recent
  end

  def builder
    authorize @challenge, :builder?
    @props = PipelinePresenter.new(@challenge, membership: current_membership).as_json
  end

  def start
    authorize @challenge, :start?
    result = @challenge.pipeline.start!

    if result.ok?
      redirect_to challenge_path(@challenge), notice: "El desafío arrancó."
    else
      redirect_to builder_challenge_path(@challenge), alert: result.error_sentence
    end
  end

  def close
    authorize @challenge, :close?
    @challenge.pipeline.close!
    redirect_to challenge_path(@challenge), notice: "Desafío cerrado."
  end

  private

  def set_challenge
    # Scopeado por TenantScoped: un slug de otra empresa levanta
    # RecordNotFound, que TenantResolution traduce a 404 (nunca 403).
    @challenge = Challenge.find_by!(slug: params[:id])
  end

  def challenge_params
    params.require(:challenge).permit(:name, :brief, :ai_default_mode)
  end
end
