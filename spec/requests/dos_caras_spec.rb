# frozen_string_literal: true

require "rails_helper"

# La pantalla de un módulo tiene dos caras y la decide `step.touched?`, no el
# estado del desafío: un desafío en curso sigue teniendo módulos pendientes
# más adelante, y ésos son configurables.
RSpec.describe "las dos caras de un módulo", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  let!(:admin) do
    without_tenant do
      u = create(:user, email: "admin@test.dev", name: "Ana Admin")
      create(:membership, :admin, company: company, user: u)
      u
    end
  end

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma", ai_default_mode: "human")
      seed_form!(c.steps.create!(kind: "ideation", position: 1))
      c.steps.create!(kind: "evaluation", position: 2, name: "Comité")
      c.steps.create!(kind: "selection", position: 3, name: "Corte")
      c.steps.create!(kind: "reporting", position: 4, name: "Informe")
      c.steps.create!(kind: "evolution", position: 5, name: "Mejorar")
      c
    end
  end

  def paso(kind) = as_company(company) { challenge.steps.reload.find { |s| s.kind == kind } }

  before { sign_in(admin, company: company) }

  describe "cara A: el módulo está pendiente" do
    it "monta la isla de ajustes en los cinco kinds" do
      %w[ideation evolution evaluation selection reporting].each do |kind|
        get challenge_step_path(challenge, paso(kind))

        expect(response.body).to include('data-island="step-settings"'),
                                 "faltó la isla en #{kind}"
      end
    end

    it "trae el form del módulo, con nombre y modo de IA" do
      get challenge_step_path(challenge, paso("selection"))

      expect(response.body).to include('name="challenge_step[name]"')
      expect(response.body).to include('name="challenge_step[ai_mode]"')
    end

    it "no muestra el trabajo del módulo, que todavía no existe" do
      get challenge_step_path(challenge, paso("selection"))

      expect(response.body).not_to include("Confirmar el corte")
    end
  end

  describe "cara B: el módulo ya arrancó" do
    before do
      as_company(company) do
        create(:idea, challenge: challenge, author: admin, status: "active")
          .update!(submitted_at: Time.current)
        challenge.pipeline.start!
      end
    end

    it "no monta la isla de ajustes" do
      get challenge_step_path(challenge, paso("ideation"))

      expect(response.body).not_to include('data-island="step-settings"')
    end

    it "muestra la configuración congelada" do
      get challenge_step_path(challenge, paso("ideation"))

      expect(response.body).to include("Quedó fijado")
    end

    # Las tres cosas que siguen vivas: modo de IA, nombre y asignaciones.
    it "deja ajustar el modo de IA" do
      get challenge_step_path(challenge, paso("ideation"))

      expect(response.body).to include('name="challenge_step[ai_mode]"')
    end

    it "los módulos de más adelante siguen en cara A" do
      get challenge_step_path(challenge, paso("selection"))

      expect(response.body).to include('data-island="step-settings"')
    end
  end
end
