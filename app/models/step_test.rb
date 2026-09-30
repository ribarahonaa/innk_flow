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
  # Sin `created_at` dos filas con el mismo `tested_at` salen en el orden que
  # quiera Postgres. Mismo desempate que `Criterion.ordered`. Ojo: esto NO tiene
  # test propio, y a propósito — un ejemplo sobre el empate pasa o falla según
  # cómo ordene Postgres dos filas iguales, así que daría verde por suerte, que
  # es justo lo que no queremos de un test.
  scope :recientes, -> { order(tested_at: :desc, created_at: :desc) }

  # El vigente antes que los superados, pase lo que pase con las fechas.
  #
  # `Testing#historial_de` promete «el vigente primero» y lo daba `recientes` por
  # COINCIDENCIA: `testear!` supersede el anterior y crea el nuevo con un
  # `Time.current` posterior, así que el vigente siempre tenía el máximo
  # `tested_at`. Eso es una propiedad del único escritor, no del orden, y un
  # segundo escritor con su propio `tested_at` —un backfill, una importación, un
  # veredicto fechado por el modelo— mostraba como actual uno ya superado.
  #
  # Va aparte de `recientes` porque «recientes» significa por recencia: meterle
  # el vigente adelante lo volvería mentiroso para cualquier otro llamador.
  scope :vigente_primero, -> { order(Arel.sql("superseded_at IS NULL DESC")) }

  def by_ai? = actor_type == "ai"
  def tested_by_name = by_ai? ? "IA" : (tested_by&.name || "—")

  # Las situaciones que se rompieron: la evidencia que sostiene el veredicto.
  def situaciones_rotas = situations.select { |s| s["resultado"] == "se_rompe" }
end
