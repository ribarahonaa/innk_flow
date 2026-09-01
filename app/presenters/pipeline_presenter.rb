# frozen_string_literal: true

# Serializa el pipeline para la isla Vue.
#
# El server es dueño del payload inicial: la vista lo embebe en un
# data-attribute y el componente monta con props, sin un fetch al arrancar.
# Una vuelta de red menos, y la tenencia la garantiza el scope de acá — no una
# ruta JSON que alguien podría olvidar scopear.
class PipelinePresenter
  def initialize(challenge, membership: nil)
    @challenge = challenge
    @membership = membership
    @pipeline = challenge.pipeline
  end

  attr_reader :challenge, :pipeline, :membership

  def as_json(*)
    {
      challenge: challenge_json,
      steps: pipeline.steps.map { |step| step_json(step) },
      palette: palette,
      aiModes: ai_modes,
      criteriaSets: criteria_sets,
      settingsSchema: settings_schema,
      insertionFloor: pipeline.insertion_floor&.to_f,
      validation: validation_json,
      permissions: {
        canEdit: policy.update_pipeline?,
        canReorder: pipeline.can_reorder?,
        canStart: policy.start?
      },
      urls: {
        pipeline: Rails.application.routes.url_helpers.api_v1_challenge_pipeline_path(challenge),
        show: Rails.application.routes.url_helpers.challenge_path(challenge),
        start: Rails.application.routes.url_helpers.start_challenge_path(challenge),
        criteriaSets: Rails.application.routes.url_helpers.criteria_sets_path,
        newCriteriaSet: Rails.application.routes.url_helpers.new_criteria_set_path
      }
    }
  end

  private

  def policy = @policy ||= ChallengePolicy.new(membership, challenge)

  def challenge_json
    {
      id: challenge.id,
      name: challenge.name,
      brief: challenge.brief,
      status: challenge.status,
      statusLabel: I18n.t("flow.challenge_statuses.#{challenge.status}"),
      aiDefaultMode: challenge.ai_default_mode,
      lockVersion: challenge.lock_version,
      draft: challenge.draft?
    }
  end

  def step_json(step)
    {
      id: step.id,
      slug: step.slug,
      kind: step.kind,
      kindLabel: I18n.t("flow.kinds.#{step.kind}"),
      name: step.name,
      status: step.status,
      statusLabel: I18n.t("flow.statuses.#{step.status}"),
      position: step.position.to_f,
      aiMode: step.ai_mode,
      effectiveAiMode: step.effective_ai_mode,
      sourceStepId: step.source_step_id,
      criteriaSetId: step.criteria_set_id,
      criteriaSetName: step.criteria_set&.name,
      settings: step.settings,
      touched: step.touched?,
      # La UI muestra la restricción, no solo la rechaza: los módulos bajo la
      # línea de agua se dibujan sin handle de arrastre y en gris.
      locked: step.touched?,
      removable: pipeline.can_remove?(step)
    }
  end

  # `ideation` se deshabilita cuando el desafío ya tiene uno.
  def palette
    taken = pipeline.steps.map(&:kind)

    ChallengeStep::KINDS.map do |kind|
      singleton = ChallengeStep::SINGLETON_KINDS.include?(kind)
      {
        kind: kind,
        label: I18n.t("flow.kinds.#{kind}"),
        description: I18n.t("flow.kind_descriptions.#{kind}"),
        singleton: singleton,
        disabled: singleton && taken.include?(kind)
      }
    end
  end

  # El esquema de configuración de cada kind, con las opciones dinámicas ya
  # resueltas. El builder lo renderiza tal cual: no declara campos propios, así
  # que agregar una opción es tocar Flow::StepSettings y nada más.
  def settings_schema
    Flow::StepSettings::SCHEMA.transform_values do |groups|
      groups.transform_values do |fields|
        fields.map { |field| resolve_field(field) }
      end
    end
  end

  def resolve_field(field)
    resolved = field.deep_dup
    resolved[:options] = dynamic_options(field[:source]) if field[:source]
    resolved
  end

  # Las opciones que dependen del desafío. `previous_*` se filtran en el
  # cliente contra la posición del módulo elegido, porque el orden cambia
  # mientras se edita el flujo.
  def dynamic_options(source)
    case source.to_s
    when "criteria_sets"
      criteria_sets.map { |set| { value: set[:id], label: "#{set[:name]} — #{set[:criteriaCount]} criterios" } }
    when "previous_evaluations"
      pipeline.steps.select(&:evaluation?).map do |step|
        { value: step.id, label: step.name, position: step.position.to_f }
      end
    when "previous_steps"
      pipeline.steps.map { |step| { value: step.slug, label: step.name, position: step.position.to_f } }
    else
      []
    end
  end

  # Sets de la biblioteca de la empresa, para asignarlos a un módulo de
  # evaluación desde el builder. Sin esto, el aviso "no tiene criterios
  # asignados" no tiene dónde resolverse.
  def criteria_sets
    CriteriaSet.library.includes(:criteria).order(:name).map do |set|
      {
        id: set.id,
        name: set.name,
        status: set.status,
        criteriaCount: set.active_criteria.size,
        summary: set.active_criteria.map { |c| "#{c.name} #{(c.weight.to_f * 100).round}%" }.join(" · "),
        editUrl: Rails.application.routes.url_helpers.edit_criteria_set_path(set)
      }
    end
  end

  def ai_modes
    Challenge::AI_MODES.map do |mode|
      {
        value: mode,
        label: I18n.t("flow.ai_modes.#{mode}"),
        description: I18n.t("flow.ai_mode_descriptions.#{mode}")
      }
    end
  end

  def validation_json
    report = pipeline.validate
    { valid: report.valid?, errors: report.errors, warnings: report.warnings }
  end
end
