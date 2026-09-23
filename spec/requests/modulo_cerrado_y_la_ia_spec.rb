# frozen_string_literal: true

require "rails_helper"

# Un módulo que ya cerró no sigue aceptando el trabajo de su IA.
#
# La regla la declara cada tarea (`requires_active_step?`) y la consultan las
# tres puertas, que es lo que impide que vuelva a divergir: el partial que
# dibuja los botones, la policy que autoriza el pedido —y el aceptar tardío de
# una propuesta que quedó pendiente— y el lote de evaluación, que no pasa por
# el partial.
#
# Estaba escrita A MANO en cada llamador de `shared/_ai_actions`: cuatro de los
# ocho la tenían y dos se la olvidaron. El que más dolía era generar ideas, que
# las CREA y las postula: `Flow::Cohort.sync!` arma las `step_entries` al
# activar el módulo, así que una idea que entra después no tiene fila en ningún
# lado.
RSpec.describe "la IA y un módulo cerrado", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def miembro(email, rol)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, company: company, user: u, role: rol)
      u
    end
  end

  let!(:admin) { miembro("admin@test.dev", "admin") }

  before { sign_in(admin, company: company) }

  def cerrar!(paso)
    as_company(company) { paso.reload.update!(status: "completed", completed_at: Time.current) }
  end

  describe "generar ideas candidatas" do
    let!(:challenge) do
      as_company(company) do
        c = create(:challenge, name: "Merma", ai_default_mode: "ai_assisted")
        seed_form!(c.steps.create!(kind: "ideation", position: 1, name: "Postulación"))
        c.pipeline.start!
        c
      end
    end

    let(:paso) { as_company(company) { challenge.steps.reload.find(&:ideation?) } }

    it "con el módulo abierto la pantalla lo ofrece" do
      get challenge_step_path(challenge, paso)

      expect(response.body).to include("Generar ideas candidatas")
    end

    it "y con el módulo cerrado ya no" do
      cerrar!(paso)

      get challenge_step_path(challenge, paso)

      expect(response.body).not_to include("Generar ideas candidatas")
    end

    it "y si lo postea igual, no crea ninguna idea" do
      cerrar!(paso)

      expect do
        post challenge_ai_requests_path(challenge, purpose: "generate_ideas",
                                        step_id: paso.id, count: 2)
      end.not_to change { as_company(company) { Idea.count } }

      expect(response).to have_http_status(:forbidden)
    end

    # Pedir y aceptar son el mismo método, así que la guarda alcanza a una
    # propuesta que nació con el módulo abierto y se acepta después de que
    # cerró: las ideas entrarían igual de huérfanas.
    it "ni aplica una propuesta que quedó pendiente de cuando estaba abierto" do
      post challenge_ai_requests_path(challenge, purpose: "generate_ideas",
                                      step_id: paso.id, count: 2)
      sugerencia = as_company(company) { AiSuggestion.pending_review.order(:created_at).last }
      cerrar!(paso)

      expect do
        post accept_ai_suggestion_path(sugerencia)
      end.not_to change { as_company(company) { Idea.count } }
    end
  end

  describe "sugerir feedback" do
    let!(:autora) { miembro("autora@test.dev", "participant") }

    let!(:challenge) do
      as_company(company) do
        c = create(:challenge, name: "Merma", ai_default_mode: "ai_assisted")
        seed_form!(c.steps.create!(kind: "ideation", position: 1))
        c.steps.create!(kind: "evolution", position: 2, name: "Ronda de feedback")
        c.pipeline.start!
        c
      end
    end

    let(:paso) { as_company(company) { challenge.steps.find_by!(kind: "evolution") } }

    let!(:idea) do
      as_company(company) do
        i = create(:idea, challenge: challenge, author: autora, status: "active")
        Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" }, author: autora).call
        i.update!(submitted_at: Time.current)
        i
      end
    end

    before { as_company(company) { challenge.pipeline.advance! } }

    it "con la ronda abierta la pantalla lo ofrece" do
      get challenge_step_path(challenge, paso)

      expect(response.body).to include("Sugerir feedback con IA")
    end

    # El feedback pertenece a su ronda: un comentario archivado en una
    # conversación cerrada se lee como lo que hay que atender ahora.
    it "y con la ronda cerrada ya no" do
      cerrar!(paso)

      get challenge_step_path(challenge, paso)

      expect(response.body).not_to include("Sugerir feedback con IA")
    end

    it "y si lo postea igual, no escribe ningún comentario" do
      cerrar!(paso)

      expect do
        post challenge_ai_requests_path(challenge, purpose: "suggest_feedback",
                                        step_id: paso.id, idea_id: idea.id)
      end.not_to change { as_company(company) { FeedbackItem.count } }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "evaluar todas con IA" do
    let!(:autora) { miembro("autora@test.dev", "participant") }

    let!(:challenge) do
      as_company(company) do
        c = create(:challenge, name: "Merma", ai_default_mode: "ai_assisted")
        seed_form!(c.steps.create!(kind: "ideation", position: 1, status: "completed"))
        c.steps.create!(kind: "evaluation", position: 2, name: "Comité", ai_mode: "ai_assisted")
        c.update!(status: "running")
        c
      end
    end

    let(:paso) { as_company(company) { challenge.steps.find_by!(kind: "evaluation") } }

    before do
      as_company(company) do
        i = create(:idea, challenge: challenge, author: autora, status: "active")
        Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" }, author: autora).call
        i.update!(submitted_at: Time.current)
        Flow::Handlers::Base.for(paso).activate!
      end
    end

    it "con el módulo abierto encola las corridas" do
      expect do
        post evaluate_all_challenge_step_path(challenge, paso)
      end.to change { enqueued_jobs.count { |j| j[:job] == Flow::AI::RunJob } }
    end

    # El lote no pasa por `shared/_ai_actions`, así que necesita su propia
    # consulta a la misma regla.
    it "y con el módulo cerrado no encola ninguna" do
      cerrar!(paso)

      expect do
        post evaluate_all_challenge_step_path(challenge, paso)
      end.not_to change { enqueued_jobs.count { |j| j[:job] == Flow::AI::RunJob } }
    end
  end

  # Los dos controles negativos. Sin ellos la guarda se puede escribir de más
  # —tapando lo que se ofrece a propósito fuera del trabajo del módulo— y nada
  # avisa.
  describe "lo que NO tapa" do
    let!(:autora) { miembro("autora@test.dev", "participant") }

    let!(:challenge) do
      as_company(company) do
        c = create(:challenge, name: "Merma", brief: "Reducir merma.", ai_default_mode: "ai_assisted")
        seed_form!(c.steps.create!(kind: "ideation", position: 1))
        c.steps.create!(kind: "evolution", position: 2)
        c.pipeline.start!
        c
      end
    end

    let(:ideacion) { as_company(company) { challenge.steps.find_by!(kind: "ideation") } }

    let!(:idea) do
      as_company(company) do
        i = create(:idea, challenge: challenge, author: autora, status: "active")
        Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" }, author: autora).call
        i.update!(submitted_at: Time.current)
        i
      end
    end

    # Comparar no edita nada: se pide para decidir qué se fusiona, haya o no
    # una ronda abierta.
    it "detectar duplicados sigue disponible con la ideación cerrada" do
      cerrar!(ideacion)

      expect do
        post challenge_ai_requests_path(challenge, purpose: "detect_duplicates",
                                        step_id: ideacion.id, idea_id: idea.id)
      end.to change { as_company(company) { AiRun.count } }.by(1)
    end

    # Las tareas de AUTORÍA se ofrecen a propósito fuera del trabajo del
    # módulo: definen cómo se trabaja DENTRO del desafío, no si su dueño puede
    # pedir una mano para diseñarlo.
    it "y proponer los campos del formulario también" do
      cerrar!(ideacion)

      expect do
        post challenge_ai_requests_path(challenge, purpose: "suggest_form_fields",
                                        step_id: ideacion.id)
      end.to change { as_company(company) { AiRun.count } }.by(1)
    end
  end
end
