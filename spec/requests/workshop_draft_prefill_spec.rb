# frozen_string_literal: true

require "rails_helper"

# El borrador vuelve al recargar, y se va cuando la mesa lo manda. Lo segundo no
# es prolijidad: si el formulario sigue prellenado con lo ya mandado, la mesa lo
# manda de nuevo, que es el defecto que la sala de la mesa existe para arreglar.
RSpec.describe "sala del taller: el borrador se prellena", type: :request do
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
      idea = create(:idea, challenge: challenge, author: ana, status: "active")
      version = Flow::Ideas::PublishVersion.new(
        idea, payload: { field.key => "lo publicado" }, author: ana
      ).call.version
      { workshop: workshop, link: link, group: group, field: field, idea: idea,
        version: version, challenge: challenge }
    end
  end

  describe "en idear" do
    it "sin borrador el formulario arranca vacío" do
      sign_in(ana, company: company)
      get workshop_sala_path(idear[:workshop], idear[:link])

      expect(response.body).to include('name="payload[')
      expect(response.body).not_to include("a medio escribir")
    end

    # Lo que B existe para resolver: la mesa escribió y alguien recargó.
    it "con borrador de la mesa, el formulario trae el texto — aunque lo haya escrito otra persona" do
      as_company(company) do
        create(:workshop_draft, workshop_group: idear[:group], workshop_challenge: idear[:link],
                                updated_by: beto,
                                payload: { idear[:field].key => "a medio escribir" })
      end
      sign_in(ana, company: company)
      get workshop_sala_path(idear[:workshop], idear[:link])

      expect(response.body).to include("a medio escribir")
    end

    it "al crear la idea el borrador se va" do
      as_company(company) do
        create(:workshop_draft, workshop_group: idear[:group], workshop_challenge: idear[:link],
                                updated_by: ana, payload: { idear[:field].key => "a medio escribir" })
      end
      sign_in(ana, company: company)
      post workshop_sala_ideas_path(idear[:workshop], idear[:link]),
           params: { payload: { idear[:field].key => "ya está" } }

      expect(as_company(company) { WorkshopDraft.count }).to eq(0)
    end
  end

  describe "en evolución" do
    it "sin borrador el formulario trae el contenido de la versión vigente" do
      sign_in(ana, company: company)
      get workshop_sala_path(evolucion[:workshop], evolucion[:link], idea: evolucion[:idea].id)

      expect(response.body).to include("lo publicado")
    end

    # El borrador GANA sobre la versión: es el texto que la mesa escribió.
    it "con borrador, el borrador le gana a la versión vigente" do
      as_company(company) do
        create(:workshop_draft, workshop_group: evolucion[:group],
                                workshop_challenge: evolucion[:link], idea: evolucion[:idea],
                                based_on_version: evolucion[:version], updated_by: ana,
                                payload: { evolucion[:field].key => "lo de la mesa" })
      end
      sign_in(ana, company: company)
      get workshop_sala_path(evolucion[:workshop], evolucion[:link], idea: evolucion[:idea].id)

      expect(response.body).to include("lo de la mesa")
      expect(response.body).not_to include('value="lo publicado"')
    end

    it "al mandar la propuesta el borrador se va" do
      as_company(company) do
        create(:workshop_draft, workshop_group: evolucion[:group],
                                workshop_challenge: evolucion[:link], idea: evolucion[:idea],
                                based_on_version: evolucion[:version], updated_by: ana,
                                payload: { evolucion[:field].key => "lo de la mesa" })
      end
      sign_in(ana, company: company)
      post workshop_sala_proposals_path(evolucion[:workshop], evolucion[:link]),
           params: { idea_id: evolucion[:idea].id,
                     payload: { evolucion[:field].key => "lo de la mesa" } }

      as_company(company) do
        expect(WorkshopDraft.count).to eq(0)
        expect(WorkshopProposal.count).to eq(1)
      end
    end

    # El borrador de la idea A no puede prellenar el formulario de la idea B.
    it "el borrador de otra idea no se mezcla" do
      otra = as_company(company) do
        i = create(:idea, challenge: evolucion[:challenge], author: ana, status: "active")
        v = Flow::Ideas::PublishVersion.new(
          i, payload: { evolucion[:field].key => "contenido de la otra" }, author: ana
        ).call.version
        create(:workshop_draft, workshop_group: evolucion[:group],
                                workshop_challenge: evolucion[:link], idea: i,
                                based_on_version: v, updated_by: ana,
                                payload: { evolucion[:field].key => "borrador de la otra" })
        i
      end
      sign_in(ana, company: company)
      get workshop_sala_path(evolucion[:workshop], evolucion[:link], idea: evolucion[:idea].id)

      expect(response.body).not_to include("borrador de la otra")
      expect(response.body).to include("lo publicado")
      expect(otra).to be_present
    end
  end
end
