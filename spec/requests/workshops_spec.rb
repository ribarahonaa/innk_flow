# frozen_string_literal: true

require "rails_helper"

# Lo que no se ve da 404, NUNCA 403: un 403 confirma que existe.
RSpec.describe "talleres", type: :request do
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
  let!(:workshop) { as_company(company) { create(:workshop) } }

  it "a quien no está convocado le da 404, no 403" do
    sign_in(paula, company: company)
    get workshop_path(workshop)
    expect(response).to have_http_status(:not_found)
  end

  it "quien administra lo abre" do
    sign_in(admin, company: company)
    get workshop_path(workshop)
    expect(response).to have_http_status(:ok)
  end
end
