# frozen_string_literal: true

module Flow
  module Evaluation
    # Calcula el puntaje de UNA evaluación a partir de sus notas por criterio.
    #
    # Dos reglas que importan:
    #   · Renormaliza por la suma de pesos RESPONDIDOS. Una evaluación parcial
    #     no se castiga por los criterios que faltan; si el módulo exige
    #     completarla, eso se impide antes, al enviar.
    #   · Los criterios fórmula se calculan DESPUÉS, en orden topológico, con
    #     los valores de sus hermanos.
    class ScoreAssessment
      def initialize(assessment, criteria_snapshot: nil)
        @assessment = assessment
        @snapshot = criteria_snapshot || assessment.challenge_step.settings["criteria"] || []
      end

      attr_reader :assessment

      def call
        scores = assessment.assessment_scores.index_by(&:criterion_key)
        compute_automatic!(scores)
        compute_derived!(scores)

        answered = scores.values.select(&:answered?)
        weight_sum = answered.sum { |s| s.weight_used.to_d }

        normalized =
          if weight_sum.positive?
            answered.sum { |s| s.normalized_value.to_d * s.weight_used.to_d } / weight_sum
          end

        assessment.update!(
          normalized_score: normalized,
          raw_score: raw_score_for(normalized)
        )
        normalized
      end

      private

      # Los criterios automáticos no los completa nadie: se verifican contra la
      # idea al guardar la evaluación. Un check que pasa vale 1, uno que no, 0,
      # y pesa igual que cualquier otro criterio del set.
      def compute_automatic!(scores)
        @snapshot.select { |config| config["source"] == "automatic" }.each do |config|
          criterion = Criterion.find_by(id: config["id"])
          next if criterion.nil?

          result = criterion.verify(assessment.idea)
          upsert_score(config, scores) do |score|
            score.assign_attributes(
              raw_value: result&.passed? ? "1" : "0",
              numeric_value: result&.passed? ? 1 : 0,
              normalized_value: result&.passed? ? 1 : 0,
              comment: result&.detail,
              error: nil
            )
          end
        rescue Flow::Errors::UnknownCheck => e
          upsert_score(config, scores) do |score|
            score.assign_attributes(numeric_value: nil, normalized_value: nil, error: e.message)
          end
        end
      end

      # `raw_score` solo tiene sentido si todas las escalas comparten rango.
      # Si el set mezcla una nota 1-10 con una letra A-F, el número crudo no
      # significa nada y se deja nil: la UI muestra porcentaje.
      def raw_score_for(normalized)
        return nil if normalized.nil?

        numerics = @snapshot.select { |c| c["scale_type"] == "numeric" && c["source"] == "manual" }
        return nil unless numerics.size == @snapshot.count { |c| c["source"] == "manual" }
        return nil if numerics.empty?

        ranges = numerics.map { |c| [(c.dig("scale_config", "min") || 1).to_d, (c.dig("scale_config", "max") || 10).to_d] }.uniq
        return nil unless ranges.size == 1

        min, max = ranges.first
        min + (normalized * (max - min))
      end

      # Orden topológico: una fórmula puede depender de otra.
      def compute_derived!(scores)
        derived = @snapshot.select { |c| c["source"] == "formula" }
        return if derived.empty?

        remaining = derived.dup
        # Tope de pasadas = cantidad de fórmulas: si queda algo sin resolver
        # es porque hay un ciclo, y el validador ya debería haberlo impedido.
        derived.size.times do
          progressed = false

          remaining.reject! do |config|
            bindings = bindings_for(config, scores)
            next false if bindings.nil?

            write_derived!(config, bindings, scores)
            progressed = true
            true
          end

          break unless progressed
        end

        remaining.each do |config|
          upsert_score(config, scores) do |score|
            score.assign_attributes(numeric_value: nil, normalized_value: nil,
                                    error: "no se pudo resolver: faltan criterios de los que depende")
          end
        end
      end

      def bindings_for(config, scores)
        expression = config.dig("scale_config", "expression").to_s
        dependencies = Flow::Formula::Calculator.new(expression).dependencies

        dependencies.each_with_object({}) do |key, acc|
          score = scores[key]
          return nil if score.nil? || score.numeric_value.nil?

          acc[key] = score.numeric_value
        end
      rescue StandardError
        nil
      end

      def write_derived!(config, bindings, scores)
        criterion = Criterion.find_by(id: config["id"])
        scale = criterion&.scale

        upsert_score(config, scores) do |score|
          value = Flow::Formula::Calculator.new(config.dig("scale_config", "expression")).evaluate(bindings)
          normalized = scale ? scale.send(:clamp, scale.normalize(value)) : nil
          score.assign_attributes(raw_value: value&.to_s, numeric_value: value,
                                  normalized_value: normalized, error: nil)
        rescue Flow::Errors::InvalidFormula => e
          # Una fórmula rota NO tumba la evaluación: se muestra "—" con el
          # motivo, y el resto de los criterios sigue contando.
          score.assign_attributes(numeric_value: nil, normalized_value: nil, error: e.message)
        end
      end

      def upsert_score(config, scores)
        score = scores[config["key"]] ||
                assessment.assessment_scores.build(criterion_key: config["key"],
                                                   criterion_id: config["id"])
        score.weight_used = config["weight"].to_d
        yield score
        score.save!
        scores[config["key"]] = score
      end
    end
  end
end
