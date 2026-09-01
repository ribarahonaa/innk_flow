# frozen_string_literal: true

# Un campo del formulario de postulación. Pertenece al módulo de ideación.
class FormField < ApplicationRecord
  include TenantScoped

  TYPES = %w[text textarea number date select multi_select file rich_text].freeze

  belongs_to :challenge_step

  validates :label, presence: true
  validates :field_type, inclusion: { in: TYPES }
  validates :key, presence: true,
                  uniqueness: { scope: :challenge_step_id },
                  format: { with: /\A[a-z][a-z0-9_]*\z/ }

  before_validation :derive_key, on: :create

  scope :ordered, -> { order(:position, :created_at) }

  def options = Array(config["options"])

  def multi? = field_type == "multi_select"

  private

  def derive_key
    return if key.present? || label.blank?

    base = label.to_s.parameterize(separator: "_").gsub(/\A[^a-z]+/, "").presence || "campo"
    taken = challenge_step ? FormField.where(challenge_step_id: challenge_step_id).pluck(:key) : []
    candidate = base
    n = 1
    candidate = "#{base}_#{n += 1}" while taken.include?(candidate)
    self.key = candidate
  end
end
