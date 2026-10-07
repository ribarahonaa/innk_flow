# frozen_string_literal: true

require "rails_helper"

# Las dos invariantes que Postgres no puede cuidar.
RSpec.describe WorkshopDraft do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }
  let!(:autora) do
    without_tenant do
      u = create(:user, email: "ana@test.dev")
      create(:membership, :participant, company: company, user: u)
      u
    end
  end

  # `kind` sale de `challenge_step&.kind`, así que la fase de la sala la fija el
  # módulo al que apunta el vínculo.
  def sala(kind)
    challenge = create(:challenge)
    step = create(:challenge_step, challenge: challenge, kind: kind, status: "active")
    workshop = create(:workshop, status: "open")
    link = create(:workshop_challenge, workshop: workshop, challenge: challenge, challenge_step: step)
    group = create(:workshop_group, workshop: workshop)
    [ link, group, challenge ]
  end

  it "en una sala de evolución exige la idea" do
    as_company(company) do
      link, group, = sala("evolution")
      draft = WorkshopDraft.new(workshop_group: group, workshop_challenge: link,
                                idea: nil, updated_by: autora, payload: {})
      expect(draft).not_to be_valid
      expect(draft.errors[:idea_id].join).to include("evolución")
    end
  end

  it "en una sala de idear rechaza la idea" do
    as_company(company) do
      link, group, challenge = sala("ideation")
      idea = create(:idea, challenge: challenge, author: autora)
      draft = WorkshopDraft.new(workshop_group: group, workshop_challenge: link,
                                idea: idea, updated_by: autora, payload: {})
      expect(draft).not_to be_valid
      expect(draft.errors[:idea_id].join).to include("sólo")
    end
  end

  # El vínculo de un taller en borrador todavía no tiene módulo resuelto, así
  # que no hay fase contra la que comparar. La validación NO opina: lo que cierra
  # ese camino es el guarda `workable?` del controller, y hacer fallar acá la
  # convertiría en el segundo lugar que decide si una sala admite trabajo.
  it "sin módulo resuelto no opina" do
    as_company(company) do
      challenge = create(:challenge)
      workshop = create(:workshop, status: "draft")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge,
                                         challenge_step: nil)
      group = create(:workshop_group, workshop: workshop)
      draft = WorkshopDraft.new(workshop_group: group, workshop_challenge: link,
                                idea: nil, updated_by: autora, payload: {})
      expect(draft).to be_valid
    end
  end

  # El caso que DISCRIMINA el `return if kind.nil?`: con la idea presente, sin
  # ese `return` la rama de «no es evolución» rechazaría. Con la idea nil el
  # ejemplo de arriba pasa igual con o sin la línea.
  it "sin módulo resuelto no opina ni con la idea presente" do
    as_company(company) do
      challenge = create(:challenge)
      workshop = create(:workshop, status: "draft")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge,
                                         challenge_step: nil)
      group = create(:workshop_group, workshop: workshop)
      idea = create(:idea, challenge: challenge, author: autora)
      draft = WorkshopDraft.new(workshop_group: group, workshop_challenge: link,
                                idea: idea, updated_by: autora, payload: {})
      expect(draft).to be_valid
    end
  end

  it "rechaza una mesa y una sala de talleres distintos" do
    as_company(company) do
      link, = sala("ideation")
      _, otra_mesa, = sala("ideation")
      draft = WorkshopDraft.new(workshop_group: otra_mesa, workshop_challenge: link,
                                updated_by: autora, payload: {})
      expect(draft).not_to be_valid
      expect(draft.errors[:workshop_challenge_id].join).to include("otro taller")
    end
  end

  it "la factoría produce un registro válido" do
    as_company(company) do
      expect(build(:workshop_draft, updated_by: autora)).to be_valid
    end
  end

  it "rechaza una versión que es de otra idea" do
    as_company(company) do
      link, group, challenge = sala("evolution")
      mia = create(:idea, challenge: challenge, author: autora)
      ajena = create(:idea, challenge: challenge, author: autora)
      version = Flow::Ideas::PublishVersion.new(
        ajena, payload: { "titulo" => "x" }, author: autora
      ).call.version
      draft = WorkshopDraft.new(workshop_group: group, workshop_challenge: link,
                                idea: mia, based_on_version: version,
                                updated_by: autora, payload: {})
      expect(draft).not_to be_valid
      expect(draft.errors[:based_on_version_id].join).to include("otra idea")
    end
  end
end
