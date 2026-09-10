# frozen_string_literal: true

# El payload con el que se serializa un campo del formulario para la isla
# `form-editor`.
#
# Vivía como método privado de `FormFieldsController`, cuando la pantalla era
# propia. El editor se embebió en `steps/_campos_editor` (task «configurar vs
# ejecutar»), y un partial no llega a un método privado del controller: de ahí
# que se mude acá.
module FormFieldsHelper
  def form_field_json(field)
    { id: field.id, key: field.key, label: field.label, hint: field.hint,
      fieldType: field.field_type, required: field.required,
      isTitle: field.title?, options: field.options, answered: field.answered_count }
  end
end
