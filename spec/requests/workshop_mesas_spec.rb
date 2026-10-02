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

    # Paula tiene que estar sentada: sin asiento `policy_scope` le da 404 y la
    # página de error no trae el control igual, con o sin guarda en la vista.
    it "no lo ve quien no administra, aunque vea el taller" do
      as_company(company) do
        mesa = create(:workshop_group, workshop: taller)
        Flow::Workshops::Convoke.new(taller, User.find(paula.id), group: mesa).call
      end
      sign_in(paula, company: company)
      get workshop_path(taller)

      expect(response).to have_http_status(:ok)
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

  describe "el aviso de los cortes" do
    # Una cadena de ideas que se pasan gente: con mesa de 2 hay que desprender.
    def evolution_chain(*people_per_idea)
      users = as_company(company) { Array.new(people_per_idea.flatten.max + 1) { create(:user) } }
      workshop = workshop_with(kind: "evolution")
      as_company(company) do
        step = workshop.workshop_challenges.first.challenge_step
        people_per_idea.each do |ids|
          idea = create(:idea, challenge: step.challenge, author: users[ids.first], status: "active")
          StepEntry.create!(challenge_step: step, idea: idea)
          ids.drop(1).each { |i| IdeaContributor.create!(idea: idea, user: users[i]) }
        end
      end
      workshop
    end

    it "con dos cortes concuerda en plural: «2 grupos quedaron partidos»" do
      workshop = evolution_chain([0, 1], [1, 2], [2, 3], [3, 4])
      sign_in(admin, company: company)
      post assign_workshop_workshop_groups_path(workshop), params: { size: 2 }

      expect(flash[:notice]).to match(/\b[2-9] grupos quedaron partidos por el tamaño de mesa/)
    end

    it "con un corte concuerda en singular: «1 grupo quedó partido»" do
      workshop = evolution_chain([0, 1], [1, 2])
      sign_in(admin, company: company)
      post assign_workshop_workshop_groups_path(workshop), params: { size: 2 }

      expect(flash[:notice]).to include("1 grupo quedó partido por el tamaño de mesa")
    end

    it "una idea más grande que la mesa tiene su propio aviso" do
      workshop = evolution_chain([0, 1, 2])
      sign_in(admin, company: company)
      post assign_workshop_workshop_groups_path(workshop), params: { size: 2 }

      expect(flash[:notice]).to include("separar a personas de una misma idea")
      expect(flash[:notice]).not_to include("quedó partido")
    end
  end

  describe "eliminar una mesa" do
    def seat(workshop_group, user, attended: true)
      as_company(company) do
        WorkshopGroupMember.create!(workshop_group: workshop_group, user: user, attended: attended)
      end
    end

    def seats_of(workshop)
      as_company(company) do
        WorkshopGroupMember.joins(:workshop_group)
                           .where(workshop_groups: { workshop_id: workshop.id })
                           .map { |m| [m.user_id, m.workshop_group.arrival?, m.attended] }
      end
    end

    def table_exists?(group)
      as_company(company) { WorkshopGroup.exists?(group.id) }
    end

    let!(:ana) { member("ana@test.dev", :participant) }

    it "manda a su gente a la mesa de llegada, con su asistencia intacta" do
      mesa = as_company(company) { create(:workshop_group, workshop: taller) }
      seat(mesa, paula, attended: true)
      seat(mesa, ana, attended: false)
      sign_in(admin, company: company)

      delete workshop_workshop_group_path(taller, mesa)

      expect(response).to redirect_to(workshop_path(taller))
      expect(flash[:notice]).to eq("Mesa eliminada.")
      expect(table_exists?(mesa)).to be(false)
      expect(seats_of(taller)).to contain_exactly([paula.id, true, true], [ana.id, true, false])
    end

    it "no borra la mesa de llegada, y la pantalla no lo ofrece" do
      llegada = as_company(company) { create(:workshop_group, :arrival, workshop: taller) }
      otra = as_company(company) { create(:workshop_group, workshop: taller) }
      seat(llegada, paula)
      sign_in(admin, company: company)

      get workshop_path(taller)
      expect(response).to have_http_status(:ok)
      # Control positivo: la otra mesa SÍ se ofrece, así que la ausencia de la
      # de llegada no es una página que no renderizó.
      expect(response.body).to include(workshop_workshop_group_path(taller, otra))
      expect(response.body).not_to include(workshop_workshop_group_path(taller, llegada))

      delete workshop_workshop_group_path(taller, llegada)

      expect(flash[:alert]).to include("llegada")
      expect(table_exists?(llegada)).to be(true)
      expect(seats_of(taller)).to eq([[paula.id, true, true]])
    end

    it "no borra una mesa con propuestas, y no pierde a nadie" do
      mesa = as_company(company) { create(:workshop_group, workshop: taller) }
      seat(mesa, paula)
      as_company(company) do
        step = taller.workshop_challenges.first.challenge_step
        idea = create(:idea, challenge: step.challenge, status: "active")
        WorkshopProposal.create!(workshop_group: mesa, idea: idea, challenge_step: step,
                                 status: "accepted", payload: { "titulo" => "x" })
      end
      sign_in(admin, company: company)

      delete workshop_workshop_group_path(taller, mesa)

      expect(flash[:alert]).to include("propuestas")
      expect(table_exists?(mesa)).to be(true)
      expect(as_company(company) { WorkshopProposal.count }).to eq(1)
      expect(seats_of(taller)).to eq([[paula.id, false, true]])
    end

    it "borrar una mesa vacía no arma una mesa de llegada que nadie va a usar" do
      mesa = as_company(company) { create(:workshop_group, workshop: taller) }
      sign_in(admin, company: company)

      delete workshop_workshop_group_path(taller, mesa)

      expect(table_exists?(mesa)).to be(false)
      expect(as_company(company) { WorkshopGroup.where(workshop_id: taller.id, arrival: true).exists? }).to be(false)
    end

    it "en modo individual se borra como siempre: cada persona es su mesa" do
      individual = workshop_with(mode: "individual")
      mesa = as_company(company) { create(:workshop_group, workshop: individual) }
      seat(mesa, paula)
      sign_in(admin, company: company)

      delete workshop_workshop_group_path(individual, mesa)

      expect(flash[:notice]).to eq("Mesa eliminada.")
      expect(table_exists?(mesa)).to be(false)
      expect(seats_of(individual)).to be_empty
      expect(as_company(company) { WorkshopGroup.where(workshop_id: individual.id).count }).to eq(0)
    end
  end
end
