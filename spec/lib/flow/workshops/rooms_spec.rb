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

  it "con una sola sala trabajable la nombra, y el vínculo de otra fase no cuenta" do
    as_company(company) do
      workshop = create(:workshop, status: "open")
      sala = room(workshop, kind: "ideation")
      room(workshop, kind: "evaluation") # no es trabajable: un taller no trabaja ahí

      rooms = described_class.new(workshop)

      expect(rooms.workable.map(&:id)).to eq([ sala.id ])
      expect(rooms.only_room.id).to eq(sala.id)
      # Y aun así NO redirige: queda otro vínculo del que el selector informa.
      expect(rooms.redirects?(can_assemble: false)).to be(false)
    end
  end

  # El redirect pide las DOS cosas: una sola sala trabajable y ningún otro
  # vínculo. Con un solo vínculo el selector no tiene nada que contar.
  it "con un único vínculo, y trabajable, redirige a quien no arma el taller" do
    as_company(company) do
      workshop = create(:workshop, status: "open")
      sala = room(workshop, kind: "ideation")

      rooms = described_class.new(workshop)

      expect(rooms.only_room.id).to eq(sala.id)
      expect(rooms.redirects?(can_assemble: false)).to be(true)
    end
  end

  # La contracara, que es el defecto que el `links.one?` arregla: el breadcrumb
  # de la sala pregunta lo mismo que el redirect y, para no hacer bucle, no
  # ofrece volver al taller. Con el redirect puesto sólo en «una sola sala
  # trabajable», quien no administra no tenía NINGÚN camino al selector, así que
  # nunca se enteraba de que el otro desafío estuvo en el taller ni de por qué
  # su sala cerró.
  it "no redirige si queda un vínculo cerrado del que informar" do
    as_company(company) do
      workshop = create(:workshop, status: "open")
      room(workshop, kind: "ideation")
      room(workshop, kind: "ideation", link_status: "closed")

      rooms = described_class.new(workshop)

      expect(rooms.workable.size).to eq(1)
      expect(rooms.only_room).not_to be_nil
      expect(rooms.redirects?(can_assemble: false)).to be(false)
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
