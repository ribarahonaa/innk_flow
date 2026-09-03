# frozen_string_literal: true

class ChallengeStepPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope; end

  # Ver la pantalla de un módulo: cualquiera de la empresa.
  def show? = reaches_challenge?(record&.challenge)

  # Avanzar el flujo o saltear un módulo: solo quien lo administra.
  def advance? = manager?
  def skip? = manager?

  # Editar el formulario de postulación.
  def manage_form? = manager?
  def manage_criteria? = manager?

  # El reporte incluye el ranking con los puntajes de todas las ideas: es
  # justo lo que un participante no ve en pantalla.
  def report? = manager?
end
