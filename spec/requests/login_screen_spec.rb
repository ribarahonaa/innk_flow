# frozen_string_literal: true

require "rails_helper"

# La pantalla de login lista las cuentas sembradas.
#
# Tener nueve cuentas y no saber cuál es cuál es lo mismo que no tenerlas: se
# entra a ver el producto desde cada rol sin pedirle credenciales a nadie.
RSpec.describe "la pantalla de login", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme", name: "Acme") } }
  let!(:otra) { without_tenant { create(:company, slug: "otra", name: "Otra") } }

  let!(:ana) do
    without_tenant do
      u = create(:user, email: "ana@demo.test", name: "Ana Admin")
      create(:membership, :admin, company: company, user: u)
      u
    end
  end

  let!(:marta) do
    without_tenant do
      u = create(:user, email: "marta@demo.test", name: "Marta Multiempresa")
      create(:membership, :admin, company: company, user: u)
      create(:membership, :admin, company: otra, user: u)
      u
    end
  end

  # Una cuenta real no puede tener un dominio `.test`: está reservado por RFC.
  let!(:real) { without_tenant { create(:user, email: "alguien@innk.cl", name: "Real") } }

  it "lista las cuentas de demo con su rol" do
    get login_path

    expect(response.body).to include("ana@demo.test", "Ana Admin")
    expect(response.body).to include(Flow::Demo::PASSWORD)
    expect(response.body).to include("administra")
  end

  # Dos chips iguales no distinguen nada: con más de una empresa hay que decir
  # cuál es cuál.
  it "nombra la empresa cuando alguien está en más de una" do
    get login_path

    expect(response.body).to include("acme · ", "otra · ")
  end

  it "no muestra cuentas que no sean de la demo" do
    get login_path

    expect(response.body).not_to include("alguien@innk.cl")
  end

  # Un clic precarga el correo: la pantalla no carga ningún bundle de JS.
  it "un clic precarga el correo, sin JavaScript" do
    get login_path(email: "ana@demo.test")

    # Rails ordena los atributos como quiere; lo que importa es que el input
    # del correo llegue con el valor puesto.
    expect(response.body).to match(/<input value="ana@demo\.test"[^>]*name="email"/)
  end

  # Con una base real esto sería un tablón con las llaves puestas.
  it "en producción no lista nada" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

    get login_path

    expect(response.body).not_to include("ana@demo.test")
    expect(response.body).not_to include(Flow::Demo::PASSWORD)
  end
end
