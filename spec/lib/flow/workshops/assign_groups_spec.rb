# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flow::Workshops::AssignGroups do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  let(:paula) { as_company(company) { create(:user, name: "Paula") } }
  let(:pedro) { as_company(company) { create(:user, name: "Pedro") } }
  let(:ana)   { as_company(company) { create(:user, name: "Ana") } }

  def open_workshop(*kinds_and_challenges)
    workshop = create(:workshop, status: "open")
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

      expect(as_company(company) { described_class.new(taller, size: 4).call }).not_to be_ok
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
end
