# frozen_string_literal: true

# `owner` y `admin` daban exactamente los mismos permisos: no había una sola
# policy que los distinguiera. Dos nombres para lo mismo son una regla más que
# explicar y una pregunta más en cada revisión de permisos.
class DropOwnerRole < ActiveRecord::Migration[7.1]
  ROLES = %w[admin evaluator participant].freeze

  def up
    execute "UPDATE memberships SET role = 'admin' WHERE role = 'owner'"
    replace_check(ROLES)
  end

  # Sin vuelta: quién era owner antes no queda registrado en ningún lado, así
  # que revertir dejaría a todos como admin igual.
  def down = replace_check(ROLES + ["owner"])

  private

  def replace_check(roles)
    lista = roles.map { |r| connection.quote(r) }.join(", ")
    execute "ALTER TABLE memberships DROP CONSTRAINT memberships_role_check"
    execute "ALTER TABLE memberships ADD CONSTRAINT memberships_role_check CHECK (role IN (#{lista}))"
  end
end
