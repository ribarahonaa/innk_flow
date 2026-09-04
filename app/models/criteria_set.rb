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
  # Mismo desempate que `Criterion.ordered`: sin `created_at` dos criterios con
  # la misma posición salen en el orden que quiera Postgres, y ese orden termina
  # congelado en el snapshot del módulo y en las columnas de la tabla.
  has_many :criteria, -> { order(:position, :created_at) },
           dependent: :destroy, inverse_of: :criteria_set
  has_many :challenge_steps, dependent: :nullify

  validates :name, presence: true
  validates :scope, inclusion: { in: SCOPES }
  validates :status, inclusion: { in: STATUSES }

  accepts_nested_attributes_for :criteria, allow_destroy: true

  scope :library, -> { where(scope: "library") }
  scope :usable, -> { where(status: "valid") }
  # La versión vigente de cada familia: la que se ofrece para asignar.
  scope :current, -> { where(superseded_at: nil) }

  before_create :start_family

  SCOPES.each { |s| define_method("#{s}?") { self.scope == s } }

  # Un set EN USO no se puede editar en el lugar: hay módulos que todavía no
  # arrancaron apuntándole, y cambiarle los criterios les cambiaría la vara
  # sin avisar. Los que ya arrancaron tienen su snapshot congelado y no corren
  # riesgo, pero los pendientes sí.
  def in_use? = challenge_steps.exists?

  def superseded? = superseded_at.present?

  def label = version > 1 ? "#{name} · v#{version}" : name

  # La huella de lo que decide un puntaje. Cambiar el nombre del set no crea
  # una versión; cambiar un criterio, un peso o una escala, sí.
  def fingerprint
    criteria.ordered.map do |c|
      [c.key, c.name, c.weight.to_d.round(6), c.source, c.scale_type,
       c.source_config, c.scale_config, c.active]
    end
  end

  # Crea la versión siguiente, con una copia de los criterios. La anterior
  # queda marcada y sigue sirviendo a quien ya la estaba usando.
  def next_version!
    copia = CriteriaSet.create!(
      name: name, description: description, scope: scope, owner_step_id: owner_step_id,
      family_id: family_id, version: CriteriaSet.where(family_id: family_id).maximum(:version).to_i + 1
    )
    criteria.ordered.each do |criterion|
      copia.criteria.create!(criterion.attributes.except("id", "criteria_set_id", "created_at", "updated_at"))
    end
    update!(superseded_at: Time.current)
    copia
  end

  def active_criteria = criteria.select(&:active)

  def scored_criteria = active_criteria.select(&:answerable?)
  def automatic_criteria = active_criteria.select(&:automatic?)

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

  # Cada set nace siendo su propia familia; las versiones siguientes heredan
  # el family_id de la primera.
  def start_family
    self.family_id ||= id || SecureRandom.uuid
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
