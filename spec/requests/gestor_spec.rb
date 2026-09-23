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

    # Los criterios de un módulo son del desafío. `CriteriaSetPolicy` no tenía
    # nada propio y heredaba `show? = membership.present?`: abrir el set por
    # id le mostraba los criterios de un desafío que no ve. No era un oráculo
    # de existencia; era leerlo.
    describe "los criterios propios de un módulo del otro desafío" do
      let!(:set_ajeno) do
        as_company(demo) do
          paso = otro_de_demo.steps.create!(kind: "evaluation", position: 3, name: "Técnica")
          set = CriteriaSet.create!(name: "Criterios del onboarding", scope: "inline", owner_step_id: paso.id)
          set.criteria.create!(key: "margen", name: "Margen interno del proveedor", weight: 1,
                               source: "manual", scale_type: "numeric", position: 0)
          paso.update!(criteria_set: set)
          set
        end
      end

      it "no los lee" do
        get criteria_set_path(set_ajeno)

        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to include("Margen interno del proveedor")
      end

      it "ni le confirma que existen al intentar editarlos" do
        get edit_criteria_set_path(set_ajeno)
        expect(response).to have_http_status(:not_found)
      end

      # La biblioteca es de la empresa, no de un desafío: esto no la toca. Si
      # se decide que un gestor tampoco la ve, cambia acá.
      it "la biblioteca la sigue viendo" do
        biblioteca = as_company(demo) { CriteriaSet.create!(name: "Genéricos", scope: "library") }

        get criteria_set_path(biblioteca)
        expect(response).to have_http_status(:ok)
      end
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

    # Era al revés: el gestor no configuraba nada. Desde que administra los
    # desafíos que le asignaron, el builder es suyo.
    it "y configura el flujo del desafío que le asignaron" do
      get builder_challenge_path(acompanado)
      expect(response).to have_http_status(:ok)
    end

    it "pero no el del desafío que no le asignaron" do
      get builder_challenge_path(otro_de_demo)
      expect(response).to have_http_status(:not_found)
    end

    # Pedir y aceptar son el MISMO método (`AiSuggestionPolicy#request?` es
    # `accept?`) y los dos caen en `update_pipeline?`. Se prueban los dos
    # igual: divergieron dos veces mientras la tabla estuvo copiada en los dos
    # lados, y un ejemplo solo no lo habría visto.
    it "y acepta lo que la IA propuso para el flujo" do
      sugerencia = as_company(demo) do
        Flow::AI::Runner.call(
          Flow::AI::Tasks::ProposePipeline.new(challenge: acompanado),
          mode: "ai_assisted", challenge: acompanado
        ).suggestion
      end

      post accept_ai_suggestion_path(sugerencia)

      expect(as_company(demo) { sugerencia.reload }).to be_accepted
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

    # Con `update_pipeline?` abierto, el gestor administra quién acompaña su
    # desafío. Sacarse a sí mismo lo deja afuera en el acto, sin forma de
    # volver salvo que un admin lo reasigne.
    it "el gestor no se saca a sí mismo" do
      sign_in(gina, company: demo)
      asignacion = as_company(demo) { acompanado.challenge_gestores.find_by!(user_id: gina.id) }

      delete challenge_gestor_path(acompanado, asignacion)

      expect(as_company(demo) { ChallengeGestor.exists?(asignacion.id) }).to be(true)
    end

    it "pero sí saca a otro, que es parte de administrar el desafío" do
      otra_gestora = without_tenant do
        u = create(:user, email: "otra@test.dev")
        create(:membership, :gestor, company: demo, user: u)
        u
      end
      asignacion = as_company(demo) do
        ChallengeGestor.create!(challenge: acompanado, user: otra_gestora)
      end

      sign_in(gina, company: demo)
      delete challenge_gestor_path(acompanado, asignacion)

      expect(as_company(demo) { ChallengeGestor.exists?(asignacion.id) }).to be(false)
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

    # Era la ventana que acotaba al gestor: sólo con la ronda abierta. Desde
    # que administra el desafío, trabajar la idea no depende de que haya una
    # ronda en curso.
    it "y también con la ronda cerrada" do
      as_company(demo) { evolucion.reload.update!(status: "completed", completed_at: Time.current) }

      expect do
        post challenge_ai_requests_path(acompanado, purpose: "evolve_idea",
                                        step_id: evolucion.id, idea_id: idea.id)
      end.to change { as_company(demo) { AiRun.count } }.by(1)
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

    # También era al revés. `AiSuggestionPolicy#accept?` cae en
    # `update_pipeline?` para las tareas de alcance `:challenge`, así que esto
    # se abrió solo al abrir la policy: por eso tiene ejemplo propio.
    it "y puede pedirle que arme el flujo" do
      expect do
        post challenge_ai_requests_path(acompanado, purpose: "propose_pipeline")
      end.to change { as_company(demo) { AiRun.count } }.by(1)
    end
  end

  describe "los criterios de su módulo" do
    before { sign_in(gina, company: demo) }

    def criterion_params(**overrides)
      { id: nil, name: "Impacto", description: nil, weight: 100,
        source: "manual", scale_type: "numeric",
        source_config: {}, scale_config: { min: 1, max: 10, step: 1, direction: "higher_better" },
        active: true }.merge(overrides)
    end

    it "los guarda por la API, que es el único camino de escritura del editor" do
      set = as_company(demo) do
        modulo = acompanado.steps.reload.first
        CriteriaSet.create!(name: "Los del módulo", scope: "inline", owner_step: modulo)
      end

      put api_v1_criteria_set_path(set), params: {
        name: "Los del módulo", criteria: [criterion_params]
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(as_company(demo) { set.reload.criteria.count }).to eq(1)
    end

    it "pero no crea uno de biblioteca, que se comparte con desafíos que no ve" do
      expect do
        post api_v1_criteria_sets_path, params: {
          name: "Compartidos", criteria: [criterion_params]
        }, as: :json
      end.not_to change { as_company(demo) { CriteriaSet.where(scope: "library").count } }
    end

    # El link de "Guardarlos también en la biblioteca" cambió de guarda
    # (`configure?` → `CriteriaSetPolicy#create?`), pero nada en la suite
    # renderizaba la rama del set `inline` para un gestor: una condición
    # invertida en la vista pasaría en silencio. Se fija la polaridad en las
    # dos direcciones, y las dos afirman primero el marcador de la rama
    # (`"no afectan a otros desafíos"`) para que el ejemplo no pase por no
    # haber montado el bloque.
    describe "el botón de promover, en la pantalla del módulo" do
      let!(:modulo_con_set) do
        as_company(demo) do
          paso = acompanado.steps.create!(kind: "evaluation", position: 3, name: "Técnica")
          set = CriteriaSet.create!(name: "Los del módulo", scope: "inline", owner_step_id: paso.id)
          set.criteria.create!(key: "impacto", name: "Impacto", weight: 1, source: "manual",
                               scale_type: "numeric", position: 0)
          paso.update!(criteria_set: set)
          paso
        end
      end

      it "la gestora asignada no lo ve" do
        get challenge_step_path(acompanado, modulo_con_set)

        expect(response.body).to include("no afectan a otros desafíos")
        expect(response.body).not_to include("Guardarlos también en la biblioteca")
      end

      it "quien administra sí lo ve" do
        sign_in(admin, company: demo)
        get challenge_step_path(acompanado, modulo_con_set)

        expect(response.body).to include("no afectan a otros desafíos")
        expect(response.body).to include("Guardarlos también en la biblioteca")
      end
    end
  end

  # Crear es la única puerta que no puede preguntar por la asignación: el
  # desafío todavía no existe. Por eso se auto-asigna al crearlo — si no, lo
  # crea y desaparece de su lista en el mismo movimiento, porque el Scope
  # filtra por `challenge_gestores`.
  describe "creando un desafío" do
    before { sign_in(gina, company: demo) }

    it "puede, y queda acompañándolo" do
      expect do
        post challenges_path, params: { challenge: { name: "Nuevo", brief: "Probar." } }
      end.to change { as_company(demo) { Challenge.count } }.by(1)

      creado = as_company(demo) { Challenge.order(:created_at).last }
      asignados = as_company(demo) { creado.challenge_gestores.pluck(:user_id) }

      expect(asignados).to include(gina.id)
    end

    it "y lo sigue viendo en el índice" do
      post challenges_path, params: { challenge: { name: "Nuevo", brief: "Probar." } }

      get challenges_path

      expect(response.body).to include("Nuevo")
    end
  end
end

