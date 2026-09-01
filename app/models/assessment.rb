# frozen_string_literal: true

# La evaluación de una idea por un evaluador en un módulo.
class Assessment < ApplicationRecord
  include TenantScoped

  STATUSES = %w[pending submitted].freeze
  ACTOR_TYPES = %w[human ai].freeze

  belongs_to :challenge_step
  belongs_to :idea
  # Obligatorio: una nota SIEMPRE dice qué versión juzgó.
  belongs_to :idea_version
  belongs_to :evaluator, class_name: "User", optional: true
  belongs_to :ai_run, optional: true

  has_many :assessment_scores, dependent: :destroy
  accepts_nested_attributes_for :assessment_scores

  validates :status, inclusion: { in: STATUSES }
  validates :actor_type, inclusion: { in: ACTOR_TYPES }

  scope :current, -> { where(superseded_at: nil) }
  scope :submitted_ones, -> { where(status: "submitted") }

  STATUSES.each { |s| define_method("#{s}?") { status == s } }

  def by_ai? = actor_type == "ai"

  def evaluator_name = by_ai? ? "IA" : (evaluator&.name || "—")

  # Cálculo de DISPLAY, no mutación: la nota sobre v2 sigue siendo válida
  # cuando existe v3, pero la UI tiene que avisar que la idea cambió después.
  def stale? = idea.stale_for?(idea_version_id)
end
