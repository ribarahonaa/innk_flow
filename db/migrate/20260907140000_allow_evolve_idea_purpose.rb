# frozen_string_literal: true

# La lista de propósitos vive en el modelo Y en un CHECK de Postgres: sumar una
# tarea de IA es tocar los dos.
class AllowEvolveIdeaPurpose < ActiveRecord::Migration[7.1]
  PURPOSES = %w[
    propose_pipeline suggest_form_fields suggest_criteria generate_ideas
    coauthor_field detect_duplicates suggest_feedback evaluate_idea
    decide_verdicts evolve_idea summarize_challenge
  ].freeze

  def up = replace_check(PURPOSES)

  def down = replace_check(PURPOSES - ["evolve_idea"])

  private

  def replace_check(purposes)
    lista = purposes.map { |p| connection.quote(p) }.join(", ")
    execute "ALTER TABLE ai_runs DROP CONSTRAINT ai_runs_purpose_check"
    execute "ALTER TABLE ai_runs ADD CONSTRAINT ai_runs_purpose_check CHECK (purpose IN (#{lista}))"
  end
end
