# frozen_string_literal: true

# Pundit, no CanCanCan.
#
# El `ability.rb` de innk_r5 tiene 2045 líneas en un solo `initialize`, y es
# exactamente el archivo donde se escondieron las fugas de `can :manage`
# pelado. Una policy por recurso mantiene la superficie legible y auditable.
#
# `user` acá es el MEMBERSHIP, no el User: el rol es por empresa.
class ApplicationPolicy
  attr_reader :membership, :record

  def initialize(membership, record)
    @membership = membership
    @record = record
  end

  def index?   = membership.present?
  def show?    = membership.present?
  def create?  = manager?
  def update?  = manager?
  def destroy? = manager?

  # Convención de Pundit: `authorize` en #new busca new?, en #edit busca edit?.
  def new?  = create?
  def edit? = update?

  private

  def manager? = membership.present? && membership.manages_challenges?

  # Un gestor solo entra a los desafíos que le asignaron.
  #
  # Es la regla que rompe la equivalencia «tener membresía = ver todo lo de la
  # empresa». Vale para el desafío y para todo lo que cuelga de él: si se
  # chequeara solo en la pantalla del desafío, la URL de una idea seguiría
  # abierta.
  def reaches_challenge?(challenge)
    return false if membership.nil?
    return true unless membership.gestor?
    return false if challenge.nil?

    ChallengeGestor.exists?(challenge_id: challenge.id, user_id: membership.user_id)
  end

  # Administrar ESTE desafío: quien administra la empresa, y el gestor al que
  # se lo asignaron.
  #
  # `manager?` se queda significando «administra la empresa», y es lo que
  # protege lo que no cuelga de ningún desafío: la gente, la biblioteca de
  # criterios y la auditoría de IA. De rebote, una puerta nueva escrita con
  # `manager?` nace cerrada para el gestor, que es el lado seguro.
  #
  # El desafío llega por cadenas opcionales (`record.challenge_step&.challenge`),
  # así que tiene que aceptar `nil` sin reventar: para un gestor eso es `false`
  # y un admin ya salió antes por `manager?`.
  def administra?(challenge)
    manager? || (membership.present? && membership.gestor? && reaches_challenge?(challenge))
  end

  class Scope
    attr_reader :membership, :scope

    def initialize(membership, scope)
      @membership = membership
      @scope = scope
    end

    # El scope de tenancy ya lo aplica TenantScoped; acá solo van reglas de rol.
    #
    # Sin membresía, nada. La sesión guarda la empresa elegida y no vuelve a
    # pedir la membresía, así que a quien se la sacaron le queda el tenant
    # puesto y `membership` en `nil`: con `scope.all` a secas, todo `Scope`
    # que no sobreescribiera esto le mostraba la empresa entera.
    def resolve = membership.nil? ? scope.none : scope.all

    def gestor? = membership.present? && membership.gestor?
  end
end
