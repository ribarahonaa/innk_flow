# frozen_string_literal: true

require "rails_helper"

# El endpoint que recarga la mesa de llegada. Devuelve el MISMO frame que la
# pantalla completa, con el mismo id: si no coincidieran, Turbo no reemplazaría
# nada y la pantalla se quedaría quieta sin un solo error.
RSpec.describe "la llegada en vivo", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }
  let!(:otra) { without_tenant { create(:company, slug: "otra") } }

  def member(email, role, empresa = company)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, role.to_sym, company: empresa, user: u)
      u
    end
  end

  let!(:admin) { member("admin@test.dev", :admin) }
  let!(:paula) { member("paula@test.dev", :participant) }
  let!(:taller) { as_company(company) { create(:workshop, status: "open") } }

  it "lista a quien está en la mesa de llegada, dentro del frame" do
    as_company(company) do
      llegada = create(:workshop_group, :arrival, workshop: taller)
      WorkshopGroupMember.create!(workshop_group: llegada, user_id: paula.id)
    end
    sign_in(admin, company: company)

    get arrival_workshop_path(taller)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="llegada"')
    expect(response.body).to include(paula.name)
  end

  # Review Focus 3: el reparto puede haber vaciado y barrido la llegada entre dos
  # refrescos. El frame devuelve el vacío; no revienta ni crea una mesa.
  it "sin mesa de llegada devuelve el vacío y no la crea" do
    sign_in(admin, company: company)

    expect do
      get arrival_workshop_path(taller)
    end.not_to change { as_company(company) { WorkshopGroup.count } }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Todavía no llegó nadie")
  end

  it "a quien participa le da 404" do
    sign_in(paula, company: company)

    get arrival_workshop_path(taller)

    expect(response).to have_http_status(:not_found)
  end

  # El 404 de arriba lo da el SCOPE (paula no está convocada y el taller no se
  # le ve), así que no ejercita `authorize`. Acá sí se le ve —está sentada en la
  # llegada— y lo que la frena es `update?`: 403, y sin la lista de los demás.
  it "a quien está sentada en la llegada pero no administra le da 403 y no le muestra la lista" do
    as_company(company) do
      llegada = create(:workshop_group, :arrival, workshop: taller)
      WorkshopGroupMember.create!(workshop_group: llegada, user_id: paula.id)
    end
    sign_in(paula, company: company)

    get arrival_workshop_path(taller)

    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include('id="llegada"')
  end

  # Review Focus 2: la sesión guarda la empresa y no vuelve a pedir la membresía.
  # A quien se la sacaron `TenantResolution` lo manda a elegir empresa (302,
  # ver `spec/tenancy/sin_membresia_spec.rb`): ni 200 con la lista ni un 500.
  it "a quien perdió la membresía lo manda a elegir empresa, sin la lista" do
    as_company(company) do
      llegada = create(:workshop_group, :arrival, workshop: taller)
      WorkshopGroupMember.create!(workshop_group: llegada, user_id: paula.id)
    end
    sign_in(admin, company: company)
    without_tenant { Membership.where(user_id: admin.id, company_id: company.id).destroy_all }

    get arrival_workshop_path(taller)

    expect(response).to redirect_to(select_company_path)
    expect(response.body).not_to include(paula.name)
  end

  it "a un taller de otra empresa le da 404" do
    ajeno = as_company(otra) { create(:workshop, status: "open") }
    sign_in(admin, company: company)

    get arrival_workshop_path(ajeno)

    expect(response).to have_http_status(:not_found)
  end
end
