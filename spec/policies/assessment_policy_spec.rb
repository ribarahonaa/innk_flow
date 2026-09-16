# frozen_string_literal: true

require "rails_helper"

# Las policies se prueban por request en todo el repo. Ésta no se puede: la
# línea que importa —llegar al desafío— la tapan los `policy_scope(Challenge)`
# de los controllers de evaluar y el `IdeaPolicy#show?` que pregunta
# `AiSuggestionPolicy#visible?` antes. Por request sólo se puede probar que
# alguien la tapa, no que esta policy lo sepa por su cuenta; mutando esa línea
# la suite de requests quedaba en verde.
RSpec.describe AssessmentPolicy do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  let!(:gina) do
    without_tenant do
      u = create(:user, email: "gina@test.dev")
      create(:membership, :gestor, company: company, user: u)
      u
    end
  end

  let!(:paso) do
    as_company(company) do
      desafio = create(:challenge, name: "Merma")
      p = desafio.steps.create!(kind: "evaluation", position: 1, name: "Técnica")
      StepAssignment.create!(challenge_step: p, user: gina, role: "evaluator")
      p
    end
  end

  def puede_evaluar?
    as_company(company) do
      membresia = Membership.find_by!(user_id: gina.id)
      described_class.new(membresia, Assessment.new(challenge_step: paso)).create?
    end
  end

  # Un gestor dado de baja del desafío conserva su asignación: la baja no la
  # borra. La asignación sola no alcanza.
  it "quien no llega al desafío no evalúa, aunque tenga la asignación" do
    expect(puede_evaluar?).to be(false)
  end

  # El control: con el desafío asignado, la misma asignación sí alcanza. Sin
  # esto, el `false` de arriba podría venir de cualquier otra cosa.
  it "y con el desafío asignado, la misma asignación alcanza" do
    as_company(company) { ChallengeGestor.create!(challenge: paso.challenge, user: gina) }

    expect(puede_evaluar?).to be(true)
  end
end
