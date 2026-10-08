# frozen_string_literal: true

module Flow
  module AI
    # Interfaz del proveedor. Decisión abierta: cuál es el adapter real.
    #
    # La maqueta corre con Providers::Fixture — determinista, sin red, sin API
    # key. Todo lo que rodea al proveedor (auditoría, modos, revisión humana)
    # ya está construido, así que cambiar de adapter es una variable de
    # entorno, no un refactor.
    class Provider
      Result = Data.define(:ok, :data, :raw, :tokens_in, :tokens_out, :model, :latency_ms, :error) do
        def ok? = ok
      end

      # Devuelve datos ESTRUCTURADOS validados contra `schema` (JSON Schema).
      # El schema no es decoración: se valida en los dos caminos —fixture y
      # proveedor real— para que el adapter real no descubra drift en
      # producción.
      def complete(messages:, schema:, purpose:, temperature: 0.2)
        raise NotImplementedError
      end

      # ¿Este proveedor sabe hacer embeddings?
      #
      # No todos: Anthropic no expone el endpoint. Quien pregunta es la tarea
      # de duplicados, que compara por vectores cuando puede y le pregunta al
      # modelo cuando no. Sin este predicado la única forma de saberlo era
      # llamar a #embed y atajar la excepción.
      def embeddings? = false

      # Para detección de duplicados. Sin esto la similitud es una demo.
      def embed(texts:)
        raise NotImplementedError
      end

      # ¿Este proveedor sabe transcribir audio?
      #
      # Tercera capacidad y tercer predicado, por el mismo motivo que
      # `embeddings?`: ninguno de los proveedores tiene las tres. Anthropic no
      # expone ni embeddings ni transcripción; Deepgram sólo transcribe.
      def transcription? = false

      # Audio → utterances con hablante, MÁS la metadata de la llamada.
      #
      # Las dos cosas en un valor inmutable y no en dos llamadas, porque el
      # proveedor se MEMOIZA —una instancia por proceso— y Sidekiq corre con
      # cinco hilos: un accesor que se pregunta después de `transcribe` es
      # estado compartido, y dos grabaciones en vuelo se pisarían la metadata.
      # Mismo idioma que el `Result` de arriba.
      #
      # `utterances` es un arreglo de hashes con claves string: "speaker",
      # "start", "end", "transcript", "confidence", "speaker_confidence". NO es
      # la respuesta cruda del proveedor: normalizar es parte del adapter.
      # Medido, la respuesta completa de Deepgram son 0,80 MB por 20 minutos de
      # reunión y esta forma 0,040 MB, veinte veces menos, sin perder nada que
      # el dominio use.
      Transcription = Data.define(:utterances, :duration, :request_id, :model)

      def transcribe(audio:, content_type:, language:)
        raise NotImplementedError
      end

      def name = self.class.name.demodulize.underscore

      # Con qué modelo se calcularon los vectores. Se guarda junto al vector:
      # dos modelos distintos no producen vectores comparables, y sin el dato
      # no hay forma de saber cuáles hay que rehacer.
      def embedding_model = name
    end
  end
end
