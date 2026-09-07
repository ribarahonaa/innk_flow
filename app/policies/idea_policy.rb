# frozen_string_literal: true

class IdeaPolicy < ApplicationPolicy
  # Quien participa ve SOLO las ideas en las que participa —las que creó y
  # aquellas en las que colabora—. El resto del desafío no es asunto suyo:
  # compite por el mismo corte.
  #
  # Quien administra, acompaña o evalúa ve todas: las tres cosas se hacen sobre
  # el pool entero.
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if membership.nil?
      return scope.all unless membership.participant?

      # Las dos formas de participar, que son las mismas que mira
      # `Idea#participates?`: haberla creado, o colaborar en ella.
      colabora = IdeaContributor.where(user_id: membership.user_id).select(:idea_id)

      scope.where(author_id: membership.user_id).or(scope.where(id: colabora))
    end
  end

  def show?
    return false unless reaches_challenge?(record&.challenge)
    return true unless membership.participant?

    record.participates?(membership.user)
  end

  # Postular: cualquiera con membresía, mientras el módulo de ideación esté
  # abierto. El gestor no: acompaña la evolución de las ideas de otros, y
  # proponer las propias lo pondría a guiar su competencia.
  def create? = membership.present? && !membership.gestor?

  # Editar = publicar una versión nueva.
  #
  # El autor puede mientras la idea sigue en borrador, y también cuando hay un
  # módulo de EVOLUCIÓN abierto: responder al feedback actualizando la idea es
  # exactamente para lo que existe ese módulo. Fuera de esos dos momentos, una
  # idea postulada no se edita en caliente.
  def update?
    return false if record.nil?
    return true if manager?
    # Quien acompaña trabaja la idea MIENTRAS la ronda esté abierta: ayudar a
    # que evolucione es para lo que existe el rol, y responder el feedback
    # editando es la forma de hacerlo. Fuera de esa ventana no, y sobre un
    # borrador tampoco: una idea que su autor todavía no postuló no está en
    # ninguna ronda.
    return evolution_open? && !record.draft? if acompana?

    # Participar es haberla creado o colaborar en ella, y son las dos formas
    # de trabajarla: quien colabora la ve —esa es la regla de visibilidad— y
    # no poder tocarla la dejaba a medias.
    return false unless record.participates?(membership&.user)

    record.draft? || evolution_open?
  end

  # Postular la idea es del autor: quien acompaña la trabaja, no la presenta
  # por él.
  def submit? = update? && !acompana?

  # Sumar o sacar a alguien sigue la misma ventana que editar el contenido: en
  # borrador, o con una ronda de evolución abierta. Un colaborador no es
  # decorativo — hay criterios que cuentan personas —, así que agregarlo con la
  # evaluación en curso movería el puntaje después del hecho.
  def manage_contributors? = update?
  def destroy? = manager? || (record.author_id == membership.user_id && record.draft?)

  private

  def acompana?
    membership.present? && membership.gestor? && reaches_challenge?(record.challenge)
  end

  # ¿El desafío está en una ronda de evolución ahora mismo?
  def evolution_open?
    step = record.challenge.pipeline.active_step
    step.present? && step.evolution?
  end
end
