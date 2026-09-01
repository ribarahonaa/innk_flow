# frozen_string_literal: true

# Un evento de selección. No se edita ni se borra: si una idea se repesca, se
# escribe OTRA fila con outcome "reinstate".
class SelectionDecision < ApplicationRecord
  include TenantScoped

  OUTCOMES = %w[advance eliminate reinstate].freeze

  belongs_to :challenge_step
  belongs_to :idea
  belongs_to :idea_version
  belongs_to :decided_by, class_name: "User", optional: true

  validates :outcome, inclusion: { in: OUTCOMES }

  scope :chronological, -> { order(:decided_at) }
  scope :latest_first, -> { order(decided_at: :desc) }

  OUTCOMES.each { |o| define_method("#{o}?") { outcome == o } }

  def decided_by_name = decided_by&.name || (actor_type == "ai" ? "IA" : "—")

  def label
    { "advance" => "avanzó", "eliminate" => "no avanzó", "reinstate" => "repescada" }[outcome]
  end
end
