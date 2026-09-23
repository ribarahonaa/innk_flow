# frozen_string_literal: true

class AssessmentPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope; end

  # Evalúa quien esté asignado al módulo, o quien lo administra.
  # Nadie evalúa una idea de la que participa —autor o colaborador—, ni
  # siquiera quien administra: el conflicto de interés es el mismo. Postular
  # sigue permitido; lo que no se puede es puntuarse a uno mismo.
  def create?
    return false if membership.nil?
    # Llegar al desafío, que un gestor sólo hace con los que le asignaron. Los
    # controllers de evaluar ya lo filtraban con `policy_scope(Challenge)`,
    # pero aceptar una propuesta de evaluación de la IA pregunta esto sin pasar
    # por ningún scope, y una asignación que sobrevivió a la baja del gestor
    # alcanzaba para escribir una evaluación sobre un desafío que le da 404.
    return false unless reaches_challenge?(record.challenge_step&.challenge)
    return false if record.idea&.participates?(membership.user)
    return true if administra?(record.challenge_step&.challenge)

    record.challenge_step.step_assignments.exists?(user_id: membership.user_id)
  end

  def update?
    return false if record.nil?
    return true if administra?(record.challenge_step&.challenge)

    record.evaluator_id == membership.user_id && !record.submitted?
  end
end
