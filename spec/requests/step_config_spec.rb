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

  # `permit` es una lista blanca: `status`, `kind`, `position`, `challenge_id`
  # y `company_id` no están en `ADJUSTABLE_ATTRIBUTES` ni en las columnas
  # estructurales que agrega `step_params`, así que nunca llegan a `update`.
  it "no permite tocar columnas que no son ajustables ni estructurales" do
    antes = corte.attributes.slice("status", "kind", "position", "challenge_id", "company_id")

    patch challenge_step_path(challenge, corte),
          params: { challenge_step: {
            status: "completed", kind: "reporting", position: "99",
            challenge_id: SecureRandom.uuid, company_id: SecureRandom.uuid
          } }

    despues = corte.attributes.slice("status", "kind", "position", "challenge_id", "company_id")
    expect(despues).to eq(antes)
  end

  # `Flow::StepSettings.filtrar` promete sanar lo malformado sin reventar. La
  # raíz también tiene que cumplirlo: antes, un `config` que no llegaba como
  # hash tiraba `NoMethodError` o `TypeError` en vez de sanear a `{}`.
  it "un config escalar no revienta: se sanea a vacío" do
    patch challenge_step_path(challenge, corte),
          params: { challenge_step: { config: "x" } }

    expect(response).to have_http_status(:redirect)
    expect(corte.config).to eq({})
  end

  it "un config en array no revienta: se sanea a vacío" do
    patch challenge_step_path(challenge, corte),
          params: { challenge_step: { config: ["x"] } }

    expect(response).to have_http_status(:redirect)
    expect(corte.config).to eq({})
  end

  # `belongs_to optional: true` no valida existencia: un id borrado o
  # inventado llegaba intacto hasta la FK compuesta y reventaba con
  # `PG::ForeignKeyViolation` en vez de un error de validación legible.
  it "un criteria_set_id inexistente no revienta: lo rechaza la validación" do
    patch challenge_step_path(challenge, corte),
          params: { challenge_step: { criteria_set_id: SecureRandom.uuid } }

    expect(response).to have_http_status(:redirect)
    expect(flash[:alert]).to be_present
    expect(corte.criteria_set_id).to be_nil
  end

  it "un source_step_id inexistente no revienta: lo rechaza la validación" do
    patch challenge_step_path(challenge, corte),
          params: { challenge_step: { source_step_id: SecureRandom.uuid } }

    expect(response).to have_http_status(:redirect)
    expect(flash[:alert]).to be_present
    expect(corte.source_step_id).to be_nil
  end

  it "un participante no puede configurar el módulo" do
    participante = without_tenant do
      u = create(:user, email: "participante@test.dev", name: "Paula Participante")
      create(:membership, :participant, company: company, user: u)
      u
    end
    sign_in(participante, company: company)

    patch challenge_step_path(challenge, corte),
          params: { challenge_step: { config: { cut: { mode: "top_n", value: "4" } } } }

    expect(response).to have_http_status(:forbidden)
    expect(corte.config).to eq({})
  end

  # Un set `library` es compartible por diseño; uno `inline` es de UN módulo
  # —su `owner_step`— y si ese módulo fuera de otro desafío, editar los
  # criterios desde acá reescribiría, sin darse cuenta, los de ese otro
  # desafío.
  describe "con un set de criterios inline de otro desafío" do
    it "rechaza el criteria_set_id" do
      ajeno = as_company(company) do
        otro = create(:challenge, name: "Otro desafío")
        paso = otro.steps.create!(kind: "evaluation", position: 1, name: "Comité ajeno")
        CriteriaSet.create!(name: "Del otro", scope: "inline", owner_step_id: paso.id)
      end

      patch challenge_step_path(challenge, corte),
            params: { challenge_step: { criteria_set_id: ajeno.id } }

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to be_present
      expect(corte.criteria_set_id).to be_nil
    end
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

    # `criteria_set_id` es FROZEN_ATTRIBUTE igual que `config` y
    # `source_step_id`: si no lo estuviera, una evaluación en curso podría
    # dejar la columna sin coincidir con el `criteria_set_id` que ya se
    # congeló en `resolved_config` al activarse.
    it "rechaza cambiar el set de criterios" do
      set = as_company(company) { CriteriaSet.create!(name: "Suelto", scope: "library") }

      patch challenge_step_path(challenge, idear),
            params: { challenge_step: { criteria_set_id: set.id } }

      expect(idear.criteria_set_id).to be_nil
      expect(flash[:alert]).to be_present
    end
  end

  # `update_pipeline?` suma `&& !closed? && !archived?` sobre `manager?`. Ésa
  # es toda la diferencia entre las dos autorizaciones, y es la que importa.
  describe "con el desafío cerrado" do
    before { as_company(company) { challenge.update!(status: "closed") } }

    # Ancla que el rechazo es de la POLICY (403) y no una casualidad de que
    # `antes` ya fuera `{}`: sin este `expect` de status, el test pasaría
    # igual si la acción fallara por cualquier otro motivo.
    it "no deja reescribir la configuración" do
      antes = corte.config

      patch challenge_step_path(challenge, corte),
            params: { challenge_step: { config: { cut: { mode: "top_n", value: "9" } } } }

      expect(response).to have_http_status(:forbidden)
      expect(corte.config).to eq(antes)
    end

    it "sí deja ajustar el modo de IA" do
      patch challenge_step_path(challenge, corte),
            params: { challenge_step: { ai_mode: "human" } }

      expect(corte.ai_mode).to eq("human")
    end
  end
end
