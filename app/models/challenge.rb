# frozen_string_literal: true

# Un desafío es un pipeline de módulos que arma su dueño.
#
# La secuencia NO es fija: reemplaza el `ideas.stage` 0..7 hardcodeado de
# innk_r5, idéntico para todos los clientes.
class Challenge < ApplicationRecord
  include TenantScoped

  STATUSES = %w[draft running closed archived].freeze
  AI_MODES = %w[human ai_assisted ai_auto].freeze

  has_many :steps, -> { order(:position) },
           class_name: "ChallengeStep", dependent: :destroy, inverse_of: :challenge
  # `class_name` explícito además de la inflexión: un proceso que arranque
  # antes del initializer busca `ChallengeGestore` y revienta con 500. Es la
  # misma lección que dejó `Criterion` con su `table_name`.
  has_many :challenge_gestores, class_name: "ChallengeGestor", dependent: :destroy
  has_many :gestores, through: :challenge_gestores, source: :user
  has_many :ideas, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :company_id },
                   format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }
  validates :status, inclusion: { in: STATUSES }
  validates :ai_default_mode, inclusion: { in: AI_MODES }

  before_validation :derive_slug, on: :create

  STATUSES.each { |s| define_method("#{s}?") { status == s } }

  scope :open_ones, -> { where(status: %w[draft running]) }

  def to_param = slug

  def pipeline = @pipeline ||= Flow::Pipeline.new(self)

  # Mutable sin restricciones solo antes de arrancar.
  def pipeline_editable_freely? = draft?

  private

  def derive_slug
    return if slug.present?

    base = name.to_s.parameterize.presence || "desafio"
    candidate = base
    n = 2
    candidate = "#{base}-#{n += 1}" while self.class.where(slug: candidate).exists?
    self.slug = candidate
  end
end
