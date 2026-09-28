# frozen_string_literal: true

require "rails_helper"

# Convocar ES sumar a una mesa: no hay lista aparte. En modo individual no hay
# mesa que elegir, así que se crea la de esa persona en el acto — y por eso el
# resto del código nunca tiene dos caminos.
RSpec.describe Flow::Workshops::Convoke do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }
  let(:ana) { without_tenant { create(:user, email: "ana@test.dev") } }

  it "en modo individual crea la mesa de esa persona" do
    as_company(company) do
      workshop = create(:workshop, mode: "individual")

      result = described_class.new(workshop, ana).call

      expect(result.ok).to be(true)
      expect(workshop.workshop_groups.count).to eq(1)
      expect(workshop.workshop_groups.first.members).to eq([ana])
    end
  end

  it "en modo por mesas exige una mesa" do
    as_company(company) do
      workshop = create(:workshop, mode: "group")

      result = described_class.new(workshop, ana).call

      expect(result.ok).to be(false)
      expect(result.errors.join).to include("mesa")
      expect(workshop.workshop_groups.count).to eq(0)
    end
  end

  it "convocar dos veces no crea una mesa huérfana" do
    as_company(company) do
      workshop = create(:workshop, mode: "individual")
      described_class.new(workshop, ana).call

      result = described_class.new(workshop, ana).call

      expect(result.ok).to be(false)
      expect(workshop.workshop_groups.count).to eq(1)
    end
  end
end
