# frozen_string_literal: true

class AiRunPolicy < ApplicationPolicy
  # La auditoría es entera de quien administra. Vacío, el scope encontraba la
  # corrida y `show` rebotaba recién en el `authorize`: 403 por un id que
  # existe y 404 por uno que no, que le confirma a cualquiera que existe.
  class Scope < ApplicationPolicy::Scope
    def resolve = membership&.manages_challenges? ? scope.all : scope.none
  end

  def index? = manager?
  def show? = manager?
end
