# frozen_string_literal: true

require "rails_helper"

# El autoguardado de la mesa. Lo dispara un temporizador y no una persona, así
# que responde con códigos pelados: un `redirect_to` haría que el `fetch` siga
# la redirección y traiga la pantalla entera cada dos segundos.
RSpec.describe "sala del taller: el borrador de la mesa", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, :participant, company: company, user: u)
      u
    end
  end

  let!(:ana) { member("ana@test.dev") }
  let!(:beto) { member("beto@test.dev") }
  let!(:carla) { member("carla@test.dev") }

  # Una sala de IDEAR con ana y beto sentados. Carla queda afuera a propósito.
  let!(:idear) do
    as_company(company) do
      challenge = create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: "ideation", status: "active")
      field = create(:form_field, challenge_step: step, label: "Resumen", field_type: "text")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge, challenge_step: step)
      group = create(:workshop_group, workshop: workshop)
      [ ana, beto ].each { |u| create(:workshop_group_member, workshop_group: group, user: u) }
      { workshop: workshop, link: link, group: group, field: field, challenge: challenge }
    end
  end

  def patch_draft(setup, params)
    patch workshop_sala_draft_path(setup[:workshop], setup[:link]), params: params
  end

  def drafts
    as_company(company) { WorkshopDraft.all.to_a }
  end

  describe "las cuatro guardas, en el mismo orden que los otros dos POST de la sala" do
    it "sin sesión no entra" do
      patch_draft(idear, payload: { idear[:field].key => "x" })
      expect(response).to have_http_status(:found)
      # El `fetch` del autoguardado SIGUE ese 302 y lo lee como 200: por eso el JS
      # exige 204 y no `res.ok`. Este ejemplo fija la premisa: el rechazo no es 204
      # y no escribe nada.
      expect(response).not_to have_http_status(:no_content)
      expect(drafts).to be_empty
    end

    # Un taller es por convocatoria: a quien participa y no está sentado el scope
    # del taller ni se lo muestra, así que es 404 y no 403.
    it "quien participa y no está en ninguna mesa del taller: 404" do
      sign_in(carla, company: company)
      patch_draft(idear, payload: { idear[:field].key => "x" })
      expect(response).to have_http_status(:not_found)
      expect(drafts).to be_empty
    end

    # El 403 de «sin mesa» es alcanzable por quien SÍ ve el taller y `work?` le
    # da true sin estar sentado: quien administra la empresa.
    it "quien administra y no está sentado en ninguna mesa: 403" do
      admin = without_tenant do
        u = create(:user, email: "admin@test.dev")
        create(:membership, :admin, company: company, user: u)
        u
      end
      sign_in(admin, company: company)
      patch_draft(idear, payload: { idear[:field].key => "x" })
      expect(response).to have_http_status(:forbidden)
      expect(drafts).to be_empty
    end

    it "desde la mesa de llegada: 403" do
      as_company(company) do
        idear[:group].workshop_group_members.destroy_all
        llegada = create(:workshop_group, workshop: idear[:workshop], arrival: true)
        create(:workshop_group_member, workshop_group: llegada, user: ana)
      end
      sign_in(ana, company: company)
      patch_draft(idear, payload: { idear[:field].key => "x" })
      expect(response).to have_http_status(:forbidden)
      expect(drafts).to be_empty
    end

    it "una sala que ya no admite trabajo: 409" do
      as_company(company) do
        idear[:link].challenge_step.update!(status: "completed")
      end
      sign_in(ana, company: company)
      patch_draft(idear, payload: { idear[:field].key => "x" })
      expect(response).to have_http_status(:conflict)
      expect(drafts).to be_empty
    end
  end

  describe "el camino feliz" do
    it "escribe el borrador y responde 204" do
      sign_in(ana, company: company)
      patch_draft(idear, payload: { idear[:field].key => "a medio escribir" })

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_empty
      # La cabecera es lo único que distingue «guardé» de «no había nada que
      # guardar»: si se filtrara al camino real, el sello dejaría de acusar los
      # guardados buenos.
      expect(response.headers["X-Draft-Saved"]).to be_nil
      draft = drafts.sole
      expect(draft.payload).to eq(idear[:field].key => "a medio escribir")
      expect(draft.idea_id).to be_nil
      expect(draft.updated_by_id).to eq(ana.id)
    end

    # Prueba que queda UNA fila y gana la última escritura. Los índices parciales
    # que garantizan la unicidad ante la carrera se prueban en
    # `spec/models/workshop_draft_spec.rb`: acá los PATCH son secuenciales y el
    # `find_or_initialize_by` encuentra la fila sin pasar por ellos.
    it "dos personas de la misma mesa dejan UNA fila, y gana la última" do
      sign_in(ana, company: company)
      patch_draft(idear, payload: { idear[:field].key => "lo de ana" })
      sign_in(beto, company: company)
      patch_draft(idear, payload: { idear[:field].key => "lo de beto" })

      draft = drafts.sole
      expect(draft.payload[idear[:field].key]).to eq("lo de beto")
      expect(draft.updated_by_id).to eq(beto.id)
    end

    it "una clave que no es de un campo se descarta" do
      sign_in(ana, company: company)
      patch_draft(idear, payload: { idear[:field].key => "ok", "inventada" => "no" })
      expect(drafts.sole.payload.keys).to contain_exactly(idear[:field].key)
    end
  end

  # ── Review Focus ─────────────────────────────────────────────────────────
  #
  # Cuatro cosas que ningún test obvio ejercita y que son pérdida de datos o
  # cambio de código de estado si alguien las toca.

  # Lo peor que podía hacer este endpoint: `params.fetch(:payload, {})` devuelve
  # `{}` y pisa el texto de la mesa con nada. Un cuerpo mal armado del JS lo
  # causaría sin que nadie se enterara.
  it "un PATCH sin `payload` es un no-op: no pisa el borrador con nada" do
    sign_in(ana, company: company)
    patch_draft(idear, payload: { idear[:field].key => "lo que la mesa escribió" })
    patch_draft(idear, {})

    expect(response).to have_http_status(:no_content)
    expect(response.headers["X-Draft-Saved"]).to eq("0")
    expect(drafts.sole.payload[idear[:field].key]).to eq("lo que la mesa escribió")
  end

  # La fase la decide la SALA y no el cliente. Si el servidor aceptara el
  # `idea_id`, un cliente crearía una fila con idea en una sala de idear, que
  # escapa al índice de unicidad pensado para esa cara.
  it "un `idea_id` mandado a una sala de idear se ignora" do
    idea = as_company(company) { create(:idea, challenge: idear[:challenge], author: ana) }
    sign_in(ana, company: company)
    patch_draft(idear, payload: { idear[:field].key => "x" }, idea_id: idea.id)

    expect(response).to have_http_status(:no_content)
    expect(drafts.sole.idea_id).to be_nil
  end


  it "un payload con TODAS las claves inventadas no toca el borrador existente" do
    sign_in(ana, company: company)
    patch_draft(idear, payload: { idear[:field].key => "lo que la mesa escribió" })
    patch_draft(idear, payload: { "inventada" => "x" })

    expect(response).to have_http_status(:no_content)
    expect(response.headers["X-Draft-Saved"]).to eq("0")
    expect(drafts.sole.payload).to eq(idear[:field].key => "lo que la mesa escribió")
  end

  it "vaciar un campo a propósito sí se guarda" do
    sign_in(ana, company: company)
    patch_draft(idear, payload: { idear[:field].key => "algo" })
    patch_draft(idear, payload: { idear[:field].key => "" })
    expect(drafts.sole.payload).to eq(idear[:field].key => "")
  end

  it "un payload escalar es un 400 y no un 500" do
    sign_in(ana, company: company)
    patch_draft(idear, payload: "x")
    expect(response).to have_http_status(:bad_request)
    expect(drafts).to be_empty
  end

  it "los campos de tipo file no se guardan" do
    archivo = as_company(company) do
      create(:form_field, challenge_step: idear[:link].challenge_step, label: "Adjunto",
                          field_type: "file")
    end
    sign_in(ana, company: company)
    patch_draft(idear, payload: { idear[:field].key => "ok", archivo.key => "x.pdf" })
    expect(drafts.sole.payload.keys).to contain_exactly(idear[:field].key)
  end

  it "una sala de OTRO taller es 404" do
    otra = as_company(company) do
      ch = create(:challenge)
      st = create(:challenge_step, challenge: ch, kind: "ideation", status: "active")
      w = create(:workshop, status: "open")
      l = create(:workshop_challenge, workshop: w, challenge: ch, challenge_step: st)
      g = create(:workshop_group, workshop: w)
      create(:workshop_group_member, workshop_group: g, user: ana)
      l
    end
    sign_in(ana, company: company)
    patch workshop_sala_draft_path(idear[:workshop], otra), params: { payload: { "x" => "y" } }
    expect(response).to have_http_status(:not_found)
    expect(drafts).to be_empty
  end

  context "en una sala de evolución" do
    let!(:evolucion) do
      as_company(company) do
        challenge = create(:challenge)
        ideation = create(:challenge_step, challenge: challenge, kind: "ideation", status: "completed")
        field = create(:form_field, challenge_step: ideation, label: "Resumen", field_type: "text")
        step = create(:challenge_step, challenge: challenge, kind: "evolution", status: "active")
        workshop = create(:workshop, status: "open")
        link = create(:workshop_challenge, workshop: workshop, challenge: challenge, challenge_step: step)
        group = create(:workshop_group, workshop: workshop)
        create(:workshop_group_member, workshop_group: group, user: ana)
        # `workable_ideas` es `Idea.alive`, o sea `status: "active"`.
        idea = create(:idea, challenge: challenge, author: ana, status: "active")
        version = Flow::Ideas::PublishVersion.new(
          idea, payload: { field.key => "La mía" }, author: ana
        ).call.version
        { workshop: workshop, link: link, field: field, idea: idea, version: version,
          challenge: challenge }
      end
    end

    it "escribe el borrador con la idea y la versión vigente" do
      sign_in(ana, company: company)
      patch_draft(evolucion, payload: { evolucion[:field].key => "mejor así" },
                             idea_id: evolucion[:idea].id)

      draft = drafts.sole
      expect(draft.idea_id).to eq(evolucion[:idea].id)
      # Este `PATCH` va SIN `base_version_id` a propósito —un cliente viejo, un
      # PATCH a mano—, y ése es el camino de fallback: el servidor lee
      # `idea.current_version_id`.
      #
      # Ojo, que este comentario decía lo contrario: que el sello «lo escribe el
      # SERVIDOR, nunca el cliente». Desde la revisión final lo manda el cliente
      # (`base_version_id`, contra la que la vista prellenó el formulario) y el
      # servidor lo busca en `idea.versions`. El motivo de ese cambio y lo que
      # acota la mentira están en el bullet del sello en `CLAUDE.md`; los
      # ejemplos del camino del cliente son los tres de más abajo.
      expect(draft.based_on_version_id).to eq(evolucion[:version].id)
    end

    it "sin `idea_id`: 404, no 403 ni 500" do
      sign_in(ana, company: company)
      patch_draft(evolucion, payload: { evolucion[:field].key => "x" })
      expect(response).to have_http_status(:not_found)
      expect(drafts).to be_empty
    end

    # Una idea que no es de nadie de la mesa no se distingue de una inexistente:
    # el 404 es lo que impide que el código de estado confirme que existe.
    it "con una idea ajena al conjunto trabajable: 404" do
      ajena = as_company(company) do
        create(:idea, challenge: evolucion[:challenge], author: carla, status: "active")
      end
      sign_in(ana, company: company)
      patch_draft(evolucion, payload: { evolucion[:field].key => "x" }, idea_id: ajena.id)
      expect(response).to have_http_status(:not_found)
      expect(drafts).to be_empty
    end

    # Discrimina `workable_ideas` de `policy_scope(Idea)`: ana es participant y
    # con ese scope no vería la idea de beto, que sí es de su mesa.
    it "una idea de otro integrante de la mesa se puede trabajar: 204" do
      group = as_company(company) { evolucion[:workshop].group_of(ana) }
      de_beto = as_company(company) do
        create(:workshop_group_member, workshop_group: group, user: beto)
        create(:idea, challenge: evolucion[:challenge], author: beto, status: "active")
      end
      sign_in(ana, company: company)
      patch_draft(evolucion, payload: { evolucion[:field].key => "x" }, idea_id: de_beto.id)
      expect(response).to have_http_status(:no_content)
      expect(drafts.sole.idea_id).to eq(de_beto.id)
    end

    # El sello es contra qué versión se tecleó: se escribe al crear la fila y los
    # autoguardados siguientes no lo mueven, o el aviso de base vieja no dispara.
    it "el sello de la versión no se reescribe en el autoguardado siguiente" do
      sign_in(ana, company: company)
      patch_draft(evolucion, payload: { evolucion[:field].key => "uno" },
                             idea_id: evolucion[:idea].id)
      as_company(company) do
        Flow::Ideas::PublishVersion.new(
          evolucion[:idea], payload: { evolucion[:field].key => "v2" }, author: ana
        ).call
      end
      patch_draft(evolucion, payload: { evolucion[:field].key => "dos" },
                             idea_id: evolucion[:idea].id)

      draft = drafts.sole
      expect(draft.payload[evolucion[:field].key]).to eq("dos")
      expect(draft.based_on_version_id).to eq(evolucion[:version].id)
    end

    # El formulario se prellena al RENDERIZAR y la mesa puede tardar en teclear: el
    # sello es contra la versión del render, no la de la base al primer PATCH.
    it "el sello usa la versión con la que se prellenó, aunque la idea avanzara antes del primer PATCH" do
      sign_in(ana, company: company)
      get workshop_sala_path(evolucion[:workshop], evolucion[:link], idea: evolucion[:idea].id)
      expect(response.body).to include(%(data-draft-base="#{evolucion[:version].id}"))
      as_company(company) do
        Flow::Ideas::PublishVersion.new(
          evolucion[:idea], payload: { evolucion[:field].key => "v2" }, author: ana
        ).call
      end

      patch_draft(evolucion, payload: { evolucion[:field].key => "uno" },
                             idea_id: evolucion[:idea].id,
                             base_version_id: evolucion[:version].id)
      expect(drafts.sole.based_on_version_id).to eq(evolucion[:version].id)

      get workshop_sala_path(evolucion[:workshop], evolucion[:link], idea: evolucion[:idea].id)
      expect(response.body).to include("la versión vigente ya es v2")
    end

    it "una versión inexistente cae a la vigente, sin reventar" do
      sign_in(ana, company: company)
      patch_draft(evolucion, payload: { evolucion[:field].key => "x" },
                             idea_id: evolucion[:idea].id, base_version_id: 999_999_999)
      expect(response).to have_http_status(:no_content)
      expect(drafts.sole.based_on_version_id).to eq(evolucion[:version].id)
    end

    # EL ejemplo que distingue el arreglo, y el único.
    #
    # El de arriba no lo hace y no podría: manda una versión que no existe, así
    # que el código nuevo cae a `current_version_id` y el viejo leía
    # `current_version_id` directo — los dos escriben el mismo id y los dos dan
    # verde. Ninguna aserción sobre el FALLBACK puede discriminar, porque el
    # fallback ES el comportamiento viejo.
    #
    # Éste manda una versión REAL de la misma empresa que pertenece a OTRA idea.
    # Separa las dos implementaciones plausibles:
    #
    #   `idea.versions.find_by(id:)`  →  no la encuentra (el scope filtra por
    #                                    `idea_id`), cae a la vigente, 204.
    #   `IdeaVersion.find_by(id:)`    →  SÍ la encuentra (misma empresa), la
    #                                    escribe, y `version_belongs_to_idea`
    #                                    levanta en el `update!`: 500.
    #
    # O sea que esto es también lo único que prueba que la validación del modelo
    # no es la que está atajando el caso: en el camino real no se ejecuta nunca,
    # porque el scope ya excluyó la versión ajena.
    it "una versión de otra idea de la misma empresa cae a la vigente y no revienta" do
      ajena = as_company(company) do
        otra = create(:idea, challenge: evolucion[:challenge], author: beto, status: "active")
        Flow::Ideas::PublishVersion.new(
          otra, payload: { evolucion[:field].key => "la de beto" }, author: beto
        ).call.version
      end

      sign_in(ana, company: company)
      patch_draft(evolucion, payload: { evolucion[:field].key => "x" },
                             idea_id: evolucion[:idea].id, base_version_id: ajena.id)

      expect(response).to have_http_status(:no_content)
      expect(drafts.sole.based_on_version_id).to eq(evolucion[:version].id)
    end

    # No se agrega tope: `WorkshopProposal.payload` ya acepta el mismo contenido
    # del mismo formulario, así que un tope acá rechazaría un borrador cuya
    # propuesta sí entraría. Este ejemplo existe para que nadie meta un truncado
    # silencioso después.
    it "un payload largo viaja entero, sin truncar" do
      largo = "a" * 50_000
      sign_in(ana, company: company)
      patch_draft(evolucion, payload: { evolucion[:field].key => largo },
                             idea_id: evolucion[:idea].id)
      expect(drafts.sole.payload[evolucion[:field].key].length).to eq(50_000)
    end
  end
end
