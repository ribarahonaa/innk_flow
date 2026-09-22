# frozen_string_literal: true

# El testeo de factibilidad de UNA idea.
#
# Pantalla propia y no embebida en la del módulo: es trabajo por idea, como
# `assessments/new`, no configuración.
class StepTestsController < ApplicationController
  before_action :set_context

  def new
    authorize @step, :advance?
    @handler = @step.handler
    @vigente = @handler.vigente_para(@idea.id)
  end

  def create
    authorize @step, :advance?

    @step.handler.testear!(
      idea: @idea,
      verdict: params[:verdict],
      situations: situaciones,
      reservations: params[:reservations].to_s.split("\n").map(&:strip).compact_blank,
      summary: params[:summary].presence,
      tested_by: current_user
    )

    redirect_to challenge_step_path(@challenge, @step),
                notice: "Testeo guardado para «#{@idea.title.truncate(40)}»."
  end

  private

  # El desafío por `policy_scope` y la idea también: buscar con el scope de
  # tenencia y autorizar DESPUÉS devuelve 403 sobre algo que no se debería
  # ver, y esa diferencia con el 404 confirma que existe.
  def set_context
    @challenge = policy_scope(Challenge).find_by!(slug: params[:challenge_id])
    @step = @challenge.steps.find(params[:step_id])
    @idea = policy_scope(Idea).where(challenge_id: @challenge.id).find(params[:idea_id])
  end

  # `params[:situations]` llega distinto según quién lo mande: un arreglo de
  # hashes desde un spec o un JSON, un hash indexado (`situations[0][...]`,
  # `situations[1][...]`) desde el formulario real. `.values` sobre el hash
  # da las filas; sobre un arreglo, `Array()` ya las da — de ahí que se pida
  # `.values` solo cuando responde a eso.
  def situaciones
    filas = params[:situations]
    filas = filas.values if filas.respond_to?(:values)

    Array(filas).filter_map do |fila|
      fila = fila.respond_to?(:to_unsafe_h) ? fila.to_unsafe_h : fila
      next if fila["escenario"].blank?

      fila.slice("dimension", "escenario", "resultado", "detalle")
    end
  end
end
