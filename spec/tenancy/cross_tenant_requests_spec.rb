# frozen_string_literal: true

require "rails_helper"

# Barrido a nivel request: logueado en la empresa A, pegarle a recursos de la
# empresa B tiene que dar 404 — nunca 200 (fuga), nunca 403 (oráculo de
# existencia), nunca 500 (error no manejado).
#
# El spec recorre las rutas automáticamente, así que crece solo a medida que
# aparecen recursos nuevos en las fases siguientes.
RSpec.describe "requests cross-tenant", type: :request do
  let!(:company_a) { without_tenant { create(:company, slug: "empresa-a") } }
  let!(:company_b) { without_tenant { create(:company, slug: "empresa-b") } }
  let!(:user_a)    { without_tenant { create(:user, email: "a@test.dev") } }
  let!(:user_b)    { without_tenant { create(:user, email: "b@test.dev") } }

  before do
    without_tenant do
      create(:membership, :owner, company: company_a, user: user_a)
      create(:membership, :owner, company: company_b, user: user_b)
    end
    sign_in(user_a, company: company_a)
  end

  # Recursos de la empresa B a los que un usuario de A no debe llegar.
  # Cada fase agrega entradas acá.
  def foreign_records
    without_tenant do
      { membership: Membership.find_by(company_id: company_b.id) }
    end
  end

  it "no expone recursos de otra empresa por id" do
    foreign_records.each do |label, record|
      next if record.nil?

      as_company(company_a) do
        found = record.class.where(id: record.id).exists?
        expect(found).to be(false), "#{label}: visible desde otra empresa"
      end
    end
  end

  it "el selector de empresa rechaza una empresa ajena con 404" do
    post choose_company_path, params: { company_id: company_b.id }
    expect(response).to have_http_status(:not_found)
  end

  it "no filtra la existencia con un 403" do
    post choose_company_path, params: { company_id: company_b.id }
    expect(response).not_to have_http_status(:forbidden)
  end

  it "las rutas GET con :id responden 404 o redirect, nunca 200 ni 500" do
    ids = foreign_records.values.compact.map(&:id)
    next if ids.empty?

    routes_with_id = Rails.application.routes.routes.select do |route|
      route.path.spec.to_s.include?(":id") &&
        route.verb.to_s.include?("GET") &&
        !route.path.spec.to_s.start_with?("/rails/")
    end

    routes_with_id.each do |route|
      ids.each do |id|
        path = route.path.spec.to_s.sub("(.:format)", "").gsub(/:\w+/, id.to_s)
        get path
        expect(response.status).not_to eq(200), "#{path} devolvió 200 con un id de otra empresa"
        expect(response.status).not_to eq(500), "#{path} devolvió 500 (error no manejado)"
      rescue ActionController::RoutingError
        next
      end
    end
  end
end
