# frozen_string_literal: true

# Dispara una tarea de IA. Siempre síncrono desde la UI para que la maqueta se
# sienta inmediata; en producción con un proveedor real esto encola
# Flow::AI::RunJob y la pantalla hace polling.
class AiRequestsController < ApplicationController
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

    flash[:ia] = respuesta_de_ia(result)
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

  # Lo que el popup de respuesta va a decir.
  #
  # Un hash y no un `notice`: el popup necesita saber si salió bien o mal y,
  # cuando quedó algo por revisar, cuál es la propuesta. Además el `notice` se
  # perdía en los pedidos que responden al marco, porque el layout lo pinta
  # AFUERA del marco y Turbo se queda sólo con el marco.
  #
  # Las claves van en STRING a propósito: el flash viaja en la cookie de
  # sesión serializado a JSON, así que un símbolo vuelve como string y
  # `flash[:ia][:tipo]` sería `nil` del otro lado del redirect.
  #
  # `sugerencia_id` sólo cuando la propuesta quedó PENDIENTE: una ya aceptada
  # no tiene nada que revisar, y ofrecerle «Aplicar» a lo que ya se aplicó es
  # el control fantasma que estamos sacando.
  def respuesta_de_ia(result)
    {
      "tipo" => result.ok? ? "ok" : "error",
      "mensaje" => result.ok? ? success_message(result) : error_message(result),
      "sugerencia_id" => (result.suggestion&.id if result.suggestion&.pending?)
    }
  end

  # La IA respondió y el dominio rechazó lo que propuso: son dos cosas
  # distintas y antes se decían igual. «No pudo responder» era falso, y encima
  # escondía que había una propuesta pendiente esperando a una persona.
  def error_message(result)
    return "La IA respondió, pero no se pudo aplicar: #{result.error_sentence}" if result.suggestion

    "La IA no pudo responder: #{result.error_sentence}"
  end

  def success_message(result)
    return "Listo: la evaluación de la IA ya está en la lista." if result.run&.purpose == "evaluate_idea"
    return "La IA respondió y se aplicó automáticamente." if result.suggestion&.accepted?

    # Un pedido repetido mientras la propuesta anterior sigue sin revisar no
    # llama de nuevo al proveedor: se dice con todas las letras, en vez de
    # anunciar una respuesta nueva que no existe.
    return "Ya había una propuesta esperando tu revisión." if result.reused?

    "La IA respondió. Revisá la propuesta antes de aplicarla."
  end
end
