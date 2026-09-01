# frozen_string_literal: true

class StepAssignment < ApplicationRecord
  include TenantScoped

  ROLES = %w[evaluator jury].freeze

  belongs_to :challenge_step
  belongs_to :user

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :challenge_step_id }
end
