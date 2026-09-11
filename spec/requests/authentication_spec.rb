# frozen_string_literal: true

require "rails_helper"

RSpec.describe "autenticación", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }
  let!(:other)   { without_tenant { create(:company, slug: "otra") } }
  let!(:user) do
    without_tenant do
      u = create(:user, email: "ana@test.dev", name: "Ana Admin", password: "Test1234")
      create(:membership, :owner, company: company, user: u)
      u
    end
  end

  it "el home exige sesión" do
    get root_path
    expect(response).to redirect_to(login_path)
  end

  it "entra con credenciales válidas y queda en su empresa" do
    post login_path, params: { email: "ana@test.dev", password: "Test1234" }
    expect(response).to redirect_to(root_path)

    follow_redirect!
    expect(response.body).to include(company.name)
    expect(response.body).to include("Ana Admin")
  end

  it "rechaza credenciales inválidas" do
    post login_path, params: { email: "ana@test.dev", password: "incorrecta" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("incorrectos")
  end

  it "no distingue email inexistente de contraseña incorrecta" do
    post login_path, params: { email: "nadie@test.dev", password: "Test1234" }
    expect(response.body).to include("incorrectos")
  end

  it "con dos membresías pide elegir empresa" do
    without_tenant { create(:membership, :admin, company: other, user: user) }

    post login_path, params: { email: "ana@test.dev", password: "Test1234" }
    expect(response).to redirect_to(select_company_path)
  end

  it "cerrar sesión destruye la fila de sesión" do
    sign_in(user, company: company)
    expect { delete logout_path }.to change { without_tenant { Session.count } }.by(-1)
  end
end
