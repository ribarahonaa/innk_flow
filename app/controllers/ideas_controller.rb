# frozen_string_literal: true

class IdeasController < ApplicationController
  before_action :set_challenge
  before_action :set_idea, only: %i[show edit update submit destroy diff]

  def index
    @ideas = policy_scope(Idea).where(challenge_id: @challenge.id)
                               .includes(:current_version, :author).recent
    @eliminated = @ideas.select(&:eliminated?)
    @alive = @ideas.reject(&:eliminated?)
  end

  def new
    @idea = @challenge.ideas.new(author: current_user)
    authorize @idea, :create?
    @fields = ideation_step.form_fields.ordered
  end

  def create
    @idea = @challenge.ideas.new(author: current_user, status: "draft", origin: "human")
    authorize @idea, :create?

    ActiveRecord::Base.transaction do
      @idea.save!
      publish!(change_note: "Creación de la idea")
    end

    redirect_to challenge_idea_path(@challenge, @idea), notice: "Idea guardada como borrador."
  rescue ActiveRecord::RecordInvalid => e
    @fields = ideation_step.form_fields.ordered
    flash.now[:alert] = e.record.errors.full_messages.to_sentence
    render :new, status: :unprocessable_entity
  end

  def show
    authorize @idea, :show?
    @versions = @idea.versions.chronological.includes(:created_by, :source_step)
    @fields = ideation_step&.form_fields&.ordered || []
    @ideation_step = ideation_step
    @pending_suggestions = AiSuggestion.pending_review.where(idea_id: @idea.id).recent
    @feedback = FeedbackItem.where(idea_id: @idea.id).chronological.includes(:author, :challenge_step)
  end

  def edit
    authorize @idea, :update?
    @fields = ideation_step.form_fields.ordered
  end

  # Editar NO pisa: publica una versión nueva. El historial es el producto.
  def update
    authorize @idea, :update?
    result = publish!(change_note: params[:change_note].presence || "Edición")

    if result.ok?
      # Si el módulo activo es de evolución, esta versión RESPONDE al feedback
      # abierto: se cierra el ciclo feedback → versión.
      close_open_feedback!(result.version)
      redirect_to challenge_idea_path(@challenge, @idea), notice: "Versión #{result.version&.label} publicada."
    else
      @fields = ideation_step.form_fields.ordered
      flash.now[:alert] = result.error_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  def submit
    authorize @idea, :submit?
    @idea.update!(submitted_at: Time.current)
    redirect_to challenge_idea_path(@challenge, @idea), notice: "Idea postulada."
  end

  def destroy
    authorize @idea, :destroy?
    @idea.destroy!
    redirect_to challenge_ideas_path(@challenge), notice: "Idea eliminada."
  end

  def diff
    authorize @idea, :show?
    versions = @idea.versions.chronological.to_a
    @from = versions.find { |v| v.id == params[:a] } || versions.first
    @to = versions.find { |v| v.id == params[:b] } || versions.last
    @fields = ideation_step&.form_fields&.ordered || []
    @diff = Flow::Ideas::Diff.new(@from, @to, fields: @fields)
    @versions = versions
  end

  private

  def set_challenge
    @challenge = Challenge.find_by!(slug: params[:challenge_id])
  end

  def set_idea
    @idea = @challenge.ideas.find(params[:id])
  end

  def ideation_step
    @ideation_step ||= @challenge.pipeline.ideation_step
  end

  def publish!(change_note:)
    Flow::Ideas::PublishVersion.new(
      @idea,
      payload: payload_params,
      author: current_user,
      # Se atribuye al módulo ACTIVO cuando es de evolución: así el historial
      # dice desde dónde salió cada versión.
      source_step: evolution_step || ideation_step,
      change_note: change_note
    ).call
  end

  def evolution_step
    active = @challenge.pipeline.active_step
    active&.evolution? ? active : nil
  end

  def close_open_feedback!(version)
    return if version.nil?

    step = evolution_step
    step&.handler&.record_response!(@idea, version)
  end

  # El payload se arma contra el formulario declarado, no contra lo que llegue:
  # una clave que no corresponde a un FormField del módulo se descarta.
  def payload_params
    permitted = params.fetch(:payload, {}).permit!.to_h
    keys = ideation_step&.form_fields&.map(&:key) || []
    permitted.slice(*keys)
  end
end
