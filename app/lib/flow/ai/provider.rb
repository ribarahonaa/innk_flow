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

      # ¿Este proveedor sabe hacer embeddings?
      #
      # No todos: Anthropic no expone el endpoint. Quien pregunta es la tarea
      # de duplicados, que compara por vectores cuando puede y le pregunta al
      # modelo cuando no. Sin este predicado la única forma de saberlo era
      # llamar a #embed y atajar la excepción.
      def embeddings? = false

      # Para detección de duplicados. Sin esto la similitud es una demo.
      def embed(texts:)
        raise NotImplementedError
      end

      def name = self.class.name.demodulize.underscore

      # Con qué modelo se calcularon los vectores. Se guarda junto al vector:
      # dos modelos distintos no producen vectores comparables, y sin el dato
      # no hay forma de saber cuáles hay que rehacer.
      def embedding_model = name
    end
  end
end
