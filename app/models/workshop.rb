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

  # La fase del taller: el `kind` de sus vínculos VIVOS, homogéneo por la
  # regla de `Flow::Workshops::Open`. Se DERIVA y no se guarda: una columna
  # sería la segunda fuente que el día que difiera de los vínculos miente.
  #
  # `workable?` y no `open?`: tras un `advance!` el vínculo sigue `open` con su
  # módulo `completed` hasta que `MaterializeClosures` corre —que busca justo
  # `open? && !workable?`—, y esa fase ya no está en curso.
  #
  # Si los vínculos vivos no coinciden devuelve nil en vez de elegir uno: la
  # homogeneidad sólo vale desde la regla de `Open`, y un taller abierto antes
  # de ella con vínculos mezclados no debe recibir una fase adivinada.
  def phase
    kinds = workshop_challenges.select(&:workable?).map(&:kind).compact.uniq
    kinds.size == 1 ? kinds.first : nil
  end
end
