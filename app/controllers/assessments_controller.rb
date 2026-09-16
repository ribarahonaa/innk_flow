# frozen_string_literal: true

# La ficha de evaluación: una idea, los criterios del módulo, una nota por
# criterio.
class AssessmentsController < ApplicationController
  before_action :set_context

  def new
    @assessment = existing_assessment || build_assessment
    authorize @assessment, :create?
    @idea = @assessment.idea
    @handler = handler
    @ai_scores = ai_suggestion_scores
    @prefill = params[:prefill] == "ai" && @ai_scores.any?
  end

  def create
    @assessment = existing_assessment || build_assessment
    authorize @assessment, :create?

    @assessment.transaction do
      @assessment.assign_attributes(
        idea_version_id: @assessment.idea.current_version_id,
        overall_comment: params[:overall_comment],
        status: "submitted",
        submitted_at: Time.current
      )
      @assessment.save!
      write_scores!
      Flow::Evaluation::ScoreAssessment.new(@assessment, criteria_snapshot: handler.criteria_snapshot).call
      handler.recompute_entry!(entry_for(@assessment.idea_id))
    end

    redirect_to challenge_step_path(@challenge, @step), notice: "Evaluación registrada."
  rescue ActiveRecord::RecordInvalid => e
    @idea = @assessment.idea
    @handler = handler
    @ai_scores = ai_suggestion_scores
    flash.now[:alert] = e.record.errors.full_messages.to_sentence
    render :new, status: :unprocessable_content
  end

  private

  def set_context
    @challenge = policy_scope(Challenge).find_by!(slug: params[:challenge_id])
    @step = @challenge.steps.find(params[:step_id])
  end

  def handler = @handler ||= @step.handler

  # Por `policy_scope`: se resuelve dentro de `existing_assessment`, ANTES del
  # `authorize`, así que a quien participa una idea ajena le daba 403 y un id
  # inexistente 404 — y esa diferencia confirma que existe.
  def idea = @idea_record ||= policy_scope(@challenge.ideas).find(params[:idea_id])

  def existing_assessment
    @step.assessments.current.find_by(idea_id: idea.id, evaluator_id: current_user.id)
  end

  def build_assessment
    @step.assessments.new(idea: idea, evaluator: current_user,
                          idea_version_id: idea.current_version_id, actor_type: "human")
  end

  # Lo que la IA puso en cada criterio, para guiar a quien evalúa: el valor y
  # el porqué, mostrados JUNTO al criterio en vez de en un bloque aparte que
  # hay que copiar a mano.
  def ai_suggestion_scores
    ai = @step.assessments.current.submitted_ones
              .includes(:assessment_scores)
              .detect { |a| a.idea_id == idea.id && a.by_ai? }
    return {} if ai.nil?

    @ai_assessment = ai
    ai.assessment_scores.index_by(&:criterion_key)
  end

  attr_reader :ai_assessment

  def entry_for(idea_id)
    StepEntry.find_or_create_by!(challenge_step_id: @step.id, idea_id: idea_id) do |e|
      e.entered_at = Time.current
    end
  end

  # Solo se escriben los criterios del SNAPSHOT del módulo: una clave que no
  # está congelada ahí se descarta.
  def write_scores!
    submitted = params.fetch(:scores, {}).permit!.to_h
    comments = params.fetch(:comments, {}).permit!.to_h

    handler.scored_criteria.each do |config|
      criterion = Criterion.find_by(id: config["id"])
      raw = submitted[config["key"]]
      numeric, normalized = criterion ? criterion.score(raw) : [nil, nil]

      score = @assessment.assessment_scores.find_or_initialize_by(criterion_key: config["key"])
      score.assign_attributes(
        criterion_id: config["id"], weight_used: config["weight"],
        raw_value: raw.presence&.to_s, numeric_value: numeric,
        normalized_value: normalized, comment: comments[config["key"]].presence
      )
      score.save!
    end
  end
end
