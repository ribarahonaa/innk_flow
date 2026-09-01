# frozen_string_literal: true

module Flow
  module AI
    module Providers
      # Siempre falla. Existe para ejercitar el camino de error: qué ve el
      # usuario cuando el proveedor no responde.
      class Null < Provider
        def complete(messages:, schema:, purpose:, temperature: 0.2)
          Result.new(ok: false, data: nil, raw: nil, tokens_in: 0, tokens_out: 0,
                     model: "null", latency_ms: 0, error: "proveedor de IA deshabilitado")
        end

        def embed(texts:) = Array(texts).map { [] }
      end
    end
  end
end
