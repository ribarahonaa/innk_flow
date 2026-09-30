# frozen_string_literal: true

module Flow
  module Checks
    # Un criterio AUTOMÁTICO: lo verifica el sistema sobre la idea, sin que
    # nadie lo puntúe.
    #
    # Devuelve verdadero o falso, que se normaliza a 1.0 / 0.0 — así un
    # criterio automático puede sumar puntaje en una evaluación con el mismo
    # peso que uno manual, y actuar como filtro en una selección.
    class Base
      TYPES = %w[field_present contributors_count version_count feedback_addressed
                 has_attachment testing_passed].freeze

      Result = Data.define(:passed, :detail) do
        def passed? = passed
      end

      def self.for(criterion)
        type = criterion.source_config.to_h["check"].to_s
        klass = "Flow::Checks::#{type.camelize}".safe_constantize
        raise Flow::Errors::UnknownCheck, "verificación desconocida: #{type.presence || '(vacía)'}" if klass.nil?

        klass.new(criterion)
      end

      def self.label(type) = I18n.t("flow.checks.#{type}.label", default: type.humanize)

      def initialize(criterion)
        @criterion = criterion
      end

      attr_reader :criterion

      def config = criterion.source_config.to_h

      # => Result
      def call(idea) = raise NotImplementedError

      # Texto legible de lo que verifica, para la UI.
      def description = raise NotImplementedError

      # Errores de configuración, para validar el criterio. NO se sobreescribe:
      # los propios de cada check van en `own_config_errors`.
      #
      # Es un hook y no un `super` por una razón concreta. La parte genérica —un
      # `select` sólo admite las opciones que el esquema declara— no es
      # prolijidad: un valor desconocido no explota, cae al default de quien lo
      # lea, y `TestingPassed` leía `accepts` con un `fetch` cuyo default es la
      # rama MÁS PERMISIVA. El filtro aceptaba «factible con reservas» donde
      # alguien había configurado «sólo factible», y la tarjeta «Cómo se decide»
      # lo anunciaba con el texto de la permisiva: mirando la pantalla no hay con
      # qué darse cuenta.
      #
      # Con `super` eso se pierde en silencio si alguien se lo olvida, y NINGÚN
      # test puede cazarlo: los tres checks que traen errores propios no tienen
      # ningún `select` con opciones declaradas, así que perder la parte genérica
      # no cambia nada observable en ellos. Un hook no se puede olvidar, que es
      # mejor que una guarda para el mismo modo de falla.
      def config_errors = opciones_fuera_del_esquema + own_config_errors

      # Los errores propios del check. Acá sí va lo de cada uno.
      def own_config_errors = []

      protected

      # Un hueco NO se valida: es el default del esquema, que es la regla de
      # `config` de todo el repo. Validarlo dejaría sin guardar cualquier
      # criterio que no escriba cada clave, empezando por los del seed.
      def opciones_fuera_del_esquema
        Flow::CriterionSettings.check_options(config["check"].to_s).filter_map do |key, valores|
          valor = config[key].to_s
          next if valor.blank? || valores.include?(valor)

          "«#{key}»: «#{valor}» no es una de las opciones (#{valores.join(', ')})"
        end
      end

      def pass(detail = nil) = Result.new(passed: true, detail: detail)
      def fail(detail = nil) = Result.new(passed: false, detail: detail)
    end
  end
end
