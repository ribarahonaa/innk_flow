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
    it "un pedido idéntico no vuelve a llamar al proveedor" do
      first = described_class.call(task, mode: "ai_assisted", challenge: challenge)

      expect { described_class.call(task, mode: "ai_assisted", challenge: challenge) }
        .not_to change { AiRun.count }

      second = described_class.call(task, mode: "ai_assisted", challenge: challenge)
      expect(second.run.id).to eq(first.run.id)
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
