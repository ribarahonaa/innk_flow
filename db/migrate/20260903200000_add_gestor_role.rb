# frozen_string_literal: true

# El gestor ayuda a que las ideas evolucionen, y trabaja para VARIAS empresas.
#
# Lo interempresa no necesita nada nuevo: una membresía con rol `gestor` en
# cada empresa que ayuda, igual que cualquier persona en más de una. El
# aislamiento lo sigue garantizando Current.company y las FKs compuestas.
#
# Lo que sí es nuevo: un gestor NO ve todos los desafíos de la empresa, solo
# los que le asignan. Tener membresía deja de ser sinónimo de ver todo.
class AddGestorRole < ActiveRecord::Migration[7.1]
  include Flow::MigrationHelpers

  ROLES = %w[admin gestor evaluator participant].freeze

  def up
    replace_check(ROLES)
    create_assignments
  end

  def down
    drop_table :challenge_gestores
    execute "UPDATE memberships SET role = 'participant' WHERE role = 'gestor'"
    replace_check(ROLES - ["gestor"])
  end

  private

  def replace_check(roles)
    lista = roles.map { |r| connection.quote(r) }.join(", ")
    execute "ALTER TABLE memberships DROP CONSTRAINT memberships_role_check"
    execute "ALTER TABLE memberships ADD CONSTRAINT memberships_role_check CHECK (role IN (#{lista}))"
  end

  def create_assignments
    tenant_table :challenge_gestores do |t|
      t.references :challenge, null: false, type: :uuid, index: true
      t.references :user, null: false, type: :uuid, index: true
      t.datetime :assigned_at, null: false, default: -> { "now()" }
      t.timestamps
    end

    add_tenant_fk :challenge_gestores, :challenges, column: :challenge_id
    # `users` es global —una persona vive en varias empresas—, así que su FK no
    # puede ser compuesta. Quien acota la asignación a una empresa es el
    # company_id de esta misma fila.
    add_foreign_key :challenge_gestores, :users, column: :user_id

    add_index :challenge_gestores, %i[challenge_id user_id], unique: true
  end
end
