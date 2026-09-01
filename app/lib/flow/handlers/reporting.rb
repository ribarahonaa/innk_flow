# frozen_string_literal: true

module Flow
  module Handlers
    # «Reportería»: fotografía el estado del desafío en este punto del flujo.
    class Reporting < Base
      def can_activate? = [true, []]

      def progress
        total = reports.size
        done = reports.count(&:ready?)
        Progress.new(done: done, total: [total, 1].max, label: "reportes generados")
      end

      def can_complete? = [true, []]

      def reports = @reports ||= Report.where(challenge_step_id: step.id).recent.to_a

      def dashboard
        @dashboard ||= Flow::Reports::Builder.new(step, scope: report_scope).call
      end

      def report_scope
        { "mode" => settings["mode"].presence || "by_version",
          "include_eliminated" => settings.fetch("include_eliminated", true),
          "step_slugs" => settings["step_slugs"] }
      end

      protected

      # El tablero se genera solo al activar; los archivos van a Sidekiq.
      def on_activate
        create_report!(kind: "snapshot", format: "dashboard")
        request_narrative! unless effective_ai_mode == "human"
      end

      def on_complete
        reports.select(&:pending?).each { |report| report.update!(status: "failed", error: "el módulo se cerró antes") }
      end

      private

      def create_report!(kind:, format:)
        report = Report.create!(challenge_step: step, kind: kind, format: format,
                                scope: report_scope, status: "pending")
        if format == "dashboard"
          report.update!(data: dashboard, status: "ready", generated_at: Time.current,
                         row_count: dashboard.dig("ranking")&.size)
        end
        @reports = nil
        report
      end

      def request_narrative!
        Flow::AI::RunJob.perform_later(step.company_id, "summarize_challenge", { "step_id" => step.id })
      end
    end
  end
end
