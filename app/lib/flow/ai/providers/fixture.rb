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
        def embed(texts:)
          Array(texts).map do |text|
            digest = Digest::SHA256.digest(normalize(text))
            Array.new(64) { |i| (digest.getbyte(i % digest.bytesize) - 128) / 128.0 }
          end
        end

        private

        def model_name = "fixture-v1"

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
