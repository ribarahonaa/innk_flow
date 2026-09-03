# frozen_string_literal: true

require "rails_helper"

# El índice de criterios del desafío.
#
# El paso 4 del recorrido llevaba directo al primer módulo sin criterios: no se
# veía cuántos módulos puntúan, cuáles estaban resueltos ni en cuál estabas
# parado, y al volver atrás aterrizabas en otro distinto.
RSpec.describe "criterios del desafío", type: :request do
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
      c.steps.create!(kind: "selection", position: 3, name: "Corte")
      c.steps.create!(kind: "evaluation", position: 4, name: "Comité")
      c
    end
  end

  before { sign_in(owner, company: company) }

  it "lista TODOS los módulos que puntúan o filtran, y dice qué hace cada uno" do
    get challenge_criteria_path(challenge)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Técnica", "Corte", "Comité")
    expect(response.body).to include("puntúa cada idea", "filtra qué avanza")
    # «Postulación» no puntúa: no tiene por qué estar acá.
    expect(response.body).not_to include("Postulación</span>")
  end

  it "marca cuáles van a usar los genéricos" do
    get challenge_criteria_path(challenge)
    expect(response.body).to include("Sin criterios propios")
  end

  it "y muestra los criterios del que ya los tiene" do
    as_company(company) do
      step = challenge.steps.reload.find { |s| s.name == "Técnica" }
      set = CriteriaSet.create!(name: "Propios", scope: "inline", owner_step_id: step.id)
      set.criteria.create!(name: "Impacto real", key: "impacto", weight: 1, source: "manual",
                           scale_type: "numeric", scale_config: { "min" => 1, "max" => 10 })
      set.refresh_status!
      step.update!(criteria_set: set)
    end

    get challenge_criteria_path(challenge)

    expect(response.body).to include("Criterios propios de este módulo", "Impacto real", "100%")
  end

  it "un módulo ya ejecutado dice que quedó congelado, en vez de ofrecer editarlo" do
    as_company(company) do
      challenge.steps.reload.find { |s| s.name == "Técnica" }.update_column(:status, "completed")
    end

    get challenge_criteria_path(challenge)

    expect(response.body).to include("quedaron congelados")
  end

  it "un flujo sin módulos que puntúen lo dice, en vez de una lista vacía" do
    vacio = as_company(company) do
      c = create(:challenge, name: "Solo ideas")
      seed_form!(c.steps.create!(kind: "ideation", position: 1))
      c
    end

    get challenge_criteria_path(vacio)

    expect(response.body).to include("no tiene módulos que puntúen")
  end

  it "el de otra empresa da 404" do
    other = without_tenant { create(:company, slug: "otra") }
    ajeno = as_company(other) { create(:challenge) }

    get challenge_criteria_path(ajeno)
    expect(response).to have_http_status(:not_found)
  end
end
