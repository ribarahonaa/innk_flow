# frozen_string_literal: true

require "rails_helper"

# «Una persona, una mesa por taller» es la invariante de la que cuelga TODA la
# visibilidad del taller: la mesa es la unidad, y alguien en dos mesas la parte
# en dos.
RSpec.describe WorkshopGroupMember do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  it "deriva el taller de la mesa, sin que nadie se lo mande" do
    as_company(company) do
      workshop = create(:workshop)
      group = create(:workshop_group, workshop: workshop)

      member = create(:workshop_group_member, workshop_group: group)

      expect(member.workshop_id).to eq(workshop.id)
    end
  end

  it "no deja a la misma persona en dos mesas del mismo taller" do
    as_company(company) do
      workshop = create(:workshop)
      user = without_tenant { create(:user) }
      create(:workshop_group_member, workshop_group: create(:workshop_group, workshop: workshop), user: user)

      second = WorkshopGroupMember.new(workshop_group: create(:workshop_group, workshop: workshop), user: user)

      expect(second.save).to be(false)
      expect(second.errors.full_messages.join).to include("otra mesa")
    end
  end

  # La validación es un `exists?` seguido de un `save`: dos convocatorias
  # concurrentes la atraviesan. El índice único es lo que no se puede
  # atravesar, y sólo se puede escribir porque `workshop_id` está
  # desnormalizado en la tabla.
  it "la base lo rechaza aunque alguien saltee la validación" do
    as_company(company) do
      workshop = create(:workshop)
      user = without_tenant { create(:user) }
      create(:workshop_group_member, workshop_group: create(:workshop_group, workshop: workshop), user: user)

      colada = WorkshopGroupMember.new(workshop_group: create(:workshop_group, workshop: workshop),
                                       workshop: workshop, user: user, company: company)

      expect { colada.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  it "la misma persona sí puede estar en mesas de talleres distintos" do
    as_company(company) do
      user = without_tenant { create(:user) }
      dos = [create(:workshop), create(:workshop)].map do |workshop|
        create(:workshop_group_member, workshop_group: create(:workshop_group, workshop: workshop), user: user)
      end

      expect(dos.map(&:workshop_id).uniq.size).to eq(2)
    end
  end
end
