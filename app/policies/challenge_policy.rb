# frozen_string_literal: true

class ChallengePolicy < ApplicationPolicy
  # Explícita a propósito: Pundit resuelve `ChallengePolicy::Scope` con
  # const_get(..., false), que NO busca en la superclase. Heredar la policy no
  # alcanza para heredar el scope.
  class Scope < ApplicationPolicy::Scope; end

  # Cualquiera de la empresa ve los desafíos; solo quien administra los arma.
  def builder? = manager?
  def start?   = manager? && record.draft?
  def close?   = manager? && record.running?

  # El pipeline solo se edita libremente en borrador; una vez arrancado, la
  # regla del insertion floor limita qué se puede tocar (Flow::Pipeline).
  def update_pipeline? = manager? && !record.closed? && !record.archived?
end
