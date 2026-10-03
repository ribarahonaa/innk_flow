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
    expect(response).to redirect_to(workshop_path(scene[:workshop]))
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
    expect(response).to redirect_to(workshop_path(scene[:workshop]))
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

  describe "la pantalla del taller" do
    it "precarga cada formulario con el payload de la versión vigente y no repite ids de DOM" do
      as_company(company) do
        [ scene[:ana_idea], scene[:dani_idea] ].each do |idea|
          result = Flow::Ideas::PublishVersion.new(
            idea, payload: { scene[:field].key => "Texto de #{idea.author.name}" }, author: idea.author,
                  source_step: scene[:round], change_note: "Inicial"
          ).call
          expect(result).to be_ok
        end
      end
      sign_in(beto, company: company)
      get workshop_sala_path(scene[:workshop], scene[:link])

      expect(response.body).to include(%(value="Texto de #{ana.name}"))
      expect(response.body).to include(%(value="Texto de #{dani.name}"))
      ids = response.body.scan(/\bid="([^"]+)"/).flatten
      expect(ids.select { |i| i.start_with?("idea_") && i.end_with?("payload_#{scene[:field].key}") }.uniq.size).to eq(2)
      expect(ids.tally.select { |_, n| n > 1 }.keys.grep(/payload_/)).to be_empty
    end

    it "ofrece un formulario por idea de la mesa, y ninguno para la ajena" do
      sign_in(beto, company: company)
      get workshop_sala_path(scene[:workshop], scene[:link])

      expect(response.body).to include(%(value="#{scene[:ana_idea].id}"))
      expect(response.body).to include(%(value="#{scene[:dani_idea].id}"))
      expect(response.body).not_to include(%(value="#{scene[:carla_idea].id}"))
      expect(response.body).not_to include(%(value="#{scene[:ana_eliminada].id}"))
      expect(response.body).not_to include(%(value="#{scene[:beto_borrador].id}"))
      expect(response.body).to include(%(name="payload[#{scene[:field].key}]"))
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
      get workshop_sala_path(scene[:workshop], scene[:link])

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
      get workshop_sala_path(scene[:workshop], scene[:link])

      expect(response.body).to include("Los campos de archivo Plano y Anexo no se proponen desde el taller, por eso no están en el formulario.")
    end

    it "sin campos de archivo no muestra ese aviso" do
      sign_in(beto, company: company)
      get workshop_sala_path(scene[:workshop], scene[:link])

      expect(response.body).not_to include("no se propone desde el taller")
    end
  end
end
