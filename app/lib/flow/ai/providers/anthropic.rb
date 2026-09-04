# frozen_string_literal: true

module Flow
  module AI
    module Providers
      # Proveedor real: la API de Anthropic.
      #
      # Se activa con `FLOW_AI_PROVIDER=anthropic` y una `ANTHROPIC_API_KEY`.
      # NUNCA es el default: cada llamada cuesta plata, y la maqueta tiene que
      # poder correr sin red ni credenciales.
      #
      # OJO con la resolución de constantes: adentro de este módulo `Anthropic`
      # se resuelve a esta misma clase, así que la gema va siempre con `::`.
      class Anthropic < Provider
        DEFAULT_MODEL = "claude-opus-5"

        # Keywords de JSON Schema que la API rechaza con 400. El schema local
        # sigue teniéndolos: se sacan solo para el pedido, y la validación de
        # verdad la hace `SchemaValidator` sobre la respuesta — así el contrato
        # real no se afloja por una limitación del transporte.
        UNSUPPORTED_KEYWORDS = %w[
          minItems maxItems minimum maximum exclusiveMinimum exclusiveMaximum
          multipleOf minLength maxLength pattern format uniqueItems
        ].freeze

        def complete(messages:, schema:, purpose:, temperature: 0.2)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          system_text, turns = split_system(messages)

          response = client.messages.create(**request(system_text, turns, schema))
          elapsed = elapsed_ms(started)

          return refused(response, elapsed) if response.stop_reason == :refusal
          return truncated(response, elapsed) if response.stop_reason == :max_tokens

          parse(response, schema, elapsed)
        rescue JSON::ParserError => e
          failure("la respuesta no era JSON: #{e.message}", elapsed_ms(started))
        rescue ::Anthropic::Errors::Error => e
          failure(explain(e), elapsed_ms(started))
        end

        # Anthropic no expone un endpoint de embeddings. Devolver los del
        # fixture acá sería peor que fallar: la detección de duplicados diría
        # que compara significados cuando estaría comparando hashes.
        #
        # Que esto reviente ya no rompe ninguna pantalla: `embeddings?` es
        # false y la detección de duplicados le pregunta al modelo en vez de
        # pedir vectores. Sigue levantando —y no devolviendo vacío— para que
        # quien agregue un camino nuevo se entere acá y no en producción.
        def embeddings? = false

        def embed(texts:)
          raise Flow::Errors::ProviderUnsupported,
                "Anthropic no tiene endpoint de embeddings. Para comparar por vectores hace " \
                "falta un proveedor de embeddings aparte (y pgvector para buscarlos a escala)."
        end

        def name = "anthropic"

        private

        def client
          @client ||= ::Anthropic::Client.new(**client_options)
        end

        def client_options
          key = ENV["ANTHROPIC_API_KEY"].presence
          key ? { api_key: key } : {}
        end

        def model = ENV.fetch("FLOW_AI_MODEL", DEFAULT_MODEL)

        def request(system_text, turns, schema)
          params = {
            model: model,
            max_tokens: 16_000,
            thinking: { type: "adaptive" },
            messages: turns,
            output_config: { format: { type: "json_schema", schema: sanitize(schema) } }
          }
          params[:system_] = system_text if system_text.present?
          params
        end

        # Las tareas arman los mensajes con un turno `system` adelante, que en
        # esta API es un parámetro aparte y no un turno más.
        def split_system(messages)
          list = Array(messages).map { |m| m.to_h.symbolize_keys }
          system = list.select { |m| m[:role].to_s == "system" }.pluck(:content).join("\n\n")
          turns = list.reject { |m| m[:role].to_s == "system" }
                      .map { |m| { role: m[:role].to_s, content: m[:content].to_s } }

          [system, turns]
        end

        def sanitize(node)
          case node
          when Hash
            clean = node.except(*UNSUPPORTED_KEYWORDS).transform_values { |v| sanitize(v) }
            clean["additionalProperties"] = false if clean["type"] == "object" || clean.key?("properties")
            clean
          when Array
            node.map { |item| sanitize(item) }
          else
            node
          end
        end

        def parse(response, schema, elapsed)
          text = response.content.select { |block| block.type == :text }.map(&:text).join
          return failure("la respuesta vino vacía", elapsed) if text.blank?

          data = JSON.parse(text)
          errors = Flow::AI::SchemaValidator.errors_for(data, schema)
          return failure("la respuesta no valida contra el schema: #{errors.join('; ')}", elapsed, raw: data) if errors.any?

          Result.new(ok: true, data: data, raw: data,
                     tokens_in: response.usage&.input_tokens.to_i,
                     tokens_out: response.usage&.output_tokens.to_i,
                     model: response.model.to_s, latency_ms: elapsed, error: nil)
        end

        # Un rechazo por política llega con HTTP 200 y `stop_reason: refusal`,
        # no como excepción: sin mirarlo se leería `content` vacío y el error
        # diría "vino vacía", que manda a investigar el lugar equivocado.
        def refused(response, elapsed)
          detail = response.stop_details
          failure("el modelo declinó responder (#{detail&.category || 'sin categoría'})", elapsed)
        end

        def truncated(response, elapsed)
          failure("la respuesta se cortó por max_tokens: el JSON quedó incompleto", elapsed)
        end

        def failure(message, elapsed, raw: nil)
          Result.new(ok: false, data: nil, raw: raw, tokens_in: 0, tokens_out: 0,
                     model: model, latency_ms: elapsed, error: message)
        end

        # Un error de credenciales y uno de cuota no se resuelven igual, así
        # que no se leen igual. La cadena va de lo específico a lo general.
        def explain(error)
          case error
          when ::Anthropic::Errors::AuthenticationError
            "la API rechazó la credencial: revisá ANTHROPIC_API_KEY"
          when ::Anthropic::Errors::RateLimitError
            "se alcanzó el límite de la API: probá de nuevo en un rato"
          when ::Anthropic::Errors::BadRequestError
            "la API rechazó el pedido: #{error.message}"
          when ::Anthropic::Errors::APIConnectionError, ::Anthropic::Errors::APITimeoutError
            "no se pudo llegar a la API: #{error.message}"
          else
            "#{error.class.name.demodulize}: #{error.message}"
          end
        end

        def elapsed_ms(started)
          ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        end
      end
    end
  end
end
