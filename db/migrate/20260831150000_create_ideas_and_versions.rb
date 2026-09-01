# frozen_string_literal: true

# Ideas, versionado y participación por módulo.
#
# La idea es IDENTIDAD; la versión es CONTENIDO. Cada cambio crea una fila
# nueva e inmutable con snapshot completo del payload — no diffs almacenados.
# El diff se calcula al vuelo comparando dos payloads.
#
# Contraste con innk_r5: allá las respuestas viven en `idea_field_answers`,
# una fila por campo, SIN índice único sobre (idea_id, company_form_field_id).
# Por eso `Idea#problems` arrastra un `remove_duplicates` que hace destroy_all
# defensivo. Con payload jsonb el estado duplicado es inexpresable.
class CreateIdeasAndVersions < ActiveRecord::Migration[7.1]
  IDEA_STATUSES = %w[draft active eliminated withdrawn].freeze
  ACTOR_TYPES = %w[human ai].freeze
  ENTRY_STATUSES = %w[pending in_progress done advanced eliminated].freeze
  FIELD_TYPES = %w[text textarea number date select multi_select file rich_text].freeze

  def change
    # ── Formulario dinámico, definido por el módulo de ideación ──────────
    #
    # Dinámico y no fijo porque una de las tareas de IA es proponer los campos
    # según el brief del desafío.
    tenant_table :form_fields do |t|
      t.references :challenge_step, null: false, type: :uuid, index: true
      # Estable: renombrar el label no rompe el histórico, porque el payload
      # de cada versión se indexa por `key`.
      t.string :key, null: false
      t.string :label, null: false
      t.text :hint
      t.string :field_type, null: false, default: "text"
      t.boolean :required, null: false, default: false
      t.integer :position, null: false, default: 0
      t.jsonb :config, null: false, default: {}
      t.timestamps
    end
    add_tenant_fk :form_fields, :challenge_steps, column: :challenge_step_id
    add_index :form_fields, %i[challenge_step_id key], unique: true
    add_check :form_fields, :field_type, FIELD_TYPES

    # ── Idea: identidad ──────────────────────────────────────────────────
    tenant_table :ideas do |t|
      t.references :challenge, null: false, type: :uuid, index: true
      t.references :author, null: false, type: :uuid, index: true
      # Puntero a la versión vigente. Nullable porque hay un ciclo de FK con
      # idea_versions: la idea se crea primero, la versión después.
      t.uuid :current_version_id
      t.string :status, null: false, default: "draft"
      t.string :origin, null: false, default: "human"
      # Denormalizado para no recorrer selection_decisions en cada listado.
      t.uuid :eliminated_at_step_id
      t.datetime :submitted_at
      t.timestamps
    end
    add_tenant_fk :ideas, :challenges, column: :challenge_id
    add_foreign_key :ideas, :users, column: :author_id
    add_index :ideas, %i[challenge_id status]
    add_check :ideas, :status, IDEA_STATUSES
    add_check :ideas, :origin, ACTOR_TYPES

    # ── Versión: contenido, INMUTABLE ────────────────────────────────────
    tenant_table :idea_versions do |t|
      t.references :idea, null: false, type: :uuid, index: true
      t.integer :number, null: false
      t.string :title
      # Snapshot COMPLETO: { field_key => value }. No un diff.
      t.jsonb :payload, null: false, default: {}
      t.references :created_by, type: :uuid, index: true
      t.string :actor_type, null: false, default: "human"
      # Qué módulo provocó esta versión (una ronda de evolución, p.ej.).
      t.uuid :source_step_id
      t.text :change_note
      t.timestamps
    end
    add_tenant_fk :idea_versions, :ideas, column: :idea_id
    add_tenant_fk :idea_versions, :challenge_steps, column: :source_step_id, on_delete: :nullify
    add_foreign_key :idea_versions, :users, column: :created_by_id
    add_index :idea_versions, %i[idea_id number], unique: true
    add_check :idea_versions, :actor_type, ACTOR_TYPES

    # Cierra el ciclo: la idea apunta a su versión vigente.
    add_tenant_fk :ideas, :idea_versions, column: :current_version_id, on_delete: :nullify

    tenant_table :idea_attachments do |t|
      t.references :idea_version, null: false, type: :uuid, index: true
      t.string :field_key, null: false
      t.timestamps
    end
    add_tenant_fk :idea_attachments, :idea_versions, column: :idea_version_id

    # ── Participación de una idea en un módulo ───────────────────────────
    #
    # Se crean LAZY, al activar el step, y solo para el cohorte vivo. Una idea
    # eliminada en una selección NO genera fila en los módulos siguientes, así
    # que `step_entries` significa exactamente "participación real" y los
    # reportes son COUNT(*) sin condiciones que alguien pueda olvidar.
    tenant_table :step_entries do |t|
      t.references :challenge_step, null: false, type: :uuid, index: true
      t.references :idea, null: false, type: :uuid, index: true
      t.string :status, null: false, default: "pending"
      t.uuid :input_version_id
      t.uuid :output_version_id
      t.jsonb :result, null: false, default: {}
      t.datetime :entered_at
      t.datetime :resolved_at
      t.timestamps
    end
    add_tenant_fk :step_entries, :challenge_steps, column: :challenge_step_id
    add_tenant_fk :step_entries, :ideas, column: :idea_id
    add_tenant_fk :step_entries, :idea_versions, column: :input_version_id, on_delete: :nullify
    add_tenant_fk :step_entries, :idea_versions, column: :output_version_id, on_delete: :nullify
    # Hace idempotente a Flow::Cohort.sync!, que es lo que permite la repesca.
    add_index :step_entries, %i[challenge_step_id idea_id], unique: true
    add_check :step_entries, :status, ENTRY_STATUSES
  end

  private

  def add_check(table, column, values, allow_null: false)
    list = values.map { |v| "'#{v}'" }.join(", ")
    condition = "#{column} IN (#{list})"
    condition = "#{column} IS NULL OR #{condition}" if allow_null

    reversible do |dir|
      dir.up { execute "ALTER TABLE #{table} ADD CONSTRAINT #{table}_#{column}_check CHECK (#{condition})" }
      dir.down { execute "ALTER TABLE #{table} DROP CONSTRAINT IF EXISTS #{table}_#{column}_check" }
    end
  end
end
