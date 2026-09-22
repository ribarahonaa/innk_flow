# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flow::Handlers::Testing do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:tester) { without_tenant { create(:user) } }
  let(:challenge) { create(:challenge) }
  let!(:ideation) { seed_form!(challenge.steps.create!(kind: "ideation", position: 1, slug: "ideation")) }

  let!(:ideas) do
    %w[Sensores Cámaras].map do |titulo|
      idea = create(:idea, challenge: challenge, status: "active")
      Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => titulo }).call
      idea.update!(submitted_at: Time.current)
      idea
    end
  end

  def armar(config = {})
    step = challenge.steps.create!(kind: "testing", position: 2, name: "Prueba de factibilidad",
                                   config: config)
    challenge.update!(status: "running")
    Flow::Handlers::Base.for(step).activate!
    described_class.new(step.reload)
  end

  def armar_con_modo(modo)
    step = challenge.steps.create!(kind: "testing", position: 2,
                                   name: "Prueba de factibilidad", ai_mode: modo)
    challenge.update!(status: "running")
    Flow::Handlers::Base.for(step).activate!
    described_class.new(step.reload)
  end

  def testear(handler, idea, veredicto, **resto)
    handler.testear!(idea: idea, verdict: veredicto, tested_by: tester,
                     situations: [{ "dimension" => "operativa", "escenario" => "Viernes 18h",
                                    "resultado" => veredicto == "factible" ? "aguanta" : "se_rompe",
                                    "detalle" => "El turno de tarde" }],
                     reservations: [], summary: "Probado", **resto)
  end

  it "el despacho por kind lo encuentra sin tocar Handlers::Base" do
    handler = armar
    expect(Flow::Handlers::Base.for(handler.step)).to be_a(described_class)
  end

  it "arranca sin precondiciones: no necesita nada de un módulo anterior" do
    step = challenge.steps.create!(kind: "testing", position: 2)
    ready, = described_class.new(step).can_activate?
    expect(ready).to be(true)
  end

  describe "#testear!" do
    it "deja el testeo vigente de esa idea, anclado a la versión probada" do
      handler = armar
      test = testear(handler, ideas[0], "con_reservas")

      expect(test.idea_version_id).to eq(ideas[0].reload.current_version_id)
      expect(handler.vigente_para(ideas[0].id).verdict).to eq("con_reservas")
    end

    # Append-only: re-testear no edita, marca el anterior y escribe otro.
    it "re-testear supera al anterior y lo deja en el historial" do
      handler = armar
      testear(handler, ideas[0], "no_factible")
      testear(handler, ideas[0], "factible")

      expect(handler.vigente_para(ideas[0].id).verdict).to eq("factible")
      expect(handler.historial_de(ideas[0].id).map(&:verdict)).to eq(%w[factible no_factible])
      expect(StepTest.where(idea_id: ideas[0].id).count).to eq(2)
    end
  end

  describe "#progress y #can_complete?" do
    it "cuenta las ideas testeadas" do
      handler = armar
      testear(handler, ideas[0], "factible")

      expect(handler.progress.done).to eq(1)
      expect(handler.progress.total).to eq(2)
    end

    it "no se puede cerrar con ideas sin testear" do
      handler = armar
      ready, reasons = handler.can_complete?

      expect(ready).to be(false)
      expect(reasons.join).to match(/Faltan 2 ideas por testear/)
    end

    it "se puede cerrar con todas testeadas" do
      handler = armar
      ideas.each { |idea| testear(handler, idea, "factible") }

      expect(handler.can_complete?.first).to be(true)
    end
  end

  # Nadie se elimina acá: eso es exclusivo de la selección. Todas las entries
  # se resuelven `done` con el veredicto adentro, que es donde el resto de la
  # app busca el resultado de un módulo.
  it "al cerrar proyecta el veredicto a step_entries y no elimina a nadie" do
    handler = armar
    testear(handler, ideas[0], "factible")
    testear(handler, ideas[1], "no_factible")
    handler.complete!

    entries = handler.step.step_entries.reload
    expect(entries.map(&:status).uniq).to eq(["done"])
    expect(entries.map { _1.result["verdict"] }).to match_array(%w[factible no_factible])
    expect(challenge.ideas.alive.count).to eq(2)
  end

  # `on_complete` no puede confiar en que alguien preguntó `can_complete?`
  # antes. Hoy el único que llama a `complete!` es `Pipeline#advance!`, que sí
  # pregunta, pero alcanza con un segundo camino de cierre —una consola, un
  # «forzar cierre», el reintento de un job— para que una idea sin testeo
  # vigente quede `done` con el veredicto en `nil`: un módulo que cerró limpio
  # según la tabla y que nunca probó esa idea.
  #
  # Es la forma autocorrectiva de `Evaluation#recompute_entry!`, que deja
  # `in_progress` cuando no llega al mínimo justamente para no poder mentir.
  it "al cerrar sin testeo vigente deja la entry in_progress, no done" do
    handler = armar
    testear(handler, ideas[0], "factible")
    handler.complete!

    entries = handler.step.step_entries.reload.index_by(&:idea_id)
    expect(entries[ideas[0].id].status).to eq("done")
    expect(entries[ideas[1].id].status).to eq("in_progress")
    expect(entries[ideas[1].id].result["verdict"]).to be_nil
  end

  describe "los modos de IA al arrancar" do
    # Nunca un fan-out síncrono en el request: una corrida por idea, encolada.
    it "en automático encola un testeo por idea" do
      expect do
        armar_con_modo("ai_auto")
      end.to have_enqueued_job(Flow::AI::RunJob).exactly(2).times
    end

    # En asistido no se dispara solo: el veredicto se propone y alguien lo
    # acepta, así que arrancar el módulo no puede dejar dos propuestas
    # esperando sin que nadie las haya pedido.
    it "en asistido no encola nada" do
      expect { armar_con_modo("ai_assisted") }.not_to have_enqueued_job(Flow::AI::RunJob)
    end

    it "en «solo personas» tampoco" do
      expect { armar_con_modo("human") }.not_to have_enqueued_job(Flow::AI::RunJob)
    end
  end
end
