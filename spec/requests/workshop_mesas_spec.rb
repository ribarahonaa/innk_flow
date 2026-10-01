# frozen_string_literal: true

require "rails_helper"

# El control de armar las mesas, en la sala. Se ofrece sólo cuando el servicio
# lo aceptaría: una condición de más es un control que rebota contra un aviso.
RSpec.describe "armar las mesas", type: :request do
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

  # Un taller con UN vínculo en la fase `kind`, en el estado dado.
  def workshop_with(status: "open", mode: "group", link: "open", kind: "ideation")
    as_company(company) do
      workshop = create(:workshop, status: status, mode: mode)
      challenge = create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: kind, status: "active")
      create(:workshop_challenge, workshop: workshop, challenge: challenge, challenge_step: step, status: link)
      workshop
    end
  end

  let!(:taller) { workshop_with }

  def offered?(workshop)
    get workshop_path(workshop)
    response.body.include?(assign_workshop_workshop_groups_path(workshop))
  end

  describe "el control" do
    it "lo ve quien administra, con el taller abierto y sin propuestas" do
      sign_in(admin, company: company)
      expect(offered?(taller)).to be(true)
    end

    it "no lo ve quien no administra" do
      sign_in(paula, company: company)
      get workshop_path(taller)

      expect(response.body).not_to include(assign_workshop_workshop_groups_path(taller))
    end

    it "no se ofrece en borrador: el servicio lo rechazaría" do
      borrador = workshop_with(status: "draft")
      sign_in(admin, company: company)

      expect(offered?(borrador)).to be(false)
    end

    it "no se ofrece en modo individual: ahí una mesa es una persona" do
      individual = workshop_with(mode: "individual")
      sign_in(admin, company: company)

      expect(offered?(individual)).to be(false)
    end

    it "no se ofrece si el taller está abierto pero todos sus vínculos se cerraron" do
      sin_fase = workshop_with(link: "closed")
      sign_in(admin, company: company)

      expect(offered?(sin_fase)).to be(false)
    end

    it "no se ofrece si ya hay propuestas" do
      as_company(company) do
        mesa = create(:workshop_group, workshop: taller)
        step = taller.workshop_challenges.first.challenge_step
        idea = create(:idea, challenge: step.challenge, status: "active")
        WorkshopProposal.create!(workshop_group: mesa, idea: idea, challenge_step: step,
                                 status: "pending", payload: { "titulo" => "x" })
      end
      sign_in(admin, company: company)

      expect(offered?(taller)).to be(false)
    end
  end

  describe "armar" do
    it "arma las mesas y cuenta qué hizo" do
      sign_in(admin, company: company)
      post assign_workshop_workshop_groups_path(taller), params: { size: 2 }

      expect(response).to redirect_to(workshop_path(taller))
      expect(flash[:notice]).to include("mesa")
    end

    it "quien no administra recibe 404 y no arma nada" do
      sign_in(paula, company: company)

      expect do
        post assign_workshop_workshop_groups_path(taller), params: { size: 2 }
      end.not_to(change { as_company(company) { WorkshopGroup.count } })
      expect(response).to have_http_status(:not_found)
    end

    it "si el servicio rechaza, lo dice en un aviso" do
      borrador = workshop_with(status: "draft")
      sign_in(admin, company: company)
      post assign_workshop_workshop_groups_path(borrador), params: { size: 2 }

      expect(flash[:alert]).to include("abierto")
    end
  end
end
