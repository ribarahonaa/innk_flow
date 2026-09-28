# frozen_string_literal: true

# NO nace vacía. Una policy sin nada propio hereda `show? = membership.present?`,
# o sea «cualquiera de la empresa lee esto»: es exactamente la fuga que tenía
# `CriteriaSetPolicy`, y la encontró una auditoría, no un test.
class WorkshopPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if membership.nil?
      return scope.all if membership.manages_challenges?

      # Estar convocado es estar en una mesa. Participar de un desafío
      # vinculado no alcanza: un taller es por convocatoria.
      group_workshop_ids = WorkshopGroup.joins(:workshop_group_members)
                                         .where(workshop_group_members: { user_id: membership.user_id })
                                         .select(:workshop_id)
      own = scope.where(id: group_workshop_ids)

      return own unless membership.gestor?

      # El gestor además ve los talleres que tocan sus desafíos: los lleva.
      assigned_challenge_ids = ChallengeGestor.where(user_id: membership.user_id).select(:challenge_id)
      managed_workshop_ids = WorkshopChallenge.where(challenge_id: assigned_challenge_ids).select(:workshop_id)

      own.or(scope.where(id: managed_workshop_ids))
    end
  end

  def show? = Scope.new(membership, Workshop).resolve.exists?(id: record.id)

  def create? = membership.present? && membership.manages_challenges?
  def update? = administers_any?
  def destroy? = update?
  def manage_groups? = update?

  # Sumar un desafío se pregunta por el DESAFÍO, no por el taller: un gestor
  # arma un taller con los suyos y no puede colar uno ajeno.
  def add_challenge?(challenge) = administers?(challenge)

  # Trabajar en la sala es de quien está en una mesa. Quien administra entra
  # igual: lleva el taller y ve todas las mesas.
  def work?
    return false if membership.nil?
    return true if administers_any?

    WorkshopGroupMember.joins(:workshop_group)
                        .where(workshop_groups: { workshop_id: record.id }, user_id: membership.user_id)
                        .exists?
  end

  private

  def administers_any?
    return false if membership.nil?
    return true if manager?

    record.workshop_challenges.any? { |wc| administers?(wc.challenge) }
  end
end
