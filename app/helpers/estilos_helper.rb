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
  # Cubre dos enums a la vez: ChallengeStep::STATUSES (pending/activating/
  # active/completed/skipped) y Challenge::STATUSES (draft/running/closed/
  # archived) — la hoja ya los agrupa con el mismo color (`.status-chip--
  # draft, .status-chip--pending { ... }`), así que comparten helper. El
  # brief original no traía draft/running/closed: un desafío "running" caía
  # al default "pending" y perdía el celeste que tiene "en curso" en la ficha
  # del desafío.
  CHIP_DE_ESTADO = {
    "pending" => "status-chip status-chip--pending",
    "draft" => "status-chip status-chip--draft",
    "active" => "status-chip status-chip--active",
    "activating" => "status-chip status-chip--activating",
    "running" => "status-chip status-chip--running",
    "completed" => "status-chip status-chip--completed",
    "skipped" => "status-chip status-chip--skipped",
    "closed" => "status-chip status-chip--closed",
    "archived" => "status-chip status-chip--archived"
  }.freeze

  CHIP_DE_ORIGEN = {
    "manual" => "source-chip source-chip--manual",
    "automatic" => "source-chip source-chip--automatic",
    "ai" => "source-chip source-chip--ai",
    "formula" => "source-chip source-chip--formula"
  }.freeze

  CLASE_DE_FLASH = {
    "notice" => "alert alert-soft alert-success",
    "alert" => "alert alert-soft alert-error"
  }.freeze

  # Las claves son FeedbackItem::KINDS tal cual las declara el modelo
  # (suggestion/question/issue). El brief original traía "comment" y "risk",
  # que no son valores del dominio, y no mapeaba "issue" —el real— que caía
  # al default y perdía el color rojo de `.feedback-kind--issue` en la hoja.
  CLASE_DE_FEEDBACK = {
    "suggestion" => "feedback-kind feedback-kind--suggestion",
    "question" => "feedback-kind feedback-kind--question",
    "issue" => "feedback-kind feedback-kind--issue"
  }.freeze

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

  CLASE_DE_NODO_DE_FLUJO = {
    "pending" => "flow-strip__node flow-strip__node--pending",
    "active" => "flow-strip__node flow-strip__node--active",
    "activating" => "flow-strip__node flow-strip__node--activating",
    "completed" => "flow-strip__node flow-strip__node--completed",
    "skipped" => "flow-strip__node flow-strip__node--skipped"
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
