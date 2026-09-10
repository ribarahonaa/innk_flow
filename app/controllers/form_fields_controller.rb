# frozen_string_literal: true

# El formulario de postulación de un desafío: qué se le pregunta a quien
# postula una idea.
#
# Vive acá y no dentro del builder porque definir las preguntas es una tarea en
# sí, y el panel lateral del builder no da para editarlas cómodo. El builder
# muestra el resumen y trae para acá.
class FormFieldsController < ApplicationController
  before_action :set_context

  # El formulario se edita en la pantalla del módulo de idear. Redirige en vez
  # de dar 404 por el mismo motivo que los criterios: la URL vive en links y
  # en marcadores.
  #
  # `show?`, no `manage_form?`: el destino es la pantalla del módulo, que
  # cualquiera de la empresa puede ver. Pedir un permiso más estricto que el
  # del destino le daba 403 a un marcador viejo de alguien que sí puede ver
  # a dónde lo manda.
  def show
    authorize @step, :show?

    redirect_to challenge_step_path(@challenge, @step), status: :moved_permanently
  end

  # Siembra los tres campos básicos. Es un atajo, no un comportamiento
  # automático: antes se creaban solos al activar el módulo y nadie los veía
  # hasta que el desafío ya había arrancado.
  def seed_defaults
    authorize @step, :manage_form?

    unless FormField.seed_basics!(@step)
      return redirect_to challenge_step_path(@challenge, @step), alert: "El formulario ya tiene campos."
    end

    redirect_to challenge_step_path(@challenge, @step), notice: "Listo: tres campos para empezar."
  end

  private

  def set_context
    @challenge = policy_scope(Challenge).find_by!(slug: params[:challenge_id])
    @step = @challenge.pipeline.ideation_step
    raise ActiveRecord::RecordNotFound if @step.nil?
  end
end
