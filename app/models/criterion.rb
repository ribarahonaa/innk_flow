# frozen_string_literal: true

class Criterion < ApplicationRecord
  include TenantScoped

  # Explícito y no derivado de la inflexión: sin esto, un proceso que arranque
  # antes de cargar config/initializers/inflections.rb busca "criterions".
  self.table_name = "criteria"

  SCALE_TYPES = %w[numeric letter rubric formula].freeze
  RESERVED_KEYS = %w[true false if and or not null nil].freeze

  belongs_to :criteria_set
  has_many :assessment_scores, foreign_key: :criterion_id, dependent: :nullify, inverse_of: :criterion

  validates :name, presence: true
  validates :scale_type, inclusion: { in: SCALE_TYPES }
  validates :weight, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  # La `key` es el identificador que usan las fórmulas: inmutable de hecho una
  # vez que hay notas, y con forma de variable.
  validates :key, presence: true,
                  uniqueness: { scope: :criteria_set_id },
                  format: { with: /\A[a-z][a-z0-9_]{0,39}\z/,
                            message: "solo minúsculas, números y guión bajo, empezando por letra" },
                  exclusion: { in: RESERVED_KEYS, message: "es una palabra reservada" }

  validate :scale_config_is_valid

  before_validation :derive_key, on: :create

  scope :ordered, -> { order(:position, :created_at) }
  scope :active_ones, -> { where(active: true) }

  def scale = @scale ||= Flow::Scales::Base.for(self)

  def derived? = scale.derived?

  def score(raw) = scale.call(raw)

  # Snapshot que se congela en el módulo al activarlo.
  def to_snapshot
    { "id" => id, "key" => key, "name" => name, "description" => description,
      "weight" => weight.to_s, "scale_type" => scale_type, "scale_config" => scale_config,
      "position" => position }
  end

  private

  def derive_key
    return if key.present? || name.blank?

    base = name.to_s.parameterize(separator: "_").gsub(/\A[^a-z]+/, "").presence || "criterio"
    taken = criteria_set ? Criterion.where(criteria_set_id: criteria_set_id).pluck(:key) : []
    candidate = base
    n = 1
    candidate = "#{base}_#{n += 1}" while taken.include?(candidate)
    self.key = candidate
  end

  def scale_config_is_valid
    scale.config_errors.each { |message| errors.add(:scale_config, message) }
  rescue StandardError => e
    errors.add(:scale_type, "escala no soportada: #{e.message}")
  end
end
