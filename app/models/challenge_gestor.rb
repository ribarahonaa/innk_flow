# frozen_string_literal: true

# Un gestor asignado a UN desafío.
#
# Existe porque tener membresía en una empresa no puede significar ver todo lo
# de esa empresa: un gestor contratado para un desafío no tiene por qué leer
# los demás.
class ChallengeGestor < ApplicationRecord
  include TenantScoped

  belongs_to :challenge
  belongs_to :user

  validates :user_id, uniqueness: { scope: :challenge_id }
  validate :user_must_be_gestor

  scope :for_user, ->(user) { where(user_id: user&.id) }

  private

  # Se consulta explícito y no por `user.memberships`: esa asociación puede
  # venir cargada desde OTRO contexto de empresa —una persona vive en varias— y
  # daría un falso negativo.
  def user_must_be_gestor
    return if user_id.nil? || challenge.nil?
    return if Membership.exists?(user_id: user_id, company_id: challenge.company_id, role: "gestor")

    errors.add(:user_id, "no es gestor en esta empresa")
  end
end
