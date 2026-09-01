# frozen_string_literal: true

# Alguien que participó de una idea además de quien la creó.
#
# Existe porque un criterio puede pedir "que participe más de una persona": sin
# esto, toda idea tendría exactamente un autor y el criterio no distinguiría
# nada.
class IdeaContributor < ApplicationRecord
  include TenantScoped

  ROLES = %w[contributor sponsor reviewer].freeze

  belongs_to :idea
  belongs_to :user

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :idea_id }
  validate :not_the_author

  private

  def not_the_author
    return if idea.nil? || user_id != idea.author_id

    errors.add(:user_id, "ya es quien creó la idea")
  end
end
