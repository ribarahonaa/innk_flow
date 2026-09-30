# frozen_string_literal: true

# Mantenedor de criterios de la empresa.
class CriteriaSetsController < ApplicationController
  before_action :set_criteria_set, only: %i[show edit promote]

  def index
    @sets = policy_scope(CriteriaSet).library.current.includes(:criteria).order(:name)
  end

  # El set nace VACÍO. Antes traía dos criterios ya puestos, que la mitad de
  # las veces había que borrar: el editor ofrece plantillas de arranque, que es
  # lo mismo pero elegido.
  def new
    @set = CriteriaSet.new(name: "")
    authorize @set
    @props = CriteriaSetPresenter.new(@set, membership: current_membership).as_json
  end

  # NINGUNA vista la linkea, y no es huérfana. Se fichó como tal; son tres cosas
  # distintas y conviene tenerlas juntas antes de volver a proponer borrarla:
  #
  #   · Es la lectura de SOLO LECTURA de un set. Los dos links que existen
  #     —«Ver el set» en `steps/_referencia_evaluacion` y «Editar el set» en
  #     `steps/_como_se_decide`— van a `edit` y están detrás de
  #     `policy(set).edit?`. Sobre un set de biblioteca eso es `manager?`, así
  #     que a un gestor se le esconden los dos y ésta es su única vía.
  #   · Es la superficie con la que `spec/requests/gestor_spec.rb` prueba que la
  #     fuga de lectura está cerrada: un gestor abría por id —200, con los
  #     criterios adentro— el set `inline` de un desafío que no le asignaron.
  #     Lo cerró `CriteriaSetPolicy::Scope`; borrar esta acción deja esa regla
  #     sin ruta propia donde probarse.
  #   · El precedente de `CLAUDE.md` que manda borrar una capacidad sin interfaz
  #     (`Tasks::EvaluateIdea#editable?`) es sobre una capacidad de ESCRITURA sin
  #     control. Ésta no escribe nada.
  def show
    authorize @set
  end

  def edit
    authorize @set
    @props = CriteriaSetPresenter.new(@set, membership: current_membership).as_json
  end

  def promote
    authorize @set, :create?
    copy = @set.promote_to_library!
    redirect_to edit_criteria_set_path(copy), notice: "Copiado a la biblioteca."
  end

  private

  # Por `policy_scope`: un set `inline` de un desafío que no ves no existe.
  def set_criteria_set
    @set = policy_scope(CriteriaSet).find(params[:id])
  end
end
