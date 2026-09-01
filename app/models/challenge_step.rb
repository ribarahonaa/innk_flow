# frozen_string_literal: true

# Una instancia de módulo dentro de un desafío.
#
# "Instancia" es la palabra: un desafío puede tener dos evaluaciones y tres
# selecciones, cada una con su propia configuración. Solo `ideation` es único.
class ChallengeStep < ApplicationRecord
  include TenantScoped

  KINDS = %w[ideation evolution evaluation selection reporting].freeze
  SINGLETON_KINDS = %w[ideation].freeze
  STATUSES = %w[pending activating active completed skipped].freeze
  TOUCHED_STATUSES = %w[activating active completed skipped].freeze

  # Campos que se congelan cuando el step deja de estar pending. Cambiarlos
  # después reescribiría la historia (p.ej. mover un módulo ya ejecutado).
  FROZEN_ATTRIBUTES = %w[kind slug challenge_id position config source_step_id].freeze

  belongs_to :challenge, inverse_of: :steps
  belongs_to :source_step, class_name: "ChallengeStep", optional: true
  has_many :dependent_steps, class_name: "ChallengeStep",
                             foreign_key: :source_step_id, dependent: :nullify, inverse_of: :source_step
  has_many :step_entries, dependent: :destroy
  has_many :entry_ideas, through: :step_entries, source: :idea
  # Solo el módulo de ideación los usa.
  has_many :form_fields, -> { order(:position) }, dependent: :destroy, inverse_of: :challenge_step
  belongs_to :criteria_set, optional: true
  has_many :assessments, dependent: :destroy
  has_many :step_assignments, dependent: :destroy
  has_many :assigned_users, through: :step_assignments, source: :user

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :ai_mode, inclusion: { in: Challenge::AI_MODES }, allow_nil: true
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :challenge_id },
                   format: { with: /\A[a-z][a-z0-9_]*\z/ }
  validates :position, presence: true, numericality: { greater_than: 0 }

  validate :single_ideation_per_challenge
  validate :source_step_precedes_self
  validate :position_respects_insertion_floor
  validate :frozen_attributes_unchanged

  before_validation :derive_slug, on: :create
  before_validation :derive_name, on: :create

  scope :ordered, -> { order(:position) }
  scope :touched, -> { where(status: TOUCHED_STATUSES) }
  scope :pending_ones, -> { where(status: "pending") }

  STATUSES.each { |s| define_method("#{s}?") { status == s } }
  KINDS.each { |k| define_method("#{k}?") { kind == k } }

  def touched? = TOUCHED_STATUSES.include?(status)

  # ─────────────────────────────────────────────────────────────────────────
  # ÚNICO accesor público de configuración.
  #
  # Un step pending se lee de `config` (intención del autor, puede decir
  # "auto"); uno ya tocado se lee de `resolved_config` (materialización
  # congelada en activate!). Leer la fuente equivocada da comportamiento
  # distinto según el estado — por eso config y resolved_config son privados
  # y esto es lo único que el resto del código toca.
  # ─────────────────────────────────────────────────────────────────────────
  def settings
    (touched? ? resolved_config : config) || {}
  end

  def effective_ai_mode = ai_mode.presence || challenge.ai_default_mode

  def handler = Flow::Handlers::Base.for(self)

  def display_kind = I18n.t("flow.kinds.#{kind}")

  private

  def derive_slug
    return if slug.present?

    base = kind
    taken = challenge&.steps&.reject { |s| s == self }&.map(&:slug).to_a
    return self.slug = base if taken.exclude?(base)

    n = 2
    n += 1 while taken.include?("#{base}_#{n}")
    self.slug = "#{base}_#{n}"
  end

  def derive_name
    self.name = I18n.t("flow.kinds.#{kind}") if name.blank? && kind.present?
  end

  def single_ideation_per_challenge
    return unless SINGLETON_KINDS.include?(kind)
    return if challenge.nil?

    siblings = challenge.steps.reject { |s| s == self || (persisted? && s.id == id) }
    return if siblings.none? { |s| s.kind == kind }

    errors.add(:kind, :duplicate_singleton,
               message: "«#{I18n.t("flow.kinds.#{kind}")}» se genera una sola vez por desafío")
  end

  # Una selección no puede tomar el puntaje de una evaluación que viene después.
  def source_step_precedes_self
    return if source_step.nil?

    errors.add(:source_step_id, "debe pertenecer al mismo desafío") if source_step.challenge_id != challenge_id
    errors.add(:source_step_id, "debe estar antes en el flujo") if source_step.position.to_d >= position.to_d
  end

  # La regla dura del producto, replicada como invariante de modelo.
  #
  # Flow::Pipeline#insertion_floor es la API ergonómica, pero nada impide un
  # `step.update(position: 0.5)` desde la consola. Acá se cierra esa puerta.
  def position_respects_insertion_floor
    return if challenge.nil?
    return unless position_changed? || new_record?

    floor = Flow::Pipeline.new(challenge).insertion_floor(excluding: self)
    return if floor.nil? || position.to_d > floor

    errors.add(:position, :below_insertion_floor,
               message: "no se puede insertar antes ni entre módulos ya ejecutados")
  end

  def frozen_attributes_unchanged
    return if new_record?
    return unless TOUCHED_STATUSES.include?(status_was.to_s)

    changed_frozen = changed & FROZEN_ATTRIBUTES
    return if changed_frozen.empty?

    errors.add(:base, "un módulo ya ejecutado no se puede modificar (#{changed_frozen.join(', ')})")
  end
end
