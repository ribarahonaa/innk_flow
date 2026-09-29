# frozen_string_literal: true

require "rails_helper"

# Lo que no se ve da 404, NUNCA 403: un 403 confirma que existe.
RSpec.describe "talleres", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email, role)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, role.to_sym, company: company, user: u)
      u
    end
  end

  let!(:admin) { member("admin@test.dev", :admin) }
  let!(:paula) { member("paula@test.dev", :participant) }
  let!(:workshop) { as_company(company) { create(:workshop) } }

  # El spec §6 promete «crear» al gestor. Se abre por AUTORÍA: administra el
  # que él creó, y ninguno ajeno.
  describe "un gestor crea talleres" do
    let!(:gestor) { member("gestor-crea@test.dev", :gestor) }
    let!(:propio) { as_company(company) { create(:challenge).tap { |c| ChallengeGestor.create!(challenge: c, user: gestor) } } }
    let!(:ajeno) { as_company(company) { create(:challenge) } }

    it "lo crea, lo abre y suma sus desafíos, no los ajenos" do
      sign_in(gestor, company: company)
      post workshops_path, params: { workshop: { name: "Mío", mode: "group" } }
      created = as_company(company) { Workshop.find_by!(name: "Mío") }

      expect(response).to redirect_to(workshop_path(created))
      follow_redirect!
      expect(response).to have_http_status(:ok)

      patch workshop_path(created), params: { challenge_ids: [propio.id, ajeno.id] }
      expect(as_company(company) { created.workshop_challenges.pluck(:challenge_id) }).to eq([propio.id])
      expect(flash[:notice]).to include("no lo administrás")
    end

    it "no administra el taller que creó otra persona: 404 y ningún cambio" do
      other = as_company(company) { create(:workshop, name: "De otro", created_by: admin) }
      sign_in(gestor, company: company)

      get workshop_path(other)
      expect(response).to have_http_status(:not_found)
      patch workshop_path(other), params: { challenge_ids: [propio.id] }
      expect(response).to have_http_status(:not_found)
      expect(as_company(company) { other.workshop_challenges.count }).to eq(0)
    end

    it "quien participa sigue sin poder crear" do
      sign_in(paula, company: company)
      expect { post workshops_path, params: { workshop: { name: "Nope", mode: "group" } } }
        .not_to(change { as_company(company) { Workshop.count } })
      expect(response).to have_http_status(:forbidden)
    end
  end

  it "a quien no está convocado le da 404, no 403" do
    sign_in(paula, company: company)
    get workshop_path(workshop)
    expect(response).to have_http_status(:not_found)
  end

  it "quien administra lo abre" do
    sign_in(admin, company: company)
    get workshop_path(workshop)
    expect(response).to have_http_status(:ok)
  end

  # El ciclo de vida pone «sumar y sacar desafíos» en `draft` y en ningún otro
  # estado. No había ni un request spec de `workshops#update`.
  describe "sumar y sacar desafíos" do
    let!(:uno) { as_company(company) { create(:challenge) } }
    let!(:otro) { as_company(company) { create(:challenge) } }

    def link_count = as_company(company) { workshop.workshop_challenges.count }

    it "quien administra la empresa suma los que tilde" do
      sign_in(admin, company: company)
      patch workshop_path(workshop), params: { challenge_ids: [uno.id, otro.id] }

      expect(link_count).to eq(2)
      expect(flash[:notice]).to eq("Taller actualizado.")
    end

    # El gestor recibía un acuse de éxito por un desafío que no se sumó: el
    # `next` en silencio y «Taller actualizado.» igual.
    it "cuenta y avisa los que quedaron afuera por no administrarlos" do
      gestor = member("gestor@test.dev", :gestor)
      as_company(company) do
        ChallengeGestor.create!(challenge: uno, user: gestor)
        # El taller ya toca un desafío suyo: sin eso ni siquiera lo ve.
        create(:workshop_challenge, workshop: workshop, challenge: uno)
      end
      sign_in(gestor, company: company)
      patch workshop_path(workshop), params: { challenge_ids: [otro.id] }

      expect(link_count).to eq(1)
      expect(flash[:notice]).to include("1 desafío no se sumó: no lo administrás.")
    end

    it "en plural concuerda la frase entera, no sólo el sustantivo" do
      gestor = member("gestor2@test.dev", :gestor)
      tercero = as_company(company) { create(:challenge) }
      as_company(company) do
        ChallengeGestor.create!(challenge: uno, user: gestor)
        create(:workshop_challenge, workshop: workshop, challenge: uno)
      end
      sign_in(gestor, company: company)
      patch workshop_path(workshop), params: { challenge_ids: [otro.id, tercero.id] }

      expect(flash[:notice]).to include("2 desafíos no se sumaron: no los administrás.")
    end

    it "con el taller abierto no suma: el vínculo nacería sin módulo" do
      as_company(company) { workshop.update!(status: "open") }
      sign_in(admin, company: company)

      expect { patch workshop_path(workshop), params: { challenge_ids: [uno.id] } }
        .not_to(change { link_count })
      expect(flash[:alert]).to include("borrador")
    end

    it "saca un desafío del taller en borrador" do
      link = as_company(company) { create(:workshop_challenge, workshop: workshop, challenge: uno) }
      sign_in(admin, company: company)
      delete remove_challenge_workshop_path(workshop), params: { workshop_challenge_id: link.id }

      expect(link_count).to eq(0)
      expect(flash[:notice]).to include("sacado")
    end

    it "con el taller abierto no saca" do
      link = as_company(company) { create(:workshop_challenge, workshop: workshop, challenge: uno) }
      as_company(company) { workshop.update!(status: "open") }
      sign_in(admin, company: company)

      expect { delete remove_challenge_workshop_path(workshop), params: { workshop_challenge_id: link.id } }
        .not_to(change { link_count })
      expect(flash[:alert]).to include("borrador")
    end

    # La contracara de la guarda `open?` de `MaterializeClosures`: el mismo
    # estado, del lado de la LECTURA. Un vínculo de borrador tiene
    # `challenge_step_id` nulo a propósito, y anunciarlo como «el desafío
    # avanzó de fase» es falso: el desafío no avanzó, el taller no se abrió.
    it "un taller en borrador no dibuja salas ni dice que el desafío avanzó" do
      as_company(company) { create(:workshop_challenge, workshop: workshop, challenge: uno) }
      sign_in(admin, company: company)
      get workshop_path(workshop)

      expect(response).to have_http_status(:ok)
      # El armado sí está: la pantalla se renderizó entera.
      expect(response.body).to include("Sumar al taller")
      # Y ninguna sala: el título de una sala es el nombre del desafío como
      # `h2.section-title`; en el armado los desafíos son links, no encabezados.
      expect(response.body).not_to include(%(<h2 class="section-title">#{uno.name}</h2>))
      expect(response.body).not_to include("Esta sala ya no admite trabajo")
    end

    it "ofrece el control de sacar sólo mientras es borrador" do
      link = as_company(company) { create(:workshop_challenge, workshop: workshop, challenge: uno) }
      sign_in(admin, company: company)

      get workshop_path(workshop)
      expect(response.body).to include(remove_challenge_workshop_path(workshop))
      # Entrar al armado de un borrador NO cierra sus vínculos: el
      # `challenge_step_id` nulo es el estado correcto hasta que se abre.
      expect(as_company(company) { link.reload }).to be_open

      as_company(company) { workshop.update!(status: "open") }
      get workshop_path(workshop)
      expect(response.body).not_to include(remove_challenge_workshop_path(workshop))
    end
  end

  # `Flow::Texto.contar` acuerda el sustantivo y la frase trae su propio verbo:
  # «1 desafío quedaron afuera» es literalmente el bug que `Flow::Texto`
  # documenta para que no vuelva a pasar.
  describe "abrir" do
    it "dice en singular cuando quedó UN desafío afuera" do
      as_company(company) do
        adentro = create(:challenge)
        create(:challenge_step, challenge: adentro, kind: "ideation", status: "active")
        afuera = create(:challenge)
        create(:challenge_step, challenge: afuera, kind: "evaluation", status: "active")
        create(:workshop_challenge, workshop: workshop, challenge: adentro)
        create(:workshop_challenge, workshop: workshop, challenge: afuera)
      end
      sign_in(admin, company: company)
      post open_workshop_path(workshop)

      expect(flash[:notice]).to eq("Taller abierto. 1 desafío quedó afuera.")
    end

    it "sin nadie afuera no agrega la frase" do
      as_company(company) do
        adentro = create(:challenge)
        create(:challenge_step, challenge: adentro, kind: "ideation", status: "active")
        create(:workshop_challenge, workshop: workshop, challenge: adentro)
      end
      sign_in(admin, company: company)
      post open_workshop_path(workshop)

      expect(flash[:notice]).to eq("Taller abierto.")
    end
  end

  # Un estado terminal sin guarda no es una decisión de producto: `Open` exige
  # `draft?`, así que un taller saltado a `closed` no se podía reabrir NUNCA.
  describe "cerrar" do
    it "un borrador no se cierra: se elimina" do
      sign_in(admin, company: company)

      expect { post close_workshop_path(workshop) }
        .not_to(change { as_company(company) { workshop.reload.status } })
      expect(flash[:alert]).to include("todavía no se abrió")
    end

    it "uno ya cerrado lo dice en vez de cerrarlo de nuevo" do
      as_company(company) { workshop.update!(status: "closed") }
      sign_in(admin, company: company)
      post close_workshop_path(workshop)

      expect(flash[:alert]).to include("ya está cerrado")
    end
  end

  # Borrar una mesa cascadea sus propuestas, aceptadas incluidas, y con ellas
  # la procedencia de versiones ya publicadas. Con el taller ABIERTO las mesas
  # se siguen tocando a propósito: llegó alguien tarde a la sesión.
  describe "mesas y convocatoria con el taller cerrado" do
    let!(:group) { as_company(company) { create(:workshop_group, workshop: workshop) } }

    before { as_company(company) { workshop.update!(status: "closed") } }

    def group_count = as_company(company) { workshop.workshop_groups.count }

    it "no crea mesas" do
      sign_in(admin, company: company)

      expect { post workshop_workshop_groups_path(workshop), params: { name: "Mesa X" } }
        .not_to(change { group_count })
      expect(flash[:alert]).to include("ya cerró")
    end

    it "no borra mesas" do
      sign_in(admin, company: company)

      expect { delete workshop_workshop_group_path(workshop, group) }.not_to(change { group_count })
      expect(flash[:alert]).to include("ya cerró")
    end

    it "no convoca ni desconvoca" do
      sign_in(admin, company: company)

      expect { post convoke_workshop_path(workshop), params: { user_id: paula.id, workshop_group_id: group.id } }
        .not_to(change { as_company(company) { WorkshopGroupMember.count } })
      expect(flash[:alert]).to include("ya cerró")

      delete dismiss_workshop_path(workshop), params: { user_id: paula.id }
      expect(flash[:alert]).to include("ya cerró")
    end

    it "no ofrece los controles de mesa" do
      sign_in(admin, company: company)
      get workshop_path(workshop)

      expect(response.body).not_to include("Eliminar mesa")
      expect(response.body).not_to include("Crear mesa")
    end

    it "con el taller ABIERTO las mesas se siguen tocando" do
      as_company(company) { workshop.update!(status: "open") }
      sign_in(admin, company: company)

      expect { post workshop_workshop_groups_path(workshop), params: { name: "Mesa X" } }
        .to(change { group_count }.by(1))
    end
  end
end
