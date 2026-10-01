# frozen_string_literal: true

# La asistencia de una persona a su mesa.
#
# `attended` y NO `present`: en Rails una columna `present` genera `present?`,
# que choca con `Object#present?` de ActiveSupport —el choque no da error,
# devuelve otra cosa—.
#
# Default `true` es lo que evita un paso extra: el reparto automático sienta al
# pool completo y marcar ausentes es la excepción, no el trámite. Cuelga de la
# membresía de la mesa y no de un padrón aparte, para no crear la segunda fuente
# de «quién está en este taller» que `Flow::Workshops::Convoke` advierte.
class AddAttendedToWorkshopGroupMembers < ActiveRecord::Migration[7.1]
  def change
    add_column :workshop_group_members, :attended, :boolean, null: false, default: true
  end
end
