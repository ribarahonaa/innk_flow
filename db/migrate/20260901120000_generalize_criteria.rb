# frozen_string_literal: true

# Generaliza el concepto de criterio.
#
# Hasta acá, un criterio era siempre "una persona pone un valor en una escala",
# y `scale_type` mezclaba dos cosas distintas:
#
#   · QUIÉN produce el valor  → una persona, la IA, el sistema, una fórmula
#   · QUÉ FORMA tiene         → nota, letra, rúbrica, sí/no
#
# `formula` estaba del lado equivocado: no es una escala, es un origen (el
# valor se deriva de otros criterios). Se separan los dos ejes.
class GeneralizeCriteria < ActiveRecord::Migration[7.1]
  SOURCES = %w[manual automatic ai formula].freeze
  SCALE_TYPES = %w[numeric letter rubric boolean].freeze
  CHECK_TYPES = %w[field_present contributors_count version_count feedback_addressed has_attachment].freeze

  def up
    add_column :criteria, :source, :string, null: false, default: "manual"
    # Qué mide un criterio automático: el campo, el mínimo, etc.
    add_column :criteria, :source_config, :jsonb, null: false, default: {}

    # Los criterios fórmula pasan a declarar su origen; su escala es numérica,
    # porque el resultado es un número dentro de un rango.
    execute <<~SQL.squish
      UPDATE criteria SET source = 'formula', scale_type = 'numeric'
      WHERE scale_type = 'formula'
    SQL

    execute "ALTER TABLE criteria DROP CONSTRAINT IF EXISTS criteria_scale_type_check"
    add_check :criteria, :scale_type, SCALE_TYPES
    add_check :criteria, :source, SOURCES

    # Un criterio automático declara qué verifica.
    execute <<~SQL.squish
      ALTER TABLE criteria ADD CONSTRAINT criteria_automatic_needs_check
      CHECK (source <> 'automatic' OR source_config ? 'check')
    SQL

    # ── Colaboradores de una idea ────────────────────────────────────────
    #
    # Hasta acá una idea tenía un solo autor. El criterio "más de un autor"
    # necesita poder registrar a quién más participó.
    create_table :idea_contributors, id: :uuid, default: -> { "uuid_generate_v7()" } do |t|
      t.references :company, null: false, type: :uuid, foreign_key: true, index: true
      t.references :idea, null: false, type: :uuid, index: true
      t.references :user, null: false, type: :uuid, foreign_key: true, index: true
      t.string :role, null: false, default: "contributor"
      t.timestamps
    end
    execute "ALTER TABLE idea_contributors ADD CONSTRAINT idea_contributors_tenant_uniq UNIQUE (id, company_id)"
    execute <<~SQL.squish
      ALTER TABLE idea_contributors
        ADD CONSTRAINT idea_contributors_idea_id_same_company
        FOREIGN KEY (idea_id, company_id) REFERENCES ideas (id, company_id) ON DELETE CASCADE
    SQL
    add_index :idea_contributors, %i[idea_id user_id], unique: true

    # ── Veredictos de selección ──────────────────────────────────────────
    #
    # Una selección puede resolverse criterio por criterio (pasa / no pasa),
    # decidido por una persona o por la IA.
    tenant_table :selection_verdicts do |t|
      t.references :challenge_step, null: false, type: :uuid, index: true
      t.references :idea, null: false, type: :uuid, index: true
      t.uuid :idea_version_id, null: false
      t.string :criterion_key, null: false
      t.uuid :criterion_id
      t.boolean :passed, null: false
      t.string :actor_type, null: false, default: "human"
      t.references :decided_by, type: :uuid, index: true
      t.uuid :ai_run_id
      t.text :note
      t.timestamps
    end
    add_tenant_fk :selection_verdicts, :challenge_steps, column: :challenge_step_id
    add_tenant_fk :selection_verdicts, :ideas, column: :idea_id
    add_tenant_fk :selection_verdicts, :idea_versions, column: :idea_version_id
    add_tenant_fk :selection_verdicts, :criteria, column: :criterion_id, on_delete: :nullify
    add_tenant_fk :selection_verdicts, :ai_runs, column: :ai_run_id, on_delete: :nullify
    add_foreign_key :selection_verdicts, :users, column: :decided_by_id
    add_index :selection_verdicts, %i[challenge_step_id idea_id criterion_key],
              unique: true, name: "index_selection_verdicts_unique"
    add_check :selection_verdicts, :actor_type, %w[human ai]
  end

  def down
    drop_table :selection_verdicts
    drop_table :idea_contributors
    execute "ALTER TABLE criteria DROP CONSTRAINT IF EXISTS criteria_automatic_needs_check"
    execute "ALTER TABLE criteria DROP CONSTRAINT IF EXISTS criteria_source_check"
    execute "UPDATE criteria SET scale_type = 'formula' WHERE source = 'formula'"
    remove_column :criteria, :source_config
    remove_column :criteria, :source
  end

  private

  def add_check(table, column, values)
    list = values.map { |v| "'#{v}'" }.join(", ")
    execute "ALTER TABLE #{table} ADD CONSTRAINT #{table}_#{column}_check CHECK (#{column} IN (#{list}))"
  end
end
