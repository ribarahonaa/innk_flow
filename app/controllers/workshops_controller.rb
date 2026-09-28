# frozen_string_literal: true

class WorkshopsController < ApplicationController
  before_action :set_workshop, only: %i[show update destroy open close]

  def index
    @workshops = policy_scope(Workshop).order(scheduled_at: :desc, created_at: :desc)
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
    @links = @workshop.workshop_challenges.includes(:challenge, :challenge_step)
    @groups = @workshop.workshop_groups.includes(:members)
    @my_group = @workshop.workshop_groups.joins(:workshop_group_members)
                         .find_by(workshop_group_members: { user_id: current_user.id })
  end

  def open
    authorize @workshop, :update?
    result = Flow::Workshops::Open.new(@workshop).call

    if result.ok?
      notice_message = "Taller abierto."
      notice_message += " #{Flow::Texto.contar(result.rejected.size, 'desafío')} quedaron afuera." if result.rejected.any?
      redirect_to workshop_path(@workshop), notice: notice_message
    else
      redirect_to workshop_path(@workshop), alert: result.errors.to_sentence
    end
  end

  def close
    authorize @workshop, :update?
    Flow::Workshops::Close.new(@workshop).call
    redirect_to workshop_path(@workshop), notice: "Taller cerrado."
  end

  def update
    authorize @workshop, :update?
    # Sumar un desafío se pregunta por el DESAFÍO, no por el taller.
    Array(params[:challenge_ids]).each do |id|
      challenge = policy_scope(Challenge).find_by(id: id)
      next if challenge.nil? || !policy(@workshop).add_challenge?(challenge)

      @workshop.workshop_challenges.find_or_create_by!(challenge: challenge)
    end
    redirect_to workshop_path(@workshop), notice: "Taller actualizado."
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
end
