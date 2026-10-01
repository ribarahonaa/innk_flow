# frozen_string_literal: true

require "rails_helper"

# La ÚNICA ruta pública de la app: se entra con el token y sin sesión.
#
# Lo que se fija acá es tanto que entre como que no sea un oráculo: con un
# formulario único para «ya tengo cuenta» y «no tengo», el mensaje de error no
# puede decir si el email existía.
RSpec.describe "check-in por link", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email, role)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, role.to_sym, company: company, user: u)
      u
    end
  end

  let!(:admin) { member("admin@test.dev", :admin) }

  # Sin desafíos vinculados a propósito: nada de lo que se prueba acá los
  # necesita. `CheckIn` pide taller abierto y modo puesto, y `workshops#show`
  # renderiza con `@links` vacío —`MaterializeClosures` sobre cero vínculos no
  # hace nada—. El estado se escribe directo porque lo que se prueba es el
  # check-in y no `Flow::Workshops::Open`.
  def workshop(status: "open", registered: true)
    as_company(company) do
      create(:workshop, status: status,
                        attendance_mode: registered ? "registered" : "presumed")
    end
  end

  let!(:taller) { workshop }
  let(:url) { checkin_path(taller.checkin_token) }

  describe "GET" do
    it "da 404 con un token que no existe" do
      get checkin_path("no-existe")

      expect(response).to have_http_status(:not_found)
    end

    it "sirve el formulario sin sesión" do
      get url

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Entrar al taller")
    end

    # Con el token en la mano ya se sabe que el taller existe, así que decir por
    # qué no se puede entrar no confirma nada. 200 y no 4xx: la pantalla
    # renderizó bien, y `make screens` falla con cualquier >= 400 no declarado.
    it "explica el borrador en vez de dar el formulario" do
      borrador = workshop(status: "draft")
      get checkin_path(borrador.checkin_token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("todavía no está abierto")
      expect(response.body).not_to include("Entrar al taller")
    end

    it "explica el modo apagado" do
      apagado = workshop(registered: false)
      get checkin_path(apagado.checkin_token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("no toma asistencia por link")
    end
  end

  describe "POST sin cuenta" do
    it "crea cuenta, identidad, membresía, asiento presente y sesión" do
      expect {
        post url, params: { email: "nueva@taller.example", name: "Nueva", password: "Test1234" }
      }.to change { without_tenant { User.count } }.by(1)

      user = without_tenant { User.find_by(email: "nueva@taller.example") }
      expect(without_tenant { Identity.exists?(provider: Identity::PASSWORD, uid: user.email) }).to be(true)
      expect(without_tenant { Membership.find_by(user_id: user.id, company_id: company.id).role }).to eq("participant")

      asiento = as_company(company) do
        WorkshopGroupMember.joins(:workshop_group)
                           .find_by(workshop_groups: { workshop_id: taller.id }, user_id: user.id)
      end
      expect(asiento.attended).to be(true)
      expect(response).to redirect_to(workshop_path(taller))

      # La sesión quedó abierta: el taller se puede ver sin volver a loguearse.
      follow_redirect!
      expect(response).to have_http_status(:ok)
    end

    it "rechaza una clave corta sin crear nada" do
      expect {
        post url, params: { email: "corta@taller.example", name: "Corta", password: "123" }
      }.not_to change { without_tenant { User.count } }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST con una cuenta que ya existe" do
    it "entra con la clave correcta sin crear otra cuenta" do
      expect {
        post url, params: { email: "admin@test.dev", name: "Ignorado", password: "Test1234" }
      }.not_to change { without_tenant { User.count } }

      expect(response).to redirect_to(workshop_path(taller))
    end

    # El mensaje es el MISMO del login: si dijera «esa cuenta ya existe» el
    # formulario sería un oráculo de cuentas de toda la instalación.
    it "con la clave mala no revela que el email existe" do
      post url, params: { email: "admin@test.dev", name: "X", password: "mala1234" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("auth.invalid_credentials"))
      expect(response.body).not_to match(/ya (existe|está)/i)
    end

    # Review Focus 1: el teléfono autocapitaliza y agrega un espacio. Sin
    # normalizar en NINGÚN lado, el `find_by` no encuentra la cuenta y el create
    # choca contra el índice único de la base: 500 en la cara de quien entra —
    # `User` no tiene validación de unicidad, sólo presencia y formato—.
    #
    # Hoy hay dos normalizaciones y el ejemplo se cumple con cualquiera de las
    # dos: la del controller y el `normalizes :email` de `User`, que en Rails 7.1
    # normaliza también el valor de los finders. Medido con una mutación de cada
    # lado: saliendo una sigue verde, saliendo las dos se pone rojo. Por eso
    # afirma a quién dejó entrar y no sólo que no creó una cuenta: con el asiento
    # del admin, «no creó nada» no se puede cumplir reventando.
    it "normaliza el email tipeado con mayúsculas y espacios" do
      expect {
        post url, params: { email: " Admin@Test.DEV ", name: "X", password: "Test1234" }
      }.not_to change { without_tenant { User.count } }

      expect(response).to redirect_to(workshop_path(taller))
      asiento = as_company(company) do
        WorkshopGroupMember.joins(:workshop_group)
                           .find_by(workshop_groups: { workshop_id: taller.id }, user_id: admin.id)
      end
      expect(asiento).to be_present
    end

    # Review Focus: escanear su propio QR no le puede bajar el rol a quien
    # administra, ni reventar contra el UNIQUE (user_id, company_id).
    #
    # El redirect va PRIMERO y no es decoración: con el rol en el `where` del
    # `find_or_create_by!` la membresía no se encuentra, el create choca contra
    # el UNIQUE y el request muere en 500 — o sea que el rol tampoco cambia y
    # mirar sólo el rol daba verde justo con la mutación que esto tiene que
    # cazar. Medido.
    it "no le baja el rol a quien ya es admin" do
      post url, params: { email: "admin@test.dev", name: "X", password: "Test1234" }

      expect(response).to redirect_to(workshop_path(taller))
      expect(without_tenant { Membership.find_by(user_id: admin.id, company_id: company.id).role }).to eq("admin")
    end

    # Review Focus 4: alguien de otra empresa. Queda con las dos membresías y la
    # sesión en la empresa del taller.
    it "le suma la membresía sin sacarle la que tenía en otra empresa" do
      otra = without_tenant { create(:company, slug: "otra") }
      viajera = without_tenant do
        u = create(:user, email: "viajera@test.dev")
        create(:membership, :participant, company: otra, user: u)
        u
      end

      post url, params: { email: viajera.email, name: "X", password: "Test1234" }

      roles = without_tenant { Membership.where(user_id: viajera.id).pluck(:company_id) }
      expect(roles).to contain_exactly(otra.id, company.id)
      expect(response).to redirect_to(workshop_path(taller))
    end
  end

  describe "POST con sesión viva" do
    it "entra sin pedir el formulario" do
      sign_in(admin, company: company)

      post url

      expect(response).to redirect_to(workshop_path(taller))
      asiento = as_company(company) do
        WorkshopGroupMember.joins(:workshop_group)
                           .find_by(workshop_groups: { workshop_id: taller.id }, user_id: admin.id)
      end
      expect(asiento.attended).to be(true)
    end
  end

  # Review Focus 3: el taller se cierra entre el GET y el POST. Tiene que
  # explicar, no reventar ni redirigir a un taller que todavía no puede ver.
  describe "cuando el taller se cierra entre el GET y el POST" do
    it "explica en vez de entrar" do
      get url
      as_company(company) { taller.update!(status: "closed") }

      post url, params: { email: "tarde@taller.example", name: "Tarde", password: "Test1234" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("ya cerró")
      expect(without_tenant { User.exists?(email: "tarde@taller.example") }).to be(false)
    end
  end
end
