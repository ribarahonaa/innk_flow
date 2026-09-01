# frozen_string_literal: true

# Resuelve sesión y empresa activa, y las limpia al terminar el request.
#
# Regla dura: ante un recurso de OTRA empresa se responde 404, nunca 403. Un
# 403 confirma que el recurso existe, y eso convierte cualquier listado de ids
# en un oráculo de existencia cross-tenant.
module TenantResolution
  extend ActiveSupport::Concern

  included do
    around_action :with_tenant_context
    helper_method :current_user, :current_company, :current_membership, :signed_in?

    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
    rescue_from TenantScoped::MissingTenant, with: :render_not_found
    rescue_from Pundit::NotAuthorizedError, with: :render_forbidden
  end

  private

  def with_tenant_context
    Current.request_id = request.request_id
    Current.session = current_session
    Current.user = current_session&.user
    Current.company = current_session&.company
    yield
  ensure
    Current.reset
  end

  def current_session
    return @current_session if defined?(@current_session)

    token = cookies.signed[:session_token]
    @current_session = token.presence && Session.find_by(token: token)
  end

  def current_user = Current.user
  def current_company = Current.company
  def signed_in? = Current.user.present?

  def current_membership
    return @current_membership if defined?(@current_membership)

    @current_membership = Current.user && Current.company &&
                          Membership.where(company_id: Current.company.id, user_id: Current.user.id).first
  end

  def require_authentication
    return if signed_in?

    redirect_to login_path, alert: t("auth.sign_in_required")
  end

  def require_company
    return if current_company

    redirect_to select_company_path
  end

  def render_not_found
    respond_to do |format|
      format.html { render "errors/not_found", status: :not_found, layout: "application" }
      format.json { render json: { error: "not_found" }, status: :not_found }
    end
  end

  def render_forbidden
    respond_to do |format|
      format.html { render "errors/forbidden", status: :forbidden, layout: "application" }
      format.json { render json: { error: "forbidden" }, status: :forbidden }
    end
  end
end
