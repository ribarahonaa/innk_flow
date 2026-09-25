# frozen_string_literal: true

class ChallengeStepPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope; end

  # Ver la pantalla de un módulo: cualquiera de la empresa.
  def show? = reaches_challenge?(record&.challenge)

  # Avanzar el flujo o saltear un módulo: quien administra ese desafío.
  #
  # `skip?` NO mira el estado del módulo, así que dice que sí también sobre uno
  # completado. Quien se niega ahí es `Handlers::Base#skip!`, que es donde vive
  # esa regla una sola vez. Si algún día se dibuja un control «Saltear» con
  # `policy(step).skip?`, va a aparecer sobre módulos cerrados y rebotar en ese
  # aviso —el control fantasma de siempre—: el botón tiene que preguntar además
  # por el estado, no duplicarse el predicado acá.
  def advance? = administers?(record&.challenge)
  def skip? = administers?(record&.challenge)

  # Reescribir la configuración de un módulo, que es más que ajustarlo en
  # curso: `update_pipeline?` suma `&& !closed? && !archived?`. Con el desafío
  # cerrado, cambiar el modo de IA sigue siendo legítimo —es política
  # operativa— y reescribir el corte no.
  def configure? = ChallengePolicy.new(membership, record&.challenge).update_pipeline?

  # Editar el formulario de postulación.
  def manage_form? = administers?(record&.challenge)
  def manage_criteria? = administers?(record&.challenge)

  # Quién evalúa y cuánto pesa su voto: es política del desafío, no del
  # módulo. Un evaluador no se asigna solo ni se sube el peso.
  def manage_assignments? = administers?(record&.challenge)

  # El reporte incluye el ranking con los puntajes de todas las ideas: es
  # justo lo que un participante no ve en pantalla.
  def report? = administers?(record&.challenge)
end
