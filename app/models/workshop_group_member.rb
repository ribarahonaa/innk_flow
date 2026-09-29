# frozen_string_literal: true

# Estar convocado ES estar en una mesa: no hay una lista aparte. Dos fuentes
# para «quién está en este taller» divergen, y la primera vez que difieran una
# de las dos estaría mintiendo.
class WorkshopGroupMember < ApplicationRecord
  include TenantScoped

  belongs_to :workshop_group
  belongs_to :workshop
  belongs_to :user

  # `workshop_id` está desnormalizado para poder escribir el UNIQUE
  # (workshop_id, user_id) que respalda «una persona, una mesa por taller»: la
  # columna no vive en esta tabla y en Postgres no hay otra forma de decirlo.
  # Se DERIVA siempre de la mesa y nunca de un parámetro — si alguien pudiera
  # mandarlo distinto, el índice dejaría de decir lo que dice.
  before_validation { self.workshop_id = workshop_group&.workshop_id }

  validates :user_id, uniqueness: { scope: :workshop_group_id }
  validate :one_group_per_workshop

  private

  # La mesa es la unidad de visibilidad. Alguien en dos mesas del mismo taller
  # la partiría en dos, y dejaría sin respuesta «¿de qué mesa es esta idea?».
  #
  # La validación se queda aunque el índice exista: da el mensaje en vez de un
  # `PG::UniqueViolation`. El índice es el que no se puede atravesar con dos
  # convocatorias concurrentes.
  def one_group_per_workshop
    return if workshop_group.nil? || user_id.blank?

    sibling_groups = WorkshopGroup.where(workshop_id: workshop_group.workshop_id).where.not(id: workshop_group_id)
    return unless WorkshopGroupMember.where(workshop_group_id: sibling_groups, user_id: user_id).exists?

    errors.add(:user_id, "ya está en otra mesa de este taller")
  end
end
