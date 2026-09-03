# frozen_string_literal: true

require "rails_helper"

# Proponer los criterios de un módulo.
#
# Es la configuración que más cuesta a mano: los dos ejes de cada criterio, los
# pesos sumando 100, y —si es automático— qué campo del formulario mirar.
RSpec.describe Flow::AI::Tasks::SuggestCriteria do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:challenge) { create(:challenge, name: "Merma", brief: "Bajar la merma en bodega.") }

  let!(:ideation) do
    s = challenge.steps.create!(kind: "ideation", position: 1)
    seed_form!(s)
    s.form_fields.create!(key: "adjunto", label: "Costeo", field_type: "file", position: 9)
    s
  end

  let!(:evaluacion) { challenge.steps.create!(kind: "evaluation", position: 2, name: "Técnica") }
  let!(:seleccion) { challenge.steps.create!(kind: "selection", position: 3, name: "Corte") }

  def task_for(step) = described_class.new(challenge: challenge, step: step)

  def suggestion_for(step)
    run = AiRun.create!(challenge: challenge, challenge_step: step, purpose: "suggest_criteria",
                        mode: "ai_assisted", status: "succeeded", provider: "fixture",
                        idempotency_key: SecureRandom.uuid)
    AiSuggestion.create!(ai_run: run, payload: {}, status: "pending", challenge_step: step)
  end

  describe "lo que se le pide al modelo" do
    # Una selección FILTRA y una evaluación PUNTÚA. Pedir lo mismo para las dos
    # da criterios que no sirven para ninguna.
    it "a una evaluación le pide criterios que puntúan" do
      expect(task_for(evaluacion).system_prompt).to include("se puntúa cada idea")
    end

    it "y a una selección, condiciones que se cumplen o no" do
      expect(task_for(seleccion).system_prompt).to include("CUMPLIR para avanzar")
    end

    it "manda el brief y el nombre del módulo" do
      prompt = task_for(evaluacion).messages.last[:content]
      expect(prompt).to include("Bajar la merma en bodega.", "«Técnica»")
    end

    # Sin las claves reales, un criterio automático apunta a un campo que no
    # existe y no lo puede cumplir nadie — el mismo bug que ya arreglamos en
    # generate_ideas.
    it "ofrece los campos del formulario que se pueden verificar" do
      prompt = task_for(evaluacion).messages.last[:content]
      expect(prompt).to include("titulo", "problema", "solucion")
      expect(prompt).not_to include("adjunto")
    end

    it "y el schema solo admite esas claves" do
      enum = task_for(evaluacion).schema.dig("properties", "criteria", "items", "properties", "field_key", "enum")
      expect(enum).to eq(%w[titulo problema solucion])
    end
  end

  describe "al aplicar la propuesta" do
    let(:payload) do
      {
        "name" => "Criterios técnicos",
        "description" => "Impacto contra esfuerzo.",
        "criteria" => [
          { "name" => "Impacto", "weight" => 50, "source" => "manual", "scale_type" => "numeric" },
          { "name" => "Esfuerzo", "weight" => 30, "source" => "manual", "scale_type" => "numeric",
            "lower_is_better" => true },
          { "name" => "Está desarrollada", "weight" => 20, "source" => "automatic",
            "check" => "field_present", "field_key" => "solucion", "min_length" => 120 }
        ]
      }
    end

    def aplicar(step: evaluacion, data: payload)
      task_for(step).apply!(data, suggestion: suggestion_for(step))
    end

    it "crea un set PROPIO del módulo, no uno de biblioteca" do
      aplicar

      set = evaluacion.reload.criteria_set
      expect(set.scope).to eq("inline")
      expect(set.owner_step_id).to eq(evaluacion.id)
      expect(set.name).to eq("Criterios técnicos")
    end

    it "traduce cada criterio a los dos ejes del dominio" do
      aplicar
      criterios = evaluacion.reload.criteria_set.criteria.ordered

      esfuerzo = criterios.find { |c| c.name == "Esfuerzo" }
      expect(esfuerzo.scale_config["direction"]).to eq("lower_better")

      automatico = criterios.find(&:automatic?)
      expect(automatico.source_config).to eq("check" => "field_present", "field_key" => "solucion",
                                             "min_length" => 120)
      # El origen manda sobre la forma: un automático siempre es sí/no.
      expect(automatico.scale_type).to eq("boolean")
    end

    it "el set queda válido y usable" do
      aplicar

      set = evaluacion.reload.criteria_set
      expect(set.validation_errors).to be_empty
      expect(set.status).to eq("valid")
    end

    # Un 95 o un 105 dejarían el set inválido por un redondeo del modelo, no
    # por un error de criterio.
    it "renormaliza los pesos aunque no sumen 100" do
      torcido = payload.merge("criteria" => payload["criteria"].map { |c| c.merge("weight" => c["weight"] * 0.9) })
      aplicar(data: torcido)

      set = evaluacion.reload.criteria_set
      expect(set.weight_total.to_f).to be_within(0.001).of(1.0)
      expect(set.validation_errors).to be_empty
    end

    # La expresión referencia las claves de los criterios hermanos, que se
    # derivan del nombre recién al guardar: el modelo no las puede conocer.
    it "no se le ofrece proponer fórmulas" do
      enum = task_for(evaluacion).schema.dig("properties", "criteria", "items", "properties", "source", "enum")
      expect(enum).not_to include("formula")
      expect(enum).to include("manual", "automatic", "ai")
    end

    # Si uno queda afuera, los pesos ya no suman 100 y el módulo no podría
    # arrancar por culpa de un criterio que ni siquiera existe.
    it "reparte los pesos entre los que sí entraron cuando alguno falla" do
      roto = payload.merge("criteria" => payload["criteria"] + [
        { "name" => "Sin verificación", "weight" => 40, "source" => "automatic" }
      ])
      ok, errores = aplicar(data: roto)

      expect(ok).to be(true)
      expect(errores.join).to include("Sin verificación")
      set = evaluacion.reload.criteria_set
      expect(set.weight_total.to_f).to be_within(0.001).of(1.0)
      expect(set.validation_errors).to be_empty
    end

    # Los criterios se congelan al activar el módulo: reescribirlos después
    # cambiaría el sentido de lo ya evaluado.
    it "no toca un módulo que ya se ejecutó" do
      evaluacion.update_column(:status, "completed")

      ok, errores = aplicar
      expect(ok).to be(false)
      expect(errores.join).to include("congelados")
      expect(evaluacion.reload.criteria_set).to be_nil
    end

    # Una rúbrica con los niveles genéricos 1/3/5 contradice al criterio a
    # medida que la acompaña: el punto de elegirla son los descriptores.
    it "una rúbrica llega con sus propios niveles, ordenados por valor" do
      con_rubrica = payload.merge("criteria" => [
        payload["criteria"].first.merge(
          "scale_type" => "rubric", "weight" => 100,
          "levels" => [
            { "label" => "Decisivo", "value" => 5, "descriptor" => "Revierte el alza entera." },
            { "label" => "Marginal", "value" => 1, "descriptor" => "Un punto o menos." }
          ]
        )
      ])
      aplicar(data: con_rubrica)

      niveles = evaluacion.reload.criteria_set.criteria.first.scale_config["levels"]
      expect(niveles.map { |l| l["value"] }).to eq([1, 5])
      expect(niveles.last["descriptor"]).to eq("Revierte el alza entera.")
      expect(niveles.first["key"]).to eq("1")
    end

    it "y una escala numérica no inventa niveles" do
      aplicar
      numerico = evaluacion.reload.criteria_set.criteria.find { |c| c.name == "Impacto" }
      expect(numerico.scale_config).not_to have_key("levels")
    end

    # La `key` valida contra 40 caracteres. Un nombre largo generaba una clave
    # más larga y el criterio se rechazaba entero: de cinco propuestos entraban
    # dos, y la pantalla igual decía «aplicada».
    it "un nombre largo no tumba al criterio: la clave se recorta" do
      largo = payload.merge("criteria" => [
        payload["criteria"].first.merge(
          "name" => "Claridad de expectativas en los primeros quince días remotos", "weight" => 100
        )
      ])
      ok, errores = aplicar(data: largo)

      expect(ok).to be(true)
      expect(errores).to be_empty
      criterio = evaluacion.reload.criteria_set.criteria.first
      expect(criterio.key.length).to be <= 40
      expect(criterio.name).to start_with("Claridad de expectativas")
    end

    it "el resumen dice qué propone y con qué peso" do
      expect(task_for(evaluacion).preview(payload)).to include("Impacto 50%", "Esfuerzo 30%")
    end
  end
end
