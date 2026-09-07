# frozen_string_literal: true

# Dispara una tarea de IA. Siempre síncrono desde la UI para que la maqueta se
# sienta inmediata; en producción con un proveedor real esto encola
# Flow::AI::RunJob y la pantalla hace polling.
class AiRequestsController < ApplicationController
  # Qué tareas actúan sobre UNA IDEA y no sobre el desafío. Quien puede editar
  # esa idea puede pedirlas: su autor, además de quien administra.
  #
  # Antes todo pedido exigía `update_pipeline?`, que es solo administración, así
  # que quien participa no podía usar ninguna función de IA — ni siquiera sobre
  # su propia idea, con el botón ahí ofreciéndoselo.
  SOBRE_LA_IDEA = %w[coauthor_field evolve_idea detect_duplicates].freeze

  def create
    @challenge = policy_scope(Challenge).find_by!(slug: params[:challenge_id])
    context = build_context
    autorizar!(context)

    task = Flow::AI::Tasks::Base.for(params[:purpose], **context)

    result = Flow::AI::Runner.call(
      task,
      mode: resolved_mode(context, task),
      requested_by: current_user,
      challenge: @challenge, step: context[:step], idea: context[:idea]
    )

    redirect_back fallback_location: challenge_path(@challenge),
                  notice: result.ok? ? success_message(result) : nil,
                  alert: result.ok? ? nil : "La IA no pudo responder: #{result.error_sentence}"
  rescue ArgumentError => e
    redirect_back fallback_location: challenge_path(@challenge), alert: e.message
  end

  private

  def autorizar!(context)
    idea = context[:idea]
    return authorize(idea, :update?) if SOBRE_LA_IDEA.include?(params[:purpose]) && idea

    authorize @challenge, :update_pipeline?
  end

  def build_context
    step = params[:step_id].present? ? @challenge.steps.find(params[:step_id]) : nil
    idea = params[:idea_id].present? ? @challenge.ideas.find(params[:idea_id]) : nil
    field = params[:field_key].present? ? step&.form_fields&.find_by(key: params[:field_key]) : nil

    { challenge: @challenge, step: step, idea: idea, field: field,
      count: params[:count].presence&.to_i }.compact
  end

  # El modo efectivo del módulo manda; si la tarea no cuelga de un módulo
  # (proponer el pipeline, p.ej.), manda el default del desafío. `human` no
  # llega hasta acá salvo para las acciones de autoría: la UI no ofrece el
  # botón dentro de un módulo en modo human.
  #
  # Las tareas aditivas se aplican al pedirlas: el clic ya es la decisión.
  def resolved_mode(context, task)
    return "ai_auto" if task.applies_on_request?

    mode = context[:step]&.effective_ai_mode || @challenge.ai_default_mode
    mode == "human" ? "ai_assisted" : mode
  end

  def success_message(result)
    return "Listo: la evaluación de la IA ya está en la lista." if result.run&.purpose == "evaluate_idea"
    return "La IA respondió y se aplicó automáticamente." if result.suggestion&.accepted?

    # Un pedido repetido mientras la propuesta anterior sigue sin revisar no
    # llama de nuevo al proveedor: se dice con todas las letras, en vez de
    # anunciar una respuesta nueva que no existe.
    return "Ya hay una propuesta esperando tu revisión más abajo." if result.reused?

    "La IA respondió. Revisá la propuesta antes de aplicarla."
  end
end
