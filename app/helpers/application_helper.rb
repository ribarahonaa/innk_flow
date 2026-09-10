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
