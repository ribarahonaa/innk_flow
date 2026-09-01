# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("spec/system_support/driver")

# La isla del builder tiene que montar por LOS DOS caminos.
#
# Turbo intercepta los links y reemplaza el body por fetch, sin disparar
# DOMContentLoaded. Una isla que solo escucha ese evento monta al entrar por
# URL directa y deja "Cargando el editor de flujo…" al llegar por un link —
# que es como navega una persona.
#
# El setup no usa `pipeline.start!`: ese método abre `with_lock` (SELECT FOR
# UPDATE) y deadlockea contra el pool compartido de los system specs.
RSpec.describe "isla del builder", type: :system, js: true do
  let!(:company) { Flow::Tenant.bypass! { Company.create!(name: "Acme", slug: "acme") } }
  let!(:owner) do
    Flow::Tenant.bypass! do
      user = User.create!(email: "owner@test.dev", name: "Olga Owner", password: "Test1234")
      Membership.create!(company: company, user: user, role: "owner")
      user
    end
  end
  let!(:challenge) do
    Flow::Tenant.with(company) do
      c = Challenge.create!(name: "Merma", brief: "Reducir merma.", slug: "merma")
      c.steps.create!(kind: "ideation", position: 1, name: "Postulación")
      c.steps.create!(kind: "evaluation", position: 2, name: "Evaluación")
      c
    end
  end

  before do
    visit login_path
    fill_in "email", with: owner.email
    fill_in "password", with: "Test1234"
    click_button "Entrar"
  end

  it "monta entrando por URL directa" do
    visit builder_challenge_path(challenge)

    expect(page).to have_css(".builder .step-card", wait: 10)
    expect(page).to have_no_css(".island-placeholder")
  end

  it "monta navegando por el link, que es lo que hace una persona" do
    visit challenge_path(challenge)
    click_link "Editar flujo"

    expect(page).to have_css(".builder .step-card", wait: 10)
    expect(page).to have_no_css(".island-placeholder"),
                    "quedó el placeholder: la isla no montó tras la navegación de Turbo"
    expect(page).to have_content("Postulación")
  end

  it "sigue montada al volver al builder por segunda vez" do
    visit challenge_path(challenge)
    click_link "Editar flujo"
    expect(page).to have_css(".builder", wait: 10)

    click_link "Ver desafío"
    expect(page).to have_css(".step-table", wait: 10)

    click_link "Editar flujo"
    expect(page).to have_css(".builder .step-card", wait: 10)
    expect(page).to have_no_css(".island-placeholder")
  end
end
