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

  def title? = config["is_title"] == true

  def type_label = I18n.t("flow.field_types.#{field_type}")

  # Cuántas ideas respondieron este campo. Es lo que hace visible el costo de
  # borrarlo o renombrarlo.
  def answered_count
    @answered_count ||= IdeaVersion
                        .where(idea_id: challenge_step.challenge.ideas.select(:id))
                        .where("payload ? :k", k: key)
                        .select(:idea_id).distinct.count
  end

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
