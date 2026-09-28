# frozen_string_literal: true

require "rails_helper"

# Las cinco tablas del taller, contra las mismas reglas que el resto del
# dominio: sin tenant la query revienta, y una persona no puede estar en dos
# mesas del mismo taller.
RSpec.describe "tenencia del taller" do
  let!(:acme) { without_tenant { create(:company, slug: "acme") } }
  let!(:other_company) { without_tenant { create(:company, slug: "otra") } }

  it "revienta sin tenant en contexto" do
    expect { Workshop.count }.to raise_error(TenantScoped::MissingTenant)
  end

  it "no deja a una persona en dos mesas del mismo taller" do
    as_company(acme) do
      workshop = create(:workshop)
      person = Flow::Tenant.bypass! { create(:user) }
      create(:workshop_group_member, workshop_group: create(:workshop_group, workshop: workshop), user: person)

      second_group = create(:workshop_group, workshop: workshop)
      duplicate_member = WorkshopGroupMember.new(workshop_group: second_group, user: person)

      expect(duplicate_member).not_to be_valid
      expect(duplicate_member.errors[:user_id].join).to include("ya está en otra mesa")
    end
  end

  it "deja a la misma persona en mesas de talleres distintos" do
    as_company(acme) do
      person = Flow::Tenant.bypass! { create(:user) }
      create(:workshop_group_member, workshop_group: create(:workshop_group), user: person)
      other_group = create(:workshop_group, workshop: create(:workshop))

      expect(WorkshopGroupMember.new(workshop_group: other_group, user: person)).to be_valid
    end
  end

  it "rechaza atar una mesa a un taller de otra empresa" do
    foreign_workshop = as_company(other_company) { create(:workshop) }

    as_company(acme) do
      cross_tenant_group = WorkshopGroup.new(workshop_id: foreign_workshop.id, name: "Mesa 1")
      expect(cross_tenant_group).not_to be_valid
    end
  end
end
