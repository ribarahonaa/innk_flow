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

end

