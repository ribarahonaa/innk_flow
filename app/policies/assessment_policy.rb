# frozen_string_literal: true

class AssessmentPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope; end

  # Evalúa quien esté asignado al módulo, o quien lo administra.
  # Nadie evalúa una idea de la que participa —autor o colaborador—, ni
  # siquiera quien administra: el conflicto de interés es el mismo. Postular
  # sigue permitido; lo que no se puede es puntuarse a uno mismo.
  def create?
    return false if membership.nil?
    # Llegar al desafío, que un gestor sólo hace con los que le asignaron. Los
    # controllers de evaluar ya lo filtraban con `policy_scope(Challenge)`,
    # pero aceptar una propuesta de evaluación de la IA pregunta esto sin pasar
    # por ningún scope, y una asignación que sobrevivió a la baja del gestor
    # alcanzaba para escribir una evaluación sobre un desafío que le da 404.
    return false unless reaches_challenge?(record.challenge_step&.challenge)
    return false if record.idea&.participates?(membership.user)
    return true if administers?(record.challenge_step&.challenge)

    record.challenge_step.step_assignments.exists?(user_id: membership.user_id)
  end

  # No hay `update?` propio. `resources :assessments, only: %i[new create]`: una
  # evaluación no se edita, se vuelve a evaluar. El que había —«quien administra,
  # o quien la escribió mientras no la haya enviado»— no tenía ruta, ni llamador,
  # ni cobertura, y era MÁS permisivo que el default heredado (`manager?`): un
  # permiso abierto esperando a que alguien le cableara una ruta. Abrir uno de
  # más no rompe ningún test, que es por qué esto se borra en vez de dejarse.
end
