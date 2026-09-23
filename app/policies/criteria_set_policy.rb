# frozen_string_literal: true

class CriteriaSetPolicy < ApplicationPolicy
  # La biblioteca es de la empresa: se comparte entre desafíos. Un set `inline`
  # es de UN módulo, así que se ve si se ve su desafío — y quien acompaña ve
  # sólo los desafíos que le asignaron.
  #
  # No tenía nada propio: con `show? = membership.present?` heredado, abrir un
  # set por id le mostraba a un gestor los criterios de un desafío que no ve.
  # No era confirmar que existía: era leerlo.
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if membership.nil?
      return scope.all unless gestor?

      desafios = ChallengePolicy::Scope.new(membership, Challenge).resolve.select(:id)
      modulos = ChallengeStep.where(challenge_id: desafios).select(:id)

      scope.where(scope: "library").or(scope.where(owner_step_id: modulos))
    end
  end

  # Un set `inline` es de UN módulo: lo guarda quien administra ese desafío, y
  # desde que el gestor administra los suyos, también él. Sin esto el editor de
  # criterios se le renderiza por `configure?` y el guardado le rebota: el
  # control fantasma de siempre.
  #
  # Un set `library` se comparte entre TODOS los desafíos de la empresa,
  # incluidos los que el gestor no ve, así que sigue siendo de quien administra
  # la empresa.
  def update?
    return manager? if record.library?

    administers?(record.owner_step&.challenge)
  end

  # Un set nace de biblioteca: lo crea el editor (`scope: "library"`) o el
  # botón de promover, que copia uno `inline` a la biblioteca. Las dos cosas
  # escriben patrimonio común.
  def create? = manager?

  # Borrar es una acción de las pantallas de biblioteca; un set `inline` se va
  # solo con su módulo.
  def destroy? = manager?
end

