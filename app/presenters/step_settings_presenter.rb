# frozen_string_literal: true

# Props de la isla `step-settings`: los ajustes de UN módulo.
#
# `steps` viaja porque `source_step_id` se filtra contra la posición: una
# selección sólo puede tomar puntaje de una evaluación ANTERIOR.
class StepSettingsPresenter
  def initialize(step)
    @step = step
  end

  attr_reader :step

  def as_json(*)
    {
      kind: step.kind,
      stepId: step.id,
      settings: step.config || {},
      sourceStepId: step.source_step_id,
      steps: step.challenge.steps.ordered.map do |s|
        { id: s.id, slug: s.slug, kind: s.kind, name: s.name, position: s.position.to_f }
      end,
      schema: esquema
    }
  end

  private

  # El mismo transform que ya hace PipelinePresenter#settings_schema: las
  # opciones que apuntan a otros módulos se resuelven contra este desafío.
  # `settings_schema` no consulta ninguna policy, así que no hace falta
  # `membership` para resolverlo.
  def esquema
    PipelinePresenter.new(step.challenge).settings_schema
  end
end
