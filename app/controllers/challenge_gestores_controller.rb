# frozen_string_literal: true

# Asignar gestores a un desafío.
#
# Un gestor tiene membresía en la empresa pero NO ve sus desafíos: se lo asigna
# uno por uno. Es lo que permite que la misma persona acompañe a varias
# empresas sin que se le mezcle nada.
class ChallengeGestoresController < ApplicationController
  before_action :set_challenge

  def create
    authorize @challenge, :update_pipeline?

    asignacion = @challenge.challenge_gestores.new(user_id: params[:user_id])

    if asignacion.save
      redirect_to challenge_path(@challenge), notice: "#{asignacion.user.name} acompaña este desafío."
    else
      redirect_to challenge_path(@challenge), alert: asignacion.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @challenge, :update_pipeline?

    @challenge.challenge_gestores.find(params[:id]).destroy!
    redirect_to challenge_path(@challenge), notice: "Ya no acompaña este desafío."
  end

  private

  def set_challenge = @challenge = policy_scope(Challenge).find_by!(slug: params[:challenge_id])
end
