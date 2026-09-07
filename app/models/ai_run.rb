# frozen_string_literal: true

# Una llamada al proveedor de IA. Toda llamada deja una fila, sea con el
# adapter de fixtures o con uno real.
class AiRun < ApplicationRecord
  include TenantScoped

  PURPOSES = %w[
    suggest_criteria
    propose_pipeline suggest_form_fields generate_ideas coauthor_field
    detect_duplicates suggest_feedback evaluate_idea decide_verdicts evolve_idea
    summarize_challenge
  ].freeze
  MODES = %w[ai_assisted ai_auto].freeze
  STATUSES = %w[queued running succeeded failed].freeze

  belongs_to :challenge, optional: true
  belongs_to :challenge_step, optional: true
  belongs_to :idea, optional: true
  belongs_to :requested_by, class_name: "User", optional: true

  has_many :ai_suggestions, dependent: :destroy

  validates :purpose, inclusion: { in: PURPOSES }
  validates :mode, inclusion: { in: MODES }
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }
  scope :failed_ones, -> { where(status: "failed") }

  STATUSES.each { |s| define_method("#{s}?") { status == s } }

  def purpose_label = I18n.t("flow.ai_purposes.#{purpose}", default: purpose.humanize)

  def tokens_total = tokens_in.to_i + tokens_out.to_i

  def auto? = mode == "ai_auto"
end
