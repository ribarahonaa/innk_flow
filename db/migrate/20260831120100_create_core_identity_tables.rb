# frozen_string_literal: true

# Identidad y tenencia.
#
# Decisión: `users` es GLOBAL (email único en toda la instalación) y la
# pertenencia a una empresa vive en `memberships`. Es lo que hace posible el
# selector de empresa post-login sin resolver subdominios, y permite que una
# persona participe en más de una empresa sin duplicar credenciales.
#
# Consecuencia: Company, User, Identity y Session NO son tenant-scoped (el
# lookup de sesión ocurre antes de que exista Current.company). Membership sí.
# La allowlist de spec/tenancy/model_coverage_spec.rb es exactamente esa lista.
class CreateCoreIdentityTables < ActiveRecord::Migration[7.1]
  def change
    create_table :companies, id: :uuid, default: -> { "uuid_generate_v7()" } do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.timestamps
    end
    add_index :companies, :slug, unique: true

    create_table :users, id: :uuid, default: -> { "uuid_generate_v7()" } do |t|
      t.string :email, null: false
      t.string :name, null: false
      t.string :password_digest
      t.timestamps
    end
    execute "CREATE UNIQUE INDEX index_users_on_lower_email ON users (lower(email))"

    # Costura para SSO. Hoy solo hay filas provider='password'; el día que se
    # delegue en innk_r5 se agrega provider='innk_r5' sin migrar datos ni
    # cambiar el modelo de User. Crearla vacía ahora es barato; después no.
    create_table :identities, id: :uuid, default: -> { "uuid_generate_v7()" } do |t|
      t.references :user, null: false, type: :uuid, foreign_key: true, index: true
      t.string :provider, null: false, default: "password"
      t.string :uid, null: false
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end
    add_index :identities, %i[provider uid], unique: true

    create_table :memberships, id: :uuid, default: -> { "uuid_generate_v7()" } do |t|
      t.references :company, null: false, type: :uuid, foreign_key: true, index: true
      t.references :user, null: false, type: :uuid, foreign_key: true, index: true
      t.string :role, null: false, default: "participant"
      t.timestamps
    end
    add_index :memberships, %i[company_id user_id], unique: true
    execute <<~SQL.squish
      ALTER TABLE memberships ADD CONSTRAINT memberships_tenant_uniq UNIQUE (id, company_id)
    SQL
    execute <<~SQL.squish
      ALTER TABLE memberships ADD CONSTRAINT memberships_role_check
        CHECK (role IN ('owner', 'admin', 'evaluator', 'participant'))
    SQL

    # Sesión persistida en tabla, no solo cookie: permite cerrar sesiones desde
    # el server y saber qué empresa tiene activa cada sesión.
    create_table :sessions, id: :uuid, default: -> { "uuid_generate_v7()" } do |t|
      t.references :user, null: false, type: :uuid, foreign_key: true, index: true
      t.references :company, type: :uuid, foreign_key: true, index: true
      t.string :token, null: false
      t.string :user_agent
      t.string :ip_address
      t.datetime :last_seen_at
      t.timestamps
    end
    add_index :sessions, :token, unique: true
  end
end
