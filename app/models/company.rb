# frozen_string_literal: true

# El tenant. No es TenantScoped: es la raíz.
class Company < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9][a-z0-9-]*\z/, message: "solo minúsculas, números y guiones" }

  def to_param = slug
end
