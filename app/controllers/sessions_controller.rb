# frozen_string_literal: true

# Login propio. Rails 7.1 no trae el generador `authentication` de Rails 8, así
# que esto es a mano: bcrypt + una fila en `sessions` + cookie firmada.
#
# El día que el login se delegue en innk_r5, lo que cambia es de dónde sale el
# `user` en #create — Identity ya está modelada para eso.
class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: %i[new create]
  # `destroy` también: sin esto, quien se quedó sin ninguna membresía rebota
  # contra `require_company` al apretar «Cerrar sesión» y vuelve al selector.
  # El único botón de esa pantalla no puede ser el que lo deja encerrado.
  skip_before_action :require_company,
                     only: %i[new create destroy select_company choose_company]

  layout "auth", only: %i[new]

  def new
    redirect_to root_path if signed_in?
  end

  def create
    user = User.find_by(email: params[:email].to_s.strip.downcase)

    if user&.authenticate(params[:password].to_s)
      session_record = sign_in!(user, company: default_company_for(user))
      redirect_to(session_record.company ? root_path : select_company_path)
    else
      # Mensaje único: no se distingue "email inexistente" de "clave incorrecta".
      flash.now[:alert] = t("auth.invalid_credentials")
      render :new, layout: "auth", status: :unprocessable_content
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
