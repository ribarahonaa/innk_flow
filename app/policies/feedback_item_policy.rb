# frozen_string_literal: true

class FeedbackItemPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope; end

  # Dar feedback es abierto a la empresa: la gracia del módulo es que la idea
  # mejore, no filtrar quién opina.
  def create? = membership.present?
end
