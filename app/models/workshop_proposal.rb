# frozen_string_literal: true

# Lo que una mesa propone sobre una idea que ya existe, en un módulo de
# evolución. El autor la acepta y ahí se publica la versión.
class WorkshopProposal < ApplicationRecord
  include TenantScoped

  STATUSES = %w[pending accepted rejected].freeze

  belongs_to :workshop_group
  belongs_to :idea
  belongs_to :challenge_step
  belongs_to :reviewed_by, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :pending_review, -> { where(status: "pending") }

  STATUSES.each { |s| define_method("#{s}?") { status == s } }

  # Aceptar publica una versión con `source_step` de ESTA ronda. Publicar
  # dentro de una ronda cerrada escribiría en una conversación terminada, así
  # que una propuesta se vence con su ronda. Mismo predicado perezoso que
  # `WorkshopChallenge#workable?`: no hay estado `expired` que alguien tenga
  # que escribir.
  def actionable? = pending? && challenge_step.active?
end
