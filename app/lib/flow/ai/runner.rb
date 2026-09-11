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
      Result = Data.define(:ok, :run, :suggestion, :errors, :reused) do
        def ok? = ok
        def reused? = reused
        def error_sentence = errors.join(". ")
      end

      def self.call(...) = new(...).call

      def initialize(task, mode:, requested_by: nil, challenge: nil, step: nil, idea: nil)
        @task = task
        # Lo que es para leer se lee: una tarea informativa no toca el dominio,
        # así que en «IA automática» auto-aceptarla no aplicaba nada y la
        # sacaba del panel, que es el único lugar donde se ve. Corre asistida
        # en cualquier modo, y el run lo registra así.
        @mode = task.informativa? ? "ai_assisted" : mode
        @requested_by = requested_by
        @challenge = challenge || step&.challenge || idea&.challenge
        @step = step
        @idea = idea
      end

      def call
        return already_done(reusable_run) if reusable_run

        run = create_run!
        response = invoke(run)

        return failed(run, response.error) unless response.ok?

        suggestion = build_suggestion!(run, response)
        apply_if_auto(run, suggestion)
      rescue StandardError => e
        Rails.logger.error("[Flow::AI::Runner] #{@task.purpose}: #{e.class} #{e.message}")
        run&.update(status: "failed", error: "#{e.class}: #{e.message}")
        Result.new(ok: false, run: run, suggestion: nil, errors: [e.message], reused: false)
      end

      private

      def provider = Flow::AI.provider

      # ── Idempotencia ──────────────────────────────────────────────────
      #
      # Protege contra el REINTENTO del mismo pedido (un retry de Sidekiq, un
      # doble clic), no contra un pedido NUEVO de la persona.
      #
      # La diferencia importa: si alguien pide una propuesta, la descarta y
      # vuelve a pedirla, está pidiendo algo nuevo. Devolverle la sugerencia
      # descartada la deja sin nada que revisar y sin forma de salir.
      #
      # Un run se reutiliza solo mientras sigue "vivo": está en curso, o su
      # sugerencia todavía espera revisión. Una vez resuelta (aceptada, editada
      # o rechazada) o fallida, el pedido siguiente genera un run nuevo, con la
      # clave base más el número de intento.
      def base_idempotency_key = @task.idempotency_key

      def previous_runs
        @previous_runs ||= AiRun.where(
          "idempotency_key = :key OR idempotency_key LIKE :prefix",
          key: base_idempotency_key, prefix: "#{base_idempotency_key}:%"
        ).order(:created_at).to_a
      end

      def reusable_run
        return @reusable_run if defined?(@reusable_run)

        @reusable_run = previous_runs.reverse.find { |run| reusable?(run) }
      end

      def reusable?(run)
        return true if %w[queued running].include?(run.status)
        return false unless run.status == "succeeded"

        # Sigue habiendo algo que revisar: no tiene sentido pedir de nuevo.
        run.ai_suggestions.any?(&:pending?)
      end

      def effective_idempotency_key
        return base_idempotency_key if previous_runs.empty?

        "#{base_idempotency_key}:#{previous_runs.size + 1}"
      end

      def already_done(run)
        Result.new(ok: run.status == "succeeded", run: run,
                   suggestion: run.ai_suggestions.detect(&:pending?) || run.ai_suggestions.first,
                   errors: [], reused: true)
      end

      def create_run!
        AiRun.create!(
          challenge: @challenge, challenge_step: @step, idea: @idea,
          requested_by: @requested_by,
          purpose: @task.purpose, mode: @mode, status: "running",
          prompt: { messages: @task.messages, context: @task.context_snapshot },
          provider: provider.name,
          idempotency_key: effective_idempotency_key
        )
      end

      def invoke(run)
        # Algunas tareas resuelven sin llamar al modelo. DetectDuplicates
        # compara con embeddings cuando el proveedor los tiene; cuando no,
        # vuelve al camino de siempre. Quién decide es la tarea, mirando al
        # proveedor: el runner no sabe de embeddings.
        if @task.respond_to?(:local?) && @task.local?(provider)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          data = @task.run_locally(provider)
          elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

          # `nil` significa «no pude resolverlo acá, seguí por el camino
          # normal». Sin esto, un proveedor de embeddings configurado pero
          # caído rompe una tarea que sabe arreglárselas sin él.
          return provider.complete(messages: @task.messages, schema: @task.schema,
                                   purpose: @task.purpose) if data.nil?

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
        Result.new(ok: false, run: run, suggestion: nil, errors: [message], reused: false)
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
        return Result.new(ok: true, run: run, suggestion: suggestion, errors: [], reused: false) unless run.auto?

        applied, errors = @task.apply!(suggestion.payload, suggestion: suggestion)

        if applied
          suggestion.update!(status: "accepted", auto_accepted_at: Time.current,
                             review_note: "Aceptada automáticamente (modo IA automática)")
          Result.new(ok: true, run: run, suggestion: suggestion, errors: [], reused: false)
        else
          # La sugerencia queda pendiente: la IA propuso algo que el dominio
          # rechazó, y eso lo tiene que ver una persona.
          suggestion.update!(review_note: "No se pudo aplicar automáticamente: #{errors.join('. ')}")
          Result.new(ok: false, run: run, suggestion: suggestion, errors: errors, reused: false)
        end
      end
    end
  end
end
