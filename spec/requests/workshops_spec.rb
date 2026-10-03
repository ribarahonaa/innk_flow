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

  describe "el índice" do
    it "lista los talleres sin fecha DESPUÉS de los programados" do
      as_company(company) do
        workshop.update!(name: "Sin fecha")
        create(:workshop, name: "Programado cerca", scheduled_at: 1.day.from_now)
        create(:workshop, name: "Programado lejos", scheduled_at: 30.days.from_now)
      end
      sign_in(admin, company: company)
      get workshops_path

      names = response.body.scan(/Sin fecha|Programado cerca|Programado lejos/)
      expect(names.uniq).to eq(["Programado lejos", "Programado cerca", "Sin fecha"])
    end
  end

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

      as_company(company) { create(:challenge_step, challenge: propio, kind: "ideation", status: "active") }
      post open_workshop_path(created)
      expect(flash[:notice]).to include("Taller abierto")
      expect(as_company(company) { created.reload.status }).to eq("open")
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

  describe "el selector de salas" do
    let!(:ana) do
      without_tenant do
        u = create(:user, email: "ana-selector@test.dev")
        create(:membership, :participant, company: company, user: u)
        u
      end
    end

    def taller_con(kinds, brief: "De qué trata este desafío.")
      as_company(company) do
        workshop = create(:workshop, status: "open")
        group = create(:workshop_group, workshop: workshop)
        create(:workshop_group_member, workshop_group: group, user: ana)
        links = kinds.map do |kind|
          challenge = create(:challenge, brief: brief)
          step = create(:challenge_step, challenge: challenge, kind: kind, status: "active")
          create(:form_field, challenge_step: step, label: "Resumen", field_type: "text")
          create(:workshop_challenge, workshop: workshop, challenge: challenge, challenge_step: step)
        end
        { workshop: workshop, links: links }
      end
    end

    it "con dos salas lista cada desafío con su brief y no apila formularios" do
      escena = taller_con(%w[ideation ideation])
      sign_in(ana, company: company)
      get workshop_path(escena[:workshop])

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("De qué trata este desafío.")
      escena[:links].each do |link|
        expect(response.body).to include(workshop_sala_path(escena[:workshop], link))
      end
      # El formulario vive en la sala, no acá: era lo que hacía de la pantalla
      # del taller una pila de formularios sin contexto.
      expect(response.body).not_to include(%(name="payload[))
    end

    it "con un único vínculo, y trabajable, redirige a su sala" do
      escena = taller_con(%w[ideation])
      sign_in(ana, company: company)
      get workshop_path(escena[:workshop])

      expect(response).to redirect_to(workshop_sala_path(escena[:workshop], escena[:links].first))
    end

    # El escenario está en el seed: «Taller de mejora continua» lleva idear
    # activo y el desafío del manual, que se rechaza al abrir y queda cerrado
    # con su motivo. Con el redirect puesto sólo en «una sola sala trabajable»,
    # Paula caía en la sala de idear y el breadcrumb —que pregunta lo mismo,
    # para no hacer bucle— no le ofrecía volver: ningún camino al selector, así
    # que nunca se enteraba de que ese desafío estuvo en el taller ni de por qué
    # cerró. Es justo lo que el selector existe para no hacer.
    it "con un vínculo trabajable y otro cerrado sirve el selector, con el motivo del cerrado" do
      escena = taller_con(%w[ideation ideation])
      as_company(company) do
        escena[:links].last.update!(status: "closed", closed_at: Time.current,
                                    closed_reason: "El desafío está en Evaluación.")
      end
      sign_in(ana, company: company)
      get workshop_path(escena[:workshop])

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("El desafío está en Evaluación.")
      # Y la sala trabajable se sigue ofreciendo desde el selector.
      expect(response.body).to include(workshop_sala_path(escena[:workshop], escena[:links].first))
    end

    it "a quien administra no lo redirige: ahí está el bloque de armado" do
      escena = taller_con(%w[ideation])
      admin = without_tenant do
        u = create(:user, email: "admin-selector@test.dev")
        create(:membership, :admin, company: company, user: u)
        u
      end
      sign_in(admin, company: company)
      get workshop_path(escena[:workshop])

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Abrir taller").or include("Cerrar taller")
    end

    # A quien no tiene mesa el selector se le SIRVE igual.
    #
    # Lo que este ejemplo NO puede aislar: que con dos salas no se redirija.
    # Quien no tiene mesa y aun así ve el taller sólo puede ser quien
    # administra o un gestor, y para ellos `can_assemble` ya es true. La
    # discriminación de «con dos salas no redirige» la aporta el primer
    # ejemplo de este describe, con un participante CON mesa.
    it "con dos salas y sin mesa se sirve el selector" do
      escena = taller_con(%w[ideation evolution])
      sin_mesa = without_tenant do
        u = create(:user, email: "sin-mesa@test.dev")
        create(:membership, :admin, company: company, user: u)
        u
      end
      sign_in(sin_mesa, company: company)
      get workshop_path(escena[:workshop])

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(workshop_sala_path(escena[:workshop], escena[:links].first))
    end

    # El selector mostraba el brief de TODOS los desafíos del taller, y a un
    # gestor `work?` le abre el taller por administrar ALGUNO: el de los otros
    # es contenido de un desafío cuya ficha le da 404. El nombre sí: es lo que
    # dice qué salas hay.
    it "no muestra el brief del desafío que el gestor no alcanza, y sí el nombre" do
      escena = taller_con(%w[ideation ideation])
      gestor = member("gestor-selector@test.dev", :gestor)
      suyo, ajeno = as_company(company) do
        links = escena[:links]
        ChallengeGestor.create!(challenge: links.first.challenge, user: gestor)
        links.last.challenge.update!(brief: "El brief del desafío que no administra.")
        [links.first.challenge, links.last.challenge]
      end
      sign_in(gestor, company: company)
      get workshop_path(escena[:workshop])

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ajeno.name)
      expect(response.body).not_to include("El brief del desafío que no administra.")
      # Control positivo: el brief del suyo SÍ está, así que el ejemplo no pasa
      # por haberse quedado sin briefs.
      expect(response.body).to include(suyo.brief)
    end

    it "el vínculo no trabajable se lista con su motivo y sin «Entrar»" do
      escena = taller_con(%w[ideation])
      as_company(company) do
        escena[:links].first.update!(status: "closed", closed_at: Time.current,
                                     closed_reason: "El desafío está en Evaluación.")
      end
      sign_in(ana, company: company)
      get workshop_path(escena[:workshop])

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("El desafío está en Evaluación.")
      expect(response.body).not_to include(workshop_sala_path(escena[:workshop], escena[:links].first))
    end
  end
end
