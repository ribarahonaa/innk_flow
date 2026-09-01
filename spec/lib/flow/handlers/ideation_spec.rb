# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flow::Handlers::Ideation do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:challenge) { create(:challenge) }
  let!(:ideation) { seed_form!(challenge.steps.create!(kind: "ideation", position: 1)) }
  let!(:evaluation) { challenge.steps.create!(kind: "evaluation", position: 2) }
  let(:handler) { described_class.new(ideation) }

  def author = Flow::Tenant.bypass! { create(:user) }

  def submitted_idea(title = "Idea")
    idea = create(:idea, challenge: challenge, author: author)
    Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => title }).call
    idea.update!(submitted_at: Time.current)
    idea
  end

  describe "#can_activate?" do
    # ANTES: si nadie había configurado el formulario, `activate!` sembraba tres
    # campos por defecto. El dueño del desafío no veía nunca sus propias
    # preguntas: nacían con el desafío ya corriendo, cuando la ventana para
    # cambiarlas ya se había cerrado. Ahora se niega a abrir vacío.
    it "no deja arrancar un módulo sin formulario" do
      otro = create(:challenge)
      vacio = otro.steps.create!(kind: "ideation", position: 1)
      ok, errors = described_class.new(vacio).can_activate?

      expect(ok).to be(false)
      expect(errors.join).to include("no tiene formulario")
    end

    it "y no lo inventa: el formulario queda como lo dejó su dueño" do
      handler.activate!

      expect(ideation.reload.form_fields.map(&:key)).to eq(%w[titulo problema solucion])
    end
  end

  describe "#activate!" do
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
RSpec.describe "«Idear» con IA automática" do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let!(:owner) do
    without_tenant do
      user = create(:user)
      create(:membership, :owner, company: company, user: user)
      user
    end
  end
  let(:challenge) { create(:challenge, brief: "Reducir la merma en bodega.") }

  def ideation_with(mode)
    step = seed_form!(challenge.steps.create!(kind: "ideation", position: 1, ai_mode: mode))
    Flow::Handlers::Base.for(step).activate!
    step.reload
  end

  it "en ai_auto genera las ideas al abrir el módulo" do
    expect { ideation_with("ai_auto") }
      .to have_enqueued_job(Flow::AI::RunJob)
      .with(company.id, "generate_ideas", hash_including("count" => 5))
  end

  it "en ai_assisted NO las genera sola: la IA acompaña a quien postula" do
    expect { ideation_with("ai_assisted") }.not_to have_enqueued_job(Flow::AI::RunJob)
  end

  it "en human no llama al proveedor" do
    expect { ideation_with("human") }.not_to have_enqueued_job(Flow::AI::RunJob)
  end

  it "no vuelve a generarlas si el módulo se reactiva" do
    step = ideation_with("ai_auto")
    idea = create(:idea, challenge: challenge, author: owner, origin: "ai")
    Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => "Ya generada" }).call

    expect { Flow::Handlers::Base.for(step).send(:on_activate) }
      .not_to have_enqueued_job(Flow::AI::RunJob)
  end

  it "las ideas generadas quedan postuladas y marcadas como de IA" do
    step = ideation_with("ai_auto")
    perform_enqueued_jobs

    ideas = challenge.ideas.reload
    expect(ideas.count).to eq(5)
    expect(ideas.map(&:origin).uniq).to eq(%w[ai])
    expect(ideas.map(&:submitted_at)).to all(be_present)
    expect(ideas.first.current_version).to be_by_ai
  end
end
