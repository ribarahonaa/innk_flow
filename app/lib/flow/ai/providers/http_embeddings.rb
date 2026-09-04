# frozen_string_literal: true

require "net/http"

module Flow
  module AI
    module Providers
      # Lo común a todo proveedor de embeddings por HTTP.
      #
      # Voyage y OpenAI tienen la misma forma —POST con JSON, respuesta con
      # `data[].embedding` y su índice— y difieren en la URL, los nombres de
      # los parámetros y dónde ponen el mensaje de error. Lo que se repite es
      # justo lo que es fácil hacer mal: el orden, el tamaño del lote y la
      # dimensión.
      class HttpEmbeddings < Provider
        # La API acepta bastante más, pero un lote grande es un timeout grande
        # y un reintento caro.
        BATCH = 128
        TIMEOUT = 30

        def embeddings? = true

        # Un modelo de embeddings no sirve para conversar: si alguien apunta
        # FLOW_AI_PROVIDER acá, que se entere de una.
        def complete(messages:, schema:, purpose:, temperature: 0.2)
          raise Flow::Errors::ProviderUnsupported,
                "#{name} solo hace embeddings: no sirve como proveedor de chat."
        end

        def embed(texts:)
          entradas = Array(texts).map(&:to_s)
          return [] if entradas.empty?

          entradas.each_slice(BATCH).flat_map { |lote| request(lote) }
        end

        def embedding_model = model_name

        def model_name = ENV["FLOW_EMBEDDINGS_MODEL"].presence || self.class::DEFAULT_MODEL

        private

        # ── Lo que cada proveedor define ──────────────────────────────────
        def endpoint = raise NotImplementedError
        def request_body(lote) = raise NotImplementedError
        def api_key = raise NotImplementedError

        # Dónde pone el mensaje de error este proveedor.
        def error_detail(respuesta) = respuesta.dig("error", "message")

        # Qué agregar según el código HTTP, si este proveedor tiene una
        # confusión conocida.
        def hint(_codigo) = ""

        # ── Lo común ──────────────────────────────────────────────────────

        def request(lote)
          respuesta = post(lote)
          datos = respuesta["data"]
          raise error_for(respuesta) if datos.nil?

          # La API no promete el orden: cada fila trae su índice y hay que
          # respetarlo, o los vectores terminan pegados a otro texto.
          datos.sort_by { |fila| fila["index"].to_i }.map { |fila| validate(fila["embedding"]) }
        end

        def post(lote)
          uri = endpoint
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = TIMEOUT
          http.read_timeout = TIMEOUT

          pedido = Net::HTTP::Post.new(uri)
          pedido["Authorization"] = "Bearer #{api_key}"
          pedido["Content-Type"] = "application/json"
          pedido.body = JSON.generate(request_body(lote))

          respuesta = http.request(pedido)
          cuerpo = parse(respuesta.body)
          # El código HTTP viaja con el error: sin él, «Internal Server Error»
          # no distingue entre un modelo mal escrito, una credencial inválida
          # y una caída del proveedor.
          if cuerpo.is_a?(Hash)
            cuerpo.merge("__status" => respuesta.code)
          else
            { "__status" => respuesta.code, "detail" => cuerpo.to_s }
          end
        rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError => e
          raise Flow::Errors::EmbeddingFailed, "#{name} no respondió: #{e.class} #{e.message}"
        end

        def parse(cuerpo)
          JSON.parse(cuerpo.to_s)
        rescue JSON::ParserError
          cuerpo.to_s.truncate(200)
        end

        # Una dimensión distinta a la de la columna no se guarda: mejor
        # enterarse acá que con un error de Postgres a mitad de un backfill.
        def validate(vector)
          esperado = Flow::AI::EMBEDDING_DIMENSIONS
          return vector if vector.is_a?(Array) && vector.size == esperado

          raise Flow::Errors::EmbeddingFailed,
                "#{name} devolvió un vector de #{vector.try(:size).inspect} dimensiones y la " \
                "columna espera #{esperado}. Revisá FLOW_EMBEDDINGS_MODEL."
        end

        def error_for(respuesta)
          codigo = respuesta["__status"].to_s
          detalle = error_detail(respuesta) || respuesta.except("__status").to_s.truncate(200)

          Flow::Errors::EmbeddingFailed.new(
            "#{name} rechazó el pedido (HTTP #{codigo}, modelo #{model_name}): #{detalle}#{hint(codigo)}"
          )
        end

        def missing_key(variable, donde)
          raise Flow::Errors::EmbeddingFailed,
                "Falta #{variable}. Se saca en #{donde} y va en el .env."
        end
      end
    end
  end
end
