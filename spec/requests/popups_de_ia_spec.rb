# frozen_string_literal: true

require "rails_helper"

# Pedirle algo a la IA tiene dos momentos y ninguno se veía. El de la
# respuesta se perdía por una razón concreta: el mensaje viajaba en `notice` /
# `alert`, que el layout pinta ARRIBA de `.app-main` —afuera del
# `turbo-frame#ai-suggestions`—, así que en un pedido que responde al marco
# Turbo lo descartaba. La confirmación no se veía y el error tampoco.
#
# Ahora lo que pasó se registra en `flash[:ia]`, con la forma que el popup
# necesita: si salió bien o mal, qué decir, y cuál es la propuesta cuando
# quedó una por revisar.
RSpec.describe "lo que registra un pedido a la IA", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def miembro(email, rol)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, company: company, user: u, role: rol)
      u
    end
  end

  let!(:admin) { miembro("admin@test.dev", "admin") }

  let!(:challenge) do
    as_company(company) { create(:challenge, name: "Merma", brief: "Reducir merma.", ai_default_mode: "ai_assisted") }
  end

  before { sign_in(admin, company: company) }

  def pedir!(purpose, **params)
    post challenge_ai_requests_path(challenge, purpose: purpose, **params)
  end

  describe "en modo asistido" do
    it "deja la propuesta por revisar, con su id" do
      pedir!("propose_pipeline")

      expect(flash[:ia]["tipo"]).to eq("ok")
      expect(flash[:ia]["mensaje"]).to match(/Revisá la propuesta/)
      expect(flash[:ia]["sugerencia_id"]).to eq(as_company(company) { AiSuggestion.first.id })
    end

    # Un pedido repetido mientras la anterior sigue sin revisar no llama de
    # nuevo al proveedor. El mensaje perdió el «más abajo»: la propuesta ya no
    # está más abajo, está en el popup.
    it "avisa cuando ya había una esperando, y la vuelve a ofrecer" do
      pedir!("propose_pipeline")
      pedir!("propose_pipeline")

      expect(flash[:ia]["tipo"]).to eq("ok")
      expect(flash[:ia]["mensaje"]).to match(/Ya había una propuesta esperando/)
      expect(flash[:ia]["mensaje"]).not_to include("más abajo")
      expect(flash[:ia]["sugerencia_id"]).to be_present
    end
  end

  describe "en modo automático" do
    before { as_company(company) { challenge.update!(ai_default_mode: "ai_auto") } }

    it "dice que se aplicó sola y no ofrece nada que revisar" do
      pedir!("propose_pipeline")

      expect(flash[:ia]["tipo"]).to eq("ok")
      expect(flash[:ia]["mensaje"]).to match(/aplicó automáticamente/)
      expect(flash[:ia]["sugerencia_id"]).to be_nil
    end

    # La IA respondió y el dominio rechazó lo que propuso. Decir «no pudo
    # responder» sería falso, y además queda una propuesta pendiente que
    # alguien tiene que mirar: el popup la trae.
    it "cuando el dominio la rechaza, lo dice sin culpar a la IA, y trae la propuesta" do
      allow_any_instance_of(Flow::AI::Tasks::ProposePipeline)
        .to receive(:apply!).and_return([false, ["el flujo ya arrancó"]])

      pedir!("propose_pipeline")

      expect(flash[:ia]["tipo"]).to eq("error")
      expect(flash[:ia]["mensaje"]).to eq("La IA respondió, pero no se pudo aplicar: el flujo ya arrancó")
      expect(flash[:ia]["sugerencia_id"]).to be_present
    end
  end

  # La única rama de `success_message` que faltaba: `evaluate_idea` es una
  # tarea ADITIVA (`applies_on_request?` es `true`), así que corre en
  # `ai_auto` sin importar el modo del desafío o del módulo —pedirla ya es
  # aceptarla— y la propuesta queda aceptada: no hay nada que revisar.
  describe "una tarea aditiva (evaluate_idea)" do
    let!(:autora) { miembro("autora-eval@test.dev", "participant") }

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

    let!(:evaluacion) do
      as_company(company) do
        seed_form!(challenge.steps.create!(kind: "ideation", position: 1, status: "completed"))
        paso = challenge.steps.create!(kind: "evaluation", position: 2, criteria_set: set)
        challenge.update!(status: "running")
        paso
      end
    end

    # La idea tiene que existir ANTES de activar el módulo: `activate!`
    # sincroniza el cohorte con las ideas que hay en ese momento.
    let!(:idea) do
      as_company(company) do
        i = create(:idea, challenge: challenge, author: autora, status: "active")
        Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" }, author: autora).call
        i.update!(submitted_at: Time.current)
        Flow::Handlers::Base.for(evaluacion).activate!
        i
      end
    end

    it "dice que ya está en la lista, sin propuesta que revisar" do
      pedir!("evaluate_idea", step_id: evaluacion.id, idea_id: idea.id)

      expect(flash[:ia]["tipo"]).to eq("ok")
      expect(flash[:ia]["mensaje"]).to eq("Listo: la evaluación de la IA ya está en la lista.")
      expect(flash[:ia]["sugerencia_id"]).to be_nil
    end
  end

  describe "cuando algo falla" do
    it "el proveedor caído se cuenta como tal" do
      allow_any_instance_of(Flow::AI::Providers::Fixture)
        .to receive(:complete).and_raise(StandardError, "se cayó")

      pedir!("propose_pipeline")

      expect(flash[:ia]["tipo"]).to eq("error")
      expect(flash[:ia]["mensaje"]).to eq("La IA no pudo responder: se cayó")
      expect(flash[:ia]["sugerencia_id"]).to be_nil
    end

    # Un propósito que no existe se rechaza ANTES de llamar a nadie: es el
    # único camino de error que `make screens` puede recorrer gratis.
    it "un propósito desconocido no llama al proveedor" do
      pedir!("propósito-inexistente")

      expect(flash[:ia]["tipo"]).to eq("error")
      expect(flash[:ia]["mensaje"]).to match(/propósito desconocido/)
      expect(as_company(company) { AiRun.count }).to be_zero
    end
  end

  # El flash de la IA ya no es una franja: es el popup. Pintarlo además arriba
  # de `.app-main` sería decir dos veces lo mismo, y encima escupiendo el hash.
  #
  # Se mira el hijo directo de `.app-main`, que es donde el layout pinta el
  # flash de un redirect. No el nombre de la clase en el body: con los avisos
  # en `alert`, `flash--notice` no aparece nunca y esa aserción pasaba sin
  # probar nada.
  it "no se pinta como franja de flash" do
    pedir!("propose_pipeline")
    follow_redirect!

    expect(Nokogiri::HTML(response.body).css(".app-main > .alert")).to be_empty
    expect(response.body).not_to include("tipo&quot;=&gt;")
  end

  describe "el <template> que el popup va a leer" do
    # Hacen falta LOS DOS renders. Este repo no tiene la gema `turbo-rails`,
    # así que Rails pinta el layout completo también cuando el pedido es de un
    # marco, y Turbo recorta el marco de esa respuesta: lo que está afuera del
    # marco se pierde. Y al revés, hay pantallas que ni siquiera tienen marco.
    it "aparece dentro del marco y en el layout, con la propuesta y sus botones" do
      pedir!("propose_pipeline")
      follow_redirect!

      expect(response.body.scan(/<template[^>]*data-ia-respuesta/).size).to eq(2)
      expect(response.body).to include('data-tipo="ok"')
      expect(response.body).to include("Revisá la propuesta")
      expect(response.body).to include("Aplicar")
      expect(response.body).to include("Descartar")
    end

    # Este es el caso que hoy se pierde entero: en modo asistido el pedido
    # responde al marco, y el error viajaba en un `alert` que el layout pinta
    # afuera del marco.
    it "el error en modo asistido llega adentro del marco" do
      allow_any_instance_of(Flow::AI::Providers::Fixture)
        .to receive(:complete).and_raise(StandardError, "se cayó")

      pedir!("propose_pipeline")
      follow_redirect!

      marco = response.body[/<turbo-frame id="ai-suggestions".*?<\/turbo-frame>/m]
      expect(marco).to include("data-ia-respuesta")
      expect(marco).to include('data-tipo="error"')
      expect(marco).to include("La IA no pudo responder: se cayó")
    end

    it "sin pedido de por medio no hay ningún template" do
      get challenge_path(challenge)

      expect(response.body).not_to include("data-ia-respuesta")
    end
  end

  # La ficha de evaluación —donde vive «Pedir la guía de la IA»— no tiene
  # `turbo-frame#ai-suggestions`, y hasta ahora no mostraba absolutamente nada.
  # Lo único que la cubre es el render del LAYOUT, que es incondicional: basta
  # con probar que esa copia vive afuera del marco. Montar la ficha entera acá
  # ataría el ejemplo a que el módulo de evaluación esté activo y a que haya
  # asignación, que no es lo que se está probando.
  it "el del layout vive afuera del marco, que es lo que cubre a una pantalla sin marco" do
    pedir!("propose_pipeline")
    follow_redirect!

    afuera = response.body.sub(/<turbo-frame id="ai-suggestions".*?<\/turbo-frame>/m, "")
    expect(afuera).to include("data-ia-respuesta")
    expect(afuera).to include("Revisá la propuesta")
  end

  # Las pantallas de 404/403 se renderizan DESPUÉS del `Current.reset` del
  # `around_action` —`rescue_from` corre afuera de la cadena de callbacks—,
  # así que ahí no hay tenant. Si una propuesta quedó pendiente en el flash,
  # `respuesta_de_ia` consultaba `AiSuggestion` sin tenant en contexto:
  # `MissingTenant`, que agarra el mismo `rescue_from` que pinta el 404, y
  # vuelve a pintar el layout, y vuelve a reventar.
  it "una pantalla de error no revienta si el flash trae una propuesta pendiente" do
    pedir!("propose_pipeline")

    get challenge_path("no-existe")

    expect(response).to have_http_status(:not_found)
  end
end
