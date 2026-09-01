# frozen_string_literal: true

# La idea es IDENTIDAD. Su contenido vive en IdeaVersion.
#
# Nada escribe `current_version_id` a mano: el único camino es
# Flow::Ideas::PublishVersion, que crea la versión y mueve el puntero en una
# transacción.
class Idea < ApplicationRecord
  include TenantScoped

  STATUSES = %w[draft active eliminated withdrawn].freeze
  ORIGINS = %w[human ai].freeze

  belongs_to :challenge
  belongs_to :author, class_name: "User"
  belongs_to :current_version, class_name: "IdeaVersion", optional: true
  belongs_to :eliminated_at_step, class_name: "ChallengeStep", optional: true

  has_many :versions, -> { order(:number) },
           class_name: "IdeaVersion", dependent: :destroy, inverse_of: :idea
  has_many :step_entries, dependent: :destroy
  has_many :assessments, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :origin, inclusion: { in: ORIGINS }

  # El cohorte vivo. `draft` no entra: todavía no se postuló.
  scope :alive, -> { where(status: "active") }
  scope :submitted, -> { where.not(submitted_at: nil) }
  scope :eliminated, -> { where(status: "eliminated") }
  scope :recent, -> { order(created_at: :desc) }

  STATUSES.each { |s| define_method("#{s}?") { status == s } }

  def title = current_version&.title.presence || "(sin título)"

  def payload = current_version&.payload || {}

  def version_count = versions.size

  # ¿Hay una versión posterior a la que juzgó este artefacto? Es cálculo de
  # display: una evaluación anclada a v2 no se invalida porque exista v3, pero
  # la UI tiene que decirlo.
  def stale_for?(version_id)
    version_id.present? && current_version_id.present? && version_id != current_version_id
  end
end
