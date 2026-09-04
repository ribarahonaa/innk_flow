# frozen_string_literal: true

require "net/http"

module Flow
  module AI
    module Providers
      # Embeddings de Voyage AI, el proveedor de embeddings que recomienda
      # Anthropic —que no tiene endpoint propio—.
      #
      # Solo hace embeddings: `complete` no existe acá. Es el proveedor de la
      # variable `FLOW_EMBEDDINGS_PROVIDER`, que va aparte de la de chat
      # justamente porque son dos capacidades distintas.
      class Voyage < Provider
        ENDPOINT = URI("https://api.voyageai.com/v1/embeddings")
        DEFAULT_MODEL = "voyage-3.5-lite"

        # La API acepta bastante más, pero un lote grande es un timeout grande
        # y un reintento caro. 128 entra cómodo en el límite de tokens.
        BATCH = 128
        TIMEOUT = 30

        def embeddings? = true

        def name = "voyage"

        # `presence` y no `ENV.fetch(..., DEFAULT)`: el compose declara la
        # variable como string VACÍO cuando no está en el .env, y fetch solo
        # usa el default si la clave está AUSENTE. Sin esto se le manda a la
        # API un modelo vacío.
        def model_name = ENV["FLOW_EMBEDDINGS_MODEL"].presence || DEFAULT_MODEL

        # Lo que se guarda al lado de cada vector tiene que identificar el
        # MODELO, no el proveedor: cambiar de voyage-3.5-lite a voyage-3.5
        # produce vectores incomparables y con «voyage» en los dos casos se
        # mezclarían sin que nadie se entere.
        def embedding_model = model_name

        # Un modelo de chat no tiene nada que hacer acá: si alguien apunta
        # FLOW_AI_PROVIDER a voyage, que se entere de una.
        def complete(messages:, schema:, purpose:, temperature: 0.2)
          raise Flow::Errors::ProviderUnsupported,
                "Voyage solo hace embeddings: no sirve como proveedor de chat."
        end

        def embed(texts:)
          entradas = Array(texts).map(&:to_s)
          return [] if entradas.empty?

          entradas.each_slice(BATCH).flat_map { |lote| request(lote) }
        end

        private

        def request(lote)
          respuesta = post(lote)
          datos = respuesta["data"]
          raise error_for(respuesta) if datos.nil?

          # La API no promete el orden: cada fila trae su índice y hay que
          # respetarlo, o los vectores terminan pegados a otro texto.
          datos.sort_by { |fila| fila["index"].to_i }.map { |fila| validar(fila["embedding"]) }
        end

        def post(lote)
          http = Net::HTTP.new(ENDPOINT.host, ENDPOINT.port)
          http.use_ssl = true
          http.open_timeout = TIMEOUT
          http.read_timeout = TIMEOUT

          pedido = Net::HTTP::Post.new(ENDPOINT)
          pedido["Authorization"] = "Bearer #{api_key}"
          pedido["Content-Type"] = "application/json"
          pedido.body = JSON.generate(
            input: lote, model: model_name, input_type: "document",
            output_dimension: Flow::AI::EMBEDDING_DIMENSIONS
          )

          respuesta = http.request(pedido)
          cuerpo = parse(respuesta.body)
          # El código HTTP viaja con el error: sin él, «Internal Server Error»
          # no distingue entre un modelo mal escrito (400), una credencial
          # inválida (401) y una caída del proveedor (5xx).
          cuerpo.is_a?(Hash) ? cuerpo.merge("__status" => respuesta.code) : { "__status" => respuesta.code, "detail" => cuerpo.to_s }
        rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError => e
          raise Flow::Errors::EmbeddingFailed, "Voyage no respondió: #{e.class} #{e.message}"
        end

        def api_key
          ENV["VOYAGE_API_KEY"].presence ||
            raise(Flow::Errors::EmbeddingFailed,
                  "Falta VOYAGE_API_KEY. Se saca gratis en voyageai.com y va en el .env.")
        end

        # Una dimensión distinta a la de la columna no se guarda: mejor
        # enterarse acá que con un error de Postgres a mitad de un backfill.
        def validar(vector)
          esperado = Flow::AI::EMBEDDING_DIMENSIONS
          return vector if vector.is_a?(Array) && vector.size == esperado

          raise Flow::Errors::EmbeddingFailed,
                "Voyage devolvió un vector de #{vector.try(:size).inspect} dimensiones y la " \
                "columna espera #{esperado}. Revisá FLOW_EMBEDDINGS_MODEL."
        end

        def parse(cuerpo)
          JSON.parse(cuerpo.to_s)
        rescue JSON::ParserError
          cuerpo.to_s.truncate(200)
        end

        def error_for(respuesta)
          detalle = respuesta["detail"] || respuesta.dig("error", "message") ||
                    respuesta.except("__status").to_s.truncate(200)

          Flow::Errors::EmbeddingFailed.new(
            "Voyage rechazó el pedido (HTTP #{respuesta['__status']}, modelo #{model_name}): #{detalle}"
          )
        end
      end
    end
  end
end
