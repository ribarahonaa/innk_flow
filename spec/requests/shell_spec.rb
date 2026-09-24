# frozen_string_literal: true

require "rails_helper"

# El shell de tres regiones. La regla que decide qué se dibuja no es «qué
# controller es» sino «hay un desafío en contexto»: el flujo solo tiene sentido
# adentro de uno.
RSpec.describe "el shell", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }
  let!(:admin) do
    without_tenant do
      u = create(:user, email: "admin@test.dev")
      create(:membership, :admin, company: company, user: u)
      u
    end
  end

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma")
      seed_form!(c.steps.create!(kind: "ideation", position: 1))
      c.steps.create!(kind: "evaluation", position: 2, name: "Comité")
      c
    end
  end

  before { sign_in(admin, company: company) }

  it "dibuja el flujo del desafío en la pantalla del desafío" do
    get challenge_path(challenge)

    expect(response.body).to include("flow-drawer")
    expect(response.body).to include("Comité")
  end

  it "y también dentro de un módulo" do
    paso = as_company(company) { challenge.steps.find_by(kind: "evaluation") }
    get challenge_step_path(challenge, paso)

    expect(response.body).to include("flow-drawer")
  end

  # La pantalla de error se pinta cuando el `around_action` ya limpió el
  # tenant, así que el drawer no puede pedirle los módulos al desafío: sin
  # guard, TODO 404 adentro de un desafío se convierte en un 500.
  it "no rompe la pantalla de 404 de adentro de un desafío" do
    get challenge_idea_path(challenge, "no-existe")

    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include("flow-drawer")
  end

  # El contador de la cabecera cuenta los pasos LISTOS, y el pie de esa misma
  # pantalla dice «Paso 3 de 9», que es una POSICIÓN. Sin la palabra convivían
  # dos «de 9» distintos en una pantalla y el de arriba se leía como el de
  # abajo.
  it "dice qué cuenta el contador de la cabecera" do
    get challenge_path(challenge)

    expect(response.body).to include("3 de 5 listos")
  end

  # Cero módulos es la ficha recién creada, antes de pasar por el builder: ahí
  # el único paso hecho es el brief.
  it "y lo concuerda en singular" do
    recien_creado = as_company(company) { create(:challenge, name: "Recién creado") }

    get challenge_path(recien_creado)

    expect(response.body).to include("1 de 3 listo")
  end

  # Sin desafío no hay flujo que mostrar, y una barra lateral vacía es peor que
  # ninguna: ocupa un cuarto de la pantalla para no decir nada.
  it "NO lo dibuja fuera de un desafío" do
    get criteria_sets_path
    expect(response.body).not_to include("flow-drawer")

    get members_path
    expect(response.body).not_to include("flow-drawer")
  end
end
