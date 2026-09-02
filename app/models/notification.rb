# frozen_string_literal: true

# Un aviso para una persona.
#
# In-app y no mail: un mailer sin proveedor real sería una promesa que no se
# puede verificar, y la maqueta se verifica de punta a punta. La costura para
# sumar mail después es `Flow::Notifications::Notify`, que es el único escritor
# y el lugar donde se encolaría el envío.
class Notification < ApplicationRecord
  include TenantScoped

  # Los tres momentos en que alguien tiene que enterarse de algo sin estar
  # mirando: le tocó trabajo, su idea recibió comentarios, o su idea avanzó o
  # quedó fuera.
  KINDS = %w[assigned_to_evaluate feedback_received idea_advanced idea_eliminated].freeze

  belongs_to :user
  belongs_to :challenge, optional: true
  belongs_to :challenge_step, optional: true
  belongs_to :idea, optional: true

  validates :kind, inclusion: { in: KINDS }

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  def read? = read_at.present?

  def read!
    update!(read_at: Time.current) unless read?
  end

  def title = I18n.t("flow.notifications.#{kind}.title", **symbolized_payload)
  def body = I18n.t("flow.notifications.#{kind}.body", **symbolized_payload)

  # A dónde lleva el aviso. Siempre al lugar donde se hace algo con él, no a
  # una pantalla de detalle del aviso: la notificación es un atajo, no un
  # destino.
  def path
    routes = Rails.application.routes.url_helpers

    case kind
    when "assigned_to_evaluate"
      challenge_step && routes.challenge_step_path(challenge, challenge_step)
    else
      idea && routes.challenge_idea_path(challenge, idea)
    end
  end

  private

  def symbolized_payload = payload.to_h.symbolize_keys
end
