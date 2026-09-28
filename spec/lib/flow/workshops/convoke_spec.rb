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
      # Mensaje exacto y no `include("mesa")`: ese fragmento también aparece
      # en "Ya está en una mesa de este taller.", así que una aserción laxa
      # pasaría igual si el servicio devolviera el otro camino.
      expect(result.errors).to eq(["Hay que elegir una mesa."])
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

  # Un POST fabricado sin `user_id` llega con `user: nil` (el controller hace
  # `User.find_by(id: params[:user_id])`, que devuelve `nil` si falta). Sin
  # esta guarda, en modo individual el servicio intenta nombrar la mesa con
  # `nil.name` y revienta — después de haber creado ya la mesa.
  it "sin persona no convoca, no revienta, y no crea ninguna mesa" do
    as_company(company) do
      workshop = create(:workshop, mode: "individual")

      result = described_class.new(workshop, nil).call

      expect(result.ok).to be(false)
      expect(result.errors).to eq(["Hay que elegir una persona."])
      expect(workshop.workshop_groups.count).to eq(0)
    end
  end
end
