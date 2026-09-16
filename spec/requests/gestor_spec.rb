# frozen_string_literal: true

require "rails_helper"

# El rol gestor: acompaña la evolución de las ideas, para VARIAS empresas.
#
# Lo interempresa no necesitó nada nuevo —una membresía por empresa, como
# cualquiera que esté en más de una—. Lo nuevo es que tener membresía dejó de
# significar ver todos los desafíos de esa empresa.
RSpec.describe "el rol gestor", type: :request do
  let!(:demo) { without_tenant { create(:company, slug: "demo") } }
  let!(:otra) { without_tenant { create(:company, slug: "otra") } }

  let!(:gina) { without_tenant { create(:user, email: "gina@test.dev", name: "Gina Guía") } }
  let!(:admin) do
    without_tenant do
      u = create(:user, email: "admin@test.dev")
      create(:membership, :admin, company: demo, user: u)
      u
    end
  end

  before do
    without_tenant do
      create(:membership, :gestor, company: demo, user: gina)
      create(:membership, :gestor, company: otra, user: gina)
    end
  end

  def challenge_in(company, name)
    as_company(company) do
      c = create(:challenge, name: name)
      seed_form!(c.steps.create!(kind: "ideation", position: 1))
      c.steps.create!(kind: "evolution", position: 2, name: "Ronda")
      c
    end
  end

  let!(:acompanado) { challenge_in(demo, "Merma") }
  let!(:otro_de_demo) { challenge_in(demo, "Onboarding") }
  let!(:de_otra_empresa) { challenge_in(otra, "Ajeno") }

  before do
    as_company(demo) { ChallengeGestor.create!(challenge: acompanado, user: gina) }
  end

  def idea_en(challenge, company)
    as_company(company) do
      autor = without_tenant { create(:user) }
      without_tenant { create(:membership, company: company, user: autor) }
      i = create(:idea, challenge: challenge, author: autor)
      Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" }, author: autor).call
      i.update!(submitted_at: Time.current)
      i
    end
  end

  describe "qué ve dentro de una empresa" do
    before { sign_in(gina, company: demo) }

    it "el índice lista SOLO los desafíos que le asignaron" do
      get challenges_path

      expect(response.body).to include("Merma")
      expect(response.body).not_to include("Onboarding")
    end

    it "y entrar al que no le asignaron da 404, no 403" do
      get challenge_path(otro_de_demo)
      expect(response).to have_http_status(:not_found)
    end

    # Si el chequeo viviera solo en la pantalla del desafío, la URL de una idea
    # seguiría abierta. Vale para todo lo que cuelga.
    it "ni por la URL de una idea de ese desafío" do
      ajena = idea_en(otro_de_demo, demo)

      get challenge_idea_path(otro_de_demo, ajena)
      expect(response).to have_http_status(:not_found)
    end

    it "ni por la de un módulo" do
      step = as_company(demo) { otro_de_demo.steps.reload.first }

      get challenge_step_path(otro_de_demo, step)
      expect(response).to have_http_status(:not_found)
    end

    # Por la URL de SU desafío con el id de un comentario del otro. El
    # comentario se buscaba por id en toda la empresa y `resolve?` miraba el
    # desafío del comentario: 403, que confirma que existe.
    it "ni cerrando un comentario del otro desde la URL del suyo" do
      ajena = idea_en(otro_de_demo, demo)
      comentario = as_company(demo) do
        ronda = otro_de_demo.steps.reload.find_by(name: "Ronda")
        FeedbackItem.create!(challenge_step: ronda, idea: ajena, idea_version_id: ajena.current_version_id,
                             author: admin, actor_type: "human", kind: "suggestion", body: "x")
      end
      mi_ronda = as_company(demo) { acompanado.steps.reload.find_by(name: "Ronda") }

      post resolve_challenge_step_feedback_item_path(acompanado, mi_ronda, comentario)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "lo que sí puede hacer" do
    let!(:idea) { idea_en(acompanado, demo) }

    before { sign_in(gina, company: demo) }

    it "ve la idea y su historial" do
      get challenge_idea_path(acompanado, idea)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sensores", "Historial")
    end

    it "deja feedback, que es su tarea" do
      step = as_company(demo) { acompanado.steps.reload.find(&:evolution?) }

      expect do
        post challenge_step_feedback_items_path(acompanado, step),
             params: { idea_id: idea.id, kind: "suggestion",
                       body: "Acotá el piloto a un centro." }
      end.to change { as_company(demo) { FeedbackItem.count } }.by(1)
    end

    # Guía, no propone: proponer las propias lo pondría a guiar su competencia.
    it "pero NO postula ideas" do
      get new_challenge_idea_path(acompanado)
      expect(response).to have_http_status(:forbidden).or have_http_status(:found)
    end

    it "ni configura el flujo" do
      get builder_challenge_path(acompanado)
      expect(response).to have_http_status(:forbidden).or have_http_status(:found)
    end
  end

  # Es el punto del rol: la misma persona en dos empresas, sin que se mezcle.
  describe "trabajando para dos empresas" do
    it "en cada una ve lo suyo y nada de la otra" do
      as_company(otra) { ChallengeGestor.create!(challenge: de_otra_empresa, user: gina) }

      sign_in(gina, company: demo)
      get challenges_path
      expect(response.body).to include("Merma")
      expect(response.body).not_to include("Ajeno")

      sign_in(gina, company: otra)
      get challenges_path
      expect(response.body).to include("Ajeno")
      expect(response.body).not_to include("Merma")
    end

    it "el desafío de la otra empresa da 404 desde esta" do
      sign_in(gina, company: demo)
      get challenge_path(de_otra_empresa)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "asignar gestores" do
    before { sign_in(admin, company: demo) }

    it "quien administra los suma" do
      expect do
        post challenge_gestores_path(otro_de_demo, user_id: gina.id)
      end.to change { as_company(demo) { ChallengeGestor.count } }.by(1)
    end

    # La membresía es lo que habilita: sin rol gestor en ESA empresa, no.
    it "no se puede asignar a quien no es gestor de la empresa" do
      post challenge_gestores_path(otro_de_demo, user_id: admin.id)

      expect(flash[:alert]).to include("no es gestor en esta empresa")
      expect(as_company(demo) { ChallengeGestor.count }).to eq(1)
    end

    it "y los saca" do
      asignacion = as_company(demo) { ChallengeGestor.find_by(challenge_id: acompanado.id) }

      delete challenge_gestor_path(acompanado, asignacion)

      expect(as_company(demo) { ChallengeGestor.where(challenge_id: acompanado.id) }.to_a).to be_empty
    end
  end

  # Un gestor acompaña la EVOLUCIÓN de las ideas, así que se lo asigna donde
  # eso pasa. Antes se pedía desde la ficha del desafío, que reclamaba un
  # gestor incluso sobre un flujo vacío en el que todavía no se sabía si iba a
  # haber evolución.
  describe "dónde se asigna un gestor" do
    before { sign_in(admin, company: demo) }

    def evolucion(challenge) = as_company(demo) { challenge.steps.find(&:evolution?) }

    # El módulo de evolución de este test está PENDIENTE (nunca se arrancó el
    # pipeline): desde la tarea «configurar vs ejecutar» eso muestra la
    # pantalla de configuración, no la de ejecución —que es donde vivía este
    # bloque—, y las asignaciones viven en las DOS caras
    # (`steps/_asignaciones_gestores.html.haml`).
    it "en el módulo de evolución" do
      get challenge_step_path(otro_de_demo, evolucion(otro_de_demo))

      expect(response.body).to include("Quiénes acompañan")
      expect(response.body).to include("Nadie asignado todavía")
      # El acceso es al desafío entero: sin decirlo, alguien asigna creyendo
      # que solo va a ver este módulo.
      expect(response.body).to include("Se asigna por desafío, no por módulo")
    end

    it "y ya no desde la ficha del desafío" do
      get challenge_path(otro_de_demo)

      expect(response.body).not_to include("Quiénes acompañan")
    end

    it "tampoco sobre un desafío sin flujo, que era el caso raro" do
      vacio = as_company(demo) { create(:challenge, name: "Sin armar") }

      get challenge_path(vacio)

      expect(response.body).not_to include("Quiénes acompañan")
    end

    # Si alguien borra la evolución después de asignar, los gestores quedarían
    # sin pantalla donde sacarlos. Ahí la ficha los muestra.
    it "salvo que queden sin módulo donde administrarlos" do
      as_company(demo) { evolucion(acompanado).destroy! }

      get challenge_path(acompanado)

      expect(response.body).to include("Quiénes acompañan", "Gina Guía")
    end
  end


  # Acompañar la evolución es pedirle feedback a la IA y aplicar el que ya
  # propuso. Con la regla anterior —«quien administra, o el autor de la idea»—
  # el gestor no podía ninguna de las dos, que es literalmente su trabajo.
  describe "el gestor y la IA de la evolución" do
    let(:evolucion) { as_company(demo) { acompanado.steps.find(&:evolution?) } }

    let!(:idea) do
      as_company(demo) do
        autor = Flow::Tenant.bypass! { create(:user, email: "autora@test.dev") }
        i = create(:idea, challenge: acompanado, author: autor, status: "active")
        Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" }, author: autor).call
        i.update!(submitted_at: Time.current)
        i
      end
    end

    before do
      as_company(demo) do
        acompanado.pipeline.start!
        acompanado.pipeline.advance!
        evolucion.reload.update!(ai_mode: "ai_assisted")
      end
      sign_in(gina, company: demo)
    end

    it "puede pedirle a la IA que proponga el feedback" do
      expect do
        post challenge_ai_requests_path(acompanado, purpose: "suggest_feedback",
                                        step_id: evolucion.id, idea_id: idea.id)
      end.to change { as_company(demo) { AiRun.count } }.by(1)

      expect(flash[:ia]["tipo"]).to eq("ok")
    end

    it "y puede aplicar lo que la IA propuso" do
      sugerencia = as_company(demo) do
        Flow::AI::Runner.call(
          Flow::AI::Tasks::SuggestFeedback.new(challenge: acompanado, step: evolucion, idea: idea),
          mode: "ai_assisted", challenge: acompanado, step: evolucion, idea: idea
        ).suggestion
      end

      expect do
        post accept_ai_suggestion_path(sugerencia)
      end.to change { as_company(demo) { FeedbackItem.count } }

      expect(as_company(demo) { sugerencia.reload }).to be_accepted
    end

    # Ayudar a que la idea evolucione es para lo que existe el rol, y
    # responder el feedback editando es la forma de hacerlo.
    it "puede pedirle a la IA que reescriba la idea con el feedback" do
      as_company(demo) do
        FeedbackItem.create!(challenge_step: evolucion, idea: idea,
                             idea_version_id: idea.reload.current_version_id,
                             author: admin, kind: "question", body: "¿Y el costo?")
      end

      expect do
        post challenge_ai_requests_path(acompanado, purpose: "evolve_idea",
                                        step_id: evolucion.id, idea_id: idea.id)
      end.to change { as_company(demo) { AiRun.where(purpose: "evolve_idea").count } }.by(1)
    end

    it "y la pantalla se lo ofrece" do
      as_company(demo) do
        FeedbackItem.create!(challenge_step: evolucion, idea: idea,
                             idea_version_id: idea.reload.current_version_id,
                             author: admin, kind: "question", body: "¿Y el costo?")
      end

      get challenge_idea_path(acompanado, idea)

      expect(response.body).to include("Reescribir la idea con el feedback")
    end

    # Fuera de la ronda, no: acompañar tiene su ventana.
    it "pero no con la ronda cerrada" do
      as_company(demo) { evolucion.reload.update!(status: "completed", completed_at: Time.current) }

      expect do
        post challenge_ai_requests_path(acompanado, purpose: "evolve_idea",
                                        step_id: evolucion.id, idea_id: idea.id)
      end.not_to change { as_company(demo) { AiRun.count } }
    end

    # Presentar la idea es de su autor: quien acompaña la trabaja, no la
    # postula por él.
    it "y no postula la idea de otro" do
      borrador = as_company(demo) do
        i = create(:idea, challenge: acompanado, author: idea.author, status: "draft")
        Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sin postular" }).call
        i
      end

      post submit_challenge_idea_path(acompanado, borrador)

      expect(response).to have_http_status(:forbidden)
      expect(as_company(demo) { borrador.reload.submitted_at }).to be_nil
    end

    # Lo que configura el desafío sigue siendo de quien administra.
    it "pero no puede pedirle que arme el flujo" do
      expect do
        post challenge_ai_requests_path(acompanado, purpose: "propose_pipeline")
      end.not_to change { as_company(demo) { AiRun.count } }
    end
  end
end

