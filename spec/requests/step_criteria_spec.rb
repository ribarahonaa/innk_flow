# frozen_string_literal: true

require "rails_helper"

# Los criterios de un módulo, definidos sin salir del desafío.
#
# El modelo ya soportaba sets `inline` —atados a un módulo— pero nada los
# creaba salvo el propio handler AL ACTIVAR, cuando su dueño ya no los ve
# venir. El único camino visible era la biblioteca.
RSpec.describe "criterios de un módulo", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  let!(:owner) do
    without_tenant do
      u = create(:user, email: "owner@test.dev")
      create(:membership, :owner, company: company, user: u)
      u
    end
  end

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma")
      seed_form!(c.steps.create!(kind: "ideation", position: 1, name: "Postulación"))
      c.steps.create!(kind: "evaluation", position: 2, name: "Técnica")
      c
    end
  end

  def step = as_company(company) { challenge.steps.reload.find(&:evaluation?) }
  def criteria_path = challenge_step_criteria_path(challenge, step)
  def set_of(a_step) = as_company(company) { ChallengeStep.find(a_step.id).criteria_set }
  def criteria_of(a_step) = as_company(company) { ChallengeStep.find(a_step.id).criteria_set.criteria.ordered.to_a }

  before { sign_in(owner, company: company) }

  describe "cuando el módulo no tiene criterios propios" do
    it "dice con qué va a correr y ofrece las salidas" do
      get criteria_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("todavía no tiene criterios propios",
                                       "Usar los tres genéricos y editarlos",
                                       "Empezar en blanco")
    end

    it "«los tres genéricos» los crea atados a ESTE módulo" do
      post criteria_path, params: { from: "defaults" }

      set = set_of(step)
      expect(set.scope).to eq("inline")
      expect(as_company(company) { set.owner_step_id }).to eq(step.id)
      expect(criteria_of(step).map(&:key)).to eq(%w[impacto factibilidad esfuerzo])
    end

    it "«en blanco» crea el set vacío, para armarlo desde cero" do
      post criteria_path, params: { from: "blank" }

      expect(criteria_of(step)).to be_empty
      expect(set_of(step).status).to eq("invalid")
    end

    it "y después de crearlos, monta el editor" do
      post criteria_path, params: { from: "defaults" }
      get criteria_path

      expect(response.body).to include('data-island="criteria-editor"')
      expect(response.body).to include("no afectan a otros desafíos")
    end
  end

  describe "cuando el módulo apunta a un set de la biblioteca" do
    let!(:library) do
      as_company(company) do
        s = CriteriaSet.create!(name: "Estándar", scope: "library")
        s.criteria.create!(name: "Impacto", key: "impacto", weight: 1, source: "manual",
                           scale_type: "numeric", scale_config: { "min" => 1, "max" => 10 })
        s.refresh_status!
        s
      end
    end

    before { as_company(company) { ChallengeStep.find(step.id).update!(criteria_set_id: library.id) } }

    # Editar el set de la biblioteca desde el módulo tocaría a todos los
    # desafíos que lo comparten. Se copia, no se apunta.
    it "no deja editarlo desde acá: ofrece copiarlo" do
      get criteria_path

      expect(response.body).to include("Estándar", "Copiar ese set y hacerlo propio")
      expect(response.body).not_to include('data-island="criteria-editor"')
    end

    it "copiar deja la biblioteca intacta" do
      post criteria_path, params: { from: "library" }

      copy = set_of(step)
      expect(copy.id).not_to eq(library.id)
      expect(copy.scope).to eq("inline")
      expect(criteria_of(step).map(&:key)).to eq(%w[impacto])
      expect(as_company(company) { CriteriaSet.library.pluck(:name) }).to eq(["Estándar"])
    end
  end

  describe "con el módulo ya ejecutado" do
    before { as_company(company) { ChallengeStep.find(step.id).update_column(:status, "completed") } }

    it "no se crean criterios nuevos: quedaron congelados" do
      post criteria_path, params: { from: "defaults" }

      expect(flash[:alert]).to include("ya se ejecutó")
      expect(set_of(step)).to be_nil
    end
  end

  # Un criterio de fórmula guarda el resultado crudo porque de ahí sale la
  # normalización. Mostrarlo entero en la ficha no le dice nada a nadie.
  describe "cómo se muestra un puntaje derivado" do
    it "redondea el resultado de una fórmula, y deja los enteros enteros" do
      # `.new` ya toca el default_scope, así que también va dentro del tenant.
      as_company(company) do
        score = AssessmentScore.new(criterion_key: "prioridad", raw_value: "1.1428571428571428571",
                                    numeric_value: BigDecimal("1.1428571428571428571"))
        expect(score.display_value).to eq("1.14")

        entero = AssessmentScore.new(criterion_key: "impacto", raw_value: "8", numeric_value: 8)
        expect(entero.display_value).to eq("8")

        vacio = AssessmentScore.new(criterion_key: "impacto", raw_value: nil)
        expect(vacio.display_value).to eq("—")
      end
    end
  end

  # Los criterios cuelgan de un módulo, así que redirigir por tipo de objetivo
  # sacaba de la pantalla de criterios justo al aplicarlos.
  describe "proponer los criterios con IA" do
    it "la pantalla lo ofrece cuando el módulo no tiene criterios propios" do
      get criteria_path
      expect(response.body).to include("Proponer criterios con IA")
    end

    it "aplicar la propuesta deja en la pantalla de criterios, con el set puesto" do
      post challenge_ai_requests_path(challenge, purpose: "suggest_criteria", step_id: step.id)
      sugerencia = as_company(company) { AiSuggestion.pending_review.order(:created_at).last }

      post accept_ai_suggestion_path(sugerencia)

      expect(response).to redirect_to(criteria_path)
      expect(set_of(step)&.scope).to eq("inline")
      expect(criteria_of(step)).not_to be_empty
    end
  end

  describe "dónde no aplica" do
    it "un módulo de ideación no tiene criterios: 404" do
      ideation = as_company(company) { challenge.steps.reload.find(&:ideation?) }
      get challenge_step_criteria_path(challenge, ideation)

      expect(response).to have_http_status(:not_found)
    end
  end
end
