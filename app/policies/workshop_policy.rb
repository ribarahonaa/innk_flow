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

      # El gestor además ve los talleres que tocan sus desafíos —los lleva— y
      # los que creó él SÓLO mientras no tienen desafíos: uno recién creado
      # todavía no tiene ninguno, y sin esto el redirect del `create` caería en
      # un 404. En cuanto tiene desafíos, la visibilidad los sigue (igual que
      # `administers_any?`): si le revocan la asignación, 404 y no 403.
      assigned_challenge_ids = ChallengeGestor.where(user_id: membership.user_id).select(:challenge_id)
      managed_workshop_ids = WorkshopChallenge.where(challenge_id: assigned_challenge_ids).select(:workshop_id)

      own.or(scope.where(id: managed_workshop_ids)).or(scope.where(created_by_id: membership.user_id)
                                     .where.not(id: WorkshopChallenge.select(:workshop_id)))
    end
  end

  def show? = Scope.new(membership, Workshop).resolve.exists?(id: record.id)

  # Crear no pregunta por ningún desafío —el taller todavía no tiene—, así que
  # al gestor lo acota `administers_any?`: administra el que él creó
  # (`created_by`), la misma idea que el auto-asignado de
  # `ChallengesController#create`. Un taller ajeno sin desafíos suyos sigue
  # cerrado para él.
  def create? = manager? || (membership.present? && membership.gestor?)
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

  # Se pregunta tres veces por render de `show` (el controller y dos veces la
  # vista): se resuelve una vez. Para el gestor es UNA consulta —los desafíos
  # vinculados contra sus asignaciones— y no un `exists?` por vínculo; para
  # los demás roles no hay consulta, porque `administers?` sólo abre por
  # `manager?` o por gestor.
  def administers_any?
    return @administers_any if defined?(@administers_any)

    @administers_any = resolve_administers_any
  end

  def resolve_administers_any
    return false if membership.nil?
    return true if manager?
    return false unless membership.gestor?
    # La autoría sólo vale mientras el taller no tiene desafíos: cubre crear y
    # sumar el primero. Con desafíos, la autoridad los sigue: si le revocan la
    # asignación, no conserva un taller cuyo desafío ya no ve.
    return true if record.created_by_id == membership.user_id && record.workshop_challenges.empty?

    ChallengeGestor.exists?(
      user_id: membership.user_id,
      challenge_id: record.workshop_challenges.select(:challenge_id)
    )
  end
end
