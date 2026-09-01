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
  def evaluator? = membership.present? && (membership.evaluator? || manager?)

  class Scope
    attr_reader :membership, :scope

    def initialize(membership, scope)
      @membership = membership
      @scope = scope
    end

    # El scope de tenancy ya lo aplica TenantScoped; acá solo van reglas de rol.
    def resolve = scope.all
  end
end
