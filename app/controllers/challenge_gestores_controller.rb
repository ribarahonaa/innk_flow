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

    # `redirect_back`: esto se configura desde el módulo de evolución, que es
    # donde un gestor tiene algo que hacer. Volver siempre a la ficha del
    # desafío sacaba de la pantalla en la que estabas trabajando.
    if asignacion.save
      volver notice: "#{asignacion.user.name} acompaña este desafío."
    else
      volver alert: asignacion.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @challenge, :update_pipeline?

    asignacion = @challenge.challenge_gestores.find(params[:id])

    # Sacarse a uno mismo deja afuera en el acto y sin vuelta: el Scope filtra
    # por esta tabla, así que después del redirect el desafío ya da 404 y sólo
    # un admin puede reasignar. Sacar a OTRO sigue permitido — es parte de
    # administrar el desafío. Quien administra la empresa no puede caer acá:
    # `user_must_be_gestor` impide que esté en la tabla.
    if asignacion.user_id == current_user.id
      return volver alert: "No podés dejar de acompañar un desafío vos mismo."
    end

    # Un gestor es elegible para evaluar por esta asignación y no por su rol,
    # así que sacarlo de acá lo deja tan fantasma como una baja de la empresa.
    # Qué se suelta y qué no vive una sola vez, en el servicio — y las dos
    # escrituras van juntas, por la misma razón que en `MembershipsController`.
    release = Flow::Assignments::Release.new(asignacion.user_id)
    ActiveRecord::Base.transaction do
      asignacion.destroy!
      release.unassign!
    end
    release.recompute!

    volver notice: "Ya no acompaña este desafío."
  end

  private

  def volver(**flash)
    redirect_back fallback_location: challenge_path(@challenge), **flash
  end

  def set_challenge = @challenge = policy_scope(Challenge).find_by!(slug: params[:challenge_id])
end
