# frozen_string_literal: true

# Participación real de una idea en un módulo.
#
# Se crea LAZY (Flow::Cohort.sync!, al activar el step) y solo para ideas
# vivas. Que exista una fila significa "esta idea participó de este módulo",
# sin condiciones extra — por eso los reportes son COUNT(*) limpios.
class StepEntry < ApplicationRecord
  include TenantScoped

  STATUSES = %w[pending in_progress done advanced eliminated].freeze

  belongs_to :challenge_step
  belongs_to :idea
  belongs_to :input_version, class_name: "IdeaVersion", optional: true
  belongs_to :output_version, class_name: "IdeaVersion", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :idea_id, uniqueness: { scope: :challenge_step_id }

  scope :pending_ones, -> { where(status: "pending") }
  scope :resolved, -> { where(status: %w[done advanced eliminated]) }

  STATUSES.each { |s| define_method("#{s}?") { status == s } }

  def score = result["score"]

  def resolve!(status:, output_version: nil, result: nil)
    update!(
      status: status,
      output_version: output_version,
      result: result || self.result,
      resolved_at: Time.current
    )
  end
end
