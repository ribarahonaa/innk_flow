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

  # Lo que hay para revisar en la pantalla de un módulo, que son DOS cosas y no
  # una: lo que apunta al módulo, y lo que se pidió DESDE el módulo sobre una
  # idea. Filtrar sólo por `challenge_step_id` dejaba las tres tareas del
  # segundo grupo sin aparecer nunca en el panel que las pidió.
  #
  # Se filtra por `ai_runs.purpose` y no por el objetivo porque el objetivo no
  # sabe desde dónde se pidió: eso lo declara la tarea.
  scope :para_revisar_en, lambda { |step|
    desde_el_modulo = joins(:ai_run).where(
      ai_runs: { challenge_step_id: step.id,
                 purpose: Flow::AI::Tasks::Base.purposes_revisados_en_el_modulo }
    )

    where(challenge_step_id: step.id).or(where(id: desde_el_modulo.select(:id)))
  }

  STATUSES.each { |s| define_method("#{s}?") { status == s } }

  delegate :purpose, :mode, to: :ai_run

  def target
    challenge_step || idea || challenge
  end

  # El desafío del que cuelga, sea cual sea su objetivo. Lo pregunta la
  # policy, para quién puede revisarla y quién la ve.
  #
  # El último recurso es el run: `TARGETS` todavía admite `criteria_set`, que
  # no trae desafío, y un `nil` acá dejaría la propuesta invisible hasta para
  # quien administra. Hoy ninguna tarea apunta a un set.
  def desafio = challenge || challenge_step&.challenge || idea&.challenge || ai_run&.challenge

  # La pantalla del módulo donde se revisa esta propuesta, o `nil` si se revisa
  # donde vive su objetivo —el caso de casi todas—.
  #
  # Quién pregunta: el panel del módulo, para mostrarla, y el redirect de
  # aceptar, para volver ahí. Los dos derivan de `Tasks::Base.revisa_en`, que
  # es donde está escrita la regla; acá sólo se resuelve a qué módulo.
  #
  # El paso sale del objetivo o del run, igual que en `AiSuggestionPolicy#paso`:
  # las tres tareas que llegan hasta acá apuntan a la idea, así que el módulo lo
  # tiene el run.
  def paso_de_revision
    return nil unless Flow::AI::Tasks::Base.revision_de(purpose) == :modulo

    challenge_step || ai_run&.challenge_step
  end

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
