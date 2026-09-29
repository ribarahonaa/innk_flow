# frozen_string_literal: true

require "rails_helper"

# El cierre perezoso no lo escribe nadie más: `Open` y `Close` son los otros
# dos escritores de `status`/`closed_reason`, y ninguno corre cuando el desafío
# avanza DESPUÉS de que el taller abrió —que es el caso normal—.
RSpec.describe Flow::Workshops::MaterializeClosures do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def scene(kind:, status:)
    challenge = create(:challenge)
    ideation = create(:challenge_step, challenge: challenge, kind: "ideation", status: "completed")
    workshop = create(:workshop, status: "open")
    link = create(:workshop_challenge, workshop: workshop, challenge: challenge,
                                       challenge_step: ideation, status: "open")
    create(:challenge_step, challenge: challenge, kind: kind, status: status) if kind
    [workshop, link]
  end

  it "cierra el vínculo cuyo módulo dejó de estar activo, diciendo a qué avanzó" do
    as_company(company) do
      workshop, link = scene(kind: "evolution", status: "active")

      expect(described_class.new(workshop).call.map(&:id)).to eq([link.id])

      link.reload
      expect(link).to be_closed
      expect(link.closed_at).to be_present
      expect(link.closed_reason).to include("Evolución")
    end
  end

  # El texto de una fase que el taller no trabaja es el MISMO que usa `Open`
  # al rechazar: si alguien lo duplica y los dos divergen, esto falla.
  it "para una fase que el taller no trabaja reusa el motivo de Open" do
    as_company(company) do
      workshop, link = scene(kind: "evaluation", status: "active")
      step = as_company(company) { link.challenge.pipeline.active_step }

      described_class.new(workshop).call

      expect(link.reload.closed_reason).to eq(Flow::Workshops::Open.reason_for(step))
    end
  end

  it "sin ningún módulo en curso lo dice, en vez de dejar el motivo vacío" do
    as_company(company) do
      workshop, link = scene(kind: nil, status: nil)

      described_class.new(workshop).call

      expect(link.reload.closed_reason).to eq("El desafío no tiene ningún módulo en curso.")
    end
  end

  # En borrador el `challenge_step_id` es nulo A PROPÓSITO: lo resuelve `Open`.
  # Sin esta guarda, entrar al armado de un taller recién creado cerraba todos
  # sus vínculos con «El desafío no tiene ningún módulo en curso».
  it "no toca los vínculos de un taller en borrador" do
    as_company(company) do
      workshop = create(:workshop, status: "draft")
      link = create(:workshop_challenge, workshop: workshop, challenge: create(:challenge))

      expect(described_class.new(workshop).call).to be_empty
      expect(link.reload).to be_open
      expect(link.closed_reason).to be_nil
    end
  end

  it "no toca los vínculos de un taller cerrado: de eso ya se encargó Close" do
    as_company(company) do
      workshop = create(:workshop, status: "closed")
      link = create(:workshop_challenge, workshop: workshop, challenge: create(:challenge),
                                         status: "closed", closed_reason: "El taller se cerró.")

      expect(described_class.new(workshop).call).to be_empty
      expect(link.reload.closed_reason).to eq("El taller se cerró.")
    end
  end

  it "no toca el vínculo que sigue trabajable ni el que ya estaba cerrado" do
    as_company(company) do
      challenge = create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: "ideation", status: "active")
      workshop = create(:workshop, status: "open")
      vivo = create(:workshop_challenge, workshop: workshop, challenge: challenge,
                                         challenge_step: step, status: "open")
      ya_cerrado = create(:workshop_challenge, workshop: workshop, challenge: create(:challenge),
                                               status: "closed", closed_reason: "El taller se cerró.")

      expect(described_class.new(workshop).call).to be_empty
      expect(vivo.reload).to be_open
      expect(ya_cerrado.reload.closed_reason).to eq("El taller se cerró.")
    end
  end
end
