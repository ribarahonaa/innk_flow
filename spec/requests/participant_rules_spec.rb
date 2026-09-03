# frozen_string_literal: true

require "rails_helper"

# Las reglas del rol participante.
RSpec.describe "reglas de quien participa", type: :request do
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
  let!(:paula) { member("paula@test.dev", :participant) }
  let!(:pedro) { member("pedro@test.dev", :participant) }

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma", ai_default_mode: "human")
      seed_form!(c.steps.create!(kind: "ideation", position: 1))
      c.steps.create!(kind: "evolution", position: 2, name: "Ronda")
      c.steps.create!(kind: "evaluation", position: 3, name: "Técnica",
                      config: { "min_assessments" => 1 })
      c
    end
  end

  def step_named(name) = as_company(company) { challenge.steps.reload.find_by(name: name) }

  def idea_de(autor, titulo)
    as_company(company) do
      i = create(:idea, challenge: challenge, author: autor)
      Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => titulo }, author: autor).call
      i.update!(submitted_at: Time.current)
      i
    end
  end

  let!(:mia) { idea_de(paula, "La idea de Paula") }
  let!(:ajena) { idea_de(pedro, "La idea de Pedro") }

  before { as_company(company) { challenge.pipeline.start!; challenge.pipeline.advance! } }

  describe "feedback" do
    before { sign_in(paula, company: company) }

    it "puede comentar la suya" do
      expect do
        post challenge_step_feedback_items_path(challenge, step_named("Ronda")),
             params: { idea_id: mia.id, kind: "suggestion", body: "Me falta el costeo." }
      end.to change { as_company(company) { FeedbackItem.count } }.by(1)
    end

    # El ida y vuelta entre autores que compiten por el mismo corte no es
    # feedback, es negociación.
    it "pero no la de otro autor" do
      expect do
        post challenge_step_feedback_items_path(challenge, step_named("Ronda")),
             params: { idea_id: ajena.id, kind: "suggestion", body: "Cambiala." }
      end.not_to change { as_company(company) { FeedbackItem.count } }
    end

    it "y la pantalla no le ofrece la caja donde no puede" do
      get challenge_step_path(challenge, step_named("Ronda"))

      expect(response.body).to include("La idea de Paula", "La idea de Pedro")
      # Una sola caja de comentar: la de su propia idea.
      expect(response.body.scan(%(class="feedback-form")).size).to eq(1)
    end

    it "quien evalúa sí puede comentar cualquiera" do
      sign_in(elena, company: company)

      expect do
        post challenge_step_feedback_items_path(challenge, step_named("Ronda")),
             params: { idea_id: ajena.id, kind: "suggestion", body: "Acotala." }
      end.to change { as_company(company) { FeedbackItem.count } }.by(1)
    end
  end

  describe "los puntajes" do
    before do
      as_company(company) do
        challenge.pipeline.advance!
        evaluacion = challenge.steps.reload.find_by(name: "Técnica")
        [mia, ajena].each do |idea|
          evaluacion.assessments.create!(idea: idea, idea_version_id: idea.current_version_id,
                                         evaluator: elena, actor_type: "human", status: "submitted",
                                         submitted_at: Time.current, normalized_score: 0.58)
          evaluacion.handler.recompute_entry!(StepEntry.find_by(challenge_step_id: evaluacion.id,
                                                                idea_id: idea.id))
        end
        evaluacion.update_column(:status, "completed")
      end
      sign_in(paula, company: company)
    end

    # Ver el nombre de quien te puntuó bajo y su comentario convierte un
    # resultado en una discusión personal.
    it "no ve quién puso qué, ni siquiera con el módulo cerrado" do
      get challenge_step_path(challenge, step_named("Técnica"))

      expect(response.body).not_to include(elena.name)
      expect(response.body).not_to include("Evaluaciones hechas")
    end

    it "pero sí el resultado de SU idea, en su ficha" do
      get challenge_idea_path(challenge, mia)

      expect(response.body).to include("Cómo le fue", "Técnica", "58%")
    end

    it "y no el de la ajena" do
      get challenge_idea_path(challenge, ajena)

      expect(response.body).to include("Cómo le fue")
      expect(response.body).not_to include("58%")
    end

    # El reporte trae el ranking entero: es justo lo que no ve en pantalla.
    it "no puede generar el reporte" do
      post challenge_step_reports_path(challenge, step_named("Técnica")), params: { kind: "summary" }

      expect(response).to have_http_status(:forbidden).or have_http_status(:found)
    end
  end
end
