# frozen_string_literal: true

class StepAssignment < ApplicationRecord
  include TenantScoped

  ROLES = %w[evaluator jury].freeze

  # Sin peso asignado, todas las voces valen lo mismo. `nil` y 1 significan
  # exactamente eso; se guarda nil para no fingir una decisión que nadie tomó.
  DEFAULT_WEIGHT = 1
  MAX_WEIGHT = 10

  belongs_to :challenge_step
  belongs_to :user

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :challenge_step_id }
  validates :weight, numericality: { greater_than: 0, less_than_or_equal_to: MAX_WEIGHT },
                     allow_nil: true

  def effective_weight = (weight || DEFAULT_WEIGHT).to_d

  # ¿Alguien le puso un peso distinto del de todos?
  def weighted? = weight.present? && weight.to_d != DEFAULT_WEIGHT
end
