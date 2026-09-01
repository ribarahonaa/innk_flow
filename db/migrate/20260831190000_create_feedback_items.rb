# frozen_string_literal: true

# Feedback sobre una idea dentro de un módulo de evolución.
#
# Anclado a la versión que se leyó: un comentario sobre v2 no queda huérfano
# cuando el autor publica v3 — queda fechado, y la UI puede decir si ya fue
# atendido por una versión posterior.
class CreateFeedbackItems < ActiveRecord::Migration[7.1]
  KINDS = %w[suggestion question issue].freeze
  ACTOR_TYPES = %w[human ai].freeze

  def change
    tenant_table :feedback_items do |t|
      t.references :challenge_step, null: false, type: :uuid, index: true
      t.references :idea, null: false, type: :uuid, index: true
      t.uuid :idea_version_id, null: false
      t.references :author, type: :uuid, index: true
      t.string :actor_type, null: false, default: "human"
      t.string :kind, null: false, default: "suggestion"
      t.text :body, null: false
      t.boolean :addressed, null: false, default: false
      # Qué versión respondió este feedback.
      t.uuid :addressed_by_version_id
      t.uuid :ai_run_id
      t.timestamps
    end
    add_tenant_fk :feedback_items, :challenge_steps, column: :challenge_step_id
    add_tenant_fk :feedback_items, :ideas, column: :idea_id
    add_tenant_fk :feedback_items, :idea_versions, column: :idea_version_id
    add_tenant_fk :feedback_items, :idea_versions, column: :addressed_by_version_id, on_delete: :nullify
    add_tenant_fk :feedback_items, :ai_runs, column: :ai_run_id, on_delete: :nullify
    add_foreign_key :feedback_items, :users, column: :author_id
    add_index :feedback_items, %i[idea_id addressed]
    add_check :feedback_items, :kind, KINDS
    add_check :feedback_items, :actor_type, ACTOR_TYPES
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
