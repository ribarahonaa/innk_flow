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

  # `ChallengeStepPolicy#skip?` es `administers?(challenge)` y no mira el estado
  # del módulo, así que la ruta llega a uno ya COMPLETADO: `skip!` le pisaba el
  # `status`, le reescribía el `completed_at` y respondía «Módulo salteado.».
  # Un módulo que corrió entero pasaba a decir que nunca corrió, con sus
  # evaluaciones intactas debajo.
  #
  # Es la misma superficie que el defecto del salteo: sin control en ninguna
  # vista, pero la ruta y la policy sí llegan.
  it "no reescribe uno que ya terminó, y lo dice" do
    challenge = arrancado(%w[ideation reporting])
    # Por el dominio y no por `advance`: completar «Idear» desde la ruta pide
    # el mínimo de ideas postuladas, y lo que este ejemplo prueba es el POST de
    # abajo.
    completado = as_company(company) do
      paso = challenge.steps.ordered.first
      Flow::Handlers::Base.for(paso).complete!
      challenge.pipeline.continue!
      paso.reload
    end
    expect(completado).to be_completed
    cerrado_en = completado.completed_at

    post skip_challenge_step_path(challenge, completado)

    expect(flash[:alert]).to include("ya terminó")
    as_company(company) do
      quedo = challenge.steps.ordered.first.reload
      expect(quedo).to be_completed
      expect(quedo.completed_at).to eq(cerrado_en)
      expect(quedo.settings).not_to have_key("skip_reason")
    end
  end

  # Y lo mismo con uno ya salteado: un segundo POST le reescribía el motivo y
  # la fecha.
  it "ni uno ya salteado" do
    challenge = arrancado(%w[ideation evaluation reporting])
    primero = as_company(company) { challenge.steps.ordered.first }
    post skip_challenge_step_path(challenge, primero), params: { reason: "el primero" }
    salteado = as_company(company) { challenge.steps.ordered.first.reload }
    cerrado_en = salteado.completed_at

    post skip_challenge_step_path(challenge, salteado), params: { reason: "otro motivo" }

    # «ya está salteado» y no «ya terminó»: son dos motivos distintos y el
    # aviso los distingue.
    expect(flash[:alert]).to include("ya está salteado")
    as_company(company) do
      quedo = challenge.steps.ordered.first.reload
      expect(quedo.completed_at).to eq(cerrado_en)
      expect(quedo.settings["skip_reason"]).to eq("el primero")
    end
  end

  # El defecto se veía acá: `activate!` levanta `StepNotReady` y nadie lo
  # rescataba, así que el POST moría con un 500 DESPUÉS de que el salteo ya se
  # había guardado. Quien lo pedía veía la pantalla de error y no se enteraba de
  # que el módulo había quedado salteado.
  it "no revienta si el siguiente no puede arrancar: el salteo queda y lo dice" do
    challenge = arrancado(%w[ideation evaluation])
    activo = as_company(company) do
      paso = challenge.steps.ordered.first
      # Un set sin criterios activos: es lo único que `validate` no mira, así
      # que llega hasta `activate!`.
      set = CriteriaSet.create!(name: "Roto", scope: "library")
      set.refresh_status!
      challenge.steps.ordered.last.update!(criteria_set: set)
      paso
    end

    post skip_challenge_step_path(challenge, activo)

    expect(response).to have_http_status(:found)
    expect(flash[:alert]).to include("el flujo no avanzó", "al menos un criterio activo")
    as_company(company) do
      expect(challenge.steps.ordered.first.reload).to be_skipped
      expect(challenge.steps.ordered.last.reload).to be_pending
      expect(challenge.reload).to be_running
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
