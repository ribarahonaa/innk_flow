# frozen_string_literal: true

module Flow
  module AI
    # Ejecuta una tarea y materializa el resultado.
    #
    # LOS TRES MODOS, en un solo camino:
    #   human       → no se llama al proveedor. El runner ni se invoca.
    #   ai_assisted → run + suggestion PENDIENTE. Una persona acepta/edita/rechaza.
    #   ai_auto     → run + suggestion ya ACEPTADA (auto_accepted_at) y aplicada.
    #
    # `ai_auto` no saltea la sugerencia: la auto-acepta. Eso mantiene un solo
    # code path, deja el mismo rastro de auditoría en los dos modos, y hace que
    # pasar un módulo de auto a assisted sea legible en el historial. Si `auto`
    # escribiera directo al dominio habría dos caminos y un agujero.
    class Runner
      Result = Data.define(:ok, :run, :suggestion, :errors) do
        def ok? = ok
        def error_sentence = errors.join(". ")
      end

      def self.call(...) = new(...).call

      def initialize(task, mode:, requested_by: nil, challenge: nil, step: nil, idea: nil)
        @task = task
        @mode = mode
        @requested_by = requested_by
        @challenge = challenge || step&.challenge || idea&.challenge
        @step = step
        @idea = idea
      end

      def call
        return already_done if existing_run

        run = create_run!
        response = invoke(run)

        return failed(run, response.error) unless response.ok?

        suggestion = build_suggestion!(run, response)
        apply_if_auto(run, suggestion)
      rescue StandardError => e
        Rails.logger.error("[Flow::AI::Runner] #{@task.purpose}: #{e.class} #{e.message}")
        run&.update(status: "failed", error: "#{e.class}: #{e.message}")
        Result.new(ok: false, run: run, suggestion: nil, errors: [e.message])
      end

      private

      def provider = Flow::AI.provider

      # Un pedido idéntico no vuelve a llamar al proveedor. Es lo que hace
      # seguro reintentar el job.
      def existing_run
        @existing_run ||= AiRun.find_by(idempotency_key: @task.idempotency_key)
      end

      def already_done
        Result.new(ok: existing_run.status == "succeeded", run: existing_run,
                   suggestion: existing_run.ai_suggestions.first, errors: [])
      end

      def create_run!
        AiRun.create!(
          challenge: @challenge, challenge_step: @step, idea: @idea,
          requested_by: @requested_by,
          purpose: @task.purpose, mode: @mode, status: "running",
          prompt: { messages: @task.messages, context: @task.context_snapshot },
          provider: provider.name,
          idempotency_key: @task.idempotency_key
        )
      end

      def invoke(run)
        # DetectDuplicates no pasa por #complete: calcula similitud local sobre
        # embeddings. Se le da su camino en vez de forzar la forma equivocada.
        if @task.respond_to?(:run_locally)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          data = @task.run_locally(provider)
          elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

          errors = Flow::AI::SchemaValidator.errors_for(data, @task.schema)
          return Provider::Result.new(ok: false, data: nil, raw: data, tokens_in: 0, tokens_out: 0,
                                      model: provider.name, latency_ms: elapsed,
                                      error: errors.join("; ")) if errors.any?

          return Provider::Result.new(ok: true, data: data, raw: data, tokens_in: 0, tokens_out: 0,
                                      model: provider.name, latency_ms: elapsed, error: nil)
        end

        provider.complete(messages: @task.messages, schema: @task.schema, purpose: @task.purpose)
      end

      def failed(run, message)
        run.update!(status: "failed", error: message)
        Result.new(ok: false, run: run, suggestion: nil, errors: [message])
      end

      def build_suggestion!(run, response)
        run.update!(
          status: "succeeded", response: response.data,
          model: response.model, tokens_in: response.tokens_in,
          tokens_out: response.tokens_out, latency_ms: response.latency_ms
        )

        AiSuggestion.create!(
          ai_run: run,
          payload: response.data,
          status: "pending",
          **@task.target_attributes
        )
      end

      def apply_if_auto(run, suggestion)
        return Result.new(ok: true, run: run, suggestion: suggestion, errors: []) unless run.auto?

        applied, errors = @task.apply!(suggestion.payload, suggestion: suggestion)

        if applied
          suggestion.update!(status: "accepted", auto_accepted_at: Time.current,
                             review_note: "Aceptada automáticamente (modo IA automática)")
          Result.new(ok: true, run: run, suggestion: suggestion, errors: [])
        else
          # La sugerencia queda pendiente: la IA propuso algo que el dominio
          # rechazó, y eso lo tiene que ver una persona.
          suggestion.update!(review_note: "No se pudo aplicar automáticamente: #{errors.join('. ')}")
          Result.new(ok: false, run: run, suggestion: suggestion, errors: errors)
        end
      end
    end
  end
end
