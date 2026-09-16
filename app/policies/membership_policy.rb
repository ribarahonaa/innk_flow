# frozen_string_literal: true

# Quién administra la empresa administra a su gente.
class MembershipPolicy < ApplicationPolicy
  # La gente de la empresa la ve quien la administra. Vacío, el scope
  # encontraba la membresía y la acción rebotaba recién en el `authorize`: 403
  # por un id que existe y 404 por uno que no, que confirma que existe.
  class Scope < ApplicationPolicy::Scope
    def resolve = membership&.manages_challenges? ? scope.all : scope.none
  end

  def index? = manager?
  def create? = manager?
  def update? = manager?
  def destroy? = manager?
end
