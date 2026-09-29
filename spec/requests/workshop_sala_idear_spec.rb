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

  it "no deja crear si el vínculo dejó de ser trabajable" do
    as_company(company) { setup[:step].update!(status: "completed") }
    sign_in(ana, company: company)

    expect { post_draft }.not_to(change { as_company(company) { Idea.count } })
    expect(flash[:alert]).to include("avanzó de fase")
  end

  it "quien no fue convocado al taller ni lo ve: 404, no 403" do
    sign_in(carla, company: company)

    expect { post_draft }.not_to(change { as_company(company) { Idea.count } })
    expect(response).to have_http_status(:not_found)
  end

  it "si la versión no se puede publicar, no queda una idea vacía" do
    allow_any_instance_of(Flow::Ideas::PublishVersion).to receive(:call).and_return(
      Flow::Ideas::PublishVersion::Result.new(ok: false, version: nil, errors: [ "Título en blanco" ])
    )
    sign_in(ana, company: company)

    expect { post_draft }.not_to(change { as_company(company) { Idea.count } })
    expect(flash[:alert]).to include("Título en blanco")
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
    expect(response).to redirect_to(workshop_path(setup[:workshop]))
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

  describe "la pantalla del taller" do
    it "ofrece a quien está en la mesa el formulario del módulo, diciendo con quién se comparte" do
      sign_in(ana, company: company)
      get workshop_path(setup[:workshop])

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
      get workshop_path(setup[:workshop])

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Evolución")

      as_company(company) do
        link = setup[:link].reload
        expect(link).to be_closed
        expect(link.closed_at).to be_present
        expect(link.closed_reason).to include("Evolución")
      end
    end

    # Un taller con dos desafíos en idear es el caso más natural, y sin prefijo
    # las dos salas emiten el mismo `id="payload_<clave>"`: el `<label for>` de
    # la segunda enfoca el campo de la primera.
    it "con dos salas de idear no repite ids de DOM" do
      as_company(company) do
        otro = create(:challenge)
        paso = create(:challenge_step, challenge: otro, kind: "ideation", status: "active")
        create(:form_field, challenge_step: paso, label: "Resumen", field_type: "text")
        create(:workshop_challenge, workshop: setup[:workshop], challenge: otro, challenge_step: paso)
      end
      sign_in(ana, company: company)
      get workshop_path(setup[:workshop])

      ids = response.body.scan(/\bid="([^"]+)"/).flatten
      expect(ids.grep(/payload_/).size).to eq(2)
      expect(ids.tally.select { |_, n| n > 1 }.keys.grep(/payload_/)).to be_empty
      expect(response.body.scan(/for="([^"]*payload_[^"]*)"/).flatten.uniq.size).to eq(2)
    end

    it "muestra la sala cerrada con su motivo en vez de hacerla desaparecer" do
      as_company(company) do
        setup[:link].update!(status: "closed", closed_reason: "El desafío avanzó de fase.", closed_at: Time.current)
      end
      sign_in(ana, company: company)
      get workshop_path(setup[:workshop])

      expect(response.body).to include("El desafío avanzó de fase.")
      expect(response.body).not_to include(%(name="payload[))
    end
  end
end
