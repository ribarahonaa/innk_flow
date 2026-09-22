# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flow::AI::Tasks::TestIdea do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:challenge) { create(:challenge) }
  let!(:ideation) { seed_form!(challenge.steps.create!(kind: "ideation", position: 1)) }

  let!(:idea) do
    i = create(:idea, challenge: challenge, status: "active")
    Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Bicis eléctricas" }).call
    i.update!(submitted_at: Time.current)
    i.reload
  end

  def paso(config = {})
    step = challenge.steps.create!(kind: "testing", position: 2,
                                   name: "Prueba de factibilidad", config: config)
    challenge.update!(status: "running")
    Flow::Handlers::Base.for(step).activate!
    step.reload
  end

  def tarea(step) = described_class.new(challenge: challenge, step: step, idea: idea)

  it "actúa sobre el desafío, no sobre la idea" do
    expect(described_class.actua_sobre).to eq(:challenge)
  end

  # Pedirla NO la aplica: el veredicto es LA respuesta del módulo para esa
  # idea y habilita un filtro después. Es el criterio de `decide_verdicts`,
  # no el de `evaluate_idea`.
  it "se propone y alguien la acepta; no se aplica al pedirla" do
    expect(tarea(paso).applies_on_request?).to be(false)
  end

  # La lección de EvaluateIdea: aceptar una propuesta admitiendo un payload
  # editado dejaba a una persona poniendo su veredicto con el nombre de la IA
  # encima.
  it "no se edita antes de aceptarla" do
    expect(tarea(paso).editable?).to be(false)
  end

  it "produce algo que se aplica, así que no es informativa" do
    expect(tarea(paso).informativa?).to be(false)
  end

  describe "#schema" do
    it "las dimensiones van como enum de las que el módulo configuró" do
      step = paso("dimensions" => %w[tecnica legal])
      dimension = tarea(step).schema.dig("properties", "situaciones", "items",
                                         "properties", "dimension")

      expect(dimension["enum"]).to eq(%w[tecnica legal])
    end

    it "el mínimo de situaciones sale de la configuración" do
      step = paso("min_situations" => 4)

      expect(tarea(step).schema.dig("properties", "situaciones", "minItems")).to eq(4)
    end

    # La API poda `minItems` y `minimum`, así que el mínimo tiene que estar
    # ADEMÁS en la descripción: es lo único que el modelo ve.
    it "el mínimo se repite en la descripción, porque la API poda minItems" do
      step = paso("min_situations" => 4)
      descripcion = tarea(step).schema.dig("properties", "situaciones", "description")

      expect(descripcion).to include("4")
    end
  end

  describe "#messages" do
    it "el rigor va en las situaciones y el veredicto lo dicta lo encontrado" do
      system = tarea(paso).messages.first[:content]

      expect(system).to include("no_factible")
      expect(system).to match(/con_reservas/)
    end

    it "la severidad configurada llega al prompt" do
      system = tarea(paso("severity" => "estandar")).messages.first[:content]

      expect(system).to include("estandar").or include("previsible")
    end
  end

  describe "#apply!" do
    let(:payload) do
      { "veredicto" => "con_reservas",
        "resumen" => "Aguanta el día normal, no el pico",
        "reservas" => ["Conseguir un segundo proveedor"],
        "situaciones" => [
          { "dimension" => "operativa", "escenario" => "Viernes 18h, 400 pedidos",
            "resultado" => "se_rompe", "detalle" => "El turno de tarde satura" }
        ] }
    end

    it "deja el testeo vigente a nombre de la IA, con su run" do
      step = paso
      run = AiRun.create!(challenge: challenge, purpose: "test_idea",
                          mode: "ai_assisted", status: "succeeded")
      sugerencia = AiSuggestion.create!(ai_run: run, idea: idea,
                                        payload: payload, status: "pending")

      ok, errores = tarea(step).apply!(payload, suggestion: sugerencia)

      expect([ok, errores]).to eq([true, []])
      test = step.handler.vigente_para(idea.id)
      expect(test.verdict).to eq("con_reservas")
      expect(test.actor_type).to eq("ai")
      expect(test.tested_by_id).to be_nil
      expect(test.ai_run_id).to eq(run.id)
      expect(test.reservations).to eq(["Conseguir un segundo proveedor"])
    end
  end

  it "el preview dice el veredicto y por dónde se rompe" do
    payload = { "veredicto" => "no_factible", "resumen" => "No da",
                "reservas" => [],
                "situaciones" => [{ "dimension" => "tecnica", "escenario" => "Pico de carga",
                                    "resultado" => "se_rompe", "detalle" => "Se cae" }] }

    expect(tarea(paso).preview(payload)).to include("Pico de carga")
  end
end
