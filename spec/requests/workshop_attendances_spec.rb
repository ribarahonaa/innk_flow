# frozen_string_literal: true

require "rails_helper"

# Marcar presente o ausente a mano. Es el único escritor de presencia en un
# taller con la asistencia presumida, y el que cubre a quien vino sin teléfono.
RSpec.describe "la asistencia a mano", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email, role)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, role.to_sym, company: company, user: u)
      u
    end
  end

  let!(:admin) { member("admin@test.dev", :admin) }
  let!(:paula) { member("paula@test.dev", :participant) }

  let!(:taller) { as_company(company) { create(:workshop, status: "open") } }
  let!(:asiento) do
    as_company(company) do
      mesa = create(:workshop_group, workshop: taller, name: "Mesa de Paula")
      WorkshopGroupMember.create!(workshop_group: mesa, user_id: paula.id, attended: true)
    end
  end

  it "marca ausente" do
    sign_in(admin, company: company)

    patch attendance_workshop_path(taller), params: { user_id: paula.id, attended: "false" }

    expect(as_company(company) { asiento.reload.attended }).to be(false)
  end

  it "marca presente de vuelta" do
    as_company(company) { asiento.update!(attended: false) }
    sign_in(admin, company: company)

    patch attendance_workshop_path(taller), params: { user_id: paula.id, attended: "true" }

    expect(as_company(company) { asiento.reload.attended }).to be(true)
  end

  it "no lo puede hacer quien participa" do
    sign_in(paula, company: company)

    patch attendance_workshop_path(taller), params: { user_id: paula.id, attended: "false" }

    # Sin flash: Pundit levanta y el rescue global responde 403 directo.
    expect(response).to have_http_status(:forbidden)
    expect(as_company(company) { asiento.reload.attended }).to be(true)
  end

  # Con el taller cerrado no se toca nada, igual que convocar y desconvocar.
  it "no toca nada con el taller cerrado" do
    as_company(company) { taller.update!(status: "closed") }
    sign_in(admin, company: company)

    patch attendance_workshop_path(taller), params: { user_id: paula.id, attended: "false" }

    expect(flash[:alert]).to eq("Este taller ya cerró: la asistencia queda como está.")
    expect(as_company(company) { asiento.reload.attended }).to be(true)
  end

  # Sólo acepta los dos valores que manda la pantalla: sin `attended` la
  # columna NOT NULL daba un 500, y cualquier otro valor se leía como presente.
  [{}, { attended: "" }, { attended: "banana" }].each do |extra|
    it "rechaza #{extra.inspect} sin tocar nada ni dar 500" do
      as_company(company) { asiento.update!(attended: false) }
      sign_in(admin, company: company)

      patch attendance_workshop_path(taller), params: { user_id: paula.id }.merge(extra)

      expect(flash[:alert]).to eq("La asistencia tiene que ser presente o ausente.")
      expect(as_company(company) { asiento.reload.attended }).to be(false)
    end
  end

  it "da 404 por alguien que no está sentado" do
    pedro = member("pedro@test.dev", :participant)
    sign_in(admin, company: company)

    patch attendance_workshop_path(taller), params: { user_id: pedro.id, attended: "false" }

    expect(response).to have_http_status(:not_found)
  end

  describe "el control" do
    it "lo ve quien administra, con el estado actual" do
      sign_in(admin, company: company)

      get workshop_path(taller)

      expect(response.body).to include(attendance_workshop_path(taller))
      expect(response.body).to include("Marcar ausente")
    end

    it "no lo ve quien participa" do
      as_company(company) { create(:workshop_group, workshop: taller, name: "Mesa de otras personas") }
      sign_in(paula, company: company)

      get workshop_path(taller)

      expect(response).to have_http_status(:ok)
      # Quien participa no ve la lista de mesas entera: vive detrás del
      # `can_assemble` de `show`, no de `can_edit`. Sí ve SU mesa, en el panel
      # «Tu mesa» (`workshops/_my_group`), así que la ausencia se prueba con la
      # mesa de otras personas y no con la suya. El control positivo es que
      # la pantalla sí se rinde para esa persona (el nombre del taller sale del
      # encabezado, que se sirve siempre), y el contraste, el ejemplo del admin
      # de arriba, que sí ve el botón con este mismo taller.
      expect(response.body).to include(taller.name)
      expect(response.body).to include("Tu mesa")
      expect(response.body).not_to include("Mesa de otras personas")
      expect(response.body).not_to include(attendance_workshop_path(taller))
    end

    # Es la puerta de la VISTA: el botón cuelga de `can_edit`, y ofrecerlo con
    # el taller cerrado sería un control que el controller rechaza.
    it "no lo ofrece con el taller cerrado" do
      as_company(company) { taller.update!(status: "closed") }
      sign_in(admin, company: company)

      get workshop_path(taller)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(paula.name)
      expect(response.body).not_to include(attendance_workshop_path(taller))
      expect(response.body).not_to include("Marcar ausente")
    end
  end
end
