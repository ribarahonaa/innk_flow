# frozen_string_literal: true

module ApplicationHelper
  # Lo que dejó el último pedido a la IA, listo para el popup de respuesta.
  #
  # La propuesta se busca ACÁ y no en un controller porque el partial se
  # renderiza también desde el layout, donde no hay ivar que valga: el layout
  # lo sirven las treinta pantallas y ninguna sabe de esto.
  #
  # Por `find_by` y no `find`: entre el redirect y este render alguien pudo
  # descartarla desde otra pestaña, y el popup igual tiene que poder decir qué
  # pasó en vez de tirar un 404 sobre una pantalla que está bien.
  def respuesta_de_ia
    # Las pantallas de 404 y 403 se renderizan DESPUÉS del `Current.reset` del
    # around_action —`rescue_from` corre afuera de la cadena de callbacks—, así
    # que ahí no hay tenant. Si el flash trae una propuesta pendiente, buscarla
    # es una consulta del dominio: sin este guard, cualquier 404 con un pedido
    # de IA de por medio revienta con MissingTenant al pintar el error, y el
    # mismo `rescue_from` que pinta el 404 lo vuelve a agarrar. Y una pantalla
    # de error tampoco tiene una respuesta de la IA que mostrar: no llegaste a
    # ninguna parte.
    #
    # Pregunta por `Current.company` y no por el `current_company` del
    # controller a propósito: lo que hay que saber es si la consulta que viene
    # abajo puede correr, y eso lo decide el mismo lugar que mira el
    # `default_scope` de TenantScoped.
    return nil if Current.company.nil?

    datos = flash[:ia]
    return nil if datos.blank?

    id = datos["sugerencia_id"]
    { tipo: datos["tipo"], mensaje: datos["mensaje"],
      sugerencia: id.present? ? AiSuggestion.find_by(id: id) : nil }
  end

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
  #
  # Una tarea informativa no cambia nada en ningún modo: el runner la corre
  # siempre asistida, y su resultado aparece en el marco.
  def marco_para_pedido_de_ia(purpose, mode)
    tarea = Flow::AI::Tasks::Base.for(purpose)
    return "ai-suggestions" if tarea.informativa?
    return "_top" if mode == "ai_auto" || tarea.applies_on_request?

    "ai-suggestions"
  rescue ArgumentError
    "ai-suggestions"
  end

  # Las filas de «cómo quedó configurado»: `[etiqueta, valor legible]` por cada
  # campo del esquema que tenga algo que decir sobre este módulo.
  #
  # Sobre `Flow::StepSettings.efectivo` y no sobre `step.settings` a secas:
  # `settings` sólo trae lo que alguien escribió, y ni las plantillas ni el
  # seed escriben todo. Con el hueco leído como ausencia, evolución y
  # reportería servían la tarjeta entera vacía —«Cómo quedó configurado»
  # arriba de un `<ul>` sin ningún `<li>`—, que es justo el control fantasma
  # que esta rama existe para sacar.
  def resumen_de_configuracion(step)
    efectivo = Flow::StepSettings.efectivo(step.kind, step.settings)

    Flow::StepSettings.fields(step.kind).filter_map do |campo|
      next unless Flow::StepSettings.visible?(campo, efectivo)

      valor = valor_de_campo(step, campo, efectivo)
      next if valor.blank?

      [campo[:label], valor]
    end
  end

  # `column: true` no vive en `config`: es una columna con su propia asociación
  # (`source_step_id` → `source_step`), y lo que se muestra es su nombre, no el
  # id crudo. Por eso lo resuelve la vista y no `Flow::StepSettings`, que no
  # tiene el step a mano.
  def valor_de_campo(step, campo, efectivo)
    return step.public_send(campo[:key].to_s.sub(/_id\z/, ""))&.name if campo[:column]

    crudo = Flow::StepSettings.read(efectivo, campo[:key])
    return nil if crudo.nil? || crudo == ""

    Flow::StepSettings.display_value(campo, crudo)
  end
end
