# frozen_string_literal: true

# Alta y baja de mesas. Poblarlas —convocar gente— es de
# `WorkshopConvocationsController`; acá sólo se arma y se borra la mesa.
class WorkshopGroupsController < ApplicationController
  before_action :set_workshop

  def create
    authorize @workshop, :manage_groups?
    return reject_closed if @workshop.closed?

    @workshop.workshop_groups.create!(name: params[:name].presence || next_name)
    redirect_to workshop_path(@workshop), notice: "Mesa creada."
  end

  def destroy
    authorize @workshop, :manage_groups?
    return reject_closed if @workshop.closed?

    group = @workshop.workshop_groups.find_by!(id: params[:id])

    # La llegada no es una mesa que se administre: es la sala de espera, y se
    # va sola cuando el reparto la vacía. Para «esta persona no está» el
    # control es «Marcar ausente», que conserva el asiento y deja registro.
    if group.arrival?
      return redirect_to workshop_path(@workshop),
                         alert: "La mesa de llegada no se elimina: se va sola cuando el reparto la vacía. " \
                                "Para quien no vino, usá «Marcar ausente»."
    end

    # `group.with_lock` (FOR UPDATE sobre la mesa) y la guarda va ADENTRO.
    # Crear una propuesta inserta una fila con FK a esta mesa, que
    # toma FOR KEY SHARE sobre ella: conflicta con nuestro lock, así que una
    # propuesta concurrente espera, y si llega después del borrado la FK la
    # frena. Sin esto, una propuesta creada entre el `exists?` y el `destroy!`
    # se iría por la cascada sin ruido —y las aceptadas son la procedencia de
    # versiones publicadas—. Va antes de pedir la llegada para no crear una
    # que después la guarda rechaza.
    had_draft = false
    refused = group.with_lock do
      # Misma regla que `AssignGroups` (no rearmar con propuestas), para que
      # borrar a mano y repartir no se contradigan.
      next :proposals if group.workshop_proposals.exists?

      # En modo individual `arrival_group!` es `nil` y la mesa se borra como
      # siempre: cada persona ES su mesa, no hay a dónde redistribuirla.
      #
      # Y sólo se pide la llegada si hay a quién mandar: borrar una mesa vacía
      # no tiene por qué crear una sala de espera que nadie va a usar.
      arrival = @workshop.arrival_group! if group.workshop_group_members.exists?
      # `update_all` y no destruir y recrear los asientos, por dos razones:
      # conserva `attended` tal cual está (presente sigue presente, ausente
      # sigue ausente: cambiar la configuración no reescribe la asistencia), y
      # no puede chocar con ningún índice, porque el UNIQUE
      # (workshop_id, user_id) garantiza un asiento por persona y mudarlo no
      # duplica nada.
      group.workshop_group_members.update_all(workshop_group_id: arrival.id) if arrival
      # Recargar: la asociación pudo cargarse antes de mudar los asientos, y
      # `destroy!` los borraría por `dependent: :destroy`.
      group.workshop_group_members.reset
      # A diferencia del reparto, acá el borrador SÍ se va con la mesa, y el
      # aviso lo dice. En `AssignGroups` la mesa queda vacía por un efecto del
      # reparto y nadie eligió perderla; acá alguien eligió ESTA mesa por su
      # nombre. Tampoco se niega como con las propuestas: ninguna pantalla borra
      # un borrador, así que una mesa con texto tecleado quedaría imposible de
      # borrar para siempre. Se lee antes del `destroy!`, que lo borra.
      had_draft = group.workshop_drafts.exists?
      group.destroy!
      nil
    end

    if refused == :proposals
      return redirect_to workshop_path(@workshop),
                         alert: "Esta mesa ya tiene propuestas: no se elimina. Las mesas con trabajo hecho se mueven a mano."
    end
    notice = had_draft ? "Mesa eliminada, con el borrador que tenía sin mandar." : "Mesa eliminada."
    redirect_to workshop_path(@workshop), notice: notice
  end

  def assign
    authorize @workshop, :manage_groups?
    result = Flow::Workshops::AssignGroups.new(@workshop, size: params[:size]).call

    if result.ok?
      redirect_to workshop_path(@workshop), notice: assigned_notice(result)
    else
      redirect_to workshop_path(@workshop), alert: result.errors.to_sentence
    end
  end

  private

  # Qué hizo, y qué partió. Los cortes se cuentan aparte de las mesas: son la
  # única parte del resultado que no respeta «no partir grupos», así que
  # esconderlos en el mismo número sería no decirlo.
  def assigned_notice(result)
    base = "#{Flow::Texto.contar(result.tables.size, 'mesa')} con " \
           "#{Flow::Texto.contar(result.tables.flatten.size, 'persona')}."
    return base if result.splits.empty?

    # El caso extremo tiene aviso propio: una idea más grande que la mesa se
    # parte POR DENTRO, y eso no es mover un grupo a otra mesa —es separar a
    # gente que trabaja en lo mismo—. Quien lee tiene que enterarse.
    if result.splits.any?(&:inside)
      return "#{base} El tamaño de mesa obligó a separar a personas de una misma idea."
    end

    n = result.splits.size
    "#{base} #{Flow::Texto.contar(n, 'grupo')} #{Flow::Texto.agree(n, 'quedó', 'quedaron')} " \
      "#{Flow::Texto.plural('partido', n)} por el tamaño de mesa."
  end

  # `policy_scope(...).find_by!` y no `Workshop.find_by!`: así lo que no se ve
  # da 404 y no 403, que sería un oráculo de existencia.
  def set_workshop = @workshop = policy_scope(Workshop).find_by!(id: params[:workshop_id])

  # Armar mesas y convocar quedan VIVOS con el taller ABIERTO, y es
  # DELIBERADO: llegó alguien tarde a la sesión y hay que moverlo de mesa, que
  # es el caso real de un taller. Lo que se cierra es el taller CERRADO:
  # borrar una mesa cascadea sus `workshop_proposals` —incluidas las
  # aceptadas, y con ellas la procedencia de versiones ya publicadas—, y sobre
  # un taller cerrado eso es puro daño.
  def reject_closed
    redirect_to workshop_path(@workshop), alert: "Este taller ya cerró: las mesas no se tocan."
  end

  def next_name = "Mesa #{@workshop.workshop_groups.count + 1}"
end
