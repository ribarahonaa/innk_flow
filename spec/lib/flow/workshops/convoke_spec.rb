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

  # El UNIQUE (workshop_id, user_id) es lo que la validación no puede
  # garantizar: `convoked?` y `one_group_per_workshop` son los dos un `exists?`
  # seguido de un `save`, y dos convocatorias concurrentes los atraviesan. Los
  # dos stubs son exactamente eso: al mirar, la otra fila todavía no estaba.
  # Que la base frene a la segunda es correcto; el 500 no.
  it "la convocatoria que pierde la carrera contra el índice avisa, no revienta" do
    as_company(company) do
      workshop = create(:workshop)
      persona = without_tenant { create(:user) }
      create(:workshop_group_member, workshop_group: create(:workshop_group, workshop: workshop), user: persona)
      otra_mesa = create(:workshop_group, workshop: workshop)

      service = described_class.new(workshop, persona, group: otra_mesa)
      allow(service).to receive(:convoked?).and_return(false)
      allow_any_instance_of(WorkshopGroupMember).to receive(:one_group_per_workshop)

      result = service.call

      expect(result.ok).to be(false)
      # El mensaje del rescate, no el de la validación («ya está en otra
      # mesa…»): si el rescate no estuviera, esto sería un RecordNotUnique.
      expect(result.errors).to eq(["Ya está en una mesa de este taller."])
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

  describe "la asistencia con la que nace el asiento" do
    it "nace presente en un taller con la presencia presumida" do
      taller = as_company(company) { create(:workshop, status: "open") }
      mesa = as_company(company) { create(:workshop_group, workshop: taller) }

      result = as_company(company) { described_class.new(taller, User.find(ana.id), group: mesa).call }

      expect(result).to be_ok
      expect(result.member.attended).to be(true)
    end

    # Convocar a mano en un taller con la presencia registrada deja el asiento
    # AUSENTE: está invitado, no llegó.
    it "nace ausente en un taller con la presencia registrada" do
      taller = as_company(company) { create(:workshop, :registered, status: "open") }
      mesa = as_company(company) { create(:workshop_group, workshop: taller) }

      result = as_company(company) { described_class.new(taller, User.find(ana.id), group: mesa).call }

      expect(result).to be_ok
      expect(result.member.attended).to be(false)
    end

    it "un valor explícito le gana al default del modo" do
      taller = as_company(company) { create(:workshop, :registered, status: "open") }
      mesa = as_company(company) { create(:workshop_group, workshop: taller) }

      result = as_company(company) do
        described_class.new(taller, User.find(ana.id), group: mesa, attended: true).call
      end

      expect(result.member.attended).to be(true)
    end
  end
end
