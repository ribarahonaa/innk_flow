# frozen_string_literal: true

class AiSuggestionPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope; end

  # Aceptar o descartar lo que propuso la IA sigue exactamente la misma regla
  # que pedirlo: depende de sobre QUÉ actúa la tarea, y eso lo declara la tarea.
  #
  # Antes era «quien administra, o el autor de la idea». Con esa regla quien
  # acompaña la evolución no podía aplicar el feedback que la IA propuso —que
  # es literalmente su trabajo— y quien colabora en una idea tampoco, aunque
  # la viera.
  def accept?
    return false if membership.nil?
    return true if manager?

    case Flow::AI::Tasks::Base.scope_of(record.purpose)
    when :idea then IdeaPolicy.new(membership, record.idea).update?
    when :feedback then FeedbackItemPolicy.new(membership, comentario).create?
    when :assessment then AssessmentPolicy.new(membership, evaluacion).create?
    else false
    end
  end

  def reject? = accept?
  def index? = manager?

  private

  # Un comentario de mentira, para preguntarle a la política de feedback si
  # esta persona podría escribirlo. Es la misma pregunta.
  def comentario
    FeedbackItem.new(idea: record.idea, challenge_step: paso)
  end

  # Igual que arriba, pero para evaluar. Va SIN la idea a propósito: la
  # pregunta es si esta persona evalúa en este módulo, no si podría evaluar esa
  # idea. Quien participa de una idea no la puntúa —ese es el conflicto de
  # interés—, pero pedirle a la IA que la evalúe no pone su nota: pone la de la
  # IA. Y bloquearlo trabaría el módulo, porque el mínimo por idea ya baja
  # contando a la IA como quien evalúa lo que su autor no puede.
  def evaluacion
    Assessment.new(challenge_step: paso)
  end

  def paso = record.challenge_step || record.ai_run&.challenge_step
end
