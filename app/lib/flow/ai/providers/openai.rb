# frozen_string_literal: true

module Flow
  module AI
    module Providers
      # Embeddings de OpenAI.
      #
      # Solo embeddings: el chat de esta maqueta va por Anthropic, que no tiene
      # endpoint de vectores. Son dos capacidades y dos variables distintas.
      class Openai < HttpEmbeddings
        # `text-embedding-3-small` sale nativo en 1536 dimensiones, pero acepta
        # el parámetro `dimensions` para devolver menos. Se le piden 1024, que
        # es lo que declara la columna: por eso la elección de 1024 no ataba a
        # un solo proveedor.
        DEFAULT_MODEL = "text-embedding-3-small"

        def name = "openai"

        private

        def endpoint = URI("https://api.openai.com/v1/embeddings")

        def request_body(lote)
          { input: lote, model: model_name, dimensions: Flow::AI::EMBEDDING_DIMENSIONS }
        end

        def api_key
          ENV["OPENAI_API_KEY"].presence || missing_key("OPENAI_API_KEY", "platform.openai.com")
        end

        # Un 401 acá casi siempre es la key; un 429, crédito agotado. Los dos
        # se leen mal en el mensaje crudo de la API.
        def hint(codigo)
          case codigo
          when "401" then ". Revisá que OPENAI_API_KEY sea de la organización correcta."
          when "429" then ". Puede ser cuota o crédito agotado: se revisa en el panel de facturación."
          else ""
          end
        end
      end
    end
  end
end
