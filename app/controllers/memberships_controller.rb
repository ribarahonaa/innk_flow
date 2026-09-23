# frozen_string_literal: true

# Quiénes están en la empresa y con qué rol.
#
# Hasta acá los roles solo se sembraban: no había forma de convertir a alguien
# en gestor sin entrar por consola, que es un requisito imposible para un rol
# que se contrata por desafío.
#
# Los usuarios son GLOBALES —una persona trabaja para varias empresas— así que
# "invitar" es encontrar o crear a la persona por su email y darle una
# membresía acá. Su rol en otra empresa no se toca.
class MembershipsController < ApplicationController
  before_action :set_membership, only: %i[update destroy]

  def index
    authorize Membership, :index?
    @memberships = policy_scope(Membership).includes(:user).order("users.name")
  end

  def create
    authorize Membership, :create?

    email = params[:email].to_s.strip.downcase
    return redirect_to(members_path, alert: "Falta el email.") if email.blank?

    persona = find_or_invite(email)
    return redirect_to(members_path, alert: persona.errors.full_messages.to_sentence) if persona.errors.any?

    membership = Membership.new(user: persona, role: params[:role])

    if membership.save
      redirect_to members_path, notice: "#{persona.name} entró como #{rol(membership)}."
    else
      redirect_to members_path, alert: membership.errors.full_messages.to_sentence
    end
  end

  def update
    authorize @membership, :update?
    return redirect_to(members_path, alert: ultimo_admin) if quita_al_ultimo_admin?

    if @membership.update(role: params[:role])
      redirect_to members_path, notice: "#{@membership.user.name} ahora es #{rol(@membership)}."
    else
      redirect_to members_path, alert: @membership.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @membership, :destroy?
    return redirect_to(members_path, alert: se_saca_a_si_mismo) if propia?
    return redirect_to(members_path, alert: ultimo_admin) if quita_al_ultimo_admin?

    @membership.destroy!
    redirect_to members_path, notice: "Ya no forma parte de esta empresa."
  end

  private

  # Por `policy_scope`: una membresía que no ves no existe.
  def set_membership = @membership = policy_scope(Membership).find(params[:id])

  def rol(membership) = t("flow.roles.#{membership.role}")

  # Sacarse a uno mismo deja afuera en el acto y sin vuelta: después del
  # redirect ya no hay empresa donde volver y sólo otra persona que administre
  # puede reponer la membresía. La guarda del último admin no alcanza —con
  # otro admin en la empresa deja pasar—, y es hermana de la que
  # `ChallengeGestoresController#destroy` tiene un nivel más abajo.
  #
  # Sacar a OTRO sigue siendo parte de administrar la empresa. Y cambiarse el
  # propio ROL no entra acá: es recuperable, y lo que no debe pasar —quedarse
  # sin nadie que administre— ya lo ataja `quita_al_ultimo_admin?`.
  def propia? = @membership.user_id == current_user.id

  def se_saca_a_si_mismo
    "No podés sacarte de #{current_company.name} vos mismo: pedíselo a otra persona que la administre."
  end

  # Una empresa sin nadie que la administre no se puede volver a administrar:
  # no queda quién invite ni quién cambie roles.
  def quita_al_ultimo_admin?
    return false unless @membership.admin?
    return false if params[:role] == "admin"

    Membership.where(role: "admin").where.not(id: @membership.id).none?
  end

  def ultimo_admin
    "#{@membership.user.name} es la única persona que administra esta empresa: " \
      "nombrá a otra antes de sacarla."
  end

  # El usuario es global —no lleva company_id— así que buscarlo por email no
  # necesita levantar el aislamiento: si ya existe, se le suma la membresía.
  def find_or_invite(email)
    User.find_by(email: email) ||
      User.create(email: email, name: params[:name].presence || email.split("@").first.humanize,
                  password: SecureRandom.alphanumeric(16))
  end
end
