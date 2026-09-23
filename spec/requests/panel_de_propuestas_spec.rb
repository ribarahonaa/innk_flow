# frozen_string_literal: true

require "rails_helper"

# El panel de propuestas de la IA se sirve en diez pantallas y no filtraba
# nada: quien llegaba a la pantalla recibía cada propuesta pendiente de su
# objetivo —el desafío, el módulo o la idea— con «Aplicar» y «Descartar».
# Quien no podía revisarla se comía un 403 al apretar y, antes de apretar, ya
# había leído la vista previa: el flujo que la IA propone, las ideas que
# generó o, en la ficha de una idea, lo que le propone a otra persona.
#
# La regla de quién revisa qué ya existía (`AiSuggestionPolicy#accept?`, que
# depende de sobre qué actúa la tarea); faltaba que el panel la aplicara.
RSpec.describe "el panel de propuestas de la IA", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def miembro(email, rol)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, company: company, user: u, role: rol)
      u
    end
  end

  let!(:admin) { miembro("admin@test.dev", "admin") }
  let!(:participante) { miembro("part@test.dev", "participant") }
  let!(:evaluador) { miembro("eval@test.dev", "evaluator") }

  let!(:challenge) do
    as_company(company) { create(:challenge, name: "Merma", brief: "Reducir merma.", ai_default_mode: "ai_assisted") }
  end

  let!(:ideacion) do
    as_company(company) do
      paso = seed_form!(challenge.steps.create!(kind: "ideation", position: 1))
      challenge.steps.create!(kind: "evolution", position: 2)
      challenge.pipeline.start!
      paso
    end
  end

  let!(:propia) do
    as_company(company) do
      i = create(:idea, challenge: challenge, author: participante, status: "active")
      Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" }, author: participante).call
      i.update!(submitted_at: Time.current)
      i
    end
  end

  def pendiente(task, step: nil, idea: nil)
    as_company(company) do
      Flow::AI::Runner.call(task, mode: "ai_assisted", challenge: challenge, step: step, idea: idea).suggestion
    end
  end

  # Una propuesta por objetivo. Las dos primeras son de quien administra
  # (alcance `:challenge`); la tercera, de quien puede editar la idea.
  let!(:flujo) { pendiente(Flow::AI::Tasks::ProposePipeline.new(challenge: challenge)) }
  let!(:ideas_generadas) do
    pendiente(Flow::AI::Tasks::GenerateIdeas.new(challenge: challenge, step: ideacion, count: 2), step: ideacion)
  end
  let!(:coautoria) do
    campo = as_company(company) { ideacion.form_fields.find_by(key: "titulo") }
    pendiente(Flow::AI::Tasks::CoauthorField.new(challenge: challenge, step: ideacion, idea: propia, field: campo),
              step: ideacion, idea: propia)
  end

  def aplicar(sugerencia) = accept_ai_suggestion_path(sugerencia)

  describe "en la ficha del desafío" do
    it "quien participa no recibe la propuesta de flujo, ni su vista previa" do
      sign_in(participante, company: company)
      get challenge_path(challenge)

      expect(response.body).not_to include(aplicar(flujo))
      expect(response.body).not_to include("ai-suggestion__body")
    end

    # El marco es el destino de los botones de `shared/_ai_actions`: tiene que
    # estar aunque no quede nada que mostrar adentro.
    it "sin nada que revisar, recibe el marco vacío y sin encabezado" do
      sign_in(participante, company: company)
      get challenge_path(challenge)

      expect(response.body).to include('id="ai-suggestions"')
      expect(response.body).not_to include("Propuestas de la IA")
    end

    it "quien administra la recibe" do
      sign_in(admin, company: company)
      get challenge_path(challenge)

      expect(response.body).to include(aplicar(flujo))
    end
  end

  describe "en la pantalla del módulo" do
    it "quien participa no recibe las ideas que la IA generó" do
      sign_in(participante, company: company)
      get challenge_step_path(challenge, ideacion)

      expect(response.body).not_to include(aplicar(ideas_generadas))
    end

    it "quien administra, sí" do
      sign_in(admin, company: company)
      get challenge_step_path(challenge, ideacion)

      expect(response.body).to include(aplicar(ideas_generadas))
    end
  end

  describe "en la ficha de la idea" do
    # Con la ronda de evolución abierta quien participa puede editar su idea,
    # y por lo tanto revisar lo que la IA le propuso.
    #
    # Va acá y no arriba porque `advance!` CIERRA la ideación de paso, y el
    # panel del módulo ya no ofrece aplicar lo que la IA propuso para uno
    # cerrado: aplicarlo crearía ideas sin fila en ninguna `step_entries`.
    before { as_company(company) { challenge.pipeline.advance! } }

    it "su autor recibe lo que la IA le propone" do
      sign_in(participante, company: company)
      get challenge_idea_path(challenge, propia)

      expect(response.body).to include(aplicar(coautoria))
    end

    # Evaluar deja ver todas las ideas, pero no editarlas.
    it "quien evalúa la ve, pero no recibe la propuesta" do
      sign_in(evaluador, company: company)
      get challenge_idea_path(challenge, propia)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(aplicar(coautoria))
    end
  end
end
