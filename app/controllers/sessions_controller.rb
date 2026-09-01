# frozen_string_literal: true

# Login propio. Rails 7.1 no trae el generador `authentication` de Rails 8, así
# que esto es a mano: bcrypt + una fila en `sessions` + cookie firmada.
#
# El día que el login se delegue en innk_r5, lo que cambia es de dónde sale el
# `user` en #create — Identity ya está modelada para eso.
class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: %i[new create]
  skip_before_action :require_company, only: %i[new create select_company choose_company]

  layout "auth", only: %i[new]

  def new
    redirect_to root_path if signed_in?
  end

  def create
    user = User.find_by(email: params[:email].to_s.strip.downcase)

    if user&.authenticate(params[:password].to_s)
      session_record = user.sessions.create!(
        company: default_company_for(user),
        ip_address: request.remote_ip,
        user_agent: request.user_agent.to_s.first(255),
        last_seen_at: Time.current
      )
      cookies.signed.permanent[:session_token] = { value: session_record.token, httponly: true, same_site: :lax }
      redirect_to(session_record.company ? root_path : select_company_path)
    else
      # Mensaje único: no se distingue "email inexistente" de "clave incorrecta".
      flash.now[:alert] = t("auth.invalid_credentials")
      render :new, layout: "auth", status: :unprocessable_entity
    end
  end

  def destroy
    current_session&.destroy
    cookies.delete(:session_token)
    redirect_to login_path, notice: t("auth.signed_out")
  end

  # Selector de empresa. La maqueta no usa subdominios (a diferencia de r5):
  # una persona puede tener membresías en varias empresas y elige acá.
  def select_company
    @memberships = current_user.all_memberships
  end

  def choose_company
    membership = Flow::Tenant.bypass! do
      current_user.memberships.find_by(company_id: params[:company_id])
    end
    raise ActiveRecord::RecordNotFound unless membership

    current_session.update!(company_id: membership.company_id)
    redirect_to root_path
  end

  private

  # Con una sola membresía no tiene sentido preguntar.
  def default_company_for(user)
    memberships = user.all_memberships
    memberships.first&.company if memberships.one?
  end
end
