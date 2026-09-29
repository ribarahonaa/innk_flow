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

  # El fantasma se arma como se arma de verdad: la asignación nace mientras
  # Gina acompaña el desafío —ahora el modelo no deja crearla de otra forma— y
  # sobrevive a que la saquen. `Flow::Assignments::Release` suelta estas
  # asignaciones desde las dos pantallas que las dejan huérfanas, pero no las
  # suelta todas a propósito: la de quien ya evaluó y la de un módulo cerrado
  # se quedan. Ésta es la línea que las sostiene igual.
  let!(:paso) do
    as_company(company) do
      desafio = create(:challenge, name: "Merma")
      p = desafio.steps.create!(kind: "evaluation", position: 1, name: "Técnica")
      acompana = ChallengeGestor.create!(challenge: desafio, user: gina)
      StepAssignment.create!(challenge_step: p, user: gina, role: "evaluator")
      acompana.destroy!
      p
    end
  end

  def puede_evaluar?
    as_company(company) do
      membresia = Membership.find_by!(user_id: gina.id)
      described_class.new(membresia, Assessment.new(challenge_step: paso)).create?
    end
  end

  # Un gestor que dejó de acompañar el desafío puede conservar su asignación.
  # La asignación sola no alcanza.
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
