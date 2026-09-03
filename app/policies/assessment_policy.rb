# frozen_string_literal: true

class AssessmentPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope; end

  # Evalúa quien esté asignado al módulo, o quien lo administra.
  # Nadie evalúa una idea de la que participa —autor o colaborador—, ni
  # siquiera quien administra: el conflicto de interés es el mismo. Postular
  # sigue permitido; lo que no se puede es puntuarse a uno mismo.
  def create?
    return false if membership.nil?
    return false if record.idea&.participates?(membership.user)
    return true if manager?

    record.challenge_step.step_assignments.exists?(user_id: membership.user_id)
  end

  def update?
    return false if record.nil?
    return true if manager?

    record.evaluator_id == membership.user_id && !record.submitted?
  end
end
