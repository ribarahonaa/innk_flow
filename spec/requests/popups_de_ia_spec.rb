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
  it "no se pinta como franja de flash" do
    pedir!("propose_pipeline")
    follow_redirect!

    expect(response.body).not_to include("flash--notice")
    expect(response.body).not_to include("tipo&quot;=&gt;")
  end
end
