# frozen_string_literal: true

require "rails_helper"

# Las dos reglas del rol evaluador.
RSpec.describe "reglas de quien evalúa", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email, role)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, role.to_sym, company: company, user: u)
      u
    end
  end

  let!(:admin) { member("admin@test.dev", :admin) }
  let!(:elena) { member("elena@test.dev", :evaluator) }
  let!(:emilio) { member("emilio@test.dev", :evaluator) }

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma", ai_default_mode: "human")
      seed_form!(c.steps.create!(kind: "ideation", position: 1))
      c.steps.create!(kind: "evaluation", position: 2, name: "Técnica",
                      config: { "min_assessments" => 3 })
      c
    end
  end

  def step = as_company(company) { challenge.steps.reload.find(&:evaluation?) }

  def idea_de(autor, titulo)
    as_company(company) do
      i = create(:idea, challenge: challenge, author: autor)
      Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => titulo }, author: autor).call
      i.update!(submitted_at: Time.current)
      i
    end
  end

  let!(:paula) { member("paula@test.dev", :participant) }

  let!(:propia) { idea_de(elena, "La idea de Elena") }
  let!(:ajena) { idea_de(paula, "La idea de Paula") }

  before do
    as_company(company) do
      challenge.pipeline.start!
      challenge.pipeline.advance!
    end
  end

  describe "postular y evaluar en el mismo desafío" do
    before { sign_in(elena, company: company) }

    it "puede postular una idea" do
      get new_challenge_idea_path(challenge)
      expect(response).to have_http_status(:ok)
    end

    it "y evaluar las ajenas" do
      get new_challenge_step_assessment_path(challenge, step, idea_id: ajena.id)
      expect(response).to have_http_status(:ok)
    end

    # Puntuarse a uno mismo no es una evaluación.
    it "pero NO la suya" do
      get new_challenge_step_assessment_path(challenge, step, idea_id: propia.id)
      expect(response).to have_http_status(:forbidden).or have_http_status(:found)
    end

    it "la pantalla lo dice en vez de ofrecer un botón que rebota" do
      get challenge_step_path(challenge, step)
      expect(response.body).to include("Es tu idea")
    end
  end

  # El conflicto de interés no depende del rol.
  it "quien administra tampoco evalúa una idea propia" do
    del_admin = idea_de(admin, "La idea del admin")
    sign_in(admin, company: company)

    get new_challenge_step_assessment_path(challenge, step, idea_id: del_admin.id)
    expect(response).to have_http_status(:forbidden).or have_http_status(:found)

    get new_challenge_step_assessment_path(challenge, step, idea_id: ajena.id)
    expect(response).to have_http_status(:ok)
  end

  describe "el mínimo por idea" do
    # Evalúan tres —Elena, Emilio y el admin— y el módulo pide 3. Para la idea
    # de Elena solo quedan dos posibles: esperar 3 dejaría el módulo trabado
    # esperando una evaluación que no puede existir.
    it "descuenta a quien no puede evaluar esa idea" do
      as_company(company) do
        handler = step.handler
        expect(handler.min_assessments_for(propia)).to eq(2)
      end
    end

    # Paula no evalúa —es participante—, así que nadie queda bloqueado y el
    # mínimo del módulo se respeta entero.
    it "y no lo toca cuando el autor no evalúa igual" do
      as_company(company) do
        expect(step.handler.min_assessments_for(ajena)).to eq(3)
      end
    end
  end

  describe "evaluación a ciegas" do
    before do
      as_company(company) do
        a = step.assessments.create!(idea: ajena, idea_version_id: ajena.current_version_id,
                                     evaluator: emilio, actor_type: "human",
                                     status: "submitted", submitted_at: Time.current,
                                     normalized_score: 0.8)
        a
      end
    end

    it "no muestra los puntajes ajenos antes de enviar el propio" do
      sign_in(elena, company: company)
      get challenge_step_path(challenge, step)

      expect(response.body).to include("se muestran cuando envíes tu evaluación",
                                       "oculto")
      expect(response.body).not_to include(emilio.name)
    end

    it "y sí después" do
      as_company(company) do
        step.assessments.create!(idea: ajena, idea_version_id: ajena.current_version_id,
                                 evaluator: elena, actor_type: "human",
                                 status: "submitted", submitted_at: Time.current,
                                 normalized_score: 0.5)
      end

      sign_in(elena, company: company)
      get challenge_step_path(challenge, step)

      expect(response.body).to include(emilio.name)
    end

    # Quien administra necesita ver cómo viene el módulo para poder cerrarlo.
    it "quien administra las ve siempre" do
      sign_in(admin, company: company)
      get challenge_step_path(challenge, step)

      expect(response.body).to include(emilio.name)
      expect(response.body).not_to include("ancla el juicio")
    end
  end

  # Pedirle a la IA que evalúe todo lo que falta.
  #
  # Dos cosas que se rompen fácil y por eso están acá: que el botón sea de
  # quien EVALÚA y no solo de quien administra, y que alcance también a las
  # ideas de quien pide —pedirle a la IA no es evaluar, y si no el módulo se
  # traba esperando una evaluación que nadie puede hacer—.
  describe "evaluar todas con IA" do
    before do
      as_company(company) { step.update!(ai_mode: "ai_assisted") }
    end

    it "se lo ofrece a quien evalúa, no solo a quien administra" do
      sign_in(elena, company: company)
      get challenge_step_path(challenge, step)

      expect(response.body).to include("Evaluar 2 ideas con IA")
    end

    it "no se lo ofrece a quien ni evalúa ni administra" do
      sign_in(paula, company: company)
      get challenge_step_path(challenge, step)

      expect(response.body).not_to include("Evaluar 2 ideas con IA")
    end

    it "encola una corrida por idea y por pasada, sin llamar al proveedor" do
      sign_in(elena, company: company)

      expect do
        post evaluate_all_challenge_step_path(challenge, step)
      end.to change { enqueued_jobs.count { |j| j[:job] == Flow::AI::RunJob } }.by(6)

      expect(flash[:notice]).to include("2 ideas")
    end

    # La suya entre ellas: el mínimo por idea ya cuenta a la IA justamente
    # para eso, así que dejarla afuera trabaría el módulo.
    it "incluye la idea de quien pide" do
      sign_in(elena, company: company)
      post evaluate_all_challenge_step_path(challenge, step)

      corridas = enqueued_jobs.select { |j| j[:job] == Flow::AI::RunJob }
      expect(corridas.map { |j| j[:args].last["idea_id"] }).to include(propia.id)
    end

    it "a quien no evalúa el módulo le rebota" do
      sign_in(paula, company: company)
      post evaluate_all_challenge_step_path(challenge, step)

      expect(response).to have_http_status(:forbidden)
    end
  end

  # Una propuesta de evaluación de la IA que quedó pendiente, revisada por
  # alguien que ya no tiene acceso a lo que evalúa pero conserva su asignación.
  #
  # `accept?` para una evaluación termina en `AssessmentPolicy#create?` sin
  # idea, que sólo preguntaba por la asignación: ni si llega al desafío, ni si
  # ve la idea. Y el camino de las propuestas no pasa por el `policy_scope`
  # que sí tienen los de evaluar a mano. Aplicar una propuesta así escribe una
  # evaluación —con el payload que quien acepta quiera mandar— sobre algo que
  # para esa persona da 404.
  describe "revisar una propuesta de evaluación sin acceso a lo que evalúa" do
    def propuesta_pendiente(idea)
      as_company(company) do
        task = Flow::AI::Tasks::EvaluateIdea.new(challenge: challenge, step: step, idea: idea)
        Flow::AI::Runner.call(task, mode: "ai_assisted", challenge: challenge, step: step, idea: idea).suggestion
      end
    end

    it "quien acompañaba el desafío y ya no, no la aplica" do
      gina = without_tenant do
        u = create(:user, email: "gina@test.dev")
        create(:membership, :gestor, company: company, user: u)
        u
      end
      as_company(company) do
        gestora = ChallengeGestor.create!(challenge: challenge, user: gina)
        StepAssignment.create!(challenge_step: step, user: gina, role: "evaluator")
        gestora.destroy!
      end
      propuesta = propuesta_pendiente(ajena)
      antes = as_company(company) { Assessment.where(idea_id: ajena.id).count }

      sign_in(gina, company: company)
      post accept_ai_suggestion_path(propuesta)

      expect(response).to have_http_status(:not_found)
      as_company(company) do
        expect(propuesta.reload).to be_pending
        expect(Assessment.where(idea_id: ajena.id).count).to eq(antes)
      end
    end

    it "quien evaluaba y pasó a participar, no la descarta sobre una idea que no ve" do
      propuesta = propuesta_pendiente(ajena)
      without_tenant { Membership.find_by!(company: company, user: elena).update!(role: "participant") }

      sign_in(elena, company: company)
      post reject_ai_suggestion_path(propuesta)

      expect(response).to have_http_status(:not_found)
      expect(as_company(company) { propuesta.reload }).to be_pending
    end
  end

  # El mismo botón, de a una, en la ficha de evaluación.
  #
  # Es la regla de arriba en la otra pantalla, y ahí se escribió a mano con
  # `update_pipeline?`: un evaluador asignado PODÍA pedirlo —lo autoriza
  # `AssessmentPolicy#create?`, igual que el lote— y nunca veía el botón.
  describe "pedir la guía de la IA para una idea" do
    before do
      as_company(company) { step.update!(ai_mode: "ai_assisted") }
    end

    it "se lo ofrece a quien evalúa, no solo a quien administra" do
      sign_in(elena, company: company)
      get new_challenge_step_assessment_path(challenge, step, idea_id: ajena.id)

      expect(response.body).to include("Pedir la guía de la IA")
    end

    it "y también a quien administra" do
      sign_in(admin, company: company)
      get new_challenge_step_assessment_path(challenge, step, idea_id: ajena.id)

      expect(response.body).to include("Pedir la guía de la IA")
    end
  end
end
