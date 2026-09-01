# frozen_string_literal: true

# El veredicto sobre un criterio de una selección: pasa o no pasa.
#
# Es lo que permite que una selección se resuelva por juicio —de una persona o
# de la IA— y no solo por un corte de puntaje.
class SelectionVerdict < ApplicationRecord
  include TenantScoped

  belongs_to :challenge_step
  belongs_to :idea
  belongs_to :idea_version
  belongs_to :criterion, optional: true
  belongs_to :decided_by, class_name: "User", optional: true
  belongs_to :ai_run, optional: true

  validates :criterion_key, presence: true,
                            uniqueness: { scope: %i[challenge_step_id idea_id] }

  scope :passing, -> { where(passed: true) }

  def by_ai? = actor_type == "ai"
  def decided_by_name = by_ai? ? "IA" : (decided_by&.name || "—")
end
