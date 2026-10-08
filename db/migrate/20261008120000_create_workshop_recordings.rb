# frozen_string_literal: true

# La grabación de la conversación de una mesa.
#
# El audio vive en Active Storage, que NO tiene `company_id`: la tenencia la
# lleva esta fila, igual que `IdeaAttachment` y `Report`. Y como
# `config.active_storage.draw_routes = false`, no hay rutas públicas de blob que
# esquiven la policy.
#
# SIN índice único, a diferencia de `workshop_drafts`: una mesa graba varias
# veces en una sesión, y cada grabación es una conversación distinta.
class CreateWorkshopRecordings < ActiveRecord::Migration[7.1]
  include Flow::MigrationHelpers

  def change
    tenant_table :workshop_recordings do |t|
      t.uuid :workshop_group_id,     null: false
      t.uuid :workshop_challenge_id, null: false
      # Qué idea tenía la sala elegida al apretar grabar. Es CONTEXTO y no
      # pertenencia: sirve para que el resumen de C2 no le dé la conversación
      # sobre la idea X al borrador de la idea Y. NULL en idear, donde la idea
      # todavía no existe.
      t.uuid :idea_id
      t.references :recorded_by, type: :uuid, null: false,
                   foreign_key: { to_table: :users }
      t.string :status, null: false, default: "pending"
      # Las utterances NORMALIZADAS y no la respuesta cruda: medido, 0,040 MB
      # por 20 minutos contra 0,80 MB. Lo que se tira es reconstruible porque el
      # audio se conserva, y re-transcribir es justamente cómo se arregla una
      # diarización colapsada.
      t.jsonb :utterances, null: false, default: []
      t.float :duration_seconds
      # Auditoría. A diferencia de los embeddings, transcribir se COBRA por
      # minuto, y alguien va a preguntar cuánto salió y con qué modelo. Mismo
      # precedente que `idea_versions.embedding_model`: el dato va al lado del
      # artefacto y no en una tabla aparte. De paso es lo que deja a la pantalla
      # decir que una transcripción salió del fixture.
      t.string :provider
      t.string :model
      t.string :request_id
      t.text :error
      t.timestamps
    end

    execute <<~SQL.squish
      ALTER TABLE workshop_recordings
        ADD CONSTRAINT workshop_recordings_status_check
        CHECK (status IN ('pending', 'transcribing', 'ready', 'failed'))
    SQL

    # El par por el que se lista en la sala. Plano y no único.
    add_index :workshop_recordings, %i[workshop_group_id workshop_challenge_id],
              name: "index_workshop_recordings_on_group_and_room"
    # Por la FK con cascade, igual que en `workshop_drafts`.
    add_index :workshop_recordings, :idea_id
    # Lo que el job busca para no re-transcribir: las que están esperando.
    add_index :workshop_recordings, :status

    add_tenant_fk :workshop_recordings, :workshop_groups,     column: :workshop_group_id
    add_tenant_fk :workshop_recordings, :workshop_challenges, column: :workshop_challenge_id
    # `nullify` y no `cascade`: borrar una idea no puede llevarse la grabación
    # de una conversación que habló de varias. El helper acota el SET NULL a la
    # columna para no nulear `company_id`, que es NOT NULL.
    add_tenant_fk :workshop_recordings, :ideas, column: :idea_id, on_delete: :nullify
  end
end
