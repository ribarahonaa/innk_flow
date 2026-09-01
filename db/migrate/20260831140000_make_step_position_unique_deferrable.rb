# frozen_string_literal: true

# Reordenar el pipeline reescribe varias posiciones dentro de una transacción,
# y en los estados intermedios dos steps comparten posición un instante.
#
# Un UNIQUE INDEX se chequea fila por fila y revienta ahí:
#   duplicate key value violates unique constraint ... Key (challenge_id, position)=(..., 2.0)
#
# Un UNIQUE CONSTRAINT DEFERRABLE INITIALLY DEFERRED se chequea recién en el
# COMMIT, que es cuando el orden ya es coherente. Postgres solo admite
# DEFERRABLE en constraints, no en índices — por eso el swap.
class MakeStepPositionUniqueDeferrable < ActiveRecord::Migration[7.1]
  def up
    remove_index :challenge_steps, %i[challenge_id position]
    execute <<~SQL.squish
      ALTER TABLE challenge_steps
        ADD CONSTRAINT challenge_steps_position_unique
        UNIQUE (challenge_id, position) DEFERRABLE INITIALLY DEFERRED
    SQL
  end

  def down
    execute "ALTER TABLE challenge_steps DROP CONSTRAINT IF EXISTS challenge_steps_position_unique"
    add_index :challenge_steps, %i[challenge_id position], unique: true
  end
end
