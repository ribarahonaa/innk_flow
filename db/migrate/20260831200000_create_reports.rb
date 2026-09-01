# frozen_string_literal: true

# Reportes del estado del desafío en un punto del flujo.
class CreateReports < ActiveRecord::Migration[7.1]
  KINDS = %w[funnel ranking snapshot narrative].freeze
  FORMATS = %w[dashboard xlsx pdf].freeze
  STATUSES = %w[pending ready failed].freeze

  def change
    tenant_table :reports do |t|
      t.references :challenge_step, null: false, type: :uuid, index: true
      t.string :kind, null: false, default: "snapshot"
      t.string :format, null: false, default: "dashboard"
      t.string :status, null: false, default: "pending"
      # scope: qué módulos abarca, si incluye eliminadas, y el MODO —
      # by_version (cada celda con la versión que se evaluó) o latest.
      t.jsonb :scope, null: false, default: {}
      t.jsonb :data, null: false, default: {}
      t.integer :row_count
      t.datetime :generated_at
      t.text :error
      t.references :requested_by, type: :uuid, index: true
      t.uuid :ai_run_id
      t.timestamps
    end
    add_tenant_fk :reports, :challenge_steps, column: :challenge_step_id
    add_tenant_fk :reports, :ai_runs, column: :ai_run_id, on_delete: :nullify
    add_foreign_key :reports, :users, column: :requested_by_id
    add_check :reports, :kind, KINDS
    add_check :reports, :format, FORMATS
    add_check :reports, :status, STATUSES
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
