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

  # Ítem 2 de los minors: el spec §6 promete «crear» al gestor, y con
  # `manager?` puro y `administers_any?` exigiendo un desafío ya vinculado, no
  # podía ni empezar. Se abre por AUTORÍA, no por rol: los dos sentidos.
  describe "el gestor y el taller que crea" do
    let(:other_gestor) { member(:gestor) }

    it "un gestor crea; quien participa, no" do
      expect(WorkshopPolicy.new(challenge_gestor, Workshop).create?).to be(true)
      expect(WorkshopPolicy.new(participant, Workshop).create?).to be(false)
      expect(WorkshopPolicy.new(nil, Workshop).create?).to be(false)
    end

    it "administra, ve y trabaja el taller que creó aunque todavía no tenga desafíos" do
      as_company(company) do
        workshop = create(:workshop, created_by: challenge_gestor.user)
        policy = WorkshopPolicy.new(challenge_gestor, workshop)

        expect(policy.show?).to be(true)
        expect(policy.update?).to be(true)
        expect(policy.work?).to be(true)
      end
    end

    it "suma al taller que creó sus desafíos y sólo los suyos" do
      as_company(company) do
        own_challenge = create(:challenge)
        other_challenge = create(:challenge)
        ChallengeGestor.create!(challenge: own_challenge, user: challenge_gestor.user)
        policy = WorkshopPolicy.new(challenge_gestor, create(:workshop, created_by: challenge_gestor.user))

        expect(policy.add_challenge?(own_challenge)).to be(true)
        expect(policy.add_challenge?(other_challenge)).to be(false)
      end
    end

    # El lado que importa: abrir de más no rompe ningún otro test.
    it "NO administra ni ve el taller de otra persona que no toca sus desafíos" do
      as_company(company) do
        workshop = create(:workshop, created_by: other_gestor.user)
        policy = WorkshopPolicy.new(challenge_gestor, workshop)

        expect(policy.show?).to be(false)
        expect(policy.update?).to be(false)
        expect(policy.work?).to be(false)
      end
    end

    it "si le revocan la asignación del único desafío del taller, deja de administrarlo" do
      as_company(company) do
        challenge = create(:challenge)
        assignment = ChallengeGestor.create!(challenge: challenge, user: challenge_gestor.user)
        workshop = create(:workshop, created_by: challenge_gestor.user)
        create(:workshop_challenge, workshop: workshop, challenge: challenge)
        expect(WorkshopPolicy.new(challenge_gestor, workshop).update?).to be(true)

        assignment.destroy!
        policy = WorkshopPolicy.new(challenge_gestor, workshop.reload)
        expect(policy.update?).to be(false)
        expect(policy.work?).to be(false)
        expect(policy.manage_groups?).to be(false)
      end
    end

    it "un taller sin autor (creado por quien ya no está) no se abre a ningún gestor" do
      as_company(company) do
        workshop = create(:workshop, created_by: nil)

        expect(WorkshopPolicy.new(challenge_gestor, workshop).update?).to be(false)
      end
    end

    it "quien creó un taller siendo gestor y ya no lo es deja de administrarlo" do
      as_company(company) do
        workshop = create(:workshop, created_by: participant.user)

        expect(WorkshopPolicy.new(participant, workshop).update?).to be(false)
      end
    end
  end

  # Ítem 3: `administers_any?` se pregunta tres veces por render y cargaba los
  # vínculos sin precargar, con un `exists?` por vínculo para el gestor.
  it "responder update? y work? cuesta una sola consulta de asignaciones, sin importar cuántos vínculos" do
    as_company(company) do
      workshop = create(:workshop)
      # Sólo el ÚLTIMO desafío es del gestor: el `any?` viejo recorría los tres
      # vínculos con un `exists?` cada uno; el subquery, uno solo.
      3.times do |i|
        challenge = create(:challenge)
        create(:workshop_challenge, workshop: workshop, challenge: challenge)
        ChallengeGestor.create!(challenge: challenge, user: challenge_gestor.user) if i == 2
      end
      policy = WorkshopPolicy.new(challenge_gestor, workshop)

      queries = []
      counter = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?("challenge_gestores") }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        3.times { policy.update? }
        policy.work?
      end

      expect(queries.size).to eq(1)
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

  # Fix round 1: la rama del gestor en `Scope#resolve` no tenía cobertura —
  # ningún ejemplo anterior llegaba a `own.or(scope.where(id: managed_workshop_ids))`.
  describe "el Scope suma los talleres del gestor por sus desafíos asignados" do
    it "ve el taller de un desafío que le asignaron, sin estar en ninguna mesa" do
      as_company(company) do
        challenge = create(:challenge)
        workshop = create(:workshop)
        create(:workshop_challenge, workshop: workshop, challenge: challenge)
        ChallengeGestor.create!(challenge: challenge, user: challenge_gestor.user)

        expect(WorkshopPolicy::Scope.new(challenge_gestor, Workshop).resolve).to include(workshop)
      end
    end

    it "no ve el taller de un desafío que no le asignaron" do
      as_company(company) do
        mine = create(:challenge)
        other = create(:challenge)
        workshop = create(:workshop)
        create(:workshop_challenge, workshop: workshop, challenge: other)
        ChallengeGestor.create!(challenge: mine, user: challenge_gestor.user)

        expect(WorkshopPolicy::Scope.new(challenge_gestor, Workshop).resolve).not_to include(workshop)
      end
    end
  end

  # Fix round 1: `work?` no tenía ningún test, y tres tareas posteriores la
  # van a usar como puerta de entrada a la sala de trabajo.
  describe "#work?" do
    it "lo abre quien está en una mesa de ESE taller" do
      as_company(company) do
        workshop = create(:workshop)
        create(:workshop_group_member, workshop_group: create(:workshop_group, workshop: workshop),
                                       user: participant.user)

        expect(WorkshopPolicy.new(participant, workshop).work?).to be(true)
      end
    end

    # Prueba que la consulta filtra por taller y no sólo por persona.
    it "se lo niega a quien está en una mesa de OTRO taller" do
      as_company(company) do
        mine = create(:workshop)
        other = create(:workshop)
        create(:workshop_group_member, workshop_group: create(:workshop_group, workshop: other),
                                       user: participant.user)

        expect(WorkshopPolicy.new(participant, mine).work?).to be(false)
      end
    end

    it "lo abre quien administra alguno de sus desafíos, sin estar en ninguna mesa" do
      as_company(company) do
        challenge = create(:challenge)
        workshop = create(:workshop)
        create(:workshop_challenge, workshop: workshop, challenge: challenge)
        ChallengeGestor.create!(challenge: challenge, user: challenge_gestor.user)

        expect(WorkshopPolicy.new(challenge_gestor, workshop).work?).to be(true)
      end
    end

    it "se lo niega a quien no está en ninguna mesa ni administra nada" do
      as_company(company) do
        workshop = create(:workshop)

        expect(WorkshopPolicy.new(participant, workshop).work?).to be(false)
      end
    end
  end
end
