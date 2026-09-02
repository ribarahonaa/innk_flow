# frozen_string_literal: true

class CreateNotifications < ActiveRecord::Migration[7.1]
  include Flow::MigrationHelpers

  def change
    tenant_table :notifications do |t|
      t.references :user, null: false, type: :uuid, index: true
      t.string :kind, null: false
      t.references :challenge, type: :uuid, index: true
      t.references :challenge_step, type: :uuid, index: true
      t.references :idea, type: :uuid, index: true
      t.jsonb :payload, null: false, default: {}
      t.datetime :read_at
      t.timestamps
    end

    # `users` es global: una persona puede pertenecer a varias empresas por
    # memberships, así que no tiene company_id y su FK no puede ser compuesta.
    # Quien acota la notificación a una empresa es su propio company_id.
    add_foreign_key :notifications, :users, column: :user_id

    add_tenant_fk :notifications, :challenges, column: :challenge_id
    add_tenant_fk :notifications, :challenge_steps, column: :challenge_step_id
    add_tenant_fk :notifications, :ideas, column: :idea_id

    # La bandeja se lee siempre igual: las de esta persona, primero las nuevas.
    add_index :notifications, %i[user_id read_at created_at], order: { created_at: :desc }
  end
end
