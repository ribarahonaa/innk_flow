# frozen_string_literal: true

module Flow
  module AI
    module Providers
      # Embeddings de Voyage AI, el proveedor que recomienda Anthropic —que no
      # tiene endpoint propio—.
      class Voyage < HttpEmbeddings
        DEFAULT_MODEL = "voyage-3.5-lite"

        def name = "voyage"

        private

        def endpoint = URI("https://api.voyageai.com/v1/embeddings")

        def request_body(lote)
          { input: lote, model: model_name, input_type: "document",
            output_dimension: Flow::AI::EMBEDDING_DIMENSIONS }
        end

        def api_key
          ENV["VOYAGE_API_KEY"].presence || missing_key("VOYAGE_API_KEY", "voyageai.com")
        end

        def error_detail(respuesta) = respuesta["detail"] || super

        # Un 500 en TODO pedido de inferencia, con la credencial autenticando
        # bien (sin ella da 401) y la validación funcionando (cuerpo vacío da
        # 400), no es un problema del pedido. Pasó de verdad y costó media hora
        # de sondeos: la cuenta autentica pero no tiene inferencia habilitada, y
        # Voyage contesta 500 en vez de un 402 que lo diga.
        def hint(codigo)
          return "" unless codigo.start_with?("5")

          ". Si falla TODO pedido —incluso con un modelo inexistente, que debería dar 400— " \
            "el problema no es este código: revisá que la cuenta de Voyage esté activada " \
            "(medio de pago) en su dashboard."
        end
      end
    end
  end
end
