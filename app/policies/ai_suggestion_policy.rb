# frozen_string_literal: true

class AiSuggestionPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope; end

  # Aceptar o descartar lo que propuso la IA es la misma pregunta que pedirlo:
  # depende de sobre QUÉ actúa la tarea, y eso lo declara la tarea.
  #
  # Antes era «quien administra, o el autor de la idea». Con esa regla quien
  # acompaña la evolución no podía aplicar el feedback que la IA propuso —que
  # es literalmente su trabajo— y quien colabora en una idea tampoco, aunque
  # la viera.
  #
  # Y no es sólo la misma regla: es el mismo método. `AiRequestsController`
  # pregunta `request?` con una propuesta armada a partir del pedido. Tuvo el
  # mapeo copiado allá y divergió: acá arrancaba con `return true if
  # manager?`, así que quien administra aplicaba sobre un desafío cerrado una
  # propuesta que ya no podía pedir.
  def accept?
    return false if membership.nil?

    alcance = Flow::AI::Tasks::Base.scope_of(record.purpose)

    return IdeaPolicy.new(membership, record.idea).update? if alcance == :idea && record.idea
    return FeedbackItemPolicy.new(membership, comentario).create? if alcance == :feedback && record.idea
    return AssessmentPolicy.new(membership, evaluacion).create? if alcance == :assessment && paso

    ChallengePolicy.new(membership, desafio).update_pipeline?
  end

  def request? = accept?
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

  # Una propuesta cuelga de UN objetivo —el desafío, el módulo o la idea—, así
  # que el desafío hay que buscarlo en el que tenga.
  def desafio = record.challenge || paso&.challenge || record.idea&.challenge
end
