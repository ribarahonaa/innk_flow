# frozen_string_literal: true

require "rails_helper"

# El control de tema.
#
# El mecanismo entero existe para no matar `prefersdark`: el tema oscuro se
# engancha a `@media (prefers-color-scheme: dark) { :root:not([data-theme]) }`,
# así que escribir `data-theme` SIEMPRE —aunque sea con el nombre del tema
# claro— hace que ese selector no matchee nunca.
#
# Por eso son tres estados y no dos, y por eso «Auto» BORRA la cookie en vez de
# escribir "flow".
RSpec.describe "control de tema", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }
  let!(:user) do
    without_tenant do
      u = create(:user, email: "u@test.dev")
      create(:membership, :participant, company: company, user: u)
      u
    end
  end

  before { sign_in user, company: company }

  it "sin cookie no escribe data-theme" do
    get root_path
    expect(response.body).not_to include("data-theme")
  end

  it "elegir el claro escribe la cookie y el atributo" do
    patch theme_path, params: { theme: "flow" }
    expect(response).to have_http_status(:redirect)
    get root_path
    expect(response.body).to include(%(data-theme="flow"))
  end

  it "elegir el oscuro escribe la cookie y el atributo" do
    patch theme_path, params: { theme: "flow-oscuro" }
    get root_path
    expect(response.body).to include(%(data-theme="flow-oscuro"))
  end

  # El caso que justifica todo el diseño: «Auto» tiene que BORRAR. Si escribe
  # "flow", prefersdark queda muerto para siempre y nadie se entera.
  it "volver a Auto borra la cookie y el atributo" do
    patch theme_path, params: { theme: "flow" }
    get root_path
    expect(response.body).to include("data-theme")

    patch theme_path, params: { theme: "auto" }
    get root_path
    expect(response.body).not_to include("data-theme")
  end

  # Review Focus #4: la cookie es entrada del usuario y se renderiza dentro de
  # un atributo del <html>.
  it "ignora un valor que no está en la lista blanca" do
    patch theme_path, params: { theme: "flow-inventado" }
    get root_path
    expect(response.body).not_to include("data-theme")
  end

  it "ignora una cookie forjada a mano" do
    cookies[:theme] = %(" onload="alert(1))
    get root_path
    expect(response.body).not_to include("data-theme")
    expect(response.body).not_to include("onload")
  end

  it "vuelve a donde estabas" do
    patch theme_path, params: { theme: "flow" }, headers: { "HTTP_REFERER" => workshops_url }
    expect(response).to redirect_to(workshops_url)
  end

  # Review Focus #2: el login usa OTRO layout, con su propio <html>.
  it "el login respeta la cookie" do
    patch theme_path, params: { theme: "flow-oscuro" }
    delete logout_path
    get login_path
    expect(response.body).to include(%(data-theme="flow-oscuro"))
  end

  # El login también ofrece el control, así que el PATCH tiene que andar sin
  # sesión: si pidiera autenticación rebotaría al login sin escribir nada.
  it "se puede elegir el tema sin sesión" do
    delete logout_path
    patch theme_path, params: { theme: "flow-oscuro" }
    expect(response).to redirect_to(root_path)
    get login_path
    expect(response.body).to include(%(data-theme="flow-oscuro"))
  end
end
