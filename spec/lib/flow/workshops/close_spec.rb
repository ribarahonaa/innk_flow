# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flow::Workshops::Close do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  it "cierra el taller y todos sus vínculos abiertos" do
    as_company(company) do
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: create(:challenge), status: "open")

      expect(described_class.new(workshop).call).to be_ok

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

  # `Open` exige `draft?`, así que un taller saltado de borrador a cerrado no
  # se podía reabrir NUNCA. Un estado terminal sin guarda no es una decisión de
  # producto, es un bug de máquina de estados.
  it "no cierra un borrador, y lo dice" do
    as_company(company) do
      workshop = create(:workshop, status: "draft")
      link = create(:workshop_challenge, workshop: workshop, challenge: create(:challenge), status: "open")

      result = described_class.new(workshop).call

      expect(result).not_to be_ok
      expect(result.errors.join).to include("todavía no se abrió")
      expect(workshop.reload).to be_draft
      expect(link.reload).to be_open
    end
  end

  it "no cierra uno ya cerrado" do
    as_company(company) do
      workshop = create(:workshop, status: "closed")

      result = described_class.new(workshop).call

      expect(result).not_to be_ok
      expect(result.errors.join).to include("ya está cerrado")
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
