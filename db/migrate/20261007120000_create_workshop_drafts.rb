# frozen_string_literal: true

# El borrador de trabajo de una mesa: lo que teclea y todavía no mandó.
#
# NO es una versión ni una propuesta. Una versión es contenido inmutable con su
# `embedding`, y una propuesta es algo que la mesa YA mandó para que el autor
# decida. Esto es mutable y se pisa: por eso no acumula filas ni encola un
# `EmbedVersionJob` por tanda de tecleo, que es lo que haría un autoguardado que
# publicara.
#
# No reusa `workshop_proposals` porque ahí `idea_id` es NOT NULL y en la cara de
# idear la idea todavía no existe: cubriría media función.
class CreateWorkshopDrafts < ActiveRecord::Migration[7.1]
  include Flow::MigrationHelpers

  def change
    tenant_table :workshop_drafts do |t|
      t.uuid :workshop_group_id,     null: false
      t.uuid :workshop_challenge_id, null: false
      # NULL en idear: el borrador es de la mesa y de la sala, y todavía no hay
      # idea a la que colgarse.
      t.uuid :idea_id
      # Contra qué versión se tecleó. Es lo que deja avisar que la vigente
      # avanzó mientras la mesa escribía.
      t.uuid :based_on_version_id
      t.jsonb :payload, null: false, default: {}
      # Quién tocó último. Funcional y no auditoría: es la única señal de
      # colisión que se puede dar sin websockets —el sello la nombra—.
      t.references :updated_by, type: :uuid, null: false,
                   foreign_key: { to_table: :users }
      t.timestamps
    end

    # DOS índices parciales y no uno: Postgres trata los NULL como distintos,
    # así que un UNIQUE(group, link, idea) a secas dejaría a una mesa acumular
    # un borrador de idear POR AUTOGUARDADO. Mismo patrón que
    # `index_workshop_groups_on_workshop_id_arrival ... WHERE arrival`.
    add_index :workshop_drafts, %i[workshop_group_id workshop_challenge_id],
              unique: true, where: "idea_id IS NULL",
              name: "index_workshop_drafts_ideation_uniq"
    add_index :workshop_drafts, %i[workshop_group_id workshop_challenge_id idea_id],
              unique: true, where: "idea_id IS NOT NULL",
              name: "index_workshop_drafts_evolution_uniq"

    add_tenant_fk :workshop_drafts, :workshop_groups,     column: :workshop_group_id
    add_tenant_fk :workshop_drafts, :workshop_challenges, column: :workshop_challenge_id
    add_tenant_fk :workshop_drafts, :ideas,               column: :idea_id
    # `nullify` y no `cascade`: si se borrara una versión, el cascade se
    # llevaría el texto de la mesa por un evento ajeno a ella. Nulificando se
    # pierde sólo el marcador de «contra qué se tecleó» y el texto queda. El
    # helper acota el SET NULL a la columna para no nulear `company_id`, que es
    # NOT NULL.
    add_tenant_fk :workshop_drafts, :idea_versions, column: :based_on_version_id,
                                                   on_delete: :nullify
  end
end
