# frozen_string_literal: true

module Flow
  # Qué se puede configurar en un criterio, declarado una sola vez.
  #
  # FUENTE ÚNICA, igual que Flow::StepSettings. El editor no declara campos:
  # los renderiza desde acá. Antes pedía escribir el JSON a mano —
  # `{"check":"field_present","field_key":"costo","min_length":200}`— que es la
  # razón por la que nadie armó nunca un set de criterios.
  #
  # Tres ejes, porque la config vive en dos columnas distintas:
  #
  #   SOURCES  quién produce el valor   -> qué campos habilita
  #   CHECKS   qué verifica el sistema  -> escribe en `source_config`
  #   SCALES   qué forma tiene el valor -> escribe en `scale_config`
  #
  # `formula` es un origen pero su configuración vive en `scale_config`, porque
  # es la escala la que sabe calcular y normalizar. Se declara en SCALES bajo
  # la clave "formula" y el editor la muestra cuando el origen es fórmula.
  module CriterionSettings
    # Los orígenes que dejan elegir la forma del valor. Un criterio automático
    # siempre es sí/no y uno de fórmula siempre numérico: lo fuerza el modelo
    # en `align_scale_with_source`, así que el editor ni ofrece la opción.
    CHOOSES_SCALE = %w[manual ai].freeze

    # Verificaciones automáticas. `params` escribe en `source_config`, junto a
    # la clave `check` que elige cuál se usa.
    CHECKS = {
      "field_present" => {
        summary: "El campo del formulario está completo.",
        params: [
          { key: "field_key", type: "select", source: "form_fields", required: true,
            label: "Qué campo", blank: "Elegí un campo" },
          { key: "min_length", type: "number", default: 0, min: 0,
            label: "Largo mínimo", suffix: "caracteres",
            hint: "0 = alcanza con que no esté vacío." }
        ]
      },
      "contributors_count" => {
        summary: "Participa más de una persona, contando al autor.",
        params: [
          { key: "minimum", type: "number", default: 2, min: 1, label: "Personas mínimas" }
        ]
      },
      "version_count" => {
        summary: "La idea se actualizó: tiene más de una versión.",
        params: [
          { key: "minimum", type: "number", default: 2, min: 1, label: "Versiones mínimas" }
        ]
      },
      "feedback_addressed" => {
        summary: "No le quedan comentarios sin atender.",
        params: []
      },
      "has_attachment" => {
        summary: "Adjuntó un archivo.",
        params: [
          { key: "field_key", type: "select", source: "form_fields",
            label: "En qué campo", blank: "Cualquiera" }
        ]
      }
    }.freeze

    # Formas del valor. `params` escribe en `scale_config`.
    SCALES = {
      "numeric" => {
        summary: "Una nota dentro de un rango.",
        params: [
          { key: "min", type: "number", default: 1, label: "Desde" },
          { key: "max", type: "number", default: 10, label: "Hasta" },
          { key: "step", type: "number", default: 1, min: 1, label: "Saltos de" },
          { key: "direction", type: "select", default: "higher_better",
            label: "Qué es mejor",
            options: [
              { value: "higher_better", label: "Más alto es mejor" },
              { value: "lower_better", label: "Más bajo es mejor" }
            ] }
        ]
      },
      "letter" => {
        summary: "Niveles con nombre: A-F, Alto/Medio/Bajo.",
        params: [
          { key: "levels", type: "levels", label: "Niveles",
            columns: %w[key label value],
            default: [
              { "key" => "A", "label" => "A", "value" => 4 },
              { "key" => "B", "label" => "B", "value" => 3 },
              { "key" => "C", "label" => "C", "value" => 2 },
              { "key" => "D", "label" => "D", "value" => 1 },
              { "key" => "F", "label" => "F", "value" => 0 }
            ],
            hint: "El valor numérico es el que se normaliza. El más alto vale 100%." }
        ]
      },
      "rubric" => {
        summary: "Niveles con una descripción que guía a quien evalúa.",
        params: [
          { key: "levels", type: "levels", label: "Niveles",
            columns: %w[key label value descriptor],
            default: [
              { "key" => "1", "label" => "1", "value" => 1, "descriptor" => "Sin impacto medible" },
              { "key" => "3", "label" => "3", "value" => 3, "descriptor" => "Impacto en un área" },
              { "key" => "5", "label" => "5", "value" => 5, "descriptor" => "Impacto en toda la empresa" }
            ],
            hint: "El descriptor es lo que lee quien evalúa al elegir el nivel." }
        ]
      },
      "boolean" => {
        summary: "Sí o no.",
        params: [
          { key: "true_label", type: "text", default: "Sí", label: "Cómo se llama el sí" },
          { key: "false_label", type: "text", default: "No", label: "Cómo se llama el no" },
          { key: "direction", type: "select", default: "higher_better",
            label: "Qué es mejor",
            options: [
              { value: "higher_better", label: "El sí es lo bueno" },
              { value: "lower_better", label: "El no es lo bueno (riesgo legal, bloqueantes)" }
            ] }
        ]
      },
      # No es un scale_type elegible: es la config del origen `formula`, que
      # vive en scale_config porque la escala es la que calcula y normaliza.
      "formula" => {
        summary: "Se calcula a partir de los otros criterios del set.",
        params: [
          { key: "expression", type: "text", required: true, mono: true,
            label: "Fórmula", placeholder: "(impacto * confianza) / esfuerzo",
            hint: "Usá las claves de los otros criterios como variables." },
          { key: "output.min", type: "number", default: 0, label: "Resultado mínimo" },
          { key: "output.max", type: "number", default: 10, label: "Resultado máximo" }
        ]
      }
    }.freeze

    class << self
      def check_params(type) = CHECKS.dig(type.to_s, :params) || []

      # La escala efectiva de un origen: la fórmula tiene la suya, el resto usa
      # la que eligió. Es la misma regla que `align_scale_with_source`, de este
      # lado para que el editor muestre los campos correctos.
      def scale_key(source, scale_type)
        source.to_s == "formula" ? "formula" : scale_type.to_s
      end

      # Un criterio AUTOMÁTICO no configura su escala. Es sí/no por definición
      # y nadie lo elige en un formulario: pedirle "cómo se llama el sí" sería
      # configurar una etiqueta que no se muestra en ningún lado.
      def scale_params(source, scale_type)
        return [] if source.to_s == "automatic"

        SCALES.dig(scale_key(source, scale_type), :params) || []
      end

      def check_defaults(type) = defaults_for(check_params(type)).merge("check" => type.to_s)

      def scale_defaults(source, scale_type) = defaults_for(scale_params(source, scale_type))

      # Deja en el config solo lo que la combinación actual usa. Sin esto,
      # cambiar de verificación arrastra los parámetros de la anterior y el
      # JSON guardado dice cosas que ya no aplican.
      def prune_check(config, type)
        keep = check_params(type).map { |p| p[:key].to_s } + ["check"]
        config.to_h.slice(*keep).merge("check" => type.to_s)
      end

      def prune_scale(config, source, scale_type)
        keys = scale_params(source, scale_type).map { |p| p[:key].to_s }
        roots = keys.map { |k| k.split(".").first }.uniq
        config.to_h.slice(*roots)
      end

      def as_json
        {
          sources: Criterion::SOURCES.map do |source|
            { value: source, label: I18n.t("flow.criterion_sources.#{source}"),
              choosesScale: CHOOSES_SCALE.include?(source) }
          end,
          scaleTypes: Criterion::SCALE_TYPES.map do |type|
            { value: type, label: I18n.t("flow.scale_types.#{type}"),
              summary: SCALES.dig(type, :summary) }
          end,
          checks: CHECKS.map do |type, spec|
            { value: type, label: Flow::Checks::Base.label(type),
              summary: spec[:summary], params: spec[:params] }
          end,
          scales: SCALES.transform_values { |spec| spec[:params] }
        }
      end

      private

      def defaults_for(params)
        params.each_with_object({}) do |param, acc|
          next unless param.key?(:default)

          Flow::StepSettings.write(acc, param[:key], param[:default])
        end
      end
    end
  end
end
