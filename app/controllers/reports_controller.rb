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
    # `downloadable` saca los `dashboard`, que nacen `ready` sin archivo: no son
    # un archivo que exista, así que no son un 404 por accidente sino por regla.
    report = Report.where(challenge_step_id: @step.id).downloadable.find(params[:id])

    send_attached_file(report.file)
  end

  # Polling: el patrón de ExcelDocument de innk_r5, scopeado al tenant.
  def statuses
    authorize @step, :report?
    reports = Report.where(challenge_step_id: @step.id, status: "ready").where.not(format: "dashboard")

    render json: {
      # Sin `url`: nadie la leía. El JS de `shared/_reports_auto_refresh` mira
      # `pending` y recarga la pantalla, que es la que trae los links.
      ready: reports.map { |report| { id: report.id, format: report.format, kind: report.kind } },
      pending: Report.where(challenge_step_id: @step.id, status: "pending").count
    }
  end

  private

  def set_context
    @challenge = policy_scope(Challenge).find_by!(slug: params[:challenge_id])
    @step = @challenge.steps.find(params[:step_id])
  end
end
