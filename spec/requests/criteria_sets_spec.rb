# frozen_string_literal: true

require "rails_helper"

# El editor de criterios.
#
# Antes esta pantalla pedía escribir el JSON a mano —
# `{"check":"field_present","field_key":"costo","min_length":200}`— y no tenía
# un solo spec. La demo tenía cero sets: nadie la había usado nunca.
RSpec.describe "sets de criterios", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  let!(:owner) do
    without_tenant do
      u = create(:user, email: "owner@test.dev")
      create(:membership, :owner, company: company, user: u)
      u
    end
  end

  let!(:participant) do
    without_tenant do
      u = create(:user, email: "part@test.dev")
      create(:membership, company: company, user: u)
      u
    end
  end

  def json = JSON.parse(response.body)
  # Toda lectura del dominio va DENTRO del tenant: leer afuera revienta con
  # MissingTenant, que es exactamente lo que tiene que pasar.
  def saved_criteria(name = nil)
    as_company(company) do
      set = name ? CriteriaSet.find_by!(name: name) : CriteriaSet.order(:created_at).first
      set.criteria.ordered.to_a
    end
  end

  def criterion_params(**overrides)
    { id: nil, name: "Impacto", description: nil, weight: 100,
      source: "manual", scale_type: "numeric",
      source_config: {}, scale_config: { min: 1, max: 10, step: 1, direction: "higher_better" },
      active: true }.merge(overrides)
  end

  describe "la pantalla" do
    before { sign_in(owner, company: company) }

    it "monta el editor con el esquema serializado por el server" do
      get new_criteria_set_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-island="criteria-editor"')
      # El esquema viaja en las props: el editor no declara los parámetros.
      expect(response.body).to include("field_present", "min_length", "lower_better")
    end

    it "el set nace vacío: las plantillas se eligen, no se imponen" do
      get new_criteria_set_path

      props = JSON.parse(Nokogiri::HTML(response.body).at_css("[data-island]")["data-props"])
      expect(props["criteria"]).to be_empty
    end
  end

  describe "guardar" do
    before { sign_in(owner, company: company) }

    it "crea el set con un criterio manual" do
      post api_v1_criteria_sets_path, params: {
        name: "Evaluación técnica", criteria: [criterion_params]
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["set"]["status"]).to eq("valid")
      # El peso viaja en porcentaje y se guarda en [0,1], que es como lo lee
      # el cálculo de puntaje.
      expect(json["criteria"].first["weight"]).to eq(100.0)
      expect(saved_criteria.first.weight.to_f).to eq(1.0)
    end

    it "arma un criterio automático sin escribir JSON" do
      post api_v1_criteria_sets_path, params: {
        name: "Admisibilidad",
        criteria: [criterion_params(name: "Está costeada", source: "automatic", scale_type: "boolean",
                                    source_config: { check: "field_present", field_key: "costo", min_length: 200 },
                                    scale_config: {})]
      }, as: :json

      expect(response).to have_http_status(:ok)
      criterion = saved_criteria.first
      expect(criterion.source_config).to eq("check" => "field_present", "field_key" => "costo",
                                            "min_length" => 200)
      expect(criterion.scale_type).to eq("boolean")
      expect(as_company(company) { criterion.summary }).to include("al menos 200 caracteres")
    end

    # Sin esto, cambiar de verificación deja atrás los parámetros de la
    # anterior y el config guardado dice cosas que ya no aplican.
    it "al cambiar de verificación no arrastra los parámetros de la anterior" do
      post api_v1_criteria_sets_path, params: {
        name: "Set",
        criteria: [criterion_params(source: "automatic", scale_type: "boolean",
                                    source_config: { check: "contributors_count", minimum: 3,
                                                     field_key: "costo", min_length: 200 },
                                    scale_config: {})]
      }, as: :json

      expect(saved_criteria.first.source_config).to eq("check" => "contributors_count",
                                                       "minimum" => 3)
    end

    it "guarda una fórmula con su rango de salida" do
      post api_v1_criteria_sets_path, params: {
        name: "ICE",
        criteria: [
          criterion_params(name: "Impacto", key: "impacto", weight: 50),
          criterion_params(name: "Esfuerzo", key: "esfuerzo", weight: 50)
        ]
      }, as: :json

      criteria = saved_criteria("ICE")
      set_id = criteria.first.criteria_set_id
      put api_v1_criteria_set_path(set_id), params: {
        name: "ICE",
        criteria: [
          criterion_params(id: criteria.first.id, name: "Impacto", key: "impacto", weight: 40),
          criterion_params(id: criteria.second.id, name: "Esfuerzo", key: "esfuerzo", weight: 40),
          criterion_params(name: "Prioridad", key: "prioridad", weight: 20, source: "formula",
                           scale_config: { expression: "impacto / esfuerzo",
                                           output: { min: 0, max: 10 } })
        ]
      }, as: :json

      expect(response).to have_http_status(:ok)
      formula = saved_criteria("ICE").find(&:formula?)
      expect(formula.scale_config).to eq("expression" => "impacto / esfuerzo",
                                         "output" => { "min" => 0, "max" => 10 })
      # El origen manda sobre la forma: una fórmula siempre es numérica.
      expect(formula.scale_type).to eq("numeric")
    end

    it "rechaza una fórmula que usa una variable inexistente" do
      post api_v1_criteria_sets_path, params: {
        name: "Rota",
        criteria: [criterion_params(name: "Prioridad", source: "formula",
                                    scale_config: { expression: "impacto / inexistente",
                                                    output: { min: 0, max: 10 } })]
      }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["errors"].join).to include("inexistente")
    end

    it "marca inválido el set cuyos pesos no suman 100%" do
      post api_v1_criteria_sets_path, params: {
        name: "Desbalanceado",
        criteria: [criterion_params(name: "Uno", weight: 30), criterion_params(name: "Dos", weight: 30)]
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["set"]["status"]).to eq("invalid")
      expect(json["validation"]["errors"].join).to include("deben sumar 1")
      expect(json["validation"]["weightTotal"]).to be_within(0.001).of(0.6)
    end
  end

  # Un set de biblioteca es de la empresa, no del módulo que lo usa. Editarlo
  # en el lugar le cambiaría la vara a todo desafío que todavía no arrancó, sin
  # que nadie se entere. Por eso guardar crea la versión siguiente.
  describe "un set de biblioteca en uso" do
    let!(:set) do
      as_company(company) do
        s = CriteriaSet.create!(name: "Técnica", scope: "library")
        s.criteria.create!(name: "Impacto", key: "impacto", weight: 1, source: "manual",
                           scale_type: "numeric", scale_config: { "min" => 1, "max" => 10 })
        s.refresh_status!
        s
      end
    end

    # Con notas ya puestas: es el caso que el candado viejo bloqueaba y que el
    # versionado destraba, porque lo puntuado queda en la versión anterior.
    let!(:step) do
      as_company(company) do
        challenge = create(:challenge)
        seed_form!(challenge.steps.create!(kind: "ideation", position: 1))
        paso = challenge.steps.create!(kind: "evaluation", position: 2, criteria_set: set)

        author = Flow::Tenant.bypass! { create(:user) }
        idea = create(:idea, challenge: challenge, author: author)
        Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => "Una" }).call

        assessment = Assessment.create!(challenge_step: paso, idea: idea,
                                        idea_version_id: idea.current_version_id,
                                        evaluator_id: owner.id, actor_type: "human")
        AssessmentScore.create!(assessment: assessment, criterion: set.criteria.first,
                                criterion_key: "impacto", weight_used: 1,
                                raw_value: "8", numeric_value: 8, normalized_value: 0.777)
        paso
      end
    end

    def familia = as_company(company) { CriteriaSet.where(family_id: set.family_id).order(:version).to_a }

    def v1 = as_company(company) { CriteriaSet.find(set.id) }

    def first_criterion = as_company(company) { CriteriaSet.find(set.id).criteria.ordered.first }

    before { sign_in(owner, company: company) }

    it "avisa, antes de guardar, qué va a pasar" do
      get edit_criteria_set_path(set)

      expect(response.body).to include("Lo usan 1 módulo")
      expect(response.body).to include("se crea la v2")
      # Y no el mensaje de candado: acá no hay nada cerrado, hay una copia.
      expect(response.body).not_to include("Ya hay evaluaciones hechas con este set")
    end

    it "guardar crea la versión siguiente y deja intacta la anterior" do
      put api_v1_criteria_set_path(set), params: {
        name: "Técnica", criteria: [criterion_params(id: first_criterion.id, name: "Impacto real", weight: 100)]
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["versioned"]).to be(true)
      expect(json["set"]["version"]).to eq(2)

      v1_criterios, v2_criterios = familia.map { |s| as_company(company) { s.criteria.ordered.map(&:name) } }
      expect(v1_criterios).to eq(["Impacto"])
      expect(v2_criterios).to eq(["Impacto real"])
    end

    it "el módulo que lo usaba sigue apuntando a la versión anterior" do
      put api_v1_criteria_set_path(set), params: {
        name: "Técnica", criteria: [criterion_params(id: first_criterion.id, name: "Otra cosa")]
      }, as: :json

      expect(as_company(company) { ChallengeStep.find(step.id).criteria_set_id }).to eq(set.id)
    end

    # Es lo que el candado viejo prohibía. Sobre una versión nueva se puede:
    # nadie puntuó nada con ella todavía.
    it "sobre la versión nueva se puede cambiar el peso y quitar criterios" do
      as_company(company) do
        s = CriteriaSet.find(set.id)
        s.criteria.create!(name: "Costo", key: "costo", weight: 0, source: "manual",
                           scale_type: "numeric", scale_config: { "min" => 1, "max" => 10 })
      end

      put api_v1_criteria_set_path(set), params: {
        name: "Técnica",
        criteria: [criterion_params(id: first_criterion.id, name: "Impacto", weight: 100,
                                    scale_config: { min: 1, max: 100 })]
      }, as: :json

      expect(response).to have_http_status(:ok)
      criterios = as_company(company) { familia.last.criteria.ordered.to_a }
      expect(criterios.size).to eq(1)
      expect(criterios.first.scale_config["max"]).to eq(100)

      # Y la nota puesta sigue significando lo mismo: cuelga de la v1, que no
      # se tocó.
      original = as_company(company) { CriteriaSet.find(set.id).criteria.ordered.first }
      expect(original.scale_config["max"]).to eq(10)
      expect(as_company(company) { AssessmentScore.where(criterion_id: original.id).count }).to eq(1)
    end

    it "la versión reemplazada ya no se edita" do
      put api_v1_criteria_set_path(set), params: {
        name: "Técnica", criteria: [criterion_params(id: first_criterion.id)]
      }, as: :json

      put api_v1_criteria_set_path(set), params: {
        name: "Otro nombre", criteria: [criterion_params(id: first_criterion.id)]
      }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["errors"].join).to include("reemplazada")
    end

    it "la biblioteca lista la versión vigente, no las anteriores" do
      put api_v1_criteria_set_path(set), params: {
        name: "Técnica", criteria: [criterion_params(id: first_criterion.id)]
      }, as: :json

      get criteria_sets_path

      expect(response.body).to include("v2")
      expect(response.body.scan("Técnica").size).to eq(1)
    end

    it "un set que no usa nadie se edita en el lugar, sin versionar" do
      suelto = as_company(company) do
        s = CriteriaSet.create!(name: "Sin usar", scope: "library")
        s.criteria.create!(name: "Uno", key: "uno", weight: 1, source: "manual", scale_type: "numeric",
                           scale_config: { "min" => 1, "max" => 10 })
        s
      end
      criterio = as_company(company) { CriteriaSet.find(suelto.id).criteria.first }

      put api_v1_criteria_set_path(suelto), params: {
        name: "Sin usar", criteria: [criterion_params(id: criterio.id, name: "Renombrado")]
      }, as: :json

      expect(json["versioned"]).to be(false)
      expect(json["set"]["version"]).to eq(1)
      expect(as_company(company) { CriteriaSet.find(suelto.id).criteria.first.name }).to eq("Renombrado")
    end
  end

  # Un set inline es de un módulo: no se comparte, así que versionarlo no
  # protegería a nadie. Ahí el candado sigue siendo la respuesta correcta.
  describe "con evaluaciones ya hechas sobre el set propio de un módulo" do
    let!(:set) do
      as_company(company) do
        challenge = create(:challenge)
        seed_form!(challenge.steps.create!(kind: "ideation", position: 1))
        step = challenge.steps.create!(kind: "evaluation", position: 2)

        s = CriteriaSet.create!(name: "Técnica", scope: "inline", owner_step_id: step.id)
        s.criteria.create!(name: "Impacto", key: "impacto", weight: 1, source: "manual",
                           scale_type: "numeric", scale_config: { "min" => 1, "max" => 10 })
        s.refresh_status!
        step.update!(criteria_set: s)

        author = Flow::Tenant.bypass! { create(:user) }
        idea = create(:idea, challenge: challenge, author: author)
        Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => "Una" }).call

        assessment = Assessment.create!(challenge_step: step, idea: idea,
                                        idea_version_id: idea.current_version_id,
                                        evaluator_id: owner.id, actor_type: "human")
        AssessmentScore.create!(assessment: assessment, criterion: s.criteria.first,
                                criterion_key: "impacto", weight_used: 1,
                                raw_value: "8", numeric_value: 8, normalized_value: 0.777)
        s
      end
    end

    def first_criterion = as_company(company) { CriteriaSet.find(set.id).criteria.ordered.first }

    def reloaded_criteria = as_company(company) { CriteriaSet.find(set.id).criteria.ordered.to_a }

    before { sign_in(owner, company: company) }

    it "avisa que lo estructural quedó cerrado" do
      get edit_criteria_set_path(set)
      expect(response.body).to include("Ya hay evaluaciones hechas con este set")
    end

    it "renombrar sigue abierto: no cambia el sentido de lo puntuado" do
      put api_v1_criteria_set_path(set), params: {
        name: "Técnica", criteria: [criterion_params(id: first_criterion.id, name: "Impacto real")]
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(reloaded_criteria.first.name).to eq("Impacto real")
    end

    # Cambiar el peso reescribiría el sentido de las notas ya puestas: la misma
    # evaluación pasaría a valer otra cosa.
    it "cambiar el peso o la escala NO" do
      put api_v1_criteria_set_path(set), params: {
        name: "Técnica",
        criteria: [criterion_params(id: first_criterion.id, name: "Impacto", weight: 40,
                                    scale_config: { min: 1, max: 100 })]
      }, as: :json

      criterion = reloaded_criteria.first
      expect(criterion.weight.to_f).to eq(1.0)
      expect(criterion.scale_config["max"]).to eq(10)
    end

    it "quitar un criterio tampoco, y lo dice" do
      put api_v1_criteria_set_path(set), params: { name: "Técnica", criteria: [] }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["errors"].join).to include("No se pueden quitar criterios")
      expect(reloaded_criteria.size).to eq(1)
    end
  end

  describe "quién puede" do
    it "quien participa, no" do
      sign_in(participant, company: company)
      get new_criteria_set_path

      expect(response).to have_http_status(:forbidden).or have_http_status(:found)
    end

    it "no se puede escribir en un set de otra empresa" do
      other = without_tenant { create(:company, slug: "otra") }
      ajeno = as_company(other) { CriteriaSet.create!(name: "Ajeno", scope: "library") }

      sign_in(owner, company: company)
      put api_v1_criteria_set_path(ajeno), params: { name: "Robado", criteria: [] }, as: :json

      expect(response).to have_http_status(:not_found)
      expect(as_company(other) { ajeno.reload.name }).to eq("Ajeno")
    end
  end
end
