# frozen_string_literal: true

class IdeaPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope; end

  # Cualquiera de la empresa ve las ideas del desafío.
  def show? = reaches_challenge?(record&.challenge)

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
    return false unless record.author_id == membership.user_id

    record.draft? || evolution_open?
  end

  def submit? = update?

  # Sumar o sacar a alguien sigue la misma ventana que editar el contenido: en
  # borrador, o con una ronda de evolución abierta. Un colaborador no es
  # decorativo — hay criterios que cuentan personas —, así que agregarlo con la
  # evaluación en curso movería el puntaje después del hecho.
  def manage_contributors? = update?
  def destroy? = manager? || (record.author_id == membership.user_id && record.draft?)

  private

  # ¿El desafío está en una ronda de evolución ahora mismo?
  def evolution_open?
    step = record.challenge.pipeline.active_step
    step.present? && step.evolution?
  end
end
