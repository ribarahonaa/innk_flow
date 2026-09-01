# frozen_string_literal: true

# Cómo se cierra un feedback.
#
# Hasta acá había un solo camino: publicar una versión nueva de la idea, y eso
# marcaba TODOS los comentarios abiertos de golpe — arreglar uno de tres los
# cerraba los tres. Y no había manera de decir "esto no aplica".
class AddResolutionToFeedbackItems < ActiveRecord::Migration[7.1]
  RESOLUTIONS = %w[answered acknowledged dismissed].freeze

  def change
    add_column :feedback_items, :resolution, :string
    add_column :feedback_items, :resolution_note, :text
    add_column :feedback_items, :resolved_at, :datetime
    add_reference :feedback_items, :resolved_by, type: :uuid, index: true
    add_foreign_key :feedback_items, :users, column: :resolved_by_id

    reversible do |dir|
      dir.up do
        list = RESOLUTIONS.map { |r| "'#{r}'" }.join(", ")
        execute <<~SQL.squish
          ALTER TABLE feedback_items ADD CONSTRAINT feedback_items_resolution_check
          CHECK (resolution IS NULL OR resolution IN (#{list}))
        SQL
        # Lo ya cerrado se considera respondido con una versión.
        execute "UPDATE feedback_items SET resolution = 'answered' WHERE addressed = true"
      end
      dir.down { execute "ALTER TABLE feedback_items DROP CONSTRAINT IF EXISTS feedback_items_resolution_check" }
    end
  end
end
