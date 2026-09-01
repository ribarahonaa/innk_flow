# frozen_string_literal: true

# Conjunto de criterios de evaluación.
#
# `library` = plantilla reusable de la empresa. `inline` = criterios ad-hoc de
# un módulo. Misma tabla y un flag, no dos code paths.
class CriteriaSet < ApplicationRecord
  include TenantScoped

  SCOPES = %w[library inline].freeze
  STATUSES = %w[draft valid invalid].freeze
  WEIGHT_TOLERANCE = 1e-6

  belongs_to :owner_step, class_name: "ChallengeStep", optional: true
  has_many :criteria, -> { order(:position) }, dependent: :destroy, inverse_of: :criteria_set
  has_many :challenge_steps, dependent: :nullify

  validates :name, presence: true
  validates :scope, inclusion: { in: SCOPES }
  validates :status, inclusion: { in: STATUSES }

  accepts_nested_attributes_for :criteria, allow_destroy: true

  scope :library, -> { where(scope: "library") }
  scope :usable, -> { where(status: "valid") }

  SCOPES.each { |s| define_method("#{s}?") { self.scope == s } }

  def active_criteria = criteria.select(&:active)

  def scored_criteria = active_criteria.reject { |c| c.scale.derived? }

  def weight_total = active_criteria.sum { |c| c.weight.to_d }

  # Se recalcula en cada guardado y también antes de activar un módulo: un set
  # puede volverse inválido después de haberse asignado.
  def validation_errors
    errors = []
    errors << "el set necesita al menos un criterio activo" if active_criteria.empty?

    unless active_criteria.empty? || (weight_total - 1).abs <= WEIGHT_TOLERANCE
      errors << "los pesos de los criterios activos deben sumar 1 (suman #{weight_total.round(4)})"
    end

    active_criteria.each do |criterion|
      criterion.scale.config_errors.each { |e| errors << "«#{criterion.name}»: #{e}" }
    end

    errors
  end

  def refresh_status!
    update_column(:status, validation_errors.empty? ? "valid" : "invalid")
  end

  # Copia a la biblioteca de la empresa. Un set inline nace atado a un módulo;
  # promoverlo lo vuelve reusable sin arrastrar esa atadura.
  def promote_to_library!(name: nil)
    copy = CriteriaSet.create!(name: name || "#{self.name} (copia)", scope: "library",
                               description: description, status: status)
    criteria.each do |criterion|
      copy.criteria.create!(criterion.attributes.except("id", "criteria_set_id", "created_at", "updated_at"))
    end
    copy
  end
end
