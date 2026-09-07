# frozen_string_literal: true

# Une una persona con una empresa y le da un rol. Es tenant-scoped: la
# pertenencia sí es un dato de la empresa.
class Membership < ApplicationRecord
  include TenantScoped

  # `owner` se eliminó: daba exactamente los mismos permisos que `admin` y no
  # había una sola policy que los distinguiera.
  # `gestor` acompaña la evolución de las ideas y trabaja para varias
  # empresas: una membresía por cada una. A diferencia del resto, no ve todos
  # los desafíos de la empresa — solo los que le asignan.
  ROLES = %w[admin gestor evaluator participant].freeze

  belongs_to :company
  belongs_to :user

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :company_id }

  ROLES.each { |role| define_method("#{role}?") { self.role == role } }

  # Quien puede armar y correr desafíos.
  def manages_challenges? = admin?
end
