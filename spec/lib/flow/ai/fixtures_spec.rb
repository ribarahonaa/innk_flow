# frozen_string_literal: true

require "rails_helper"

# La red que evita el drift: si un fixture se desvía del contrato que declara
# su tarea, falla acá y no cuando se enchufe el proveedor real.
RSpec.describe "fixtures de IA" do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:challenge) { create(:challenge) }
  # Un formulario realista, no de un solo campo: algunos schemas se arman
  # desde los campos declarados (`suggest_criteria` solo admite claves que
  # existen), así que un formulario de juguete haría fallar fixtures válidos.
  let(:step) do
    s = challenge.steps.create!(kind: "ideation", position: 1)
    seed_form!(s)
    s
  end
  let(:idea) { create(:idea, challenge: challenge) }

  # La mayoría de las tareas no le preguntan nada al handler del `step` en su
  # `#schema`: cualquier módulo alcanza para leerlo (`decide_verdicts` usa el
  # handler sólo en `apply!`/`preview`, que este spec no ejercita). `test_idea`
  # es la primera cuyo `#schema` sí lo toca (`min_situations`, `dimensions`,
  # `severity`), y esos métodos sólo existen en el handler de su propio `kind`
  # —`ChallengeStep#handler` despacha por `step.kind`—, así que necesita un
  # `step` de ESE kind y no el de ideación de siempre. Mapa angosto a
  # propósito: hoy es la única tarea que lo pide.
  STEP_KIND_POR_PROPOSITO = { "test_idea" => "testing" }.freeze

  # Memoizado por kind y no en un solo valor: si memoizara un único `step`,
  # una segunda tarea que pidiera otro kind se llevaría puesto el step de la
  # primera y su schema saldría mal en silencio.
  def step_for(purpose)
    kind = STEP_KIND_POR_PROPOSITO[purpose]
    return step if kind.nil?

    @steps_por_kind ||= {}
    @steps_por_kind[kind] ||= challenge.steps.create!(kind: kind, position: 2)
  end

  # Contexto mínimo para poder instanciar cada tarea y leer su schema.
  def task_for(purpose)
    Flow::AI::Tasks::Base.for(
      purpose,
      challenge: challenge, step: step_for(purpose), idea: idea,
      field: step.form_fields.first
    )
  end

  fixture_dirs = Rails.root.glob("spec/fixtures/ai/*").select(&:directory?)

  it "hay fixtures para las tareas cableadas" do
    expect(fixture_dirs.map { |d| d.basename.to_s })
      .to include("propose_pipeline", "suggest_form_fields", "generate_ideas", "coauthor_field")
  end

  fixture_dirs.each do |dir|
    purpose = dir.basename.to_s

    context purpose do
      dir.glob("*.json").each do |file|
        it "#{file.basename} valida contra el schema de la tarea" do
          payload = JSON.parse(file.read)
          errors = Flow::AI::SchemaValidator.errors_for(payload, task_for(purpose).schema)

          expect(errors).to be_empty, "#{file}: #{errors.join('; ')}"
        end
      end
    end
  end

  it "cada tarea declara un schema no vacío" do
    AiRun::PURPOSES.each do |purpose|
      next if Flow::AI::Tasks::Base.for(purpose, challenge: challenge, step: step_for(purpose),
                                        idea: idea,
                                        field: step.form_fields.first).schema.present?

      raise "#{purpose} no declara schema"
    rescue ArgumentError
      # Tareas de fases posteriores todavía no existen: se saltean.
      next
    end
  end

  # El schema de la tarea declara `config` como un objeto cualquiera, así que
  # validar contra él no ve una clave mal escrita: `apply!` la descarta al
  # filtrar y el módulo corre con el default sin que nadie se entere. Pasó con
  # `cut_mode`/`cut_value` planos, que ningún handler lee: «Corte a top 10»
  # nacía con el corte en manual.
  Rails.root.glob("spec/fixtures/ai/propose_pipeline/*.json").each do |file|
    it "#{file.basename} de propose_pipeline sólo propone config que el esquema declara" do
      JSON.parse(file.read)["steps"].each do |paso|
        config = paso["config"] || {}

        expect(Flow::StepSettings.filtrar(paso["kind"], config))
          .to eq(config), "#{paso["name"]} (#{paso["kind"]}): #{config}"
      end
    end
  end
end
