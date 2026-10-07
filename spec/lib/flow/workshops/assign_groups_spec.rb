# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flow::Workshops::AssignGroups do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  let(:paula) { as_company(company) { create(:user, name: "Paula") } }
  let(:pedro) { as_company(company) { create(:user, name: "Pedro") } }
  let(:ana)   { as_company(company) { create(:user, name: "Ana") } }

  def open_workshop(*kinds_and_challenges, registered: false)
    workshop = create(:workshop, status: "open", attendance_mode: registered ? "registered" : "presumed")
    kinds_and_challenges.each do |kind, challenge|
      challenge ||= create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: kind, status: "active")
      create(:workshop_challenge, workshop: workshop, challenge: challenge, challenge_step: step)
    end
    workshop
  end

  def step_of(workshop) = workshop.workshop_challenges.first.challenge_step

  # Una idea del módulo, con su autor y sus colaboradores.
  def idea_in(step, author, *contributors)
    idea = create(:idea, challenge: step.challenge, author: author, status: "active")
    StepEntry.create!(challenge_step: step, idea: idea)
    contributors.each { |u| IdeaContributor.create!(idea: idea, user: u) }
    idea
  end

  def seat(workshop, user, group)
    Flow::Workshops::Convoke.new(workshop, user, group: group).call
  end

  let(:mesa) { as_company(company) { create(:workshop_group, workshop: taller) } }

  describe "los guardas" do
    let(:borrador) { as_company(company) { create(:workshop, status: "draft") } }
    let(:taller) { as_company(company) { open_workshop(["evolution"]) } }

    it "no reparte un taller en borrador: sin fase no hay criterio" do
      result = as_company(company) { described_class.new(borrador, size: 3).call }

      expect(result).not_to be_ok
      expect(result.errors.join).to include("abierto")
    end

    it "no reparte si alguna mesa ya propuso algo" do
      as_company(company) do
        step = step_of(taller)
        idea = idea_in(step, paula)
        WorkshopProposal.create!(workshop_group: mesa, idea: idea, challenge_step: step,
                                 status: "pending", payload: { "titulo" => "x" })
      end

      result = as_company(company) { described_class.new(taller, size: 3).call }

      expect(result).not_to be_ok
      expect(result.errors.join).to include("propuesta")
    end

    it "avisa cuando no hay a quién sentar" do
      result = as_company(company) { described_class.new(taller, size: 3).call }

      expect(result).not_to be_ok
      expect(result.errors.join).to include("a quién sentar")
    end

    # El estado lo produce la app sola: `MaterializeClosures` no cierra el taller.
    it "no reparte un taller abierto con todos los vínculos cerrados, ni convoca a la empresa" do
      cerrado = as_company(company) do
        create(:workshop, status: "open").tap do |w|
          create(:workshop_challenge, workshop: w, status: "closed")
        end
      end
      as_company(company) { create(:membership, company: company, user: paula, role: "participant") }

      result = as_company(company) { described_class.new(cerrado, size: 3).call }

      expect(result).not_to be_ok
      expect(result.errors.join).to include("vínculos")
      expect(as_company(company) { WorkshopGroupMember.count }).to eq(0)
    end

    it "no reparte un taller individual" do
      individual = as_company(company) { create(:workshop, status: "open", mode: "individual") }

      result = as_company(company) { described_class.new(individual, size: 3).call }

      expect(result).not_to be_ok
      expect(result.errors.join).to include("individual")
    end
  end

  describe "en evolución" do
    let(:taller) { as_company(company) { open_workshop(["evolution"]) } }

    it "el pool sale de quien trabaja en las ideas del módulo" do
      as_company(company) { idea_in(step_of(taller), paula, pedro) }

      result = as_company(company) { described_class.new(taller, size: 4).call }

      expect(result).to be_ok
      expect(result.tables.flatten).to contain_exactly(paula.id, pedro.id)
      expect(as_company(company) { WorkshopGroupMember.count }).to eq(2)
    end

    it "no cuenta las ideas que no están vivas" do
      as_company(company) do
        idea = idea_in(step_of(taller), paula)
        idea.update!(status: "draft")
      end

      result = as_company(company) { described_class.new(taller, size: 4).call }

      expect(result).not_to be_ok
      expect(result.errors.join).to include("a quién sentar")
    end

    it "con toda la gente de las ideas ausente no devuelve ok con cero mesas" do
      as_company(company) do
        idea_in(step_of(taller), paula)
        idea_in(step_of(taller), pedro)
        seat(taller, paula, mesa)
        seat(taller, pedro, mesa)
        WorkshopGroupMember.update_all(attended: false)
      end

      result = as_company(company) { described_class.new(taller, size: 4).call }

      expect(result).not_to be_ok
      expect(result.errors.join).to include("a quién sentar")
    end

    # Review Focus 1.
    it "encadena dos ideas de desafíos DISTINTOS cuando comparten gente" do
      taller_dos = as_company(company) { open_workshop(["evolution"], ["evolution"]) }

      as_company(company) do
        pasos = taller_dos.workshop_challenges.map(&:challenge_step)
        idea_in(pasos[0], paula, pedro)
        idea_in(pasos[1], pedro, ana)
      end

      result = as_company(company) { described_class.new(taller_dos, size: 9).call }

      expect(result.tables.size).to eq(1)
      expect(result.tables.first).to contain_exactly(paula.id, pedro.id, ana.id)
    end

    # Review Focus 2: por la regla de no evictar.
    it "no saca a quien ya está sentado y no trabaja en ninguna idea" do
      as_company(company) { idea_in(step_of(taller), paula, pedro) }
      as_company(company) { seat(taller, ana, mesa) }

      result = as_company(company) { described_class.new(taller, size: 4).call }

      expect(result.tables.flatten).to include(ana.id)
      expect(as_company(company) { WorkshopGroupMember.find_by(user_id: ana.id) }).to be_present
    end

    # Sin esto, cada persona de una idea sumaba además su propio grupo de una
    # persona: el reparto podía elegir ESE grupo para desprender y el aviso
    # contaba un corte que no movió a nadie.
    it "una idea con su gente sentada y presente es UN solo grupo: un corte, un aviso" do
      p1, p2, p3 = as_company(company) { [create(:user), create(:user), create(:user)] }
      ideas = as_company(company) do
        step = step_of(taller)
        [idea_in(step, p1, p2), idea_in(step, p2, p3)].tap do
          [p1, p2, p3].each { |u| seat(taller, u, mesa) }
        end
      end

      result = as_company(company) { described_class.new(taller, size: 2).call }

      expect(result.splits.size).to eq(1)
      expect(ideas.map(&:id)).to include(result.splits.first.group_key)
      expect(result.tables.map(&:size).sort).to eq([1, 2])
      expect(result.tables.flatten).to contain_exactly(p1.id, p2.id, p3.id)
    end

    it "una idea cuya única persona está ausente no arma mesa" do
      as_company(company) do
        idea_in(step_of(taller), paula)
        idea_in(step_of(taller), pedro)
        seat(taller, paula, mesa)
        WorkshopGroupMember.find_by!(user_id: paula.id).update!(attended: false)
      end

      result = as_company(company) { described_class.new(taller, size: 4).call }

      expect(result.tables.flatten).to contain_exactly(pedro.id)
    end
  end

  describe "en idear" do
    let(:taller) { as_company(company) { open_workshop(["ideation"]) } }

    before do
      as_company(company) do
        [paula, pedro].each { |u| create(:membership, company: company, user: u, role: "participant") }
        seat(taller, pedro, mesa)
      end
    end

    it "reparte a los participantes presentes y no a los ausentes" do
      as_company(company) do
        WorkshopGroupMember.find_by!(user_id: pedro.id).update!(attended: false)
      end

      result = as_company(company) { described_class.new(taller, size: 2).call }

      expect(result.tables.flatten).to include(paula.id)
      expect(result.tables.flatten).not_to include(pedro.id)
    end

    it "deja al ausente en su mesa en vez de sacarlo" do
      as_company(company) do
        WorkshopGroupMember.find_by!(user_id: pedro.id).update!(attended: false)
      end

      as_company(company) { described_class.new(taller, size: 2).call }

      as_company(company) do
        miembro = WorkshopGroupMember.find_by!(user_id: pedro.id)
        expect(miembro.attended).to be(false)
        expect(miembro.workshop_group_id).to eq(mesa.id)
      end
    end

    it "una persona sentada y una sin sentar quedan una vez cada una, sin duplicar" do
      result = as_company(company) { described_class.new(taller, size: 2).call }

      expect(result.tables.flatten).to contain_exactly(paula.id, pedro.id)
      expect(as_company(company) { WorkshopGroupMember.pluck(:user_id) }).to contain_exactly(paula.id, pedro.id)
    end
  end

  describe "las mesas que quedan" do
    let(:taller) { as_company(company) { open_workshop(["ideation"]) } }

    def mesas(n) = as_company(company) { Array.new(n) { create(:workshop_group, workshop: taller) } }

    it "borra las que quedan vacías" do
      m1, = mesas(3)
      as_company(company) do
        [paula, pedro].each { |u| create(:membership, company: company, user: u, role: "participant") }
        seat(taller, paula, m1)
      end

      result = as_company(company) { described_class.new(taller, size: 4).call }

      expect(result).to be_ok
      expect(as_company(company) { taller.workshop_groups.count }).to eq(1)
    end

    it "no borra la que sólo tiene a un ausente: conserva su asiento" do
      _m1, m2 = mesas(2)
      as_company(company) do
        create(:membership, company: company, user: paula, role: "participant")
        seat(taller, ana, m2)
        WorkshopGroupMember.find_by!(user_id: ana.id).update!(attended: false)
      end

      as_company(company) { described_class.new(taller, size: 4).call }

      as_company(company) do
        expect(WorkshopGroup.exists?(m2.id)).to be(true)
        expect(WorkshopGroupMember.find_by!(user_id: ana.id).workshop_group_id).to eq(m2.id)
      end
    end

    # Con propuestas el servicio ni arranca, así que se anula ese guarda: lo
    # que se fija es la condición del barrido, que cubre la propuesta que entra
    # DESPUÉS del guarda (el escritor no toma el lock).
    it "no borra una mesa que queda vacía pero tiene una propuesta, ni la propuesta" do
      m1, m2 = mesas(2)
      proposal = as_company(company) do
        [paula, pedro].each { |u| create(:membership, company: company, user: u, role: "participant") }
        seat(taller, paula, m1)
        step = step_of(taller)
        idea = create(:idea, challenge: step.challenge, status: "active")
        WorkshopProposal.create!(workshop_group: m2, idea: idea, challenge_step: step,
                                 status: "pending", payload: { "titulo" => "x" })
      end
      allow_any_instance_of(described_class).to receive(:proposals?).and_return(false)

      result = as_company(company) { described_class.new(taller, size: 4).call }

      expect(result).to be_ok
      as_company(company) do
        expect(WorkshopGroup.exists?(m2.id)).to be(true)
        expect(WorkshopProposal.exists?(proposal.id)).to be(true)
      end
    end

    # El barrido de vacías borra con `mesa.destroy!`, y `dependent: :destroy`
    # se llevaría el borrador. A diferencia de las propuestas, acá NO se anula
    # ningún guarda: el reparto corre igual con un borrador, y lo que se fija es
    # que la mesa sobrevive. Perder el texto de la mesa no es un sobrante inocuo.
    it "no borra una mesa que queda vacía pero tiene un borrador, ni el borrador" do
      m1, m2 = mesas(2)
      draft = as_company(company) do
        [paula, pedro].each { |u| create(:membership, company: company, user: u, role: "participant") }
        seat(taller, paula, m1)
        create(:workshop_draft, workshop_group: m2, workshop_challenge: taller.workshop_challenges.first,
                                updated_by: ana, payload: { "resumen" => "a medio escribir" })
      end

      result = as_company(company) { described_class.new(taller, size: 4).call }

      expect(result).to be_ok
      as_company(company) do
        expect(WorkshopGroup.exists?(m2.id)).to be(true)
        expect(WorkshopDraft.exists?(draft.id)).to be(true)
      end
    end
  end

  describe "un vínculo cuyo módulo ya terminó" do
    it "no cuenta como fase: no se rearman mesas alrededor de una ronda cerrada" do
      taller = as_company(company) { open_workshop(["ideation"]) }
      as_company(company) do
        create(:membership, company: company, user: paula, role: "participant")
        step_of(taller).update_columns(status: "completed")
      end

      result = as_company(company) { described_class.new(taller.reload, size: 3).call }

      expect(result).not_to be_ok
      expect(result.errors.join).to include("ya se cerraron")
    end
  end

  describe "el pool en un taller con la presencia registrada" do
    # Sin esto el escaneo es DECORATIVO para idear: `participant_ids` son todos
    # los `participant` de la empresa, así que el reparto sienta igual a quien
    # no vino.
    it "son sólo los sentados y presentes, no toda la empresa" do
      taller = as_company(company) { open_workshop(["ideation"], registered: true) }
      mesa = as_company(company) { create(:workshop_group, workshop: taller) }
      as_company(company) do
        # Pedro es participante de la empresa y nunca escaneó: es quien el pool
        # automático metería de más.
        create(:membership, company: company, user: pedro, role: "participant")
        WorkshopGroupMember.create!(workshop_group: mesa, user_id: paula.id, attended: true)
      end

      result = as_company(company) { described_class.new(taller, size: 4).call }

      expect(result).to be_ok
      expect(result.tables.flatten).to contain_exactly(paula.id)
    end

    # En evolución `absent_ids` no alcanza: el autor que nunca escaneó no tiene
    # asiento, así que no figura como ausente y su idea armaba la mesa igual.
    it "en evolución, la idea de quien no escaneó no arma mesa" do
      taller = as_company(company) { open_workshop(["evolution"], registered: true) }
      mesa = as_company(company) { create(:workshop_group, workshop: taller) }
      as_company(company) do
        step = step_of(taller)
        idea_in(step, paula)
        idea_in(step, pedro)
        WorkshopGroupMember.create!(workshop_group: mesa, user_id: paula.id, attended: true)
      end

      result = as_company(company) { described_class.new(taller, size: 4).call }

      expect(result).to be_ok
      expect(result.tables.flatten).to contain_exactly(paula.id)
    end

    # La de llegada es la PRIMERA mesa creada, así que `seat!` la reusaría como
    # «Mesa 1» conservando `arrival: true` y el nombre, y la sala de la mesa 1
    # quedaría muda para siempre.
    it "no reusa la mesa de llegada, y la borra cuando queda vacía" do
      taller = as_company(company) { open_workshop(["ideation"], registered: true) }
      llegada = as_company(company) { create(:workshop_group, :arrival, workshop: taller) }
      as_company(company) do
        WorkshopGroupMember.create!(workshop_group: llegada, user_id: paula.id, attended: true)
      end

      as_company(company) { described_class.new(taller, size: 4).call }

      mesas = as_company(company) { taller.workshop_groups.reload.to_a }
      expect(mesas.map(&:id)).not_to include(llegada.id)
      expect(mesas.map(&:arrival)).to all(be(false))
      expect(mesas.map(&:name)).to contain_exactly("Mesa 1")
    end
  end
end
