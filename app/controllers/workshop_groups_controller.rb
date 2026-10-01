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

    @workshop.workshop_groups.find_by!(id: params[:id]).destroy!
    redirect_to workshop_path(@workshop), notice: "Mesa eliminada."
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
