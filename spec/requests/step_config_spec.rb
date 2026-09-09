# frozen_string_literal: true

require "rails_helper"

# El ÚNICO camino de escritura de la configuración de un módulo.
RSpec.describe "configurar un módulo", type: :request do
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
      c
    end
  end

  def corte = as_company(company) { challenge.steps.reload.find(&:selection?) }

  before { sign_in(admin, company: company) }

  it "guarda el corte con los tipos que declara el esquema" do
    patch challenge_step_path(challenge, corte),
          params: { challenge_step: { config: { cut: { mode: "top_n", value: "4" } } } }

    expect(corte.config).to eq("cut" => { "mode" => "top_n", "value" => 4 })
  end

  it "descarta claves que el esquema no declara para ese kind" do
    patch challenge_step_path(challenge, corte),
          params: { challenge_step: { config: { cut: { mode: "top_n" }, colado: "x" } } }

    expect(corte.config).to eq("cut" => { "mode" => "top_n" })
  end

  it "guarda el módulo de origen del puntaje, que es columna y no config" do
    evaluacion = as_company(company) { challenge.steps.reload.find(&:evaluation?) }

    patch challenge_step_path(challenge, corte),
          params: { challenge_step: { source_step_id: evaluacion.id } }

    expect(corte.source_step_id).to eq(evaluacion.id)
  end

  it "sigue guardando nombre y modo de IA, como hasta ahora" do
    patch challenge_step_path(challenge, corte),
          params: { challenge_step: { name: "Corte final", ai_mode: "ai_assisted" } }

    expect(corte.name).to eq("Corte final")
    expect(corte.ai_mode).to eq("ai_assisted")
  end

  describe "con el módulo ya en curso" do
    before do
      as_company(company) do
        create(:idea, challenge: challenge, author: admin, status: "active")
          .update!(submitted_at: Time.current)
        challenge.pipeline.start!
      end
    end

    def idear = as_company(company) { challenge.steps.reload.find(&:ideation?) }

    # `config` es FROZEN_ATTRIBUTE: lo cuida el modelo, no el controller, para
    # que no haya dos copias de la regla que se puedan desincronizar.
    it "rechaza un cambio estructural" do
      antes = idear.config

      patch challenge_step_path(challenge, idear),
            params: { challenge_step: { config: { min_ideas: 99 } } }

      expect(idear.config).to eq(antes)
      expect(flash[:alert]).to be_present
    end

    it "acepta el cambio de modo de IA, que es política operativa" do
      patch challenge_step_path(challenge, idear),
            params: { challenge_step: { ai_mode: "ai_assisted" } }

      expect(idear.ai_mode).to eq("ai_assisted")
    end
  end

  # `update_pipeline?` suma `&& !closed? && !archived?` sobre `manager?`. Ésa
  # es toda la diferencia entre las dos autorizaciones, y es la que importa.
  describe "con el desafío cerrado" do
    before { as_company(company) { challenge.update!(status: "closed") } }

    it "no deja reescribir la configuración" do
      antes = corte.config

      patch challenge_step_path(challenge, corte),
            params: { challenge_step: { config: { cut: { mode: "top_n", value: "9" } } } }

      expect(corte.config).to eq(antes)
    end

    it "sí deja ajustar el modo de IA" do
      patch challenge_step_path(challenge, corte),
            params: { challenge_step: { ai_mode: "human" } }

      expect(corte.ai_mode).to eq("human")
    end
  end
end
