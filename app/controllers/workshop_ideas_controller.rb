# frozen_string_literal: true

# Crear una idea desde la sala de un taller.
#
# ÚNICA diferencia con postular desde el desafío: la mesa entera queda como
# `idea_contributors` desde el minuto cero. Eso es lo que hace que «veo las
# ideas de mi mesa y no las de las otras» sea `IdeaPolicy::Scope` tal como
# está, sin una excepción nueva a la regla que este repo más audita.
class WorkshopIdeasController < ApplicationController
  before_action :set_link

  def create
    authorize @workshop, :work?
    return reject_room unless @link.workable? && @link.kind == "ideation"

    # Misma guarda que la sala de evolución, y por dos motivos a la vez.
    # `work?` es del TALLER y devuelve true por `administers_any?` sin mesa:
    # sin esto, quien administra un desafío del taller creaba una idea a su
    # nombre —sin pasar nunca por `IdeaPolicy#create?`, que al gestor se lo
    # prohíbe por conflicto de interés— y podía hacerlo en la sala de un
    # desafío ajeno, que por la ruta normal le da 404. Y el `&.` de más abajo
    # toleraba el `nil` creando una idea sin un solo contribuyente.
    group = group_of(current_user)
    return reject_without_group unless group

    result = nil
    ActiveRecord::Base.transaction do
      idea = @link.challenge.ideas.new(author: current_user, status: "draft", origin: "human")
      idea.save!
      group.members.each do |person|
        next if person.id == current_user.id

        idea.idea_contributors.create!(user: person)
      end
      result = Flow::Ideas::PublishVersion.new(
        idea, payload: payload_params, author: current_user,
              source_step: @link.challenge_step, files: file_params,
              change_note: "Creada en el taller «#{@workshop.name}»"
      ).call
      # Sin versión no hay borrador: no se deja una idea vacía colgada.
      raise ActiveRecord::Rollback unless result.ok?
    end

    if result.ok?
      redirect_to workshop_path(@workshop), notice: "Borrador creado en la sala."
    else
      redirect_to workshop_path(@workshop), alert: result.error_sentence
    end
  end

  private

  def set_link
    @workshop = policy_scope(Workshop).find_by!(id: params[:workshop_id])
    @link = @workshop.workshop_challenges.find_by!(id: params[:sala_id])
  end

  def group_of(user)
    @workshop.workshop_groups.joins(:workshop_group_members)
             .find_by(workshop_group_members: { user_id: user.id })
  end

  # Contra el formulario declarado: una clave que no es de un campo se descarta.
  def payload_params
    keys = @link.challenge_step.form_fields.map(&:key)
    params.fetch(:payload, {}).permit!.to_h.slice(*keys)
  end

  def file_params
    keys = @link.challenge_step.form_fields.select { |f| f.field_type == "file" }.map(&:key)
    return {} if keys.empty? || params[:files].blank?

    params[:files].to_unsafe_h.slice(*keys)
  end

  def reject_room
    redirect_to workshop_path(@workshop),
                alert: "Esta sala ya no admite trabajo: el desafío avanzó de fase."
  end

  def reject_without_group
    redirect_to workshop_path(@workshop),
                alert: "Sólo se crea un borrador desde una mesa: no estás en ninguna de este taller."
  end
end
