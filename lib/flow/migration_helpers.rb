# frozen_string_literal: true

module Flow
  # Helpers de migración para la defensa de tenancy.
  #
  # Rails 7.1 NO tiene DSL para claves foráneas compuestas (`add_foreign_key`
  # no acepta arrays de columnas; eso llegó en 7.2). Sin estos helpers, cada
  # tabla nueva exigiría escribir el mismo `ALTER TABLE ... FOREIGN KEY
  # (x_id, company_id) REFERENCES ...` a mano, y el día que alguien escriba
  # una FK simple en su lugar la garantía se pierde en silencio.
  #
  # spec/tenancy/schema_spec.rb introspecciona pg_constraint y falla si
  # aparece una FK simple entre dos tablas con company_id, así que este helper
  # es el camino cómodo y el spec es la red.
  module MigrationHelpers
    # Crea una tabla del dominio: PK uuid, company_id NOT NULL indexado, y el
    # UNIQUE (id, company_id) que las FKs compuestas necesitan como destino.
    def tenant_table(name, **options)
      create_table(name, id: :uuid, default: -> { "uuid_generate_v7()" }, **options) do |t|
        t.references :company, null: false, type: :uuid, foreign_key: true, index: true
        yield t if block_given?
      end

      execute <<~SQL.squish
        ALTER TABLE #{quote_table_name(name)}
          ADD CONSTRAINT #{name}_tenant_uniq UNIQUE (id, company_id)
      SQL
    end

    # FK compuesta: Postgres rechaza atar una fila de la empresa A a un padre
    # de la empresa B. No "valida" — rechaza.
    ON_DELETE = {
      cascade: "CASCADE",
      nullify: "SET NULL",     # ojo: Rails dice :nullify, Postgres dice SET NULL
      restrict: "RESTRICT",
      no_action: "NO ACTION"
    }.freeze

    def add_tenant_fk(from_table, to_table, column:, on_delete: :cascade)
      constraint = "#{from_table}_#{column}_same_company"
      action = ON_DELETE.fetch(on_delete.to_sym)
      # `SET NULL` sobre una FK compuesta nulea TODAS las columnas del lado
      # local, incluida company_id — que es NOT NULL. Acotar a la columna
      # (PG 15+) es lo único que evita el PG::NotNullViolation al borrar el
      # padre.
      action = "#{action} (#{column})" if on_delete.to_sym == :nullify

      execute <<~SQL.squish
        ALTER TABLE #{quote_table_name(from_table)}
          ADD CONSTRAINT #{constraint}
          FOREIGN KEY (#{column}, company_id)
          REFERENCES #{quote_table_name(to_table)} (id, company_id)
          ON DELETE #{action}
      SQL
    end

    def remove_tenant_fk(from_table, column:)
      execute <<~SQL.squish
        ALTER TABLE #{quote_table_name(from_table)}
          DROP CONSTRAINT IF EXISTS #{from_table}_#{column}_same_company
      SQL
    end
  end
end
