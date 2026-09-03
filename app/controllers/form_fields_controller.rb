# frozen_string_literal: true

# El formulario de postulación de un desafío: qué se le pregunta a quien
# postula una idea.
#
# Vive acá y no dentro del builder porque definir las preguntas es una tarea en
# sí, y el panel lateral del builder no da para editarlas cómodo. El builder
# muestra el resumen y trae para acá.
class FormFieldsController < ApplicationController
  before_action :set_context

  def show
    authorize @step, :manage_form?
    @fields = @step.form_fields.ordered
    @locked = ideas_submitted?
    @pending_suggestions = AiSuggestion.pending_review.where(challenge_step_id: @step.id).recent

    # Las props de la isla se serializan acá, con el mismo criterio que el
    # builder: el server es dueño del payload inicial.
    @props = {
      fields: @fields.map { |field| serialize(field) },
      fieldTypes: FormField::TYPES.map { |t| { value: t, label: I18n.t("flow.field_types.#{t}") } },
      locked: @locked,
      urls: { save: api_v1_challenge_form_fields_path(@challenge),
              back: builder_challenge_path(@challenge) }
    }
  end

  # Siembra los tres campos básicos. Es un atajo, no un comportamiento
  # automático: antes se creaban solos al activar el módulo y nadie los veía
  # hasta que el desafío ya había arrancado.
  def seed_defaults
    authorize @step, :manage_form?

    unless FormField.seed_basics!(@step)
      return redirect_to challenge_form_path(@challenge), alert: "El formulario ya tiene campos."
    end

    redirect_to challenge_form_path(@challenge), notice: "Listo: tres campos para empezar."
  end

  private

  def set_context
    @challenge = policy_scope(Challenge).find_by!(slug: params[:challenge_id])
    @step = @challenge.pipeline.ideation_step
    raise ActiveRecord::RecordNotFound if @step.nil?
  end

  def ideas_submitted? = @challenge.ideas.submitted.exists?

  def serialize(field)
    { id: field.id, key: field.key, label: field.label, hint: field.hint,
      fieldType: field.field_type, required: field.required,
      isTitle: field.title?, options: field.options, answered: field.answered_count }
  end
end
