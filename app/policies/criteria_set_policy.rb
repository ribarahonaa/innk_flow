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
end

