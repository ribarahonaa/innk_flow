# frozen_string_literal: true

require "rails_helper"

# Introspección pura de esquema: esta es la capa que hace la fuga IMPOSIBLE de
# escribir, no solo improbable. Si alguien agrega una FK simple entre dos
# tablas con company_id, este spec falla y le dice cuál.
RSpec.describe "esquema: aislamiento por empresa en la base" do
  def sql(query) = ActiveRecord::Base.connection.select_all(query).to_a

  # Tablas del dominio: las que llevan company_id.
  let(:tenant_tables) do
    sql(<<~SQL).pluck("table_name")
      SELECT c.relname AS table_name
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_attribute a ON a.attrelid = c.oid
      WHERE c.relkind = 'r'
        AND n.nspname = 'public'
        AND a.attname = 'company_id'
        AND a.attnum > 0
        AND NOT a.attisdropped
      ORDER BY 1
    SQL
  end

  it "company_id es NOT NULL en toda tabla de dominio" do
    nullable = sql(<<~SQL).pluck("table_name")
      SELECT c.relname AS table_name
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_attribute a ON a.attrelid = c.oid
      WHERE c.relkind = 'r' AND n.nspname = 'public'
        AND a.attname = 'company_id' AND a.attnum > 0 AND NOT a.attisdropped
        AND a.attnotnull = false
    SQL

    # `sessions.company_id` es nullable a propósito: existe la sesión sin
    # empresa elegida todavía (login multiempresa → selector).
    expect(nullable - %w[sessions]).to be_empty
  end

  it "toda tabla de dominio tiene UNIQUE (id, company_id) para ser destino de FK compuesta" do
    missing = tenant_tables - %w[sessions] - sql(<<~SQL).pluck("table_name")
      SELECT c.relname AS table_name
      FROM pg_constraint con
      JOIN pg_class c ON c.oid = con.conrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE con.contype = 'u' AND n.nspname = 'public'
        AND (
          SELECT array_agg(att.attname::text ORDER BY att.attname::text)
          FROM unnest(con.conkey) AS k(attnum)
          JOIN pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = k.attnum
        )::text[] = ARRAY['company_id', 'id']::text[]
    SQL

    expect(missing).to be_empty, lambda {
      "Sin UNIQUE (id, company_id): #{missing.join(', ')}.\n" \
      "Usá `tenant_table` en la migración (lib/flow/migration_helpers.rb)."
    }
  end

  it "toda FK entre dos tablas de dominio incluye company_id (es compuesta)" do
    foreign_keys = sql(<<~SQL)
      SELECT con.conname                AS name,
             src.relname                AS from_table,
             tgt.relname                AS to_table,
             (SELECT array_agg(att.attname ORDER BY k.ord)
                FROM unnest(con.conkey) WITH ORDINALITY AS k(attnum, ord)
                JOIN pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = k.attnum
             )::text                    AS from_columns
      FROM pg_constraint con
      JOIN pg_class src ON src.oid = con.conrelid
      JOIN pg_class tgt ON tgt.oid = con.confrelid
      JOIN pg_namespace n ON n.oid = src.relnamespace
      WHERE con.contype = 'f' AND n.nspname = 'public'
    SQL

    simple = foreign_keys.select do |fk|
      next false unless tenant_tables.include?(fk["from_table"])
      next false unless tenant_tables.include?(fk["to_table"])
      next false if fk["to_table"] == "companies"

      !fk["from_columns"].include?("company_id")
    end

    expect(simple).to be_empty, lambda {
      "FKs simples entre tablas de dominio (deberían ser compuestas):\n" +
        simple.map { |fk| "  - #{fk['from_table']}.#{fk['from_columns']} -> #{fk['to_table']}" }.join("\n") +
        "\n\nUsá `add_tenant_fk` en la migración."
    }
  end

  it "el schema canónico es SQL (schema.rb no serializa FKs compuestas)" do
    expect(Rails.application.config.active_record.schema_format).to eq(:sql)
  end

  # `ON DELETE SET NULL` sobre una FK compuesta nulea TODAS las columnas del
  # lado local si no se acota con `(columna)` — company_id incluida, que es
  # NOT NULL. Los tres tests de arriba no lo ven porque miran otra cosa: una
  # FK compuesta sin acotador sigue siendo compuesta. Postgres 15+ guarda el
  # acotador en `confdelsetcols`, así que este sí se puede leer del catálogo,
  # y de TODAS las FKs a la vez.
  #
  # La regla se escribe como «nulear no puede romper un NOT NULL» y no como «la
  # lista no puede nombrar company_id»: es la misma garantía sobre las FKs de
  # tenencia, pero además cubre cualquier otra columna NOT NULL, y acotar la
  # columna equivocada —`SET NULL (x_id)` con `x_id` NOT NULL pasa el DDL y
  # revienta al borrar, sin company_id a la vista— sin tener que acordarse.
  #
  # Lo que NO ve: `ON DELETE SET DEFAULT` comparte el mecanismo y la misma
  # columna del catálogo, pero ahí la falla depende del default de cada
  # columna y no solo de su NOT NULL. `add_tenant_fk` no sabe producirlo
  # (`ON_DELETE` no tiene la clave), así que solo llegaría por SQL a mano.
  it "ninguna FK ON DELETE SET NULL nulea una columna NOT NULL" do
    # Un acotador vacío significa «nulea todas», así que ahí las columnas
    # escritas son `conkey` entero.
    set_null = sql(<<~SQL)
      SELECT con.conname AS name,
             (SELECT string_agg(att.attname, ', ' ORDER BY att.attname)
                FROM pg_attribute att
                WHERE att.attrelid = con.conrelid
                  AND att.attnum = ANY (coalesce(nullif(con.confdelsetcols, '{}'), con.conkey))
                  AND att.attnotnull
             )          AS not_null_columns
      FROM pg_constraint con
      JOIN pg_class src ON src.oid = con.conrelid
      JOIN pg_namespace n ON n.oid = src.relnamespace
      WHERE con.contype = 'f' AND n.nspname = 'public' AND con.confdeltype = 'n'
    SQL

    # El piso. Sin esto una consulta rota devuelve cero filas, `rompen` queda
    # vacío y el ejemplo pasa midiendo NADA, que es indistinguible de estar
    # todo bien: la misma ceguera que el autotest de `[MONO]` y el muestrario
    # de contraste existen para tapar. Las dos que nacieron sin acotador
    # tienen que aparecer en lo medido.
    expect(set_null.map { |fk| fk["name"] }).to include(
      "selection_verdicts_criterion_id_same_company",
      "selection_verdicts_ai_run_id_same_company"
    )

    rompen = set_null.select { |fk| fk["not_null_columns"].present? }

    expect(rompen).to be_empty, lambda {
      "FKs SET NULL que al borrar el padre escriben NULL en una columna NOT NULL:\n" +
        rompen.map { |fk| "  - #{fk['name']} → #{fk['not_null_columns']}" }.join("\n") +
        "\n\nUsá `add_tenant_fk ..., on_delete: :nullify` (lib/flow/migration_helpers.rb),\n" \
        "que acota con `SET NULL (columna)`."
    }
  end

  # El de arriba lee la declaración; este borra de verdad, que es lo único que
  # prueba la garantía completa de punta a punta.
  it "borrar el padre de un ON DELETE SET NULL compuesto no se lleva puesto company_id" do
    company = without_tenant { create(:company) }

    as_company(company) do
      challenge = create(:challenge)
      paso = challenge.steps.create!(kind: "testing", position: 1, slug: "testeo")
      idea = create(:idea, challenge: challenge, status: "active")
      Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => "Sensores" }).call
      idea.reload

      ai_run = AiRun.create!(purpose: "evaluate_idea", mode: "ai_assisted", status: "succeeded")
      step_test = StepTest.create!(challenge_step: paso, idea: idea,
                                    idea_version_id: idea.current_version_id,
                                    verdict: "factible", tested_at: Time.current, ai_run: ai_run)

      # Sin el acotador, esto revienta con PG::NotNullViolation sobre
      # company_id ANTES de llegar a las aserciones de abajo.
      expect { ai_run.destroy! }.not_to raise_error

      step_test.reload
      expect(step_test.ai_run_id).to be_nil
      expect(step_test.company_id).to eq(company.id)
    end
  end
end
