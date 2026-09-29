# frozen_string_literal: true

# Una mesa. En modo individual también existe: es una mesa de una persona.
# Un mecanismo y un gancho, en vez de dos caminos en el código.
class WorkshopGroup < ApplicationRecord
  include TenantScoped

  belongs_to :workshop
  has_many :workshop_group_members, dependent: :destroy
  has_many :members, through: :workshop_group_members, source: :user

  validates :name, presence: true

  # Las ideas de `challenge` que esta mesa puede trabajar: las que creó o en
  # las que colabora ALGUNO de sus integrantes, y nada más. Es la unión sobre
  # la mesa, no lo que ve cada persona por separado: «traé tu idea y la
  # mejoramos entre todos».
  def workable_ideas(challenge)
    member_ids = workshop_group_members.select(:user_id)
    ideas = challenge.ideas
    ideas.where(author_id: member_ids)
         .or(ideas.where(id: IdeaContributor.where(user_id: member_ids).select(:idea_id)))
  end
end
