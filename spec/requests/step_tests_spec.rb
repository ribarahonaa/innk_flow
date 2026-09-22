# frozen_string_literal: true

require "rails_helper"

RSpec.describe "testear una idea", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  let!(:admin) do
    without_tenant do
      u = create(:user, email: "admin@test.dev", name: "Ana Admin")
      create(:membership, :admin, company: company, user: u)
      u
    end
  end

  let!(:paula) do
    without_tenant do
      u = create(:user, email: "paula@test.dev", name: "Paula Participante")
      create(:membership, company: company, user: u, role: "participant")
      u
    end
  end

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma")
      seed_form!(c.steps.create!(kind: "ideation", position: 1))
      c.steps.create!(kind: "testing", position: 2, name: "Prueba de factibilidad")
      c
    end
  end

  let!(:idea) do
    as_company(company) do
      i = create(:idea, challenge: challenge, author: paula, status: "active")
      Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" }, author: paula).call
      i.update!(submitted_at: Time.current)
      i
    end
  end

  def paso
    as_company(company) do
      p = challenge.steps.reload.find(&:testing?)
      Flow::Handlers::Base.for(p).activate! unless p.touched?
      p.reload
    end
  end

  let(:payload) do
    { verdict: "con_reservas",
      summary: "Aguanta el día normal, no el pico",
      reservations: "Conseguir un segundo proveedor",
      situations: [{ dimension: "operativa", escenario: "Viernes 18h, 400 pedidos",
                     resultado: "se_rompe", detalle: "El turno de tarde satura" }] }
  end

  it "guarda el testeo y vuelve a la pantalla del módulo" do
    sign_in(admin, company: company)
    post challenge_step_step_tests_path(challenge, paso), params: payload.merge(idea_id: idea.id)

    expect(response).to redirect_to(challenge_step_path(challenge, paso))
    test = as_company(company) { StepTest.vigentes.find_by(idea_id: idea.id) }
    expect(test.verdict).to eq("con_reservas")
    expect(test.reservations).to eq(["Conseguir un segundo proveedor"])
    expect(test.tested_by_id).to eq(admin.id)
  end

  # Decisión 2.5 del spec: testear es de quien administra o acompaña. Con un
  # testeo vigente por idea donde el último manda, dejar que el autor lo pida
  # es re-tirar el dado hasta que salga «factible».
  it "quien participa no puede testear, ni su propia idea" do
    sign_in(paula, company: company)
    post challenge_step_step_tests_path(challenge, paso), params: payload.merge(idea_id: idea.id)

    expect(response).to have_http_status(:forbidden)
  end

  # Lo que no se ve da 404, no 403: un 403 sobre una idea que no se debería
  # ver es un oráculo de existencia. Por eso la idea se busca por policy_scope.
  it "una idea de otro desafío da 404, no 403" do
    otra = as_company(company) do
      c2 = create(:challenge, name: "Otro")
      seed_form!(c2.steps.create!(kind: "ideation", position: 1))
      i = create(:idea, challenge: c2, author: paula, status: "active")
      Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Ajena" }, author: paula).call
      i
    end

    sign_in(admin, company: company)
    post challenge_step_step_tests_path(challenge, paso), params: payload.merge(idea_id: otra.id)

    expect(response).to have_http_status(:not_found)
  end

  it "el formulario ofrece las dimensiones que el módulo configuró" do
    sign_in(admin, company: company)
    get new_challenge_step_step_test_path(challenge, paso, idea_id: idea.id)

    expect(response.body).to include("Operativa")
    expect(response.body).to include("Sensores")
  end

  # `steps/testing` exige `@step.active?` además del permiso y el modo de IA
  # para ofrecer «Pedir el testeo de la IA»; esta pantalla se olvidaba de esa
  # tercera condición y con el módulo ya cerrado el botón quedaba ofrecido
  # para escribir un `StepTest` nuevo sobre un módulo que ya no corre.
  it "con el módulo cerrado no ofrece pedirle el testeo a la IA" do
    p = paso
    as_company(company) do
      p.update!(ai_mode: "ai_assisted")
      p.handler.testear!(idea: idea, verdict: "factible", situations: [], reservations: [],
                         summary: "Aguanta", tested_by: admin)
      p.handler.complete!
    end

    sign_in(admin, company: company)
    get new_challenge_step_step_test_path(challenge, p, idea_id: idea.id)

    expect(response.body).not_to include("Pedir el testeo de la IA")
  end
end
