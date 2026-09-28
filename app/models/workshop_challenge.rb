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
  def workable? = status == "open" && challenge_step.present? && challenge_step.active?

  def kind = challenge_step&.kind
end
