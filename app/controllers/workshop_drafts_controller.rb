# frozen_string_literal: true

# El autoguardado de lo que la mesa teclea en la sala: el ÚNICO escritor de
# `WorkshopDraft`.
#
# No publica nada. Una propuesta y una versión siguen naciendo donde nacían; esto
# sólo hace que el texto sobreviva a un refresh.
#
# Responde con códigos pelados y NUNCA con un redirect. Los otros dos POST de la
# sala redirigen con flash porque los dispara una persona apretando un botón;
# esto lo dispara un temporizador cada dos segundos, y un `redirect_to` haría que
# el `fetch` siga la redirección y traiga la pantalla entera cada vez.
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
    return head :no_content unless params.key?(:payload)

    # La fase la decide la SALA y no el cliente: un `idea_id` mandado a una sala
    # de idear se ignora. Si se aceptara, el cliente crearía una fila con idea en
    # esa cara y escaparía al índice de unicidad pensado para ella.
    idea = @link.kind == "evolution" ? workable_idea : nil

    write!(group, idea)
    head :no_content
  end

  private

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
    params.require(:payload).permit!.to_h.slice(*keys)
  end

  # La carrera es real: dos personas de la mesa guardando a la vez no encuentran
  # fila, las dos insertan, y el índice parcial levanta `RecordNotUnique`. Se
  # reintenta una vez y ahí la fila ya existe. Un `upsert` sería una sentencia
  # sola, pero saltea las dos validaciones del modelo, que es justo lo que no se
  # quiere saltear.
  def write!(group, idea, intento: 1)
    draft = group.workshop_drafts.find_or_initialize_by(
      workshop_challenge: @link, idea_id: idea&.id
    )
    draft.update!(payload: payload_params, updated_by: current_user,
                  based_on_version_id: idea&.current_version_id)
  rescue ActiveRecord::RecordNotUnique
    raise if intento > 1

    write!(group, idea, intento: 2)
  end
end
