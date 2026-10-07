# frozen_string_literal: true

# El borrador de trabajo de una mesa: lo tecleado que todavía no se mandó.
#
# Es de la MESA y no de cada persona, que es lo que la pantalla ya promete («es
# de la mesa, no solo tuyo») y lo único que sobrevive al caso que esto existe
# para prevenir: al escribiente se le muere la máquina o se va, y el texto sigue
# ahí para el resto. El precio es última-escritura-gana, y la señal de colisión
# es `updated_by` en el sello.
class WorkshopDraft < ApplicationRecord
  include TenantScoped

  belongs_to :workshop_group
  belongs_to :workshop_challenge
  belongs_to :idea, optional: true
  belongs_to :based_on_version, class_name: "IdeaVersion", optional: true
  belongs_to :updated_by, class_name: "User"

  validate :group_and_room_share_workshop
  validate :idea_matches_room
  validate :version_belongs_to_idea

  # Mismo predicado que `Assessment#stale?` y `FeedbackItem#stale?`: la regla de
  # «se ancló a una versión y la idea avanzó» vive UNA vez, en `Idea`. En idear
  # no hay idea contra la cual estar viejo.
  def stale? = idea.present? && idea.stale_for?(based_on_version_id)

  private

  # La mesa y la sala tienen que ser del mismo taller. Hoy sólo el servidor
  # puede romperlo, y por eso mismo es lo que un copy-paste rompe sin que nada
  # se queje: las FK compuestas sólo atan a la misma EMPRESA.
  def group_and_room_share_workshop
    return if workshop_group.nil? || workshop_challenge.nil?
    return if workshop_group.workshop_id == workshop_challenge.workshop_id

    errors.add(:workshop_challenge_id, "la sala es de otro taller que la mesa")
  end

  # No puede ser un CHECK de Postgres: el `kind` está tres tablas más allá
  # (`workshop_challenges` → `challenge_steps` → `kind`).
  #
  # Con `kind` nil —el vínculo de un taller en borrador, que todavía no resolvió
  # su módulo— NO opina: no hay fase contra la que comparar, y rechazar ahí
  # inventaría una regla sobre un estado que no existe. Lo que cierra ese camino
  # es el guarda `workable?` del controller.
  def idea_matches_room
    kind = workshop_challenge&.kind
    return if kind.nil?

    if kind == "evolution" && idea_id.blank?
      errors.add(:idea_id, "una sala de evolución trabaja sobre una idea")
    elsif kind != "evolution" && idea_id.present?
      errors.add(:idea_id, "sólo una sala de evolución trabaja sobre una idea")
    end
  end

  # Un borrador que dice basarse en la versión de OTRA idea vuelve absurdo el
  # aviso de base vieja. Hoy sólo el servidor puede romperlo, y por eso mismo es
  # lo que un copy-paste rompe sin que nada se queje.
  def version_belongs_to_idea
    return if based_on_version.nil?
    return if based_on_version.idea_id == idea_id

    errors.add(:based_on_version_id, "esa versión es de otra idea")
  end
end
