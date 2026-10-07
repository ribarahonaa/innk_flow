# frozen_string_literal: true

# El autoguardado de lo que la mesa teclea en la sala: el ÚNICO escritor de
# `WorkshopDraft`.
#
# No publica nada. Una propuesta y una versión siguen naciendo donde nacían; esto
# sólo hace que el texto sobreviva a un refresh.
#
# Responde con códigos pelados y NUNCA con un redirect. Los otros dos POST de la
# sala redirigen con flash porque los dispara una persona apretando un botón;
# esto lo dispara un temporizador dos segundos después de la última tecla, y un
# `redirect_to` haría que el `fetch` siga la redirección y traiga la pantalla
# entera cada vez.
class WorkshopDraftsController < ApplicationController
  before_action :set_link

  def update
    authorize @workshop, :work?
    # Las mismas cuatro guardas que `WorkshopIdeasController` y
    # `WorkshopProposalsController`, en el mismo orden. Repetidas y no
    # reescritas: divergir es cómo se abrió la fuga que esos dos documentan
    # —`work?` da true por `administers_any?` SIN mesa—.
    return head :conflict unless @link.workable?

    group = @workshop.group_of(current_user)
    return head :forbidden unless group
    # La mesa de llegada no trabaja. Misma pregunta que los otros seis lugares.
    return head :forbidden if group.arrival?

    # Un PATCH sin la clave `payload` es un NO-OP. Con `fetch(:payload, {})` a
    # secas devolvería `{}` y pisaría el texto de la mesa con nada: pérdida
    # silenciosa de datos, y la puede causar el propio JS con un cuerpo mal
    # armado. No hay nada que guardar, así que no se guarda.
    return no_op unless params.key?(:payload)

    # La fase la decide la SALA y no el cliente: un `idea_id` mandado a una sala
    # de idear se ignora. Si se aceptara, el cliente crearía una fila con idea en
    # esa cara y escaparía al índice de unicidad pensado para ella.
    idea = @link.kind == "evolution" ? workable_idea : nil

    payload = payload_params
    # `?payload=x`: un escalar en vez de un hash. Es un cuerpo mal formado y
    # contesta un código, no revienta en `permit!`.
    return head :bad_request if payload.nil?
    # Si no sobrevive NINGUNA clave (por ejemplo, el JS manda el id del campo en
    # vez de su `key`) escribir `{}` pisaría el texto de la mesa con nada: el
    # mismo pisado que el no-op de arriba evita, entrando por la otra puerta.
    # Vaciar un campo a propósito manda la clave PRESENTE con valor vacío, que
    # sí pasa el filtro.
    return no_op if payload.empty?

    # El payload REEMPLAZA al guardado y la sala lo prellena entero, sin merge:
    # el cliente tiene que mandar el formulario COMPLETO en cada PATCH. Si manda
    # sólo lo tecleado, los demás campos vuelven en blanco y la propuesta
    # publica vacío lo que estaba escrito. No «optimizar» mandando menos.
    write!(group, idea, payload)
    head :no_content
  end

  private

  # 204 es correcto para «guardé» y para «no había nada que guardar»: no hay
  # cuerpo que devolver. Pero el cliente tiene que poder distinguirlos, o el sello
  # dice «Guardado ahora.» sobre un pedido que no escribió nada (por ejemplo, si
  # renombraron las claves del formulario con la sala abierta). Los códigos no se
  # tocan; la cabecera lo dice.
  def no_op
    response.headers["X-Draft-Saved"] = "0"
    head :no_content
  end

  def set_link
    @workshop = policy_scope(Workshop).find_by!(id: params[:workshop_id])
    @link = @workshop.workshop_challenges.find_by!(id: params[:sala_id])
  end

  # El mismo idioma que `WorkshopProposalsController`, y por la razón escrita
  # ahí: `policy_scope(Idea)` deja ver a quien participa sólo lo que creó o
  # comparte, y la mesa trabaja la idea de CUALQUIERA de sus integrantes. El 404
  # se conserva: una idea fuera del conjunto no se distingue de una inexistente,
  # así que no confirma que exista.
  def workable_idea
    @workshop.group_of(current_user)
             .workable_ideas(@link.challenge)
             .find_by!(id: params[:idea_id])
  end

  # Contra el formulario declarado: una clave que no es de un campo se descarta.
  # Los `file` quedan afuera —un borrador no guarda archivos, y un `<input
  # type=file>` no sobrevive una recarga en ningún navegador—.
  def payload_params
    step = @link.challenge.pipeline.ideation_step
    keys = step ? step.form_fields.reject { |f| f.field_type == "file" }.map(&:key) : []
    raw = params.require(:payload)
    raw.respond_to?(:permit!) ? raw.permit!.to_h.slice(*keys) : nil
  end

  # La carrera es real: dos personas de la mesa guardando a la vez no encuentran
  # fila, las dos insertan, y el índice parcial levanta `RecordNotUnique`. Se
  # reintenta una vez y ahí la fila ya existe. Un `upsert` sería una sentencia
  # sola, pero saltea las dos validaciones del modelo, que es justo lo que no se
  # quiere saltear.
  def write!(group, idea, payload, intento: 1)
    draft = group.workshop_drafts.find_or_initialize_by(
      workshop_challenge: @link, idea_id: idea&.id
    )
    # `based_on_version_id` es contra qué versión se tecleó, y la mesa empezó a
    # teclear UNA vez: se sella sólo al crear la fila. Reescribirlo en cada
    # autoguardado movería la base a la versión nueva y el aviso de base vieja
    # nunca dispararía. Al mandar, el borrador se borra y el próximo nace con la
    # versión de ese momento.
    draft.based_on_version_id = idea&.current_version_id if draft.new_record?
    draft.update!(payload: payload, updated_by: current_user)
  rescue ActiveRecord::RecordNotUnique
    raise if intento > 1

    write!(group, idea, payload, intento: 2)
  end
end
