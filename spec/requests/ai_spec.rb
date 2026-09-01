# frozen_string_literal: true

require "rails_helper"

RSpec.describe "capa de IA", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }
  let!(:owner) do
    without_tenant do
      u = create(:user, email: "owner@test.dev")
      create(:membership, :owner, company: company, user: u)
      u
    end
  end
  let!(:participant) do
    without_tenant do
      u = create(:user, email: "part@test.dev")
      create(:membership, company: company, user: u, role: "participant")
      u
    end
  end

  let!(:challenge) do
    as_company(company) { create(:challenge, name: "Merma", brief: "Reducir merma.", ai_default_mode: "ai_assisted") }
  end

  describe "disparar una tarea" do
    before { sign_in(owner, company: company) }

    it "en modo assisted deja la propuesta para revisar" do
      post challenge_ai_requests_path(challenge, purpose: "propose_pipeline")

      as_company(company) do
        expect(AiRun.count).to eq(1)
        expect(AiSuggestion.pending_review.count).to eq(1)
        expect(challenge.steps.reload).to be_empty
      end
      expect(flash[:notice]).to match(/Revisá la propuesta/)
    end

    it "en modo auto aplica sola" do
      as_company(company) { challenge.update!(ai_default_mode: "ai_auto") }

      post challenge_ai_requests_path(challenge, purpose: "propose_pipeline")

      as_company(company) do
        expect(challenge.steps.reload.count).to eq(7)
        expect(AiSuggestion.first).to be_accepted
      end
      expect(flash[:notice]).to match(/aplicó automáticamente/)
    end

    it "la propuesta aparece en la pantalla del desafío" do
      post challenge_ai_requests_path(challenge, purpose: "propose_pipeline")
      get challenge_path(challenge)

      expect(response.body).to include("Propuestas de la IA")
      expect(response.body).to include("Postulación de ideas → Ronda de feedback")
    end
  end

  describe "revisar la propuesta" do
    let(:suggestion) do
      as_company(company) do
        task = Flow::AI::Tasks::ProposePipeline.new(challenge: challenge)
        Flow::AI::Runner.call(task, mode: "ai_assisted", challenge: challenge).suggestion
      end
    end

    it "aplicar la ejecuta sobre el dominio" do
      sign_in(owner, company: company)
      post accept_ai_suggestion_path(suggestion)

      as_company(company) do
        expect(challenge.steps.reload.count).to eq(7)
        expect(suggestion.reload).to be_accepted
        expect(suggestion.reviewed_by_id).to eq(owner.id)
      end
    end

    it "descartar no toca nada" do
      sign_in(owner, company: company)
      post reject_ai_suggestion_path(suggestion)

      as_company(company) do
        expect(challenge.steps.reload).to be_empty
        expect(suggestion.reload).to be_rejected
      end
    end

    it "un participante NO puede aplicar propuestas del desafío" do
      sign_in(participant, company: company)
      post accept_ai_suggestion_path(suggestion)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "el modo human no ofrece IA" do
    before do
      as_company(company) do
        challenge.update!(ai_default_mode: "human")
        challenge.steps.create!(kind: "ideation", position: 1)
      end
      sign_in(owner, company: company)
    end

    it "la pantalla del desafío no muestra botones de IA" do
      get challenge_path(challenge)
      expect(response.body).not_to include("Proponer el flujo")
    end
  end

  describe "auditoría" do
    before do
      as_company(company) do
        task = Flow::AI::Tasks::ProposePipeline.new(challenge: challenge)
        Flow::AI::Runner.call(task, mode: "ai_assisted", challenge: challenge, requested_by: owner)
      end
      sign_in(owner, company: company)
    end

    it "lista las llamadas con costo y latencia" do
      get ai_runs_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Auditoría de IA", "Proponer el flujo", "fixture")
    end

    it "el detalle muestra prompt y respuesta" do
      run = as_company(company) { AiRun.first }
      get ai_run_path(run)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Prompt", "Respuesta")
    end

    it "un participante no accede a la auditoría" do
      sign_in(participant, company: company)
      get ai_runs_path
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "aislamiento entre empresas" do
    it "no se puede aplicar una sugerencia de otra empresa" do
      other = without_tenant { create(:company, slug: "otra") }
      foreign = as_company(other) do
        c = create(:challenge, brief: "x")
        Flow::AI::Runner.call(Flow::AI::Tasks::ProposePipeline.new(challenge: c),
                              mode: "ai_assisted", challenge: c).suggestion
      end

      sign_in(owner, company: company)
      post accept_ai_suggestion_path(foreign)
      expect(response).to have_http_status(:not_found)
    end
  end
end
