# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include TenantResolution

  before_action :require_authentication
  before_action :require_company

  # Falla si un controller olvida autorizar. En innk_r5 la autorización es
  # opt-in por controller, y esa opcionalidad fue parte del problema.
  #
  # Va sin `only:`/`except:`: Rails 7.1 levanta ActionNotFound si un callback
  # heredado nombra una acción que el controller hijo no tiene. El despacho se
  # decide en runtime.
  after_action :verify_pundit_usage, unless: :skip_pundit?

  private

  # Pundit recibe el MEMBERSHIP, no el user: el rol es por empresa.
  def pundit_user = current_membership

  # Entregar un archivo adjunto. Vive acá, y no en cada controller que sirve
  # uno, porque los tres detalles que importan tienen que decidirse una sola
  # vez: que esté adjunto, cómo se declara el tipo y que vaya como descarga.
  def send_attached_file(attached)
    # Sin adjuntar, `download` y `content_type` devuelven nil y `send_data`
    # revienta con 500. El caso llega de verdad: un reporte `dashboard` nace
    # `ready` sin archivo, y una fila de adjunto se crea antes de adjuntarle.
    raise ActiveRecord::RecordNotFound unless attached.attached?

    send_data attached.download,
              filename: attached.filename.to_s,
              # `content_type_for_serving` fuerza octet-stream para html, svg y
              # compañía. Hoy es redundante con `disposition: "attachment"`, que
              # ya hace que el navegador baje en vez de renderizar; deja de serlo
              # el día que alguien quiera previsualizar algo inline, y ahí el
              # archivo lo subió cualquiera que postula.
              type: attached.blob.content_type_for_serving,
              disposition: "attachment"
  end

  def verify_pundit_usage
    action_name == "index" ? verify_policy_scoped : verify_authorized
  end

  # La sesión no tiene qué autorizar: todavía no hay membresía con la cual.
  def skip_pundit?
    is_a?(SessionsController)
  end
end
