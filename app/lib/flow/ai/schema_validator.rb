# frozen_string_literal: true

module Flow
  module AI
    # Valida la salida estructurada contra JSON Schema.
    #
    # Corre en LOS DOS caminos —fixture y proveedor real— a propósito: un
    # fixture que se desvía del contrato tiene que fallar acá y no cuando se
    # enchufe el proveedor de verdad.
    module SchemaValidator
      class << self
        def errors_for(payload, schema)
          return [] if schema.blank?

          schemer(schema).validate(payload.as_json).map { |error| describe(error) }
        rescue StandardError => e
          ["no se pudo validar el schema: #{e.message}"]
        end

        def valid?(payload, schema) = errors_for(payload, schema).empty?

        private

        def schemer(schema)
          @schemers ||= {}
          @schemers[schema.hash] ||= JSONSchemer.schema(schema.deep_stringify_keys)
        end

        def describe(error)
          pointer = error["data_pointer"].presence || "(raíz)"
          "#{pointer}: #{error['type']}"
        end
      end
    end
  end
end
