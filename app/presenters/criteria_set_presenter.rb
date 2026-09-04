# frozen_string_literal: true

# Serializa un set de criterios para la isla del editor.
#
# Mismo criterio que PipelinePresenter: el server es dueño del payload inicial
# y del esquema. El editor no sabe qué parámetros pide cada verificación — los
# recibe y los dibuja.
class CriteriaSetPresenter
  def initialize(set, membership: nil, back_url: nil)
    @set = set
    @membership = membership
    @back_url = back_url
  end

  attr_reader :set, :membership

  def as_json(*)
    Flow::CriterionSettings.as_json.merge(
      set: set_json,
      criteria: set.criteria.ordered.map { |criterion| criterion_json(criterion) },
      formFields: form_field_options,
      locked: locked?,
      lockedReason: locked_reason,
      versionsOnSave: versions_on_save?,
      validation: { errors: set.validation_errors, weightTotal: set.weight_total.to_f },
      urls: urls
    )
  end

  private

  def set_json
    { id: set.id, name: set.name, description: set.description,
      scope: set.scope, status: set.status, persisted: set.persisted?,
      version: set.version,
      # Cuántos módulos lo usan: es lo que decide si guardar versiona, y lo que
      # la pantalla tiene que avisar ANTES de que alguien apriete guardar.
      usedBy: set.persisted? ? set.challenge_steps.count : 0,
      library: set.library? }
  end

  def criterion_json(criterion)
    {
      id: criterion.id,
      key: criterion.key,
      name: criterion.name,
      description: criterion.description,
      # El peso se edita en porcentaje: "40" se lee, "0.4" no.
      weight: (criterion.weight.to_d * 100).round(2).to_f,
      source: criterion.source,
      scaleType: criterion.scale_type,
      sourceConfig: criterion.source_config.to_h,
      scaleConfig: criterion.scale_config.to_h,
      active: criterion.active,
      scored: criterion.persisted? ? criterion.assessment_scores.limit(1).exists? : false
    }
  end

  # Los campos del formulario que puede verificar un check. Un set de la
  # biblioteca no cuelga de ningún desafío, así que se ofrecen los de toda la
  # empresa: sin esto, `field_key` vuelve a ser texto libre adivinado.
  def form_field_options
    scope = if set.owner_step
              FormField.where(challenge_step_id: set.owner_step.challenge.pipeline.ideation_step&.id)
            else
              FormField.all
            end

    scope.order(:key).map { |f| [f.key, f.label] }
         .group_by(&:first)
         .map { |key, pairs| { value: key, label: "#{pairs.first.last} (#{key})" } }
  end

  # Un criterio con notas puestas no se puede reescribir: cambiaría el
  # significado de lo ya puntuado. El set congelado en un módulo activo es
  # otra copia, así que editar acá no reescribe el pasado — pero sí lo haría
  # sobre las notas de este mismo set.
  # Guardar un set de biblioteca en uso no lo pisa: crea la versión siguiente.
  # Por eso ahí no hay nada cerrado — lo que se edita es una copia nueva.
  def versions_on_save? = set.persisted? && set.library? && set.in_use?

  def locked? = !versions_on_save? && scored_criteria.any?

  def locked_reason
    return version_notice if versions_on_save?
    return nil unless locked?

    "Ya hay evaluaciones hechas con este set. Podés cambiar nombres y " \
      "descripciones, pero no los pesos, la escala ni qué verifica cada criterio."
  end

  # Lo que hay que decir ANTES de guardar: qué se crea y, sobre todo, que lo
  # editado no le llega solo a quien ya estaba usando la versión anterior.
  def version_notice
    usos = set.challenge_steps.count
    "Lo usan #{usos} #{'módulo'.pluralize(usos)}. Al guardar se crea la v#{set.version + 1}: " \
      "los que ya usaban la v#{set.version} siguen con esa, y hay que asignarles la nueva " \
      "desde su módulo si querés que cambien."
  end

  def scored_criteria
    @scored_criteria ||= AssessmentScore.where(criterion_id: set.criteria.map(&:id)).limit(1).to_a
  end

  def urls
    helpers = Rails.application.routes.url_helpers
    {
      save: set.persisted? ? helpers.api_v1_criteria_set_path(set) : helpers.api_v1_criteria_sets_path,
      edit: set.persisted? ? helpers.edit_criteria_set_path(set) : nil,
      index: @back_url || helpers.criteria_sets_path
    }
  end
end
