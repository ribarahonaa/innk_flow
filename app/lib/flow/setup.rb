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

    def steps
      @steps ||= [brief_step, flow_step, form_step, criteria_step, review_step, start_step]
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
       ["El formulario", "qué se le pregunta a quien postula"],
       ["Los criterios", "con qué se puntúa"], ["Revisar", "lo que van a ver las personas"],
       ["Arrancar", "abrir la postulación"]]
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
               hint: done ? "#{count} #{'módulo'.pluralize(count)}" : "sin módulos",
               path: routes.builder_challenge_path(challenge),
               status: done ? :done : :pending, blocking: true)
    end

    def form_step
      ideation = pipeline.ideation_step
      fields = ideation ? ideation.form_fields.size : 0

      Step.new(key: :form, label: "El formulario",
               hint: fields.positive? ? "#{fields} #{'campo'.pluralize(fields)}" : "nadie puede postular",
               path: ideation ? routes.challenge_form_path(challenge) : routes.builder_challenge_path(challenge),
               status: fields.positive? ? :done : :pending, blocking: ideation.present?)
    end

    # Los criterios NO bloquean: sin set propio se usan los genéricos, que es
    # una decisión válida. Pero el paso existe para que sea una decisión y no
    # un descubrimiento a mitad de la evaluación.
    def criteria_step
      scorers = pipeline.steps.select { |s| s.evaluation? || s.selection? }
      propios = scorers.count { |s| s.criteria_set.present? }

      Step.new(key: :criteria, label: "Los criterios",
               hint: criteria_hint(scorers, propios),
               path: criteria_path(scorers),
               status: scorers.empty? || propios == scorers.size ? :done : :pending,
               blocking: false)
    end

    def criteria_hint(scorers, propios)
      return "no hay módulos que puntúen" if scorers.empty?
      return "#{propios} de #{scorers.size} con criterios propios" if propios < scorers.size

      "#{scorers.size} #{'módulo'.pluralize(scorers.size)} con criterios"
    end

    def criteria_path(scorers)
      pendiente = scorers.find { |s| s.criteria_set.blank? } || scorers.first
      return routes.builder_challenge_path(challenge) if pendiente.nil?

      routes.challenge_step_criteria_path(challenge, pendiente)
    end

    def review_step
      Step.new(key: :review, label: "Revisar",
               hint: "lo que van a ver las personas",
               path: routes.challenge_preview_path(challenge),
               status: challenge.draft? ? :pending : :done, blocking: false)
    end

    def start_step
      Step.new(key: :start, label: "Arrancar",
               hint: challenge.draft? ? "cuando esté todo listo" : I18n.t("flow.challenge_statuses.#{challenge.status}"),
               path: routes.challenge_path(challenge),
               status: challenge.draft? ? :pending : :done, blocking: false)
    end
  end
end
