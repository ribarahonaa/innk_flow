# frozen_string_literal: true

# Une una persona con una empresa y le da un rol. Es tenant-scoped: la
# pertenencia sí es un dato de la empresa.
class Membership < ApplicationRecord
  include TenantScoped

  # `owner` se eliminó: daba exactamente los mismos permisos que `admin` y no
  # había una sola policy que los distinguiera.
  ROLES = %w[admin evaluator participant].freeze

  belongs_to :user

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :company_id }

  ROLES.each { |role| define_method("#{role}?") { self.role == role } }

  # Quien puede armar y correr desafíos.
  def manages_challenges? = admin?
end
