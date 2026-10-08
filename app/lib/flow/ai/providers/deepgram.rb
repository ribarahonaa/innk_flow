# frozen_string_literal: true

module Flow
  module AI
    module Providers
      # Transcripción con hablantes. SÓLO transcribe: no hace chat ni
      # embeddings, igual que los adapters de embeddings sólo hacen `embed`.
      #
      # No hereda de `HttpEmbeddings` —esa clase base existe porque hay DOS
      # proveedores de vectores que comparten lo difícil (respetar el índice de
      # cada fila, partir en lotes, validar la dimensión)—. Acá hay uno solo; la
      # base se escribe cuando aparezca el segundo.
      #
      # El resumen NO lo hace este proveedor, aunque la competencia lo ofrezca:
      # sería una segunda llamada de IA sin rastro en `ai_runs`, sin schema
      # validado y sin modos. El resumen es un propósito de chat.
      class Deepgram < Provider
        ENDPOINT = "https://api.deepgram.com/v1/listen"
        DEFAULT_MODEL = "nova-3"
        TIMEOUT = 120

        def transcription? = true

        def complete(messages:, schema:, purpose:, temperature: 0.2)
          raise Flow::Errors::ProviderUnsupported,
                "deepgram transcribe audio; no hace chat. Usá FLOW_AI_PROVIDER para el chat."
        end

        def transcribe(audio:, content_type:, language:)
          body = post(audio, content_type, language)
          @last_metadata = metadata_from(body)
          normalize(body)
        end

        # Lo que la Tarea 5 escribe en las columnas de auditoría. Se llena en
        # `transcribe` y se lee después, en vez de devolver una tupla: el
        # contrato de la interfaz es «utterances», y meterle metadata obligaría
        # al fixture a inventar una.
        attr_reader :last_metadata

        # Pública para poder probarla sin red. Es donde están los errores.
        def normalize(body)
          utterances = body.dig("results", "utterances")
          return [] unless utterances.is_a?(Array)

          utterances.map do |u|
            {
              "speaker" => u["speaker"],
              "start" => u["start"],
              "end" => u["end"],
              "transcript" => u["transcript"],
              "confidence" => u["confidence"],
              # El MÍNIMO y no el de la primera palabra: es la señal de que el
              # diarizador dudó, y el mínimo es el lado conservador.
              "speaker_confidence" => min_speaker_confidence(u["words"])
            }
          end
        end

        def metadata_from(body)
          metadata = body["metadata"] || {}
          {
            "duration" => metadata["duration"],
            "request_id" => metadata["request_id"],
            # `model_info` viene con el UUID del modelo como clave, así que el
            # nombre está un nivel más abajo y no se puede pedir por clave fija.
            "model" => metadata.dig("model_info")&.values&.first&.dig("name")
          }
        end

        private

        def min_speaker_confidence(words)
          valores = Array(words).filter_map { |w| w["speaker_confidence"] }
          valores.min
        end

        def api_key
          ENV["DEEPGRAM_API_KEY"].presence ||
            raise(Flow::Errors::TranscriptionFailed, "falta DEEPGRAM_API_KEY")
        end

        def model_name = ENV["FLOW_SPEECH_MODEL"].presence || DEFAULT_MODEL

        def post(audio, content_type, language)
          uri = URI("#{ENDPOINT}?#{query(language)}")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = TIMEOUT
          http.read_timeout = TIMEOUT

          pedido = Net::HTTP::Post.new(uri)
          pedido["Authorization"] = "Token #{api_key}"
          pedido["Content-Type"] = content_type
          pedido.body = audio

          respuesta = http.request(pedido)
          parsed = parse(respuesta)
          return parsed if respuesta.is_a?(Net::HTTPSuccess)

          raise Flow::Errors::TranscriptionFailed,
                "deepgram respondió #{respuesta.code}: #{detail(parsed)}#{hint(respuesta.code)}"
        rescue Net::OpenTimeout, Net::ReadTimeout => e
          raise Flow::Errors::TranscriptionFailed, "deepgram no respondió en #{TIMEOUT}s (#{e.class})"
        end

        def query(language)
          URI.encode_www_form(
            model: model_name,
            # Sin esto no hay hablantes, y la diarización es el motivo por el
            # que se eligió este proveedor.
            diarize: true,
            # Sin esto no hay `results.utterances` y `normalize` devuelve vacío.
            utterances: true,
            punctuate: true,
            language: language
          )
        end

        def parse(respuesta)
          JSON.parse(respuesta.body.to_s)
        rescue JSON::ParserError
          {}
        end

        def detail(parsed) = parsed["err_msg"] || parsed["message"] || "sin detalle"

        # La pista de Voyage, por si pasa lo mismo: una cuenta que autentica
        # pero no tiene inferencia habilitada contesta 500 en TODO pedido.
        def hint(codigo)
          return "" unless codigo.to_s == "500"

          ". Un 500 en todo pedido suele ser una cuenta sin inferencia " \
            "habilitada, no un problema del audio: probá un clip de un segundo."
        end
      end
    end
  end
end
