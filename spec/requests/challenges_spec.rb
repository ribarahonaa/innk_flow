# frozen_string_literal: true

require "rails_helper"

RSpec.describe "desafíos", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }
  let!(:owner) do
    without_tenant do
      u = create(:user, email: "owner@test.dev")
      create(:membership, :owner, company: company, user: u)
      u
    end
  end
  let!(:participant) do
    without_tenant do
      u = create(:user, email: "part@test.dev")
      create(:membership, company: company, user: u, role: "participant")
      u
    end
  end

  describe "como owner" do
    before { sign_in(owner, company: company) }

    it "lista los desafíos" do
      as_company(company) { create(:challenge, name: "Merma en bodega") }

      get challenges_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Merma en bodega")
    end

    it "crea un desafío y lo manda al builder" do
      post challenges_path, params: {
        challenge: { name: "Nuevo reto", brief: "Un brief", ai_default_mode: "ai_assisted" }
      }

      challenge = as_company(company) { Challenge.find_by(name: "Nuevo reto") }
      expect(challenge).to be_present
      expect(response).to redirect_to(builder_challenge_path(challenge))
    end

    # `create` guarda adentro de una transacción —la auto-asignación del
    # gestor va en la misma— y desde esa Tarea nada ejercitaba la rama del
    # guardado fallido: sólo la sostenía la lectura del código.
    it "si el guardado falla, vuelve al form con 422 y no crea nada" do
      expect do
        post challenges_path, params: { challenge: { name: "", brief: "Un brief" } }
      end.not_to change { as_company(company) { Challenge.count } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Nuevo desafío", "Crear y armar el flujo")
    end

    it "renderiza la vista del desafío con su flujo" do
      challenge = as_company(company) do
        c = create(:challenge, name: "Merma")
        seed_form!(c.steps.create!(kind: "ideation", position: 1, name: "Postulación"))
        c.steps.create!(kind: "selection", position: 2, name: "Corte")
        c
      end

      get challenge_path(challenge)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Postulación", "Corte")
      # La selección sin evaluación previa: el banner de validación tiene que
      # renderizar, no reventar el template.
      expect(response.body).to include("Falta resolver")
    end

    it "renderiza el builder con las props serializadas por el server" do
      challenge = as_company(company) { create(:challenge) }

      get builder_challenge_path(challenge)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-island="pipeline-builder"')
      expect(response.body).to include("packs/pipeline_builder")
    end

    it "no arranca un desafío sin módulo de ideación" do
      challenge = as_company(company) do
        c = create(:challenge)
        c.steps.create!(kind: "evaluation", position: 1)
        c
      end

      post start_challenge_path(challenge)
      expect(as_company(company) { challenge.reload }).to be_draft
      expect(flash[:alert]).to match(/Falta el módulo/)
    end

    it "arranca un desafío válido y activa el primer módulo" do
      challenge = as_company(company) do
        c = create(:challenge)
        seed_form!(c.steps.create!(kind: "ideation", position: 1))
        c.steps.create!(kind: "evaluation", position: 2)
        c
      end

      post start_challenge_path(challenge)
      as_company(company) do
        expect(challenge.reload).to be_running
        expect(challenge.steps.ordered.first).to be_active
      end
    end
  end

  describe "como participante" do
    before { sign_in(participant, company: company) }

    it "ve el índice" do
      get challenges_path
      expect(response).to have_http_status(:ok)
    end

    it "NO puede crear desafíos" do
      get new_challenge_path
      expect(response).to have_http_status(:forbidden)
    end

    it "NO puede abrir el builder" do
      challenge = as_company(company) { create(:challenge) }

      get builder_challenge_path(challenge)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "aislamiento entre empresas" do
    let!(:other_company) { without_tenant { create(:company, slug: "otra") } }

    it "un desafío de otra empresa da 404, no 403" do
      foreign = as_company(other_company) { create(:challenge, name: "Ajeno") }
      sign_in(owner, company: company)

      get challenge_path(foreign)
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include("Ajeno")
    end
  end

  # El encabezado de la tarjeta «Flujo» contesta «dónde está el proceso», que
  # es lo que dice su propio comentario. El conteo de módulos que quedaron
  # atrás no lo contestaba: con seis hechos de siete el que corre es el
  # SÉPTIMO, así que «6 de 7 · ahora: X» invitaba a leer el 6 como la posición
  # de X y apuntaba al módulo anterior. Nada afirmaba ninguna de las tres
  # ramas, que es cómo pudieron quedar así.
  describe "el encabezado de la tarjeta «Flujo»" do
    before { sign_in(owner, company: company) }

    it "ubica el módulo en curso por su POSICIÓN y no por cuántos quedaron atrás" do
      challenge = as_company(company) do
        c = create(:challenge, :running, name: "Merma")
        seed_form!(c.steps.create!(kind: "ideation", position: 1, name: "Postulación", status: "completed"))
        c.steps.create!(kind: "evolution", position: 2, name: "Feedback", status: "skipped")
        # Fraccionaria a propósito: `position` es decimal(20,10) e insertar
        # entre dos módulos da `(a+b)/2`, así que sólo el ÍNDICE da el número
        # que muestra la columna «#» de la tabla de abajo. Con 1, 2 y 3 las dos
        # formas coinciden y el caso no distinguiría una de otra.
        c.steps.create!(kind: "reporting", position: 2.5, name: "Reporte de cierre", status: "active")
        c
      end

      get challenge_path(challenge)

      expect(response.body).to include("ahora: Reporte de cierre · módulo 3 de 3")
      # El número viejo contaba completados y salteados: dos, o sea el módulo
      # de antes del que corre.
      expect(response.body).not_to include("2 de 3 ·")
    end

    # `Pipeline#close!` cierra el desafío SIN tocar los pasos, así que uno
    # cerrado se queda con su módulo en curso. La rama se decidía por «no hay
    # activo» cuando lo que quiere decir es «el flujo terminó», así que el chip
    # de arriba decía «Cerrado» y la línea de abajo «ahora: Reporte de cierre».
    it "con el desafío cerrado el flujo terminó, aunque quedara un módulo en curso" do
      challenge = as_company(company) do
        c = create(:challenge, name: "Merma", status: "closed")
        seed_form!(c.steps.create!(kind: "ideation", position: 1, name: "Postulación", status: "completed"))
        c.steps.create!(kind: "reporting", position: 2, name: "Reporte de cierre", status: "active")
        c
      end

      get challenge_path(challenge)

      expect(response.body).to include("flujo terminado")
      expect(response.body).not_to include("ahora: Reporte de cierre")
    end

    it "y con el flujo terminado no repite el largo del flujo" do
      challenge = as_company(company) do
        c = create(:challenge, name: "Merma", status: "closed")
        seed_form!(c.steps.create!(kind: "ideation", position: 1, name: "Postulación", status: "completed"))
        c.steps.create!(kind: "reporting", position: 2, name: "Reporte", status: "completed")
        c
      end

      get challenge_path(challenge)

      expect(response.body).to include("flujo terminado")
      # Sin esta línea el caso no discrimina: la línea vieja decía «2 de 2 ·
      # flujo terminado», que ya cumple la afirmación de arriba y dejaría el
      # ejemplo en verde contra el código que vino a cambiar.
      expect(response.body).not_to include("2 de 2")
    end
  end

end
