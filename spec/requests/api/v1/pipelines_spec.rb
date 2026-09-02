# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API del pipeline", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }
  let!(:owner) do
    without_tenant do
      u = create(:user, email: "owner@test.dev")
      create(:membership, :owner, company: company, user: u)
      u
    end
  end
  let(:challenge) { as_company(company) { create(:challenge) } }

  def pipeline_path(c = challenge) = "/api/v1/challenges/#{c.slug}/pipeline"
  def json = JSON.parse(response.body)

  before { sign_in(owner, company: company) }

  describe "GET" do
    it "devuelve steps, paleta, floor y permisos" do
      as_company(company) { challenge.steps.create!(kind: "ideation", position: 1) }

      get pipeline_path
      expect(response).to have_http_status(:ok)
      expect(json["steps"].map { _1["kind"] }).to eq(%w[ideation])
      expect(json["insertionFloor"]).to be_nil
      expect(json["permissions"]).to include("canEdit" => true, "canReorder" => true)
    end

    # `aiMode: nil` NO es una clave ausente: significa "heredá el modo del
    # desafío", y el panel del builder la usa para preseleccionar esa opción.
    it "manda aiMode aunque valga nil: la ausencia y el nil dicen cosas distintas" do
      as_company(company) { challenge.steps.create!(kind: "ideation", position: 1) }

      get pipeline_path
      expect(json["steps"].first).to have_key("aiMode")
      expect(json["steps"].first["aiMode"]).to be_nil
      expect(json["steps"].first["effectiveAiMode"]).to eq(challenge.ai_default_mode)
    end

    it "deshabilita «Idear» en la paleta cuando ya está en el flujo" do
      as_company(company) { challenge.steps.create!(kind: "ideation", position: 1) }

      get pipeline_path
      ideation = json["palette"].find { _1["kind"] == "ideation" }
      expect(ideation["disabled"]).to be(true)
    end
  end

  describe "PUT: guardado completo del builder" do
    it "crea los módulos en el orden recibido" do
      put pipeline_path, params: {
        lock_version: 0,
        steps: [
          { id: nil, kind: "ideation", name: "Postulación", settings: { min_ideas: 3 } },
          { id: nil, kind: "evaluation", name: "Técnica", aiMode: "ai_auto", settings: {} },
          { id: nil, kind: "selection", name: "Corte", settings: { cut_mode: "top_n", cut_value: 10 } }
        ]
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["steps"].map { _1["kind"] }).to eq(%w[ideation evaluation selection])
      expect(json["steps"].map { _1["position"] }).to eq([1.0, 2.0, 3.0])
      expect(json["steps"].first["settings"]).to eq("min_ideas" => 3)
      expect(json["steps"].second["effectiveAiMode"]).to eq("ai_auto")
    end

    # El flujo recién armado NO es válido todavía: «Idear» nace sin preguntas y
    # el builder lo dice ahí mismo, en vez de dejar que el desafío arranque con
    # un formulario que nadie definió.
    it "avisa que «Idear» todavía no tiene formulario, y con qué link resolverlo" do
      put pipeline_path, params: {
        lock_version: 0,
        steps: [{ id: nil, kind: "ideation", name: "Postulación" },
                { id: nil, kind: "evaluation", name: "Técnica" }]
      }, as: :json

      expect(json["validation"]["valid"]).to be(false)
      expect(json["validation"]["errors"].join).to include("no tiene formulario")
      expect(json["steps"].first["form"]).to include("count" => 0)
      expect(json["steps"].first["form"]["editUrl"]).to eq("/challenges/#{challenge.slug}/form")
    end

    it "y vuelve a ser válido una vez definidas las preguntas" do
      put pipeline_path, params: {
        lock_version: 0,
        steps: [{ id: nil, kind: "ideation", name: "Postulación" },
                { id: nil, kind: "evaluation", name: "Técnica" }]
      }, as: :json

      as_company(company) { seed_form!(challenge.steps.reload.find(&:ideation?)) }

      get pipeline_path
      expect(json["validation"]["valid"]).to be(true)
      expect(json["steps"].first["form"]).to include("count" => 3, "requiredCount" => 3)
    end

    it "rechaza un segundo módulo de ideación" do
      put pipeline_path, params: {
        lock_version: 0,
        steps: [{ id: nil, kind: "ideation" }, { id: nil, kind: "ideation" }]
      }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["errors"].join).to match(/una sola vez/)
    end

    it "responde 409 si otra persona modificó el flujo mientras tanto" do
      as_company(company) { challenge.update_column(:lock_version, 5) }

      put pipeline_path, params: { lock_version: 0, steps: [] }, as: :json
      expect(response).to have_http_status(:conflict)
      expect(json["errors"].join).to match(/Recargá/)
    end

    it "RECHAZA reordenar cuando el flujo ya arrancó" do
      steps = as_company(company) do
        a = challenge.steps.create!(kind: "ideation", position: 1, status: "completed")
        b = challenge.steps.create!(kind: "evaluation", position: 2, status: "active")
        challenge.update!(status: "running")
        [a, b]
      end

      put pipeline_path, params: {
        lock_version: as_company(company) { challenge.reload.lock_version },
        steps: [{ id: steps[1].id, kind: "evaluation" }, { id: steps[0].id, kind: "ideation" }]
      }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["errors"].join).to match(/ya ejecutados no se pueden reordenar/)
    end

    it "RECHAZA quitar un módulo ya ejecutado" do
      as_company(company) do
        challenge.steps.create!(kind: "ideation", position: 1, status: "completed")
        challenge.update!(status: "running")
      end

      put pipeline_path, params: {
        lock_version: as_company(company) { challenge.reload.lock_version },
        steps: []
      }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["errors"].join).to match(/no se puede quitar/)
    end

    it "PERMITE agregar un módulo al final con el flujo en curso" do
      existing = as_company(company) do
        s = challenge.steps.create!(kind: "ideation", position: 1, status: "active")
        challenge.update!(status: "running")
        s
      end

      put pipeline_path, params: {
        lock_version: as_company(company) { challenge.reload.lock_version },
        steps: [
          { id: existing.id, kind: "ideation" },
          { id: nil, kind: "evaluation", name: "Nueva evaluación" }
        ]
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["steps"].map { _1["kind"] }).to eq(%w[ideation evaluation])
    end

    it "el server revalida el floor aunque el cliente mande otra cosa" do
      # Un cliente manipulado que pide meter un módulo ANTES del ejecutado.
      existing = as_company(company) do
        s = challenge.steps.create!(kind: "ideation", position: 1, status: "completed")
        challenge.update!(status: "running")
        s
      end

      put pipeline_path, params: {
        lock_version: as_company(company) { challenge.reload.lock_version },
        steps: [
          { id: nil, kind: "evolution", name: "Colado" },
          { id: existing.id, kind: "ideation" }
        ]
      }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(as_company(company) { challenge.steps.count }).to eq(1)
    end
  end

  describe "criterios de un módulo de evaluación" do
    let!(:set) do
      as_company(company) do
        s = CriteriaSet.create!(name: "Técnica avanzada")
        s.criteria.create!(key: "impacto", name: "Impacto", weight: 0.5, scale_type: "numeric")
        s.criteria.create!(key: "riesgo", name: "Riesgo", weight: 0.5, scale_type: "numeric")
        s.refresh_status!
        s
      end
    end

    it "expone los sets de la biblioteca para poder elegir uno" do
      get pipeline_path

      names = json["criteriaSets"].map { _1["name"] }
      expect(names).to include("Técnica avanzada")
      expect(json["criteriaSets"].first["criteriaCount"]).to eq(2)
      expect(json["criteriaSets"].first["editUrl"]).to be_present
    end

    it "asigna el set al guardar el flujo" do
      put pipeline_path, params: {
        lock_version: 0,
        steps: [
          { id: nil, kind: "ideation" },
          { id: nil, kind: "evaluation", name: "Técnica", criteriaSetId: set.id }
        ]
      }, as: :json

      expect(response).to have_http_status(:ok)
      evaluation = json["steps"].find { _1["kind"] == "evaluation" }
      expect(evaluation["criteriaSetId"]).to eq(set.id)
      expect(evaluation["criteriaSetName"]).to eq("Técnica avanzada")
    end

    it "el módulo usa ESOS criterios al activarse, no los por defecto" do
      put pipeline_path, params: {
        lock_version: 0,
        steps: [{ id: nil, kind: "ideation" },
                { id: nil, kind: "evaluation", name: "Técnica", criteriaSetId: set.id }]
      }, as: :json

      as_company(company) do
        step = challenge.steps.reload.find_by(kind: "evaluation")
        Flow::Handlers::Base.for(step).activate!

        expect(step.reload.settings["criteria"].map { _1["key"] }).to eq(%w[impacto riesgo])
      end
    end

    it "sin set asignado avisa qué se va a usar y qué salidas hay" do
      as_company(company) do
        seed_form!(challenge.steps.create!(kind: "ideation", position: 1))
        challenge.steps.create!(kind: "evaluation", position: 2, name: "Técnica")
      end

      get pipeline_path
      expect(json["validation"]["warnings"].join).to match(/criterios genéricos/)
      expect(json["validation"]["warnings"].join).to match(/criterios propios de este módulo/)
    end

    # El panel tiene que poder ofrecer las dos formas de tener criterios sin
    # que el editor las adivine: el set de la biblioteca y los propios.
    it "el paso de evaluación viaja con su resumen de criterios y su link" do
      step_id = as_company(company) do
        seed_form!(challenge.steps.create!(kind: "ideation", position: 1))
        challenge.steps.create!(kind: "evaluation", position: 2, name: "Técnica").id
      end

      get pipeline_path
      criteria = json["steps"].last["criteria"]

      expect(criteria).to include("count" => 0, "own" => false)
      expect(criteria["editUrl"]).to eq("/challenges/#{challenge.slug}/steps/#{step_id}/criteria")
    end
  end

  describe "aislamiento entre empresas" do
    it "el pipeline de otra empresa da 404" do
      other = without_tenant { create(:company, slug: "otra") }
      foreign = as_company(other) { create(:challenge) }

      get pipeline_path(foreign)
      expect(response).to have_http_status(:not_found)
    end
  end
end
