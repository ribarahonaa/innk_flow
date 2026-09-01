# frozen_string_literal: true

class IdeaPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope; end

  # Cualquiera de la empresa ve las ideas del desafío.
  def show? = membership.present?

  # Postular: cualquiera con membresía, mientras el módulo de ideación esté
  # abierto.
  def create? = membership.present?

  # Editar: el autor mientras la idea sigue en borrador, o un gestor.
  # Una idea ya postulada no se edita "en caliente": se le publica una versión
  # nueva desde un módulo de evolución.
  def update?
    return false if record.nil?
    return true if manager?

    record.author_id == membership.user_id && record.draft?
  end

  def submit? = update?
  def destroy? = manager? || (record.author_id == membership.user_id && record.draft?)
end
