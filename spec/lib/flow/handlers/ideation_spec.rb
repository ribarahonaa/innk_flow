# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flow::Handlers::Ideation do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:challenge) { create(:challenge) }
  let!(:ideation) { challenge.steps.create!(kind: "ideation", position: 1) }
  let!(:evaluation) { challenge.steps.create!(kind: "evaluation", position: 2) }
  let(:handler) { described_class.new(ideation) }

  def author = Flow::Tenant.bypass! { create(:user) }

  def submitted_idea(title = "Idea")
    idea = create(:idea, challenge: challenge, author: author)
    Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => title }).call
    idea.update!(submitted_at: Time.current)
    idea
  end

  describe "#activate!" do
    it "siembra el formulario por defecto si nadie lo configuró" do
      handler.activate!

      expect(ideation.reload.form_fields.map(&:key)).to eq(%w[titulo problema solucion])
      expect(ideation.form_fields.first.config["is_title"]).to be(true)
    end

    it "respeta el formulario existente" do
      ideation.form_fields.create!(key: "propio", label: "Campo propio")
      handler.activate!

      expect(ideation.reload.form_fields.map(&:key)).to eq(%w[propio])
    end

    it "arranca con el cohorte VACÍO: las ideas nacen acá, no llegan de antes" do
      handler.activate!
      expect(ideation.reload.step_entries).to be_empty
    end
  end

  describe "#can_complete?" do
    before { handler.activate! }

    it "exige el mínimo de ideas postuladas" do
      ideation.update!(resolved_config: { "min_ideas" => 2 })

      ready, reasons = described_class.new(ideation.reload).can_complete?
      expect(ready).to be(false)
      expect(reasons.join).to match(/al menos 2 ideas postuladas \(hay 0\)/)

      2.times { submitted_idea }
      ready, = described_class.new(ideation.reload).can_complete?
      expect(ready).to be(true)
    end

    it "no cuenta los borradores sin postular" do
      ideation.update!(resolved_config: { "min_ideas" => 1 })
      create(:idea, challenge: challenge, author: author)

      ready, = described_class.new(ideation.reload).can_complete?
      expect(ready).to be(false)
    end
  end

  describe "#complete!" do
    before { handler.activate! }

    it "pasa las postuladas a activas y les cierra la entry" do
      idea = submitted_idea("Sensores")

      described_class.new(ideation.reload).complete!

      expect(idea.reload).to be_active
      entry = StepEntry.find_by(challenge_step_id: ideation.id, idea_id: idea.id)
      expect(entry.status).to eq("advanced")
      expect(entry.output_version_id).to eq(idea.current_version_id)
    end

    it "retira los borradores que nunca se postularon" do
      draft = create(:idea, challenge: challenge, author: author)
      submitted_idea

      described_class.new(ideation.reload).complete!

      expect(draft.reload).to be_withdrawn
      expect(challenge.ideas.alive.count).to eq(1)
    end
  end

  describe "el cohorte del módulo siguiente" do
    it "recibe solo las ideas activas, y las entries se crean al activarlo" do
      handler.activate!
      idea = submitted_idea
      create(:idea, challenge: challenge, author: author) # borrador, no debería pasar
      described_class.new(ideation.reload).complete!

      expect(evaluation.step_entries).to be_empty

      Flow::Handlers::Base.for(evaluation).activate!

      expect(evaluation.reload.step_entries.count).to eq(1)
      entry = evaluation.step_entries.first
      expect(entry.idea_id).to eq(idea.id)
      expect(entry.input_version_id).to eq(idea.reload.current_version_id)
    end

    it "una idea eliminada NO genera fila en el módulo siguiente" do
      # Es lo que hace que step_entries signifique "participación real" y que
      # los reportes sean COUNT(*) sin condiciones que alguien pueda olvidar.
      handler.activate!
      alive = submitted_idea("Sigue")
      dead = submitted_idea("Se cae")
      described_class.new(ideation.reload).complete!
      dead.update!(status: "eliminated")

      Flow::Handlers::Base.for(evaluation).activate!

      expect(evaluation.reload.step_entries.map(&:idea_id)).to eq([alive.id])
    end

    it "Cohort.sync! es idempotente: es lo que permite la repesca" do
      handler.activate!
      idea = submitted_idea
      described_class.new(ideation.reload).complete!
      Flow::Handlers::Base.for(evaluation).activate!

      expect { Flow::Cohort.sync!(evaluation) }.not_to change { evaluation.step_entries.count }

      repescada = submitted_idea("Repescada")
      repescada.update!(status: "active")
      expect { Flow::Cohort.sync!(evaluation) }.to change { evaluation.step_entries.count }.by(1)
      expect(evaluation.step_entries.map(&:idea_id)).to include(idea.id, repescada.id)
    end
  end
end
