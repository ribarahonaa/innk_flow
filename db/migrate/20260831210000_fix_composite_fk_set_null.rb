# frozen_string_literal: true

# Corrige las FKs compuestas con ON DELETE SET NULL.
#
# `ON DELETE SET NULL` sobre una FK compuesta (columna, company_id) nulea AMBAS
# columnas al borrar el padre — y company_id es NOT NULL, así que el borrado
# revienta con:
#
#   PG::NotNullViolation: null value in column "company_id" ...
#   CONTEXT: SQL statement "UPDATE ... SET source_step_id = NULL, company_id = NULL"
#
# Postgres 15+ permite acotar qué columnas se nulean: `SET NULL (columna)`.
class FixCompositeFkSetNull < ActiveRecord::Migration[7.1]
  NULLIFYING = [
    %w[challenge_steps challenge_steps source_step_id],
    %w[challenge_steps criteria_sets criteria_set_id],
    %w[idea_versions challenge_steps source_step_id],
    %w[ideas idea_versions current_version_id],
    %w[step_entries idea_versions input_version_id],
    %w[step_entries idea_versions output_version_id],
    %w[assessments ai_runs ai_run_id],
    %w[assessment_scores criteria criterion_id],
    %w[feedback_items idea_versions addressed_by_version_id],
    %w[feedback_items ai_runs ai_run_id],
    %w[reports ai_runs ai_run_id]
  ].freeze

  def up
    NULLIFYING.each do |from_table, to_table, column|
      execute "ALTER TABLE #{from_table} DROP CONSTRAINT IF EXISTS #{from_table}_#{column}_same_company"
      execute <<~SQL.squish
        ALTER TABLE #{from_table}
          ADD CONSTRAINT #{from_table}_#{column}_same_company
          FOREIGN KEY (#{column}, company_id)
          REFERENCES #{to_table} (id, company_id)
          ON DELETE SET NULL (#{column})
      SQL
    end
  end

  def down
    NULLIFYING.each do |from_table, to_table, column|
      execute "ALTER TABLE #{from_table} DROP CONSTRAINT IF EXISTS #{from_table}_#{column}_same_company"
      execute <<~SQL.squish
        ALTER TABLE #{from_table}
          ADD CONSTRAINT #{from_table}_#{column}_same_company
          FOREIGN KEY (#{column}, company_id)
          REFERENCES #{to_table} (id, company_id)
          ON DELETE SET NULL
      SQL
    end
  end
end
