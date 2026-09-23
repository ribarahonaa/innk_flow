# frozen_string_literal: true

module Flow
  # El paso a paso de dejar un desafío listo para arrancar.
  #
  # Configurar estaba repartido en cinco pantallas que no se anunciaban entre
  # sí: armabas el flujo y no había nada que dijera «ahora falta el
  # formulario». Los avisos existían, pero eran una lista de reproches arriba
  # del builder, no un camino.
  #
  # Esto es la fuente única de ese camino: qué pasos hay, cuál está hecho, cuál
  # bloquea el arranque y a dónde lleva cada uno. Las pantallas lo dibujan; no
  # deciden nada.
  class Setup
    Step = Data.define(:key, :label, :hint, :path, :status, :blocking) do
      def done? = status == :done
      def blocked? = blocking && status != :done
    end

    def initialize(challenge)
      @challenge = challenge
      @pipeline = challenge.pipeline
    end

    attr_reader :challenge, :pipeline

    # Los pasos son los MÓDULOS del flujo, no una lista fija. Eran dos listas
    # distintas —la barra del flujo a la izquierda y los pasos de arriba— y
    # había que traducir de una a la otra. «El formulario» y «Los criterios»
    # eran además agregaciones de algo que se configura adentro de cada
    # módulo: dos módulos que puntúan compartían un casillero, así que al
    # configurar cualquiera de los dos se resaltaba el mismo.
    def steps
      @steps ||= [brief_step, flow_step, *module_steps, finish_step]
    end

    # El primero sin hacer: es donde continúa quien vuelve a la pantalla.
    def current = steps.find { |s| !s.done? } || steps.last

    def blockers = steps.select(&:blocked?)

    def ready? = blockers.empty?

    def done_count = steps.count(&:done?)

    def total = steps.size

    # El paso siguiente al que se está mirando, para el botón «Siguiente».
    def after(key)
      index = index_of(key)
      return nil if index.nil?

      steps[(index + 1)..].find { |s| !s.done? } || steps[index + 1]
    end

    def before(key)
      index = index_of(key)
      return nil if index.nil? || index.zero?

      steps[index - 1]
    end

    def number_of(key) = (index_of(key) || 0) + 1

    def find(key) = steps.find { |s| s.key.to_s == key.to_s }

    # El recorrido antes de que el desafío exista: la pantalla de creación es
    # el paso 1 y tiene que poder dibujar el camino igual.
    def self.outline
      [["El desafío", "nombre y brief"], ["El flujo", "qué módulos y en qué orden"],
       ["Cada módulo", "qué configura cada uno, uno por uno"],
       ["Revisar y arrancar", "lo que van a ver las personas, y abrir la postulación"]]
    end

    private

    def index_of(key) = steps.index { |s| s.key.to_s == key.to_s }

    def routes = Rails.application.routes.url_helpers

    def brief_step
      Step.new(key: :brief, label: "El desafío", hint: challenge.name,
               path: routes.challenge_path(challenge),
               status: challenge.brief.present? ? :done : :pending, blocking: false)
    end

    def flow_step
      count = pipeline.steps.size
      done = count.positive? && pipeline.steps.any?(&:ideation?)

      Step.new(key: :flow, label: "El flujo",
               hint: done ? "#{Flow::Texto.contar(count, "módulo")}" : "sin módulos",
               path: routes.builder_challenge_path(challenge),
               status: done ? :done : :pending, blocking: true)
    end

    # Un paso por módulo, en el orden del flujo.
    #
    # La clave es el ID y no el slug: el slug es legible pero podría chocar con
    # `brief`, `flow` o `finish` —los nombres los escribe una persona— y acá no
    # se persiste nada, así que no hace falta que sea estable entre renders.
    # Cada pantalla de configuración pasa el suyo como `current:`.
    def module_steps
      pipeline.steps.map { |modulo| module_step(modulo) }
    end

    def module_step(modulo)
      listo, pista = estado_de(modulo)

      Step.new(key: modulo.id, label: modulo.name, hint: pista,
               path: routes.challenge_step_path(challenge, modulo),
               status: listo ? :done : :pending,
               blocking: modulo.ideation?)
    end

    # Qué necesita cada tipo de módulo para contarse como configurado, y si su
    # ausencia traba el arranque. Es la misma regla que antes estaba repartida
    # entre `form_step` y `criteria_step`, ahora por módulo.
    #
    # Solo IDEAR traba: sin campos nadie puede postular. Los criterios de una
    # evaluación no traban —sin set propio se usan los genéricos, que es una
    # decisión válida— y la regla de corte de una selección tampoco.
    def estado_de(modulo)
      case modulo.kind
      when "ideation" then estado_de_ideacion(modulo)
      when "evaluation" then estado_de_evaluacion(modulo)
      when "selection" then estado_de_seleccion(modulo)
      when "testing" then [true, "#{Flow::Texto.contar(dimensiones_de(modulo).size, "dimensión")} a cubrir"]
      else [true, "nada obligatorio que configurar"]
      end
    end

    def estado_de_ideacion(modulo)
      campos = modulo.form_fields.size
      return [false, "nadie puede postular"] if campos.zero?

      [true, Flow::Texto.contar(campos, "campo")]
    end

    def estado_de_evaluacion(modulo)
      criterios = modulo.criteria_set&.active_criteria&.size.to_i
      return [false, "usa los criterios genéricos"] if criterios.zero?

      [true, criterios == 1 ? "1 criterio propio" : "#{criterios} criterios propios"]
    end

    # Los criterios de una selección son FILTROS y son opcionales; lo que hay
    # que decidir es la regla de corte. Se lee de `config` y no de `settings`
    # porque el hueco vale: una clave ausente no es «manual», es «nadie lo
    # decidió todavía» —y «manual: el dueño decide» sí es una decisión—.
    def estado_de_seleccion(modulo)
      modo = modulo.config.dig("cut", "mode").presence
      return [false, "sin regla de corte"] if modo.nil?

      [true, "corte: #{Flow::Handlers::Selection.cut_rule_label(modo, modulo.config.dig("cut", "value"))}"]
    end

    # Un testing nace configurado: las tres claves del esquema tienen default,
    # así que no hay nada obligatorio que decidir y no traba el arranque.
    def dimensiones_de(modulo)
      Array(Flow::StepSettings.efectivo("testing", modulo.settings)["dimensions"])
    end

    # Revisar y arrancar eran dos pasos que se completaban con el mismo hecho
    # —que el desafío deje de estar en borrador—, así que nunca se los veía en
    # estados distintos.
    def finish_step
      Step.new(key: :finish, label: "Revisar y arrancar",
               hint: challenge.draft? ? "lo que van a ver las personas" : I18n.t("flow.challenge_statuses.#{challenge.status}"),
               path: routes.challenge_preview_path(challenge),
               status: challenge.draft? ? :pending : :done, blocking: false)
    end
  end
end
