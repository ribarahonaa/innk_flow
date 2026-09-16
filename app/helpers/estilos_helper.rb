# frozen_string_literal: true

# Traduce un estado del dominio a la clase que lo pinta.
#
# POR QUÉ EXISTE: Tailwind escanea texto, así que una clase armada con
# interpolación no la ve y la descarta. Todo lo de acá devuelve el nombre
# COMPLETO, escrito literal, y nunca lo arma con #{}.
#
# El efecto de rebote es el que importa a largo plazo: la traducción estado ->
# estilo queda en UN lugar. Antes el ternario
# `run.succeeded? ? 'completed' : ...` estaba repetido en cinco vistas, y
# cambiar el estilo de «falló» significaba encontrarlas todas.
module EstilosHelper
  # Los chips son `badge` de DaisyUI, en su variante suave, y el color lo
  # decide el grupo al que pertenece el estado —el mismo agrupamiento que
  # tenía la hoja—:
  #
  #   neutro   draft · pending · closed · archived
  #   acento   running · active · activating         → badge-primary
  #   ok       completed                             → badge-success
  #   warn     skipped                               → badge-warning
  #
  # Cubre dos enums a la vez: ChallengeStep::STATUSES y Challenge::STATUSES.
  # Cada valor va ENTERO y literal: Tailwind escanea texto, y una clase armada
  # con interpolación no llega a la hoja.
  #
  # `badge-sm` porque los chips tenían 11px de letra; `font-semibold` y
  # `whitespace-nowrap` porque los tenían, y el `badge` no.
  CHIP_DE_ESTADO = {
    "pending" => "badge badge-soft badge-sm font-semibold whitespace-nowrap",
    "draft" => "badge badge-soft badge-sm font-semibold whitespace-nowrap",
    "closed" => "badge badge-soft badge-sm font-semibold whitespace-nowrap",
    "archived" => "badge badge-soft badge-sm font-semibold whitespace-nowrap",
    "active" => "badge badge-soft badge-primary badge-sm font-semibold whitespace-nowrap",
    "activating" => "badge badge-soft badge-primary badge-sm font-semibold whitespace-nowrap",
    "running" => "badge badge-soft badge-primary badge-sm font-semibold whitespace-nowrap",
    "completed" => "badge badge-soft badge-success badge-sm font-semibold whitespace-nowrap",
    "skipped" => "badge badge-soft badge-warning badge-sm font-semibold whitespace-nowrap"
  }.freeze

  # `badge-xs` porque tenían 10px de letra; `ml-1.5` es el `margin-left: 6px`
  # que los separaba del nombre del criterio.
  CHIP_DE_ORIGEN = {
    "manual" => "badge badge-soft badge-primary badge-xs font-semibold whitespace-nowrap ml-1.5",
    "automatic" => "badge badge-soft badge-success badge-xs font-semibold whitespace-nowrap ml-1.5",
    "ai" => "badge badge-soft badge-secondary badge-xs font-semibold whitespace-nowrap ml-1.5",
    "formula" => "badge badge-soft badge-warning badge-xs font-semibold whitespace-nowrap ml-1.5"
  }.freeze

  CLASE_DE_FLASH = {
    "notice" => "alert alert-soft alert-success",
    "alert" => "alert alert-soft alert-error"
  }.freeze

  # Las claves son FeedbackItem::KINDS tal cual las declara el modelo. Van en
  # mayúsculas y en negrita, como iban.
  CLASE_DE_FEEDBACK = {
    "suggestion" => "badge badge-soft badge-primary badge-xs font-bold uppercase",
    "question" => "badge badge-soft badge-warning badge-xs font-bold uppercase",
    "issue" => "badge badge-soft badge-error badge-xs font-bold uppercase"
  }.freeze

  # La marca de IA. Estaba escrita a mano en nueve vistas; como `badge` serían
  # cinco clases repetidas nueve veces, que es justo lo que «si aparece en más
  # de dos vistas es un componente» existe para evitar.
  CHIP_DE_IA = "badge badge-soft badge-secondary badge-xs font-bold tracking-wide"

  CLASE_DE_DIFF = {
    "added" => "diff-kind diff-kind--added",
    "removed" => "diff-kind diff-kind--removed",
    "changed" => "diff-kind diff-kind--changed"
  }.freeze

  # El paso a paso de configuración y el mapa compacto del flujo pintan el
  # MISMO conjunto de estados que los chips, con otra forma. Comparten la clave
  # y no el nombre de clase.
  CLASE_DE_PASO_DE_SETUP = {
    "pending" => "setup__step setup__step--pending",
    "active" => "setup__step setup__step--active",
    "completed" => "setup__step setup__step--completed",
    "skipped" => "setup__step setup__step--skipped",
    "blocked" => "setup__step setup__step--blocked",
    "done" => "setup__step setup__step--done",
    "current" => "setup__step setup__step--current",
    "outline" => "setup__step setup__step--outline"
  }.freeze

  # El mapa compacto del flujo. Mismos estados que los chips, otros colores:
  # cada nodo conserva lo que pintaba antes de ser `badge`.
  #
  #   pending · activating   neutro, con borde
  #   active                 acento, en negrita
  #   completed              ok
  #   skipped                neutro, borde punteado → border-dashed
  CLASE_DE_NODO_DE_FLUJO = {
    "pending" => "badge badge-soft badge-sm",
    "activating" => "badge badge-soft badge-sm",
    "active" => "badge badge-soft badge-primary badge-sm font-semibold",
    "completed" => "badge badge-soft badge-success badge-sm",
    "skipped" => "badge badge-soft badge-sm border-dashed"
  }.freeze

  # Las claves son StepEntry::STATUSES. El brief original traía "skipped"
  # —que no es un status de StepEntry— y no mapeaba "advanced" ni
  # "eliminated", que son justo los dos con color propio en la hoja
  # (`.result--advanced` verde, `.result--eliminated` rojo): sin ellos «cómo
  # le fue» perdía el borde de color que dice si la idea avanzó o no.
  CLASE_DE_RESULTADO = {
    "pending" => "result result--pending",
    "in_progress" => "result result--in_progress",
    "done" => "result result--done",
    "advanced" => "result result--advanced",
    "eliminated" => "result result--eliminated"
  }.freeze

  # Un estado desconocido no puede dejar el elemento sin ninguna clase: se cae
  # al neutro, que es visible y no miente.
  def chip_de_estado(estado) = CHIP_DE_ESTADO.fetch(estado.to_s, CHIP_DE_ESTADO.fetch("pending"))
  def chip_de_origen(source) = CHIP_DE_ORIGEN.fetch(source.to_s, CHIP_DE_ORIGEN.fetch("manual"))
  def clase_de_flash(tipo) = CLASE_DE_FLASH.fetch(tipo.to_s, CLASE_DE_FLASH.fetch("notice"))
  def clase_de_feedback(kind) = CLASE_DE_FEEDBACK.fetch(kind.to_s, CLASE_DE_FEEDBACK.fetch("suggestion"))
  def chip_de_ia = CHIP_DE_IA
  def clase_de_diff(kind) = CLASE_DE_DIFF.fetch(kind.to_s, CLASE_DE_DIFF.fetch("changed"))
  def clase_de_resultado(status) = CLASE_DE_RESULTADO.fetch(status.to_s, CLASE_DE_RESULTADO.fetch("pending"))
  def clase_de_nodo_de_flujo(estado) = CLASE_DE_NODO_DE_FLUJO.fetch(estado.to_s, CLASE_DE_NODO_DE_FLUJO.fetch("pending"))

  # `_setup_progress.html.haml` ya arma su clase como ARREGLO y le suma otras
  # condicionales. Este helper devuelve solo la de estado; el arreglo se
  # conserva tal como está.
  def clase_de_paso_de_setup(estado) = CLASE_DE_PASO_DE_SETUP.fetch(estado.to_s, CLASE_DE_PASO_DE_SETUP.fetch("pending"))

  # Los ternarios que estaban repartidos por las vistas, en un solo lugar.
  def chip_de_corrida_de_ia(run)
    return chip_de_estado("completed") if run.succeeded?
    return chip_de_estado("skipped") if run.failed?

    chip_de_estado("pending")
  end

  def chip_de_decision(decision)
    return chip_de_estado("completed") if decision.advance?
    return chip_de_estado("active") if decision.reinstate?

    chip_de_estado("skipped")
  end

  def chip_de_validez(valido) = chip_de_estado(valido ? "completed" : "skipped")
end
