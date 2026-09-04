# frozen_string_literal: true

module Flow
  module Ideas
    # Calcula y guarda el vector de una versión.
    #
    # Se hace UNA vez por versión y nunca se recalcula: la versión es contenido
    # inmutable, así que su vector tampoco cambia. Por eso se guarda también
    # con qué modelo se calculó — vectores de modelos distintos no se comparan
    # entre sí, y sin el dato no habría forma de saber cuáles rehacer.
    class EmbedVersion
      def self.call(version) = new(version).call

      def initialize(version)
        @version = version
      end

      def call
        return false if @version.nil? || text.blank?

        provider = Flow::AI.embeddings_provider
        vector = provider.embed(texts: [text]).first
        return false if vector.blank?

        store!(vector, provider.embedding_model)
        true
      end

      private

      def text
        @text ||= [@version.title, @version.payload.values.join("\n")].compact_blank.join("\n")
      end

      # SQL directo: Rails no conoce el tipo `vector`, así que asignarlo como
      # atributo lo mandaría como texto y Postgres lo rechazaría. `update_all`
      # además no dispara callbacks, que es lo correcto — esto no es un cambio
      # de contenido, es un derivado.
      def store!(vector, model)
        literal = "[#{vector.map { |v| v.to_f.round(6) }.join(',')}]"

        IdeaVersion.where(id: @version.id).update_all(
          ["embedding = ?::vector, embedding_model = ?, embedded_at = ?", literal, model, Time.current]
        )
      end
    end
  end
end
