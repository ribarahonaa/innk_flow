# frozen_string_literal: true

class FeedbackItem < ApplicationRecord
  include TenantScoped

  KINDS = %w[suggestion question issue].freeze
  ACTOR_TYPES = %w[human ai].freeze

  belongs_to :challenge_step
  belongs_to :idea
  belongs_to :idea_version
  belongs_to :addressed_by_version, class_name: "IdeaVersion", optional: true
  belongs_to :author, class_name: "User", optional: true
  belongs_to :ai_run, optional: true

  validates :body, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :actor_type, inclusion: { in: ACTOR_TYPES }

  scope :open_ones, -> { where(addressed: false) }
  scope :chronological, -> { order(:created_at) }

  KINDS.each { |k| define_method("#{k}?") { kind == k } }

  def by_ai? = actor_type == "ai"
  def author_name = by_ai? ? "IA" : (author&.name || "—")
  def kind_label = I18n.t("flow.feedback_kinds.#{kind}")

  # El feedback se dio sobre una versión anterior a la vigente.
  def stale? = idea.stale_for?(idea_version_id)
end
