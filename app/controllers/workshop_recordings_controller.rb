# frozen_string_literal: true

# El audio de la conversación de una mesa: el ÚNICO escritor de
# `WorkshopRecording`.
#
# Contesta códigos y JSON, nunca un redirect: lo dispara un `fetch` del JS al
# parar de grabar, igual que el autoguardado, y un `redirect_to` haría que el
# `fetch` siga la redirección y traiga la pantalla entera.
class WorkshopRecordingsController < ApplicationController
  # Tipos que `MediaRecorder` puede producir. Medido: Chromium elige
  # `audio/webm;codecs=opus`, y Safari da `audio/mp4`. El parámetro `codecs`
  # viaja en el Content-Type, así que se compara el tipo base.
  AUDIO_TYPES = %w[audio/webm audio/ogg audio/mp4 audio/wav audio/mpeg].freeze

  include ActsOnAGroup

  before_action :set_link

  def create
    authorize @workshop, :work?
    # Las mismas guardas que `WorkshopDraftsController` y en el mismo orden.
    # Divergir es cómo se abrió la fuga que esos documentan: `work?` da true por
    # `administers_any?` SIN mesa.
    return head :conflict unless @link.workable?

    group = acting_group(@workshop, @link)
    return head :forbidden unless group
    # La mesa de llegada no trabaja. Misma pregunta que en los demás lugares que
    # no dejan trabajar desde ella; cuántos son lo dice CLAUDE.md y no este
    # comentario, que con un número se desactualiza en silencio.
    return head :forbidden if group.arrival?

    archivo = params[:file]
    # Sin esto, `attach(nil)` levanta un 500 y la mesa ve una pantalla de error
    # en vez de un motivo. El caso lo causa el propio JS con un cuerpo mal
    # armado.
    return head :bad_request if archivo.blank?
    return head :unsupported_media_type unless audio?(archivo)

    grabacion = crear!(group, archivo)
    Flow::Workshops::TranscribeRecordingJob.perform_later(Current.company.id, grabacion.id)
    render json: { id: grabacion.id }, status: :created
  end

  def show
    authorize @workshop, :work?
    # DENTRO de lo alcanzable, que cuelga de la sala (ya buscada por
    # `policy_scope`) y de la mesa de quien pide: una grabación de otra empresa,
    # de otra sala o de otra mesa no se encuentra, así que da 404 y no 403. Un
    # 403 sería un oráculo de existencia.
    grabacion = alcanzables.find_by!(id: params[:id])

    # Levanta `RecordNotFound` si no hay archivo adjunto, que es el caso real de
    # una fila creada antes de adjuntarle nada.
    send_attached_file(grabacion.file)
  end

  private

  def set_link
    @workshop = policy_scope(Workshop).find_by!(id: params[:workshop_id])
    @link = @workshop.workshop_challenges.find_by!(id: params[:sala_id])
  end

  # La grabación es de la MESA, igual que el borrador: la oye quien está
  # sentado en esa mesa. Quien administra el taller las oye todas, porque es
  # quien lo lleva. Va en la búsqueda y no en un `authorize` aparte: así lo
  # inalcanzable da 404. Quien pasa `work?` sin administrar siempre está
  # sentado (`work?` sólo da true sin mesa por `administers_any?`), pero se
  # cubre igual el caso sin mesa.
  def alcanzables
    return @link.workshop_recordings if policy(@link.challenge).enter_any_group?

    grupo = @workshop.group_of(current_user)
    return WorkshopRecording.none if grupo.nil?

    @link.workshop_recordings.where(workshop_group: grupo)
  end

  def audio?(archivo)
    tipo = archivo.content_type.to_s.split(";").first.to_s.strip
    AUDIO_TYPES.include?(tipo)
  end

  def crear!(group, archivo)
    # La idea es CONTEXTO: qué tenía la sala elegida al grabar. En idear no hay
    # ninguna, y la fase la decide la SALA y no el cliente —un `idea_id` mandado
    # a idear se ignora—, igual que en el borrador.
    idea = @link.kind == "evolution" ? workable_idea(group) : nil

    # Los dos en UNA transacción. `attach` puede levantar —el servicio de
    # Active Storage, una validación, el disco— y afuera de la transacción eso
    # dejaba una fila `pending` sin archivo y sin job: la tarjeta decía «en
    # cola» para siempre, y «en cola» existe justamente para distinguir «subida
    # y sin job todavía» de «falló». O entra la fila con su audio, o no entra
    # ninguna de las dos cosas.
    ActiveRecord::Base.transaction do
      grabacion = group.workshop_recordings.create!(
        workshop_challenge: @link, idea: idea, recorded_by: current_user, status: "pending"
      )
      grabacion.file.attach(archivo)
      grabacion
    end
  end

  # El mismo idioma que `WorkshopDraftsController` y `WorkshopProposalsController`:
  # `policy_scope(Idea)` deja ver a quien participa sólo lo que creó o comparte,
  # y la mesa trabaja la idea de CUALQUIERA de sus integrantes.
  def workable_idea(group)
    return nil if params[:idea_id].blank?

    # La idea es contexto opcional, pero un id que no se resuelve no se
    # descarta en silencio: la grabación perdería el contexto sin avisar.
    group.workable_ideas(@link.challenge).find_by!(id: params[:idea_id])
  end
end
