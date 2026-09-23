# frozen_string_literal: true

class ChallengePolicy < ApplicationPolicy
  # Explícita a propósito: Pundit resuelve `ChallengePolicy::Scope` con
  # const_get(..., false), que NO busca en la superclase. Heredar la policy no
  # alcanza para heredar el scope.
  # Un gestor ve SOLO los desafíos que le asignaron.
  #
  # Los controllers buscan el desafío por este scope, así que uno no asignado
  # no da 403 sino 404: un 403 diría «existe pero no es tuyo», que es
  # justamente el oráculo de existencia que el resto del sistema evita.
  class Scope < ApplicationPolicy::Scope
    # Sin membresía, nada: `gestor?` es falso para quien no tiene rol, y
    # `scope.all unless gestor?` le mostraba a quien acababa de perder el
    # acceso todos los desafíos de la empresa —a un gestor removido, más de
    # los que veía antes—.
    def resolve
      return scope.none if membership.nil?
      return scope.all unless gestor?

      scope.where(id: ChallengeGestor.for_user(membership.user).select(:challenge_id))
    end
  end

  def show? = reaches_challenge?(record)

  # Cualquiera de la empresa ve los desafíos; los arma quien los administra
  # —quien administra la empresa, y el gestor al que se lo asignaron—.
  def builder? = administra?(record)
  def start?   = administra?(record) && record.draft?
  def close?   = administra?(record) && record.running?

  # El pipeline solo se edita libremente en borrador; una vez arrancado, la
  # regla del insertion floor limita qué se puede tocar (Flow::Pipeline).
  def update_pipeline? = administra?(record) && !record.closed? && !record.archived?

  # Mirar el pool entero de ideas para decidir qué se fusiona o se descarta
  # —hoy, detectar duplicados—.
  #
  # Quien participa no: la comparación devuelve títulos y resúmenes de ideas
  # ajenas, y quien participa ve sólo las suyas. Quien evalúa tampoco: puntúa
  # lo que se le asigna, no decide qué se fusiona. Y no mira si hay una ronda
  # de evolución abierta, porque comparar no edita ninguna idea.
  def curate_pool? = administra?(record)

  # LEER el pool ajeno: hoy, el resumen narrativo de reportería, que nombra
  # ideas por título. Quien participa ve sólo las ideas en las que participa
  # (`IdeaPolicy::Scope`), así que un resumen que nombra las otras le muestra
  # justo lo que el resto de esa pantalla le filtra.
  #
  # No es `curate_pool?`, aunque las dos pregunten por el pool entero: curar es
  # mirarlo para DECIDIR qué se fusiona, y por eso deja afuera a quien evalúa a
  # propósito. Leer un resumen no decide nada, y quien evalúa ve el pool
  # completo igual que quien administra o acompaña.
  #
  # Vivía escrita en la vista (`!current_membership.participant?`), que es el
  # único lugar donde una regla de rol no se puede auditar.
  def read_pool? = reaches_challenge?(record) && !membership.participant?

  # Crear no puede preguntar por la asignación —el desafío todavía no existe—,
  # así que alcanza con ser gestor de la empresa. Lo que lo acota es que
  # `ChallengesController#create` lo asigna al desafío que acaba de crear: sin
  # eso lo crearía y desaparecería de su lista en el mismo movimiento.
  def create? = manager? || (membership.present? && membership.gestor?)
end
