# frozen_string_literal: true

# La lista de propósitos vive en el modelo Y en un CHECK de Postgres: sumar una
# tarea de IA es tocar los dos. El check es lo que impide que un job viejo o una
# migración de datos meta un propósito que el código no sabe atender.
class AllowSuggestCriteriaPurpose < ActiveRecord::Migration[7.1]
  PURPOSES = %w[
    propose_pipeline suggest_form_fields suggest_criteria generate_ideas
    coauthor_field detect_duplicates suggest_feedback evaluate_idea
    summarize_challenge
  ].freeze

  def up = replace_check(PURPOSES)

  def down = replace_check(PURPOSES - ["suggest_criteria"])

  private

  def replace_check(purposes)
    lista = purposes.map { |p| connection.quote(p) }.join(", ")
    execute "ALTER TABLE ai_runs DROP CONSTRAINT ai_runs_purpose_check"
    execute "ALTER TABLE ai_runs ADD CONSTRAINT ai_runs_purpose_check CHECK (purpose IN (#{lista}))"
  end
end
