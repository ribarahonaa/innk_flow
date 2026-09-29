# frozen_string_literal: true

# El taller propone; el autor publica. Aceptar es de QUIEN ES AUTOR (ver
# `WorkshopProposalPolicy`), y el paso va siempre, incluso si el autor está en
# la mesa.
#
# Y no se edita al aceptar. Precedente: `Tasks::EvaluateIdea#editable?` se
# borró porque aceptar admitiendo un payload editado era una capacidad del
# dominio sin interfaz.
class IdeaWorkshopProposalsController < ApplicationController
  before_action :set_proposal

  def accept
    authorize @proposal
    return expired unless @proposal.actionable?

    result = nil
    ActiveRecord::Base.transaction do
      result = Flow::Ideas::PublishVersion.new(
        @idea, payload: @proposal.payload, author: current_user, actor_type: "workshop",
               source_step: @proposal.challenge_step,
               change_note: "Propuesta de la mesa «#{@proposal.workshop_group.name}»"
      ).call
      # Sin versión publicada no hay nada que aceptar.
      raise ActiveRecord::Rollback unless result.ok?

      @proposal.workshop_group.members.each do |person|
        next if person.id == @idea.author_id

        @idea.idea_contributors.find_or_create_by!(user: person)
      end
      @proposal.update!(status: "accepted", reviewed_by: current_user, reviewed_at: Time.current)
    end

    if result.ok?
      redirect_to challenge_idea_path(@idea.challenge, @idea), notice: "Propuesta aplicada."
    else
      redirect_to challenge_idea_path(@idea.challenge, @idea), alert: result.error_sentence
    end
  end

  # No exige `actionable?`: descartar una propuesta vencida no escribe nada en
  # ninguna conversación.
  def reject
    authorize @proposal
    @proposal.update!(status: "rejected", reviewed_by: current_user, reviewed_at: Time.current)
    redirect_to challenge_idea_path(@idea.challenge, @idea), notice: "Propuesta descartada."
  end

  private

  def set_proposal
    @idea = policy_scope(Idea).find_by!(id: params[:idea_id])
    @proposal = policy_scope(WorkshopProposal).find_by!(id: params[:id], idea_id: @idea.id)
  end

  def expired
    redirect_to challenge_idea_path(@idea.challenge, @idea),
                alert: "La ronda de evolución de esta propuesta ya cerró."
  end
end
