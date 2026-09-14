# frozen_string_literal: true

# Qué deja un pedido a la IA para que los popups lo cuenten, y en qué modo corre.
#
# Vive acá y no en un controller porque hay DOS lugares que corren una tarea de
# IA de forma síncrona: los botones de siempre (`AiRequestsController`) y crear
# un desafío con «Que lo proponga la IA» (`ChallengesController#create`). La
# tabla de qué decir en cada desenlace es UNA, y este repo ya pagó dos veces el
# precio de copiarla: la de quién puede aceptar una propuesta divergió entre el
# controller y la policy, y la segunda vez dejó aplicar sobre un desafío
# cerrado algo que ya no se podía pedir.
module RespuestaDeIa
  extend ActiveSupport::Concern

  private

  # Un hash y no un `notice`: el popup necesita saber si salió bien o mal y,
  # cuando quedó algo por revisar, cuál es la propuesta. Además el `notice` se
  # perdía en los pedidos que responden al marco, porque el layout lo pinta
  # AFUERA del marco y Turbo se queda sólo con el marco.
  #
  # Las claves van en STRING a propósito: el flash viaja en la cookie de sesión
  # serializado a JSON, así que un símbolo vuelve como string y
  # `flash[:ia][:tipo]` sería `nil` del otro lado del redirect.
  #
  # `sugerencia_id` sólo cuando la propuesta quedó PENDIENTE: una ya aceptada no
  # tiene nada que revisar, y ofrecerle «Aplicar» a lo que ya se aplicó es el
  # control fantasma que estamos sacando.
  def flash_de_ia(result)
    {
      "tipo" => result.ok? ? "ok" : "error",
      "mensaje" => result.ok? ? mensaje_de_exito(result) : mensaje_de_error(result),
      "sugerencia_id" => (result.suggestion&.id if result.suggestion&.pending?)
    }
  end

  # La IA respondió y el dominio rechazó lo que propuso: son dos cosas distintas
  # y antes se decían igual. «No pudo responder» era falso, y encima escondía
  # que había una propuesta pendiente esperando a una persona.
  def mensaje_de_error(result)
    return "La IA respondió, pero no se pudo aplicar: #{result.error_sentence}" if result.suggestion

    "La IA no pudo responder: #{result.error_sentence}"
  end

  def mensaje_de_exito(result)
    return "Listo: la evaluación de la IA ya está en la lista." if result.run&.purpose == "evaluate_idea"
    return "La IA respondió y se aplicó automáticamente." if result.suggestion&.accepted?

    # Un pedido repetido mientras la propuesta anterior sigue sin revisar no
    # llama de nuevo al proveedor: se dice con todas las letras, en vez de
    # anunciar una respuesta nueva que no existe.
    return "Ya había una propuesta esperando tu revisión." if result.reused?

    "La IA respondió. Revisá la propuesta antes de aplicarla."
  end

  # El modo efectivo del módulo manda; si la tarea no cuelga de un módulo
  # (proponer el pipeline, p.ej.), manda el default del desafío.
  #
  # `human` no sobrevive acá: quien apretó el botón —o eligió «Que lo proponga
  # la IA» al crear el desafío— está pidiendo justamente que la IA proponga.
  # «Solo personas» define cómo se trabaja DENTRO del desafío, no si su dueño
  # puede pedir una mano para diseñarlo.
  #
  # Las tareas aditivas se aplican al pedirlas: el clic ya es la decisión.
  def modo_de_ia(task, challenge:, step: nil)
    return "ai_auto" if task.applies_on_request?

    mode = step&.effective_ai_mode || challenge.ai_default_mode
    mode == "human" ? "ai_assisted" : mode
  end
end
