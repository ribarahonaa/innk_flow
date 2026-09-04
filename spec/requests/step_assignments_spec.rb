# frozen_string_literal: true

require "rails_helper"

# Quién evalúa un módulo y cuánto pesa su voto.
#
# `step_assignments` tenía la columna `weight` desde el principio: no entraba
# en ninguna cuenta y no había pantalla donde tocarla.
RSpec.describe "quién evalúa un módulo", type: :request do
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
  let!(:paula) { member("paula@test.dev", :participant) }

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma", ai_default_mode: "human")
      seed_form!(c.steps.create!(kind: "ideation", position: 1))
      c.steps.create!(kind: "evaluation", position: 2, name: "Técnica",
                      config: { "min_assessments" => 1 })
      c
    end
  end

  def step = as_company(company) { challenge.steps.reload.find(&:evaluation?) }

  def asignacion_de(user)
    as_company(company) { StepAssignment.find_by!(challenge_step_id: step.id, user_id: user.id) }
  end

  let!(:idea) do
    as_company(company) do
      i = create(:idea, challenge: challenge, author: paula)
      Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" }, author: paula).call
      i.update!(submitted_at: Time.current)
      i
    end
  end

  before do
    as_company(company) do
      challenge.pipeline.start!
      challenge.pipeline.advance!
    end
  end

  describe "la pantalla" do
    it "lista a quienes evalúan y deja ponerles peso" do
      sign_in(admin, company: company)
      get challenge_step_path(challenge, step)

      expect(response.body).to include("Quién evalúa")
      expect(response.body).to include(elena.name)
      expect(response.body).to include("Peso")
    end

    # Repartir el módulo es política del desafío: no se autoasigna nadie.
    it "quien evalúa no la ve" do
      sign_in(elena, company: company)
      get challenge_step_path(challenge, step)

      expect(response.body).not_to include("Quién evalúa")
    end
  end

  describe "asignar" do
    before { sign_in(admin, company: company) }

    it "suma a alguien que no estaba" do
      as_company(company) { asignacion_de(emilio).destroy! }

      post challenge_step_step_assignments_path(challenge, step),
           params: { user_id: emilio.id, weight: "2" }

      asignacion = asignacion_de(emilio)
      expect(asignacion.weight.to_f).to eq(2.0)
      expect(asignacion.role).to eq("evaluator")
    end

    it "rechaza un peso fuera de rango sin romper la pantalla" do
      as_company(company) { asignacion_de(emilio).destroy! }

      post challenge_step_step_assignments_path(challenge, step),
           params: { user_id: emilio.id, weight: "99" }

      expect(flash[:alert]).to match(/[Pp]eso/)
      expect(as_company(company) { StepAssignment.where(user_id: emilio.id).count }).to be_zero
    end
  end

  describe "el peso" do
    before { sign_in(admin, company: company) }

    def evaluar!(user, valor)
      as_company(company) do
        paso = step
        handler = paso.handler
        assessment = paso.assessments.create!(
          idea: idea, idea_version_id: idea.reload.current_version_id, evaluator: user,
          status: "submitted", submitted_at: Time.current
        )
        config = handler.criteria_snapshot.first
        criterion = Criterion.find(config["id"])
        numeric, normalized = criterion.score(valor)
        assessment.assessment_scores.create!(
          criterion_id: criterion.id, criterion_key: config["key"], weight_used: config["weight"],
          raw_value: valor.to_s, numeric_value: numeric, normalized_value: normalized
        )
        Flow::Evaluation::ScoreAssessment.new(assessment, criteria_snapshot: handler.criteria_snapshot).call
        handler.recompute_entry!(paso.step_entries.find_by(idea_id: idea.id))
      end
    end

    def puntaje = as_company(company) { step.step_entries.find_by(idea_id: idea.id).result["score"] }

    # Sin esto la tabla seguiría mostrando el puntaje calculado con el peso
    # viejo hasta que alguien evaluara de nuevo.
    it "cambiarlo recalcula el puntaje de las ideas en el acto" do
      evaluar!(elena, 10)
      evaluar!(emilio, 2)
      antes = puntaje

      patch challenge_step_step_assignment_path(challenge, step, asignacion_de(elena)),
            params: { weight: "3" }

      expect(puntaje).not_to be_within(0.0001).of(antes)
      expect(puntaje).to be > antes
    end

    it "vaciarlo lo devuelve a pesar como el resto" do
      as_company(company) { asignacion_de(elena).update!(weight: 3) }

      patch challenge_step_step_assignment_path(challenge, step, asignacion_de(elena)),
            params: { weight: "" }

      expect(asignacion_de(elena).weight).to be_nil
    end
  end

  describe "quitar" do
    before { sign_in(admin, company: company) }

    it "a quien todavía no evaluó, sí" do
      delete challenge_step_step_assignment_path(challenge, step, asignacion_de(emilio))

      expect(as_company(company) { StepAssignment.where(user_id: emilio.id).count }).to be_zero
    end

    # Su nota ya está puesta y sigue contando: sacarlo dejaría una evaluación
    # sin quién la respalde.
    it "a quien ya evaluó, no, y lo explica" do
      as_company(company) do
        step.assessments.create!(idea: idea, idea_version_id: idea.reload.current_version_id,
                                 evaluator: elena, status: "submitted", submitted_at: Time.current)
      end

      delete challenge_step_step_assignment_path(challenge, step, asignacion_de(elena))

      expect(flash[:alert]).to include("ya evaluó")
      expect(as_company(company) { StepAssignment.where(user_id: elena.id).count }).to eq(1)
    end
  end

  describe "con el módulo cerrado" do
    before do
      sign_in(admin, company: company)
      as_company(company) { step.update!(status: "completed", completed_at: Time.current) }
    end

    it "no se toca el peso: reescribiría un resultado" do
      patch challenge_step_step_assignment_path(challenge, step, asignacion_de(elena)),
            params: { weight: "5" }

      expect(flash[:alert]).to include("ya cerró")
      expect(asignacion_de(elena).weight).to be_nil
    end
  end

  describe "quién puede" do
    it "quien evalúa, no" do
      sign_in(elena, company: company)
      patch challenge_step_step_assignment_path(challenge, step, asignacion_de(emilio)),
            params: { weight: "5" }

      expect(response).to have_http_status(:forbidden).or have_http_status(:found)
      expect(asignacion_de(emilio).weight).to be_nil
    end
  end
end
