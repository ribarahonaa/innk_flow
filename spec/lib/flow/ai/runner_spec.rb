# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flow::AI::Runner do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:user) { without_tenant { create(:user) } }
  let(:challenge) { create(:challenge, name: "Merma", brief: "Reducir la merma en bodega.") }
  let(:task) { Flow::AI::Tasks::ProposePipeline.new(challenge: challenge) }

  describe "modo ai_assisted" do
    it "deja la sugerencia PENDIENTE sin tocar el dominio" do
      result = described_class.call(task, mode: "ai_assisted", requested_by: user, challenge: challenge)

      expect(result).to be_ok
      expect(result.suggestion).to be_pending
      expect(challenge.steps).to be_empty, "no debe aplicarse sin revisión humana"
    end

    it "registra el run con costo y latencia" do
      result = described_class.call(task, mode: "ai_assisted", challenge: challenge)

      run = result.run
      expect(run).to be_succeeded
      expect(run.provider).to eq("fixture")
      expect(run.tokens_total).to be_positive
      expect(run.latency_ms).not_to be_nil
      expect(run.prompt["messages"]).to be_present
    end
  end

  describe "modo ai_auto" do
    it "auto-acepta la sugerencia Y la aplica" do
      result = described_class.call(task, mode: "ai_auto", requested_by: user, challenge: challenge)

      expect(result).to be_ok
      expect(result.suggestion).to be_accepted
      expect(result.suggestion.auto_accepted_at).to be_present
      expect(challenge.steps.reload.map(&:kind))
        .to eq(%w[ideation evolution evaluation selection evaluation selection reporting])
    end

    it "NO saltea la sugerencia: la crea igual, para dejar el mismo rastro" do
      # Es lo que permite que pasar un módulo de auto a assisted sea legible en
      # el historial, y que la auditoría no tenga un agujero.
      result = described_class.call(task, mode: "ai_auto", challenge: challenge)

      expect(result.run.ai_suggestions.count).to eq(1)
      expect(result.suggestion.review_note).to match(/automáticamente/)
    end

    it "si el dominio rechaza la propuesta, la deja pendiente para una persona" do
      challenge.update!(status: "running")

      result = described_class.call(task, mode: "ai_auto", challenge: challenge)

      expect(result).not_to be_ok
      expect(result.suggestion).to be_pending
      expect(result.suggestion.review_note).to match(/No se pudo aplicar/)
    end
  end

  describe "idempotencia" do
    it "un pedido idéntico no vuelve a llamar al proveedor mientras haya algo que revisar" do
      first = described_class.call(task, mode: "ai_assisted", challenge: challenge)

      expect { described_class.call(task, mode: "ai_assisted", challenge: challenge) }
        .not_to change { AiRun.count }

      second = described_class.call(task, mode: "ai_assisted", challenge: challenge)
      expect(second.run.id).to eq(first.run.id)
      expect(second).to be_reused
    end

    # La idempotencia protege contra el REINTENTO del mismo pedido, no contra
    # un pedido NUEVO de la persona.
    it "tras DESCARTAR la propuesta, volver a pedir genera una revisable" do
      first = described_class.call(task, mode: "ai_assisted", requested_by: user, challenge: challenge)
      Flow::AI::ApplySuggestion.new(first.suggestion, user: user).reject!(note: "No me sirve")

      second = described_class.call(task, mode: "ai_assisted", requested_by: user, challenge: challenge)

      expect(second.run.id).not_to eq(first.run.id)
      expect(second.suggestion).to be_pending
      expect(second).not_to be_reused
      expect(AiSuggestion.pending_review.count).to eq(1)
    end

    it "tras ACEPTAR la propuesta, volver a pedir también genera una nueva" do
      challenge.steps.destroy_all
      first = described_class.call(task, mode: "ai_assisted", requested_by: user, challenge: challenge)
      Flow::AI::ApplySuggestion.new(first.suggestion, user: user).call

      # El desafío ya no está en borrador tras aplicar el flujo, así que se
      # vuelve a dejar editable para pedir otra propuesta.
      challenge.update!(status: "draft")
      second = described_class.call(task, mode: "ai_assisted", requested_by: user, challenge: challenge)

      expect(second.run.id).not_to eq(first.run.id)
      expect(second.suggestion).to be_pending
    end

    it "tras un FALLO del proveedor, el pedido siguiente reintenta de verdad" do
      Flow::AI.provider = Flow::AI::Providers::Null.new
      failed = described_class.call(task, mode: "ai_assisted", challenge: challenge)
      expect(failed.run).to be_failed

      Flow::AI.reset_provider!
      retried = described_class.call(task, mode: "ai_assisted", challenge: challenge)

      expect(retried).to be_ok
      expect(retried.run.id).not_to eq(failed.run.id)
      expect(retried.suggestion).to be_pending
    end

    it "guarda el número de intento en la clave, sin romper el índice único" do
      first = described_class.call(task, mode: "ai_assisted", requested_by: user, challenge: challenge)
      Flow::AI::ApplySuggestion.new(first.suggestion, user: user).reject!
      second = described_class.call(task, mode: "ai_assisted", requested_by: user, challenge: challenge)
      Flow::AI::ApplySuggestion.new(second.suggestion, user: user).reject!
      third = described_class.call(task, mode: "ai_assisted", requested_by: user, challenge: challenge)

      keys = [first, second, third].map { _1.run.idempotency_key }
      expect(keys.uniq.size).to eq(3)
      expect(keys[1]).to end_with(":2")
      expect(keys[2]).to end_with(":3")
    end
  end

  describe "camino de error" do
    around do |example|
      Flow::AI.provider = Flow::AI::Providers::Null.new
      example.run
    ensure
      Flow::AI.reset_provider!
    end

    it "marca el run como fallido con el motivo, sin romper la pantalla" do
      result = described_class.call(task, mode: "ai_assisted", challenge: challenge)

      expect(result).not_to be_ok
      expect(result.run).to be_failed
      expect(result.run.error).to match(/deshabilitado/)
      expect(result.suggestion).to be_nil
    end
  end
end
