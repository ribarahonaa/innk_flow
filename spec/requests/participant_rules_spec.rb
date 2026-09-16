# frozen_string_literal: true

require "rails_helper"

# Las reglas del rol participante.
RSpec.describe "reglas de quien participa", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email, role)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, role.to_sym, company: company, user: u)
      u
    end
  end

  let!(:admin) { member("admin@test.dev", :admin) }
  let!(:elena) { member("elena@test.dev", :evaluator) }
  let!(:paula) { member("paula@test.dev", :participant) }
  let!(:pedro) { member("pedro@test.dev", :participant) }

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma", ai_default_mode: "human")
      seed_form!(c.steps.create!(kind: "ideation", position: 1))
      c.steps.create!(kind: "evolution", position: 2, name: "Ronda")
      c.steps.create!(kind: "evaluation", position: 3, name: "Técnica",
                      config: { "min_assessments" => 1 })
      c
    end
  end

  def step_named(name) = as_company(company) { challenge.steps.reload.find_by(name: name) }

  def idea_de(autor, titulo)
    as_company(company) do
      i = create(:idea, challenge: challenge, author: autor)
      Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => titulo }, author: autor).call
      i.update!(submitted_at: Time.current)
      i
    end
  end

  let!(:mia) { idea_de(paula, "La idea de Paula") }
  let!(:ajena) { idea_de(pedro, "La idea de Pedro") }

  before { as_company(company) { challenge.pipeline.start!; challenge.pipeline.advance! } }

  describe "feedback" do
    before { sign_in(paula, company: company) }

    it "puede comentar la suya" do
      expect do
        post challenge_step_feedback_items_path(challenge, step_named("Ronda")),
             params: { idea_id: mia.id, kind: "suggestion", body: "Me falta el costeo." }
      end.to change { as_company(company) { FeedbackItem.count } }.by(1)
    end

    # El ida y vuelta entre autores que compiten por el mismo corte no es
    # feedback, es negociación.
    it "pero no la de otro autor" do
      expect do
        post challenge_step_feedback_items_path(challenge, step_named("Ronda")),
             params: { idea_id: ajena.id, kind: "suggestion", body: "Cambiala." }
      end.not_to change { as_company(company) { FeedbackItem.count } }
    end

    # Antes el tablero le mostraba las dos ideas y le ofrecía la caja de
    # comentar solo en la suya. Ahora directamente no ve la ajena: el tablero
    # de la evolución es la vista de quien acompaña.
    it "y el tablero solo le muestra la suya" do
      get challenge_step_path(challenge, step_named("Ronda"))

      expect(response.body).to include("La idea de Paula")
      expect(response.body).not_to include("La idea de Pedro")
      expect(response.body.scan(%(class="feedback-form")).size).to eq(1)
    end

    it "quien evalúa sí puede comentar cualquiera" do
      sign_in(elena, company: company)

      expect do
        post challenge_step_feedback_items_path(challenge, step_named("Ronda")),
             params: { idea_id: ajena.id, kind: "suggestion", body: "Acotala." }
      end.to change { as_company(company) { FeedbackItem.count } }.by(1)
    end
  end

  describe "los puntajes" do
    before do
      as_company(company) do
        challenge.pipeline.advance!
        evaluacion = challenge.steps.reload.find_by(name: "Técnica")
        [mia, ajena].each do |idea|
          evaluacion.assessments.create!(idea: idea, idea_version_id: idea.current_version_id,
                                         evaluator: elena, actor_type: "human", status: "submitted",
                                         submitted_at: Time.current, normalized_score: 0.58)
          evaluacion.handler.recompute_entry!(StepEntry.find_by(challenge_step_id: evaluacion.id,
                                                                idea_id: idea.id))
        end
        evaluacion.update_column(:status, "completed")
      end
      sign_in(paula, company: company)
    end

    # Ver el nombre de quien te puntuó bajo y su comentario convierte un
    # resultado en una discusión personal.
    it "no ve quién puso qué, ni siquiera con el módulo cerrado" do
      get challenge_step_path(challenge, step_named("Técnica"))

      expect(response.body).not_to include(elena.name)
      expect(response.body).not_to include("Evaluaciones hechas")
    end

    it "pero sí el resultado de SU idea, en su ficha" do
      get challenge_idea_path(challenge, mia)

      expect(response.body).to include("Cómo le fue", "Técnica", "58%")
    end

    # Antes veía la ficha ajena sin el puntaje. Ahora no la ve: quien participa
    # ve solo las ideas en las que participa, y lo que no ve da 404 —no 403—
    # para no confirmar que existe.
    it "y la ajena no la abre" do
      get challenge_idea_path(challenge, ajena)

      expect(response).to have_http_status(:not_found)
    end

    # El reporte trae el ranking entero: es justo lo que no ve en pantalla.
    it "no puede generar el reporte" do
      post challenge_step_reports_path(challenge, step_named("Técnica")), params: { kind: "summary" }

      expect(response).to have_http_status(:forbidden).or have_http_status(:found)
    end
  end

  # La regla nueva, en los cuatro lugares donde se listan ideas. Vive una sola
  # vez —en `IdeaPolicy::Scope`— y las pantallas la aplican; sin eso habría que
  # acordarse en cada una.
  describe "solo ve las ideas en las que participa" do
    before do
      # El módulo de evaluación tiene que existir para poder mirarlo.
      as_company(company) { challenge.pipeline.advance! }
      sign_in(paula, company: company)
    end

    it "el índice de ideas lista la suya y nada más" do
      get challenge_ideas_path(challenge)

      expect(response.body).to include("La idea de Paula")
      expect(response.body).not_to include("La idea de Pedro")
    end

    it "la ficha de la ajena da 404, no 403" do
      get challenge_idea_path(challenge, ajena)

      expect(response).to have_http_status(:not_found)
    end

    it "el módulo de evaluación tampoco la lista" do
      get challenge_step_path(challenge, step_named("Técnica"))

      expect(response.body).to include("La idea de Paula")
      expect(response.body).not_to include("La idea de Pedro")
    end

    # Quien acompaña o evalúa las ve todas: las dos cosas se hacen sobre el
    # pool entero.
    it "quien evalúa sigue viéndolas todas" do
      sign_in(elena, company: company)

      get challenge_ideas_path(challenge)

      expect(response.body).to include("La idea de Paula", "La idea de Pedro")
    end

    # Lo que no ve tampoco se lo confirma una ruta que ACTÚA sobre una idea.
    # Buscándola con `@challenge.ideas.find` y autorizando después, la ajena
    # daba 403 y un id que no existe daba 404: esa diferencia dice que la idea
    # existe, que es el oráculo que la ficha ya cerraba. Cada ruta se pide con
    # las dos, y tienen que responder igual.
    describe "ninguna ruta le confirma que existe una idea ajena" do
      def con_ajena_y_con_inexistente(&pedido)
        [ajena.id, SecureRandom.uuid].map do |id|
          instance_exec(id, &pedido)
          response.status
        end
      end

      it "comentarla" do
        estados = con_ajena_y_con_inexistente do |id|
          post challenge_step_feedback_items_path(challenge, step_named("Ronda")),
               params: { idea_id: id, kind: "suggestion", body: "Cambiala." }
        end

        expect(estados).to eq([404, 404])
      end

      it "sumarse como colaboradora" do
        estados = con_ajena_y_con_inexistente do |id|
          post challenge_idea_contributors_path(challenge, id), params: { user_id: paula.id, role: "contributor" }
        end

        expect(estados).to eq([404, 404])
      end

      it "abrir su ficha de evaluación" do
        estados = con_ajena_y_con_inexistente do |id|
          get new_challenge_step_assessment_path(challenge, step_named("Técnica"), idea_id: id)
        end

        expect(estados).to eq([404, 404])
      end

      it "pedirle algo a la IA sobre ella" do
        estados = con_ajena_y_con_inexistente do |id|
          post challenge_ai_requests_path(challenge, purpose: "coauthor_field", idea_id: id)
        end

        expect(estados).to eq([404, 404])
      end
    end
  end
end

