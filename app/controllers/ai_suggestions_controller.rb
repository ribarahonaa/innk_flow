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

  def redirect_back_to_target(notice: nil, alert: nil)
    target = @suggestion.idea || @suggestion.challenge_step || @suggestion.challenge
    path = case target
           when Idea then challenge_idea_path(target.challenge, target)
           when ChallengeStep then challenge_step_path(target.challenge, target)
           when Challenge then challenge_path(target)
           else root_path
           end
    redirect_to path, notice: notice, alert: alert
  end
end
