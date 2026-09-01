# frozen_string_literal: true

module Flow
  # Punto único donde se resuelve el proveedor.
  #
  # `FLOW_AI_PROVIDER=fixture` (default) hace que la maqueta corra sin API key
  # ni red. Enchufar un proveedor real es agregar un adapter y cambiar la
  # variable — nada más del sistema cambia.
  module AI
    class << self
      def provider
        @provider ||= build_provider
      end

      def provider=(value)
        @provider = value
      end

      def reset_provider! = @provider = nil

      private

      def build_provider
        name = ENV.fetch("FLOW_AI_PROVIDER", "fixture")
        klass = "Flow::AI::Providers::#{name.camelize}".safe_constantize
        return klass.new if klass

        Rails.logger.warn("[Flow::AI] proveedor desconocido: #{name}. Usando Null.")
        Flow::AI::Providers::Null.new
      end
    end
  end
end
