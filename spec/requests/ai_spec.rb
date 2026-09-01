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

    it "la propuesta aparece en el builder, que es donde se arma el flujo" do
      post challenge_ai_requests_path(challenge, purpose: "propose_pipeline")
      get builder_challenge_path(challenge)

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

  # El modo define cómo se trabaja DENTRO del desafío. Armar el flujo es una
  # acción de autoría del dueño, y ahí el modo no manda.
  describe "asistencia para armar el flujo, con el desafío en modo human" do
    before do
      as_company(company) { challenge.update!(ai_default_mode: "human") }
      sign_in(owner, company: company)
    end

    it "el builder OFRECE pedirle el flujo a la IA igual" do
      get builder_challenge_path(challenge)

      expect(response.body).to include("Armar el flujo con IA")
      expect(response.body).to include("Proponer el flujo")
      expect(response.body).to include("La propuesta pasa por tu revisión")
    end

    it "el pedido funciona y deja la propuesta para revisar" do
      post challenge_ai_requests_path(challenge, purpose: "propose_pipeline")

      as_company(company) do
        expect(AiSuggestion.pending_review.count).to eq(1)
        # Nunca se auto-aplica: un desafío "solo personas" no delega decisiones.
        expect(challenge.steps.reload).to be_empty
        expect(AiRun.first.mode).to eq("ai_assisted")
      end
    end

    it "dentro de un módulo en modo human NO se ofrece IA" do
      step = as_company(company) do
        s = challenge.steps.create!(kind: "ideation", position: 1)
        challenge.pipeline.start!
        s
      end

      get challenge_step_path(challenge, step)
      expect(response.body).not_to include("Proponer campos")
    end
  end

  describe "el builder con el flujo ya arrancado" do
    before do
      as_company(company) do
        challenge.steps.create!(kind: "ideation", position: 1, status: "completed")
        challenge.update!(status: "running")
      end
      sign_in(owner, company: company)
    end

    it "explica por qué no se puede reemplazar el flujo, en vez de esconder el botón" do
      get builder_challenge_path(challenge)

      expect(response.body).to include("Armar el flujo con IA")
      expect(response.body).to include("El flujo ya arrancó")
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
RSpec.describe "la IA evaluando", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }
  let!(:owner) do
    without_tenant do
      u = create(:user, email: "owner@test.dev")
      create(:membership, :owner, company: company, user: u)
      u
    end
  end

  let(:set) do
    as_company(company) do
      s = CriteriaSet.create!(name: "Técnica")
      s.criteria.create!(key: "impacto", name: "Impacto", weight: 0.4, source: "manual",
                         scale_type: "numeric", scale_config: { "min" => 1, "max" => 10 }, position: 0)
      s.criteria.create!(key: "factibilidad", name: "Factibilidad", weight: 0.35, source: "manual",
                         scale_type: "numeric", scale_config: { "min" => 1, "max" => 10 }, position: 1)
      s.criteria.create!(key: "esfuerzo", name: "Esfuerzo", weight: 0.25, source: "manual",
                         scale_type: "numeric", scale_config: { "min" => 1, "max" => 10 }, position: 2)
      s.refresh_status!
      s
    end
  end

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma", ai_default_mode: "ai_assisted")
      c.steps.create!(kind: "ideation", position: 1, status: "completed")
      c.steps.create!(kind: "evaluation", position: 2, name: "Técnica", criteria_set: set)
      c.update!(status: "running")
      c
    end
  end
  let(:step) { as_company(company) { challenge.steps.find_by(kind: "evaluation") } }

  let!(:idea) do
    as_company(company) do
      i = create(:idea, challenge: challenge, author: owner, status: "active")
      Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" }, author: owner).call
      i.update!(submitted_at: Time.current)
      Flow::Handlers::Base.for(challenge.steps.find_by(kind: "evaluation")).activate!
      i
    end
  end

  before { sign_in(owner, company: company) }

  it "en modo asistido la pantalla OFRECE pedirle una evaluación" do
    get challenge_step_path(challenge, step)

    expect(response.body).to include("Pedirle una evaluación a la IA")
  end

  it "la ficha de evaluación ofrece que la IA te guíe" do
    get new_challenge_step_assessment_path(challenge, step, idea_id: idea.id)

    expect(response.body).to include("¿Querés que la IA te guíe?")
    expect(response.body).to include("Pedir la guía de la IA")
  end

  it "pedirla produce una evaluación que entra al promedio" do
    post challenge_ai_requests_path(challenge, purpose: "evaluate_idea", step_id: step.id, idea_id: idea.id)

    as_company(company) do
      assessment = step.assessments.reload.first
      expect(assessment).to be_by_ai
      expect(assessment.normalized_score).to be_present
      expect(step.step_entries.find_by(idea_id: idea.id).result["score"]).to be_present
    end
  end

  describe "la IA como guía en la ficha" do
    before { post challenge_ai_requests_path(challenge, purpose: "evaluate_idea", step_id: step.id, idea_id: idea.id) }

    it "muestra el valor y la razón JUNTO A CADA criterio" do
      get new_challenge_step_assessment_path(challenge, step, idea_id: idea.id)

      # El valor de cada criterio, pegado al criterio y no en un bloque aparte.
      expect(response.body).to include("ai-hint")
      expect(response.body).to include("diferencia de inventario")   # razón de impacto
      expect(response.body).to include("Requiere integración con el WMS") # razón de factibilidad
      expect(response.body).not_to include("Pedir la guía de la IA")
    end

    it "marca en la escala el valor que pondría la IA" do
      get new_challenge_step_assessment_path(challenge, step, idea_id: idea.id)

      expect(response.body).to include("scale-radio--suggested")
      expect(response.body).to include("La IA pondría 8")
    end

    it "ofrece precargar el formulario, sin hacerlo solo" do
      get new_challenge_step_assessment_path(challenge, step, idea_id: idea.id)

      expect(response.body).to include("Precargar con los valores de la IA")
      # Sin precargar, ningún radio viene marcado.
      expect(response.body).not_to match(/name="scores\[impacto\]"[^>]*checked/)
    end

    it "con prefill deja los valores puestos y avisa que la evaluación es tuya" do
      get new_challenge_step_assessment_path(challenge, step, idea_id: idea.id, prefill: "ai")

      expect(response.body).to match(/value="8"[^>]*checked/)
      expect(response.body).to include("la evaluación queda a tu nombre")
    end

    it "el evaluador puede guardar valores distintos a los sugeridos" do
      post challenge_step_assessments_path(challenge, step),
           params: { idea_id: idea.id, scores: { impacto: "3", factibilidad: "3", esfuerzo: "9" },
                     overall_comment: "No coincido con la IA" }

      as_company(company) do
        mine = step.assessments.current.submitted_ones.detect { |a| a.evaluator_id == owner.id }
        expect(mine.assessment_scores.find_by(criterion_key: "impacto").raw_value).to eq("3")
        expect(step.assessments.count).to eq(2), "la de la IA se conserva junto a la mía"
      end
    end
  end

  it "la pantalla del módulo muestra la evaluación con su justificación" do
    post challenge_ai_requests_path(challenge, purpose: "evaluate_idea", step_id: step.id, idea_id: idea.id)

    get challenge_step_path(challenge, step)

    expect(response.body).to include("Evaluaciones hechas")
    expect(response.body).to include("diferencia de inventario")
  end

  it "en modo human no se ofrece" do
    as_company(company) { step.update!(ai_mode: "human") }

    get challenge_step_path(challenge, step)
    expect(response.body).not_to include("Pedirle una evaluación a la IA")
  end
