# frozen_string_literal: true

require "rails_helper"

RSpec.describe "aceptar una propuesta de taller", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def make_member(email, role)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, role.to_sym, company: company, user: u)
      u
    end
  end

  let!(:ana) { make_member("ana@test.dev", :participant) }
  let!(:beto) { make_member("beto@test.dev", :participant) }
  let!(:admin) { make_member("admin@test.dev", :admin) }

  let!(:setup) do
    as_company(company) do
      challenge = create(:challenge)
      ideation = create(:challenge_step, challenge: challenge, kind: "ideation", status: "completed")
      create(:form_field, challenge_step: ideation, label: "Resumen", field_type: "text")
      round = create(:challenge_step, challenge: challenge, kind: "evolution", status: "active")
      idea = create(:idea, challenge: challenge, author: ana, status: "active")
      workshop = create(:workshop, status: "open")
      group = create(:workshop_group, workshop: workshop)
      [ana, beto].each { |u| create(:workshop_group_member, workshop_group: group, user: u) }
      proposal = create(:workshop_proposal, workshop_group: group, idea: idea,
                                            challenge_step: round, payload: { "resumen" => "Mejor así" })
      { challenge: challenge, round: round, idea: idea, proposal: proposal }
    end
  end

  def accept = post accept_idea_workshop_proposal_path(setup[:idea], setup[:proposal])
  def reject = post reject_idea_workshop_proposal_path(setup[:idea], setup[:proposal])
  def versions_count = as_company(company) { setup[:idea].versions.count }
  def proposal_status = as_company(company) { setup[:proposal].reload.status }

  it "publica la versión con actor_type workshop y suma la mesa como contribuyentes" do
    sign_in(ana, company: company)
    accept

    as_company(company) do
      idea = setup[:idea].reload
      expect(idea.current_version.actor_type).to eq("workshop")
      expect(idea.current_version.source_step_id).to eq(setup[:round].id)
      expect(idea.contributors.map(&:id)).to include(beto.id)
      expect(setup[:proposal].reload).to be_accepted
    end
  end

  # El sentido del paso es que a nadie le reescriban la idea sin que
  # participe. Un atajo para quien administra lo borraría.
  it "sólo el autor acepta: a quien administra le da 403" do
    sign_in(admin, company: company)

    expect { accept }.not_to(change { versions_count })
    expect(response).to have_http_status(:forbidden)
    expect(proposal_status).to eq("pending")
  end

  it "sólo el autor descarta: a quien administra le da 403" do
    sign_in(admin, company: company)
    reject

    expect(response).to have_http_status(:forbidden)
    expect(proposal_status).to eq("pending")
  end

  # Publicar dentro de una ronda cerrada escribiría en una conversación terminada.
  it "una propuesta cuya ronda ya cerró no se puede aceptar" do
    as_company(company) { setup[:round].update!(status: "completed") }
    sign_in(ana, company: company)

    expect { accept }.not_to(change { versions_count })
    expect(flash[:alert]).to include("ya cerró")
    expect(proposal_status).to eq("pending")
  end

  it "si la publicación falla, la propuesta no queda aceptada ni la mesa como contribuyente" do
    failure = Flow::Ideas::PublishVersion::Result.new(ok: false, version: nil, errors: ["Payload inválido"])
    allow_any_instance_of(Flow::Ideas::PublishVersion).to receive(:call).and_return(failure)
    sign_in(ana, company: company)
    accept

    expect(flash[:alert]).to eq("Payload inválido")
    expect(proposal_status).to eq("pending")
    expect(as_company(company) { setup[:idea].contributors.count }).to eq(0)
  end

  it "descartar marca la propuesta como rejected, sin publicar nada" do
    sign_in(ana, company: company)

    expect { reject }.not_to(change { versions_count })
    expect(proposal_status).to eq("rejected")
    expect(flash[:notice]).to eq("Propuesta descartada.")
  end

  it "descartar una propuesta vencida funciona: no escribe en ninguna conversación" do
    as_company(company) { setup[:round].update!(status: "completed") }
    sign_in(ana, company: company)
    reject

    expect(proposal_status).to eq("rejected")
    expect(flash[:notice]).to eq("Propuesta descartada.")
  end

  it "descartar una propuesta ya aceptada no la pisa" do
    sign_in(ana, company: company)
    accept
    reject

    expect(proposal_status).to eq("accepted")
    expect(flash[:alert]).to eq("Esta propuesta ya fue resuelta.")
  end

  it "descartar una propuesta ya descartada no cambia quién la revisó" do
    as_company(company) { setup[:proposal].update!(status: "rejected", reviewed_by: admin) }
    sign_in(ana, company: company)
    reject

    expect(flash[:alert]).to eq("Esta propuesta ya fue resuelta.")
    expect(as_company(company) { setup[:proposal].reload.reviewed_by_id }).to eq(admin.id)
  end

  it "aceptar dos veces no publica dos versiones y avisa que ya fue resuelta" do
    sign_in(ana, company: company)
    accept
    expect { accept }.not_to(change { versions_count })

    expect(flash[:alert]).to eq("Esta propuesta ya fue resuelta.")
    expect(flash[:alert]).not_to include("ya cerró")
  end

  it "aceptar una propuesta descartada no la publica" do
    as_company(company) { setup[:proposal].update!(status: "rejected") }
    sign_in(ana, company: company)

    expect { accept }.not_to(change { versions_count })
    expect(flash[:alert]).to eq("Esta propuesta ya fue resuelta.")
    expect(proposal_status).to eq("rejected")
  end

  it "quien no ve la idea recibe 404" do
    stranger = make_member("carla@test.dev", :participant)
    sign_in(stranger, company: company)
    accept

    expect(response).to have_http_status(:not_found)
  end

  describe "en la ficha de la idea" do
    it "ofrece Aceptar y Descartar al autor si la ronda está abierta" do
      sign_in(ana, company: company)
      get challenge_idea_path(setup[:challenge], setup[:idea])

      expect(response.body).to include(accept_idea_workshop_proposal_path(setup[:idea], setup[:proposal]))
      expect(response.body).to include(reject_idea_workshop_proposal_path(setup[:idea], setup[:proposal]))
    end

    # Descartar una vencida es una capacidad que el controller SIEMPRE tuvo, y
    # ninguna pantalla la ofrecía: la propuesta quedaba en la ficha para
    # siempre, con un aviso y ningún control.
    it "la propuesta vencida no se acepta pero sí se descarta" do
      as_company(company) { setup[:round].update!(status: "completed") }
      sign_in(ana, company: company)
      get challenge_idea_path(setup[:challenge], setup[:idea])

      expect(response.body).to include("Mejor así")
      expect(response.body).to include("venció")
      expect(response.body).not_to include(accept_idea_workshop_proposal_path(setup[:idea], setup[:proposal]))
      expect(response.body).to include(reject_idea_workshop_proposal_path(setup[:idea], setup[:proposal]))
    end

    it "una propuesta ya resuelta no se lista" do
      as_company(company) { setup[:proposal].update!(status: "rejected") }
      sign_in(ana, company: company)
      get challenge_idea_path(setup[:challenge], setup[:idea])

      expect(response.body).not_to include("workshop_proposal_#{setup[:proposal].id}")
    end

    it "no ofrece botones a quien administra, que ve la propuesta" do
      sign_in(admin, company: company)
      get challenge_idea_path(setup[:challenge], setup[:idea])

      expect(response.body).to include("Mejor así")
      expect(response.body).not_to include(accept_idea_workshop_proposal_path(setup[:idea], setup[:proposal]))
      expect(response.body).not_to include(reject_idea_workshop_proposal_path(setup[:idea], setup[:proposal]))
    end
  end
end
