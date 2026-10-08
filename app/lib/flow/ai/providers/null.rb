# frozen_string_literal: true

module Flow
  module AI
    module Providers
      # Siempre falla. Existe para ejercitar el camino de error: qué ve el
      # usuario cuando el proveedor no responde.
      class Null < Provider
        def complete(messages:, schema:, purpose:, temperature: 0.2)
          Result.new(ok: false, data: nil, raw: nil, tokens_in: 0, tokens_out: 0,
                     model: "null", latency_ms: 0, error: "proveedor de IA deshabilitado")
        end

        def embed(texts:) = Array(texts).map { [] }

        # Falla EXPLICADA y no `NotImplementedError`, que es lo que se hereda.
        #
        # Acá es donde cae un `FLOW_SPEECH_PROVIDER` mal escrito: `resolve`
        # loguea un warning y devuelve esto. Con el `NotImplementedError` de
        # `Provider`, el `rescue Flow::Errors::TranscriptionFailed` del servicio
        # no matcheaba, así que la fila NO se marcaba `failed` y `retry_on`
        # tampoco: la tarjeta se quedaba en «transcribiendo», sin texto de
        # error, para siempre. El camino de chat ya degrada con un `ok: false`;
        # éste tiene que hacer lo propio, y el mensaje nombra la causa probable
        # porque un nombre mal escrito no deja ninguna otra pista en la
        # pantalla.
        def transcribe(audio:, content_type:, language:)
          raise Flow::Errors::TranscriptionFailed,
                "proveedor de voz deshabilitado o desconocido: revisá FLOW_SPEECH_PROVIDER"
        end
      end
    end
  end
end
