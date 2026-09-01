# frozen_string_literal: true

module Flow
  module Ideas
    # Diferencia entre dos versiones, calculada al vuelo.
    #
    # No se almacena: las versiones guardan snapshot completo, así que el diff
    # es una función pura de dos payloads. Guardarlo sería estado derivado que
    # puede desincronizarse.
    class Diff
      Change = Data.define(:key, :label, :from, :to, :kind)

      def initialize(from_version, to_version, fields: nil)
        @from = from_version
        @to = to_version
        @fields = fields
      end

      attr_reader :from, :to

      # Cambio por campo, en el orden del formulario.
      def changes
        @changes ||= ordered_keys.filter_map do |key|
          before = value_of(@from, key)
          after = value_of(@to, key)
          next if before == after

          Change.new(key: key, label: label_for(key), from: before, to: after, kind: kind_for(before, after))
        end
      end

      def any? = changes.any?

      def summary
        return "sin cambios" if changes.empty?

        counts = changes.group_by(&:kind).transform_values(&:size)
        parts = []
        parts << "#{counts[:added]} agregado#{'s' if counts[:added] > 1}" if counts[:added]
        parts << "#{counts[:changed]} modificado#{'s' if counts[:changed] > 1}" if counts[:changed]
        parts << "#{counts[:removed]} vaciado#{'s' if counts[:removed] > 1}" if counts[:removed]
        parts.join(", ")
      end

      private

      def payload_of(version) = (version&.payload || {})

      def value_of(version, key)
        raw = payload_of(version)[key]
        raw.is_a?(Array) ? raw.join(", ") : raw.presence
      end

      # Unión de claves: un campo agregado al formulario después no existe en
      # la versión vieja, y eso es un cambio legítimo de mostrar.
      def ordered_keys
        form_keys = Array(@fields).map(&:key)
        payload_keys = (payload_of(@from).keys | payload_of(@to).keys)
        (form_keys & payload_keys) + (payload_keys - form_keys)
      end

      def label_for(key)
        Array(@fields).detect { |f| f.key == key }&.label || key.humanize
      end

      def kind_for(before, after)
        return :added if before.blank?
        return :removed if after.blank?

        :changed
      end
    end
  end
end
