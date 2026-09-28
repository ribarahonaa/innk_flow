# frozen_string_literal: true

class ReportsController < ApplicationController
  before_action :set_context

  def create
    authorize @step, :report?
    report = Report.create!(
      challenge_step: @step, kind: params[:kind].presence || "snapshot",
      format: params[:format].presence || "xlsx",
      scope: @step.handler.report_scope, status: "pending", requested_by: current_user
    )
    Flow::Reports::GenerateJob.perform_later(@step.company_id, report.id)

    redirect_to challenge_step_path(@challenge, @step),
                notice: "Generando el reporte. La pantalla se actualiza sola."
  end

  # El archivo lo sirve la app y no Active Storage, que verifica la firma del
  # blob y nada más. Misma puerta que generarlo.
  def download
    authorize @step, :report?
    report = Report.where(challenge_step_id: @step.id).find(params[:id])

    send_data report.file.download,
              filename: report.file.filename.to_s,
              type: report.file.content_type,
              disposition: "attachment"
  end

  # Polling: el patrón de ExcelDocument de innk_r5, scopeado al tenant.
  def statuses
    authorize @step, :report?
    reports = Report.where(challenge_step_id: @step.id, status: "ready").where.not(format: "dashboard")

    render json: {
      ready: reports.map do |report|
        { id: report.id, format: report.format, kind: report.kind,
          url: report.file.attached? ? download_challenge_step_report_path(@challenge, @step, report) : nil }
      end,
      pending: Report.where(challenge_step_id: @step.id, status: "pending").count
    }
  end

  private

  def set_context
    @challenge = policy_scope(Challenge).find_by!(slug: params[:challenge_id])
    @step = @challenge.steps.find(params[:step_id])
  end
end
