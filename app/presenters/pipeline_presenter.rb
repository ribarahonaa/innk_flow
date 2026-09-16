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
  # Tailwind escanea texto y un `badge-${color}` armado con interpolación no
  # existe para el escáner.
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
      validation: validation_json,
      permissions: {
        canEdit: policy.update_pipeline?,
        canReorder: pipeline.can_reorder?,
        canStart: policy.start?
      },
      urls: {
        pipeline: Rails.application.routes.url_helpers.api_v1_challenge_pipeline_path(challenge),
        show: Rails.application.routes.url_helpers.challenge_path(challenge)
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

  # Lo que el builder LEE del desafío, y nada más: el título de la página lo
  # pinta el HAML de alrededor, no la isla.
  def challenge_json
    {
      # El link «Configurar →» de cada tarjeta lo arma el cliente con esto:
      # la pantalla del módulo vive en `/challenges/:slug/steps/:id`.
      slug: challenge.slug,
      # El rótulo «(heredado)» de un módulo con `aiMode: nil`.
      aiDefaultMode: challenge.ai_default_mode,
      # Viaja de vuelta en el PUT: es el candado optimista del desafío.
      lockVersion: challenge.lock_version
    }
  end

  # Lo que la tarjeta del builder DIBUJA, y nada más.
  #
  # Sin `settings`, `sourceStepId` ni `criteriaSetId`: son de la pantalla del
  # módulo, y publicarlas acá es lo que permitía que guardar el flujo con props
  # viejas revirtiera la configuración. Sin el resumen de criterios ni el del
  # formulario tampoco: los dibujaba el panel que se borró con `step_config.vue`
  # —hoy viven en la pantalla del módulo, en HAML— y seguían costando una
  # consulta por módulo (`newer_version_for`, `form_fields.ordered`) en cada
  # render del builder para algo que ningún `.vue` leía.
  #
  # `createApp(component, props)` convierte en atributos del elemento raíz toda
  # prop no declarada, así que lo que sobra acá además se serializa al DOM.
  def step_json(step)
    {
      id: step.id,
      kind: step.kind,
      kindLabel: I18n.t("flow.kinds.#{step.kind}"),
      name: step.name,
      statusLabel: I18n.t("flow.statuses.#{step.status}"),
      statusClass: chip_de_estado(step.status),
      aiMode: step.ai_mode,
      # La UI muestra la restricción, no solo la rechaza: los módulos bajo la
      # línea de agua se dibujan sin handle de arrastre y en gris, y sin la ✕
      # de quitar.
      locked: step.touched?
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
