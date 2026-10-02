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

  ARRIVAL_NAME = "Mesa de llegada"

  # La mesa de llegada, creándola si falta: la sala de espera donde cae quien
  # entra por el link y quien se queda sin mesa al borrar la suya. Una sola
  # implementación para los dos caminos (`Flow::Workshops::CheckIn` y
  # `WorkshopGroupsController#destroy`); vive en el taller porque es SU mesa,
  # una por taller, y no de un servicio u otro.
  #
  # En modo individual devuelve `nil`: NO hay mesa de llegada. `Convoke#own_group`
  # arma la mesa de una persona, que es el diseño de ese modo, y devolver `nil`
  # es pedirle exactamente eso. Y quien borre una mesa ahí no tiene a dónde
  # mandar a su gente: cada persona ES su mesa.
  def arrival_group!
    return nil if individual?

    # Con su propio savepoint (`requires_new`): este método se llama FUERA de
    # una transacción (el escaneo) y ADENTRO de una (borrar una mesa). Adentro,
    # un UNIQUE violado por el `create!` aborta la transacción entera si no hay
    # savepoint, y el `find_by!` del rescate corre contra una transacción
    # envenenada (`PG::InFailedSqlTransaction`): un 500 justo donde se promete
    # recuperar. El savepoint deshace sólo ese INSERT y el rescate puede consultar.
    transaction(requires_new: true) do
      workshop_groups.find_or_create_by!(arrival: true) { |g| g.name = ARRIVAL_NAME }
    end
  rescue ActiveRecord::RecordNotUnique
    # El índice UNIQUE parcial es lo que un `find_or_create_by!` no puede
    # garantizar: es un SELECT y después un INSERT, y dos pedidos de la llegada
    # en el mismo segundo lo atraviesan (dos escaneos, o un escaneo y un
    # borrado de mesa). Que la base frene al segundo es correcto; lo que no
    # corresponde es que quien está entrando vea un 500.
    workshop_groups.find_by!(arrival: true)
  end

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
