# frozen_string_literal: true

require "rails_helper"

# Saltear un módulo NO tiene control en ninguna vista —la ruta existe y la
# policy también, pero nada la ofrece— así que un request spec es la única
# cobertura posible, y por eso el defecto sobrevivió: `skip` llamaba a
# `advance!` para seguir el flujo, y `advance!` corta con `failure` justo
# cuando no hay módulo en curso, que es el estado que el salteo acaba de
# dejar. Saltear trababa el flujo sin avisar.
RSpec.describe "saltear un módulo", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }
  let!(:admin) do
    without_tenant do
      u = create(:user, email: "admin@test.dev")
      create(:membership, :admin, company: company, user: u)
      u
    end
  end

  def arrancado(kinds)
    as_company(company) do
      challenge = create(:challenge, name: "Merma", ai_default_mode: "human")
      kinds.each_with_index do |kind, i|
        step = challenge.steps.create!(kind: kind, position: i + 1)
        seed_form!(step) if kind == "ideation"
      end
      challenge.pipeline.start!
      challenge.steps.reset
      challenge
    end
  end

  before { sign_in(admin, company: company) }

  it "abre el siguiente módulo en vez de dejar el flujo trabado" do
    challenge = arrancado(%w[ideation evaluation reporting])
    activo = as_company(company) { challenge.steps.ordered.first }

    post skip_challenge_step_path(challenge, activo)

    as_company(company) do
      pasos = challenge.steps.ordered.reload
      expect(pasos.first).to be_skipped
      expect(pasos.second).to be_active
      expect(challenge.reload).to be_running
    end
  end

  it "cierra el desafío al saltear el último" do
    challenge = arrancado(%w[ideation reporting])
    primero = as_company(company) { challenge.steps.ordered.first }
    post skip_challenge_step_path(challenge, primero)
    segundo = as_company(company) { challenge.steps.ordered.second }
    post skip_challenge_step_path(challenge, segundo)

    as_company(company) do
      expect(challenge.steps.ordered.reload.map(&:status)).to eq(%w[skipped skipped])
      expect(challenge.reload).to be_closed
    end
  end

  # Saltear uno PENDIENTE más adelante no tiene nada que abrir, así que
  # `continue!` se niega. Se avisa en vez de decir sólo «Módulo salteado»: el
  # salteo se guardó igual, y eso sube el piso de inserción del flujo —los
  # pendientes anteriores dejan de poder moverse o borrarse—, que es demasiado
  # para dejarlo sin decir nada.
  it "saltear uno pendiente no mueve el que está en curso, y lo dice" do
    challenge = arrancado(%w[ideation evaluation reporting])
    pendiente = as_company(company) { challenge.steps.ordered.last }

    post skip_challenge_step_path(challenge, pendiente)

    expect(flash[:alert]).to include("el flujo no avanzó")
    as_company(company) do
      pasos = challenge.steps.ordered.reload
      expect(pasos.first).to be_active
      expect(pasos.last).to be_skipped
    end
  end

  it "quien participa no puede saltear" do
    challenge = arrancado(%w[ideation evaluation])
    participante = without_tenant do
      u = create(:user, email: "part@test.dev")
      create(:membership, company: company, user: u, role: "participant")
      u
    end
    sign_in(participante, company: company)
    activo = as_company(company) { challenge.steps.ordered.first }

    post skip_challenge_step_path(challenge, activo)

    expect(response).to have_http_status(:forbidden)
    as_company(company) { expect(challenge.steps.ordered.first.reload).to be_active }
  end
end
