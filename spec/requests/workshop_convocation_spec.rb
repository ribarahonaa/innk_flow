# frozen_string_literal: true

require "rails_helper"

# Las mesas y la convocatoria por HTTP: mismo 404-no-403 que el resto del
# taller (`policy_scope(Workshop).find_by!`, nunca `Workshop.find_by!`), y que
# convocar de verdad suma a la mesa —y desconvocar, la saca— y no sólo que el
# servicio lo haga en aislamiento.
RSpec.describe "mesas y convocatoria", type: :request do
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
  let!(:workshop) { as_company(company) { create(:workshop, mode: "group") } }

  describe "mesas" do
    it "quien administra crea una mesa" do
      sign_in(admin, company: company)

      expect do
        post workshop_workshop_groups_path(workshop), params: { name: "Mesa A" }
      end.to change { as_company(company) { workshop.workshop_groups.count } }.by(1)

      expect(response).to redirect_to(workshop_path(workshop))
      expect(as_company(company) { workshop.workshop_groups.last.name }).to eq("Mesa A")
    end

    it "sin nombre, la nombra sola" do
      sign_in(admin, company: company)
      post workshop_workshop_groups_path(workshop)

      expect(as_company(company) { workshop.workshop_groups.last.name }).to eq("Mesa 1")
    end

    it "a quien no está convocado le da 404, no 403, al intentar crear una mesa" do
      sign_in(paula, company: company)
      post workshop_workshop_groups_path(workshop), params: { name: "Mesa A" }

      expect(response).to have_http_status(:not_found)
    end

    it "quien administra elimina una mesa" do
      group = as_company(company) { create(:workshop_group, workshop: workshop) }
      sign_in(admin, company: company)

      expect do
        delete workshop_workshop_group_path(workshop, group)
      end.to change { as_company(company) { WorkshopGroup.count } }.by(-1)
    end
  end

  describe "convocatoria" do
    it "convoca a alguien a una mesa existente" do
      group = as_company(company) { create(:workshop_group, workshop: workshop) }
      sign_in(admin, company: company)

      expect do
        post convoke_workshop_path(workshop), params: { user_id: paula.id, workshop_group_id: group.id }
      end.to change { as_company(company) { group.reload.members.count } }.by(1)

      expect(response).to redirect_to(workshop_path(workshop))
    end

    it "sin mesa en modo por mesas, no convoca" do
      sign_in(admin, company: company)

      expect do
        post convoke_workshop_path(workshop), params: { user_id: paula.id }
      end.not_to(change { as_company(company) { WorkshopGroupMember.count } })

      follow_redirect!
      expect(response.body).to include("mesa")
    end

    it "desconvoca a alguien de su mesa" do
      group = as_company(company) { create(:workshop_group, workshop: workshop) }
      as_company(company) { create(:workshop_group_member, workshop_group: group, user: paula) }
      sign_in(admin, company: company)

      expect do
        delete dismiss_workshop_path(workshop), params: { user_id: paula.id }
      end.to change { as_company(company) { WorkshopGroupMember.count } }.by(-1)
    end

    it "a quien no está convocado le da 404, no 403, al intentar convocar" do
      sign_in(paula, company: company)
      post convoke_workshop_path(workshop), params: { user_id: paula.id }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "en modo individual" do
    let!(:individual_workshop) { as_company(company) { create(:workshop, mode: "individual") } }

    it "convocar arma la mesa de esa persona, sin elegir ninguna" do
      sign_in(admin, company: company)

      expect do
        post convoke_workshop_path(individual_workshop), params: { user_id: paula.id }
      end.to change { as_company(company) { individual_workshop.workshop_groups.count } }.by(1)

      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(as_company(company) { individual_workshop.workshop_groups.last.members.to_a }).to eq([paula])
    end
  end
end
