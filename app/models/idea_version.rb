# frozen_string_literal: true

# Snapshot COMPLETO e inmutable del contenido de una idea.
#
# Inmutable de verdad: una vez creada no se actualiza. Cambiar la idea crea
# una versión nueva. Eso es lo que permite que una evaluación diga con
# precisión qué texto juzgó.
class IdeaVersion < ApplicationRecord
  include TenantScoped

  ACTOR_TYPES = %w[human ai].freeze

  belongs_to :idea
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :source_step, class_name: "ChallengeStep", optional: true

  has_many :attachments, class_name: "IdeaAttachment", dependent: :destroy,
                         foreign_key: :idea_version_id, inverse_of: :idea_version

  validates :number, presence: true, uniqueness: { scope: :idea_id }
  validates :actor_type, inclusion: { in: ACTOR_TYPES }

  validate :immutability, on: :update

  scope :chronological, -> { order(:number) }

  def label = "v#{number}"

  def current? = idea.current_version_id == id

  def by_ai? = actor_type == "ai"

  def author_name
    return "IA" if by_ai?

    created_by&.name || "—"
  end

  private

  # Una versión que se puede editar deja de ser un registro histórico.
  def immutability
    return if changed.empty?

    errors.add(:base, "una versión publicada es inmutable: creá una nueva")
  end
end
