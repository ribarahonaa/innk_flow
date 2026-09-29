# frozen_string_literal: true

class StepAssignment < ApplicationRecord
  include TenantScoped

  ROLES = %w[evaluator jury].freeze

  # Los roles de la EMPRESA que pueden evaluar cualquier módulo. No es lo
  # mismo que `ROLES`, que es el papel dentro de este módulo.
  EVALUATING_ROLES = %w[evaluator admin].freeze

  # Sin peso asignado, todas las voces valen lo mismo. `nil` y 1 significan
  # exactamente eso; se guarda nil para no fingir una decisión que nadie tomó.
  DEFAULT_WEIGHT = 1
  MAX_WEIGHT = 10

  belongs_to :challenge_step
  belongs_to :user

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :challenge_step_id }
  validates :weight, numericality: { greater_than: 0, less_than_or_equal_to: MAX_WEIGHT },
                     allow_nil: true

  # Sólo al crear. Una asignación que YA existe y dejó de ser elegible es otra
  # cosa —a esa persona la dieron de baja o le cambiaron el rol— y se resuelve
  # en ese momento (`Flow::Assignments::Release`). Validarla también al
  # actualizar trabaría bajarle el peso a quien ya evaluó y no se puede
  # desasignar, que es justo la salida que ofrece el aviso de `destroy`.
  validate :user_can_evaluate, on: :create

  # A quién se le puede asignar este módulo.
  #
  # Evaluar depende de la ASIGNACIÓN y no del rol, así que la lista es amplia:
  # quien evalúa, quien administra la empresa, y los gestores que acompañan
  # ESE desafío —no todos los de la empresa, porque un gestor sólo alcanza lo
  # que se le asignó—. Pero no es cualquiera: a quien participa no.
  #
  # Vive acá y no en el controller porque la pantalla ya servía esta lista
  # (`StepsController#assignable_users`) sin que nadie la validara del lado del
  # servidor: un POST a mano asignaba a quien postula, y con eso podía puntuar
  # ideas ajenas —`AssessmentPolicy#create?` pregunta por la asignación, no por
  # el rol—.
  def self.eligible_user_ids(step)
    return [] if step.nil?

    por_rol = Membership.where(role: EVALUATING_ROLES).pluck(:user_id)
    # La membresía manda también para el gestor: la fila de
    # `challenge_gestores` sobrevive a la baja —lo dice `AssessmentPolicy`— así
    # que preguntarle sólo a ella dejaría elegible a quien ya no está.
    gestores = Membership.where(role: "gestor").pluck(:user_id) &
               ChallengeGestor.where(challenge_id: step.challenge_id).pluck(:user_id)

    (por_rol + gestores).uniq
  end

  def self.eligible?(step, user_id)
    user_id.present? && eligible_user_ids(step).include?(user_id)
  end

  def effective_weight = (weight || DEFAULT_WEIGHT).to_d

  # ¿Alguien le puso un peso distinto del de todos?
  def weighted? = weight.present? && weight.to_d != DEFAULT_WEIGHT

  private

  def user_can_evaluate
    return if user_id.blank? || challenge_step.nil?
    return if self.class.eligible?(challenge_step, user_id)

    errors.add(:user, "no evalúa en este desafío: se asigna a quien evalúa, " \
                      "a quien administra la empresa y a los gestores que lo acompañan")
  end
end
