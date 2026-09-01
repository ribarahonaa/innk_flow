# frozen_string_literal: true

class AiSuggestionPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope; end

  # Revisar lo que propone la IA es una decisión de producto: la toma quien
  # administra el desafío, salvo el copiloto sobre la idea propia.
  def accept?
    return true if manager?

    record.idea&.author_id == membership.user_id
  end

  def reject? = accept?
  def index? = manager?
end

