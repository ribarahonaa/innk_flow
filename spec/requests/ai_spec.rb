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
      expect(flash[:ia]["mensaje"]).to match(/Revisá la propuesta/)
    end

    it "en modo auto aplica sola" do
      as_company(company) { challenge.update!(ai_default_mode: "ai_auto") }

      post challenge_ai_requests_path(challenge, purpose: "propose_pipeline")

      as_company(company) do
        expect(challenge.steps.reload.count).to eq(7)
        expect(AiSuggestion.first).to be_accepted
      end
      expect(flash[:ia]["mensaje"]).to match(/aplicó automáticamente/)
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

    # Lo que sí se aplicó lo dice así. El aviso se bifurcó cuando las
    # propuestas informativas pasaron a decir «Listo.» —no aplican nada— y
    # esta mitad se quedó sin una sola aserción: invertir el predicado dejaba
    # la suite entera en verde.
    it "y lo dice" do
      sign_in(owner, company: company)
      post accept_ai_suggestion_path(suggestion)

      expect(flash[:notice]).to eq("Sugerencia aplicada.")
    end

    it "descartar no toca nada" do
      sign_in(owner, company: company)
      post reject_ai_suggestion_path(suggestion)

      as_company(company) do
        expect(challenge.steps.reload).to be_empty
        expect(suggestion.reload).to be_rejected
      end
    end

    # 404 y no 403: una propuesta del flujo no le aparece en ningún lado —el
    # panel filtra por `accept?` y la auditoría es de quien administra—, así
    # que un 403 le confirmaría que existe. Ver el desafío no alcanza.
    it "un participante NO puede aplicar propuestas del desafío" do
      sign_in(participant, company: company)
      post accept_ai_suggestion_path(suggestion)

      expect(response).to have_http_status(:not_found)
      expect(as_company(company) { suggestion.reload }).to be_pending
    end

    # Pedir y aceptar tienen que preguntar lo mismo. Pedirla sobre un desafío
    # cerrado ya rebotaba (`update_pipeline?`); aceptarla no, porque la policy
    # le daba `true` a quien administra antes de mirar nada más, y una
    # propuesta que quedó pendiente se aplicaba igual.
    it "con el desafío cerrado, quien administra tampoco la aplica" do
      as_company(company) { suggestion && challenge.pipeline.close! }
      sign_in(owner, company: company)

      post accept_ai_suggestion_path(suggestion)

      expect(response).to have_http_status(:forbidden)
      expect(as_company(company) { suggestion.reload }).to be_pending
    end

    it "y el panel no se la ofrece" do
      as_company(company) { suggestion && challenge.pipeline.close! }
      sign_in(owner, company: company)

      get challenge_path(challenge)

      expect(response.body).not_to include(accept_ai_suggestion_path(suggestion))
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
        s = seed_form!(challenge.steps.create!(kind: "ideation", position: 1))
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
        seed_form!(challenge.steps.create!(kind: "ideation", position: 1, status: "completed"))
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

    # La pantalla existe y no puede entrar: eso es un 403 legítimo. Pero una
    # corrida por id no la ve, y un 403 le confirmaría que existe —el scope
    # estaba vacío, así que la encontraba y rebotaba recién en el `authorize`—.
    it "ni le confirma que existe una corrida" do
      run = as_company(company) { AiRun.first }
      sign_in(participant, company: company)

      estados = [run.id, SecureRandom.uuid].map do |id|
        get ai_run_path(id)
        response.status
      end

      expect(estados).to eq([404, 404])
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

  # Pedir algo a la IA no recarga la pantalla: la respuesta reemplaza el marco
  # de las propuestas. Salvo cuando el pedido YA cambió el dominio —en «IA
  # automática» la sugerencia se auto-acepta— porque ahí el resto de la
  # pantalla queda mostrando lo viejo, y hay que recargar a mano para ver la
  # idea reescrita.
  describe "a dónde responde el pedido" do
    let!(:ideation) do
      as_company(company) do
        paso = seed_form!(challenge.steps.create!(kind: "ideation", position: 1))
        challenge.pipeline.start!
        paso
      end
    end

    before { sign_in(owner, company: company) }

    it "con revisión humana, solo al marco de las propuestas" do
      as_company(company) { ideation.reload.update!(ai_mode: "ai_assisted") }

      get challenge_step_path(challenge, ideation)

      expect(response.body).to include('data-turbo-frame="ai-suggestions"')
      expect(response.body).not_to include('data-turbo-frame="_top"')
    end

    it "en automático, a la pantalla entera: el cambio ya está hecho" do
      as_company(company) { ideation.reload.update!(ai_mode: "ai_auto") }

      get challenge_step_path(challenge, ideation)

      expect(response.body).to include('data-turbo-frame="_top"')
    end
  end

  # Todo pedido a la IA exigía `update_pipeline?`, que es solo administración:
  # quien participa no podía usar ninguna función de IA, ni siquiera sobre su
  # propia idea, con el botón ahí ofreciéndoselo.
  describe "quién puede pedirle algo a la IA" do
    let!(:ideation) do
      as_company(company) do
        paso = seed_form!(challenge.steps.create!(kind: "ideation", position: 1))
        challenge.steps.create!(kind: "evolution", position: 2)
        challenge.pipeline.start!
        paso
      end
    end

    let!(:propia) do
      as_company(company) do
        i = create(:idea, challenge: challenge, author: participant, status: "active")
        Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" }, author: participant).call
        i.update!(submitted_at: Time.current)
        i
      end
    end

    let!(:ajena) do
      as_company(company) do
        otro = Flow::Tenant.bypass! { create(:user, email: "otro@test.dev") }
        i = create(:idea, challenge: challenge, author: otro, status: "active")
        Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Cámaras" }, author: otro).call
        i.update!(submitted_at: Time.current)
        i
      end
    end

    before do
      # Su autora puede editar la idea en borrador o con una ronda de evolución
      # abierta. Fuera de esas dos ventanas no se edita en caliente, y pedirle
      # a la IA que la reescriba tampoco.
      as_company(company) { challenge.pipeline.advance! }
      sign_in(participant, company: company)
    end

    it "sobre su propia idea, quien participa sí" do
      post challenge_ai_requests_path(challenge, purpose: "coauthor_field", idea_id: propia.id,
                                      step_id: ideation.id, field_key: "titulo")

      expect(response).to have_http_status(:found)
      expect(flash[:ia]["tipo"]).to eq("ok")
    end

    # 404 y no 403: la idea ajena no la ve, y un 403 le confirmaría que
    # existe. Este spec aceptaba 403, que era justamente el oráculo.
    it "sobre la idea de otra persona, no" do
      post challenge_ai_requests_path(challenge, purpose: "coauthor_field", idea_id: ajena.id,
                                      step_id: ideation.id, field_key: "titulo")

      expect(response).to have_http_status(:not_found)
      expect(as_company(company) { AiRun.where(idea_id: ajena.id).count }).to be_zero
    end

    # Lo que configura el DESAFÍO sigue siendo de quien administra.
    it "y armar el flujo tampoco" do
      post challenge_ai_requests_path(challenge, purpose: "propose_pipeline")

      expect(response).to have_http_status(:forbidden).or have_http_status(:found)
      expect(as_company(company) { AiRun.where(purpose: "propose_pipeline").count }).to be_zero
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
      seed_form!(c.steps.create!(kind: "ideation", position: 1, status: "completed"))
      c.steps.create!(kind: "evaluation", position: 2, name: "Técnica", criteria_set: set)
      c.update!(status: "running")
      c
    end
  end
  let(:step) { as_company(company) { challenge.steps.find_by(kind: "evaluation") } }

  # El autor NO es quien evalúa: nadie puntúa una idea de la que participa.
  let!(:autora) do
    without_tenant do
      u = create(:user, email: "autora@test.dev")
      create(:membership, company: company, user: u)
      u
    end
  end

  let!(:idea) do
    as_company(company) do
      i = create(:idea, challenge: challenge, author: autora, status: "active")
      Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" }, author: autora).call
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

    desglose = Nokogiri::HTML(response.body).css(".fila-de-idea__desglose").text
    expect(desglose).to include("diferencia de inventario")
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
      seed_form!(c.steps.create!(kind: "ideation", position: 1, status: "completed"))
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

  # El `<select>` de «Heredar del desafío» manda `ai_mode=""`, no `nil` —es
  # HTML, un `<option>` sin `value`—, y la validación de `inclusion` con
  # `allow_nil: true` no perdonaba el string vacío: elegir «Heredar» no
  # guardaba nada, sin ningún error visible en ninguna vista.
  it "elegir «Heredar del desafío» sí guarda, aunque el select mande vacío" do
    as_company(company) { step.update!(ai_mode: "ai_assisted") }

    patch challenge_step_path(challenge, step), params: { challenge_step: { ai_mode: "" } }

    as_company(company) { expect(step.reload.ai_mode).to be_nil }
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

