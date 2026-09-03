# frozen_string_literal: true

# Quiénes más participaron de una idea, además de quien la creó.
#
# La tabla y el criterio automático `contributors_count` existían desde el
# principio; no había dónde cargar el dato, así que "participan al menos N
# personas" era un filtro que nadie podía pasar.
class IdeaContributorsController < ApplicationController
  before_action :set_idea

  def create
    authorize @idea, :manage_contributors?

    contributor = @idea.idea_contributors.new(user_id: params[:user_id], role: params[:role])

    if contributor.save
      redirect_to challenge_idea_path(@challenge, @idea),
                  notice: "#{contributor.user.name} suma a la idea."
    else
      redirect_to challenge_idea_path(@challenge, @idea),
                  alert: contributor.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @idea, :manage_contributors?

    contributor = @idea.idea_contributors.find(params[:id])
    contributor.destroy!

    redirect_to challenge_idea_path(@challenge, @idea), notice: "Quitado de la idea."
  end

  private

  def set_idea
    @challenge = policy_scope(Challenge).find_by!(slug: params[:challenge_id])
    @idea = @challenge.ideas.find(params[:idea_id])
  end
end
