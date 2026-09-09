# frozen_string_literal: true

class ChallengeStepPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope; end

  # Ver la pantalla de un módulo: cualquiera de la empresa.
  def show? = reaches_challenge?(record&.challenge)

  # Avanzar el flujo o saltear un módulo: solo quien lo administra.
  def advance? = manager?
  def skip? = manager?

  # Reescribir la configuración de un módulo, que es más que ajustarlo en
  # curso: `update_pipeline?` suma `&& !closed? && !archived?` sobre
  # `manager?`. Con el desafío cerrado, cambiar el modo de IA sigue siendo
  # legítimo —es política operativa— y reescribir el corte no.
  def configure? = ChallengePolicy.new(membership, record.challenge).update_pipeline?

  # Editar el formulario de postulación.
  def manage_form? = manager?
  def manage_criteria? = manager?

  # Quién evalúa y cuánto pesa su voto: es política del desafío, no del
  # módulo. Un evaluador no se asigna solo ni se sube el peso.
  def manage_assignments? = manager?

  # El reporte incluye el ranking con los puntajes de todas las ideas: es
  # justo lo que un participante no ve en pantalla.
  def report? = manager?
end
