# frozen_string_literal: true

# Log INMUTABLE de eventos de selección.
#
# `selection_decisions` es la fuente de verdad; `ideas.status` y
# `step_entries.status` son proyecciones. Un solo escritor las mantiene en
# sincronía: Handlers::Selection#complete!, en una transacción.
class CreateSelectionDecisions < ActiveRecord::Migration[7.1]
  OUTCOMES = %w[advance eliminate reinstate].freeze
  ACTOR_TYPES = %w[human ai].freeze

  def change
    tenant_table :selection_decisions do |t|
      t.references :challenge_step, null: false, type: :uuid, index: true
      t.references :idea, null: false, type: :uuid, index: true
      # Qué versión de la idea se estaba mirando al decidir.
      t.uuid :idea_version_id, null: false
      t.string :outcome, null: false
      t.integer :rank
      t.decimal :score, precision: 10, scale: 6
      t.references :decided_by, type: :uuid, index: true
      t.string :actor_type, null: false, default: "human"
      t.text :reason
      t.datetime :decided_at, null: false
      t.timestamps
    end
    add_tenant_fk :selection_decisions, :challenge_steps, column: :challenge_step_id
    add_tenant_fk :selection_decisions, :ideas, column: :idea_id
    add_tenant_fk :selection_decisions, :idea_versions, column: :idea_version_id
    add_foreign_key :selection_decisions, :users, column: :decided_by_id
    add_index :selection_decisions, %i[challenge_step_id idea_id decided_at]
    add_check :selection_decisions, :outcome, OUTCOMES
    add_check :selection_decisions, :actor_type, ACTOR_TYPES
  end

  private

  def add_check(table, column, values)
    list = values.map { |v| "'#{v}'" }.join(", ")
    reversible do |dir|
      dir.up { execute "ALTER TABLE #{table} ADD CONSTRAINT #{table}_#{column}_check CHECK (#{column} IN (#{list}))" }
      dir.down { execute "ALTER TABLE #{table} DROP CONSTRAINT IF EXISTS #{table}_#{column}_check" }
    end
  end
end
