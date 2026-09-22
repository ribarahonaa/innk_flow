# frozen_string_literal: true

require "rails_helper"

RSpec.describe "pedirle a la IA que testee", type: :request do
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
      c = create(:challenge, name: "Reparto", ai_default_mode: "ai_assisted")
      seed_form!(c.steps.create!(kind: "ideation", position: 1))
      c.steps.create!(kind: "testing", position: 2, name: "Prueba de factibilidad")
      c
    end
  end

  let!(:idea) do
    as_company(company) do
      i = create(:idea, challenge: challenge, author: paula, status: "active")
      Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Bicis" }, author: paula).call
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

  it "quien administra ve el botón en la fila de la idea" do
    sign_in(admin, company: company)
    get challenge_step_path(challenge, paso)

    expect(response.body).to include("test_idea")
  end

  # Ofrecerlo con `advance?` (que es `manager?` a secas, la misma que autoriza
  # el link «Testear») en vez de la policy que en verdad autoriza el pedido
  # —`ChallengePolicy#update_pipeline?`, vía `AiSuggestionPolicy#request?`—
  # deja el botón ofrecido después de que el desafío cierra: `Flow::Pipeline
  # #close!` sólo toca el desafío, nunca el estado de sus módulos, así que el
  # de testing sigue `active?` con el desafío ya `closed`. `advance?` no mira
  # `closed?`; `update_pipeline?` sí. Con la vista vieja esto fallaba: el
  # botón aparecía igual y apretarlo rebotaba con 403.
  it "con el desafío cerrado y el módulo todavía activo, no se le ofrece ni a quien administra" do
    sign_in(admin, company: company)
    modulo = paso
    as_company(company) { challenge.pipeline.close! }

    expect(as_company(company) { modulo.reload.active? }).to be(true)

    get challenge_step_path(challenge, modulo)

    expect(response.body).not_to include("test_idea")
  end

  # Quien participa no testea ni PIDE el testeo de su idea: con un solo
  # vigente donde el último manda, pedirlo sería re-tirar el dado hasta que
  # salga «factible». Es la decisión 2.5 del spec de diseño.
  it "a quien participa no se le ofrece, ni sobre su propia idea" do
    sign_in(paula, company: company)
    get challenge_step_path(challenge, paso)

    expect(response.body).not_to include("test_idea")
  end

  it "y si lo postea igual, se lo rebota" do
    sign_in(paula, company: company)
    post challenge_ai_requests_path(challenge, purpose: "test_idea",
                                    step_id: paso.id, idea_id: idea.id)

    expect(response).to have_http_status(:forbidden)
  end

  # La guarda de permiso que le agregamos a esta tarjeta
  # (`policy(@challenge).update_pipeline?`) podría cerrar de más tan fácil
  # como de menos: un predicado invertido, una variable mal tipeada, o un
  # `@challenge` que ahí no exista la esconderían para TODO el mundo, y sin
  # este ejemplo la suite seguiría en verde. El texto es de la tarjeta
  # específicamente, no de la pantalla en general.
  it "con el desafío corriendo, a quien administra se le ofrece la tarjeta de pedirle a la IA" do
    sign_in(admin, company: company)
    get new_challenge_step_step_test_path(challenge, paso, idea_id: idea.id)

    expect(response.body).to include("Pedir el testeo de la IA")
  end

  # `button_to` es un <form>, y uno dentro de otro es HTML inválido: el
  # navegador descarta el interno y sus botones pasan a pertenecer al
  # externo. No se ve en el DOM ni en un request spec que postea directo: se
  # mira el HTML SERVIDO.
  it "el botón de la pantalla del testeo no queda dentro del formulario" do
    sign_in(admin, company: company)
    get new_challenge_step_step_test_path(challenge, paso, idea_id: idea.id)

    formularios = Nokogiri::HTML(response.body).css("form")
    expect(formularios.map { |f| f.css("form").size }).to all(eq(0))
  end
end
