# frozen_string_literal: true

module Flow
  module Checks
    # El campo del formulario tiene contenido, opcionalmente con un largo
    # mínimo. Sirve para exigir que una idea llegue completa a la evaluación.
    class FieldPresent < Base
      def call(idea)
        value = idea.payload[field_key].to_s.strip
        return fail("sin contenido") if value.blank?
        return fail("#{value.length} de #{min_length} caracteres") if min_length.positive? && value.length < min_length

        pass("#{value.length} caracteres")
      end

      def description
        return "«#{field_label}» está completo" if min_length.zero?

        "«#{field_label}» tiene al menos #{min_length} caracteres"
      end

      def config_errors
        return ["falta indicar qué campo se verifica"] if field_key.blank?

        []
      end

      private

      def field_key = config["field_key"].to_s
      def min_length = config["min_length"].to_i

      # El label del campo si el formulario todavía lo declara; si lo
      # eliminaron, la clave cruda es mejor que un texto vacío.
      def field_label
        step = criterion.criteria_set&.owner_step&.challenge&.pipeline&.ideation_step
        step&.form_fields&.detect { |f| f.key == field_key }&.label || field_key
      end
    end
  end
end
