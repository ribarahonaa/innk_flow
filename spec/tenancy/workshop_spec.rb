# frozen_string_literal: true

require "rails_helper"

# Las cinco tablas del taller, contra las mismas reglas que el resto del
# dominio: sin tenant la query revienta, y una persona no puede estar en dos
# mesas del mismo taller.
RSpec.describe "tenencia del taller" do
  let!(:acme) { without_tenant { create(:company, slug: "acme") } }
  let!(:otra) { without_tenant { create(:company, slug: "otra") } }

  it "revienta sin tenant en contexto" do
    expect { Workshop.count }.to raise_error(TenantScoped::MissingTenant)
  end

  it "no deja a una persona en dos mesas del mismo taller" do
    as_company(acme) do
      taller = create(:workshop)
      persona = Flow::Tenant.bypass! { create(:user) }
      create(:workshop_group_member, workshop_group: create(:workshop_group, workshop: taller), user: persona)

      segunda = create(:workshop_group, workshop: taller)
      repetida = WorkshopGroupMember.new(workshop_group: segunda, user: persona)

      expect(repetida).not_to be_valid
      expect(repetida.errors[:user_id].join).to include("ya está en otra mesa")
    end
  end

  it "deja a la misma persona en mesas de talleres distintos" do
    as_company(acme) do
      persona = Flow::Tenant.bypass! { create(:user) }
      create(:workshop_group_member, workshop_group: create(:workshop_group), user: persona)
      otra_mesa = create(:workshop_group, workshop: create(:workshop))

      expect(WorkshopGroupMember.new(workshop_group: otra_mesa, user: persona)).to be_valid
    end
  end

  it "rechaza atar una mesa a un taller de otra empresa" do
    ajeno = as_company(otra) { create(:workshop) }

    as_company(acme) do
      mesa = WorkshopGroup.new(workshop_id: ajeno.id, name: "Mesa 1")
      expect(mesa).not_to be_valid
    end
  end
end
