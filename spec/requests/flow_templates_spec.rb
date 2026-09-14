# frozen_string_literal: true

require "rails_helper"

# Las plantillas de flujo.
#
# "Armalo como quieras" y "empezá de un lienzo en blanco" no son lo mismo, y lo
# segundo no es simple: un desafío nuevo abría el builder sin un solo módulo.
RSpec.describe "plantillas de flujo", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  let!(:owner) do
    without_tenant do
      u = create(:user, email: "owner@test.dev")
      create(:membership, :owner, company: company, user: u)
      u
    end
  end

  before { sign_in(owner, company: company) }

  def last_challenge = as_company(company) { Challenge.order(:created_at).last }
  def kinds_of(challenge) = as_company(company) { challenge.steps.reload.ordered.map(&:kind) }
  def form_keys(challenge)
    as_company(company) { challenge.pipeline.ideation_step&.form_fields&.ordered&.map(&:key) }
  end

  describe "al crear el desafío" do
    it "la pantalla ofrece las plantillas con su flujo a la vista" do
      get new_challenge_path

      expect(response.body).to include("Concurso clásico", "Convocatoria con feedback",
                                       "Dos rondas con comité", "Solo recolectar ideas",
                                       "Que lo proponga la IA", "En blanco")
    end

    it "«Concurso clásico» deja el flujo armado" do
      post challenges_path, params: { challenge: { name: "Merma", brief: "Bajar merma." },
                                      template: "classic" }

      expect(kinds_of(last_challenge)).to eq(%w[ideation evaluation selection reporting])
    end

    # Sin formulario «Idear» no arranca. Una plantilla que aterriza directo en
    # ese error no es un punto de partida.
    it "y con el formulario básico puesto, así el flujo es válido de entrada" do
      post challenges_path, params: { challenge: { name: "Merma", brief: "Bajar merma." },
                                      template: "classic" }

      challenge = last_challenge
      expect(form_keys(challenge)).to eq(%w[titulo problema solucion])
      expect(as_company(company) { challenge.pipeline.validate.errors }).to be_empty
    end

    it "«en blanco» no arma nada: el dueño ya dijo que lo hace él" do
      post challenges_path, params: { challenge: { name: "Vacío", brief: "b" }, template: "blank" }

      expect(kinds_of(last_challenge)).to be_empty
    end

    # «Que lo proponga la IA» corre SÍNCRONO, como cualquier otro pedido a la IA.
    #
    # Estuvo encolado en Sidekiq, y desde afuera eso se veía como que no pasaba
    # nada: la pantalla redirigía al instante, el job tardaba de 10 a 70
    # segundos con el proveedor real, y nadie le avisaba cuando la propuesta
    # llegaba. Había que recargar a mano para enterarse. Síncrono, los dos
    # popups —el de esperar y el de responder— funcionan sin una línea de
    # JavaScript nuevo, porque cuelgan del `flash[:ia]` y no del endpoint.
    it "«que lo proponga la IA» pide la propuesta en el acto, sin encolar nada" do
      expect do
        post challenges_path, params: { challenge: { name: "Con IA", brief: "b" }, template: "ai" }
      end.not_to have_enqueued_job(Flow::AI::RunJob)

      as_company(company) do
        expect(AiRun.where(purpose: "propose_pipeline").count).to eq(1)
        expect(AiSuggestion.pending_review.count).to eq(1)
      end
    end

    it "y lo cuenta por el mismo camino que el resto de los pedidos a la IA" do
      post challenges_path, params: { challenge: { name: "Con IA", brief: "b" }, template: "ai" }

      expect(flash[:notice]).to be_nil
      expect(flash[:ia]["tipo"]).to eq("ok")
      expect(flash[:ia]["mensaje"]).to match(/Revisá la propuesta/)
      expect(flash[:ia]["sugerencia_id"]).to eq(as_company(company) { AiSuggestion.first.id })
    end

    # En modo asistido la propuesta espera: el flujo se arma cuando alguien la
    # acepta, no al crear el desafío.
    it "en modo asistido el flujo sigue vacío hasta que alguien acepte" do
      post challenges_path, params: { challenge: { name: "Con IA", brief: "b",
                                                   ai_default_mode: "ai_assisted" },
                                      template: "ai" }

      expect(kinds_of(last_challenge)).to be_empty
    end

    it "en modo automático se aplica sola y no deja nada que revisar" do
      post challenges_path, params: { challenge: { name: "Con IA", brief: "b",
                                                   ai_default_mode: "ai_auto" },
                                      template: "ai" }

      expect(kinds_of(last_challenge)).not_to be_empty
      expect(flash[:ia]["mensaje"]).to match(/aplicó automáticamente/)
      expect(flash[:ia]["sugerencia_id"]).to be_nil
    end

    # El popup de espera lo dispara `ia_popups.js` al enviar, y este formulario
    # NO postea a `/ai_requests` sino a `/challenges`: la marca en el control es
    # lo único que se lo dice.
    it "la opción de la IA viene marcada para que el popup de espera la reconozca" do
      get new_challenge_path

      expect(response.body).to include("data-ia-espera")
    end

    it "sin plantilla se comporta como antes" do
      post challenges_path, params: { challenge: { name: "Suelto", brief: "b" } }

      expect(kinds_of(last_challenge)).to be_empty
      expect(response).to redirect_to(builder_challenge_path(last_challenge))
    end
  end

  describe "desde el builder" do
    let!(:challenge) { as_company(company) { create(:challenge, name: "Vacío") } }

    it "un desafío sin módulos las sigue ofreciendo" do
      get builder_challenge_path(challenge)

      expect(response.body).to include("Empezar de una plantilla", "Dos rondas con comité")
    end

    it "y aplicarlas arma el flujo" do
      post apply_template_challenge_path(challenge, template: "two_rounds")

      expect(kinds_of(challenge)).to eq(%w[ideation evaluation selection evaluation selection reporting])
      expect(form_keys(challenge)).to eq(%w[titulo problema solucion])
    end

    # Aplicar dos veces duplicaría el flujo entero. Por eso solo se ofrece
    # cuando no hay módulos, y el server lo revalida.
    it "no se aplican sobre un flujo que ya tiene módulos" do
      post apply_template_challenge_path(challenge, template: "classic")
      post apply_template_challenge_path(challenge, template: "collect")

      expect(kinds_of(challenge)).to eq(%w[ideation evaluation selection reporting])
      expect(flash[:alert]).to include("en borrador y sin módulos")
    end

    it "ni sobre un desafío ya arrancado" do
      as_company(company) do
        seed_form!(challenge.steps.create!(kind: "ideation", position: 1))
        challenge.pipeline.start!
      end

      post apply_template_challenge_path(challenge, template: "classic")

      expect(kinds_of(challenge)).to eq(%w[ideation])
    end

    it "el builder de un desafío que ya tiene módulos no las ofrece" do
      post apply_template_challenge_path(challenge, template: "collect")
      get builder_challenge_path(challenge)

      expect(response.body).not_to include("Empezar de una plantilla")
    end
  end
end
