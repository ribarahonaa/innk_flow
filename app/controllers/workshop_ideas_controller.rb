# frozen_string_literal: true

# Crear una idea desde la sala de un taller.
#
# ÚNICA diferencia con postular desde el desafío: la mesa entera queda como
# `idea_contributors` desde el minuto cero. Eso es lo que hace que «veo las
# ideas de mi mesa y no las de las otras» sea `IdeaPolicy::Scope` tal como
# está, sin una excepción nueva a la regla que este repo más audita.
class WorkshopIdeasController < ApplicationController
  include ActsOnAGroup

  before_action :set_link

  def create
    authorize @workshop, :work?
    return reject_room unless @link.workable? && @link.kind == "ideation"

    # Misma guarda que la sala de evolución, y por dos motivos a la vez.
    # `work?` es del TALLER y devuelve true por `administers_any?` sin mesa:
    # sin esto, quien administra un desafío del taller creaba una idea a su
    # nombre —sin pasar nunca por `IdeaPolicy#create?`, que al gestor se lo
    # prohíbe por conflicto de interés— y podía hacerlo en la sala de un
    # desafío ajeno, que por la ruta normal le da 404. Y el `&.` que había al
    # sembrar los contribuyentes toleraba el `nil`: la idea nacía sin uno solo.
    group = acting_group(@workshop, @link)
    return reject_without_group unless group
    return reject_arrival if group.arrival?

    # Estar en la mesa no alcanza: firmar una idea es de `IdeaPolicy#create?`,
    # que al gestor se lo niega por conflicto de interés. Puede acompañar la
    # mesa, no proponer la suya. Acá el 403 es correcto: ya ve el taller.
    idea = @link.challenge.ideas.new(author: current_user, status: "draft", origin: "human")
    authorize idea, :create?

    result = nil
    # El `perform_later` del vector va FUERA de esta transacción: adentro, un
    # worker que tome el job antes del commit no encuentra la versión y
    # `EmbedVersion` devuelve false en silencio, sin excepción ni reintento.
    publish = nil
    ActiveRecord::Base.transaction do
      idea.save!
      group.members.each do |person|
        next if person.id == current_user.id

        idea.idea_contributors.create!(user: person)
      end
      publish = Flow::Ideas::PublishVersion.new(
        idea, payload: payload_params, author: current_user,
              source_step: @link.challenge_step, files: file_params,
              change_note: "Creada en el taller «#{@workshop.name}»",
              enqueue_embedding: false
      )
      result = publish.call
      # Sin versión no hay borrador: no se deja una idea vacía colgada.
      raise ActiveRecord::Rollback unless result.ok?

      # Mandado el borrador, el borrador se va. Si sigue prellenando el
      # formulario, la mesa lo manda de nuevo. Va DENTRO de esta transacción: si
      # la publicación falla y hace rollback, el texto no puede haberse ido.
      group.workshop_drafts.where(workshop_challenge: @link, idea_id: nil).delete_all
    end

    publish.enqueue_embedding! if result.ok?

    if result.ok?
      # A la SALA y no al taller: la sala es donde se ve lo que la mesa acaba
      # de crear. Volviendo al taller el borrador no aparecía en ninguna
      # pantalla, así que la mesa no sabía que ya lo había creado y lo creaba
      # de nuevo.
      redirect_to workshop_sala_path(@workshop, @link), notice: "Borrador creado en la sala."
    else
      redirect_to workshop_sala_path(@workshop, @link), alert: result.error_sentence
    end
  end

  private

  def set_link
    @workshop = policy_scope(Workshop).find_by!(id: params[:workshop_id])
    @link = @workshop.workshop_challenges.find_by!(id: params[:sala_id])
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
    redirect_to workshop_sala_path(@workshop, @link),
                alert: "Esta sala ya no admite trabajo: el desafío avanzó de fase."
  end

  def reject_without_group
    redirect_to workshop_sala_path(@workshop, @link),
                alert: "Sólo se crea un borrador desde una mesa: no estás en ninguna de este taller."
  end

  # La mesa de llegada no trabaja. El rechazo es explícito y con su mensaje: un
  # 404 pelado en una sala que debería decir por qué no se puede trabajar es el
  # control que no responde.
  #
  # El texto es NEUTRO («esa mesa» y no «tu mesa») porque quien administra puede
  # nombrar la llegada y llegar acá sin estar sentado en ella: un «tu» ahí
  # miente. Las vistas resuelven lo mismo con `de_la_mesa`, que dice el nombre;
  # acá sería un condicional por un redirect, y neutro no puede mentir.
  def reject_arrival
    redirect_to workshop_sala_path(@workshop, @link),
                alert: "Esa mesa todavía no se armó: esperá el reparto para trabajar."
  end
end
