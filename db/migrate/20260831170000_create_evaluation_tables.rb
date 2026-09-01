# frozen_string_literal: true

# Evaluación: criterios reusables, escalas heterogéneas y notas por evaluador.
class CreateEvaluationTables < ActiveRecord::Migration[7.1]
  SCOPES = %w[library inline].freeze
  SET_STATUSES = %w[draft valid invalid].freeze
  SCALE_TYPES = %w[numeric letter rubric formula].freeze
  ACTOR_TYPES = %w[human ai].freeze
  ASSESSMENT_STATUSES = %w[pending submitted].freeze
  ASSIGNMENT_ROLES = %w[evaluator jury].freeze

  def change
    # ── Criterios reusables por empresa ──────────────────────────────────
    #
    # `library` = mantenedor de la empresa. `inline` = criterios ad-hoc que el
    # dueño armó dentro de un módulo. MISMA TABLA, un flag: dos code paths
    # para lo mismo se desincronizan.
    tenant_table :criteria_sets do |t|
      t.string :name, null: false
      t.text :description
      t.string :scope, null: false, default: "library"
      t.uuid :owner_step_id
      t.string :status, null: false, default: "draft"
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_tenant_fk :criteria_sets, :challenge_steps, column: :owner_step_id, on_delete: :cascade
    add_check :criteria_sets, :scope, SCOPES
    add_check :criteria_sets, :status, SET_STATUSES

    tenant_table :criteria do |t|
      t.references :criteria_set, null: false, type: :uuid, index: true
      # Las fórmulas referencian `key`, nunca el nombre (que es editable e
      # i18n-able) ni el id.
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.decimal :weight, precision: 8, scale: 6, null: false, default: 0
      t.string :scale_type, null: false, default: "numeric"
      t.jsonb :scale_config, null: false, default: {}
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_tenant_fk :criteria, :criteria_sets, column: :criteria_set_id
    add_index :criteria, %i[criteria_set_id key], unique: true
    add_check :criteria, :scale_type, SCALE_TYPES

    add_column :challenge_steps, :criteria_set_id, :uuid
    add_index :challenge_steps, :criteria_set_id
    add_tenant_fk :challenge_steps, :criteria_sets, column: :criteria_set_id, on_delete: :nullify

    # ── Quién evalúa qué ─────────────────────────────────────────────────
    tenant_table :step_assignments do |t|
      t.references :challenge_step, null: false, type: :uuid, index: true
      t.references :user, null: false, type: :uuid, index: true
      t.string :role, null: false, default: "evaluator"
      t.decimal :weight, precision: 8, scale: 6
      t.timestamps
    end
    add_tenant_fk :step_assignments, :challenge_steps, column: :challenge_step_id
    add_foreign_key :step_assignments, :users, column: :user_id
    add_index :step_assignments, %i[challenge_step_id user_id], unique: true
    add_check :step_assignments, :role, ASSIGNMENT_ROLES

    # ── Una evaluación de una idea por un evaluador ──────────────────────
    tenant_table :assessments do |t|
      t.references :challenge_step, null: false, type: :uuid, index: true
      t.references :idea, null: false, type: :uuid, index: true
      # NOT NULL a propósito: una nota siempre dice qué VERSIÓN juzgó. Cuando
      # una ronda de evolución genera v3, la nota sobre v2 no queda huérfana
      # sino anclada, y la UI la puede marcar como desactualizada.
      t.uuid :idea_version_id, null: false
      t.references :evaluator, type: :uuid, index: true
      t.string :actor_type, null: false, default: "human"
      t.string :status, null: false, default: "pending"
      t.uuid :ai_run_id
      t.text :overall_comment
      t.decimal :normalized_score, precision: 10, scale: 6
      t.decimal :raw_score, precision: 10, scale: 4
      t.datetime :submitted_at
      # Conserva la historia cuando una versión nueva obliga a re-evaluar.
      t.datetime :superseded_at
      t.timestamps
    end
    add_tenant_fk :assessments, :challenge_steps, column: :challenge_step_id
    add_tenant_fk :assessments, :ideas, column: :idea_id
    add_tenant_fk :assessments, :idea_versions, column: :idea_version_id
    add_tenant_fk :assessments, :ai_runs, column: :ai_run_id, on_delete: :nullify
    add_foreign_key :assessments, :users, column: :evaluator_id
    add_check :assessments, :actor_type, ACTOR_TYPES
    add_check :assessments, :status, ASSESSMENT_STATUSES

    # Un evaluador no evalúa dos veces la misma idea en el mismo módulo, pero
    # las evaluaciones superadas se conservan.
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          CREATE UNIQUE INDEX index_assessments_unique_human
            ON assessments (challenge_step_id, idea_id, evaluator_id)
            WHERE superseded_at IS NULL AND evaluator_id IS NOT NULL
        SQL
        execute <<~SQL.squish
          CREATE UNIQUE INDEX index_assessments_unique_ai
            ON assessments (challenge_step_id, idea_id)
            WHERE superseded_at IS NULL AND evaluator_id IS NULL
        SQL
      end
      dir.down do
        execute "DROP INDEX IF EXISTS index_assessments_unique_human"
        execute "DROP INDEX IF EXISTS index_assessments_unique_ai"
      end
    end

    # ── Nota por criterio ────────────────────────────────────────────────
    tenant_table :assessment_scores do |t|
      t.references :assessment, null: false, type: :uuid, index: true
      t.references :criterion, type: :uuid, index: true
      # key y peso CONGELADOS: editar el criteria_set después no puede
      # reescribir puntajes históricos. (En innk_r5, Objective#reset_ponderations
      # muta ponderaciones in-place y dispara un worker que recalcula promedios
      # de ideas viejas: editar un criterio hoy reescribe el año pasado.)
      t.string :criterion_key, null: false
      t.decimal :weight_used, precision: 8, scale: 6, null: false, default: 0
      t.string :raw_value
      t.decimal :numeric_value, precision: 12, scale: 4
      # Toda escala aterriza acá, en [0,1]: es lo que hace comparables una
      # nota 1-10, una letra A-F y una fórmula.
      t.decimal :normalized_value, precision: 10, scale: 6
      t.text :comment
      t.text :error
      t.timestamps
    end
    add_tenant_fk :assessment_scores, :assessments, column: :assessment_id
    add_tenant_fk :assessment_scores, :criteria, column: :criterion_id, on_delete: :nullify
    add_index :assessment_scores, %i[assessment_id criterion_key], unique: true
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
