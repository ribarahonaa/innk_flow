# frozen_string_literal: true

module Flow
  module Scales
    # Toda escala produce un `normalized_value` en [0,1].
    #
    # Esa normalización es lo que hace comparable una nota 1-10 con una letra
    # A-F y con una fórmula: el módulo de selección lee un número entre 0 y 1
    # sin saber ni preguntar de qué escala vino.
    class Base
      def self.for(criterion)
        const_get("Flow::Scales::#{criterion.scale_type.camelize}").new(criterion)
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
