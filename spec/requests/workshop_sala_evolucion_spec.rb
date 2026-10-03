# frozen_string_literal: true

require "rails_helper"

RSpec.describe "sala del taller: evolución", type: :request do
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
  let!(:dani) { member("dani@test.dev") }

  # Desafío con módulo de ideación (de donde salen los campos) y una ronda de
  # evolución ACTIVA; taller abierto contra esa ronda, mesa de ana y beto. La
  # idea de ana la trabaja su mesa; la de carla no; la de dani sí, pero sólo
  # porque beto colabora en ella.
  let!(:scene) do
    as_company(company) do
      challenge = create(:challenge)
      ideation = create(:challenge_step, challenge: challenge, kind: "ideation", status: "completed")
      field = create(:form_field, challenge_step: ideation, label: "Resumen", field_type: "text")
      round = create(:challenge_step, challenge: challenge, kind: "evolution", status: "active")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge, challenge_step: round)
      group = create(:workshop_group, workshop: workshop)
      [ ana, beto ].each { |u| create(:workshop_group_member, workshop_group: group, user: u) }
      ana_idea = create(:idea, challenge: challenge, author: ana, status: "active")
      dani_idea = create(:idea, challenge: challenge, author: dani, status: "active")
      IdeaContributor.create!(idea: dani_idea, user: beto)
      { challenge: challenge, round: round, field: field, workshop: workshop, link: link, group: group,
        ana_idea: ana_idea, dani_idea: dani_idea,
        carla_idea: create(:idea, challenge: challenge, author: carla, status: "active"),
        # De la mesa, pero muertas o sin postular: no se trabajan.
        ana_eliminada: create(:idea, challenge: challenge, author: ana, status: "eliminated"),
        beto_borrador: create(:idea, challenge: challenge, author: beto, status: "draft") }
    end
  end

  def propose(idea, payload: nil)
    payload = { scene[:field].key => "Mejor así", "clave_ajena" => "x" } if payload.nil?
    post workshop_sala_proposals_path(scene[:workshop], scene[:link]),
         params: { idea_id: idea.id, payload: payload }
  end

  it "la propuesta nace pendiente, con el step de ESA ronda y el payload filtrado" do
    sign_in(beto, company: company)
    propose(scene[:ana_idea])

    as_company(company) do
      proposal = WorkshopProposal.order(:created_at).last
      expect(proposal).to be_pending
      expect(proposal.challenge_step_id).to eq(scene[:round].id)
      expect(proposal.workshop_group_id).to eq(scene[:group].id)
      expect(proposal.payload).to eq(scene[:field].key => "Mejor así")
    end
  end

  it "deja proponer sobre la idea de un tercero en la que colabora alguien de la mesa" do
    sign_in(ana, company: company)

    expect { propose(scene[:dani_idea]) }
      .to(change { as_company(company) { WorkshopProposal.count } }.by(1))
  end

  # Sin polinización cruzada: la idea de carla no es de nadie de la mesa. Es
  # 404 y no 403, y falla si alguien ensancha el conjunto trabajable.
  it "no deja proponer sobre una idea que ninguna persona de la mesa creó ni comparte" do
    sign_in(beto, company: company)

    expect { propose(scene[:carla_idea]) }
      .not_to(change { as_company(company) { WorkshopProposal.count } })
    expect(response).to have_http_status(:not_found)
  end

  # Proponer sobre una idea que no pasó un corte es un control que no lleva a
  # ninguna parte, y la sala no daba ni un indicio de que estaba muerta.
  it "no deja proponer sobre una idea eliminada de la propia mesa" do
    sign_in(beto, company: company)

    expect { propose(scene[:ana_eliminada]) }
      .not_to(change { as_company(company) { WorkshopProposal.count } })
    expect(response).to have_http_status(:not_found)
  end

  # Un borrador que un integrante creó FUERA del taller y nunca postuló lo veía
  # sólo él. La mesa no lo hereda: la ronda de evolución trabaja lo postulado.
  it "no deja proponer sobre el borrador que un compañero de mesa nunca postuló" do
    sign_in(ana, company: company)

    expect { propose(scene[:beto_borrador]) }
      .not_to(change { as_company(company) { WorkshopProposal.count } })
    expect(response).to have_http_status(:not_found)
  end

  it "sin payload no revienta: propone con el payload vacío" do
    sign_in(beto, company: company)
    post workshop_sala_proposals_path(scene[:workshop], scene[:link]), params: { idea_id: scene[:ana_idea].id }

    as_company(company) { expect(WorkshopProposal.order(:created_at).last.payload).to eq({}) }
  end

  it "un payload que no es un hash se rechaza con aviso, sin 500 ni propuesta" do
    sign_in(beto, company: company)

    expect { propose(scene[:ana_idea], payload: "basura") }
      .not_to(change { as_company(company) { WorkshopProposal.count } })
    expect(response).to redirect_to(workshop_sala_path(scene[:workshop], scene[:link]))
    expect(flash[:alert]).to include("mal formada")
  end

  it "quien administra y no está en ninguna mesa recibe un aviso, no un 404" do
    admin = without_tenant do
      u = create(:user, email: "admin@test.dev")
      create(:membership, :admin, company: company, user: u)
      u
    end
    sign_in(admin, company: company)

    expect { propose(scene[:ana_idea]) }.not_to(change { as_company(company) { WorkshopProposal.count } })
    expect(response).to redirect_to(workshop_sala_path(scene[:workshop], scene[:link]))
    expect(flash[:alert]).to include("desde una mesa")
  end

  it "no deja proponer si la ronda se cerró" do
    as_company(company) { scene[:round].update!(status: "completed") }
    sign_in(beto, company: company)

    expect { propose(scene[:ana_idea]) }.not_to(change { as_company(company) { WorkshopProposal.count } })
    expect(flash[:alert]).to include("avanzó de fase")
  end

  it "quien no fue convocado al taller ni lo ve: 404" do
    sign_in(carla, company: company)

    expect { propose(scene[:carla_idea]) }.not_to(change { as_company(company) { WorkshopProposal.count } })
    expect(response).to have_http_status(:not_found)
  end

  describe "el selector de ideas" do
    def sala(params = {}) = get workshop_sala_path(scene[:workshop], scene[:link], params)

    # Por la URL de selección y NO por el título: `ideas` no tiene columna
    # `title` —sale de la versión vigente— y en esta escena ninguna idea
    # publicó versión, así que las cinco se llaman «(sin título)» y una
    # aserción sobre el texto no distinguiría la propia de la ajena.
    def link_a(idea) = workshop_sala_path(scene[:workshop], scene[:link], idea: idea.id)

    it "lista las ideas de la mesa con la participación de cada uno, y ninguna ajena" do
      sign_in(beto, company: company)
      sala

      expect(response.body).to include(link_a(scene[:ana_idea]))
      expect(response.body).to include(link_a(scene[:dani_idea]))
      expect(response.body).not_to include(link_a(scene[:carla_idea]))
      expect(response.body).not_to include(link_a(scene[:ana_eliminada]))
      expect(response.body).not_to include(link_a(scene[:beto_borrador]))
      # Quién la creó y quién colabora: es lo que deja ver a la mesa por qué
      # la idea de dani entra (beto colabora en ella).
      expect(response.body).to include("creó la idea")
      expect(response.body).to include(I18n.t("flow.contributor_roles.contributor"))
      expect(response.body).to include(beto.name)
    end

    it "con dos ideas no preselecciona ninguna y no ofrece formulario todavía" do
      sign_in(beto, company: company)
      sala

      expect(response.body).not_to include(%(name="payload[#{scene[:field].key}]"))
    end

    it "al elegir una idea muestra su contenido y un solo formulario" do
      as_company(company) do
        result = Flow::Ideas::PublishVersion.new(
          scene[:ana_idea], payload: { scene[:field].key => "Texto de ana" }, author: ana,
                            source_step: scene[:round], change_note: "Inicial"
        ).call
        expect(result).to be_ok
      end
      sign_in(beto, company: company)
      sala(idea: scene[:ana_idea].id)

      expect(response.body).to include("Texto de ana")
      expect(response.body).to include(%(value="#{scene[:ana_idea].id}"))
      expect(response.body.scan(/value="Proponer"/).size).to eq(1)
    end

    # Review Focus 1. Fuera del conjunto trabajable, `nil`: igual que un id
    # inexistente, así que no confirma que exista. Ni 403 ni 500.
    it "un id que no es de la mesa queda sin selección, no en 403" do
      sign_in(beto, company: company)
      sala(idea: scene[:carla_idea].id)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(%(name="payload[#{scene[:field].key}]"))
    end

    it "un id inventado tampoco revienta" do
      sign_in(beto, company: company)
      sala(idea: SecureRandom.uuid)

      expect(response).to have_http_status(:ok)
    end

    it "con una sola idea trabajable la preselecciona" do
      as_company(company) { scene[:dani_idea].update!(status: "eliminated") }
      sign_in(beto, company: company)
      sala

      expect(response.body).to include(%(value="#{scene[:ana_idea].id}"))
      expect(response.body).to include(%(name="payload[#{scene[:field].key}]"))
    end

    # Review Focus 5: una idea sin versión publicada. El contenido se dibuja
    # con `—` por campo y no revienta sobre `nil.payload`.
    it "una idea sin versión vigente muestra el contenido vacío, sin 500" do
      as_company(company) { scene[:dani_idea].update!(status: "eliminated") }
      sign_in(beto, company: company)
      sala

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("—")
    end
  end

  describe "lo que esta mesa propuso" do
    it "lista la propuesta pendiente de la mesa sobre la idea elegida" do
      # Nada de títulos acá tampoco: lo que se mide es el bloque y el chip.
      sign_in(beto, company: company)
      propose(scene[:ana_idea])

      get workshop_sala_path(scene[:workshop], scene[:link], idea: scene[:ana_idea].id)
      expect(response.body).to include("Lo que esta mesa propuso")
      expect(response.body).to include(I18n.t("flow.workshop_proposal_statuses.pending"))
    end

    # Con la ronda del vínculo cerrada, `MaterializeClosures` cierra el vínculo
    # y la sala ni dibuja esta cara; por eso el vencimiento se prueba con una
    # propuesta de una ronda ANTERIOR (ya completada), que la mesa sigue viendo
    # sobre la idea.
    it "la propuesta vencida dice que la ronda cerró" do
      as_company(company) do
        vieja = create(:challenge_step, challenge: scene[:challenge], kind: "evolution", status: "completed",
                                        name: "Ronda vieja")
        WorkshopProposal.create!(workshop_group: scene[:group], idea: scene[:ana_idea], challenge_step: vieja,
                                 payload: { scene[:field].key => "Tarde" }, status: "pending")
      end
      sign_in(beto, company: company)

      get workshop_sala_path(scene[:workshop], scene[:link], idea: scene[:ana_idea].id)
      expect(response.body).to include("venció")
      expect(response.body).to include("Ronda vieja")
    end

    # Dos ejemplos y no uno: la vista no dibuja el payload, así que se mide lo
    # que SÍ dibuja —el bloque y la etiqueta del chip—.
    def propuesta_de_otra_mesa
      as_company(company) do
        mesa = create(:workshop_group, workshop: scene[:workshop], name: "Mesa 9")
        WorkshopProposal.create!(workshop_group: mesa, idea: scene[:ana_idea],
                                 challenge_step: scene[:round], payload: { scene[:field].key => "De otra mesa" },
                                 status: "pending")
      end
    end

    it "si sólo otra mesa propuso, el bloque no aparece" do
      propuesta_de_otra_mesa
      sign_in(beto, company: company)
      get workshop_sala_path(scene[:workshop], scene[:link], idea: scene[:ana_idea].id)

      expect(response.body).not_to include("Lo que esta mesa propuso")
    end

    it "si las dos propusieron, lista una sola fila: la de esta mesa" do
      propuesta_de_otra_mesa
      sign_in(beto, company: company)
      propose(scene[:ana_idea])
      get workshop_sala_path(scene[:workshop], scene[:link], idea: scene[:ana_idea].id)

      expect(response.body.scan(I18n.t("flow.workshop_proposal_statuses.pending")).size).to eq(1)
    end
  end

  it "proponer vuelve a la sala con la idea elegida" do
    sign_in(beto, company: company)
    propose(scene[:ana_idea])

    expect(response).to redirect_to(
      workshop_sala_path(scene[:workshop], scene[:link], idea: scene[:ana_idea].id)
    )
  end

  describe "la sala" do
    it "precarga el formulario con el payload de la versión vigente de la idea elegida" do
      as_company(company) do
        result = Flow::Ideas::PublishVersion.new(
          scene[:dani_idea], payload: { scene[:field].key => "Texto de dani" }, author: dani,
                             source_step: scene[:round], change_note: "Inicial"
        ).call
        expect(result).to be_ok
      end
      sign_in(beto, company: company)
      get workshop_sala_path(scene[:workshop], scene[:link], idea: scene[:dani_idea].id)

      expect(response.body).to include(%(value="Texto de dani"))
      ids = response.body.scan(/\bid="([^"]+)"/).flatten
      expect(ids.tally.select { |_, n| n > 1 }.keys.grep(/payload_/)).to be_empty
    end

    # Un campo de archivo no viaja en una propuesta. No es un control fantasma
    # (no se renderiza), pero uno requerido dejaba de ser proponible sin que la
    # pantalla lo dijera.
    it "avisa que los campos de archivo no se proponen desde el taller" do
      as_company(company) do
        create(:form_field, challenge_step: scene[:challenge].pipeline.ideation_step,
                            label: "Plano firmado", field_type: "file", required: true)
      end
      sign_in(beto, company: company)
      get workshop_sala_path(scene[:workshop], scene[:link], idea: scene[:ana_idea].id)

      expect(response.body).to include("El campo de archivo Plano firmado no se propone desde el taller")
      expect(response.body).not_to include(%(name="files[))
    end

    it "con dos campos de archivo concuerda toda la frase en plural" do
      as_company(company) do
        step = scene[:challenge].pipeline.ideation_step
        create(:form_field, challenge_step: step, label: "Plano", field_type: "file")
        create(:form_field, challenge_step: step, label: "Anexo", field_type: "file")
      end
      sign_in(beto, company: company)
      get workshop_sala_path(scene[:workshop], scene[:link], idea: scene[:ana_idea].id)

      expect(response.body).to include("Los campos de archivo Plano y Anexo no se proponen desde el taller, por eso no están en el formulario.")
    end

    it "sin campos de archivo no muestra ese aviso" do
      sign_in(beto, company: company)
      get workshop_sala_path(scene[:workshop], scene[:link], idea: scene[:ana_idea].id)

      expect(response.body).not_to include("no se propone desde el taller")
    end
  end
end
