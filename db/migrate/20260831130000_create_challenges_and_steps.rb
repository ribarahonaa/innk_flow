# frozen_string_literal: true

# El núcleo del producto: un desafío es un pipeline de módulos configurable.
#
# Reemplaza el `ideas.stage` entero 0..7 de innk_r5, que era idéntico para
# todos los clientes y estaba cableado en un `case` del controller.
class CreateChallengesAndSteps < ActiveRecord::Migration[7.1]
  KINDS = %w[ideation evolution evaluation selection reporting].freeze
  STEP_STATUSES = %w[pending activating active completed skipped].freeze
  CHALLENGE_STATUSES = %w[draft running closed archived].freeze
  AI_MODES = %w[human ai_assisted ai_auto].freeze

  def change
    tenant_table :challenges do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.text :brief
      t.string :status, null: false, default: "draft"
      t.string :ai_default_mode, null: false, default: "human"
      t.datetime :started_at
      t.datetime :closed_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :challenges, %i[company_id slug], unique: true
    add_check :challenges, :status, CHALLENGE_STATUSES
    add_check :challenges, :ai_default_mode, AI_MODES

    tenant_table :challenge_steps do |t|
      t.references :challenge, null: false, type: :uuid, index: true

      # Identidad ESTABLE del módulo dentro del desafío. Toda referencia entre
      # módulos usa slug, nunca position: la posición es mutable por diseño
      # (se reordena en el builder), así que referenciar por ella es una bomba.
      # Editable mientras el step está pending; inmutable desde la activación.
      t.string :slug, null: false

      # Fraccional a propósito: insertar entre A y B es (a+b)/2 — UNA fila
      # escrita, sin shifting. El builder manda la lista completa y el server
      # renumera 1.0, 2.0, 3.0…
      #
      # Descartado acts_as_list: su shifting puede mover filas de steps ya
      # completados EN SILENCIO, violando el insertion floor. La gema no
      # conoce la invariante.
      t.decimal :position, precision: 20, scale: 10, null: false

      t.string :kind, null: false
      t.string :name, null: false
      t.string :status, null: false, default: "pending"

      # NULL = hereda challenges.ai_default_mode.
      t.string :ai_mode

      # De qué step toma su insumo (p.ej. una selección toma el puntaje de una
      # evaluación). FK COMPUESTA self-referencial: ver add_tenant_fk abajo.
      t.uuid :source_step_id

      # config          = intención del autor (puede decir "auto")
      # resolved_config = materialización, escrita UNA sola vez en activate!
      # Se leen SIEMPRE vía ChallengeStep#settings, nunca directo.
      t.jsonb :config, null: false, default: {}
      t.jsonb :resolved_config

      t.integer :lock_version, null: false, default: 0
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_tenant_fk :challenge_steps, :challenges, column: :challenge_id
    add_tenant_fk :challenge_steps, :challenge_steps, column: :source_step_id, on_delete: :nullify

    add_index :challenge_steps, %i[challenge_id slug], unique: true
    add_index :challenge_steps, %i[challenge_id position], unique: true
    add_index :challenge_steps, %i[challenge_id status]

    add_check :challenge_steps, :kind, KINDS
    add_check :challenge_steps, :status, STEP_STATUSES
    add_check :challenge_steps, :ai_mode, AI_MODES, allow_null: true

    # "Idear" se genera una sola vez: es la creación de la idea, no una etapa
    # repetible. Índice parcial único = la regla vive en la base, no solo en
    # una validación de modelo que un seed o una consola pueden saltear.
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          CREATE UNIQUE INDEX index_challenge_steps_single_ideation
            ON challenge_steps (challenge_id) WHERE kind = 'ideation'
        SQL
      end
      dir.down { execute "DROP INDEX IF EXISTS index_challenge_steps_single_ideation" }
    end
  end

  private

  def add_check(table, column, values, allow_null: false)
    list = values.map { |v| "'#{v}'" }.join(", ")
    condition = "#{column} IN (#{list})"
    condition = "#{column} IS NULL OR #{condition}" if allow_null

    reversible do |dir|
      dir.up do
        execute "ALTER TABLE #{table} ADD CONSTRAINT #{table}_#{column}_check CHECK (#{condition})"
      end
      dir.down do
        execute "ALTER TABLE #{table} DROP CONSTRAINT IF EXISTS #{table}_#{column}_check"
      end
    end
  end
end
