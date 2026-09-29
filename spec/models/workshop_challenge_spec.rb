# frozen_string_literal: true

require "rails_helper"

# `room_state` es el despacho de la sala en UN valor. Lo que se le pide no es
# sólo acertar los dos casos vivos: es que ningún estado quede sin nombre y
# caiga en la rama por defecto diciendo algo falso.
RSpec.describe WorkshopChallenge do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def link_for(workshop_status:, kind: nil, step_status: nil, link_status: "open")
    workshop = create(:workshop, status: workshop_status)
    challenge = create(:challenge)
    step = kind ? create(:challenge_step, challenge: challenge, kind: kind, status: step_status) : nil
    create(:workshop_challenge, workshop: workshop, challenge: challenge,
                                challenge_step: step, status: link_status)
  end

  # Se alinea con `Flow::Pipeline#active_step`: activo es `active` o `activating`.
  describe "#workable?" do
    { "active" => true, "activating" => true, "pending" => false, "completed" => false }.each do |status, expected|
      it "con el módulo #{status} es #{expected}" do
        as_company(company) do
          link = link_for(workshop_status: "open", kind: "ideation", step_status: status)
          expect(link.workable?).to be(expected)
        end
      end
    end
  end

  describe "#room_state" do
    # El vínculo de un taller en BORRADOR nace `open` con `challenge_step_id`
    # nulo A PROPÓSITO —lo resuelve `Open`—, así que `workable?` es false igual
    # que en el que venció. Sin un valor propio, la pantalla le decía a un
    # borrador recién armado «el desafío avanzó de fase», que es falso.
    it "un taller en borrador no tiene sala: :unopened, no :stale" do
      as_company(company) do
        expect(link_for(workshop_status: "draft").room_state).to eq(:unopened)
      end
    end

    it "en borrador da :unopened aunque el desafío tenga un módulo activo" do
      as_company(company) do
        link = link_for(workshop_status: "draft", kind: "ideation", step_status: "active")
        expect(link.room_state).to eq(:unopened)
      end
    end

    it "con el taller abierto, el kind del módulo manda" do
      as_company(company) do
        expect(link_for(workshop_status: "open", kind: "ideation", step_status: "active").room_state)
          .to eq(:ideation)
        expect(link_for(workshop_status: "open", kind: "evolution", step_status: "active").room_state)
          .to eq(:evolution)
      end
    end

    it "el vínculo cuyo módulo dejó de estar activo es :stale" do
      as_company(company) do
        expect(link_for(workshop_status: "open", kind: "ideation", step_status: "completed").room_state)
          .to eq(:stale)
      end
    end

    it "el vínculo cerrado es :closed, esté el taller como esté" do
      as_company(company) do
        expect(link_for(workshop_status: "draft", link_status: "closed").room_state).to eq(:closed)
        expect(link_for(workshop_status: "open", link_status: "closed").room_state).to eq(:closed)
      end
    end
  end
end
