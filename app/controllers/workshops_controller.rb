# frozen_string_literal: true

class WorkshopsController < ApplicationController
  before_action :set_workshop, only: %i[show update destroy open close remove_challenge]

  def index
    # Postgres pone NULL primero en DESC: sin `nulls_last` los talleres sin
    # fecha quedaban arriba de los programados.
    @workshops = policy_scope(Workshop).order(Workshop.arel_table[:scheduled_at].desc.nulls_last, created_at: :desc)
  end

  def new
    @workshop = Workshop.new
    authorize @workshop, :create?
    @challenges = policy_scope(Challenge)
  end

  def create
    @workshop = Workshop.new(workshop_params.merge(created_by: current_user))
    authorize @workshop, :create?

    if @workshop.save
      redirect_to workshop_path(@workshop), notice: "Taller creado."
    else
      @challenges = policy_scope(Challenge)
      flash.now[:alert] = @workshop.errors.full_messages.to_sentence
      render :new, status: :unprocessable_content
    end
  end

  def show
    authorize @workshop, :show?
    # El cierre del vínculo es perezoso: nada se engancha en `advance!`, y
    # entrar a la sala es lo que hace que el taller se entere de que el desafío
    # avanzó. Va ANTES de leer `@links`, para que la pantalla vea lo cerrado.
    Flow::Workshops::MaterializeClosures.new(@workshop).call
    @links = @workshop.workshop_challenges.includes(:challenge, :challenge_step)
    @groups = @workshop.workshop_groups.includes(:members)
    @my_group = @workshop.workshop_groups.joins(:workshop_group_members)
                         .find_by(workshop_group_members: { user_id: current_user.id })
  end

  def open
    authorize @workshop, :update?
    result = Flow::Workshops::Open.new(@workshop).call

    if result.ok?
      redirect_to workshop_path(@workshop), notice: opened_notice(result.rejected.size)
    else
      redirect_to workshop_path(@workshop), alert: result.errors.to_sentence
    end
  end

  def close
    authorize @workshop, :update?
    result = Flow::Workshops::Close.new(@workshop).call

    if result.ok?
      redirect_to workshop_path(@workshop), notice: "Taller cerrado."
    else
      redirect_to workshop_path(@workshop), alert: result.errors.to_sentence
    end
  end

  def update
    authorize @workshop, :update?
    # Sumar y sacar desafíos es de un taller en BORRADOR. Con el taller ya
    # abierto el vínculo nace con `challenge_step_id` en nil —`Open` ya corrió
    # y es el único que lo resuelve—, así que su `kind` queda en nil, no se
    # dibuja en ninguna cara de la sala y aparece en el armado sin motivo:
    # basura invisible.
    return reject_not_draft unless @workshop.draft?

    # Sumar un desafío se pregunta por el DESAFÍO, no por el taller.
    ignored = 0
    Array(params[:challenge_ids]).each do |id|
      challenge = policy_scope(Challenge).find_by(id: id)
      if challenge.nil? || !policy(@workshop).add_challenge?(challenge)
        ignored += 1
        next
      end

      @workshop.workshop_challenges.find_or_create_by!(challenge: challenge)
    end
    redirect_to workshop_path(@workshop), notice: updated_notice(ignored)
  end

  # Sacar un desafío del taller. Sólo en borrador: una vez abierto el vínculo
  # ya resolvió su módulo y puede tener trabajo colgando, y el ciclo de vida
  # del taller pone «sumar y sacar desafíos» en `draft` y en ningún otro lado.
  def remove_challenge
    authorize @workshop, :update?
    return reject_not_draft unless @workshop.draft?

    @workshop.workshop_challenges.find_by!(id: params[:workshop_challenge_id]).destroy!
    redirect_to workshop_path(@workshop), notice: "Desafío sacado del taller."
  end

  def destroy
    authorize @workshop, :destroy?
    @workshop.destroy!
    redirect_to workshops_path, notice: "Taller eliminado."
  end

  private

  # `policy_scope(...).find_by!` y no `Workshop.find_by!`: así lo que no se ve
  # da 404 y no 403, que sería un oráculo de existencia.
  def set_workshop = @workshop = policy_scope(Workshop).find_by!(id: params[:id])

  def workshop_params = params.require(:workshop).permit(:name, :mode, :scheduled_at)

  # El verbo concuerda con el número igual que el sustantivo, y `contar` sólo
  # acuerda el sustantivo: acá eso daba «1 desafío quedaron afuera». La regla
  # vive en `Flow::Texto.agree`, que es la misma que usa `faltan`.
  def opened_notice(rejected)
    return "Taller abierto." if rejected.zero?

    "Taller abierto. #{Flow::Texto.contar(rejected, 'desafío')} " \
      "#{Flow::Texto.agree(rejected, 'quedó', 'quedaron')} afuera."
  end

  def reject_not_draft
    redirect_to workshop_path(@workshop),
                alert: "Los desafíos del taller se suman y se sacan mientras es un borrador."
  end

  # Un acuse de éxito por algo que no pasó es el mismo control fantasma que
  # esta rama persigue: un desafío que el gestor no administra se saltaba en
  # silencio y la pantalla decía «Taller actualizado.» igual.
  def updated_notice(ignored)
    return "Taller actualizado." if ignored.zero?

    frase = Flow::Texto.agree(ignored, "no se sumó: no lo administrás",
                              "no se sumaron: no los administrás")
    "Taller actualizado. #{Flow::Texto.contar(ignored, 'desafío')} #{frase}."
  end
end
