# frozen_string_literal: true

class AssessmentPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope; end

  # Evalúa quien esté asignado al módulo, o quien lo administra.
  def create?
    return true if manager?
    return false if membership.nil?

    record.challenge_step.step_assignments.exists?(user_id: membership.user_id)
  end

  def update?
    return false if record.nil?
    return true if manager?

    record.evaluator_id == membership.user_id && !record.submitted?
  end
end
