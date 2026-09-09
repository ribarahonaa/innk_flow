# frozen_string_literal: true

# Pantalla de un módulo. Despacha por `kind` a la vista que corresponde.
#
# Un controller y no cinco: el flujo (encontrar el step, autorizar, resolver
# el handler) es idéntico; lo único que cambia es qué se renderiza.
class StepsController < ApplicationController
  before_action :set_step

  def show
    authorize @step, :show?
    @handler = @step.handler
    @pending_suggestions = AiSuggestion.pending_review.where(challenge_step_id: @step.id).recent
    @assignable = @step.evaluation? ? assignable_users : []
    # Un gestor acompaña la evolución: se lo asigna donde eso pasa.
    @gestor_candidates = @step.evolution? ? gestor_candidates : []
    # Qué ideas puede ver esta persona en este módulo. La regla es una sola y
    # vive en `IdeaPolicy::Scope`: quien participa ve solo las suyas.
    @ideas_visibles = policy_scope(Idea).where(challenge_id: @challenge.id).pluck(:id).to_set
    render "steps/#{@step.kind}"
  end

  def advance
    authorize @step, :advance?
    result = @step.challenge.pipeline.advance!

    if result.ok?
      notice = result.step ? "Avanzaste a «#{result.step.name}»." : "El desafío terminó su flujo."
      redirect_to challenge_path(@step.challenge), notice: notice
    else
      redirect_to challenge_step_path(@step.challenge, @step), alert: result.error_sentence
    end
  end

  # El camino de escritura de la configuración de un módulo — salvo
  # `criteria_set_id`, que tiene un segundo camino legítimo:
  # `StepCriteriaController#create` también lo asigna, al crear el set PROPIO
  # del módulo desde su editor de criterios, otra pantalla.
  #
  # Autoriza según lo que llega, porque las dos cosas no piden lo mismo: el
  # selector de modo de IA de la cara de ejecución pide `advance?`, y
  # reescribir la configuración pide `configure?`.
  #
  # El congelamiento NO se revisa acá: lo impone `FROZEN_ATTRIBUTES` como
  # validación de modelo. Repetirlo en el controller sería una segunda copia
  # de la regla, que es exactamente como se desincronizan.
  def update
    authorize @step, estructural? ? :configure? : :advance?

    if @step.update(step_params)
      redirect_to challenge_step_path(@step.challenge, @step), notice: "Módulo actualizado."
    else
      redirect_to challenge_step_path(@step.challenge, @step),
                  alert: @step.errors.full_messages.to_sentence
    end
  end

  # Pedirle a la IA que evalúe de una todo lo que le falta al módulo, en vez
  # de idea por idea.
  #
  # Va por jobs y no síncrono como el botón de una sola: son N llamadas al
  # proveedor y el request no puede quedarse esperándolas. Es el mismo camino
  # que corre el módulo en automático al activarse.
  #
  # Quién puede pedirlo: quien evalúa en este módulo —por asignación o por
  # administrarlo—, que es más gente que `update_pipeline?`. Va sin idea: pedir
  # que la IA evalúe no es evaluar, así que la regla de «nadie puntúa una idea
  # de la que participa» no aplica acá (ver AiSuggestionPolicy#evaluacion).
  def evaluate_all
    authorize Assessment.new(challenge_step: @step), :create?
    handler = @step.handler
    pendientes = @step.step_entries.reject { |entry| handler.complete?(entry) }

    if pendientes.empty?
      return redirect_to challenge_step_path(@challenge, @step),
                         alert: "Todas las ideas ya tienen las evaluaciones que pide el módulo."
    end

    encoladas = handler.request_ai_assessments!
    redirect_to challenge_step_path(@challenge, @step),
                notice: "La IA está evaluando #{Flow::Texto.contar(encoladas, "idea")}. " \
                        "Los puntajes aparecen a medida que responde."
  end

  def skip
    authorize @step, :skip?
    @step.handler.skip!(reason: params[:reason])
    @step.challenge.pipeline.advance! if @step.challenge.pipeline.active_step.nil?
    redirect_to challenge_path(@step.challenge), notice: "Módulo salteado."
  end

  private

  # Gente con rol gestor en la empresa que todavía no acompaña este desafío.
  #
  # La membresía se busca explícita y no por `user.memberships`: esa asociación
  # puede venir cacheada de otro contexto de tenencia.
  def gestor_candidates
    ya_estan = @challenge.challenge_gestores.select(:user_id)

    User.joins(:memberships)
        .where(memberships: { company_id: Current.company.id, role: "gestor" })
        .where.not(id: ya_estan)
        .distinct.order(:name)
  end

  # Quién puede sumarse a evaluar este módulo.
  #
  # Evaluar depende de la ASIGNACIÓN y no del rol, así que la lista es amplia:
  # quien evalúa, quien administra, y los gestores asignados a este desafío —no
  # todos los de la empresa, porque un gestor solo alcanza lo que se le asignó.
  def assignable_users
    roles = Membership.where(role: %w[evaluator admin]).pluck(:user_id)
    gestores = ChallengeGestor.where(challenge_id: @step.challenge_id).pluck(:user_id)
    ya_estan = @step.step_assignments.pluck(:user_id)

    User.where(id: (roles + gestores).uniq - ya_estan).order(:name)
  end

  def set_step
    @challenge = policy_scope(Challenge).find_by!(slug: params[:challenge_id])
    @step = @challenge.steps.find(params[:id])
  end

  ESTRUCTURALES = %w[config source_step_id criteria_set_id].freeze

  def estructural? = crudos.keys.intersect?(ESTRUCTURALES)

  # Ojo con el default: `params.fetch(:challenge_step, {})` devuelve un Hash
  # pelado cuando la clave falta, y `to_unsafe_h` no existe ahí.
  def crudos
    @crudos ||= params.fetch(:challenge_step, ActionController::Parameters.new)
                      .to_unsafe_h.stringify_keys
  end

  # `config` no se permite con `permit(config: {})` —eso es un escritor de
  # jsonb arbitrario—: se filtra contra el esquema del kind, que además
  # castea al tipo declarado.
  def step_params
    permitidos = params.require(:challenge_step)
                       .permit(*ChallengeStep::ADJUSTABLE_ATTRIBUTES,
                               :source_step_id, :criteria_set_id)

    return permitidos unless crudos.key?("config")

    permitidos.merge(config: Flow::StepSettings.filtrar(@step.kind, crudos["config"]))
  end
end
