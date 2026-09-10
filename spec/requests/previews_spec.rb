# frozen_string_literal: true

require "rails_helper"

# La previsualización.
#
# Hasta acá el dueño configuraba a ciegas: el formulario de postulación y la
# ficha de evaluación recién se veían con el desafío ya en curso, cuando la
# ventana para cambiarlos estaba cerrada.
RSpec.describe "previsualizar el desafío", type: :request do
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

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma")
      seed_form!(c.steps.create!(kind: "ideation", position: 1, name: "Postulación"))
      c.steps.create!(kind: "evaluation", position: 2, name: "Técnica")
      c.steps.create!(kind: "selection", position: 3, name: "Corte",
                      config: { "cut" => { "mode" => "top_n", "value" => 5 } })
      c
    end
  end

  before { sign_in(owner, company: company) }

  it "muestra el formulario real que responde quien postula" do
    get challenge_preview_path(challenge)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Título", "¿Qué problema resuelve?", "¿Cómo funcionaría?")
    # No es una maqueta: son los mismos campos, con sus names reales.
    expect(response.body).to include('name="payload[titulo]"')
  end

  # Sin esto el preview sería una pantalla que se puede completar, y alguien
  # va a intentarlo.
  it "y no se puede escribir en él" do
    get challenge_preview_path(challenge)
    expect(response.body).to include("<fieldset class=\"preview-surface\" disabled>")
  end

  # `criteria_snapshot` solo existe una vez congelado el módulo. Sin resolver
  # los genéricos, la ficha se vería vacía justo cuando todavía se puede
  # cambiar.
  it "muestra la ficha de evaluación con los criterios genéricos si el módulo no tiene los suyos" do
    get challenge_preview_path(challenge)

    expect(response.body).to include("Impacto", "Factibilidad", "Esfuerzo")
    expect(response.body).to include("criterios genéricos")
    expect(response.body).to include('name="scores[impacto]"')
  end

  it "y con los propios cuando el módulo los tiene" do
    as_company(company) do
      set = CriteriaSet.create!(name: "Propios", scope: "library")
      set.criteria.create!(name: "Riesgo legal", key: "riesgo", weight: 1, source: "manual",
                           scale_type: "boolean", scale_config: { "true_label" => "Hay riesgo",
                                                                  "false_label" => "No hay" })
      set.refresh_status!
      challenge.steps.find_by(kind: "evaluation").update!(criteria_set: set)
    end

    get challenge_preview_path(challenge)

    expect(response.body).to include("Riesgo legal", "Hay riesgo")
    expect(response.body).not_to include("criterios genéricos")
  end

  it "explica el corte de una selección en palabras" do
    get challenge_preview_path(challenge)

    expect(response.body).to include("avanzan las 5 mejores")
  end

  it "avisa cuando «Idear» no tiene formulario, con el link para resolverlo" do
    ideation = as_company(company) do
      step = challenge.pipeline.ideation_step
      step.form_fields.destroy_all
      step
    end

    get challenge_preview_path(challenge)

    expect(response.body).to include("Sin campos: nadie puede postular")
    expect(response.body).to include(challenge_step_path(challenge, ideation))
  end

  it "un desafío sin módulos lo dice, en vez de mostrar una página vacía" do
    vacio = as_company(company) { create(:challenge, name: "Vacío") }

    get challenge_preview_path(vacio)

    expect(response.body).to include("todavía no tiene módulos")
  end

  describe "quién puede" do
    it "quien participa, no: es la pantalla de quien configura" do
      sign_in(participant, company: company)
      get challenge_preview_path(challenge)

      expect(response).to have_http_status(:forbidden).or have_http_status(:found)
    end

    it "el desafío de otra empresa da 404" do
      other = without_tenant { create(:company, slug: "otra") }
      ajeno = as_company(other) { create(:challenge) }

      get challenge_preview_path(ajeno)
      expect(response).to have_http_status(:not_found)
    end
  end
end
