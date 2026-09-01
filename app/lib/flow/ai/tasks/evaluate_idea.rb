# frozen_string_literal: true

module Flow
  module AI
    module Tasks
      # La IA evalúa una idea con los criterios congelados del módulo.
      #
      # Produce una evaluación como cualquier otra —anclada a la versión que
      # juzgó, con una nota y un comentario por criterio— así que entra en el
      # promedio junto a las humanas y se ve igual en la pantalla.
      #
      # Solo se le piden los criterios que alguien podría responder: los
      # automáticos los verifica el sistema y las fórmulas se derivan.
      class EvaluateIdea < Base
        def messages
          [
            { role: "system", content: <<~TXT.squish },
              Evaluás una idea postulada a un desafío de innovación, con los criterios que te
              dan. Para cada criterio devolvés un valor dentro de su escala y una justificación
              breve y concreta, basada en lo que la idea dice. No inventás datos que la idea no
              tiene: si falta información para juzgar un criterio, lo decís en la justificación
              y puntuás bajo.
            TXT
            { role: "user", content: <<~TXT }
              Desafío: #{challenge.name}
              Brief: #{challenge.brief}

              Idea: #{idea.title}
              #{idea.payload.map { |k, v| "#{k}: #{v}" }.join("\n")}

              Criterios:
              #{criteria_prompt}
            TXT
          ]
        end

        def schema
          {
            "type" => "object",
            "required" => %w[scores overall_comment],
            "properties" => {
              "overall_comment" => { "type" => "string" },
              "scores" => {
                "type" => "array",
                "minItems" => 1,
                "items" => {
                  "type" => "object",
                  "required" => %w[criterion_key value reason],
                  "properties" => {
                    "criterion_key" => { "type" => "string" },
                    "value" => { "type" => %w[string number] },
                    "reason" => { "type" => "string" }
                  }
                }
              }
            }
          }
        end

        def target_attributes = { idea: idea }

        def context_snapshot = { "criteria_keys" => answerable_criteria.map { _1["key"] } }

        def apply!(payload, suggestion:)
          handler = step.handler
          snapshot = handler.criteria_snapshot

          assessment = step.assessments.find_or_initialize_by(
            idea_id: idea.id, evaluator_id: nil, superseded_at: nil
          )
          assessment.assign_attributes(
            idea_version_id: idea.current_version_id, actor_type: "ai",
            status: "submitted", submitted_at: Time.current,
            ai_run_id: suggestion.ai_run_id, overall_comment: payload["overall_comment"]
          )
          assessment.save!

          payload["scores"].each do |row|
            config = snapshot.find { |c| c["key"] == row["criterion_key"] }
            next if config.nil?

            criterion = Criterion.find_by(id: config["id"])
            numeric, normalized = criterion ? criterion.score(row["value"].to_s) : [nil, nil]

            score = assessment.assessment_scores.find_or_initialize_by(criterion_key: config["key"])
            score.assign_attributes(
              criterion_id: config["id"], weight_used: config["weight"],
              raw_value: row["value"].to_s, numeric_value: numeric,
              normalized_value: normalized, comment: row["reason"]
            )
            score.save!
          end

          Flow::Evaluation::ScoreAssessment.new(assessment, criteria_snapshot: snapshot).call
          entry = StepEntry.find_or_create_by!(challenge_step_id: step.id, idea_id: idea.id) do |e|
            e.entered_at = Time.current
            e.input_version_id = idea.current_version_id
          end
          handler.recompute_entry!(entry)

          [true, []]
        end

        def preview(payload)
          scores = payload["scores"].map { |s| "#{s['criterion_key']}: #{s['value']}" }.join(" · ")
          "#{scores} — #{payload['overall_comment'].to_s.truncate(120)}"
        end

        private

        def answerable_criteria
          (step.settings["criteria"] || []).select { |c| %w[manual ai].include?(c["source"]) }
        end

        def criteria_prompt
          answerable_criteria.map do |config|
            criterion = Criterion.find_by(id: config["id"])
            options = criterion&.scale&.options
            escala = if options.present?
                       "opciones: #{options.map { |o| o.is_a?(Array) ? o.last : o }.join(', ')}"
                     else
                       "escala #{config['scale_type']}"
                     end
            "- #{config['key']} (#{config['name']}): #{escala}. #{config['description']}"
          end.join("\n")
        end
      end
    end
  end
end
