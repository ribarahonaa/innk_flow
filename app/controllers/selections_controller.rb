# frozen_string_literal: true

# Confirmar el corte de un módulo de selección, y repescar.
class SelectionsController < ApplicationController
  before_action :set_context

  def update
    authorize @step, :advance?

    # Por `policy_scope` y no por los ids crudos, igual que las dos acciones de
    # abajo: es la regla del repo para todo lo que toca una idea, y acá además
    # deja afuera lo que no es una idea de este desafío. `decide!` ya ignoraba
    # esos ids —itera `step_entries`—, pero eso lo protegía de rebote: el
    # filtro tiene que estar en la puerta.
    pedidos = Array(params[:advancing_idea_ids]).reject(&:blank?)
    advancing = policy_scope(@challenge.ideas).where(id: pedidos).pluck(:id)

    avanzan = @step.handler.decide!(advancing, decided_by: current_user, reason: params[:reason])

    redirect_to challenge_step_path(@challenge, @step), notice: aviso_del_corte(avanzan.size)
  end

  # Un filtro de sí/no resuelto por una persona.
  def verdict
    authorize @step, :advance?
    idea = policy_scope(@challenge.ideas).find(params[:idea_id])

    @step.handler.record_verdict!(
      idea: idea,
      criterion_key: params[:criterion_key],
      passed: params[:passed].to_s == "true",
      decided_by: current_user,
      note: params[:note].presence
    )

    redirect_to challenge_step_path(@challenge, @step),
                notice: "Veredicto registrado para «#{idea.title.truncate(40)}»."
  end

  def reinstate
    authorize @step, :advance?
    idea = policy_scope(@challenge.ideas).find(params[:idea_id])

    @step.handler.reinstate!(idea, decided_by: current_user, reason: params[:reason])

    redirect_to challenge_step_path(@challenge, @step),
                notice: "«#{idea.title}» vuelve al flujo."
  end

  private

  # Cuenta lo que AVANZÓ, no lo que llegó en el pedido: con ids inventados el
  # aviso los contaba igual, porque el `size` era el de los params.
  #
  # Y el verbo concuerda. `Flow::Texto.contar` acuerda el sustantivo y con eso
  # no alcanza: la frase que lo envuelve trae su propio verbo, y quien la
  # escribe lo deja en plural porque está pensando en el caso de varios —es lo
  # que documenta `Flow::Texto.faltan` («Faltan 1 idea por testear») y lo que
  # `WorkshopsController` ya tuvo que corregir dos veces—.
  def aviso_del_corte(cuantas)
    verbo = cuantas == 1 ? "avanza" : "avanzan"
    "Corte confirmado: #{verbo} #{Flow::Texto.contar(cuantas, "idea")}."
  end

  def set_context
    @challenge = policy_scope(Challenge).find_by!(slug: params[:challenge_id])
    @step = @challenge.steps.find(params[:step_id])
  end
end
