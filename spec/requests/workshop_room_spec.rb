# frozen_string_literal: true

require "rails_helper"

# La sala como pantalla propia. Lo que se prueba acá es la PUERTA: quién
# entra, qué devuelve lo que no se ve, y que un vínculo no trabajable diga su
# motivo en vez de quedarse mudo o dar 404.
RSpec.describe "la sala del taller", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email, role = :participant)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, role, company: company, user: u)
      u
    end
  end

  let!(:ana) { member("ana@test.dev") }
  let!(:carla) { member("carla@test.dev") }
  let!(:admin) { member("admin@test.dev", :admin) }

  let!(:scene) do
    as_company(company) do
      challenge = create(:challenge, brief: "Bajar la merma de bodega sin tocar el stock de seguridad.")
      step = create(:challenge_step, challenge: challenge, kind: "ideation", status: "active")
      create(:form_field, challenge_step: step, label: "Resumen", field_type: "text")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge, challenge_step: step)
      group = create(:workshop_group, workshop: workshop)
      create(:workshop_group_member, workshop_group: group, user: ana)
      { challenge: challenge, step: step, workshop: workshop, link: link, group: group }
    end
  end

  it "quien está en la mesa entra y ve el nombre del desafío" do
    sign_in(ana, company: company)
    get workshop_sala_path(scene[:workshop], scene[:link])

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(scene[:challenge].name)
  end

  # `work?` da true por `administers_any?` sin mesa: entra y la sala se lo dice.
  it "quien administra entra sin estar sentado" do
    sign_in(admin, company: company)
    get workshop_sala_path(scene[:workshop], scene[:link])

    expect(response).to have_http_status(:ok)
  end

  it "quien no fue convocado no la ve: 404, no 403" do
    sign_in(carla, company: company)
    get workshop_sala_path(scene[:workshop], scene[:link])

    expect(response).to have_http_status(:not_found)
  end

  it "un vínculo de otro taller da 404 aunque el taller propio se vea" do
    otro_link = as_company(company) do
      otro = create(:workshop, status: "open")
      create(:workshop_challenge, workshop: otro, challenge: scene[:challenge])
    end
    sign_in(ana, company: company)
    get workshop_sala_path(scene[:workshop], otro_link)

    expect(response).to have_http_status(:not_found)
  end

  # Review Focus 3. `:unopened` es el vínculo de un taller que todavía no se
  # abrió: `challenge_step_id` es nulo a propósito. Es el estado que una vez
  # cayó en la rama equivocada y anunció «el desafío avanzó de fase», que es
  # falso, y antes de eso dejó la sala EN BLANCO.
  it "la sala de un taller en borrador dice que todavía no empezó, sin 404 ni pantalla vacía" do
    draft = as_company(company) do
      w = create(:workshop, status: "draft")
      g = create(:workshop_group, workshop: w)
      create(:workshop_group_member, workshop_group: g, user: ana)
      create(:workshop_challenge, workshop: w, challenge: scene[:challenge], challenge_step: nil)
    end
    sign_in(ana, company: company)
    get workshop_sala_path(draft.workshop, draft)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("todavía no se abrió")
    expect(response.body).not_to include(%(name="payload[))
  end

  it "la sala de un vínculo cerrado muestra su motivo y ningún formulario" do
    as_company(company) do
      scene[:link].update!(status: "closed", closed_at: Time.current,
                           closed_reason: "El desafío está en Evaluación.")
    end
    sign_in(ana, company: company)
    get workshop_sala_path(scene[:workshop], scene[:link])

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("El desafío está en Evaluación.")
    expect(response.body).not_to include(%(name="payload[))
  end

  # El cierre es PEREZOSO: nada se engancha en `advance!`. Entrar a la sala es
  # lo que hace que el taller se entere, así que materializar va ANTES de leer
  # el vínculo o la sala dibuja trabajo sobre un módulo ya cerrado.
  it "materializa el cierre al entrar, y lo dice" do
    as_company(company) do
      scene[:step].update!(status: "completed")
      create(:challenge_step, challenge: scene[:challenge], kind: "evolution", status: "active")
    end
    sign_in(ana, company: company)
    get workshop_sala_path(scene[:workshop], scene[:link])

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Evolución")
    as_company(company) { expect(scene[:link].reload).to be_closed }
  end

  # El breadcrumb pregunta lo mismo que el redirect. Si divergen, el taller
  # manda a la sala y la sala ofrece volver al taller: bucle.
  describe "el breadcrumb" do
    it "con una sola sala no ofrece volver al taller, que redirigiría de nuevo" do
      sign_in(ana, company: company)
      get workshop_sala_path(scene[:workshop], scene[:link])

      expect(response.body).not_to include(%(href="#{workshop_path(scene[:workshop])}"))
      expect(response.body).to include(%(href="#{workshops_path}"))
    end

    it "con dos salas sí ofrece volver al taller" do
      as_company(company) do
        otro = create(:challenge)
        paso = create(:challenge_step, challenge: otro, kind: "ideation", status: "active")
        create(:workshop_challenge, workshop: scene[:workshop], challenge: otro, challenge_step: paso)
      end
      sign_in(ana, company: company)
      get workshop_sala_path(scene[:workshop], scene[:link])

      expect(response.body).to include(%(href="#{workshop_path(scene[:workshop])}"))
    end
  end

  describe "la columna de referencia" do
    it "muestra el brief del desafío y la mesa, en ese orden" do
      as_company(company) { create(:workshop_group_member, workshop_group: scene[:group], user: admin) }
      sign_in(ana, company: company)
      get workshop_sala_path(scene[:workshop], scene[:link])

      expect(response.body).to include("Bajar la merma de bodega sin tocar el stock de seguridad.")
      expect(response.body).to include(admin.name)
      # El orden es el que ya fijaron las pantallas de módulo: lo propio del
      # módulo, y después quién participa. Invertirlo enseñaría dos órdenes
      # para la misma columna.
      expect(response.body.index("El desafío")).to be < response.body.index("Tu mesa")
    end

    it "marca a quien mira y a quien no vino" do
      as_company(company) do
        seat = create(:workshop_group_member, workshop_group: scene[:group], user: admin)
        seat.update!(attended: false)
      end
      sign_in(ana, company: company)
      get workshop_sala_path(scene[:workshop], scene[:link])

      expect(response.body).to include("(vos)")
      expect(response.body).to include("ausente")
    end

    # Marcar presente y sacar gente son de quien administra, y viven en el
    # bloque de armado. En la referencia la mesa se LEE.
    it "no ofrece controles de asistencia" do
      sign_in(ana, company: company)
      get workshop_sala_path(scene[:workshop], scene[:link])

      expect(response.body).not_to include(attendance_workshop_path(scene[:workshop]))
      expect(response.body).not_to include(dismiss_workshop_path(scene[:workshop]))
    end

    # En modo individual la mesa es de una persona y NO hay mesa de llegada
    # (`arrival_group!` devuelve nil). El panel lo dice en vez de desaparecer:
    # un panel que no está no se distingue de uno roto.
    it "en modo individual dice que la mesa es de una persona" do
      workshop, link = as_company(company) do
        w = create(:workshop, status: "open", mode: "individual")
        g = create(:workshop_group, workshop: w, name: "Mesa de Ana")
        create(:workshop_group_member, workshop_group: g, user: ana)
        [w, create(:workshop_challenge, workshop: w, challenge: scene[:challenge], challenge_step: scene[:step])]
      end
      sign_in(ana, company: company)
      get workshop_sala_path(workshop, link)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Trabajás sola o solo en este taller")
    end

    it "sin mesa la referencia lo dice y no finge una" do
      sign_in(admin, company: company)
      get workshop_sala_path(scene[:workshop], scene[:link])

      expect(response.body).to include("No estás en ninguna mesa de este taller")
    end
  end
end
