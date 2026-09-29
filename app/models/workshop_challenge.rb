# frozen_string_literal: true

# El vínculo de un taller con UN desafío, y con el módulo concreto contra el
# que trabaja.
#
# Apunta al módulo y no a la fase: de ahí salen el modo de la sala (el `kind`),
# el cierre automático (el módulo dejó de estar activo) y el
# `challenge_step_id` correcto para las propuestas —que es lo que evita
# mezclar dos rondas de evolución—.
class WorkshopChallenge < ApplicationRecord
  include TenantScoped

  STATUSES = %w[open closed].freeze
  # Las dos únicas fases sobre las que un taller tiene algo que hacer.
  WORKABLE_KINDS = %w[ideation evolution].freeze

  belongs_to :workshop
  belongs_to :challenge
  belongs_to :challenge_step, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :challenge_id, uniqueness: { scope: :workshop_id }

  STATUSES.each { |s| define_method("#{s}?") { status == s } }

  # Perezoso a propósito: nada se engancha en `advance!`. El taller se entera
  # de que el desafío avanzó; no interviene.
  #
  # «Activo» es lo que dice el motor: `Flow::Pipeline#active_step` acepta
  # `active?` y también `activating?`. Con solo `active?`, si algún día se
  # escribe `activating`, `Open` vincularía un módulo y la sala nacería
  # invisible. Hoy nada escribe `activating`; el predicado ya no lo asume.
  def workable? = status == "open" && challenge_step.present? && (challenge_step.active? || challenge_step.activating?)

  def kind = challenge_step&.kind

  # Qué cara toca dibujar en la sala, en UN solo valor.
  #
  # Existe porque la pantalla resolvía esto con una cadena de `elsif` SIN
  # rama por defecto, y el vínculo que avanzó —`open` con su módulo ya
  # `completed`, el estado en que queda TODO vínculo tras un `advance!`— no
  # caía en ninguna: la sala se renderizaba vacía, sin un solo mensaje. Con un
  # valor cerrado y un `case` con `else`, el silencio es imposible: un estado
  # nuevo cae en la rama por defecto y se ve.
  #
  # :unopened es el vínculo de un taller que TODAVÍA NO SE ABRIÓ. Ahí
  # `challenge_step_id` es nulo a propósito —lo resuelve `Flow::Workshops::Open`—
  # y `workable?` es false, igual que en el vínculo que venció: sin este valor
  # los dos caían en la misma rama y un borrador recién armado anunciaba «el
  # desafío avanzó de fase», que es falso. Es el mismo estado que
  # `MaterializeClosures` ya protegía del lado de la ESCRITURA.
  #
  # :stale es el vínculo que todavía no pasó por `MaterializeClosures`. En la
  # pantalla no debería verse —el controller materializa antes de renderizar—,
  # pero tiene nombre para que no vuelva a ser un hueco.
  def room_state
    return :closed if closed?
    return :unopened if workshop.draft?
    return :stale unless workable?

    WORKABLE_KINDS.include?(kind) ? kind.to_sym : :stale
  end
end
