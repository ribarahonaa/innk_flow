# frozen_string_literal: true

require "rails_helper"

# El truco que hace barato todo lo demás: la visibilidad por mesa NO se
# programa. Crear el borrador con la mesa como idea_contributors hace que
# IdeaPolicy::Scope responda sola.
RSpec.describe "sala del taller: idear", type: :request do
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

  # Un solo armado para todos los ejemplos: taller abierto sobre un desafío en
  # idear, con una mesa de ana y beto. Carla queda afuera a propósito.
  let!(:setup) do
    as_company(company) do
      challenge = create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: "ideation", status: "active")
      field = create(:form_field, challenge_step: step, label: "Resumen", field_type: "text")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge, challenge_step: step)
      group = create(:workshop_group, workshop: workshop)
      [ ana, beto ].each { |u| create(:workshop_group_member, workshop_group: group, user: u) }
      { challenge: challenge, step: step, field: field, workshop: workshop, link: link }
    end
  end

  def post_draft(text = "Una idea")
    post workshop_sala_ideas_path(setup[:workshop], setup[:link]),
         params: { payload: { setup[:field].key => text } }
  end

  it "el borrador nace con el resto de la mesa como contribuyentes" do
    sign_in(ana, company: company)
    post_draft

    as_company(company) do
      idea = Idea.order(:created_at).last
      expect(idea.author_id).to eq(ana.id)
      expect(idea).to be_draft
      expect(idea.contributors.map(&:id)).to contain_exactly(beto.id)
      expect(idea.current_version.payload[setup[:field].key]).to eq("Una idea")
    end
  end

  # La regla NO es nueva: es `IdeaPolicy::Scope`. Este ejemplo prueba que
  # sembrar los contribuyentes en el momento de crear alcanza para que la
  # visibilidad por mesa funcione sin escribir una excepción.
  it "quien no está en la mesa no ve el borrador de esa mesa, y quien sí, sí" do
    sign_in(ana, company: company)
    post_draft
    idea = as_company(company) { Idea.order(:created_at).last }

    sign_in(beto, company: company)
    get challenge_idea_path(setup[:challenge], idea)
    expect(response).to have_http_status(:ok)

    sign_in(carla, company: company)
    get challenge_idea_path(setup[:challenge], idea)
    expect(response).to have_http_status(:not_found)
  end

  # `reject_room` tiene UN solo alert, así que el mensaje no dice por qué se
  # rechazó: una aserción sobre el texto sola no discrimina causas. Lo que sí
  # discrimina es cambiar UNA causa por ejemplo y comparar con la línea de base
  # (el ejemplo «quien participa y está en la mesa sigue creando»): con todo
  # igual y sólo esa causa cambiada, no se crea nada. Son tres causas de
  # `workable? && kind == "ideation"`; se cubre cada una.
  describe "no deja crear si la sala no es trabajable" do
    def rejected_room!
      expect { post_draft }.not_to(change { as_company(company) { Idea.count } })
      expect(response).to redirect_to(workshop_sala_path(setup[:workshop], setup[:link]))
      expect(flash[:alert]).to eq("Esta sala ya no admite trabajo: el desafío avanzó de fase.")
    end

    it "porque el módulo dejó de estar activo" do
      as_company(company) { setup[:step].update!(status: "completed") }
      sign_in(ana, company: company)

      rejected_room!
    end

    it "porque el vínculo ya se cerró" do
      as_company(company) { setup[:link].update!(status: "closed", closed_at: Time.current, closed_reason: "x") }
      sign_in(ana, company: company)

      rejected_room!
    end

    it "porque la sala es de evolución, no de idear" do
      as_company(company) do
        round = create(:challenge_step, challenge: setup[:challenge], kind: "evolution", status: "active")
        setup[:step].update!(status: "completed")
        setup[:link].update!(challenge_step: round)
      end
      sign_in(ana, company: company)

      rejected_room!
    end
  end

  it "quien no fue convocado al taller ni lo ve: 404, no 403" do
    sign_in(carla, company: company)

    expect { post_draft }.not_to(change { as_company(company) { Idea.count } })
    expect(response).to have_http_status(:not_found)
  end

  # El job se encola DESPUÉS de la transacción externa: adentro, un worker que
  # lo tome antes del commit no encuentra la versión y `EmbedVersion` devuelve
  # false en silencio, sin excepción ni reintento.
  it "encola el vector de la versión una sola vez, ya commiteada" do
    sign_in(ana, company: company)

    expect { post_draft }.to have_enqueued_job(Flow::Ideas::EmbedVersionJob).exactly(:once)

    version_id = as_company(company) { Idea.order(:created_at).last.current_version_id }
    expect(enqueued_jobs.last["arguments"].last).to eq(version_id)
  end

  it "si la versión no se puede publicar, no queda una idea vacía" do
    allow_any_instance_of(Flow::Ideas::PublishVersion).to receive(:call).and_return(
      Flow::Ideas::PublishVersion::Result.new(ok: false, version: nil, errors: [ "Título en blanco" ])
    )
    sign_in(ana, company: company)

    expect { post_draft }.not_to(change { as_company(company) { Idea.count } })
    expect(flash[:alert]).to include("Título en blanco")
    expect(enqueued_jobs).to be_empty
  end

  # Simétrico con la sala de evolución, que ya lo exigía. `work?` es del TALLER
  # y da true por `administers_any?` sin mesa: sin esta guarda, quien administra
  # creaba una idea a su nombre sin pasar nunca por `IdeaPolicy#create?`.
  it "quien administra y no está en ninguna mesa recibe un aviso, no una idea" do
    admin = without_tenant do
      u = create(:user, email: "admin@test.dev")
      create(:membership, :admin, company: company, user: u)
      u
    end
    sign_in(admin, company: company)

    expect { post_draft }.not_to(change { as_company(company) { Idea.count } })
    expect(response).to redirect_to(workshop_sala_path(setup[:workshop], setup[:link]))
    expect(flash[:alert]).to include("desde una mesa")
  end

  # El segundo agujero que cierra la misma guarda: `set_link` busca el vínculo
  # dentro del taller y nada más, así que un gestor entraba por el desafío que
  # SÍ administra y posteaba a la sala de uno ajeno —que por la ruta normal le
  # da 404—. Y de paso el gestor no postula ideas propias: es conflicto de
  # interés, no permisos.
  it "un gestor no crea en la sala de un desafío ajeno del mismo taller" do
    gestor = without_tenant do
      u = create(:user, email: "gestor@test.dev")
      create(:membership, :gestor, company: company, user: u)
      u
    end
    as_company(company) do
      propio = create(:challenge)
      create(:challenge_step, challenge: propio, kind: "ideation", status: "active")
      ChallengeGestor.create!(challenge: propio, user: gestor)
      create(:workshop_challenge, workshop: setup[:workshop], challenge: propio)
    end
    sign_in(gestor, company: company)

    # La sala a la que postea es la del desafío que NO administra.
    expect { post_draft }.not_to(change { as_company(company) { Idea.count } })
    expect(flash[:alert]).to include("desde una mesa")
  end

  # Un gestor puede sentarse en una mesa y acompañarla, pero no firmar una idea:
  # `IdeaPolicy#create?` es conflicto de interés. `work?` y la mesa no lo cubren.
  describe "un gestor convocado a la mesa" do
    let!(:gestor) do
      without_tenant do
        u = create(:user, email: "gestor-mesa@test.dev")
        create(:membership, :gestor, company: company, user: u)
        u
      end
    end

    before do
      as_company(company) do
        ChallengeGestor.create!(challenge: setup[:challenge], user: gestor)
        group = setup[:workshop].workshop_groups.first
        create(:workshop_group_member, workshop_group: group, user: gestor)
      end
    end

    it "no crea la idea: 403 por conflicto de interés" do
      sign_in(gestor, company: company)

      expect { post_draft }.not_to(change { as_company(company) { Idea.count } })
      expect(response).to have_http_status(:forbidden)
    end

    it "no recibe el formulario en la pantalla" do
      sign_in(gestor, company: company)
      get workshop_sala_path(setup[:workshop], setup[:link])

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(%(name="payload[#{setup[:field].key}]"))
      expect(response.body).not_to include("Crear borrador")
      # Y no queda una sala vacía sin explicación: el aviso ocupa su lugar.
      expect(response.body).to include("Podés acompañar a la mesa, pero no proponer ideas propias: es conflicto de interés.")
    end
  end

  # Anti-sobrecorrección: cerrar de más no rompe ningún otro ejemplo.
  it "quien participa y está en la mesa sigue creando y viendo el formulario" do
    sign_in(ana, company: company)
    get workshop_sala_path(setup[:workshop], setup[:link])
    expect(response.body).to include(%(name="payload[#{setup[:field].key}]"))
    expect(response.body).to include("Crear borrador")

    expect { post_draft }.to(change { as_company(company) { Idea.count } }.by(1))
    expect(response).to redirect_to(workshop_sala_path(setup[:workshop], setup[:link]))
  end

  describe "lo que ya creó la mesa" do
    def sala = get workshop_sala_path(setup[:workshop], setup[:link])

    it "lista el borrador que la mesa creó, con estado y versión" do
      sign_in(ana, company: company)
      post_draft("Idea de la mesa")
      # `ideas` NO tiene columna `title`: `Idea#title` sale de la versión
      # vigente y sin versión es «(sin título)» para TODAS. Se lee del registro
      # en vez de escribirlo a mano, así la aserción no depende de cómo se
      # derive.
      # El título se lee DENTRO del tenant: `title` consulta la versión.
      idea, title = as_company(company) { Idea.order(:created_at).last.then { |i| [ i, i.title ] } }

      sala
      expect(response.body).to include(title)
      expect(response.body).to include(challenge_idea_path(setup[:challenge], idea))
      expect(response.body).to include("Borrador")
    end

    # Lo ve cada integrante porque el borrador nace con la mesa entera como
    # `idea_contributors`: la visibilidad la resuelve `IdeaPolicy::Scope`, no
    # una excepción nueva.
    it "lo ve también el resto de la mesa" do
      sign_in(ana, company: company)
      post_draft("Idea compartida")
      idea, title = as_company(company) { Idea.order(:created_at).last.then { |i| [ i, i.title ] } }

      sign_in(beto, company: company)
      sala
      expect(response.body).to include(challenge_idea_path(setup[:challenge], idea))
      expect(response.body).to include(title)
    end

    # La razón por la que la consulta NO sale de `workable_ideas`: su comentario
    # documenta que exponer a toda la mesa el borrador que alguien creó AFUERA
    # fue una fuga ya arreglada. `policy_scope(Idea)` la hace imposible.
    it "no muestra el borrador que un compañero creó fuera del taller" do
      ajena = as_company(company) do
        idea = create(:idea, challenge: setup[:challenge], author: beto, status: "draft")
        # Con título propio: sin versión publicada toda idea se llama
        # «(sin título)», y una aserción sobre ese texto no distingue nada.
        result = Flow::Ideas::PublishVersion.new(
          idea, payload: {}, author: beto, title: "Borrador privado de Beto"
        ).call
        expect(result).to be_ok
        idea
      end
      sign_in(ana, company: company)
      sala

      expect(response.body).not_to include("Borrador privado de Beto")
      expect(response.body).not_to include(challenge_idea_path(setup[:challenge], ajena))
    end

    # Discrimina I1: para quien administra, `IdeaPolicy::Scope` devuelve `all`,
    # así que sin el filtro por integrantes este bloque lista las ideas de las
    # OTRAS mesas del taller bajo un título que dice que son de ésta.
    it "no lista el borrador de otra mesa, ni para quien administra" do
      admin = without_tenant do
        u = create(:user, email: "admin-mesas@test.dev")
        create(:membership, :admin, company: company, user: u)
        u
      end
      ajena = as_company(company) do
        tercera = without_tenant do
          u = create(:user, email: "tercera@test.dev")
          create(:membership, :participant, company: company, user: u)
          u
        end
        otra_mesa = create(:workshop_group, workshop: setup[:workshop], name: "Mesa 9")
        create(:workshop_group_member, workshop_group: otra_mesa, user: tercera)
        # Quien administra se sienta en la mesa de ana y beto: el bloque sólo se
        # dibuja desde una mesa.
        create(:workshop_group_member, workshop_group: setup[:workshop].workshop_groups.first, user: admin)
        idea = create(:idea, challenge: setup[:challenge], author: tercera, status: "draft")
        result = Flow::Ideas::PublishVersion.new(
          idea, payload: {}, author: tercera, title: "Borrador de la Mesa 9"
        ).call
        expect(result).to be_ok
        idea
      end
      sign_in(admin, company: company)
      sala

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Borrador de la Mesa 9")
      expect(response.body).not_to include(challenge_idea_path(setup[:challenge], ajena))
    end

    # El nombre de este ejemplo prometía «dice que no hay nada» y sólo miraba
    # el formulario: la cara de idear no dibujaba NADA cuando la mesa no tenía
    # ideas, así que la sección se fotografiaba ausente y daba verde —el mismo
    # agujero que la captura `25` pagó con la lista de participación—. La cara
    # de evolución sí tiene su `empty-state`.
    it "sin nada creado dice que no hay nada y ofrece el formulario igual" do
      sign_in(ana, company: company)
      sala

      vacio = Nokogiri::HTML(response.body).at_css(".card-body.empty-state")
      expect(vacio).not_to be_nil
      expect(vacio.text).to include("Ninguna idea en esta mesa todavía")
      expect(response.body).to include("Crear un borrador")
      expect(response.body).to include(%(name="payload[#{setup[:field].key}]"))
    end

    # El control POSITIVO del `empty-state` de arriba: con una idea creada la
    # sección es la LISTA y no el vacío. Sin este ejemplo se puede dibujar el
    # `empty-state` siempre y los dos pasan.
    it "con algo creado la sección es la lista y no el vacío" do
      sign_in(ana, company: company)
      post_draft("Lo que hizo la mesa")
      sala

      expect(Nokogiri::HTML(response.body).at_css(".card-body.empty-state")).to be_nil
      expect(response.body).to include("Las ideas de tu mesa")
    end

    it "con algo creado el formulario dice «Crear otro borrador»" do
      sign_in(ana, company: company)
      post_draft
      sala

      expect(response.body).to include("Crear otro borrador")
    end
  end

  it "crear el borrador vuelve a la sala, no al taller: ahí se ve lo que se creó" do
    sign_in(ana, company: company)
    post_draft

    expect(response).to redirect_to(workshop_sala_path(setup[:workshop], setup[:link]))
  end


  describe "la sala" do
    it "ofrece a quien está en la mesa el formulario del módulo, diciendo con quién se comparte" do
      sign_in(ana, company: company)
      get workshop_sala_path(setup[:workshop], setup[:link])

      # El submit va en `.form-actions`, igual que en `ideas/new`.
      expect(response.body).to match(/class="form-actions">\s*<input[^>]*value="Crear borrador"/)

      expect(response.body).to include(%(name="payload[#{setup[:field].key}]"))
      expect(response.body).to include("Resumen")
      expect(response.body).to include(beto.name)
    end

    # El cierre del vínculo es PEREZOSO: nada se engancha en `advance!`. Hasta
    # que alguien entra a la sala, el vínculo sigue `open` con su módulo ya
    # terminado — que es el estado en que queda TODO vínculo tras un avance—.
    # Sin materializarlo, la sala no entraba en ninguna rama y salía EN BLANCO.
    it "materializa el cierre cuando el desafío avanzó, y dice a qué avanzó" do
      as_company(company) do
        setup[:step].update!(status: "completed")
        create(:challenge_step, challenge: setup[:challenge], kind: "evolution", status: "active")
      end
      sign_in(ana, company: company)
      get workshop_sala_path(setup[:workshop], setup[:link])

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Evolución")

      as_company(company) do
        link = setup[:link].reload
        expect(link).to be_closed
        expect(link.closed_at).to be_present
        expect(link.closed_reason).to include("Evolución")
      end
    end

    it "muestra la sala cerrada con su motivo en vez de hacerla desaparecer" do
      as_company(company) do
        setup[:link].update!(status: "closed", closed_reason: "El desafío avanzó de fase.", closed_at: Time.current)
      end
      sign_in(ana, company: company)
      get workshop_sala_path(setup[:workshop], setup[:link])

      expect(response.body).to include("El desafío avanzó de fase.")
      expect(response.body).not_to include(%(name="payload[))
    end
  end
end
