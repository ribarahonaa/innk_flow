# frozen_string_literal: true

# Los criterios del desafío, módulo por módulo.
#
# El paso 4 del recorrido llevaba directo al primer módulo sin criterios: no se
# veía cuántos módulos puntúan, cuáles ya estaban resueltos ni en cuál de todos
# estabas parado. Al volver atrás aterrizabas en otro distinto, porque «el
# primero sin resolver» había cambiado.
class ChallengeCriteriaController < ApplicationController
  before_action :set_challenge

  def show
    authorize @challenge, :builder?
    @scorers = @challenge.pipeline.steps.select { |s| s.evaluation? || s.selection? }
  end

  private

  def set_challenge = @challenge = Challenge.find_by!(slug: params[:challenge_id])
end
