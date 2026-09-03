# frozen_string_literal: true

# Revisión humana de lo que propone la IA.
#
# Aceptar acá y la auto-aceptación del modo `ai_auto` corren exactamente el
# mismo `task.apply!`: un solo camino de escritura al dominio.
class AiSuggestionsController < ApplicationController
  before_action :set_suggestion

  def accept
    authorize @suggestion, :accept?
    result = Flow::AI::ApplySuggestion.new(@suggestion, user: current_user, payload: edited_payload).call

    redirect_back_to_target(
      notice: result.ok? ? "Sugerencia aplicada." : nil,
      alert: result.ok? ? nil : result.error_sentence
    )
  end

  def reject
    authorize @suggestion, :reject?
    Flow::AI::ApplySuggestion.new(@suggestion, user: current_user).reject!(note: params[:note])
    redirect_back_to_target(notice: "Sugerencia descartada.")
  end

  private

  def set_suggestion
    @suggestion = AiSuggestion.find(params[:id])
  end

  # Editar antes de aceptar: la sugerencia queda con status "edited" y el
  # payload que realmente se aplicó, no el que propuso el modelo.
  def edited_payload
    return nil if params[:payload].blank?

    params.require(:payload).permit!.to_h
  end

  # Vuelve a donde se pidió la propuesta, no a donde "vive" el objetivo.
  #
  # Los campos del formulario cuelgan de un módulo, así que por tipo de
  # objetivo esto mandaba a la pantalla del módulo — sacándote del formulario
  # que estabas editando justo cuando aceptabas los campos nuevos.
  PATHS_BY_PURPOSE = {
    "suggest_form_fields" => ->(s, r) { r.challenge_form_path(s.challenge_step.challenge) }
  }.freeze

  def redirect_back_to_target(notice: nil, alert: nil)
    redirect_to path_for(@suggestion), notice: notice, alert: alert
  end

  def path_for(suggestion)
    routes = Rails.application.routes.url_helpers
    by_purpose = PATHS_BY_PURPOSE[suggestion.purpose]
    return by_purpose.call(suggestion, routes) if by_purpose

    target = suggestion.idea || suggestion.challenge_step || suggestion.challenge
    case target
    when Idea then challenge_idea_path(target.challenge, target)
    when ChallengeStep then challenge_step_path(target.challenge, target)
    when Challenge then challenge_path(target)
    else root_path
    end
  end
end
