# frozen_string_literal: true

# Un taller: una sesión de trabajo que abarca N desafíos.
#
# NO es un módulo del flujo. El motor tiene un módulo activo por construcción
# (`Flow::Pipeline#active_step`), y un taller es un evento que se monta sobre
# la fase que cada desafío ya está corriendo.
class Workshop < ApplicationRecord
  include TenantScoped

  MODES = %w[individual group].freeze
  STATUSES = %w[draft open closed].freeze

  belongs_to :created_by, class_name: "User", optional: true
  has_many :workshop_challenges, dependent: :destroy
  has_many :challenges, through: :workshop_challenges
  has_many :workshop_groups, dependent: :destroy

  validates :name, presence: true
  validates :mode, inclusion: { in: MODES }
  validates :status, inclusion: { in: STATUSES }

  STATUSES.each { |s| define_method("#{s}?") { status == s } }

  def individual? = mode == "individual"

  # La fase del taller: el `kind` de sus vínculos abiertos, homogéneo por la
  # regla de `Flow::Workshops::Open`. Se DERIVA y no se guarda: una columna
  # sería la segunda fuente que el día que difiera de los vínculos miente.
  def phase = workshop_challenges.select(&:open?).map(&:kind).compact.uniq.first
end
