# frozen_string_literal: true

require "rails_helper"

RSpec.describe "la cara de configuración de un testing", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  let!(:admin) do
    without_tenant do
      u = create(:user, email: "admin@test.dev", name: "Ana Admin")
      create(:membership, :admin, company: company, user: u)
      u
    end
  end

  let!(:mirona) do
    without_tenant do
      u = create(:user, email: "mirona@test.dev", name: "Mica Mirona")
      create(:membership, company: company, user: u, role: "participant")
      u
    end
  end

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma")
      seed_form!(c.steps.create!(kind: "ideation", position: 1))
      c.steps.create!(kind: "testing", position: 2, name: "Prueba de factibilidad")
      c
    end
  end

  def paso = as_company(company) { challenge.steps.reload.find(&:testing?) }

  it "monta la isla de ajustes para quien configura" do
    sign_in(admin, company: company)
    get challenge_step_path(challenge, paso)

    expect(response.body).to include("step-settings")
    expect(response.body).to include("Dimensiones que hay que cubrir")
  end

  # La pantalla la sirve `ChallengeStepPolicy#show?` —cualquiera de la
  # empresa—, así que sin una guarda más estricta adentro la isla y el botón
  # quedan montados para quien no puede usarlos, y apretarlos rebota en 403.
  #
  # Las dos aserciones negativas van sobre nodos puntuales y no sobre texto
  # libre: "Guardar" y "step-settings" son cadenas comunes, y `not_to
  # include` a secas se rompe por un motivo ajeno el día que otra pantalla
  # comparta esa palabra. Se comprobó que hoy son únicas en esta vista —el
  # único "Guardar" es `f.submit "Guardar el módulo"` dentro de
  # `steps/config/_modulo`, y el único "step-settings" es el
  # `data-island` de esa misma isla—, pero el selector deja la prueba atada
  # al nodo real y no a esa casualidad.
  it "a quien no configura no le sirve ni la isla ni el botón" do
    sign_in(mirona, company: company)
    get challenge_step_path(challenge, paso)

    expect(response).to have_http_status(:ok)

    documento = Nokogiri::HTML(response.body)
    expect(documento.css('[data-island="step-settings"]')).to be_empty
    expect(documento.css('input[type="submit"], button[type="submit"]').map { |n| n["value"] || n.text })
      .not_to include(a_string_matching(/Guardar/))
  end

  # `setup_nav` es lo ÚNICO que avanza el paso a paso. Sin su render acá el
  # recorrido se corta en este módulo, y el paso sigue apareciendo en el
  # drawer igual: no se nota mirando. Pasó de verdad con `:form` (2029528).
  it "renderiza el pie del paso a paso" do
    sign_in(admin, company: company)
    get challenge_step_path(challenge, paso)

    expect(response.body).to include("setup-nav")
  end
end
