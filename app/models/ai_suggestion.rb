# frozen_string_literal: true

# Una propuesta de la IA, materializada y revisable.
#
# `ai_auto` no saltea este objeto: lo crea ya aceptado (`auto_accepted_at`).
# Un solo camino para los tres modos.
class AiSuggestion < ApplicationRecord
  include TenantScoped

  STATUSES = %w[pending accepted edited rejected].freeze
  TARGETS = %i[challenge challenge_step idea criteria_set].freeze

  belongs_to :ai_run
  belongs_to :challenge, optional: true
  belongs_to :challenge_step, optional: true
  belongs_to :idea, optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }
  validate :exactly_one_target

  scope :pending_review, -> { where(status: "pending") }
  scope :recent, -> { order(created_at: :desc) }

  STATUSES.each { |s| define_method("#{s}?") { status == s } }

  delegate :purpose, :mode, to: :ai_run

  def target
    challenge_step || idea || challenge
  end

  # El desafío del que cuelga, sea cual sea su objetivo. Lo preguntan la
  # policy —quién puede revisarla— y el controller —quién la ve—, que tienen
  # que llegar al mismo desafío por el mismo camino.
  def desafio = challenge || challenge_step&.challenge || idea&.challenge

  def resolved? = !pending?

  # ¿Lo que propone es para LEER y no para aplicar? Lo declara la tarea.
  # Lo preguntan la tarjeta —que ofrece un solo «Listo» en vez de «Aplicar» y
  # «Descartar»— y el controller, que si no anuncia que aplicó algo que su
  # `apply!` no hizo.
  def informativa? = Flow::AI::Tasks::Base.informativa?(purpose)

  # La tarea que produjo esta propuesta, con el contexto de su run: la tarjeta
  # la necesita para el `preview`. `nil` si el propósito no existe —ahí se
  # muestra el payload crudo, que es mejor que una pantalla caída—.
  #
  # Acá y no en el partial porque el rescue tiene que ir acotado, y un
  # `begin/rescue/end` no entra en HAML —no acepta `- end`—: el modificador
  # `rescue nil` que había atrapaba `StandardError` entero y taparía un error
  # de verdad.
  def tarea
    Flow::AI::Tasks::Base.for(purpose, challenge: ai_run.challenge,
                                       step: ai_run.challenge_step, idea: ai_run.idea)
  rescue ArgumentError
    nil
  end

  private

  # Espeja el CHECK de la base. La restricción real vive en Postgres; esto es
  # para que el error llegue como validación y no como excepción de driver.
  def exactly_one_target
    present = [challenge_id, challenge_step_id, idea_id, criteria_set_id].count(&:present?)
    return if present == 1

    errors.add(:base, "una sugerencia apunta a exactamente un objetivo (hay #{present})")
  end
end
