# frozen_string_literal: true

# Un reporte generado desde un módulo de reportería.
#
# Ciclo de vida espejando el ExcelDocument de innk_r5: fila con estado +
# polling desde la vista + `failed?` por antigüedad, para que un worker que
# murió no deje un spinner eterno.
class Report < ApplicationRecord
  include TenantScoped

  KINDS = %w[funnel ranking snapshot narrative].freeze
  FORMATS = %w[dashboard xlsx pdf].freeze
  STATUSES = %w[pending ready failed].freeze
  STALE_AFTER = 30.minutes

  belongs_to :challenge_step
  belongs_to :requested_by, class_name: "User", optional: true
  belongs_to :ai_run, optional: true

  has_one_attached :file

  validates :kind, inclusion: { in: KINDS }
  validates :format, inclusion: { in: FORMATS }
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }
  scope :downloadable, -> { where.not(format: "dashboard") }

  STATUSES.each { |s| define_method("#{s}?") { status == s } }

  # Pendiente hace demasiado = el worker murió. Sin esto la UI espera para
  # siempre.
  def stalled? = pending? && created_at < STALE_AFTER.ago

  def kind_label = I18n.t("flow.report_kinds.#{kind}")
  def mode = scope["mode"].presence || "by_version"
end
