# frozen_string_literal: true

require "rails_helper"

# La regresión más cara de mover la configuración al módulo: el builder guarda
# la lista ENTERA de steps. Si sigue mandando `settings` desde props cargadas
# antes de que alguien configurara el módulo, guardar el flujo lo revierte.
#
# El bloqueo optimista no lo ataja: `lock_version` es del desafío y un PATCH
# al módulo no lo incrementa.
RSpec.describe "guardar el flujo no pisa la configuración de un módulo", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  let!(:admin) do
    without_tenant do
      u = create(:user, email: "admin@test.dev", name: "Ana Admin")
      create(:membership, :admin, company: company, user: u)
      u
    end
  end

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma", ai_default_mode: "human")
      seed_form!(c.steps.create!(kind: "ideation", position: 1))
      c.steps.create!(kind: "selection", position: 2, name: "Corte")
      c
    end
  end

  def corte = as_company(company) { challenge.steps.reload.find(&:selection?) }
  def idear = as_company(company) { challenge.steps.reload.find(&:ideation?) }

  before { sign_in(admin, company: company) }

  it "conserva el config aunque el builder mande el viejo" do
    patch challenge_step_path(challenge, corte),
          params: { challenge_step: { config: { cut: { mode: "top_n", value: "4" } } } }

    # El builder guarda con las props de antes: `settings` vacío.
    put api_v1_challenge_pipeline_path(challenge),
        params: { lock_version: challenge.reload.lock_version,
                  steps: [{ id: idear.id, kind: "ideation", name: idear.name },
                          { id: corte.id, kind: "selection", name: "Corte", settings: {} }] },
        as: :json

    expect(response).to have_http_status(:ok)
    expect(corte.config).to eq("cut" => { "mode" => "top_n", "value" => 4 })
  end

  it "conserva el set de criterios aunque el builder mande null" do
    set = as_company(company) do
      s = CriteriaSet.create!(name: "Filtros", scope: "inline", owner_step: corte, status: "valid")
      s.criteria.create!(name: "¿Claro?", key: "claro", weight: 1, source: "manual",
                         scale_type: "boolean")
      s
    end
    patch challenge_step_path(challenge, corte),
          params: { challenge_step: { criteria_set_id: set.id } }

    put api_v1_challenge_pipeline_path(challenge),
        params: { lock_version: challenge.reload.lock_version,
                  steps: [{ id: idear.id, kind: "ideation", name: idear.name },
                          { id: corte.id, kind: "selection", name: "Corte", criteriaSetId: nil }] },
        as: :json

    expect(corte.criteria_set_id).to eq(set.id)
  end

  it "sigue guardando el nombre y el orden, que son suyos" do
    put api_v1_challenge_pipeline_path(challenge),
        params: { lock_version: challenge.reload.lock_version,
                  steps: [{ id: idear.id, kind: "ideation", name: idear.name },
                          { id: corte.id, kind: "selection", name: "Corte final" }] },
        as: :json

    expect(corte.name).to eq("Corte final")
  end

  # Contra el JSON del endpoint y no contra un regex sobre el HTML: es el
  # mismo presenter, y HAML escapa el `data-props` de formas que el regex
  # atrapa mal.
  it "no publica en las props lo que dejó de ser suyo" do
    get api_v1_challenge_pipeline_path(challenge)

    paso = response.parsed_body["steps"].find { |s| s["kind"] == "selection" }

    expect(paso).not_to have_key("settings")
    expect(paso).not_to have_key("criteriaSetId")
    expect(paso).not_to have_key("sourceStepId")
  end
end
