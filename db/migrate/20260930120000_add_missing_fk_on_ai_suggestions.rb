# frozen_string_literal: true

# `ai_suggestions.criteria_set_id` era la única de sus CUATRO columnas de destino
# sin foreign key. El CHECK `ai_suggestions_single_target_check` la nombra junto
# a `challenge_id`, `challenge_step_id` e `idea_id` —exactamente una tiene que
# estar no nula—, y las otras tres tienen su FK compuesta desde el día uno.
#
# Sin FK la columna queda AFUERA de la cuarta capa de tenencia: Postgres no tiene
# con qué rechazar una propuesta de la empresa A apuntando a un set de la B. Está
# dormida —hoy ninguna tarea de IA apunta a un `criteria_set`, `SuggestCriteria`
# apunta al módulo— así que esto cierra la puerta antes de que alguien la use, no
# arregla datos.
#
# Lo encontró la guarda que se sumó con esta migración
# (`spec/tenancy/schema_spec.rb`, «toda columna que apunta a otra tabla de
# dominio tiene su FK»): las cuatro que ya existían miran FKs que EXISTEN, y
# ninguna podía ver una que falta.
#
# CASCADE como las otras tres: una propuesta cuyo objetivo ya no está no
# significa nada, y el rastro de auditoría vive en `ai_runs`.
class AddMissingFkOnAiSuggestions < ActiveRecord::Migration[7.1]
  include Flow::MigrationHelpers

  def up
    add_tenant_fk :ai_suggestions, :criteria_sets, column: :criteria_set_id
  end

  def down
    remove_tenant_fk :ai_suggestions, column: :criteria_set_id
  end
end
