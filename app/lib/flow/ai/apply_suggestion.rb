# frozen_string_literal: true

module Flow
  module AI
    # Acepta (o edita y acepta) una sugerencia pendiente y la aplica al dominio.
    #
    # Misma ruta que usa el modo automático: aceptar a mano y aceptar solo
    # ejecutan el mismo `task.apply!`.
    class ApplySuggestion
      Result = Data.define(:ok, :errors) do
        def ok? = ok
        def error_sentence = errors.join(". ")
      end

      def initialize(suggestion, user:, payload: nil)
        @suggestion = suggestion
        @user = user
        @payload = payload
      end

      def call
        return Result.new(ok: false, errors: ["esta sugerencia ya fue revisada"]) if @suggestion.resolved?

        edited = @payload.present? && @payload != @suggestion.payload
        if edited && !task.editable?
          return Result.new(ok: false, errors: ["esta propuesta no se edita: se aplica como la dio la IA o se descarta"])
        end

        payload = edited ? @payload : @suggestion.payload

        # `apply!` puede aplicar PARTE: crear tres criterios de cinco, por
        # ejemplo. Los errores viajan aunque haya salido bien, para que la
        # pantalla no anuncie un éxito limpio sobre algo que quedó a medias.
        applied, errors = task.apply!(payload, suggestion: assign_reviewer)
        return Result.new(ok: false, errors: errors) unless applied

        @suggestion.update!(
          payload: payload,
          status: edited ? "edited" : "accepted",
          reviewed_by: @user,
          reviewed_at: Time.current
        )
        Result.new(ok: true, errors: errors)
      end

      def reject!(note: nil)
        @suggestion.update!(status: "rejected", reviewed_by: @user,
                            reviewed_at: Time.current, review_note: note)
        Result.new(ok: true, errors: [])
      end

      private

      def assign_reviewer
        @suggestion.reviewed_by = @user
        @suggestion
      end

      def task
        run = @suggestion.ai_run
        Flow::AI::Tasks::Base.for(
          run.purpose,
          challenge: run.challenge, step: run.challenge_step, idea: run.idea,
          **rehydrated_context(run)
        )
      end

      # El contexto que la tarea guardó al ejecutarse (ai_runs.prompt["context"]).
      # Sin esto, aceptar una sugerencia de CoauthorField no sabría sobre qué
      # campo trabajar.
      def rehydrated_context(run)
        snapshot = run.prompt["context"] || {}
        context = {}

        if (key = snapshot["field_key"]).present?
          field = run.challenge_step&.form_fields&.find_by(key: key)
          context[:field] = field if field
        end

        context[:count] = snapshot["count"] if snapshot["count"].present?
        context
      end
    end
  end
end
