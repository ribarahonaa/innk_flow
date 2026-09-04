# frozen_string_literal: true

# Quién evalúa este módulo, y cuánto pesa su voto.
#
# `step_assignments` existía desde el principio con su columna `weight`, pero
# la única forma de crear filas era `assign_evaluators!` —todos los evaluadores
# y admins de la empresa, con peso nulo— y no había dónde tocar ninguna de las
# dos cosas.
class StepAssignmentsController < ApplicationController
  before_action :set_step

  def create
    authorize @step, :manage_assignments?
    return redirect_back_with(alert: cerrado) if cerrado

    assignment = @step.step_assignments.new(user_id: params[:user_id], role: "evaluator",
                                            weight: peso)

    if assignment.save
      recalcular!
      redirect_back_with(notice: "#{assignment.user.name} evalúa este módulo.")
    else
      redirect_back_with(alert: assignment.errors.full_messages.to_sentence)
    end
  end

  def update
    authorize @step, :manage_assignments?
    return redirect_back_with(alert: cerrado) if cerrado

    assignment = @step.step_assignments.find(params[:id])

    if assignment.update(weight: peso)
      # El peso cambia el puntaje agregado de TODAS las ideas del módulo: sin
      # esto la tabla seguiría mostrando el número calculado con el peso viejo.
      recalcular!
      redirect_back_with(notice: peso_dicho(assignment))
    else
      redirect_back_with(alert: assignment.errors.full_messages.to_sentence)
    end
  end

  def destroy
    authorize @step, :manage_assignments?
    return redirect_back_with(alert: cerrado) if cerrado

    assignment = @step.step_assignments.find(params[:id])

    # Quien ya evaluó no se desasigna: su nota está puesta y sigue contando.
    # Sacarlo de la lista dejaría una evaluación sin quién la respalde.
    if @step.assessments.current.where(evaluator_id: assignment.user_id).exists?
      return redirect_back_with(alert: "#{assignment.user.name} ya evaluó en este módulo: " \
                                       "su nota queda. Podés bajarle el peso a 0.1 si querés " \
                                       "que pese menos.")
    end

    assignment.destroy!
    recalcular!
    redirect_back_with(notice: "#{assignment.user.name} ya no evalúa este módulo.")
  end

  private

  def set_step
    @challenge = policy_scope(Challenge).find_by!(slug: params[:challenge_id])
    @step = @challenge.steps.find(params[:step_id])
    raise ActiveRecord::RecordNotFound unless @step.evaluation?
  end

  # Vacío significa "sin peso": todas las voces valen lo mismo. No es lo mismo
  # que un 1 puesto a mano, aunque la cuenta dé igual.
  def peso = params[:weight].presence&.to_d

  def cerrado
    return nil unless @step.completed? || @step.skipped?

    "Este módulo ya cerró: cambiar quién evalúa o cuánto pesa reescribiría un resultado."
  end

  # El agregado de cada idea depende de quién evalúa y con qué peso, así que
  # cualquier cambio acá lo invalida.
  def recalcular!
    handler = @step.reload.handler
    @step.step_entries.includes(:idea).each { |entry| handler.recompute_entry!(entry) }
  end

  def peso_dicho(assignment)
    return "#{assignment.user.name} vuelve a pesar como el resto." if assignment.weight.nil?

    "El voto de #{assignment.user.name} pesa #{assignment.weight.to_f.round(2)}."
  end

  def redirect_back_with(**flash)
    redirect_to challenge_step_path(@challenge, @step), **flash
  end
end
