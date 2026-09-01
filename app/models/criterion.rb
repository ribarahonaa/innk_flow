# frozen_string_literal: true

class Criterion < ApplicationRecord
  include TenantScoped

  # Explícito y no derivado de la inflexión: sin esto, un proceso que arranque
  # antes de cargar config/initializers/inflections.rb busca "criterions".
  self.table_name = "criteria"

  # Dos ejes independientes.
  #
  #   SOURCES     quién produce el valor
  #   SCALE_TYPES qué forma tiene ese valor
  #
  # Antes estaban colapsados: `formula` figuraba como escala cuando en
  # realidad es un origen (el valor se deriva de otros criterios).
  SOURCES = %w[manual automatic ai formula].freeze
  SCALE_TYPES = %w[numeric letter rubric boolean].freeze
  RESERVED_KEYS = %w[true false if and or not null nil].freeze

  belongs_to :criteria_set
  has_many :assessment_scores, foreign_key: :criterion_id, dependent: :nullify, inverse_of: :criterion

  validates :name, presence: true
  validates :source, inclusion: { in: SOURCES }
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
  validate :source_config_is_valid

  before_validation :align_scale_with_source

  before_validation :derive_key, on: :create

  scope :ordered, -> { order(:position, :created_at) }
  scope :active_ones, -> { where(active: true) }
  scope :automatic_ones, -> { where(source: "automatic") }
  scope :answerable, -> { where(source: %w[manual ai]) }

  SOURCES.each { |s| define_method("#{s}?") { source == s } }

  def scale = @scale ||= Flow::Scales::Base.for(self)

  def check = @check ||= (automatic? ? Flow::Checks::Base.for(self) : nil)

  # Nadie lo completa a mano: se calcula (fórmula) o se verifica (automático).
  def derived? = formula? || automatic?

  # Lo responde una persona o la IA en la ficha de evaluación.
  def answerable? = manual? || ai?

  def score(raw) = scale.call(raw)

  # Verifica el criterio automático contra una idea. => Checks::Base::Result
  def verify(idea) = check&.call(idea)

  def source_label = I18n.t("flow.criterion_sources.#{source}")

  def summary
    return check.description if automatic? && check

    return "fórmula: #{scale_config['expression']}" if formula?

    "#{source_label} · #{I18n.t("flow.scale_types.#{scale_type}")}"
  end

  # Snapshot que se congela en el módulo al activarlo.
  def to_snapshot
    { "id" => id, "key" => key, "name" => name, "description" => description,
      "weight" => weight.to_s, "source" => source, "source_config" => source_config,
      "scale_type" => scale_type, "scale_config" => scale_config, "position" => position }
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

  def source_config_is_valid
    return unless automatic?

    Flow::Checks::Base.for(self).config_errors.each { |message| errors.add(:source_config, message) }
  rescue Flow::Errors::UnknownCheck => e
    errors.add(:source_config, e.message)
  end

  # Un criterio automático o de fórmula no elige su escala: la primera produce
  # sí/no, la segunda un número. Dejar que se configuren por separado permitiría
  # estados incoherentes (un check con escala de letras).
  def align_scale_with_source
    self.scale_type = "boolean" if automatic?
    self.scale_type = "numeric" if formula?
  end
end
