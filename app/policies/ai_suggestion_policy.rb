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
    return ChallengePolicy.new(membership, desafio).curate_pool? if alcance == :pool

    ChallengePolicy.new(membership, desafio).update_pipeline?
  end

  def request? = accept?

  # ¿La ve? Lo que no ve da 404, no un 403 que confirme que existe.
  #
  # Quien administra ve todas, en la auditoría (`/admin/ai_runs`). Cualquier
  # otra persona ve una propuesta si le aparece en un panel —que filtra por
  # `accept?`— Y si ve aquello sobre lo que actúa: el desafío y, si la tiene,
  # la idea. Las dos cosas, porque los paneles viven en pantallas que ya
  # filtraron por desafío e idea, y la regla tiene que filtrar igual.
  #
  # Llevó tres intentos, y cada uno falló por una de las dos mitades:
  #
  #   · `accept?` a secas volvía 404 el 403 legítimo de quien administra un
  #     desafío cerrado —ve la propuesta y ya no la puede aplicar—.
  #   · «se ve si se ve su objetivo» le dejaba 403 a quien participa por una
  #     propuesta del flujo, que no le aparece en ningún lado.
  #   · `manager? || accept?` confiaba en `accept?`, y para una evaluación eso
  #     es `AssessmentPolicy#create?` sin idea: sólo miraba la asignación. Un
  #     gestor dado de baja con la asignación intacta, o alguien que evaluaba y
  #     pasó a participar, aplicaba una evaluación sobre algo que le da 404.
  def visible?
    return true if manager?
    return false unless accept? && reaches_challenge?(desafio)

    record.idea.nil? || IdeaPolicy.new(membership, record.idea).show?
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

  # Una propuesta cuelga de UN objetivo —el desafío, el módulo o la idea—, así
  # que el desafío hay que buscarlo en el que tenga.
  def desafio = record.desafio
end
