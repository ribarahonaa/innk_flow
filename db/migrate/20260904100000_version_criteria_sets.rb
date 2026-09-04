# frozen_string_literal: true

# Los sets de biblioteca se comparten entre desafíos: editar uno cambiaba lo
# que iban a usar módulos que todavía no arrancaron, de desafíos que quien
# editaba quizás ni armó.
#
# En vez de prohibirlo, se versiona: editar los criterios de un set en uso crea
# la versión siguiente, y los que ya lo usaban siguen con la anterior hasta que
# alguien los mueva a mano. Nada cambia bajo los pies de nadie.
class VersionCriteriaSets < ActiveRecord::Migration[7.1]
  def up
    add_column :criteria_sets, :family_id, :uuid
    add_column :criteria_sets, :version, :integer, null: false, default: 1
    add_column :criteria_sets, :superseded_at, :datetime

    # Los sets existentes son cada uno su propia familia, versión 1.
    execute "UPDATE criteria_sets SET family_id = id"
    change_column_null :criteria_sets, :family_id, false

    add_index :criteria_sets, %i[family_id version], unique: true
    add_index :criteria_sets, :superseded_at
  end

  def down
    remove_column :criteria_sets, :family_id
    remove_column :criteria_sets, :version
    remove_column :criteria_sets, :superseded_at
  end
end
