# frozen_string_literal: true

class FeedbackItemPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope; end

  # Dar feedback es abierto a la empresa: la gracia del módulo es que la idea
  # mejore, no filtrar quién opina.
  # Quien acompaña o juzga comenta cualquier idea del desafío. Quien participa
  # comenta solo las suyas: el ida y vuelta entre autores que compiten por el
  # mismo corte no es feedback, es negociación.
  def create?
    return false unless reaches_challenge?(record&.idea&.challenge)
    return true if manager? || membership.gestor? || membership.evaluator?

    record.idea.participates?(membership.user)
  end

  # Cerrar un comentario: quien administra el desafío o el autor de la idea.
  # Quien lo escribió no decide solo si quedó atendido.
  # Cierra quien administra, quien escribió la idea, y el gestor del desafío:
  # marcar que un comentario quedó atendido es parte de acompañar la evolución.
  def resolve?
    return false if membership.nil?
    return true if manager?
    return reaches_challenge?(record.idea.challenge) if membership.gestor?

    record.idea.participates?(membership.user)
  end
end
