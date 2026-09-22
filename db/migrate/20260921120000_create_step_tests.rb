# frozen_string_literal: true

# El sexto kind del flujo y la tabla donde vive cada testeo.
#
# La lista de kinds vive en el modelo Y en un CHECK de Postgres: sumar uno es
# tocar los dos. El check es lo que impide que una migración de datos o un job
# viejo metan un kind que `Handlers::Base.for` no sabe despachar.
class CreateStepTests < ActiveRecord::Migration[7.1]
  KINDS = %w[ideation evolution evaluation selection reporting testing].freeze
  VERDICTS = %w[factible con_reservas no_factible].freeze
  ACTOR_TYPES = %w[human ai].freeze

  def up
    reemplazar_check_de_kind(KINDS)

    tenant_table :step_tests do |t|
      t.references :challenge_step, null: false, type: :uuid, index: true
      t.references :idea, null: false, type: :uuid, index: true
      t.references :idea_version, null: false, type: :uuid

      t.string :verdict, null: false
      t.jsonb :situations, null: false, default: []
      t.jsonb :reservations, null: false, default: []
      t.text :summary

      t.string :actor_type, null: false, default: "human"
      t.references :tested_by, type: :uuid, foreign_key: { to_table: :users }
      # Sin `foreign_key:` acá: ai_runs tiene company_id, así que la FK tiene
      # que ser compuesta (ver `add_tenant_fk` más abajo). Un `foreign_key:
      # true` en el `references` arma una FK simple id->id, exactamente la
      # fuga que `spec/tenancy/schema_spec.rb` está para cazar.
      t.uuid :ai_run_id

      t.datetime :superseded_at
      t.datetime :tested_at, null: false
      t.timestamps
    end

    agregar_check :step_tests, :verdict, VERDICTS
    agregar_check :step_tests, :actor_type, ACTOR_TYPES

    # UN solo testeo vigente por idea, garantizado por la base y no por una
    # convención que un camino de escritura nuevo pueda romper.
    add_index :step_tests, %i[challenge_step_id idea_id],
              unique: true, where: "superseded_at IS NULL",
              name: "index_step_tests_vigente"

    # Postgres rechaza atar una fila de la empresa A a un padre de la B.
    add_tenant_fk :step_tests, :challenge_steps, column: :challenge_step_id
    add_tenant_fk :step_tests, :ideas, column: :idea_id
    add_tenant_fk :step_tests, :idea_versions, column: :idea_version_id
    add_tenant_fk :step_tests, :ai_runs, column: :ai_run_id, on_delete: :nullify
  end

  def down
    drop_table :step_tests
    reemplazar_check_de_kind(KINDS - ["testing"])
  end

  private

  def reemplazar_check_de_kind(kinds)
    lista = kinds.map { |k| connection.quote(k) }.join(", ")
    execute "ALTER TABLE challenge_steps DROP CONSTRAINT challenge_steps_kind_check"
    execute "ALTER TABLE challenge_steps ADD CONSTRAINT challenge_steps_kind_check CHECK (kind IN (#{lista}))"
  end

  def agregar_check(tabla, columna, valores)
    lista = valores.map { |v| connection.quote(v) }.join(", ")
    execute "ALTER TABLE #{tabla} ADD CONSTRAINT #{tabla}_#{columna}_check CHECK (#{columna} IN (#{lista}))"
  end
end
