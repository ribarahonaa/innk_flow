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

  def verify_pundit_usage
    action_name == "index" ? verify_policy_scoped : verify_authorized
  end

  # Sesión y páginas sin recurso no tienen qué autorizar.
  def skip_pundit?
    is_a?(SessionsController) || is_a?(PagesController)
  end
end
