# frozen_string_literal: true

class ChallengePolicy < ApplicationPolicy
  # Explícita a propósito: Pundit resuelve `ChallengePolicy::Scope` con
  # const_get(..., false), que NO busca en la superclase. Heredar la policy no
  # alcanza para heredar el scope.
  # Un gestor ve SOLO los desafíos que le asignaron.
  #
  # Los controllers buscan el desafío por este scope, así que uno no asignado
  # no da 403 sino 404: un 403 diría «existe pero no es tuyo», que es
  # justamente el oráculo de existencia que el resto del sistema evita.
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all unless gestor?

      scope.where(id: ChallengeGestor.for_user(membership.user).select(:challenge_id))
    end
  end

  def show? = reaches_challenge?(record)

  # Cualquiera de la empresa ve los desafíos; solo quien administra los arma.
  def builder? = manager?
  def start?   = manager? && record.draft?
  def close?   = manager? && record.running?

  # El pipeline solo se edita libremente en borrador; una vez arrancado, la
  # regla del insertion floor limita qué se puede tocar (Flow::Pipeline).
  def update_pipeline? = manager? && !record.closed? && !record.archived?

  # Mirar el pool entero de ideas para decidir qué se fusiona o se descarta
  # —hoy, detectar duplicados—: quien administra y quien acompaña el desafío.
  #
  # Quien participa no: la comparación devuelve títulos y resúmenes de ideas
  # ajenas, y quien participa ve sólo las suyas. Quien evalúa tampoco: puntúa
  # lo que se le asigna, no decide qué se fusiona. Y no mira si hay una ronda
  # de evolución abierta, porque comparar no edita ninguna idea.
  def curate_pool? = manager? || (membership.present? && membership.gestor? && reaches_challenge?(record))
end