end
RSpec.describe "cambiar el modo de IA de un módulo en curso", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }
  let!(:owner) do
    without_tenant do
      u = create(:user, email: "owner@test.dev")
      create(:membership, :owner, company: company, user: u)
      u
    end
  end
  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, ai_default_mode: "human")
      c.steps.create!(kind: "ideation", position: 1, status: "completed")
      c.steps.create!(kind: "evaluation", position: 2, name: "Comité", ai_mode: "human", status: "active")
      c.update!(status: "running")
      c
    end
  end
  let(:step) { as_company(company) { challenge.steps.find_by(kind: "evaluation") } }

  before { sign_in(owner, company: company) }

  it "la pantalla explica cómo habilitar la IA cuando está en «Solo personas»" do
    get challenge_step_path(challenge, step)

    expect(response.body).to include("Modo de IA")
    expect(response.body).to include("la IA no interviene en este módulo")
    expect(response.body).to include("IA asistida")
  end

  it "se puede cambiar el modo sin reiniciar el módulo" do
    patch challenge_step_path(challenge, step), params: { challenge_step: { ai_mode: "ai_assisted" } }

    as_company(company) do
      expect(step.reload.ai_mode).to eq("ai_assisted")
      expect(step).to be_active, "el módulo sigue en curso"
    end
  end

  it "cambiado el modo, la IA aparece disponible" do
    as_company(company) do
      idea = create(:idea, challenge: challenge, author: owner, status: "active")
      Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => "Una idea" }, author: owner).call
      idea.update!(submitted_at: Time.current)
      step.step_entries.create!(idea: idea, input_version_id: idea.current_version_id, entered_at: Time.current)
      step.update!(resolved_config: { "criteria" => [], "min_assessments" => 1 })
    end

    get challenge_step_path(challenge, step)
    expect(response.body).not_to include("Pedirle una evaluación a la IA")

    patch challenge_step_path(challenge, step), params: { challenge_step: { ai_mode: "ai_assisted" } }
    get challenge_step_path(challenge, step)

    expect(response.body).to include("Pedirle una evaluación a la IA")
  end

  it "lo estructural sigue congelado" do
    as_company(company) do
      step.kind = "selection"
      expect(step).not_to be_valid
      expect(step.errors.full_messages.join).to match(/ya ejecutado no se puede modificar/)
    end
  end

  it "un participante no puede cambiarlo" do
    otro = without_tenant do
      u = create(:user, email: "p@test.dev")
      create(:membership, company: company, user: u, role: "participant")
      u
    end
    sign_in(otro, company: company)

    patch challenge_step_path(challenge, step), params: { challenge_step: { ai_mode: "ai_auto" } }

    expect(response).to have_http_status(:forbidden)
    expect(as_company(company) { step.reload.ai_mode }).to eq("human")
  end
end
