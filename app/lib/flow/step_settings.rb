# frozen_string_literal: true

module Flow
  # Qué se puede configurar en cada tipo de módulo.
  #
  # FUENTE ÚNICA. El builder no declara campos: los renderiza a partir de esto,
  # así que sumar una opción es agregar una línea acá y no tocar Vue. Antes el
  # panel exponía 4 opciones de las 13 que los handlers leían, y las cajas de
  # Evolución y Reportería no tenían nada que configurar.
  #
  # `essential` va a la vista; `advanced` detrás de un desplegable.
  #
  # Los campos con `column: true` no viven en `config` sino en una columna del
  # step (el set de criterios, el módulo del que toma el puntaje).
  module StepSettings
    SCHEMA = {
      "ideation" => {
        essential: [
          { key: "min_ideas", type: "number", default: 1, min: 1,
            label: "Ideas mínimas para poder avanzar",
            hint: "El módulo no se cierra con menos ideas postuladas." }
        ],
        advanced: [
          { key: "generated_ideas", type: "number", default: 5, min: 1, max: 20,
            label: "Cuántas ideas genera la IA",
            hint: "Solo aplica cuando el módulo está en IA automática." }
        ]
      },

      "evolution" => {
        essential: [
          { key: "require_response", type: "boolean", default: false,
            label: "Exigir que cada idea responda",
            hint: "Si está activo, el módulo no se cierra hasta que todas publiquen una versión nueva." }
        ],
        advanced: []
      },

      "evaluation" => {
        essential: [
          { key: "criteria_set_id", type: "select", column: true, source: "criteria_sets",
            label: "Set de criterios",
            blank: "Criterios por defecto (impacto, factibilidad, esfuerzo)",
            hint: "Con qué se puntúa cada idea." },
          { key: "min_assessments", type: "number", default: 1, min: 1,
            label: "Evaluaciones mínimas por idea",
            hint: "En IA automática, la IA hace las que falten para llegar a este número." }
        ],
        advanced: [
          { key: "evaluator_aggregation", type: "select", default: "mean",
            label: "Cómo se combinan las evaluaciones",
            options: [
              { value: "mean", label: "Promedio" },
              { value: "median", label: "Mediana" },
              { value: "trimmed_mean", label: "Promedio sin extremos" }
            ],
            hint: "«Sin extremos» descarta la nota más alta y la más baja: amortigua al que puntúa todo en 10." }
        ]
      },

      "selection" => {
        essential: [
          { key: "criteria_set_id", type: "select", column: true, source: "criteria_sets",
            label: "Filtros",
            blank: "Sin filtros",
            hint: "Condiciones que la idea tiene que cumplir para avanzar. Se aplican antes del corte." },
          { key: "source_step_id", type: "select", column: true, source: "previous_evaluations",
            label: "Puntaje que usa para ordenar",
            blank: "Automático (la evaluación previa más cercana)",
            hint: "De qué módulo de evaluación toma la nota." },
          { key: "cut.mode", type: "select", default: "manual",
            label: "Regla de corte",
            options: [
              { value: "manual", label: "Manual: el dueño decide" },
              { value: "top_n", label: "Top N ideas" },
              { value: "top_percent", label: "Top N %" },
              { value: "threshold", label: "Puntaje mínimo" }
            ] },
          { key: "cut.value", type: "number", default: 10, min: 1,
            label: "Valor del corte",
            depends_on: { key: "cut.mode", not: "manual" } }
        ],
        advanced: [
          { key: "score_source.combine", type: "select", default: "weighted_avg",
            label: "Si combina varias evaluaciones",
            options: [
              { value: "weighted_avg", label: "Promedio ponderado" },
              { value: "max", label: "La nota más alta" },
              { value: "min", label: "La nota más baja" },
              { value: "last", label: "La última evaluación" }
            ] },
          { key: "cut.tie_break", type: "select", default: "earliest_submission",
            label: "Desempate",
            options: [
              { value: "earliest_submission", label: "La postulada primero" },
              { value: "lowest_dispersion", label: "La de evaluaciones más parejas" }
            ] }
        ]
      },

      "reporting" => {
        essential: [
          { key: "mode", type: "select", default: "by_version",
            label: "Cómo trata las versiones",
            options: [
              { value: "by_version", label: "Por versión: cada puntaje dice qué versión se evaluó" },
              { value: "latest", label: "Versión vigente, marcando lo desactualizado" }
            ],
            hint: "Nunca se promedia entre versiones distintas sin decirlo." }
        ],
        advanced: [
          { key: "include_eliminated", type: "boolean", default: true,
            label: "Incluir las ideas que no avanzaron",
            hint: "El embudo siempre las cuenta; esto afecta al ranking y a la matriz." },
          { key: "step_slugs", type: "multi_select", source: "previous_steps",
            label: "Qué módulos abarca",
            hint: "Vacío = todos los anteriores a este." }
        ]
      }
    }.freeze

    class << self
      def for(kind) = SCHEMA.fetch(kind.to_s, { essential: [], advanced: [] })

      def fields(kind) = self.for(kind).values.flatten

      # Valores por defecto de un kind, para sembrar la config de un step nuevo.
      def defaults(kind)
        fields(kind).each_with_object({}) do |field, acc|
          next if field[:column] || !field.key?(:default)

          write(acc, field[:key], field[:default])
        end
      end

      # Lee una clave que puede ser anidada ("cut.mode").
      def read(config, key)
        key.to_s.split(".").reduce(config) do |node, segment|
          node.is_a?(Hash) ? node[segment] : nil
        end
      end

      def write(config, key, value)
        segments = key.to_s.split(".")
        last = segments.pop
        node = segments.reduce(config) { |acc, segment| acc[segment] ||= {} }
        node[last] = value
        config
      end
    end
  end
end
