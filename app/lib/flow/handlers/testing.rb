# frozen_string_literal: true

module Flow
  module Handlers
    # «Testing»: pone la idea a prueba contra situaciones concretas de
    # ejecución y deja un veredicto de factibilidad con su evidencia.
    #
    # NO elimina a nadie: `ideas.status` sigue teniendo un solo escritor, que
    # es `Selection#decide!`. Quien quiera que el testeo corte, pone una
    # selección después con un filtro `testing_passed`.
    class Testing < Base
      SEVERITIES = %w[exigente estandar].freeze
      DIMENSIONS = %w[tecnica operativa economica legal adopcion].freeze

      # Arranca sin precondiciones: no lee el resultado de ningún módulo
      # anterior, solo las ideas que le llegan.
      def can_activate? = [true, []]

      def dimensions = Array(settings.fetch("dimensions", DIMENSIONS)).presence || DIMENSIONS
      def min_situations = settings.fetch("min_situations", 3).to_i
      def severity = settings.fetch("severity", "exigente")

      def vigente_para(idea_id) = vigentes[idea_id]

      # Del más nuevo al más viejo, el vigente primero.
      def historial_de(idea_id)
        StepTest.where(challenge_step_id: step.id, idea_id: idea_id).recientes.to_a
      end

      def sin_testear
        step.step_entries.includes(:idea).reject { |entry| vigentes.key?(entry.idea_id) }
      end

      def progress
        Progress.new(done: vigentes.size, total: step.step_entries.size, label: "ideas testeadas")
      end

      def can_complete?
        faltan = sin_testear.size
        return [true, []] if faltan.zero?

        [false, ["Faltan #{Flow::Texto.contar(faltan, "idea")} por testear."]]
      end

      # Escribe el testeo nuevo y supera al anterior EN LA MISMA transacción:
      # si se escribiera primero el nuevo, el índice parcial lo rechazaría, y
      # si se superara primero y fallara el nuevo, la idea quedaría sin testeo
      # vigente.
      def testear!(idea:, verdict:, situations:, reservations:, summary:,
                   tested_by: nil, ai_run_id: nil)
        ActiveRecord::Base.transaction do
          StepTest.where(challenge_step_id: step.id, idea_id: idea.id, superseded_at: nil)
                  .update_all(superseded_at: Time.current)

          @vigentes = nil
          StepTest.create!(
            challenge_step: step, idea: idea, idea_version_id: idea.current_version_id,
            verdict: verdict, situations: situations, reservations: reservations,
            summary: summary, tested_by: tested_by, ai_run_id: ai_run_id,
            actor_type: tested_by ? "human" : "ai", tested_at: Time.current
          )
        end
      end

      def veredictos_contados
        StepTest::VERDICTS.index_with { |v| vigentes.values.count { |t| t.verdict == v } }
      end

      # EL VEREDICTO. Análogo a `Evaluation#score_visible_for?`: lo ve quien
      # administra siempre, y quien participa de la idea recién cuando el
      # módulo ya no sigue activo. Mientras corre puede venir un re-testeo, y
      # mostrar un "no factible" que todavía puede cambiar sería un resultado
      # a medias.
      def verdict_visible_for?(idea, user:, manager: false)
        return true if manager

        !step.active? && idea.participates?(user)
      end

      # QUIÉN TESTEÓ. Análogo a `Evaluation#breakdown_visible_for?`: es el
      # desglose, no el resultado. A diferencia de evaluación no hay a quién
      # sumarle la excepción de "ya lo hizo": solo quien administra testea
      # (`ChallengeStepPolicy#advance?`), así que el desglose es
      # exclusivamente suyo.
      def tester_visible_for?(manager: false) = manager

      protected

      # El resultado queda donde el resto de la app lo busca, igual que
      # `recompute_entry!` en evaluación. Todas `done`: nadie se elimina.
      def on_complete
        step.step_entries.each do |entry|
          test = vigente_para(entry.idea_id)
          entry.resolve!(status: "done",
                         result: entry.result.merge("verdict" => test&.verdict,
                                                    "tested_at" => test&.tested_at))
        end
      end

      private

      def vigentes
        @vigentes ||= StepTest.where(challenge_step_id: step.id, superseded_at: nil)
                              .index_by(&:idea_id)
      end
    end
  end
end
