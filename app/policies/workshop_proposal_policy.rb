# frozen_string_literal: true

class WorkshopProposalPolicy < ApplicationPolicy
  # Una propuesta cuelga de una idea, así que hereda su visibilidad: se ve
  # lo que se ve la idea. Sin esto la herencia daría `membership.present?`.
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if membership.nil?

      visible = IdeaPolicy::Scope.new(membership, Idea).resolve.select(:id)
      scope.where(idea_id: visible)
    end
  end

  # Aceptar y descartar son de QUIEN ES AUTOR de la idea, ni siquiera de quien
  # administra: el sentido del paso es que a nadie le reescriban la idea sin
  # que participe. Un atajo para quien administra lo borraría.
  def accept? = author?
  def reject? = author?

  private

  def author?
    membership.present? && record.idea.author_id == membership.user_id
  end
end
