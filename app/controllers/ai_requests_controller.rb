# frozen_string_literal: true

# Dispara una tarea de IA. SÍNCRONO, y eso es lo que hace posible los dos
# popups: el de espera se abre al enviar y el de respuesta lee el `flash[:ia]`
# que deja el redirect. Encolarlo dejaría a la pantalla sin nada que contar
# hasta que alguien recargara —que es exactamente lo que pasaba al crear un
# desafío con «Que lo proponga la IA» antes de que ése también se hiciera
# síncrono (`ChallengesController#proponer_flujo_con_ia`)—.
#
# Los `Flow::AI::RunJob.perform_later` que quedan son los de los handlers, que
# disparan solos al activarse un módulo: ahí no hay nadie esperando.
class AiRequestsController < ApplicationController
  include RespuestaDeIa

  def create
    @challenge = policy_scope(Challenge).find_by!(slug: params[:challenge_id])
    context = build_context
    autorizar!(context)

    task = Flow::AI::Tasks::Base.for(params[:purpose], **context)

    result = Flow::AI::Runner.call(
      task,
      mode: modo_de_ia(task, challenge: @challenge, step: context[:step]),
      requested_by: current_user,
      challenge: @challenge, step: context[:step], idea: context[:idea]
    )

    flash[:ia] = flash_de_ia(result)
    redirect_back fallback_location: challenge_path(@challenge)
  rescue ArgumentError => e
    flash[:ia] = { "tipo" => "error", "mensaje" => e.message, "sugerencia_id" => nil }
    redirect_back fallback_location: challenge_path(@challenge)
  end

  private

  # Quién puede pedir cada tarea depende de sobre qué actúa, y eso lo declara
  # la tarea. Antes todo exigía `update_pipeline?` —solo administración—, así
  # que quien participa no podía usar ninguna función de IA sobre su propia
  # idea, y quien acompaña no podía pedir el feedback que es su trabajo.
  #
  # La regla vive en `AiSuggestionPolicy`: pedir es preguntar si podrías
  # revisar lo que la IA va a proponer. Estuvo escrita acá también, y las
  # dos copias divergieron.
  #
  # Se le pregunta con una propuesta de mentira armada con lo que trae el
  # pedido. Nunca se guarda —tiene los tres objetivos a la vez, y una de
  # verdad tiene uno—; el propósito viaja en su `AiRun` porque
  # `AiSuggestion#purpose` delega ahí.
  def autorizar!(context)
    pedido = AiSuggestion.new(ai_run: AiRun.new(purpose: params[:purpose]), challenge: @challenge,
                              challenge_step: context[:step], idea: context[:idea])
    authorize pedido, :request?
  end

  def build_context
    step = params[:step_id].present? ? @challenge.steps.find(params[:step_id]) : nil
    # Por `policy_scope`: el contexto se arma ANTES de `autorizar!`, así que a
    # quien participa una idea ajena le daba 403 y un id inexistente 404 — y
    # esa diferencia confirma que existe.
    idea = params[:idea_id].present? ? policy_scope(@challenge.ideas).find(params[:idea_id]) : nil
    field = params[:field_key].present? ? step&.form_fields&.find_by(key: params[:field_key]) : nil

    { challenge: @challenge, step: step, idea: idea, field: field,
      count: params[:count].presence&.to_i }.compact
  end
end
