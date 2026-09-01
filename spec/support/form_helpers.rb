# frozen_string_literal: true

module FormHelpers
  # Las mismas preguntas que antes se sembraban solas al activar el módulo.
  # Ahora las define su dueño, así que en los specs las pone esto.
  FORM = {
    "titulo" => ["Título", "text"],
    "problema" => ["¿Qué problema resuelve?", "textarea"],
    "solucion" => ["¿Cómo funcionaría?", "textarea"]
  }.freeze

  # Un módulo de ideación SIN formulario no valida ni arranca: sin preguntas
  # nadie puede postular una idea. Los specs que no están probando el
  # formulario en sí le ponen el mínimo con esto.
  def seed_form!(step, keys: FORM.keys)
    keys.each_with_index do |key, index|
      label, type = FORM.fetch(key, [key.humanize, "text"])
      step.form_fields.create!(
        key: key, label: label, field_type: type, position: index, required: true,
        config: index.zero? ? { "is_title" => true } : {}
      )
    end
    step
  end
end

RSpec.configure { |config| config.include FormHelpers }
