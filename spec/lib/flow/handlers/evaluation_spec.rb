# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flow::Handlers::Evaluation do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:evaluators) do
    without_tenant do
      3.times.map do |n|
        user = create(:user, email: "eval#{n}@test.dev")
        create(:membership, :evaluator, company: company, user: user)
        user
      end
    end
  end

  let(:set) do
    s = CriteriaSet.create!(name: "Técnica")
    s.criteria.create!(key: "impacto", name: "Impacto", weight: 0.6, scale_type: "numeric",
                       scale_config: { "min" => 1, "max" => 10 }, position: 0)
    s.criteria.create!(key: "esfuerzo", name: "Esfuerzo", weight: 0.4, scale_type: "numeric",
                       scale_config: { "min" => 1, "max" => 10, "direction" => "lower_better" }, position: 1)
    s.refresh_status!
    s
  end

  let(:challenge) { create(:challenge) }
  let!(:ideation) { seed_form!(challenge.steps.create!(kind: "ideation", position: 1)) }
  let!(:step) { challenge.steps.create!(kind: "evaluation", position: 2, criteria_set: set) }

  let!(:idea) do
    i = create(:idea, challenge: challenge, status: "active")
    Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" }).call
    i.update!(submitted_at: Time.current)
    i
  end

  def activate!
    Flow::Handlers::Base.for(step).activate!
    step.reload
  end

  def evaluate!(user, impacto:, esfuerzo:, submit: true)
    handler = described_class.new(step.reload)
    assessment = step.assessments.create!(
      idea: idea, idea_version: idea.reload.current_version, evaluator: user,
      status: submit ? "submitted" : "pending", submitted_at: submit ? Time.current : nil
    )

    { "impacto" => impacto, "esfuerzo" => esfuerzo }.each do |key, raw|
      config = handler.criteria_snapshot.find { |c| c["key"] == key }
      criterion = Criterion.find(config["id"])
      numeric, normalized = criterion.score(raw)
      assessment.assessment_scores.create!(
        criterion_id: criterion.id, criterion_key: key, weight_used: config["weight"],
        raw_value: raw.to_s, numeric_value: numeric, normalized_value: normalized
      )
    end

    Flow::Evaluation::ScoreAssessment.new(assessment, criteria_snapshot: handler.criteria_snapshot).call
    handler.recompute_entry!(step.step_entries.find_by(idea_id: idea.id))
    assessment
  end

  describe "#can_activate?" do
    it "sin criterios asignados siembra un set INLINE por defecto" do
      # Igual que «Idear» siembra campos por defecto: la maqueta corre de punta
      # a punta sin obligar a configurar todo primero.
      naked = challenge.steps.create!(kind: "evaluation", position: 3)
      ready, = described_class.new(naked).can_activate?
      expect(ready).to be(true)

      Flow::Handlers::Base.for(naked).activate!
      naked.reload

      expect(naked.criteria_set).to be_present
      expect(naked.criteria_set.scope).to eq("inline")
      expect(naked.criteria_set.owner_step_id).to eq(naked.id)
      expect(naked.settings["criteria"].map { _1["key"] }).to eq(%w[impacto factibilidad esfuerzo])
    end

    it "rechaza un set cuyos pesos no suman 1" do
      set.criteria.first.update!(weight: 0.9)
      ready, reasons = described_class.new(step).can_activate?

      expect(ready).to be(false)
      expect(reasons.join).to match(/deben sumar 1/)
    end
  end

  describe "snapshot de criterios" do
    it "CONGELA los criterios al activar el módulo" do
      activate!
      expect(step.settings["criteria"].map { _1["key"] }).to eq(%w[impacto esfuerzo])
      expect(step.settings["criteria"].first["weight"]).to eq("0.6")
    end

    it "editar el set DESPUÉS no reescribe puntajes históricos" do
      # En innk_r5, Objective#reset_ponderations muta ponderaciones in-place y
      # dispara un worker que recalcula promedios de ideas viejas: editar un
      # criterio hoy reescribe el año pasado. Acá no.
      activate!
      evaluate!(evaluators.first, impacto: 10, esfuerzo: 1)
      score_before = step.step_entries.find_by(idea_id: idea.id).result["score"]

      set.criteria.find_by(key: "impacto").update!(weight: 0.1)
      set.criteria.find_by(key: "esfuerzo").update!(weight: 0.9)

      expect(step.reload.settings["criteria"].first["weight"]).to eq("0.6")
      expect(step.step_entries.find_by(idea_id: idea.id).result["score"]).to eq(score_before)
    end
  end

  describe "cálculo del puntaje" do
    before { activate! }

    it "pondera por el peso de cada criterio" do
      # impacto 10/10 = 1.0 (peso .6) · esfuerzo 1/10 invertido = 1.0 (peso .4)
      evaluate!(evaluators.first, impacto: 10, esfuerzo: 1)

      expect(step.assessments.first.normalized_score.to_f).to be_within(0.001).of(1.0)
    end

    it "respeta la dirección lower_better" do
      # esfuerzo 10 (el peor) => 0. Solo queda impacto: 0.6 de 1.0 de peso.
      evaluate!(evaluators.first, impacto: 10, esfuerzo: 10)

      expect(step.assessments.first.normalized_score.to_f).to be_within(0.001).of(0.6)
    end

    it "promedia entre evaluadores" do
      evaluate!(evaluators[0], impacto: 10, esfuerzo: 1)  # 1.0
      evaluate!(evaluators[1], impacto: 1, esfuerzo: 10)  # 0.0

      entry = step.step_entries.find_by(idea_id: idea.id)
      expect(entry.result["score"]).to be_within(0.001).of(0.5)
      expect(entry.result["assessments_count"]).to eq(2)
      expect(entry.result["dispersion"]).to be > 0
    end

    it "usa la mediana cuando el módulo lo pide" do
      step.update!(resolved_config: step.resolved_config.merge("evaluator_aggregation" => "median"))
      evaluate!(evaluators[0], impacto: 10, esfuerzo: 1)
      evaluate!(evaluators[1], impacto: 10, esfuerzo: 1)
      evaluate!(evaluators[2], impacto: 1, esfuerzo: 10)

      entry = step.step_entries.find_by(idea_id: idea.id)
      expect(entry.result["score"]).to be_within(0.001).of(1.0)
    end

    it "renormaliza cuando faltan criterios por responder" do
      # Una evaluación parcial no se castiga por lo que no respondió.
      handler = described_class.new(step)
      assessment = step.assessments.create!(idea: idea, idea_version: idea.current_version,
                                            evaluator: evaluators.first, status: "submitted")
      config = handler.criteria_snapshot.find { _1["key"] == "impacto" }
      assessment.assessment_scores.create!(criterion_key: "impacto", criterion_id: config["id"],
                                           weight_used: config["weight"], raw_value: "10",
                                           numeric_value: 10, normalized_value: 1)

      Flow::Evaluation::ScoreAssessment.new(assessment, criteria_snapshot: handler.criteria_snapshot).call

      expect(assessment.reload.normalized_score.to_f).to eq(1.0)
    end
  end

  describe "criterios fórmula" do
    let(:set) do
      s = CriteriaSet.create!(name: "ICE")
      s.criteria.create!(key: "impacto", name: "Impacto", weight: 0.5, scale_type: "numeric",
                         scale_config: { "min" => 1, "max" => 10 }, position: 0)
      s.criteria.create!(key: "esfuerzo", name: "Esfuerzo", weight: 0.5, scale_type: "numeric",
                         scale_config: { "min" => 1, "max" => 10 }, position: 1)
      s.criteria.create!(key: "ice", name: "ICE", weight: 0, source: "formula", scale_type: "numeric", position: 2,
                         scale_config: { "expression" => "impacto / esfuerzo",
                                         "output" => { "min" => 0, "max" => 10 } })
      s.refresh_status!
      s
    end

    it "se calculan solos a partir de los otros criterios" do
      activate!
      evaluate!(evaluators.first, impacto: 8, esfuerzo: 2)

      derived = step.assessments.first.assessment_scores.find_by(criterion_key: "ice")
      expect(derived.numeric_value.to_f).to eq(4.0)
      expect(derived.normalized_value.to_f).to eq(0.4)
    end

    it "no aparecen en el formulario del evaluador" do
      activate!
      expect(described_class.new(step).scored_criteria.map { _1["key"] }).to eq(%w[impacto esfuerzo])
    end

    it "una fórmula rota NO tumba la evaluación" do
      activate!
      # División por cero: el criterio derivado queda con error y los demás
      # siguen contando.
      evaluate!(evaluators.first, impacto: 8, esfuerzo: 0)

      derived = step.assessments.first.assessment_scores.find_by(criterion_key: "ice")
      expect(derived.normalized_value).to be_nil
      expect(step.assessments.first.normalized_score).to be_present
    end
  end

  describe "#can_complete?" do
    before { activate! }

    it "exige el mínimo de evaluaciones por idea" do
      step.update!(resolved_config: step.resolved_config.merge("min_assessments" => 2))
      evaluate!(evaluators.first, impacto: 5, esfuerzo: 5)

      ready, reasons = described_class.new(step.reload).can_complete?
      expect(ready).to be(false)
      expect(reasons.join).to match(/Faltan evaluaciones/)

      evaluate!(evaluators[1], impacto: 5, esfuerzo: 5)
      ready, = described_class.new(step.reload).can_complete?
      expect(ready).to be(true)
    end
  end

  describe "anclaje a la versión" do
    it "la nota dice qué versión juzgó" do
      activate!
      evaluate!(evaluators.first, impacto: 5, esfuerzo: 5)
      assessment = step.assessments.first
      expect(assessment.idea_version_id).to eq(idea.reload.current_version_id)
      expect(assessment).not_to be_stale

      Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => "Cambiada" }).call

      # No se invalida: queda anclada, y la UI puede decir "evaluada sobre v1".
      expect(assessment.reload).to be_stale
      expect(assessment.normalized_score).to be_present
    end
  end

  # `step_assignments.weight` existía desde el principio y no entraba en
  # ninguna cuenta: el peso por evaluador era una columna decorativa.
  describe "el peso de cada evaluador" do
    def pesar!(user, weight)
      StepAssignment.find_by!(challenge_step_id: step.id, user_id: user.id).update!(weight: weight)
    end

    def puntaje = step.step_entries.find_by(idea_id: idea.id).reload.result["score"]

    # `evaluators` primero: activar asigna a quienes ya existen, y el let es
    # perezoso — sin tocarlo, el módulo arranca sin nadie asignado.
    before do
      evaluators
      activate!
    end

    it "sin pesos asignados, el promedio de siempre" do
      evaluate!(evaluators[0], impacto: 10, esfuerzo: 1)
      evaluate!(evaluators[1], impacto: 2, esfuerzo: 10)

      # (1.0*0.6 + 1.0*0.4) y (0.111*0.6 + 0.0*0.4), promediados.
      esperado = (1.0 + ((1.0 / 9) * 0.6)) / 2
      expect(puntaje).to be_within(0.001).of(esperado)
    end

    it "con el doble de peso, esa nota cuenta el doble" do
      evaluate!(evaluators[0], impacto: 10, esfuerzo: 1)
      evaluate!(evaluators[1], impacto: 2, esfuerzo: 10)
      pesar!(evaluators[0], 2)

      alta = 1.0
      baja = (1.0 / 9) * 0.6
      esperado = ((alta * 2) + baja) / 3

      described_class.new(step.reload).recompute_entry!(step.step_entries.find_by(idea_id: idea.id))
      expect(puntaje).to be_within(0.001).of(esperado)
    end

    # Asignar gente sin tocar pesos no puede mover un puntaje ya calculado.
    it "poner el mismo peso a todos no cambia nada" do
      evaluate!(evaluators[0], impacto: 10, esfuerzo: 1)
      evaluate!(evaluators[1], impacto: 2, esfuerzo: 10)
      antes = puntaje

      evaluators.each { |u| pesar!(u, 3) }
      described_class.new(step.reload).recompute_entry!(step.step_entries.find_by(idea_id: idea.id))

      expect(puntaje).to eq(antes)
    end

    # La dispersión acompaña al número que informa: calcularla sobre otra
    # distribución que la del puntaje no describe nada.
    it "la dispersión también se pondera" do
      evaluate!(evaluators[0], impacto: 10, esfuerzo: 1)
      evaluate!(evaluators[1], impacto: 2, esfuerzo: 10)
      sin_pesos = step.step_entries.find_by(idea_id: idea.id).result["dispersion"]

      pesar!(evaluators[0], 5)
      described_class.new(step.reload).recompute_entry!(step.step_entries.find_by(idea_id: idea.id))

      expect(step.step_entries.find_by(idea_id: idea.id).reload.result["dispersion"])
        .not_to be_within(0.0001).of(sin_pesos)
    end

    # La IA no tiene asignación: no se le reparte el módulo, es una opinión
    # más. Pesa 1 y no rompe la cuenta.
    it "una evaluación de la IA pesa 1" do
      evaluate!(evaluators[0], impacto: 10, esfuerzo: 1)
      pesar!(evaluators[0], 4)

      handler = described_class.new(step.reload)
      expect(handler.send(:weight_of, step.assessments.first)).to eq(4)
      expect(handler.send(:weight_of, Assessment.new(evaluator_id: nil))).to eq(1)
    end
  end
