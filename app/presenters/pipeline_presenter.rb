# frozen_string_literal: true

# Serializa el pipeline para la isla Vue.
#
# El server es dueño del payload inicial: la vista lo embebe en un
# data-attribute y el componente monta con props, sin un fetch al arrancar.
# Una vuelta de red menos, y la tenencia la garantiza el scope de acá — no una
# ruta JSON que alguien podría olvidar scopear.
class PipelinePresenter
  # La clase del chip de estado la resuelve el MISMO mapeo que usan las vistas
  # HAML. La isla la recibe hecha en vez de armarla con un template literal:
  # Tailwind escanea texto y un `status-chip--${step.status}` no existe para el
  # escáner —hoy es inocuo porque la clase está escrita a mano en la hoja, y
  # deja de serlo en cuanto el chip pase a `badge` de DaisyUI—.
  include EstilosHelper

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

  # El esquema de configuración de cada kind, con las opciones dinámicas ya
  # resueltas. El builder lo renderiza tal cual: no declara campos propios, así
  # que agregar una opción es tocar Flow::StepSettings y nada más.
  #
  # Público porque `StepSettingsPresenter` lo necesita para la isla de la
  # pantalla del módulo: duplicar el transform daría dos esquemas
  # desincronizándose.
  def settings_schema
    Flow::StepSettings::SCHEMA.transform_values do |groups|
      groups.transform_values do |fields|
        fields.map { |field| resolve_field(field) }
      end
    end
  end

  private

  def policy = @policy ||= ChallengePolicy.new(membership, challenge)

  def challenge_json
    {
      id: challenge.id,
      # El link «Configurar →» de cada tarjeta lo arma el cliente con esto:
      # la pantalla del módulo vive en `/challenges/:slug/steps/:id`.
      slug: challenge.slug,
      name: challenge.name,
      brief: challenge.brief,
      status: challenge.status,
      statusLabel: I18n.t("flow.challenge_statuses.#{challenge.status}"),
      aiDefaultMode: challenge.ai_default_mode,
      lockVersion: challenge.lock_version,
      draft: challenge.draft?
    }
  end

  # Sin `settings`, `sourceStepId` ni `criteriaSetId`: son de la pantalla del
  # módulo. Publicarlas acá es lo que permitía que guardar el flujo con props
  # viejas revirtiera la configuración.
  def step_json(step)
    json = {
      id: step.id,
      slug: step.slug,
      kind: step.kind,
      kindLabel: I18n.t("flow.kinds.#{step.kind}"),
      name: step.name,
      status: step.status,
      statusLabel: I18n.t("flow.statuses.#{step.status}"),
      statusClass: chip_de_estado(step.status),
      position: step.position.to_f,
      aiMode: step.ai_mode,
      effectiveAiMode: step.effective_ai_mode,
      criteriaSetName: step.criteria_set&.name,
      touched: step.touched?,
      # La UI muestra la restricción, no solo la rechaza: los módulos bajo la
      # línea de agua se dibujan sin handle de arrastre y en gris.
      locked: step.touched?,
      removable: pipeline.can_remove?(step)
    }
    # `form` solo existe en «Idear». Nada de `.compact` sobre el hash entero:
    # se llevaría puestas las claves que valen nil a propósito —`aiMode: nil`
    # es "heredá del desafío", y sin ella el select del panel queda en blanco.
    json[:form] = form_json(step) if step.ideation?
    json[:criteria] = criteria_json(step) if step.evaluation? || step.selection?
    json
  end

  # Igual que el formulario en «Idear»: el panel no edita los criterios —no
  # entran en una columna de 290px— pero sí tiene que decir con cuáles va a
  # correr el módulo y ofrecer la puerta.
  def criteria_json(step)
    set = step.criteria_set
    criteria = set ? set.active_criteria : []

    {
      setName: set&.name,
      own: set.present? && set.inline?,
      count: criteria.size,
      labels: criteria.first(4).map(&:name),
      more: [criteria.size - 4, 0].max,
      valid: set.nil? || set.validation_errors.empty?,
      # Quedó con una versión que ya fue reemplazada: no está roto —sigue
      # significando lo que significaba— pero su dueño tiene que enterarse de
      # que hay una más nueva y decidir.
      newerVersion: newer_version_for(set),
      editUrl: Rails.application.routes.url_helpers.challenge_step_criteria_path(challenge, step)
    }
  end

  # El builder no edita el formulario —definir las preguntas es una tarea en sí
  # y el panel lateral no da—, pero sí tiene que MOSTRAR que existe. Sin esto el
  # dueño no se entera de que le falta hasta que arranca el desafío.
  def form_json(step)
    fields = step.form_fields.ordered
    {
      count: fields.size,
      requiredCount: fields.count(&:required?),
      labels: fields.first(4).map(&:label),
      more: [fields.size - 4, 0].max,
      editUrl: Rails.application.routes.url_helpers.challenge_form_path(challenge)
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
  #
  # Se ofrece la versión vigente de cada familia, más —si algún módulo quedó en
  # una anterior— esa, para que el select no pierda lo que ya tiene puesto.
  def criteria_sets
    vigentes = CriteriaSet.library.current
    asignados = CriteriaSet.library.where(id: pipeline.steps.map(&:criteria_set_id).compact)

    vigentes.or(asignados).includes(:criteria).order(:name, :version).map do |set|
      {
        id: set.id,
        name: set.label,
        status: set.status,
        criteriaCount: set.active_criteria.size,
        summary: set.active_criteria.map { |c| "#{c.name} #{(c.weight.to_f * 100).round}%" }.join(" · "),
        editUrl: Rails.application.routes.url_helpers.edit_criteria_set_path(set)
      }
    end
  end

  # La vigente de la misma familia, si el set asignado ya no lo es.
  def newer_version_for(set)
    return nil if set.nil? || set.inline? || !set.superseded?

    vigente = CriteriaSet.library.current.find_by(family_id: set.family_id)
    return nil if vigente.nil?

    { id: vigente.id, label: vigente.label }
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
