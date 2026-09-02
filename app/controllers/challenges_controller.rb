# frozen_string_literal: true

class ChallengesController < ApplicationController
  before_action :set_challenge, only: %i[show builder start close apply_template]

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

    return render(:new, status: :unprocessable_entity) unless @challenge.save

    redirect_to builder_challenge_path(@challenge), notice: start_from(params[:template])
  end

  # Aplica una plantilla a un desafío que todavía no tiene módulos. Se ofrece
  # también desde el builder: alguien puede haber creado el desafío en blanco y
  # arrepentirse, y no tiene por qué armar seis módulos a mano por eso.
  def apply_template
    authorize @challenge, :update_pipeline?

    if Flow::FlowTemplates.apply!(@challenge, params[:template])
      redirect_to builder_challenge_path(@challenge), notice: "Flujo armado. Editalo como quieras."
    else
      redirect_to builder_challenge_path(@challenge),
                  alert: "La plantilla solo se puede aplicar a un desafío en borrador y sin módulos."
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
    @pending_suggestions = AiSuggestion.pending_review.where(challenge_id: @challenge.id).recent
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

  # El flujo inicial: una plantilla, la propuesta de la IA, o nada.
  def start_from(template)
    return "Desafío creado. Armá su flujo." if template.blank? || template == "blank"

    if template == "ai"
      Flow::AI::RunJob.perform_later(@challenge.company_id, "propose_pipeline",
                                     { "challenge_id" => @challenge.id })
      return "Desafío creado. La IA está armando una propuesta: vas a poder revisarla acá."
    end

    return "Desafío creado. Armá su flujo." unless Flow::FlowTemplates.apply!(@challenge, template)

    "Desafío creado con la plantilla «#{Flow::FlowTemplates.find(template)[:name]}». Editalo como quieras."
  end

  def set_challenge
    # Scopeado por TenantScoped: un slug de otra empresa levanta
    # RecordNotFound, que TenantResolution traduce a 404 (nunca 403).
    @challenge = Challenge.find_by!(slug: params[:id])
  end

  def challenge_params
    params.require(:challenge).permit(:name, :brief, :ai_default_mode)
  end
end
