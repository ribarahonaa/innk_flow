# frozen_string_literal: true

module Flow
  # Namespace de errores del motor. Es `Flow::Errors::X` y no `Flow::X`
  # porque Zeitwerk exige que app/lib/flow/errors.rb defina Flow::Errors.
  module Errors
    class Error < StandardError; end

    # Se intentó activar un módulo sin sus precondiciones (p.ej. una selección
    # sin evaluación previa resoluble).
    class StepNotReady < Error; end

    # La expresión de un criterio fórmula no pasó Flow::Formula::Validator.
    class InvalidFormula < Error; end

    # Mutación de pipeline rechazada por la regla del insertion floor.
    class PipelineLocked < Error; end

    # Un criterio automático declara una verificación que no existe.
    class UnknownCheck < Error; end

    # El proveedor de IA configurado no soporta esa operación. No es un bug:
    # es una capacidad que ese proveedor no tiene.
    class ProviderUnsupported < Error; end
  end
end
