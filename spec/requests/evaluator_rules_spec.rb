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
end
