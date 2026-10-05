# frozen_string_literal: true

module ApplicationHelper
  # El tema elegido a mano, o `nil` si no hay ninguno.
  #
  # `nil` es la respuesta importante: los dos layouts lo pasan como valor de
  # `data: { theme: ... }` y HAML OMITE el atributo cuando es nil. Sin atributo,
  # `:root:not([data-theme])` matchea y `prefersdark` sigue vivo. Cualquier
  # cosa fuera de la lista blanca se trata como ausente, no como error.
  def tema_elegido
    valor = cookies[:theme]
    valor if Flow::Themes::NAMES.include?(valor)
  end

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
    return "ai-suggestions" if Flow::AI::Tasks::Base.informativa?(purpose)
    return "_top" if mode == "ai_auto" || Flow::AI::Tasks::Base.aplica_al_pedirse?(purpose)

    "ai-suggestions"
  end

  # ¿Se le ofrece «Saltear» a esta persona sobre este módulo?
  #
  # Son DOS preguntas y no una, y por eso vive acá y no en la policy:
  # `ChallengeStepPolicy#skip?` es `administers?` a secas y su propio
  # comentario dice por qué —«dice que sí también sobre un módulo completado;
  # el botón tiene que preguntar además por el estado, no duplicarse el
  # predicado acá»—. Quien decide de verdad sobre el estado es
  # `Handlers::Base#skip!`, que se niega sobre uno `completed` o `skipped`:
  # sin esa mitad el botón aparecía igual y el `alert` del controller era el
  # que lo contaba, que es el control-que-no-responde de siempre.
  #
  # `running?` es la segunda mitad y espeja la otra negativa de `skip!`: fuera
  # del flujo en curso no se saltea. La regla es de `skip!` —acá se pregunta
  # para no dibujar un control que va a rebotar, no para decidir—, y está ahí
  # porque sobre un BORRADOR el salteo se guardaba y `continue!` se negaba,
  # dejando un módulo `skipped` que `activate!` no vuelve a tocar nunca
  # —devuelve sin hacer nada sobre uno ya tocado—: si era el primero del flujo,
  # `start!` abría el desafío sin NINGÚN módulo activo.
  #
  # UNA definición, consultada dos veces por pantalla —el resumen del plegable
  # y el bloque—: escrita en cada vista, las dos mitades divergen.
  # De dónde viene un set de criterios, para el breadcrumb.
  #
  # Uno de biblioteca viene del índice. Uno `inline` es de UN módulo, y el índice
  # lista `.library.current`: volver ahí dejaba a quien lo estaba editando en una
  # lista donde su set no está ni puede estar. Y editar uno inline se ofrece de
  # verdad —`steps/_como_se_decide` linkea «Editar el set» para cualquiera que se
  # pueda editar, no sólo los de biblioteca—.
  #
  # UNA definición porque la misma línea está en `edit` y en `show`.
  def origen_del_set(set)
    return link_to("Criterios", criteria_sets_path) if set.library? || set.owner_step.nil?

    paso = set.owner_step
    link_to(paso.name, challenge_step_path(paso.challenge, paso))
  end

  def puede_saltear?(step)
    policy(step).skip? && step.challenge.running? && !step.completed? && !step.skipped?
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
