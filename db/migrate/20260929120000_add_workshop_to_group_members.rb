# frozen_string_literal: true

# «Una persona, una mesa por taller» es LA invariante de la que cuelga toda la
# visibilidad del taller: la mesa es la unidad, y alguien en dos mesas la parte
# en dos. La respaldaba sólo una validación de modelo —un `exists?` seguido de
# un `save`—, que dos convocatorias concurrentes atraviesan.
#
# El índice que hacía falta no se podía escribir: la columna no estaba en la
# tabla. `UNIQUE (workshop_group_id, user_id)` dice «una fila por mesa y
# persona», que no es la invariante. Por eso se desnormaliza `workshop_id`,
# derivado SIEMPRE de `workshop_groups.workshop_id` (ver el modelo).
#
# De paso, los índices que faltaban en columnas de FK con ON DELETE CASCADE:
# sin ellos, borrar un desafío o una mesa hace seq scan.
class AddWorkshopToGroupMembers < ActiveRecord::Migration[7.1]
  include Flow::MigrationHelpers

  def up
    add_column :workshop_group_members, :workshop_id, :uuid

    execute <<~SQL.squish
      UPDATE workshop_group_members m
         SET workshop_id = g.workshop_id
        FROM workshop_groups g
       WHERE g.id = m.workshop_group_id
    SQL

    change_column_null :workshop_group_members, :workshop_id, false
    add_index :workshop_group_members, %i[workshop_id user_id], unique: true
    add_tenant_fk :workshop_group_members, :workshops, column: :workshop_id

    add_index :workshop_proposals,  :workshop_group_id
    add_index :workshop_proposals,  :challenge_step_id
    add_index :workshop_challenges, :challenge_step_id
    add_index :workshop_challenges, :challenge_id
  end

  def down
    remove_index :workshop_challenges, :challenge_id
    remove_index :workshop_challenges, :challenge_step_id
    remove_index :workshop_proposals,  :challenge_step_id
    remove_index :workshop_proposals,  :workshop_group_id

    remove_tenant_fk :workshop_group_members, column: :workshop_id
    remove_index :workshop_group_members, %i[workshop_id user_id]
    remove_column :workshop_group_members, :workshop_id
  end
end
