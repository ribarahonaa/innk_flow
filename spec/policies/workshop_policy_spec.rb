# frozen_string_literal: true

require "rails_helper"

# El reparto completo. Existe porque abrir un permiso de más no rompe ningún
# otro test: es el mismo motivo de `spec/policies/gestor_administra_spec.rb`.
RSpec.describe WorkshopPolicy do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(role)
    without_tenant do
      u = create(:user)
      create(:membership, role.to_sym, company: company, user: u)
    end
  end

  let(:admin) { member(:admin) }
  let(:challenge_gestor) { member(:gestor) }
  let(:participant) { member(:participant) }

  it "sin membresía, el scope no devuelve nada" do
    as_company(company) do
      create(:workshop)
      expect(WorkshopPolicy::Scope.new(nil, Workshop).resolve.count).to eq(0)
    end
  end

  it "quien administra la empresa ve y arma talleres" do
    as_company(company) do
      workshop = create(:workshop)
      expect(WorkshopPolicy.new(admin, workshop).show?).to be(true)
      expect(WorkshopPolicy.new(admin, workshop).update?).to be(true)
    end
  end

  it "quien está en una mesa ve el taller pero no lo arma" do
    as_company(company) do
      workshop = create(:workshop)
      create(:workshop_group_member, workshop_group: create(:workshop_group, workshop: workshop),
                                     user: participant.user)

      expect(WorkshopPolicy.new(participant, workshop).show?).to be(true)
      expect(WorkshopPolicy.new(participant, workshop).update?).to be(false)
    end
  end

  # Review Focus 5: participar del desafío NO es una invitación.
  it "quien participa de un desafío vinculado, sin mesa, NO ve el taller" do
    as_company(company) do
      challenge = create(:challenge)
      workshop = create(:workshop)
      create(:workshop_challenge, workshop: workshop, challenge: challenge)

      expect(WorkshopPolicy.new(participant, workshop).show?).to be(false)
      expect(WorkshopPolicy::Scope.new(participant, Workshop).resolve).not_to include(workshop)
    end
  end

  # Review Focus 4: el gestor sólo suma los desafíos que le asignaron.
  it "el gestor suma al taller sólo sus desafíos" do
    as_company(company) do
      own_challenge = create(:challenge)
      other_challenge = create(:challenge)
      ChallengeGestor.create!(challenge: own_challenge, user: challenge_gestor.user)
      workshop = create(:workshop)

      expect(WorkshopPolicy.new(challenge_gestor, workshop).add_challenge?(own_challenge)).to be(true)
      expect(WorkshopPolicy.new(challenge_gestor, workshop).add_challenge?(other_challenge)).to be(false)
    end
  end
end
