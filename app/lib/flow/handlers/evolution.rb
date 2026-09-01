# frozen_string_literal: true

module Flow
  module Handlers
    # «Evolución»: se da feedback y el autor actualiza la idea.
    #
    # Cierra el círculo del versionado: el feedback apunta a la versión que se
    # leyó, y la respuesta del autor es una versión nueva atada a este módulo.
    class Evolution < Base
      def can_activate? = [true, []]

      def progress
        entries = step.step_entries
        done = entries.count { |entry| responded?(entry) }
        Progress.new(done: done, total: entries.size, label: "ideas actualizadas")
      end

      def can_complete?
        return [true, []] if settings["allow_partial"] != false && !require_response?

        pending = step.step_entries.reject { |entry| responded?(entry) }
        return [true, []] if pending.empty?

        [false, ["#{pending.size} #{'idea'.pluralize(pending.size)} sin responder al feedback."]]
      end

      def feedback_for(idea_id)
        feedback_index.fetch(idea_id, [])
      end

      def open_feedback_for(idea_id) = feedback_for(idea_id).reject(&:addressed)

      # Una idea "respondió" si publicó una versión nueva desde este módulo.
      def responded?(entry)
        entry.output_version_id.present? ||
          versions_from_step.any? { |version| version.idea_id == entry.idea_id }
      end

      # Registra que una versión nueva responde al feedback abierto.
      #
      # Se llama desde IdeasController cuando el autor publica: acá se cierra
      # el ciclo feedback → versión.
      def record_response!(idea, version)
        entry = step.step_entries.find_by(idea_id: idea.id)
        entry&.update!(status: "done", output_version_id: version.id, resolved_at: Time.current)

        FeedbackItem.where(challenge_step_id: step.id, idea_id: idea.id, addressed: false)
                    .update_all(addressed: true, addressed_by_version_id: version.id, updated_at: Time.current)
        entry
      end

      protected

      def on_activate
        request_ai_feedback! unless effective_ai_mode == "human"
      end

      # El feedback sin atender NO bloquea el cierre: queda registrado como
      # abierto y visible en el historial de la idea.
      def on_complete
        step.step_entries.each do |entry|
          next if entry.resolved_at

          entry.update!(status: responded?(entry) ? "done" : "advanced", resolved_at: Time.current)
        end
      end

      private

      def require_response? = settings["require_response"] == true

      def feedback_index
        @feedback_index ||= FeedbackItem.where(challenge_step_id: step.id)
                                        .chronological.includes(:author).group_by(&:idea_id)
      end

      def versions_from_step
        @versions_from_step ||= IdeaVersion.where(source_step_id: step.id).to_a
      end

      # Una llamada por idea, encolada: nunca fan-out síncrono en el request.
      def request_ai_feedback!
        step.step_entries.each do |entry|
          Flow::AI::RunJob.perform_later(
            step.company_id, "suggest_feedback",
            { "step_id" => step.id, "idea_id" => entry.idea_id }
          )
        end
      end
    end
  end
end
