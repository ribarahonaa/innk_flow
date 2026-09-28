# frozen_string_literal: true

# Sumar un valor a un enum que tiene CHECK de Postgres son DOS lugares. Sin
# este cambio la fila revienta con PG::CheckViolation antes de crearse, y el
# error llega truncado — es lo que pasó con `ai_runs.purpose`.
class AllowWorkshopActorOnIdeaVersions < ActiveRecord::Migration[7.1]
  def up
    remove_check_constraint :idea_versions, name: "idea_versions_actor_type_check"
    add_check_constraint :idea_versions,
                         "actor_type IN ('human','ai','workshop')",
                         name: "idea_versions_actor_type_check"
  end

  def down
    remove_check_constraint :idea_versions, name: "idea_versions_actor_type_check"
    add_check_constraint :idea_versions,
                         "actor_type IN ('human','ai')",
                         name: "idea_versions_actor_type_check"
  end
end
