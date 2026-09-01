# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flow::Handlers::Evolution do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:author) { without_tenant { create(:user, name: "Ana Autora") } }
  let(:reviewer) { without_tenant { create(:user, name: "Raúl Revisor") } }

  let(:challenge) { create(:challenge, ai_default_mode: "human") }
  let!(:ideation) { seed_form!(challenge.steps.create!(kind: "ideation", position: 1)) }
  let!(:step) { challenge.steps.create!(kind: "evolution", position: 2, name: "Ronda de feedback") }

  let!(:idea) do
    i = create(:idea, challenge: challenge, author: author, status: "active")
    Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores", "solucion" => "Poner sensores" },
                                       author: author).call
    i.update!(submitted_at: Time.current)
    i
  end

  let(:handler) { Flow::Handlers::Base.for(step).tap(&:activate!) && described_class.new(step.reload) }

  def give_feedback(body: "Falta el costo", kind: "question")
    FeedbackItem.create!(challenge_step: step, idea: idea, idea_version_id: idea.reload.current_version_id,
                         author: reviewer, kind: kind, body: body)
  end

  describe "el ciclo feedback → versión" do
    it "el feedback se ancla a la versión que se leyó" do
      handler
      item = give_feedback

      expect(item.idea_version_id).to eq(idea.current_version_id)
      expect(item).not_to be_stale
    end

    it "publicar una versión nueva marca el feedback como atendido" do
      handler
      item = give_feedback

      version = Flow::Ideas::PublishVersion.new(
        idea, payload: { "titulo" => "Sensores", "solucion" => "Poner sensores. Costo: 8 celdas." },
        author: author, source_step: step, change_note: "Agregué el costo"
      ).call.version

      handler.record_response!(idea, version)

      expect(item.reload).to be_addressed
      expect(item.addressed_by_version_id).to eq(version.id)
    end

    it "cierra la entry con la versión que la respondió" do
      handler
      give_feedback
      version = Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => "Otra cosa" },
                                                      author: author, source_step: step).call.version

      handler.record_response!(idea, version)

      entry = step.step_entries.find_by(idea_id: idea.id)
      expect(entry.status).to eq("done")
      expect(entry.output_version_id).to eq(version.id)
      expect(entry.input_version_id).not_to eq(version.id), "la entry conserva con qué versión entró"
    end

    it "el feedback sobre una versión vieja se marca desactualizado" do
      handler
      item = give_feedback
      Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => "Cambiada" }, author: author).call

      expect(item.reload).to be_stale
    end
  end

  describe "progreso" do
    it "cuenta las ideas que publicaron versión desde este módulo" do
      handler
      expect(handler.progress.done).to eq(0)

      version = Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => "Nueva" },
                                                      author: author, source_step: step).call.version
      handler.record_response!(idea, version)

      expect(described_class.new(step.reload).progress.done).to eq(1)
    end
  end

  describe "#complete!" do
    it "el feedback sin atender NO bloquea el cierre, queda registrado" do
      handler
      give_feedback

      ready, = handler.can_complete?
      expect(ready).to be(true)

      handler.complete!

      expect(FeedbackItem.open_ones.count).to eq(1)
      expect(step.step_entries.first.reload.status).to eq("advanced")
    end

    it "con require_response sí exige que todas respondan" do
      handler
      step.update!(resolved_config: step.resolved_config.merge("require_response" => true))

      ready, reasons = described_class.new(step.reload).can_complete?
      expect(ready).to be(false)
      expect(reasons.join).to match(/sin responder al feedback/)
    end
  end

  describe "con IA" do
    it "encola una llamada por idea al activarse" do
      challenge.update!(ai_default_mode: "ai_assisted")

      expect { Flow::Handlers::Base.for(step).activate! }
        .to have_enqueued_job(Flow::AI::RunJob).at_least(:once)
    end

    it "no llama al proveedor en modo human" do
      expect { Flow::Handlers::Base.for(step).activate! }
        .not_to have_enqueued_job(Flow::AI::RunJob)
    end

    it "la tarea de IA crea items de feedback" do
      task = Flow::AI::Tasks::SuggestFeedback.new(challenge: challenge, step: step, idea: idea)
      Flow::Handlers::Base.for(step).activate!

      expect { Flow::AI::Runner.call(task, mode: "ai_auto", challenge: challenge, step: step, idea: idea) }
        .to change { FeedbackItem.count }.by(3)

      expect(FeedbackItem.pluck(:kind)).to match_array(%w[question suggestion issue])
      expect(FeedbackItem.first).to be_by_ai
    end
  end

  describe "el círculo completo con una evaluación" do
    it "evaluar → feedback → versión nueva deja la evaluación anclada y marcada" do
      evaluation = challenge.steps.create!(kind: "evaluation", position: 3)
      assessment = evaluation.assessments.create!(
        idea: idea, idea_version_id: idea.current_version_id,
        evaluator: reviewer, status: "submitted", normalized_score: 0.8
      )
      expect(assessment).not_to be_stale

      handler
      give_feedback
      version = Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => "Mejorada" },
                                                      author: author, source_step: step).call.version
      handler.record_response!(idea, version)

      # La nota NO se borra ni se invalida: queda anclada a la versión que
      # juzgó, y la UI puede decir "evaluada sobre v1, la idea ya va por v2".
      expect(assessment.reload.normalized_score.to_f).to eq(0.8)
      expect(assessment).to be_stale
      expect(assessment.idea_version_id).not_to eq(idea.reload.current_version_id)
    end
  end
end
