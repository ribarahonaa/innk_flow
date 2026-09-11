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
    it "devuelve steps y permisos" do
      as_company(company) { challenge.steps.create!(kind: "ideation", position: 1) }

      get pipeline_path
      expect(response).to have_http_status(:ok)
      expect(json["steps"].map { _1["kind"] }).to eq(%w[ideation])
      expect(json["permissions"]).to include("canEdit" => true, "canReorder" => true)
    end

    # `aiMode: nil` NO es una clave ausente: significa "heredá el modo del
    # desafío", y el panel del builder la usa para preseleccionar esa opción.
    it "manda aiMode aunque valga nil: la ausencia y el nil dicen cosas distintas" do
      as_company(company) { challenge.steps.create!(kind: "ideation", position: 1) }

      get pipeline_path
      expect(json["steps"].first).to have_key("aiMode")
      expect(json["steps"].first["aiMode"]).to be_nil
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
      # La posición ya no viaja en el payload —el builder dibuja el orden del
      # array— pero renumerar sigue siendo lo que hace el server.
      expect(as_company(company) { challenge.steps.reload.ordered.map { _1.position.to_f } }).to eq([1.0, 2.0, 3.0])
      # Ni `settings` ni `name` ni `aiMode` son un segundo camino hacia la
      # configuración, ni siquiera al crear: el módulo nace con los defaults
      # del esquema y con el nombre de su kind, y se configura después en su
      # pantalla. El `min_ideas: 3` y el `aiMode: "ai_auto"` de arriba se
      # ignoran.
      ideation = as_company(company) { challenge.steps.reload.find_by(kind: "ideation") }
      expect(ideation.config).to eq(Flow::StepSettings.defaults("ideation"))
      evaluation = as_company(company) { challenge.steps.reload.find_by(kind: "evaluation") }
      expect(evaluation.ai_mode).to be_nil
      expect(evaluation.name).to eq(I18n.t("flow.kinds.evaluation"))
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
    end

    it "rechaza un segundo módulo de ideación" do
      put pipeline_path, params: {
        lock_version: 0,
        steps: [{ id: nil, kind: "ideation" }, { id: nil, kind: "ideation" }]
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
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

      expect(response).to have_http_status(:unprocessable_content)
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

      expect(response).to have_http_status(:unprocessable_content)
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

      expect(response).to have_http_status(:unprocessable_content)
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

    # `criteriaSetId` ya no es del builder, ni siquiera al crear el módulo:
    # se asigna después, en su pantalla (`steps#update`). Mandarlo en el PUT
    # no rompe el guardado, pero tampoco asigna nada.
    it "el criteriaSetId del builder ya no asigna nada: eso lo hace la pantalla del módulo" do
      put pipeline_path, params: {
        lock_version: 0,
        steps: [
          { id: nil, kind: "ideation" },
          { id: nil, kind: "evaluation", name: "Técnica", criteriaSetId: set.id }
        ]
      }, as: :json

      expect(response).to have_http_status(:ok)
      step = as_company(company) { challenge.steps.reload.find_by(kind: "evaluation") }
      expect(step.criteria_set_id).to be_nil
    end

    it "el módulo usa ESOS criterios al activarse, no los por defecto" do
      put pipeline_path, params: {
        lock_version: 0,
        steps: [{ id: nil, kind: "ideation" },
                { id: nil, kind: "evaluation", name: "Técnica" }]
      }, as: :json

      step = as_company(company) { challenge.steps.reload.find_by(kind: "evaluation") }
      # El set se asigna en la pantalla del módulo, no al crearlo desde el
      # builder.
      patch challenge_step_path(challenge, step), params: { challenge_step: { criteria_set_id: set.id } }

      as_company(company) do
        Flow::Handlers::Base.for(step.reload).activate!

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
