# frozen_string_literal: true

require "rails_helper"

RSpec.describe "desafíos", type: :request do
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

  describe "como owner" do
    before { sign_in(owner, company: company) }

    it "lista los desafíos" do
      as_company(company) { create(:challenge, name: "Merma en bodega") }

      get challenges_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Merma en bodega")
    end

    it "crea un desafío y lo manda al builder" do
      post challenges_path, params: {
        challenge: { name: "Nuevo reto", brief: "Un brief", ai_default_mode: "ai_assisted" }
      }

      challenge = as_company(company) { Challenge.find_by(name: "Nuevo reto") }
      expect(challenge).to be_present
      expect(response).to redirect_to(builder_challenge_path(challenge))
    end

    it "renderiza la vista del desafío con su flujo" do
      challenge = as_company(company) do
        c = create(:challenge, name: "Merma")
        seed_form!(c.steps.create!(kind: "ideation", position: 1, name: "Postulación"))
        c.steps.create!(kind: "selection", position: 2, name: "Corte")
        c
      end

      get challenge_path(challenge)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Postulación", "Corte")
      # La selección sin evaluación previa: el banner de validación tiene que
      # renderizar, no reventar el template.
      expect(response.body).to include("Falta resolver")
    end

    it "renderiza el builder con las props serializadas por el server" do
      challenge = as_company(company) { create(:challenge) }

      get builder_challenge_path(challenge)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-island="pipeline-builder"')
      expect(response.body).to include("packs/pipeline_builder")
    end

    it "no arranca un desafío sin módulo de ideación" do
      challenge = as_company(company) do
        c = create(:challenge)
        c.steps.create!(kind: "evaluation", position: 1)
        c
      end

      post start_challenge_path(challenge)
      expect(as_company(company) { challenge.reload }).to be_draft
      expect(flash[:alert]).to match(/Falta el módulo/)
    end

    it "arranca un desafío válido y activa el primer módulo" do
      challenge = as_company(company) do
        c = create(:challenge)
        seed_form!(c.steps.create!(kind: "ideation", position: 1))
        c.steps.create!(kind: "evaluation", position: 2)
        c
      end

      post start_challenge_path(challenge)
      as_company(company) do
        expect(challenge.reload).to be_running
        expect(challenge.steps.ordered.first).to be_active
      end
    end
  end

  describe "como participante" do
    before { sign_in(participant, company: company) }

    it "ve el índice" do
      get challenges_path
      expect(response).to have_http_status(:ok)
    end

    it "NO puede crear desafíos" do
      get new_challenge_path
      expect(response).to have_http_status(:forbidden)
    end

    it "NO puede abrir el builder" do
      challenge = as_company(company) { create(:challenge) }

      get builder_challenge_path(challenge)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "aislamiento entre empresas" do
    let!(:other_company) { without_tenant { create(:company, slug: "otra") } }

    it "un desafío de otra empresa da 404, no 403" do
      foreign = as_company(other_company) { create(:challenge, name: "Ajeno") }
      sign_in(owner, company: company)

      get challenge_path(foreign)
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include("Ajeno")
    end
  end
end
