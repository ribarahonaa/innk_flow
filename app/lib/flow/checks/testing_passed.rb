# frozen_string_literal: true

module Flow
  module Checks
    # La idea pasó su prueba de factibilidad.
    #
    # Un check NO sabe en qué módulo lo están corriendo: sólo tiene su
    # `criterion` y la idea. Así que «el testeo» no puede ser «el de este
    # módulo»: es el vigente del módulo de testing MÁS RECIENTE que probó esta
    # idea. Mirando todos, un veredicto de una ronda vieja decidiría para
    # siempre. Es la misma lógica de `feedback_addressed`, con otra tabla.
    class TestingPassed < Base
      ACEPTA = {
        "solo_factible" => %w[factible],
        "factible_o_con_reservas" => %w[factible con_reservas]
      }.freeze

      def call(idea)
        test = vigente_de(idea)
        return sin_testeo if test.nil?

        return fail(detalle_de(test)) unless aceptados.include?(test.verdict)

        pass(detalle_de(test))
      end

      # Es el único check con params que no reflejaba su configuración: los
      # otros cuatro sí lo hacen (`field_present`, `contributors_count`,
      # `version_count`, `has_attachment`; `feedback_addressed` no tiene
      # params). Con `accepts: solo_factible` la tarjeta «Cómo se decide»
      # seguía diciendo «pasó su prueba de factibilidad» sobre un filtro que
      # además rechaza «con reservas», y con `sin_testeo: no_pasa` no decía
      # nada de que una idea sin testear queda afuera.
      def description
        base = aceptados == %w[factible] ? "pasó su prueba de factibilidad sin reservas" \
                                          : "pasó su prueba de factibilidad, con reservas o sin ellas"
        return base unless config["sin_testeo"].to_s == "no_pasa"

        "#{base}; sin testear, no pasa"
      end

      private

      # El vigente del módulo de testing con la posición más alta entre los que
      # probaron esta idea.
      def vigente_de(idea)
        StepTest.vigentes.where(idea_id: idea.id).includes(:challenge_step).to_a
                .max_by { |test| test.challenge_step.position.to_d }
      end

      def aceptados = ACEPTA.fetch(config["accepts"].to_s, ACEPTA.fetch("factible_o_con_reservas"))

      # El detalle se lee en la celda del filtro del ranking, así que dice cuál
      # de los tres veredictos fue y no sólo si pasó.
      #
      # El label de `con_reservas` ya dice «Factible con reservas»: sumarle el
      # conteo encima duplicaba la frase («Factible con reservas con 2
      # reservas»). Con reservas cargadas la base pasa a ser la de `factible`
      # a secas, y el conteo lo dice todo. Nada en el modelo impide que un
      # `no_factible` traiga reservas, así que esto tiene que servir para los
      # tres veredictos y no sólo para `con_reservas`.
      def detalle_de(test)
        reservas = Array(test.reservations).size
        return I18n.t("flow.verdicts.#{test.verdict}") if reservas.zero?

        clave = test.verdict == "con_reservas" ? "factible" : test.verdict
        "#{I18n.t("flow.verdicts.#{clave}")} con #{Flow::Texto.contar(reservas, 'reserva')}"
      end

      def sin_testeo
        config["sin_testeo"].to_s == "no_pasa" ? fail("sin testear") : pass("sin testear")
      end
    end
  end
end
