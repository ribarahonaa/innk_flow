# frozen_string_literal: true

class CreateWorkshops < ActiveRecord::Migration[7.1]
  include Flow::MigrationHelpers

  def change
    tenant_table :workshops do |t|
      t.string :name, null: false
      t.string :mode, null: false, default: "group"
      t.string :status, null: false, default: "draft"
      t.datetime :scheduled_at
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_check_constraint :workshops, "mode IN ('individual','group')", name: "workshops_mode_check"
    add_check_constraint :workshops, "status IN ('draft','open','closed')", name: "workshops_status_check"

    tenant_table :workshop_challenges do |t|
      t.uuid :workshop_id, null: false
      t.uuid :challenge_id, null: false
      # Nulo mientras el taller es borrador: se resuelve al abrir, contra el
      # módulo que esté activo en ese momento.
      t.uuid :challenge_step_id
      t.string :status, null: false, default: "open"
      t.string :closed_reason
      t.datetime :closed_at
      t.timestamps
    end
    add_index :workshop_challenges, %i[workshop_id challenge_id], unique: true
    add_check_constraint :workshop_challenges, "status IN ('open','closed')",
                         name: "workshop_challenges_status_check"

    tenant_table :workshop_groups do |t|
      t.uuid :workshop_id, null: false
      t.string :name, null: false
      t.timestamps
    end
    add_index :workshop_groups, :workshop_id

    tenant_table :workshop_group_members do |t|
      t.uuid :workshop_group_id, null: false
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.timestamps
    end
    add_index :workshop_group_members, %i[workshop_group_id user_id], unique: true

    tenant_table :workshop_proposals do |t|
      t.uuid :workshop_group_id, null: false
      t.uuid :idea_id, null: false
      t.uuid :challenge_step_id, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :status, null: false, default: "pending"
      t.references :reviewed_by, type: :uuid, foreign_key: { to_table: :users }
      t.datetime :reviewed_at
      t.timestamps
    end
    add_index :workshop_proposals, :idea_id
    add_check_constraint :workshop_proposals, "status IN ('pending','accepted','rejected')",
                         name: "workshop_proposals_status_check"

    # Todas compuestas: Postgres rechaza atar una fila de la empresa A a un
    # padre de la B. `add_foreign_key` simple acá haría fallar
    # spec/tenancy/schema_spec.rb, y con razón.
    add_tenant_fk :workshop_challenges,    :workshops,       column: :workshop_id
    add_tenant_fk :workshop_challenges,    :challenges,      column: :challenge_id
    add_tenant_fk :workshop_challenges,    :challenge_steps, column: :challenge_step_id, on_delete: :nullify
    add_tenant_fk :workshop_groups,        :workshops,       column: :workshop_id
    add_tenant_fk :workshop_group_members, :workshop_groups, column: :workshop_group_id
    add_tenant_fk :workshop_proposals,     :workshop_groups, column: :workshop_group_id
    add_tenant_fk :workshop_proposals,     :ideas,           column: :idea_id
    add_tenant_fk :workshop_proposals,     :challenge_steps, column: :challenge_step_id
  end
end
