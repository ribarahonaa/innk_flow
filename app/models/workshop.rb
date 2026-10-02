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

  # Cómo se establece la presencia. `presumed` es lo de siempre: el reparto
  # sienta al pool completo y marcar ausentes es la excepción. `registered` dice
  # que la presencia la ESCRIBE alguien —el escaneo, o el toggle de la pantalla—
  # y que quien no está marcado no está.
  ATTENDANCE_MODES = %w[presumed registered].freeze

  belongs_to :created_by, class_name: "User", optional: true
  has_many :workshop_challenges, dependent: :destroy
  has_many :challenges, through: :workshop_challenges
  has_many :workshop_groups, dependent: :destroy

  validates :name, presence: true
  validates :mode, inclusion: { in: MODES }
  validates :status, inclusion: { in: STATUSES }
  validates :attendance_mode, inclusion: { in: ATTENDANCE_MODES }

  has_secure_token :checkin_token

  STATUSES.each { |s| define_method("#{s}?") { status == s } }

  def individual? = mode == "individual"

  def presumed_attendance? = attendance_mode == "presumed"
  def registered_attendance? = attendance_mode == "registered"

  # Qué puede hacer el link, en UN valor. Misma forma que
  # `WorkshopChallenge#room_state`: con un valor cerrado y un `case` con `else`
  # la pantalla no puede quedarse muda cuando mañana haya un estado más, que es
  # justo cómo una sala se renderizó vacía sin un solo mensaje.
  #
  # Borrador y cerrado se distinguen porque la pantalla dice cosas distintas:
  # «volvé cuando empiece» sobre un taller que ya terminó es mentira.
  def checkin_state
    return :off unless registered_attendance?
    return :closed if closed?
    return :draft if draft?

    :open
  end

  def checkin_open? = checkin_state == :open

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
