# frozen_string_literal: true

class IdeaPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope; end

  # Cualquiera de la empresa ve las ideas del desafío.
  def show? = membership.present?

  # Postular: cualquiera con membresía, mientras el módulo de ideación esté
  # abierto.
  def create? = membership.present?

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
  def destroy? = manager? || (record.author_id == membership.user_id && record.draft?)

  private

  # ¿El desafío está en una ronda de evolución ahora mismo?
  def evolution_open?
    step = record.challenge.pipeline.active_step
    step.present? && step.evolution?
  end
end
