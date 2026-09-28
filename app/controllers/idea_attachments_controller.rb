# frozen_string_literal: true

# El adjunto de una idea, servido por la app.
#
# Antes iba por `rails_blob_path`, o sea por el controller de Active Storage,
# que verifica la firma del blob y nada más: sin sesión, sin membresía, sin
# Pundit y sin tenant, con una firma que no vence. Acá el adjunto hereda la
# visibilidad de SU idea, que es la misma regla que ya siguen los comentarios.
class IdeaAttachmentsController < ApplicationController
  before_action :set_idea

  def show
    authorize @idea, :show?

    # Dentro de las versiones de ESA idea, no por id en toda la empresa: si se
    # buscara global, una idea visible sería la llave del archivo de otra.
    attachment = IdeaAttachment.where(idea_version_id: @idea.versions.select(:id)).find(params[:id])

    send_attached_file(attachment.file)
  end

  private

  def set_idea
    @challenge = policy_scope(Challenge).find_by!(slug: params[:challenge_id])
    # Por `policy_scope`: a quien participa, una idea ajena le daba 403 y un id
    # inexistente 404, y esa diferencia confirma que existe.
    @idea = policy_scope(@challenge.ideas).find(params[:idea_id])
  end
end
