# frozen_string_literal: true

# Marcar presente o ausente a mano.
#
# Es el único escritor de presencia en un taller con la asistencia PRESUMIDA, y
# el que cubre a quien vino sin teléfono en uno con check-in por link.
class WorkshopAttendancesController < ApplicationController
  before_action :set_workshop

  def update
    authorize @workshop, :manage_groups?
    # Con el taller cerrado no se toca nada, igual que convocar y desconvocar:
    # cambiar la asistencia de una sesión que terminó no arregla nada.
    return reject_closed if @workshop.closed?

    # Sólo los dos valores que manda la pantalla: `cast` devuelve nil para un
    # vacío (500 contra la columna NOT NULL) y `true` para cualquier otra cosa.
    attended = { "true" => true, "false" => false }[params[:attended]]
    return reject_attended if attended.nil?

    # `UNIQUE (workshop_id, user_id)` en `workshop_group_members`: hay a lo sumo
    # un asiento por persona en el taller, y eso es lo que hace CORRECTO (no
    # sólo cómodo) buscar uno con `find_by!`.
    seat = WorkshopGroupMember.where(workshop_id: @workshop.id).find_by!(user_id: params[:user_id])
    seat.update!(attended: attended)

    redirect_to workshop_path(@workshop),
                notice: seat.attended? ? "Marcada presente." : "Marcada ausente."
  end

  private

  # `policy_scope(...).find_by!` y no `Workshop.find_by!`: así lo que no se ve
  # da 404 y no 403, que sería un oráculo de existencia.
  def set_workshop = @workshop = policy_scope(Workshop).find_by!(id: params[:id])

  def reject_attended
    redirect_to workshop_path(@workshop), alert: "La asistencia tiene que ser presente o ausente."
  end

  def reject_closed
    redirect_to workshop_path(@workshop), alert: "Este taller ya cerró: la asistencia queda como está."
  end
end
