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

  # La pantalla de un desafío que ya cerró, por el camino real: `close!` saltea
  # el módulo que estaba corriendo, así que lo que se mira es un módulo
  # `skipped`.
  #
  # Lo que este ejemplo NO prueba, y hay que decirlo: la guarda del botón es
  # `puede_pedir_ia && @step.active? && …`, y con el módulo salteado el
  # `@step.active?` ya lo oculta por su cuenta. Sacar `!closed?` de
  # `update_pipeline?` lo dejaría en verde. Lo que aísla esa mitad es el
  # ejemplo de abajo.
  #
  # El desafío se pasa a `running` a mano antes de cerrarlo porque `paso`
  # activa el módulo con `activate!` y lo deja en BORRADOR, que es un estado
  # que ninguna pantalla produce: `ChallengePolicy#close?` pide `running?`.
  # Desde que `Handlers::Base#skip!` también lo pide, cerrar un borrador ya no
  # saltea nada —y la aserción de abajo lo cantó—.
  it "con el desafío cerrado no se le ofrece ni a quien administra" do
    sign_in(admin, company: company)
    modulo = paso
    as_company(company) do
      challenge.update!(status: "running", started_at: Time.current)
      challenge.pipeline.close!
    end

    expect(as_company(company) { modulo.reload.skipped? }).to be(true)

    get challenge_step_path(challenge, modulo)

    expect(response.body).not_to include("test_idea")
  end

  # El ejemplo que SÍ discrimina `update_pipeline?`.
  #
  # Ofrecer el botón con `advance?` (que es `administers?` a secas, la misma
  # que autoriza el link «Testear») en vez de la policy que autoriza el pedido
  # —`update_pipeline?`, vía `AiSuggestionPolicy#request?`— lo deja ofrecido
  # con el desafío cerrado, y apretarlo rebota con 403. Para aislar eso hay que
  # separar las dos condiciones de la misma línea: módulo ACTIVO y desafío
  # `closed`.
  #
  # Es la contradicción que `close!` vino a sacar, así que hoy se llega
  # escribiendo el estado a mano. La guarda existe igual, y no es de más: su
  # trabajo es preguntar la MISMA policy que autoriza al controller —también
  # excluye `archived?`, que nada más en esta pantalla mira— y no depender de
  # que `close!` siga salteando lo que estaba corriendo.
  #
  # «Testear» es el control positivo, y sin él el ejemplo pasaría igual si la
  # fila entera dejara de renderizarse: ese link cuelga de `advance?`, que NO
  # mira `closed?`, así que tiene que seguir ahí.
  it "y con el módulo activo adentro de un desafío cerrado tampoco, aunque «Testear» siga" do
    sign_in(admin, company: company)
    modulo = paso
    as_company(company) { challenge.update!(status: "closed", closed_at: Time.current) }

    expect(as_company(company) { modulo.reload }).to be_active

    get challenge_step_path(challenge, modulo)

    expect(response.body).to match(%r{href="[^"]*/step_tests/new})
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
