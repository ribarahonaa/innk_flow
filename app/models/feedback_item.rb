# frozen_string_literal: true

class FeedbackItem < ApplicationRecord
  include TenantScoped

  KINDS = %w[suggestion question issue].freeze
  ACTOR_TYPES = %w[human ai].freeze

  # Cómo se cerró.
  #
  #   answered     → el autor publicó una versión que lo responde
  #   acknowledged → alguien lo dio por atendido sin cambiar la idea
  #   dismissed    → no aplica, y queda dicho por qué
  RESOLUTIONS = %w[answered acknowledged dismissed].freeze

  belongs_to :challenge_step
  belongs_to :idea
  belongs_to :idea_version
  belongs_to :addressed_by_version, class_name: "IdeaVersion", optional: true
  belongs_to :author, class_name: "User", optional: true
  belongs_to :resolved_by, class_name: "User", optional: true
  belongs_to :ai_run, optional: true

  validates :body, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :actor_type, inclusion: { in: ACTOR_TYPES }
  validates :resolution, inclusion: { in: RESOLUTIONS }, allow_nil: true

  # `addressed` queda como proyección de `resolution`: un solo lugar decide si
  # el comentario sigue abierto.
  before_save { self.addressed = resolution.present? }

  scope :open_ones, -> { where(addressed: false) }
  scope :chronological, -> { order(:created_at) }

  KINDS.each { |k| define_method("#{k}?") { kind == k } }

  def by_ai? = actor_type == "ai"

  def open? = resolution.blank?

  def resolution_label
    return nil if open?

    I18n.t("flow.feedback_resolutions.#{resolution}")
  end

  def resolved_by_name = resolved_by&.name || "—"

  # Cierra el comentario. `answered` lo usa el ciclo normal (publicar una
  # versión); los otros dos los elige una persona desde el tablero.
  def resolve!(resolution:, user: nil, note: nil, version: nil)
    update!(
      resolution: resolution,
      resolved_by: user,
      resolved_at: Time.current,
      resolution_note: note.presence,
      addressed_by_version_id: version&.id || addressed_by_version_id
    )
  end
  def author_name = by_ai? ? "IA" : (author&.name || "—")
  def kind_label = I18n.t("flow.feedback_kinds.#{kind}")

  # El feedback se dio sobre una versión anterior a la vigente.
  def stale? = idea.stale_for?(idea_version_id)
end
