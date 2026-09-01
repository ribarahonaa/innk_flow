# frozen_string_literal: true

module Flow
  module Reports
    # Arma los datos del reporte. Una sola fuente de cómputo para el tablero,
    # el Excel y el PDF — como el IdeaPivot::Calculator de innk_r5, que es el
    # patrón que ese repo hizo bien.
    class Builder
      def initialize(step, scope: {})
        @step = step
        @challenge = step.challenge
        @scope = (scope || {}).with_indifferent_access
      end

      attr_reader :step, :challenge, :scope

      def call
        {
          "challenge" => challenge_summary,
          "funnel" => funnel,
          "ranking" => ranking,
          "distribution" => distribution,
          "evaluators" => evaluator_participation,
          "matrix" => matrix,
          "mode" => mode,
          "as_of" => Time.current.iso8601
        }
      end

      # by_version: cada celda dice sobre qué versión se evaluó.
      # latest: solo la versión vigente, marcando lo desactualizado.
      #
      # NUNCA se promedia entre versiones distintas sin decirlo — es el punto
      # del modo.
      def mode = scope[:mode].presence || "by_version"

      def include_eliminated? = scope[:include_eliminated].to_s != "false"

      private

      def challenge_summary
        {
          "name" => challenge.name,
          "status" => challenge.status,
          "brief" => challenge.brief,
          "ai_default_mode" => challenge.ai_default_mode,
          "started_at" => challenge.started_at&.iso8601
        }
      end

      # El embudo real del flujo: cuántas ideas participaron de cada módulo.
      # Es un COUNT(*) limpio porque step_entries solo existe para
      # participación real.
      def funnel
        scoped_steps.map do |s|
          entries = s.step_entries
          {
            "slug" => s.slug, "name" => s.name, "kind" => s.kind, "status" => s.status,
            "position" => s.position.to_f,
            "entered" => entries.size,
            "advanced" => entries.count { |e| e.status == "advanced" },
            "eliminated" => entries.count { |e| e.status == "eliminated" }
          }
        end
      end

      def ranking
        source = last_evaluation
        return [] if source.nil?

        rows = source.step_entries.includes(idea: %i[current_version author]).filter_map do |entry|
          score = entry.result["score"]
          next if score.nil?
          next if !include_eliminated? && entry.idea.eliminated?

          {
            "idea_id" => entry.idea_id,
            "title" => entry.idea.title,
            "author" => entry.idea.author.name,
            "origin" => entry.idea.origin,
            "status" => entry.idea.status,
            "score" => score.to_f,
            "assessments" => entry.result["assessments_count"],
            "dispersion" => entry.result["dispersion"],
            "version" => entry.input_version&.label,
            "current_version" => entry.idea.current_version&.label,
            "stale" => entry.input_version_id.present? && entry.input_version_id != entry.idea.current_version_id
          }
        end

        rows.sort_by { |row| -row["score"] }.each_with_index.map { |row, i| row.merge("rank" => i + 1) }
      end

      # Histograma de puntajes en tramos de 10%.
      def distribution
        scores = ranking.map { |row| row["score"] }
        return [] if scores.empty?

        (0...10).map do |bucket|
          low = bucket / 10.0
          high = (bucket + 1) / 10.0
          count = scores.count { |s| s >= low && (bucket == 9 ? s <= high : s < high) }
          { "label" => "#{(low * 100).round}–#{(high * 100).round}%", "count" => count }
        end
      end

      def evaluator_participation
        evaluation_steps.flat_map do |s|
          expected = s.step_assignments.size
          submitted = s.assessments.current.submitted_ones.map(&:evaluator_id).compact.uniq.size
          next [] if expected.zero? && submitted.zero?

          [{ "step" => s.name, "expected" => expected, "submitted" => submitted,
             "assessments" => s.assessments.current.submitted_ones.size }]
        end
      end

      # Matriz idea × módulo de evaluación. En modo by_version cada celda
      # lleva la versión que se juzgó.
      def matrix
        steps = evaluation_steps
        return { "columns" => [], "rows" => [] } if steps.empty?

        ideas = challenge.ideas.includes(:current_version, :author)
        ideas = ideas.where.not(status: "eliminated") unless include_eliminated?

        rows = ideas.map do |idea|
          cells = steps.map do |s|
            entry = s.step_entries.detect { |e| e.idea_id == idea.id }
            next({ "score" => nil, "version" => nil }) if entry.nil?

            score = entry.result["score"]
            version = entry.input_version&.label
            cell = { "score" => score&.to_f }
            cell["version"] = version if mode == "by_version"
            cell["stale"] = entry.input_version_id.present? &&
                            entry.input_version_id != idea.current_version_id
            cell
          end

          { "idea_id" => idea.id, "title" => idea.title, "status" => idea.status,
            "current_version" => idea.current_version&.label, "cells" => cells }
        end

        { "columns" => steps.map { |s| { "slug" => s.slug, "name" => s.name } }, "rows" => rows }
      end

      def scoped_steps
        slugs = Array(scope[:step_slugs])
        list = challenge.steps.ordered.reject { |s| s.position.to_d > step.position.to_d }
        slugs.any? ? list.select { |s| slugs.include?(s.slug) } : list
      end

      def evaluation_steps = scoped_steps.select(&:evaluation?)

      def last_evaluation = evaluation_steps.max_by { |s| s.position.to_d }
    end
  end
end
