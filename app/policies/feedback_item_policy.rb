# frozen_string_literal: true

class FeedbackItemPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope; end

  # Dar feedback es abierto a la empresa: la gracia del módulo es que la idea
  # mejore, no filtrar quién opina.
  def create? = membership.present?

  # Cerrar un comentario: quien administra el desafío o el autor de la idea.
  # Quien lo escribió no decide solo si quedó atendido.
  def resolve?
    return false if membership.nil?
    return true if manager?

    record.idea.author_id == membership.user_id
  end
end
