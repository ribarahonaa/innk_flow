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
  # dato por un cambio de configuración. Corregirlo es del botón de cada
  # integrante (`attendance_workshop_path`), que prueba workshop_attendances_spec.
  it "activar el modo no marca ausente a quien ya estaba presente, ni presente a quien estaba ausente" do
    pedro = member("pedro@test.dev", :participant)
    mesa = as_company(company) { create(:workshop_group, workshop: taller) }
    presente, ausente = as_company(company) do
      [WorkshopGroupMember.create!(workshop_group: mesa, user_id: paula.id, attended: true),
       WorkshopGroupMember.create!(workshop_group: mesa, user_id: pedro.id, attended: false)]
    end
    sign_in(admin, company: company)

    post enable_checkin_workshop_path(taller)

    expect(as_company(company) { [presente.reload.attended, ausente.reload.attended] }).to eq([true, false])
  end

  %i[enable_checkin_workshop_path disable_checkin_workshop_path rotate_checkin_token_workshop_path].each do |ruta|
    it "quien participa no puede usar #{ruta}" do
      as_company(company) do
        taller.update!(attendance_mode: "registered")
        mesa = create(:workshop_group, workshop: taller)
        WorkshopGroupMember.create!(workshop_group: mesa, user_id: paula.id)
      end
      anterior = taller.reload.attributes.slice("attendance_mode", "checkin_token")
      sign_in(paula, company: company)

      post public_send(ruta, taller)

      expect(response).to have_http_status(:forbidden)
      expect(as_company(company) { taller.reload.attributes.slice("attendance_mode", "checkin_token") }).to eq(anterior)
    end
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
      expect(response.body).to include("crispEdges")
    end

    # El helper inlinea el SVG en un documento HTML: un prólogo XML ahí es basura
    # y además una declaración falsa. Este ejemplo es la única cobertura directa
    # del helper, y lo mide por la pantalla servida.
    it "sirve el QR como SVG sin el prólogo XML" do
      as_company(company) { taller.update!(attendance_mode: "registered") }
      sign_in(admin, company: company)

      get workshop_path(taller)

      expect(response.body).to include("crispEdges")
      expect(response.body).not_to include("<?xml")
    end

    it "no se lo ofrece a quien participa, ni le muestra el token, aun con el modo puesto" do
      as_company(company) do
        taller.update!(attendance_mode: "registered")
        mesa = create(:workshop_group, workshop: taller)
        WorkshopGroupMember.create!(workshop_group: mesa, user_id: paula.id)
        # Con una sola sala el taller redirige a ella y la pantalla del taller
        # no se sirve: un segundo desafío la mantiene a la vista.
        otro = create(:challenge)
        paso = create(:challenge_step, challenge: otro, kind: "ideation", status: "active")
        create(:workshop_challenge, workshop: taller, challenge: otro, challenge_step: paso)
      end
      sign_in(paula, company: company)

      get workshop_path(taller)

      expect(response).to have_http_status(:ok)
      [enable_checkin_workshop_path(taller), disable_checkin_workshop_path(taller),
       rotate_checkin_token_workshop_path(taller), taller.checkin_token, "crispEdges"].each do |rastro|
        expect(response.body).not_to include(rastro)
      end
    end

    it "no ofrece activarlo en un taller cerrado, y lo dice" do
      as_company(company) { taller.update!(status: "closed") }
      sign_in(admin, company: company)

      get workshop_path(taller)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(enable_checkin_workshop_path(taller))
      expect(response.body).to include("Este taller ya cerró")
    end
  end
end
