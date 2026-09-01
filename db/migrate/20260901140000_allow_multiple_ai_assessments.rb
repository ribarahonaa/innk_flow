# frozen_string_literal: true

# En modo automático la IA tiene que cubrir el mínimo de evaluaciones del
# módulo. Si pide 3 por idea, hace 3.
#
# El índice anterior permitía UNA sola evaluación de IA por idea, así que un
# módulo con mínimo 2 o más quedaba trabado: la IA no podía completarlo y
# `can_complete?` nunca daba verdadero.
#
# Cada pasada es una consulta independiente al proveedor —su propio ai_run,
# su propio prompt— así que la unicidad pasa a ser por run.
class AllowMultipleAiAssessments < ActiveRecord::Migration[7.1]
  def up
    execute "DROP INDEX IF EXISTS index_assessments_unique_ai"
    execute <<~SQL.squish
      CREATE UNIQUE INDEX index_assessments_unique_ai
        ON assessments (challenge_step_id, idea_id, ai_run_id)
        WHERE superseded_at IS NULL AND evaluator_id IS NULL
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS index_assessments_unique_ai"
    execute <<~SQL.squish
      CREATE UNIQUE INDEX index_assessments_unique_ai
        ON assessments (challenge_step_id, idea_id)
        WHERE superseded_at IS NULL AND evaluator_id IS NULL
    SQL
  end
end
