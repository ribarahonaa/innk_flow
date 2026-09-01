# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ideas", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }
  let!(:owner) do
    without_tenant do
      u = create(:user, email: "owner@test.dev", name: "Olga Owner")
      create(:membership, :owner, company: company, user: u)
      u
    end
  end
  let!(:participant) do
    without_tenant do
      u = create(:user, email: "part@test.dev", name: "Pablo Participante")
      create(:membership, company: company, user: u, role: "participant")
      u
    end
  end

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma en bodega")
      seed_form!(c.steps.create!(kind: "ideation", position: 1, name: "Postulación"))
      c.steps.create!(kind: "evaluation", position: 2, name: "Evaluación")
      c.pipeline.start!
      c
    end
  end

  def ideation = as_company(company) { challenge.steps.find_by(kind: "ideation") }

  describe "postular" do
    before { sign_in(participant, company: company) }

    it "muestra el formulario con los campos del módulo" do
      get new_challenge_idea_path(challenge)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Título", "¿Qué problema resuelve?", "¿Cómo funcionaría?")
    end

    it "crea la idea como borrador con su v1" do
      post challenge_ideas_path(challenge), params: {
        payload: { titulo: "Sensores IoT", problema: "No sabemos dónde se pierde", solucion: "Sensores por rack" }
      }

      as_company(company) do
        idea = Idea.last
        expect(idea).to be_draft
        expect(idea.author_id).to eq(participant.id)
        expect(idea.versions.count).to eq(1)
        expect(idea.title).to eq("Sensores IoT")
        expect(response).to redirect_to(challenge_idea_path(challenge, idea))
      end
    end

    it "descarta claves que no son campos del formulario" do
      post challenge_ideas_path(challenge), params: {
        payload: { titulo: "T", inyectado: "no debería quedar" }
      }

      as_company(company) do
        expect(Idea.last.payload.keys).to eq(%w[titulo])
      end
    end
  end

  describe "editar publica una versión nueva" do
    let(:idea) do
      as_company(company) do
        i = create(:idea, challenge: challenge, author: participant)
        Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Original" }, author: participant).call
        i
      end
    end

    before { sign_in(participant, company: company) }

    it "no pisa: crea v2 y deja v1 en el historial" do
      patch challenge_idea_path(challenge, idea), params: {
        payload: { titulo: "Corregido" }, change_note: "Ajusté el alcance"
      }

      as_company(company) do
        idea.reload
        expect(idea.versions.count).to eq(2)
        expect(idea.versions.map(&:title)).to eq(%w[Original Corregido])
        expect(idea.current_version.label).to eq("v2")
        expect(idea.current_version.change_note).to eq("Ajusté el alcance")
      end
    end

    it "el historial se ve en el detalle" do
      patch challenge_idea_path(challenge, idea), params: { payload: { titulo: "Corregido" } }
      get challenge_idea_path(challenge, idea)

      expect(response.body).to include("v1", "v2", "Historial")
    end

    it "el diff muestra el campo que cambió" do
      patch challenge_idea_path(challenge, idea), params: { payload: { titulo: "Corregido" } }
      versions = as_company(company) { idea.reload.versions.chronological.to_a }

      get diff_challenge_idea_path(challenge, idea, a: versions.first.id, b: versions.last.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Original", "Corregido", "modificado")
    end
  end

  describe "autorización" do
    let(:idea) do
      as_company(company) do
        i = create(:idea, challenge: challenge, author: participant)
        Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "De Pablo" }).call
        i
      end
    end

    it "otro participante NO puede editar una idea ajena" do
      otro = without_tenant do
        u = create(:user, email: "otro@test.dev")
        create(:membership, company: company, user: u, role: "participant")
        u
      end
      sign_in(otro, company: company)

      get edit_challenge_idea_path(challenge, idea)
      expect(response).to have_http_status(:forbidden)
    end

    it "el autor SÍ puede editar durante una ronda de evolución" do
      # Es la razón de ser del módulo: responder al feedback actualizando la
      # idea. Sin esto, «Evolución» no sirve para nada.
      as_company(company) do
        idea.update!(submitted_at: Time.current, status: "active")
        challenge.steps.create!(kind: "evolution", position: 3, name: "Ronda", status: "active")
        challenge.steps.find_by(kind: "ideation").update!(status: "completed")
      end
      sign_in(participant, company: company)

      get edit_challenge_idea_path(challenge, idea)
      expect(response).to have_http_status(:ok)
    end

    it "el autor NO puede editar una vez postulada" do
      as_company(company) { idea.update!(submitted_at: Time.current, status: "active") }
      sign_in(participant, company: company)

      get edit_challenge_idea_path(challenge, idea)
      expect(response).to have_http_status(:forbidden)
    end

    it "un gestor sí puede" do
      as_company(company) { idea.update!(submitted_at: Time.current, status: "active") }
      sign_in(owner, company: company)

      get edit_challenge_idea_path(challenge, idea)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "pantalla del módulo" do
    before { sign_in(owner, company: company) }

    it "muestra el formulario declarado, el progreso y las ideas" do
      as_company(company) do
        i = create(:idea, challenge: challenge, author: participant)
        Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" }).call
        i.update!(submitted_at: Time.current)
      end

      get challenge_step_path(challenge, ideation)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Formulario de postulación", "Ideas postuladas", "Sensores")
    end

    it "avanzar cierra el módulo y activa el siguiente" do
      as_company(company) do
        i = create(:idea, challenge: challenge, author: participant)
        Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" }).call
        i.update!(submitted_at: Time.current)
      end

      post advance_challenge_step_path(challenge, ideation)

      as_company(company) do
        expect(challenge.steps.find_by(kind: "ideation")).to be_completed
        expect(challenge.steps.find_by(kind: "evaluation")).to be_active
      end
    end
  end

  describe "aislamiento entre empresas" do
    it "una idea de otra empresa da 404" do
      other = without_tenant { create(:company, slug: "otra") }
      foreign_challenge = as_company(other) do
        c = create(:challenge)
        seed_form!(c.steps.create!(kind: "ideation", position: 1))
        c
      end
      foreign_idea = as_company(other) { create(:idea, challenge: foreign_challenge) }

      sign_in(owner, company: company)
      get challenge_idea_path(foreign_challenge, foreign_idea)
      expect(response).to have_http_status(:not_found)
    end
  end
end
