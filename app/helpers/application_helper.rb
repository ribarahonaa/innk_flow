# frozen_string_literal: true

module ApplicationHelper
  # A qué marco tiene que responder un pedido a la IA.
  #
  # Por defecto al de las propuestas: la respuesta reemplaza ese marco y nada
  # más, así pedir algo no recarga la pantalla ni pierde lo que estuvieras
  # editando.
  #
  # Pero hay dos casos donde el pedido YA cambió el dominio: en «IA automática»
  # la sugerencia se auto-acepta, y las tareas aditivas se aplican al pedirlas.
  # Ahí refrescar solo el marco deja el resto de la pantalla mostrando lo
  # viejo — la idea reescrita se seguía viendo como estaba hasta recargar a
  # mano.
  def marco_para_pedido_de_ia(purpose, mode)
    return "_top" if mode == "ai_auto"
    return "_top" if Flow::AI::Tasks::Base.for(purpose).applies_on_request?

    "ai-suggestions"
  rescue ArgumentError
    "ai-suggestions"
  end
end
