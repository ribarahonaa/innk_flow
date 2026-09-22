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

      def description = "pasó su prueba de factibilidad"

      private

      # El vigente del módulo de testing con la posición más alta entre los que
      # probaron esta idea.
      def vigente_de(idea)
        StepTest.vigentes.where(idea_id: idea.id).includes(:challenge_step).to_a
                .max_by { |test| test.challenge_step.position.to_d }
      end

      def aceptados = ACEPTA.fetch(config["accepts"].to_s, ACEPTA.fetch("factible_o_con_reservas"))

      # El detalle se lee en la celda del filtro del ranking, así que dice cuál
      # de los dos casos fue y no sólo si pasó.
      def detalle_de(test)
        reservas = Array(test.reservations).size
        texto = I18n.t("flow.verdicts.#{test.verdict}")
        return texto if reservas.zero?

        "#{texto} con #{Flow::Texto.contar(reservas, 'reserva')}"
      end

      def sin_testeo
        config["sin_testeo"].to_s == "no_pasa" ? fail("sin testear") : pass("sin testear")
      end
    end
  end
end
