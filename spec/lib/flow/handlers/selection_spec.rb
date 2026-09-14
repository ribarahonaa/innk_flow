# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flow::Handlers::Selection do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:decider) { without_tenant { create(:user) } }
  let(:challenge) { create(:challenge) }

  # ideation → evaluación técnica → evaluación de comité → selección
  let!(:ideation) { seed_form!(challenge.steps.create!(kind: "ideation", position: 1, slug: "ideation")) }
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
      seed_form!(solo.steps.create!(kind: "ideation", position: 1))
      step = solo.steps.create!(kind: "selection", position: 2)

      ready, reasons = described_class.new(step).can_activate?
      expect(ready).to be(false)
      expect(reasons.join).to match(/no tiene criterios propios ni una evaluación previa/)
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

    # Con `threshold` el corte cuenta las que superan el puntaje, y eso puede dar
    # CERO: si nadie llega, no pasa ninguna idea. Con el módulo en «IA
    # automática» eso se aplica solo y el desafío se queda sin finalistas sin
    # que nadie haya decidido nada. El piso es lo que lo evita, y GANA sobre la
    # regla: pasan las N mejores aunque no lleguen al puntaje.
    it "el piso deja pasar las N mejores aunque nadie alcance el puntaje" do
      handler = build_selection("cut" => { "mode" => "threshold", "value" => 0.95, "min" => 2 })
      above = handler.ranking.select(&:above_cut?)

      expect(above.map { _1.idea.title }).to eq(["Idea E", "Idea D"])
      expect(above.map(&:score)).to all(be < 0.95)
      expect(handler).to be_piso_aplicado
    end

    it "sin piso, el mismo corte no deja pasar a nadie" do
      handler = build_selection("cut" => { "mode" => "threshold", "value" => 0.95 })

      expect(handler.ranking.count(&:above_cut?)).to be_zero
      expect(handler).not_to be_piso_aplicado
    end

    # El piso no puede prometer más ideas de las que hay evaluadas. Es la misma
    # protección que `top_n` ya tenía, ahora para los tres modos.
    it "el piso no promete más ideas de las que hay" do
      handler = build_selection("cut" => { "mode" => "threshold", "value" => 0.95, "min" => 99 })

      expect(handler.ranking.count(&:above_cut?)).to eq(5)
    end

    # El piso sube el corte, nunca lo baja: con una regla que ya deja pasar más
    # que el mínimo, el mínimo no hace nada.
    it "no recorta lo que la regla ya dejaba pasar" do
      handler = build_selection("cut" => { "mode" => "top_n", "value" => 4, "min" => 2 })

      expect(handler.ranking.count(&:above_cut?)).to eq(4)
      expect(handler).not_to be_piso_aplicado
    end

    # Igual que el modo y el valor, el piso se RESUELVE al activar. `settings`
    # devuelve el resuelto en cuanto el módulo arrancó, así que si
    # `resolve_config!` no escribiera la clave, un módulo en curso leería `nil`
    # y correría sin piso — sin nada que lo delate en la pantalla.
    #
    # Editar el `config` después no hace falta probarlo acá: `config` está en
    # FROZEN_ATTRIBUTES y el modelo rechaza la escritura.
    it "el piso se resuelve al activar, junto al modo y al valor" do
      handler = build_selection("cut" => { "mode" => "threshold", "value" => 0.95, "min" => 2 })

      expect(handler.step.resolved_config.dig("cut", "min")).to eq(2)
      expect(handler.step.settings.dig("cut", "min")).to eq(2)
      expect(handler.cut_min).to eq(2)
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

  describe "filtros: criterios de la propia selección" do
    let(:filters) do
      set = CriteriaSet.create!(name: "Filtros de comité")
      set.criteria.create!(name: "Tiene costo", key: "tiene_costo", weight: 0.5, source: "automatic",
                           source_config: { "check" => "field_present", "field_key" => "costo" })
      set.criteria.create!(name: "¿Es viable?", key: "es_viable", weight: 0.5,
                           source: "manual", scale_type: "boolean")
      set.refresh_status!
      set
    end

    def build_with_filters(config = {})
      step = challenge.steps.create!(kind: "selection", position: 4, name: "Corte",
                                     criteria_set: filters, config: config)
      challenge.update!(status: "running")
      tecnica.update!(status: "completed")
      comite.update!(status: "completed")
      Flow::Handlers::Base.for(step).activate!
      described_class.new(step.reload)
    end

    it "una selección con filtros propios se sostiene sin evaluación previa" do
      solo = create(:challenge)
      seed_form!(solo.steps.create!(kind: "ideation", position: 1))
      step = solo.steps.create!(kind: "selection", position: 2, criteria_set: filters)

      ready, = described_class.new(step).can_activate?
      expect(ready).to be(true)
    end

    it "verifica los filtros automáticos contra cada idea" do
      # Solo la primera declara el costo.
      Flow::Ideas::PublishVersion.new(ideas[0], payload: ideas[0].payload.merge("costo" => "8 celdas")).call
      handler = build_with_filters

      rows = handler.ranking.index_by { |row| row.idea.id }
      expect(rows[ideas[0].id].gates.find { _1[:key] == "tiene_costo" }[:passed]).to be(true)
      expect(rows[ideas[1].id].gates.find { _1[:key] == "tiene_costo" }[:passed]).to be(false)
    end

    it "una idea que no pasa un filtro NO avanza aunque puntúe alto" do
      handler = build_with_filters("cut" => { "mode" => "top_n", "value" => 5 })

      # Nadie declaró el costo: ninguna pasa el filtro automático.
      expect(handler.ranking.select(&:above_cut?)).to be_empty
      expect(handler.ranking.map(&:passes_gates?).uniq).to eq([false])
    end

    it "el veredicto de una persona resuelve el filtro de sí/no" do
      Flow::Ideas::PublishVersion.new(ideas[0], payload: ideas[0].payload.merge("costo" => "8 celdas")).call
      handler = build_with_filters("cut" => { "mode" => "top_n", "value" => 5 })

      expect(handler.ranking.find { _1.idea == ideas[0] }.pending_gates.size).to eq(1)

      handler.record_verdict!(idea: ideas[0], criterion_key: "es_viable", passed: true,
                              decided_by: decider, note: "Sistemas confirmó que se puede")

      row = described_class.new(handler.step.reload).ranking.find { _1.idea == ideas[0] }
      expect(row.pending_gates).to be_empty
      expect(row).to be_passes_gates
      expect(row).to be_above_cut
    end

    it "no se puede cerrar el módulo con veredictos pendientes" do
      handler = build_with_filters

      ready, reasons = handler.can_complete?
      expect(ready).to be(false)
      expect(reasons.join).to match(/Faltan \d+ veredictos sobre los filtros/)
    end

    it "los filtros quedan CONGELADOS al activar el módulo" do
      handler = build_with_filters
      expect(handler.gate_criteria.map { _1["key"] }).to eq(%w[tiene_costo es_viable])

      filters.criteria.find_by(key: "es_viable").update!(name: "Cambiado")
      expect(described_class.new(handler.step.reload).gate_criteria.last["name"]).to eq("¿Es viable?")
    end

    it "el veredicto queda anclado a la versión que se juzgó" do
      handler = build_with_filters
      handler.record_verdict!(idea: ideas[0], criterion_key: "es_viable", passed: false,
                              decided_by: decider, note: "Sin alcance definido")

      verdict = SelectionVerdict.find_by(idea_id: ideas[0].id, criterion_key: "es_viable")
      expect(verdict.idea_version_id).to eq(ideas[0].reload.current_version_id)
      expect(verdict.decided_by_name).to eq(decider.name)
      expect(verdict).not_to be_passed
    end
  end

  # Un filtro de sí/no sin responder traba el cierre del módulo. Con la
  # selección en «Solo IA» eso era un callejón sin salida: el módulo prometía
  # correr solo y se quedaba esperando a una persona.
  describe "en modo automático la IA responde los filtros" do
    let(:con_veredictos) do
      set = CriteriaSet.create!(name: "Filtros de pase")
      set.criteria.create!(name: "¿Es viable?", key: "es_viable", weight: 1,
                           source: "manual", scale_type: "boolean")
      set.refresh_status!
      set
    end

    let(:solo_automaticos) do
      set = CriteriaSet.create!(name: "Filtros verificables")
      set.criteria.create!(name: "Tiene costo", key: "tiene_costo", weight: 1, source: "automatic",
                           source_config: { "check" => "field_present", "field_key" => "costo" })
      set.refresh_status!
      set
    end

    def activar(set:, mode:)
      step = challenge.steps.create!(kind: "selection", position: 4, name: "Corte",
                                     criteria_set: set, ai_mode: mode)
      challenge.update!(status: "running")
      tecnica.update!(status: "completed")
      comite.update!(status: "completed")
      -> { Flow::Handlers::Base.for(step).activate! }
    end

    it "encola una consulta por idea" do
      expect(&activar(set: con_veredictos, mode: "ai_auto"))
        .to have_enqueued_job(Flow::AI::RunJob).exactly(ideas.size).times
    end

    # Un veredicto decide quién queda afuera: no es una opinión más, así que
    # en asistido se propone y alguien la acepta, no se dispara sola.
    it "en asistido no dispara nada" do
      expect(&activar(set: con_veredictos, mode: "ai_assisted"))
        .not_to have_enqueued_job(Flow::AI::RunJob)
    end

    it "sin filtros de veredicto no hay nada que preguntar" do
      expect(&activar(set: solo_automaticos, mode: "ai_auto"))
        .not_to have_enqueued_job(Flow::AI::RunJob)
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
