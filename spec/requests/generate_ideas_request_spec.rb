# frozen_string_literal: true

require "rails_helper"

# El botón de generar ideas, desde la pantalla del módulo.
RSpec.describe "generar ideas candidatas", type: :request do
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
      c = create(:challenge, name: "Merma", ai_default_mode: "ai_assisted")
      seed_form!(c.steps.create!(kind: "ideation", position: 1, name: "Postulación"))
      c.pipeline.start!
      c
    end
  end

  def step = as_company(company) { challenge.steps.reload.find(&:ideation?) }

  before { sign_in(owner, company: company) }

  it "la pantalla ofrece elegir cuántas, hasta el tope" do
    get challenge_step_path(challenge, step)

    expect(response.body).to include('name="count"')
    expect(response.body).to include(">5</option>")
    expect(response.body).not_to include(">6</option>")
  end

  # En `ai_assisted` generar NO crea ideas de una: deja la propuesta para
  # revisar. Las ideas entran al aceptarla.
  def pedir_y_aceptar(count:)
    post challenge_ai_requests_path(challenge, purpose: "generate_ideas",
                                    step_id: step.id, count: count)
    sugerencia = as_company(company) { AiSuggestion.pending_review.order(:created_at).last }
    post accept_ai_suggestion_path(sugerencia)
  end

  it "genera la cantidad que se pidió" do
    expect { pedir_y_aceptar(count: 2) }.to change { as_company(company) { Idea.count } }.by(2)
  end

  it "y el pedido queda como propuesta antes de aplicarse" do
    expect do
      post challenge_ai_requests_path(challenge, purpose: "generate_ideas",
                                      step_id: step.id, count: 2)
    end.not_to change { as_company(company) { Idea.count } }

    expect(as_company(company) { AiSuggestion.pending_review.count }).to eq(1)
  end

  # Las ideas generadas responden el formulario del desafío, no un payload
  # cualquiera: es lo que las hace utilizables.
  it "y cada idea responde todos los campos del formulario" do
    pedir_y_aceptar(count: 1)

    as_company(company) do
      idea = Idea.order(:created_at).last
      expect(idea.payload.keys).to match_array(%w[titulo problema solucion])
      expect(idea.payload.values).to all(be_present)
      expect(idea.origin).to eq("ai")
      expect(idea.submitted_at).to be_present
    end
  end
end
