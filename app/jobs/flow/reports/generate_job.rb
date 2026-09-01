# frozen_string_literal: true

module Flow
  module Reports
    # Genera el archivo del reporte. Va a Sidekiq porque produce un archivo y
    # recorre todo el cohorte.
    class GenerateJob < ApplicationJob
      queue_as :flow_reports

      def perform(company_id, report_id)
        company = Flow::Tenant.bypass! { Company.find_by(id: company_id) }
        return if company.nil?

        Flow::Tenant.with(company) do
          report = Report.find_by(id: report_id)
          return if report.nil? || report.ready?

          data = Flow::Reports::Builder.new(report.challenge_step, scope: report.scope).call
          attach_file!(report, data)

          report.update!(status: "ready", data: data, generated_at: Time.current,
                         row_count: data["ranking"]&.size)
        end
      rescue StandardError => e
        Flow::Tenant.bypass! do
          Report.find_by(id: report_id)&.update(status: "failed", error: "#{e.class}: #{e.message}")
        end
        raise
      end

      private

      def attach_file!(report, data)
        case report.format
        when "xlsx"
          report.file.attach(
            io: StringIO.new(Flow::Reports::XlsxWriter.new(data).call),
            filename: filename(report, "xlsx"),
            content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
          )
        when "pdf"
          report.file.attach(
            io: StringIO.new(render_pdf(report, data)),
            filename: filename(report, "pdf"),
            content_type: "application/pdf"
          )
        end
      end

      def render_pdf(report, data)
        html = ApplicationController.render(
          template: "reports/pdf",
          layout: "pdf",
          assigns: { report: report, data: data }
        )
        WickedPdf.new.pdf_from_string(html, page_size: "Letter",
                                            margin: { top: 18, bottom: 16, left: 14, right: 14 })
      end

      def filename(report, extension)
        slug = report.challenge_step.challenge.slug
        "reporte-#{slug}-#{report.generated_at&.to_date || Date.current}.#{extension}"
      end
    end
  end
end
