# frozen_string_literal: true

# Las dos FKs `ON DELETE SET NULL` de `selection_verdicts` nulean TODAS las
# columnas del lado local, company_id incluida —que es NOT NULL—, así que
# borrar un criterio o un run de IA moría con `PG::NotNullViolation` en vez de
# dejar el veredicto sin su criterio.
#
# No es que la migración original pidiera otra cosa: ya pasaba
# `on_delete: :nullify`. El acotador `SET NULL (columna)` (PG 15+) se sumó a
# `add_tenant_fk` DESPUÉS de que esa migración corriera, y las constraints
# viejas se quedaron como estaban, en la base y en el dump. Acá se recrean con
# el helper de hoy; las otras doce ya nacieron acotadas.
class BoundSetNullOnSelectionVerdicts < ActiveRecord::Migration[7.1]
  include Flow::MigrationHelpers

  PARENTS = { criteria: :criterion_id, ai_runs: :ai_run_id }.freeze

  def up
    PARENTS.each do |to_table, column|
      remove_tenant_fk :selection_verdicts, column: column
      add_tenant_fk :selection_verdicts, to_table, column: column, on_delete: :nullify
    end
  end

  # Volver al defecto de Postgres es volver al defecto: `SET NULL` a secas
  # nulea todo. Se escribe a mano porque el helper ya no sabe hacerlo mal.
  def down
    PARENTS.each do |to_table, column|
      remove_tenant_fk :selection_verdicts, column: column
      execute <<~SQL.squish
        ALTER TABLE #{quote_table_name(:selection_verdicts)}
          ADD CONSTRAINT selection_verdicts_#{column}_same_company
          FOREIGN KEY (#{column}, company_id)
          REFERENCES #{quote_table_name(to_table)} (id, company_id)
          ON DELETE SET NULL
      SQL
    end
  end
end
