# frozen_string_literal: true

# Los vectores de las ideas, para buscar por significado y no por cadena.
#
# Van en `idea_versions` y no en `ideas` a propósito: la versión es contenido
# INMUTABLE, así que el vector se calcula una vez y nunca queda viejo. En
# `ideas` habría que recalcularlo en cada republicación, y una idea con el
# vector de su versión anterior es peor que una sin vector.
class AddEmbeddingsToIdeaVersions < ActiveRecord::Migration[7.1]
  # La dimensión se fija acá y cambiarla es recrear la columna, así que la
  # elección de modelo queda atada. 1024 es la nativa de voyage-3.5 y la que
  # OpenAI puede truncar por parámetro: deja los dos abiertos.
  DIMENSIONS = 1024

  def up
    enable_extension "vector" unless extension_enabled?("vector")

    # En SQL y no con add_column: Rails no conoce el tipo `vector`, ignora el
    # `limit` y deja una columna SIN dimensión — que después no se puede
    # indexar («column does not have dimensions»).
    execute "ALTER TABLE idea_versions ADD COLUMN embedding vector(#{DIMENSIONS})"

    add_column :idea_versions, :embedding_model, :string
    add_column :idea_versions, :embedded_at, :datetime

    # HNSW y no IVFFlat: no necesita entrenarse con datos previos, que es justo
    # lo que no hay cuando la tabla arranca vacía. `vector_cosine_ops` porque
    # la comparación es por coseno, igual que la que ya hacía a mano.
    execute <<~SQL
      CREATE INDEX index_idea_versions_on_embedding
      ON idea_versions USING hnsw (embedding vector_cosine_ops)
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS index_idea_versions_on_embedding"
    remove_column :idea_versions, :embedded_at
    remove_column :idea_versions, :embedding_model
    remove_column :idea_versions, :embedding
  end
end
