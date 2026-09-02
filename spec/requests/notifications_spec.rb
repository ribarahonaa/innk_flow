# frozen_string_literal: true

require "rails_helper"

# Los avisos.
#
# Un proceso repartido entre personas y de semanas no puede depender de que
# cada una se acuerde de entrar a mirar. Hasta acá no había un solo aviso.
RSpec.describe "avisos", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email, role = nil)
    without_tenant do
      u = create(:user, email: email)
      role ? create(:membership, role.to_sym, company: company, user: u) : create(:membership, company: company, user: u)
      u
    end
  end

  let!(:owner) { member("owner@test.dev", :owner) }
  let!(:autora) { member("autora@test.dev") }
  let!(:colega) { member("colega@test.dev") }

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma")
      seed_form!(c.steps.create!(kind: "ideation", position: 1, name: "Postulación"))
      c.steps.create!(kind: "evolution", position: 2, name: "Ronda de feedback")
      c.steps.create!(kind: "evaluation", position: 3, name: "Técnica")
      c.steps.create!(kind: "selection", position: 4, name: "Corte",
                      config: { "cut" => { "mode" => "top_n", "value" => 1 } })
      c
    end
  end

  def step_named(name) = as_company(company) { challenge.steps.reload.find_by(name: name) }
  def notifications_for(user) = as_company(company) { Notification.where(user_id: user.id).recent.to_a }

  def crear_idea(titulo, author)
    as_company(company) do
      idea = create(:idea, challenge: challenge, author: author)
      Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => titulo }, author: author).call
      idea.update!(submitted_at: Time.current)
      idea
    end
  end

  describe "te toca evaluar" do
    it "al abrir la evaluación se avisa a quien tiene que evaluar" do
      crear_idea("Sensores", autora)

      as_company(company) do
        challenge.pipeline.start!
        challenge.pipeline.advance!  # → evolución
        challenge.pipeline.advance!  # → evaluación
      end

      as_company(company) do
        aviso = Notification.where(user_id: owner.id).recent.first
        expect(aviso.kind).to eq("assigned_to_evaluate")
        expect(aviso.title).to include("Técnica")
        expect(aviso.path).to eq(challenge_step_path(challenge, step_named("Técnica")))
      end
    end
  end

  describe "tu idea recibió feedback" do
    let!(:idea) { crear_idea("Sensores", autora) }

    before do
      as_company(company) do
        IdeaContributor.create!(idea: idea, user: colega, role: "contributor")
        challenge.pipeline.start!
        challenge.pipeline.advance!
      end
    end

    it "le llega a quien la creó y a quienes participan" do
      as_company(company) do
        FeedbackItem.create!(challenge_step: step_named("Ronda de feedback"), idea: idea,
                             idea_version_id: idea.current_version_id, author: owner,
                             actor_type: "human", kind: "suggestion", body: "Acotá el piloto.")
      end

      expect(notifications_for(autora).map(&:kind)).to eq(%w[feedback_received])
      expect(notifications_for(colega).map(&:kind)).to eq(%w[feedback_received])
      expect(notifications_for(autora).first.body).to include(owner.name)
    end

    # Avisarle a alguien de su propio comentario es ruido.
    it "pero no a quien lo escribió, aunque participe de la idea" do
      as_company(company) do
        FeedbackItem.create!(challenge_step: step_named("Ronda de feedback"), idea: idea,
                             idea_version_id: idea.current_version_id, author: colega,
                             actor_type: "human", kind: "suggestion", body: "Me respondo solo.")
      end

      expect(notifications_for(colega)).to be_empty
      expect(notifications_for(autora).size).to eq(1)
    end

    # Repetir lo mismo mientras lo primero sigue sin leerse entrena a la gente
    # a ignorar la campana.
    it "dos comentarios seguidos no generan dos avisos sin leer" do
      2.times do |n|
        as_company(company) do
          FeedbackItem.create!(challenge_step: step_named("Ronda de feedback"), idea: idea,
                               idea_version_id: idea.current_version_id, author: owner,
                               actor_type: "human", kind: "suggestion", body: "Comentario #{n}")
        end
      end

      expect(notifications_for(autora).size).to eq(1)
    end

    it "pero después de leerlo sí: pasó otra vez" do
      as_company(company) do
        FeedbackItem.create!(challenge_step: step_named("Ronda de feedback"), idea: idea,
                             idea_version_id: idea.current_version_id, author: owner,
                             actor_type: "human", kind: "suggestion", body: "Primero")
        Notification.where(user_id: autora.id).find_each(&:read!)
        FeedbackItem.create!(challenge_step: step_named("Ronda de feedback"), idea: idea,
                             idea_version_id: idea.current_version_id, author: owner,
                             actor_type: "human", kind: "suggestion", body: "Segundo")
      end

      expect(notifications_for(autora).size).to eq(2)
    end
  end

  describe "tu idea avanzó o quedó fuera" do
    it "avisa el resultado del corte a quien la creó" do
      buena = crear_idea("Sensores", autora)
      mala = crear_idea("Cámaras", colega)

      as_company(company) do
        challenge.pipeline.start!
        challenge.pipeline.advance!  # cierra «Idear»: las ideas quedan activas

        seleccion = challenge.steps.reload.find_by(name: "Corte")
        seleccion.handler.activate!
        seleccion.handler.decide!([buena.id], decided_by: owner)
      end

      expect(notifications_for(autora).map(&:kind)).to include("idea_advanced")
      expect(notifications_for(colega).map(&:kind)).to include("idea_eliminated")
      expect(notifications_for(colega).first.body).to include("puede repescarse")
    end
  end

  describe "la bandeja" do
    let!(:idea) { crear_idea("Sensores", autora) }

    before do
      as_company(company) do
        challenge.pipeline.start!
        challenge.pipeline.advance!
        FeedbackItem.create!(challenge_step: step_named("Ronda de feedback"), idea: idea,
                             idea_version_id: idea.current_version_id, author: owner,
                             actor_type: "human", kind: "suggestion", body: "Acotá el piloto.")
      end
      sign_in(autora, company: company)
    end

    it "la campana muestra cuántos hay sin leer" do
      get challenge_path(challenge)
      expect(response.body).to include('class="bell__count"')
    end

    it "los lista" do
      get notifications_path
      expect(response.body).to include("recibió un comentario", owner.name)
    end

    # El aviso es un atajo, no un destino: lleva a donde se hace algo con él.
    it "abrir uno lo marca leído y lleva a la idea" do
      aviso = notifications_for(autora).first

      get notification_path(aviso)

      expect(response).to redirect_to(challenge_idea_path(challenge, idea))
      expect(as_company(company) { Notification.find(aviso.id) }).to be_read
    end

    it "se pueden marcar todos de una" do
      post read_all_notifications_path
      expect(as_company(company) { Notification.where(user_id: autora.id).unread.count }).to eq(0)
    end

    it "los avisos de otra persona no se ven ni se abren" do
      ajeno = notifications_for(autora).first
      sign_in(colega, company: company)

      get notification_path(ajeno)
      expect(response).to have_http_status(:not_found)
    end
  end
end
