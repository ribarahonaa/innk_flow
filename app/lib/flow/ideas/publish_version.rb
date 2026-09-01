# frozen_string_literal: true

module Flow
  module Ideas
    # ÚNICO escritor de versiones.
    #
    # `ideas.current_version_id` y `idea_versions.idea_id` forman un ciclo de
    # FK. Con un solo camino de escritura —crear la versión y mover el puntero
    # en la misma transacción— el ciclo nunca queda a medias, y `number` no
    # tiene carreras porque se calcula bajo el lock de la idea.
    class PublishVersion
      Result = Data.define(:ok, :version, :errors) do
        def ok? = ok
        def error_sentence = errors.join(". ")
      end

      def initialize(idea, payload:, author: nil, actor_type: "human", source_step: nil, change_note: nil, title: nil)
        @idea = idea
        @payload = payload || {}
        @author = author
        @actor_type = actor_type
        @source_step = source_step
        @change_note = change_note
        @title = title
      end

      def call
        version = nil

        @idea.with_lock do
          # Sin cambios reales no se crea una versión: el historial tiene que
          # significar algo, no llenarse de guardados idénticos.
          return skipped if unchanged?

          version = @idea.versions.create!(
            number: next_number,
            title: resolved_title,
            payload: normalized_payload,
            created_by: @author,
            actor_type: @actor_type,
            source_step: @source_step,
            change_note: @change_note
          )

          @idea.update!(current_version: version)
        end

        Result.new(ok: true, version: version, errors: [])
      rescue ActiveRecord::RecordInvalid => e
        Result.new(ok: false, version: nil, errors: e.record.errors.full_messages)
      end

      private

      def next_number = (@idea.versions.maximum(:number) || 0) + 1

      def normalized_payload
        @payload.to_h.transform_keys(&:to_s).reject { |_, v| v.nil? }
      end

      def unchanged?
        current = @idea.current_version
        return false if current.nil?

        current.payload == normalized_payload && current.title == resolved_title
      end

      def resolved_title
        return @title if @title.present?

        # El título sale del campo marcado `is_title`, o del primer campo de
        # texto del formulario. Es un derivado CACHEADO del payload, no una
        # fuente paralela: no hay doble origen como en innk_r5, donde
        # Idea#title lee del form y cae a la columna.
        step = @idea.challenge.pipeline.ideation_step
        field = step&.form_fields&.detect { |f| f.config["is_title"] } ||
                step&.form_fields&.detect { |f| %w[text textarea].include?(f.field_type) }

        from_field = field && normalized_payload[field.key]
        return truncate_title(from_field) if from_field.present?

        # Sin campo de título declarado, el primer valor con contenido es mejor
        # que dejar la idea sin nombre.
        fallback = normalized_payload.values.find { |v| v.is_a?(String) && v.present? }
        truncate_title(fallback) || @idea.current_version&.title
      end

      def truncate_title(value)
        value.presence&.to_s&.truncate(160)
      end

      def skipped = Result.new(ok: true, version: @idea.current_version, errors: [])
    end
  end
end
