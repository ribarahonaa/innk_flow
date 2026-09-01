# frozen_string_literal: true

# Auditoría de todo lo que hace la IA.
#
# Regla: TODA llamada al proveedor deja un ai_run, sea el adapter de fixtures
# o uno real. El rastro (prompt, costo, latencia, error) existe desde el día 1
# y cambiar de proveedor no cambia lo que se ve en /admin/ai_runs.
class CreateAiRunsAndSuggestions < ActiveRecord::Migration[7.1]
  PURPOSES = %w[
    propose_pipeline suggest_form_fields generate_ideas coauthor_field
    detect_duplicates suggest_feedback evaluate_idea summarize_challenge
  ].freeze
  MODES = %w[ai_assisted ai_auto].freeze
  RUN_STATUSES = %w[queued running succeeded failed].freeze
  SUGGESTION_STATUSES = %w[pending accepted edited rejected].freeze

  def change
    tenant_table :ai_runs do |t|
      t.references :challenge, type: :uuid, index: true
      t.references :challenge_step, type: :uuid, index: true
      t.references :idea, type: :uuid, index: true
      t.references :requested_by, type: :uuid, index: true

      t.string :purpose, null: false
      t.string :mode, null: false
      t.string :status, null: false, default: "queued"

      t.jsonb :prompt, null: false, default: {}
      t.jsonb :response
      t.string :provider
      t.string :model
      t.integer :tokens_in
      t.integer :tokens_out
      t.integer :latency_ms
      t.text :error

      # Un retry de Sidekiq no puede duplicar una llamada al LLM ni las
      # sugerencias que produce.
      t.string :idempotency_key
      t.datetime :redacted_at
      t.timestamps
    end
    add_tenant_fk :ai_runs, :challenges, column: :challenge_id
    add_tenant_fk :ai_runs, :challenge_steps, column: :challenge_step_id
    add_tenant_fk :ai_runs, :ideas, column: :idea_id
    add_foreign_key :ai_runs, :users, column: :requested_by_id
    add_index :ai_runs, %i[company_id idempotency_key], unique: true,
                        where: "idempotency_key IS NOT NULL"
    add_index :ai_runs, %i[company_id created_at]
    add_check :ai_runs, :purpose, PURPOSES
    add_check :ai_runs, :mode, MODES
    add_check :ai_runs, :status, RUN_STATUSES

    # La propuesta de la IA, materializada y revisable.
    #
    # `ai_auto` NO saltea este paso: lo auto-acepta (auto_accepted_at). Un solo
    # code path para los tres modos, misma trazabilidad, y pasar un módulo de
    # auto a assisted es legible en el historial. La alternativa —que auto
    # escriba directo— crea dos caminos y un agujero de auditoría.
    tenant_table :ai_suggestions do |t|
      t.references :ai_run, null: false, type: :uuid, index: true

      # Cuatro FKs explícitas en vez de polimórfica: una columna polimórfica no
      # admite FK compuesta (target_id, company_id), que es la defensa
      # principal de tenancy. Más feo, correcto.
      t.uuid :challenge_id
      t.uuid :challenge_step_id
      t.uuid :idea_id
      t.uuid :criteria_set_id

      t.jsonb :payload, null: false, default: {}
      t.string :status, null: false, default: "pending"
      t.references :reviewed_by, type: :uuid, index: true
      t.datetime :reviewed_at
      t.datetime :auto_accepted_at
      t.text :review_note
      t.timestamps
    end
    add_tenant_fk :ai_suggestions, :ai_runs, column: :ai_run_id
    add_tenant_fk :ai_suggestions, :challenges, column: :challenge_id
    add_tenant_fk :ai_suggestions, :challenge_steps, column: :challenge_step_id
    add_tenant_fk :ai_suggestions, :ideas, column: :idea_id
    add_foreign_key :ai_suggestions, :users, column: :reviewed_by_id
    add_check :ai_suggestions, :status, SUGGESTION_STATUSES

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          ALTER TABLE ai_suggestions ADD CONSTRAINT ai_suggestions_single_target_check
          CHECK (
            (challenge_id IS NOT NULL)::int +
            (challenge_step_id IS NOT NULL)::int +
            (idea_id IS NOT NULL)::int +
            (criteria_set_id IS NOT NULL)::int = 1
          )
        SQL
      end
      dir.down { execute "ALTER TABLE ai_suggestions DROP CONSTRAINT IF EXISTS ai_suggestions_single_target_check" }
    end
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
