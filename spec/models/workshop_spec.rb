# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workshop do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def link(workshop, kind:, status: "open")
    challenge = create(:challenge)
    step = create(:challenge_step, challenge: challenge, kind: kind, status: "active")
    create(:workshop_challenge, workshop: workshop, challenge: challenge, challenge_step: step, status: status)
  end

  describe "#phase" do
    it "en borrador es nil: sus vínculos todavía no tienen módulo" do
      as_company(company) do
        workshop = create(:workshop, status: "draft")
        create(:workshop_challenge, workshop: workshop)

        expect(workshop.phase).to be_nil
      end
    end

    it "abierto es el kind de sus vínculos abiertos, y los cerrados no cuentan" do
      as_company(company) do
        workshop = create(:workshop, status: "open")
        link(workshop, kind: "evolution")
        link(workshop, kind: "evolution")
        link(workshop, kind: "ideation", status: "closed")

        expect(workshop.phase).to eq("evolution")
      end
    end

    it "un vínculo `open` cuyo módulo ya se completó no cuenta" do
      as_company(company) do
        workshop = create(:workshop, status: "open")
        link(workshop, kind: "ideation").challenge_step.update_columns(status: "completed")

        expect(workshop.reload.phase).to be_nil
      end
    end

    it "con vínculos vivos de fases distintas es nil: no adivina" do
      as_company(company) do
        workshop = create(:workshop, status: "open")
        link(workshop, kind: "ideation")
        link(workshop, kind: "evolution")

        expect(workshop.phase).to be_nil
      end
    end

    # Con un solo vínculo no hay orden de filas que valga: fija `select(&:open?)`.
    it "con todos los vínculos cerrados es nil" do
      as_company(company) do
        workshop = create(:workshop, status: "open")
        link(workshop, kind: "ideation", status: "closed")

        expect(workshop.phase).to be_nil
      end
    end
  end
end
