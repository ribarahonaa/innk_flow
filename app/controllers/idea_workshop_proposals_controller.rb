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
    return resolved unless @proposal.pending?
    return expired unless @proposal.actionable?

    result = nil
    already_resolved = false
    # El `perform_later` del vector va FUERA del `with_lock`: adentro, un
    # worker que tome el job antes del commit no encuentra la versión y
    # `EmbedVersion` devuelve false en silencio, sin excepción ni reintento.
    publish = nil
    # `with_lock` relee la propuesta bajo lock: dos aceptaciones concurrentes
    # (doble clic, pestaña vieja) no publican dos versiones.
    @proposal.with_lock do
      # Ya leída bajo lock: si otra request la resolvió, no se publica nada.
      if !@proposal.pending?
        already_resolved = true
        raise ActiveRecord::Rollback
      end

      publish = Flow::Ideas::PublishVersion.new(
        @idea, payload: @proposal.payload, author: current_user, actor_type: "workshop",
               source_step: @proposal.challenge_step,
               change_note: "Propuesta de la mesa «#{@proposal.workshop_group.name}»",
               enqueue_embedding: false
      )
      result = publish.call
      # Sin versión publicada no hay nada que aceptar.
      raise ActiveRecord::Rollback unless result.ok?

      @proposal.workshop_group.members.each do |person|
        next if person.id == @idea.author_id

        @idea.idea_contributors.find_or_create_by!(user: person)
      end
      @proposal.update!(status: "accepted", reviewed_by: current_user, reviewed_at: Time.current)
    end

    publish.enqueue_embedding! if result&.ok?

    if already_resolved
      resolved
    elsif result.ok?
      redirect_to challenge_idea_path(@idea.challenge, @idea), notice: "Propuesta aplicada."
    else
      redirect_to challenge_idea_path(@idea.challenge, @idea), alert: result.error_sentence
    end
  end

  # No exige `actionable?`: descartar una propuesta vencida no escribe nada en
  # ninguna conversación. Pero sí `pending?`: descartar una ya aceptada dejaría
  # el registro contradiciendo el historial, con su versión aún publicada.
  def reject
    authorize @proposal
    outcome = @proposal.with_lock do
      next :resolved unless @proposal.pending?

      @proposal.update!(status: "rejected", reviewed_by: current_user, reviewed_at: Time.current)
      :rejected
    end
    return resolved if outcome == :resolved

    redirect_to challenge_idea_path(@idea.challenge, @idea), notice: "Propuesta descartada."
  end

  private

  def set_proposal
    @idea = policy_scope(Idea).find_by!(id: params[:idea_id])
    @proposal = policy_scope(WorkshopProposal).find_by!(id: params[:id], idea_id: @idea.id)
  end

  def resolved
    redirect_to challenge_idea_path(@idea.challenge, @idea),
                alert: "Esta propuesta ya fue resuelta."
  end

  def expired
    redirect_to challenge_idea_path(@idea.challenge, @idea),
                alert: "La ronda de evolución de esta propuesta ya cerró."
  end
end
