# frozen_string_literal: true

require "rails_helper"

RSpec.describe TenantScoped do
  let(:company_a) { without_tenant { create(:company) } }
  let(:company_b) { without_tenant { create(:company) } }
  let(:user_a)    { without_tenant { create(:user) } }
  let(:user_b)    { without_tenant { create(:user) } }

  describe "sin tenant en contexto" do
    it "REVIENTA en vez de devolver todo" do
      # Esta es la inversión respecto de innk_r5: allá olvidarse de scopear
      # devolvía silenciosamente los datos de todas las empresas.
      expect { Membership.first }.to raise_error(TenantScoped::MissingTenant, /sin Current.company/)
      expect { Membership.count }.to raise_error(TenantScoped::MissingTenant)
      expect { Membership.where(role: "owner").to_a }.to raise_error(TenantScoped::MissingTenant)
    end

    it "el mensaje dice cómo arreglarlo" do
      expect { Membership.first }.to raise_error(/Flow::Tenant.with|Flow::Tenant.bypass!/)
    end
  end

  describe "con tenant en contexto" do
    before do
      without_tenant do
        create(:membership, company: company_a, user: user_a)
        create(:membership, company: company_b, user: user_b)
      end
    end

    it "solo ve las filas de su empresa" do
      as_company(company_a) do
        expect(Membership.count).to eq(1)
        expect(Membership.first.user_id).to eq(user_a.id)
      end

      as_company(company_b) do
        expect(Membership.count).to eq(1)
        expect(Membership.first.user_id).to eq(user_b.id)
      end
    end

    it "no encuentra por id una fila de otra empresa" do
      other = without_tenant { Membership.find_by(company_id: company_b.id) }

      as_company(company_a) do
        expect { Membership.find(other.id) }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    it "asigna company_id solo desde el contexto" do
      as_company(company_a) do
        membership = Membership.create!(user: without_tenant { create(:user) }, role: "participant")
        expect(membership.company_id).to eq(company_a.id)
      end
    end

    it "rechaza escribir en otra empresa aun teniendo el objeto en memoria" do
      as_company(company_a) do
        membership = Membership.new(company: company_b, user: user_b, role: "participant")
        expect(membership).not_to be_valid
        expect(membership.errors[:company_id]).to include("pertenece a otra empresa")
      end
    end
  end

  describe "bypass!" do
    it "levanta el scoping dentro del bloque y lo repone al salir" do
      without_tenant do
        create(:membership, company: company_a, user: user_a)
        create(:membership, company: company_b, user: user_b)
        expect(Membership.count).to eq(2)
      end

      expect { Membership.count }.to raise_error(TenantScoped::MissingTenant)
    end

    it "se repone incluso si el bloque explota" do
      expect { without_tenant { raise "boom" } }.to raise_error("boom")
      expect(Flow::Tenant).not_to be_bypassed
    end
  end

  describe "validación de asociaciones cruzadas" do
    it "corre INCLUSO bajo bypass — es la red de jobs y seeds" do
      without_tenant do
        membership = Membership.new(company: company_a, user: user_a, role: "participant")
        expect(membership).to be_valid
      end
    end
  end
end
