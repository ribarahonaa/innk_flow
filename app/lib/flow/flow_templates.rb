# frozen_string_literal: true

module Flow
  # Puntos de partida para armar el flujo de un desafío.
  #
  # NO son moldes: lo que arman se edita entero después, como si lo hubiera
  # puesto una persona a mano. Existen porque "armalo como quieras" y "empezá
  # de un lienzo en blanco" no son lo mismo, y lo segundo no es simple.
  #
  # FUENTE ÚNICA, igual que Flow::StepSettings y Flow::CriterionSettings: la
  # pantalla de creación las lista desde acá.
  #
  # `form: :basics` siembra los tres campos básicos de postulación. Sin eso
  # cualquier plantilla aterriza directo en el error de «Idear» sin formulario,
  # que es lo contrario de un punto de partida. La plantilla en blanco no lo
  # hace: ahí el dueño ya dijo que arma todo él.
  module FlowTemplates
    TEMPLATES = [
      {
        key: "classic",
        name: "Concurso clásico",
        description: "Se postulan ideas, se evalúan con criterios, avanzan las mejores y se cierra con un reporte.",
        form: :basics,
        steps: [
          { kind: "ideation",   name: "Postulación de ideas", config: { "min_ideas" => 3 } },
          { kind: "evaluation", name: "Evaluación",           config: { "min_assessments" => 2 } },
          { kind: "selection",  name: "Corte",                config: { "cut" => { "mode" => "top_n", "value" => 5 } } },
          { kind: "reporting",  name: "Reporte de cierre",    config: { "mode" => "by_version" } }
        ]
      },
      {
        key: "with_feedback",
        name: "Convocatoria con feedback",
        description: "Igual que el concurso, pero antes de evaluar cada idea recibe comentarios y su autor la mejora.",
        form: :basics,
        steps: [
          { kind: "ideation",   name: "Postulación de ideas", config: { "min_ideas" => 3 } },
          { kind: "evolution",  name: "Ronda de feedback",    config: { "require_response" => false } },
          { kind: "evaluation", name: "Evaluación",           config: { "min_assessments" => 2 } },
          { kind: "selection",  name: "Corte",                config: { "cut" => { "mode" => "top_n", "value" => 5 } } },
          { kind: "reporting",  name: "Reporte de cierre",    config: { "mode" => "by_version" } }
        ]
      },
      {
        key: "two_rounds",
        name: "Dos rondas con comité",
        description: "Un primer filtro amplio y una segunda evaluación, más exigente, sobre las que quedaron.",
        form: :basics,
        steps: [
          { kind: "ideation",   name: "Postulación de ideas",   config: { "min_ideas" => 5 } },
          { kind: "evaluation", name: "Primera revisión",       config: { "min_assessments" => 1 } },
          { kind: "selection",  name: "Preselección",           config: { "cut" => { "mode" => "top_percent", "value" => 50 } } },
          { kind: "evaluation", name: "Evaluación de comité",   config: { "min_assessments" => 3 } },
          { kind: "selection",  name: "Finalistas",             config: { "cut" => { "mode" => "top_n", "value" => 3 } } },
          { kind: "reporting",  name: "Reporte de cierre",      config: { "mode" => "by_version" } }
        ]
      },
      {
        key: "collect",
        name: "Solo recolectar ideas",
        description: "Se juntan ideas y se reporta lo que llegó. Sin evaluación ni corte.",
        form: :basics,
        steps: [
          { kind: "ideation",  name: "Postulación de ideas", config: { "min_ideas" => 1 } },
          { kind: "reporting", name: "Resumen de lo recibido", config: { "mode" => "latest" } }
        ]
      }
    ].freeze

    class << self
      def find(key) = TEMPLATES.find { |t| t[:key] == key.to_s }

      def keys = TEMPLATES.map { |t| t[:key] }

      # Para la pantalla: el flujo resumido como lo va a ver quien elige.
      def outline(template)
        template[:steps].map { |step| I18n.t("flow.kinds.#{step[:kind]}") }
      end

      # Aplica la plantilla a un desafío EN BORRADOR y vacío. No es idempotente
      # a propósito: aplicar dos veces duplicaría el flujo, y por eso solo se
      # ofrece cuando no hay módulos.
      def apply!(challenge, key)
        template = find(key)
        return false if template.nil?
        return false unless challenge.draft? && challenge.steps.empty?

        pipeline = challenge.pipeline
        template[:steps].each do |step|
          pipeline.insert(kind: step[:kind], after: :end, name: step[:name], config: step[:config])
        end

        FormField.seed_basics!(pipeline.ideation_step) if template[:form] == :basics
        true
      end
    end
  end
end
