# frozen_string_literal: true

require "rails_helper"

# Activar el check-in, apagarlo y rotar el link. Los tres detrás de `update?`, y
# los tres con el taller ABIERTO: activarlo con la gente llegando es el caso.
RSpec.describe "los controles del check-in", type: :request do
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

  let!(:taller) do
    as_company(company) do
      t = create(:workshop, status: "draft")
      challenge = create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: "ideation", status: "active")
      create(:workshop_challenge, workshop: t, challenge: challenge, challenge_step: step, status: "open")
      t.update!(status: "open")
      t
    end
  end

  it "quien administra lo activa con el taller abierto" do
    sign_in(admin, company: company)

    post enable_checkin_workshop_path(taller)

    expect(as_company(company) { taller.reload.attendance_mode }).to eq("registered")
  end

  it "lo apaga" do
    as_company(company) { taller.update!(attendance_mode: "registered") }
    sign_in(admin, company: company)

    post disable_checkin_workshop_path(taller)

    expect(as_company(company) { taller.reload.attendance_mode }).to eq("presumed")
  end

  # Rotar es la revocación: el QR que alguien fotografió deja de servir.
  it "rotar invalida el link anterior" do
    as_company(company) { taller.update!(attendance_mode: "registered") }
    anterior = taller.checkin_token
    sign_in(admin, company: company)

    post rotate_checkin_token_workshop_path(taller)

    expect(as_company(company) { taller.reload.checkin_token }).not_to eq(anterior)
    get checkin_path(anterior)
    expect(response).to have_http_status(:not_found)
  end

  # Cambiar el modo NO reescribe la asistencia ya registrada: sería destruir
  # dato por un cambio de configuración. Para eso está el toggle.
  it "activar el modo no marca ausente a quien ya estaba presente" do
    mesa = as_company(company) { create(:workshop_group, workshop: taller) }
    asiento = as_company(company) do
      WorkshopGroupMember.create!(workshop_group: mesa, user_id: paula.id, attended: true)
    end
    sign_in(admin, company: company)

    post enable_checkin_workshop_path(taller)

    expect(as_company(company) { asiento.reload.attended }).to be(true)
  end

  it "quien participa no puede activarlo" do
    as_company(company) do
      mesa = create(:workshop_group, workshop: taller)
      WorkshopGroupMember.create!(workshop_group: mesa, user_id: paula.id)
    end
    sign_in(paula, company: company)

    post enable_checkin_workshop_path(taller)

    expect(response).to have_http_status(:forbidden)
  end

  describe "la pantalla" do
    it "ofrece activarlo, y con el modo puesto muestra el link" do
      sign_in(admin, company: company)
      get workshop_path(taller)
      expect(response.body).to include(enable_checkin_workshop_path(taller))

      as_company(company) { taller.update!(attendance_mode: "registered") }
      get workshop_path(taller)

      expect(response.body).to include(taller.checkin_token)
      expect(response.body).to include(rotate_checkin_token_workshop_path(taller))
      expect(response.body).to include("<svg")
    end

    # El helper inlinea el SVG en un documento HTML: un prólogo XML ahí es basura
    # y además una declaración falsa. Este ejemplo es la única cobertura directa
    # del helper, y lo mide por la pantalla servida.
    it "sirve el QR como <svg> sin el prólogo XML" do
      as_company(company) { taller.update!(attendance_mode: "registered") }
      sign_in(admin, company: company)

      get workshop_path(taller)

      expect(response.body).to include("<svg")
      expect(response.body).not_to include("<?xml")
    end

    it "no se lo ofrece a quien participa" do
      as_company(company) do
        mesa = create(:workshop_group, workshop: taller)
        WorkshopGroupMember.create!(workshop_group: mesa, user_id: paula.id)
      end
      sign_in(paula, company: company)

      get workshop_path(taller)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(enable_checkin_workshop_path(taller))
    end
  end
end
