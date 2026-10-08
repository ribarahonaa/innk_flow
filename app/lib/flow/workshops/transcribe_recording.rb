# frozen_string_literal: true

module Flow
  module Workshops
    # Audio → utterances con hablante.
    #
    # Le pide la transcripción a `Flow::AI.speech_provider` y NO al de chat. Son
    # objetos distintos, y preguntarle al de chat es exactamente el error que
    # `DetectDuplicates` pagó con los embeddings: el proveedor específico
    # quedaba sin usarse nunca, con la credencial puesta y todo.
    class TranscribeRecording
      def self.call(recording) = new(recording).call

      def initialize(recording)
        @recording = recording
      end

      def call
        # Idempotencia con factura atrás: cada transcripción se COBRA por
        # minuto, a diferencia de un embedding que se recalcula gratis. El
        # reintento del job reintenta una llamada que falló; no re-transcribe
        # una que salió bien.
        return false if recording.status == "ready"

        unless recording.file.attached?
          fallar!("sin audio adjunto: la fila existe pero el blob no llegó")
          return false
        end

        recording.update!(status: "transcribing")
        transcribir!
        true
      rescue Flow::Errors::TranscriptionFailed => e
        # El estado se escribe ANTES de propagar: así la pantalla dice algo
        # aunque los tres reintentos del job se agoten.
        fallar!(e.message)
        raise
      end

      private

      attr_reader :recording

      def transcribir!
        proveedor = Flow::AI.speech_provider
        # `transcribe` devuelve un `Provider::Transcription` —utterances Y
        # metadata en el mismo valor inmutable— y no un arreglo más un
        # `last_metadata` que se pregunta después.
        #
        # El porqué es una carrera que el diseño anterior tenía: el proveedor se
        # memoiza (`Flow::AI.speech_provider` usa `||=`), así que UNA instancia
        # sirve al proceso entero, y Sidekiq corre con cinco hilos. Con dos
        # grabaciones en vuelo, el hilo A dejaba su metadata en el objeto, el B
        # la pisaba, y acá se escribía el `request_id` del B en la fila del A.
        # Auditoría cruzada, en el camino que la spec marca como riesgo —«dos
        # personas de la mesa grabando a la vez»— e invisible para todo spec.
        resultado = proveedor.transcribe(
          audio: recording.file.download,
          content_type: recording.file.content_type,
          language: idioma
        )

        # Una transcripción vacía NO es un fallo: silencio o ruido devuelve 200
        # con texto vacío. Queda `ready` con cero utterances y la pantalla lo
        # dice; marcarla `failed` sería mentir sobre una llamada que salió bien.
        recording.update!(
          status: "ready",
          utterances: resultado.utterances,
          error: nil,
          duration_seconds: resultado.duration,
          request_id: resultado.request_id,
          provider: proveedor.name,
          # El fixture no tiene de dónde sacar un modelo, así que cae al nombre
          # del proveedor. Deepgram sí lo trae, en `metadata.model_info`.
          model: resultado.model || proveedor.name
        )
      end

      # El idioma de la app. No sale del audio: Deepgram lo quiere declarado, y
      # `nova-3` con el idioma puesto acierta más que adivinando.
      #
      # OJO: todo lo que se midió de este proveedor se midió en INGLÉS, porque
      # `flite` —lo único que sintetiza voz en esta máquina— no habla otro
      # idioma. Que transcriba español con la misma calidad es una afirmación
      # del proveedor y no una medición. La Tarea 8 la mide.
      def idioma = I18n.locale.to_s.split("-").first

      def fallar!(mensaje)
        recording.update!(status: "failed", error: mensaje)
      end
    end
  end
end
