# frozen_string_literal: true

module Flow
  # Punto único donde se resuelve el proveedor.
  #
  # `FLOW_AI_PROVIDER=fixture` (default) hace que la maqueta corra sin API key
  # ni red. Enchufar un proveedor real es agregar un adapter y cambiar la
  # variable — nada más del sistema cambia.
  module AI
    # La dimensión de los vectores. Está fijada en la columna
    # `idea_versions.embedding`, así que cambiarla es recrear la columna: todo
    # proveedor de embeddings tiene que devolver exactamente esto.
    EMBEDDING_DIMENSIONS = 1024

    class << self
      def provider
        @provider ||= build_provider
      end

      # Separado del de chat A PROPÓSITO: son dos capacidades distintas y el
      # proveedor de chat puede no tener la otra. Anthropic es exactamente ese
      # caso —no expone endpoint de embeddings— y con una sola variable no
      # había forma de tener chat real y vectores reales al mismo tiempo.
      def embeddings_provider
        @embeddings_provider ||= build_embeddings_provider
      end

      def embeddings_provider=(value)
        @embeddings_provider = value
      end

      def provider=(value)
        @provider = value
      end

      def reset_provider!
        @provider = nil
        @embeddings_provider = nil
      end

      private

      def build_provider
        resolve(ENV.fetch("FLOW_AI_PROVIDER", "fixture"))
      end

      # Si no se declara uno, se usa el de chat cuando sabe hacer embeddings.
      # Con Anthropic no sabe, así que cae en el fixture: vectores sin
      # semántica, pero el camino entero funciona sin credenciales.
      def build_embeddings_provider
        declarado = ENV["FLOW_EMBEDDINGS_PROVIDER"].presence
        return resolve(declarado) if declarado
        return provider if provider.embeddings?

        Flow::AI::Providers::Fixture.new
      end

      def resolve(name)
        klass = "Flow::AI::Providers::#{name.camelize}".safe_constantize
        return klass.new if klass

        Rails.logger.warn("[Flow::AI] proveedor desconocido: #{name}. Usando Null.")
        Flow::AI::Providers::Null.new
      end
    end
  end
end
