# frozen_string_literal: true

require "rails_helper"

# Detectar duplicados compara una idea contra TODAS las del desafío, y lo que
# devuelve son títulos y resúmenes de las otras. Es trabajo de quien decide qué
# se fusiona o se descarta: quien administra y quien acompaña el desafío.
#
# Antes colgaba de `IdeaPolicy#update?` —la tarea actuaba «sobre la idea»—, y
# eso lo dejaba al revés: el autor lo pedía sobre su borrador y leía las ideas
# ajenas que quien participa no puede ver, y quien acompaña no podía pedirlo
# fuera de una ronda de evolución. El botón, además, no tenía guarda: quien
# evalúa lo recibía y rebotaba en 403.
RSpec.describe "detectar ideas duplicadas", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def miembro(email, rol)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, company: company, user: u, role: rol)
      u
    end
  end

  let!(:admin) { miembro("admin@test.dev", "admin") }
  let!(:gestor) { miembro("gestor@test.dev", "gestor") }
  let!(:autor) { miembro("autor@test.dev", "participant") }
  let!(:evaluador) { miembro("eval@test.dev", "evaluator") }

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma", brief: "Reducir merma.", ai_default_mode: "ai_assisted")
      seed_form!(c.steps.create!(kind: "ideation", position: 1))
      c.steps.create!(kind: "evolution", position: 2)
      c.pipeline.start!
      ChallengeGestor.create!(challenge: c, user: gestor)
      c
    end
  end

  let(:ideacion) { as_company(company) { challenge.steps.find_by!(kind: "ideation") } }

  def idea_de(usuario, titulo, postulada: true)
    as_company(company) do
      i = create(:idea, challenge: challenge, author: usuario)
      Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => titulo }, author: usuario).call
      i.update!(submitted_at: Time.current, status: "active") if postulada
      i
    end
  end

  # Un borrador: es justo cuando su autor PUEDE editarla, y por eso la regla
  # vieja lo dejaba comparar contra el pool entero.
  let!(:borrador) { idea_de(autor, "Sensores por rack", postulada: false) }
  let!(:otra) { idea_de(miembro("otro@test.dev", "participant"), "Sensores en góndola") }

  def pedir(idea)
    post challenge_ai_requests_path(challenge, purpose: "detect_duplicates", idea_id: idea.id, step_id: ideacion.id)
  end

  def corridas = as_company(company) { AiRun.where(purpose: "detect_duplicates").count }

  describe "el botón" do
    it "quien administra lo ve" do
      sign_in(admin, company: company)
      get challenge_idea_path(challenge, borrador)

      expect(response.body).to include("Detectar duplicados")
    end

    it "quien acompaña el desafío lo ve" do
      sign_in(gestor, company: company)
      get challenge_idea_path(challenge, otra)

      expect(response.body).to include("Detectar duplicados")
    end

    it "el autor no lo ve, ni en su propio borrador" do
      sign_in(autor, company: company)
      get challenge_idea_path(challenge, borrador)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Detectar duplicados")
    end

    it "quien evalúa no lo ve" do
      sign_in(evaluador, company: company)
      get challenge_idea_path(challenge, otra)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Detectar duplicados")
    end
  end

  describe "pedirlo" do
    it "el autor no puede, aunque arme el pedido a mano" do
      sign_in(autor, company: company)
      pedir(borrador)

      expect(response).to have_http_status(:forbidden)
      expect(corridas).to be_zero
    end

    # Comparar no edita la idea: no depende de que haya una ronda abierta.
    it "quien acompaña puede, aunque no haya una ronda de evolución abierta" do
      sign_in(gestor, company: company)
      pedir(otra)

      expect(response).to have_http_status(:found)
      expect(flash[:ia]["tipo"]).to eq("ok")
      expect(corridas).to eq(1)
    end
  end

  # Detectar duplicados no cambia nada: lo que produce es para leer. En «IA
  # automática» la propuesta se auto-aceptaba, su `apply!` no hace nada, y el
  # resultado no quedaba en ningún lado: quien lo pedía leía «se aplicó
  # automáticamente» y nada más.
  describe "con Idear en IA automática" do
    before do
      as_company(company) { ideacion.update!(ai_mode: "ai_auto") }
      sign_in(admin, company: company)
    end

    it "el resultado queda a la vista de quien lo pidió" do
      pedir(borrador)
      resultado = as_company(company) { AiSuggestion.joins(:ai_run).find_by!(ai_runs: { purpose: "detect_duplicates" }) }

      expect(resultado).to be_pending
      get challenge_idea_path(challenge, borrador)
      expect(response.body).to include(accept_ai_suggestion_path(resultado))
    end

    # No cambia nada más de la pantalla: responder a la pantalla entera sería
    # recargarla para mostrar lo mismo.
    it "el botón responde al marco de las propuestas" do
      get challenge_idea_path(challenge, borrador)

      boton = Nokogiri::HTML(response.body).at_css("form[action*='purpose=detect_duplicates']")
      expect(boton["data-turbo-frame"]).to eq("ai-suggestions")
    end
  end

  describe "el resultado" do
    let!(:resultado) do
      as_company(company) do
        task = Flow::AI::Tasks::DetectDuplicates.new(challenge: challenge, step: ideacion, idea: borrador)
        Flow::AI::Runner.call(task, mode: "ai_assisted", challenge: challenge, step: ideacion, idea: borrador).suggestion
      end
    end

    it "el autor no lo recibe en la ficha de su idea" do
      sign_in(autor, company: company)
      get challenge_idea_path(challenge, borrador)

      expect(response.body).not_to include(accept_ai_suggestion_path(resultado))
    end

    it "quien acompaña, sí" do
      sign_in(gestor, company: company)
      get challenge_idea_path(challenge, borrador)

      expect(response.body).to include(accept_ai_suggestion_path(resultado))
    end
  end
end
