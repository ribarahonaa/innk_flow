# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flow::Workshops::Close do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  it "cierra el taller y todos sus vínculos abiertos" do
    as_company(company) do
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: create(:challenge), status: "open")

      described_class.new(workshop).call

      expect(workshop.reload).to be_closed
      expect(link.reload).to be_closed
      expect(link.closed_reason).to eq("El taller se cerró.")
      expect(link.closed_at).to be_present
    end
  end

  it "no toca un vínculo que ya estaba cerrado" do
    as_company(company) do
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: create(:challenge),
                                          status: "closed", closed_reason: "El desafío avanzó a otro módulo.")

      described_class.new(workshop).call

      expect(link.reload.closed_reason).to eq("El desafío avanzó a otro módulo.")
    end
  end

  it "acepta un motivo propio" do
    as_company(company) do
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: create(:challenge), status: "open")

      described_class.new(workshop, reason: "Cerrado a mano por quien administra.").call

      expect(link.reload.closed_reason).to eq("Cerrado a mano por quien administra.")
    end
  end
end
