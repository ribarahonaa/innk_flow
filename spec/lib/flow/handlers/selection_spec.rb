# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flow::Handlers::Selection do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:decider) { without_tenant { create(:user) } }
  let(:challenge) { create(:challenge) }

  # ideation → evaluación técnica → evaluación de comité → selección
  let!(:ideation) { challenge.steps.create!(kind: "ideation", position: 1, slug: "ideation") }
  let!(:tecnica)  { challenge.steps.create!(kind: "evaluation", position: 2, slug: "eval_tecnica", name: "Técnica") }
  let!(:comite)   { challenge.steps.create!(kind: "evaluation", position: 3, slug: "eval_comite", name: "Comité") }

  # Cinco ideas con puntajes conocidos en cada evaluación.
  let!(:ideas) do
    %w[A B C D E].map.with_index do |letter, index|
      idea = create(:idea, challenge: challenge, status: "active")
      Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => "Idea #{letter}" }).call
      idea.update!(submitted_at: Time.current)

      tecnica.step_entries.create!(idea: idea, status: "done", result: { "score" => 1.0 - (index * 0.2) })
      comite.step_entries.create!(idea: idea, status: "done", result: { "score" => index * 0.2 })
      idea
    end
  end

  def build_selection(config)
    step = challenge.steps.create!(kind: "selection", position: 4, name: "Corte", config: config)
    challenge.update!(status: "running")
    tecnica.update!(status: "completed")
    comite.update!(status: "completed")
    Flow::Handlers::Base.for(step).activate!
    step.reload
    described_class.new(step)
  end

  describe "de qué evaluación toma el puntaje" do
    it "por defecto: la evaluación completada MÁS CERCANA hacia atrás" do
      handler = build_selection({})

      expect(handler.source_steps.map(&:slug)).to eq(%w[eval_comite])
      expect(handler.ranking.first.idea.title).to eq("Idea E") # mejor en comité
    end

    it "puede combinar dos evaluaciones con pesos" do
      handler = build_selection(
        "score_source" => { "type" => "steps", "step_slugs" => %w[eval_tecnica eval_comite],
                            "combine" => "weighted_avg",
                            "weights" => { "eval_tecnica" => 0.6, "eval_comite" => 0.4 } }
      )

      expect(handler.source_steps.map(&:slug)).to eq(%w[eval_tecnica eval_comite])
      # A: 1.0*.6 + 0.0*.4 = 0.6   ·   E: 0.2*.6 + 0.8*.4 = 0.44
      expect(handler.ranking.first.idea.title).to eq("Idea A")
      expect(handler.ranking.first.score).to be_within(0.001).of(0.6)
    end

    it "CONGELA la fuente al activar: reordenar después no la cambia" do
      handler = build_selection({})
      expect(handler.step.settings.dig("score_source", "step_slugs")).to eq(%w[eval_comite])

      # Aunque cambie el pipeline, la decisión ya está tomada con ids.
      expect(handler.step.settings.dig("score_source", "step_ids")).to eq([comite.id])
      expect(handler.step.settings.dig("score_source", "resolved_at")).to be_present
    end

    it "no se puede activar sin una evaluación previa" do
      solo = create(:challenge)
      solo.steps.create!(kind: "ideation", position: 1)
      step = solo.steps.create!(kind: "selection", position: 2)

      ready, reasons = described_class.new(step).can_activate?
      expect(ready).to be(false)
      expect(reasons.join).to match(/no tiene ninguna evaluación previa/)
    end
  end

  describe "reglas de corte" do
    it "top_n deja pasar las N mejores" do
      handler = build_selection("cut" => { "mode" => "top_n", "value" => 2 })
      above = handler.ranking.select(&:above_cut?)

      expect(above.size).to eq(2)
      expect(above.map { _1.idea.title }).to eq(["Idea E", "Idea D"])
    end

    it "top_percent redondea hacia arriba" do
      handler = build_selection("cut" => { "mode" => "top_percent", "value" => 50 })
      expect(handler.ranking.count(&:above_cut?)).to eq(3) # ceil(5 * 0.5)
    end

    it "threshold corta por puntaje mínimo" do
      handler = build_selection("cut" => { "mode" => "threshold", "value" => 0.5 })
      above = handler.ranking.select(&:above_cut?)

      expect(above.map { _1.score }).to all(be >= 0.5)
    end

    it "manual no propone corte: decide una persona" do
      handler = build_selection("cut" => { "mode" => "manual" })
      expect(handler.ranking).to all(be_above_cut)

      ready, reasons = handler.can_complete?
      expect(ready).to be(false)
      expect(reasons.join).to match(/Falta decidir sobre 5 ideas/)
    end
  end

  describe "#decide!" do
    let(:handler) { build_selection("cut" => { "mode" => "top_n", "value" => 2 }) }

    it "escribe el log y actualiza el estado en una transacción" do
      winners = handler.ranking.select(&:above_cut?).map { _1.idea.id }
      handler.decide!(winners, decided_by: decider, reason: "Corte del comité")

      expect(SelectionDecision.count).to eq(5)
      expect(SelectionDecision.where(outcome: "advance").count).to eq(2)
      expect(SelectionDecision.where(outcome: "eliminate").count).to eq(3)

      advanced = SelectionDecision.where(outcome: "advance").first
      expect(advanced.decided_by_id).to eq(decider.id)
      expect(advanced.reason).to eq("Corte del comité")
      expect(advanced.rank).to be_present
      expect(advanced.idea_version_id).to be_present
    end

    it "las eliminadas quedan marcadas con el módulo donde cayeron" do
      handler.decide!(handler.ranking.select(&:above_cut?).map { _1.idea.id })

      eliminated = challenge.ideas.where(status: "eliminated")
      expect(eliminated.count).to eq(3)
      expect(eliminated.map(&:eliminated_at_step_id).uniq).to eq([handler.step.id])
    end

    it "las eliminadas NO generan entries en el módulo siguiente" do
      # Es lo que hace que step_entries signifique "participación real".
      handler.decide!(handler.ranking.select(&:above_cut?).map { _1.idea.id })
      siguiente = challenge.steps.create!(kind: "reporting", position: 5)

      Flow::Handlers::Base.for(siguiente).activate!

      expect(siguiente.reload.step_entries.count).to eq(2)
      expect(siguiente.step_entries.map(&:idea_id)).to match_array(challenge.ideas.alive.pluck(:id))
    end
  end

  describe "repesca" do
    let(:handler) { build_selection("cut" => { "mode" => "top_n", "value" => 2 }) }
    let!(:siguiente) { challenge.steps.create!(kind: "reporting", position: 5) }

    before do
      handler.decide!(handler.ranking.select(&:above_cut?).map { _1.idea.id }, decided_by: decider)
      # El flujo real tiene UN módulo activo a la vez: la selección se cierra
      # y el siguiente se activa. Repescar después devuelve la idea a ESE.
      handler.step.update!(status: "completed", completed_at: Time.current)
      Flow::Handlers::Base.for(siguiente).activate!
    end

    it "devuelve una idea eliminada al flujo y le crea la entry que falta" do
      rescued = challenge.ideas.where(status: "eliminated").first

      expect { handler.reinstate!(rescued, decided_by: decider, reason: "El comité la quiere ver") }
        .to change { siguiente.reload.step_entries.count }.by(1)

      expect(rescued.reload).to be_active
      expect(rescued.eliminated_at_step_id).to be_nil
      expect(siguiente.step_entries.map(&:idea_id)).to include(rescued.id)
    end

    it "NO edita la decisión anterior: agrega otra fila al log" do
      rescued = challenge.ideas.where(status: "eliminated").first
      handler.reinstate!(rescued, decided_by: decider, reason: "El comité la quiere ver")

      log = SelectionDecision.where(idea_id: rescued.id).chronological.to_a
      expect(log.map(&:outcome)).to eq(%w[eliminate reinstate])
      expect(log.last.reason).to eq("El comité la quiere ver")
      expect(log.first.outcome).to eq("eliminate"), "la decisión original se conserva"
    end
  end

  describe "#complete! sin decisión manual" do
    it "aplica la regla de corte automáticamente" do
      handler = build_selection("cut" => { "mode" => "top_n", "value" => 3 })
      handler.complete!

      expect(challenge.ideas.alive.count).to eq(3)
      expect(SelectionDecision.where(outcome: "advance").count).to eq(3)
      expect(SelectionDecision.first.reason).to match(/Corte automático/)
    end
  end
end
