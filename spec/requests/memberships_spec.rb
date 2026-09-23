# frozen_string_literal: true

require "rails_helper"

# Quiénes están en la empresa y con qué rol.
#
# Hasta acá los roles solo se sembraban: convertir a alguien en gestor exigía
# entrar por consola, que es imposible para un rol que se contrata por desafío.
RSpec.describe "miembros de la empresa", type: :request do
  let!(:demo) { without_tenant { create(:company, slug: "demo") } }
  let!(:otra) { without_tenant { create(:company, slug: "otra") } }

  def member(company, email, role)
    without_tenant do
      u = User.find_by(email: email) || create(:user, email: email)
      create(:membership, role.to_sym, company: company, user: u)
      u
    end
  end

  let!(:ana) { member(demo, "ana@test.dev", :admin) }
  let!(:paula) { member(demo, "paula@test.dev", :participant) }

  before { sign_in(ana, company: demo) }

  def memberships = as_company(demo) { Membership.includes(:user).to_a }

  it "lista quién está y con qué rol, y explica qué hace cada rol" do
    get members_path

    expect(response.body).to include(ana.name, paula.name)
    expect(response.body).to include("Administra los desafíos que se le asignan")
  end

  describe "sumar gente" do
    it "crea a la persona si no existía" do
      expect do
        post members_path, params: { email: "gina@test.dev", name: "Gina Guía", role: "gestor" }
      end.to change { without_tenant { User.count } }.by(1)

      gina = without_tenant { User.find_by(email: "gina@test.dev") }
      expect(memberships.find { |m| m.user_id == gina.id }.role).to eq("gestor")
    end

    # Es el punto del rol gestor: la misma persona en varias empresas.
    it "y si ya existe en otra empresa, solo le suma esta" do
      gina = member(otra, "gina@test.dev", :gestor)

      expect do
        post members_path, params: { email: "gina@test.dev", role: "gestor" }
      end.not_to change { without_tenant { User.count } }

      expect(memberships.map(&:user_id)).to include(gina.id)
      # Su rol en la otra empresa no se toca.
      expect(as_company(otra) { Membership.find_by(user_id: gina.id).role }).to eq("gestor")
    end

    it "no la suma dos veces a la misma empresa" do
      post members_path, params: { email: paula.email, role: "evaluator" }

      expect(memberships.count { |m| m.user_id == paula.id }).to eq(1)
      expect(flash[:alert]).to be_present
    end
  end

  describe "cambiar el rol" do
    it "cambia el de otra persona" do
      membership = memberships.find { |m| m.user_id == paula.id }

      patch member_path(membership), params: { role: "gestor" }

      expect(as_company(demo) { Membership.find(membership.id).role }).to eq("gestor")
    end

    # Una empresa sin nadie que la administre no se puede volver a administrar:
    # no queda quién invite ni quién cambie roles.
    it "pero no deja a la empresa sin nadie que la administre" do
      mia = memberships.find { |m| m.user_id == ana.id }

      patch member_path(mia), params: { role: "participant" }

      expect(as_company(demo) { Membership.find(mia.id).role }).to eq("admin")
      expect(flash[:alert]).to include("única persona que administra")
    end

    it "y sí lo deja si hay otro admin" do
      member(demo, "otro@test.dev", :admin)
      mia = memberships.find { |m| m.user_id == ana.id }

      patch member_path(mia), params: { role: "participant" }

      expect(as_company(demo) { Membership.find(mia.id).role }).to eq("participant")
    end
  end

  describe "sacar gente" do
    it "la saca de esta empresa" do
      membership = memberships.find { |m| m.user_id == paula.id }

      delete member_path(membership)

      expect(memberships.map(&:user_id)).not_to include(paula.id)
    end

    it "pero no al último que administra" do
      mia = memberships.find { |m| m.user_id == ana.id }

      delete member_path(mia)

      expect(memberships.map(&:user_id)).to include(ana.id)
    end
  end

  describe "quién puede" do
    it "quien participa, no" do
      sign_in(paula, company: demo)

      get members_path
      expect(response).to have_http_status(:forbidden).or have_http_status(:found)
    end

    # El scope de tenancy hace el trabajo: nunca ve la membresía de la otra.
    it "y no se ven los miembros de otra empresa" do
      member(otra, "ajeno@test.dev", :admin)

      get members_path
      expect(response.body).not_to include("ajeno@test.dev")
    end

    # La pantalla de miembros existe y no puede entrar: ese 403 está bien. Pero
    # una membresía por id no la ve, y se buscaba antes de autorizar: 403 por
    # una que existe y 404 por una que no, que le confirma que existe.
    it "ni le confirma que existe una membresía" do
      de_ana = as_company(demo) { Membership.find_by!(user_id: ana.id) }
      sign_in(paula, company: demo)

      estados = [de_ana.id, SecureRandom.uuid].map do |id|
        patch member_path(id), params: { role: "admin" }
        response.status
      end

      expect(estados).to eq([404, 404])
    end
  end
end
