# frozen_string_literal: true

# Una mesa. En modo individual también existe: es una mesa de una persona.
# Un mecanismo y un gancho, en vez de dos caminos en el código.
class WorkshopGroup < ApplicationRecord
  include TenantScoped

  belongs_to :workshop
  has_many :workshop_group_members, dependent: :destroy
  has_many :members, through: :workshop_group_members, source: :user

  validates :name, presence: true
end
