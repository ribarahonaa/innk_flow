# frozen_string_literal: true

module Flow
  module AI
    # Interfaz del proveedor. Decisión abierta: cuál es el adapter real.
    #
    # La maqueta corre con Providers::Fixture — determinista, sin red, sin API
    # key. Todo lo que rodea al proveedor (auditoría, modos, revisión humana)
    # ya está construido, así que cambiar de adapter es una variable de
    # entorno, no un refactor.
    class Provider
      Result = Data.define(:ok, :data, :raw, :tokens_in, :tokens_out, :model, :latency_ms, :error) do
        def ok? = ok
      end

      # Devuelve datos ESTRUCTURADOS validados contra `schema` (JSON Schema).
      # El schema no es decoración: se valida en los dos caminos —fixture y
      # proveedor real— para que el adapter real no descubra drift en
      # producción.
      def complete(messages:, schema:, purpose:, temperature: 0.2)
        raise NotImplementedError
      end

      # Para detección de duplicados. Sin esto la similitud es una demo.
      def embed(texts:)
        raise NotImplementedError
      end

      def name = self.class.name.demodulize.underscore
    end
  end
end
