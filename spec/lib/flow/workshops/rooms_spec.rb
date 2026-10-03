# frozen_string_literal: true

require "rails_helper"

# El redirect del taller y el breadcrumb de la sala preguntan lo MISMO. Si la
# pregunta viviera en dos lugares, el día que uno cambie aparece un bucle:
# el taller manda a la sala y la sala ofrece volver al taller.
RSpec.describe Flow::Workshops::Rooms do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def room(workshop, kind:, step_status: "active", link_status: "open")
    challenge = create(:challenge)
    step = create(:challenge_step, challenge: challenge, kind: kind, status: step_status)
    create(:workshop_challenge, workshop: workshop, challenge: challenge,
                                challenge_step: step, status: link_status)
  end

  it "con una sola sala trabajable la nombra, y redirige a quien no arma el taller" do
    as_company(company) do
      workshop = create(:workshop, status: "open")
      sala = room(workshop, kind: "ideation")
      room(workshop, kind: "evaluation") # no es trabajable: un taller no trabaja ahí

      rooms = described_class.new(workshop)

      expect(rooms.workable.map(&:id)).to eq([ sala.id ])
      expect(rooms.only_room.id).to eq(sala.id)
      expect(rooms.redirects?(can_assemble: false)).to be(true)
    end
  end

  it "a quien arma el taller NO lo redirige: ahí está el bloque de armado" do
    as_company(company) do
      workshop = create(:workshop, status: "open")
      room(workshop, kind: "ideation")

      expect(described_class.new(workshop).redirects?(can_assemble: true)).to be(false)
    end
  end

  it "con dos salas trabajables no hay a dónde redirigir" do
    as_company(company) do
      workshop = create(:workshop, status: "open")
      room(workshop, kind: "ideation")
      room(workshop, kind: "evolution")

      rooms = described_class.new(workshop)

      expect(rooms.workable.size).to eq(2)
      expect(rooms.only_room).to be_nil
      expect(rooms.redirects?(can_assemble: false)).to be(false)
    end
  end

  # Un taller en BORRADOR no tiene salas: `Open` todavía no resolvió el módulo
  # de cada vínculo, así que `room_state` es `:unopened`. Sin esto, un borrador
  # recién armado redirigía a una sala que no existe.
  it "un taller en borrador no tiene ninguna sala trabajable" do
    as_company(company) do
      workshop = create(:workshop, status: "draft")
      challenge = create(:challenge)
      create(:workshop_challenge, workshop: workshop, challenge: challenge, challenge_step: nil)

      rooms = described_class.new(workshop)

      expect(rooms.workable).to be_empty
      expect(rooms.redirects?(can_assemble: false)).to be(false)
    end
  end

  it "el vínculo cerrado y el que venció no cuentan" do
    as_company(company) do
      workshop = create(:workshop, status: "open")
      room(workshop, kind: "ideation", link_status: "closed")
      room(workshop, kind: "ideation", step_status: "completed")

      expect(described_class.new(workshop).workable).to be_empty
    end
  end
end
