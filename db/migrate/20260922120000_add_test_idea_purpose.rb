# frozen_string_literal: true

# Sumar una tarea de IA es tocar TRES lugares: la clase, `AiRun::PURPOSES` y
# este CHECK. Sin el CHECK el run revienta con `PG::CheckViolation` antes de
# crearse, y el error llega truncado hasta la pantalla.
class AddTestIdeaPurpose < ActiveRecord::Migration[7.1]
  PURPOSES = %w[
    propose_pipeline suggest_form_fields suggest_criteria generate_ideas
    coauthor_field detect_duplicates suggest_feedback evaluate_idea
    decide_verdicts evolve_idea summarize_challenge test_idea
  ].freeze

  def up = reemplazar_check(PURPOSES)
  def down = reemplazar_check(PURPOSES - ["test_idea"])

  private

  def reemplazar_check(purposes)
    lista = purposes.map { |p| connection.quote(p) }.join(", ")
    execute "ALTER TABLE ai_runs DROP CONSTRAINT ai_runs_purpose_check"
    execute "ALTER TABLE ai_runs ADD CONSTRAINT ai_runs_purpose_check CHECK (purpose IN (#{lista}))"
  end
end