end
RSpec.describe "«Evaluación» con IA automática" do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:author) { without_tenant { create(:user) } }
  let(:challenge) { create(:challenge) }
  let!(:ideation) { seed_form!(challenge.steps.create!(kind: "ideation", position: 1)) }

  let(:set) do
    s = CriteriaSet.create!(name: "Técnica")
    s.criteria.create!(key: "impacto", name: "Impacto", weight: 0.4, source: "manual",
                       scale_type: "numeric", scale_config: { "min" => 1, "max" => 10 }, position: 0)
    s.criteria.create!(key: "factibilidad", name: "Factibilidad", weight: 0.35, source: "manual",
                       scale_type: "numeric", scale_config: { "min" => 1, "max" => 10 }, position: 1)
    s.criteria.create!(key: "esfuerzo", name: "Esfuerzo", weight: 0.25, source: "manual",
                       scale_type: "numeric", scale_config: { "min" => 1, "max" => 10 }, position: 2)
    s.refresh_status!
    s
  end

  let!(:idea) do
    i = create(:idea, challenge: challenge, author: author, status: "active")
    Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" }, author: author).call
    i.update!(submitted_at: Time.current)
    i
  end

  def evaluation_with(mode)
    step = challenge.steps.create!(kind: "evaluation", position: 2, ai_mode: mode, criteria_set: set)
    Flow::Handlers::Base.for(step).activate!
    step.reload
  end

  it "en ai_auto encola una evaluación por idea cuando el mínimo es 1" do
    expect { evaluation_with("ai_auto") }
      .to have_enqueued_job(Flow::AI::RunJob)
      .with(company.id, "evaluate_idea", hash_including("idea_id" => idea.id))
      .exactly(:once)
  end

  it "CUBRE EL MÍNIMO del módulo: si pide 3 por idea, hace 3" do
    # Antes encolaba una sola y el módulo quedaba trabado para siempre:
    # can_complete? nunca podía dar verdadero.
    step = challenge.steps.create!(kind: "evaluation", position: 2, ai_mode: "ai_auto",
                                   criteria_set: set, config: { "min_assessments" => 3 })

    expect { Flow::Handlers::Base.for(step).activate! }
      .to have_enqueued_job(Flow::AI::RunJob).exactly(3).times
  end

  it "con el mínimo en 3, la IA lo completa y el módulo se puede cerrar" do
    step = challenge.steps.create!(kind: "evaluation", position: 2, ai_mode: "ai_auto",
                                   criteria_set: set, config: { "min_assessments" => 3 })
    Flow::Handlers::Base.for(step).activate!
    perform_enqueued_jobs

    step.reload
    expect(step.assessments.count).to eq(3)
    expect(step.assessments.map(&:by_ai?).uniq).to eq([true])
    expect(step.assessments.map(&:ai_run_id).uniq.size).to eq(3), "cada pasada es una consulta propia"

    ready, reasons = Flow::Handlers::Base.for(step).can_complete?
    expect(ready).to be(true), reasons.join(" ")
  end

  it "no repite las que ya existen: completa lo que falta" do
    step = challenge.steps.create!(kind: "evaluation", position: 2, ai_mode: "ai_auto",
                                   criteria_set: set, config: { "min_assessments" => 3 })
    Flow::Handlers::Base.for(step).activate!
    perform_enqueued_jobs

    # Reactivar no vuelve a pedir: ya están las tres.
    expect { Flow::Handlers::Base.for(step.reload).send(:request_ai_assessments!) }
      .not_to have_enqueued_job(Flow::AI::RunJob)
  end

  it "una evaluación humana descuenta del mínimo que cubre la IA" do
    step = challenge.steps.create!(kind: "evaluation", position: 2, ai_mode: "ai_auto",
                                   criteria_set: set, config: { "min_assessments" => 3 })
    Flow::Handlers::Base.for(step).activate!
    step.assessments.create!(idea: idea, idea_version_id: idea.current_version_id,
                             evaluator: author, status: "submitted", submitted_at: Time.current)

    expect { Flow::Handlers::Base.for(step.reload).send(:request_ai_assessments!) }
      .to have_enqueued_job(Flow::AI::RunJob).exactly(2).times
  end

  it "en ai_assisted NO evalúa sola" do
    expect { evaluation_with("ai_assisted") }.not_to have_enqueued_job(Flow::AI::RunJob)
  end

  it "la evaluación de IA entra al promedio como una más" do
    step = evaluation_with("ai_auto")
    perform_enqueued_jobs

    assessment = step.assessments.reload.first
    expect(assessment).to be_by_ai
    expect(assessment.evaluator_id).to be_nil
    expect(assessment.evaluator_name).to eq("IA")
    expect(assessment).to be_submitted

    # Escala 1..10 normaliza (v-1)/9:
    #   impacto      8 -> 0.778 x 0.40 = 0.311
    #   factibilidad 6 -> 0.556 x 0.35 = 0.194
    #   esfuerzo     5 -> 0.444 x 0.25 = 0.111
    expect(assessment.normalized_score.to_f).to be_within(0.001).of(0.6167)
    expect(step.step_entries.first.result["score"]).to be_within(0.001).of(0.6167)
  end

  it "queda anclada a la versión que juzgó, con la justificación por criterio" do
    step = evaluation_with("ai_auto")
    perform_enqueued_jobs

    assessment = step.assessments.reload.first
    expect(assessment.idea_version_id).to eq(idea.reload.current_version_id)
    expect(assessment.overall_comment).to include("costo estimado")

    scores = assessment.assessment_scores.index_by(&:criterion_key)
    expect(scores["impacto"].raw_value).to eq("8")
    expect(scores["impacto"].comment).to include("diferencia de inventario")
    expect(scores.keys).to match_array(%w[impacto factibilidad esfuerzo])
  end

  it "deja rastro en la auditoría" do
    step = evaluation_with("ai_auto")
    perform_enqueued_jobs

    run = AiRun.find_by(purpose: "evaluate_idea")
    expect(run).to be_succeeded
    expect(run.idea_id).to eq(idea.id)
    expect(run.challenge_step_id).to eq(step.id)
    expect(AiSuggestion.find_by(ai_run_id: run.id)).to be_accepted
  end
end

