# frozen_string_literal: true

# Un testeo de factibilidad sobre UNA versión de UNA idea.
#
# Append-only: re-testear no edita el anterior, lo marca `superseded_at` y
# escribe otro. El vigente es el que tiene `superseded_at` en nil, y que haya
# uno solo lo garantiza un índice parcial, no una validación.
class StepTest < ApplicationRecord
  include TenantScoped

  VERDICTS = %w[factible con_reservas no_factible].freeze

  belongs_to :challenge_step
  belongs_to :idea
  belongs_to :idea_version
  belongs_to :tested_by, class_name: "User", optional: true
  belongs_to :ai_run, optional: true

  validates :verdict, inclusion: { in: VERDICTS }

  scope :vigentes, -> { where(superseded_at: nil) }
  scope :recientes, -> { order(tested_at: :desc) }

  def by_ai? = actor_type == "ai"
  def tested_by_name = by_ai? ? "IA" : (tested_by&.name || "—")

  # Las situaciones que se rompieron: la evidencia que sostiene el veredicto.
  def situaciones_rotas = situations.select { |s| s["resultado"] == "se_rompe" }
end
