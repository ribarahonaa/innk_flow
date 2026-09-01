# frozen_string_literal: true

module Flow
  module Scales
    # Toda escala produce un `normalized_value` en [0,1].
    #
    # Esa normalización es lo que hace comparable una nota 1-10 con una letra
    # A-F y con una fórmula: el módulo de selección lee un número entre 0 y 1
    # sin saber ni preguntar de qué escala vino.
    class Base
      # El ORIGEN manda sobre la forma cuando la determina:
      #
      #   formula   -> el valor es un número dentro de un rango de salida
      #   automatic -> el valor es el resultado de una verificación: sí o no
      #
      # Para los orígenes que sí dejan elegir forma (manual, ai), manda
      # scale_type. Sin esto, un criterio fórmula se normalizaría contra el
      # rango genérico 1..10 en vez de contra su propio `output`.
      def self.for(criterion)
        name = case criterion.source
               when "formula" then "Formula"
               when "automatic" then "Boolean"
               else criterion.scale_type.camelize
               end

        const_get("Flow::Scales::#{name}").new(criterion)
      end

      def initialize(criterion)
        @criterion = criterion
      end

      attr_reader :criterion

      def config = criterion.scale_config || {}

      # Lo que tipeó la persona -> número
      def numeric(raw) = raise NotImplementedError

      # Número -> [0,1]
      def normalize(value) = raise NotImplementedError

      # Opciones para el formulario del evaluador
      def options = []

      # Errores de configuración de la escala, para validar el criterio.
      def config_errors = []

      # Los criterios derivados (fórmula) no los completa el evaluador: se
      # calculan a partir de los demás.
      def derived? = false

      def call(raw)
        value = numeric(raw)
        return [nil, nil] if value.nil?

        [value, clamp(normalize(value))]
      end

      protected

      def clamp(value) = value.nil? ? nil : [[value.to_d, 0.to_d].max, 1.to_d].min
    end
  end
end
