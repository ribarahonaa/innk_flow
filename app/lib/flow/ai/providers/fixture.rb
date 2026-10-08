# frozen_string_literal: true

module Flow
  module AI
    module Providers
      # Proveedor determinista para la maqueta.
      #
      # Resuelve por hash del prompt a un archivo en spec/fixtures/ai/, con
      # fallback a `default.json` de cada purpose — así la maqueta NUNCA se
      # rompe por falta de un fixture puntual.
      #
      # No es un mock de test: corre en development y es lo que permite
      # demostrar los tres modos de IA sin credenciales ni red.
      class Fixture < Provider
        ROOT = Rails.root.join("spec/fixtures/ai")

        def complete(messages:, schema:, purpose:, temperature: 0.2)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          payload = load_fixture(messages: messages, purpose: purpose)
          elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

          if payload.nil?
            return Result.new(ok: false, data: nil, raw: nil, tokens_in: 0, tokens_out: 0,
                              model: model_name, latency_ms: elapsed,
                              error: "sin fixture para purpose=#{purpose}")
          end

          errors = Flow::AI::SchemaValidator.errors_for(payload, schema)
          if errors.any?
            return Result.new(ok: false, data: nil, raw: payload, tokens_in: 0, tokens_out: 0,
                              model: model_name, latency_ms: elapsed,
                              error: "la respuesta no valida contra el schema: #{errors.join('; ')}")
          end

          Result.new(ok: true, data: payload, raw: payload,
                     tokens_in: rough_tokens(messages), tokens_out: rough_tokens(payload),
                     model: model_name, latency_ms: elapsed, error: nil)
        end

        def embeddings? = true

        # Embedding determinista: no tiene semántica real, pero da similitudes
        # estables y reproducibles. Sirve para ejercitar el flujo de
        # duplicados; para que sea útil de verdad hace falta un proveedor real.
        #
        # Devuelve la MISMA dimensión que un proveedor de verdad: si no, no
        # entra en la columna y el camino que ejercita no es el que va a correr.
        def embed(texts:)
          Array(texts).map { |text| deterministic_vector(text) }
        end

        def embedding_model = model_name

        def transcription? = true

        # Transcripción determinista, sin red y sin credenciales.
        #
        # DOS hablantes a propósito: con uno solo el aviso de diarización
        # colapsada —«todas las utterances son del mismo hablante y hay dos o
        # más sentados»— dispararía en toda corrida del recorrido, y la guarda
        # que lo mide no podría distinguir «colapsó de verdad» de «así es el
        # fixture».
        #
        # No depende del audio: los bytes del micrófono falso cambian con la
        # duración de la grabación, y un fixture que variara con ellos dejaría
        # de ser reproducible.
        def transcribe(audio:, content_type:, language:)
          # Sin `duration` ni `request_id`: no hubo llamada que medir. El modelo
          # sí, porque identifica de dónde salió el texto, y es lo que deja a la
          # pantalla decir que una transcripción es canneada.
          Provider::Transcription.new(
            duration: nil, request_id: nil, model: model_name,
            utterances: [
              { "speaker" => 0, "start" => 0.0, "end" => 4.2,
                "transcript" => "Tenemos que bajar la merma de la bodega reusando las barricas.",
                "confidence" => 0.99, "speaker_confidence" => 0.91 },
              { "speaker" => 1, "start" => 5.1, "end" => 9.4,
                "transcript" => "No estoy de acuerdo: el problema real es la inducción de los operarios nuevos.",
                "confidence" => 0.97, "speaker_confidence" => 0.88 }
            ]
          )
        end

        private

        def model_name = "fixture-v1"

        # Un SHA256 da 32 bytes; hacen falta 1024 números, así que se encadenan
        # digests numerados en vez de repetir el mismo en círculo —que daría un
        # vector periódico y similitudes falsas entre textos distintos.
        def deterministic_vector(text)
          base = normalize(text)
          bytes = (0...(Flow::AI::EMBEDDING_DIMENSIONS / 32.0).ceil).flat_map do |i|
            Digest::SHA256.digest("#{i}:#{base}").bytes
          end

          bytes.first(Flow::AI::EMBEDDING_DIMENSIONS).map { |b| (b - 128) / 128.0 }
        end

        def load_fixture(messages:, purpose:)
          dir = ROOT.join(purpose.to_s)
          return nil unless dir.directory?

          exact = dir.join("#{digest_of(messages)}.json")
          file = exact.exist? ? exact : dir.join("default.json")
          return nil unless file.exist?

          JSON.parse(file.read)
        rescue JSON::ParserError => e
          Rails.logger.error("[Flow::AI::Providers::Fixture] fixture inválido #{file}: #{e.message}")
          nil
        end

        def digest_of(messages)
          Digest::SHA256.hexdigest(JSON.generate(messages))[0, 16]
        end

        def normalize(text) = text.to_s.downcase.strip.gsub(/\s+/, " ")

        def rough_tokens(payload) = (JSON.generate(payload).length / 4.0).ceil
      end
    end
  end
end
