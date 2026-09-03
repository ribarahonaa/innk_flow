# frozen_string_literal: true

# Lo que van a ver las personas, antes de arrancar el desafío.
#
# Hasta acá el dueño configuraba a ciegas: el formulario de postulación y la
# ficha de evaluación recién se veían con el desafío ya en curso, cuando la
# ventana para cambiarlos estaba cerrada.
#
# La pantalla renderiza las vistas REALES, no una maqueta: los mismos parciales
# que usan `ideas/new` y `assessments/new`. Un preview que reimplementa la
# pantalla se desincroniza y termina mostrando algo que no existe.
class PreviewsController < ApplicationController
  before_action :set_challenge

  def show
    authorize @challenge, :builder?
    @pipeline = @challenge.pipeline
    @report = @pipeline.validate
  end

  private

  def set_challenge
    @challenge = policy_scope(Challenge).find_by!(slug: params[:challenge_id])
  end
end
