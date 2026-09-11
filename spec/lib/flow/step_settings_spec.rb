# frozen_string_literal: true

require "rails_helper"

# El esquema es la fuente única de qué configura cada módulo. Antes el builder
# declaraba sus propios campos y quedó exponiendo 4 de las 13 opciones que los
# handlers leían: Evolución y Reportería no tenían nada que configurar.
RSpec.describe Flow::StepSettings do
  it "cubre los cinco tipos de módulo" do
    expect(described_class::SCHEMA.keys).to match_array(ChallengeStep::KINDS)
  end

  it "ningún módulo queda sin nada que configurar" do
    vacios = described_class::SCHEMA.reject { |_, groups| groups[:essential].any? }
    expect(vacios.keys).to be_empty
  end

  it "todo campo declara clave, tipo y etiqueta" do
    described_class::SCHEMA.each do |kind, groups|
      described_class.fields(kind).each do |field|
        expect(field[:key]).to be_present, "#{kind}: campo sin key"
        expect(field[:type]).to be_present, "#{kind}/#{field[:key]}: sin type"
        expect(field[:label]).to be_present, "#{kind}/#{field[:key]}: sin label"
      end
    end
  end

  it "los selects tienen opciones propias o una fuente dinámica" do
    described_class::SCHEMA.each_key do |kind|
      described_class.fields(kind).select { |f| f[:type].in?(%w[select multi_select]) }.each do |field|
        tiene = field[:options].present? || field[:source].present?
        expect(tiene).to be(true), "#{kind}/#{field[:key]}: select sin opciones ni source"
      end
    end
  end

  describe ".fields" do
    it "junta esencial y avanzado, en ese orden" do
      claves = described_class.fields("selection").map { |f| f[:key] }

      expect(claves).to eq(%w[source_step_id cut.mode cut.value
                              score_source.combine])
    end

    it "devuelve vacío para un kind que no existe" do
      expect(described_class.fields("inventado")).to eq([])
    end
  end

  describe ".filtrar" do
    it "arma las claves anidadas que declara el esquema" do
      resultado = described_class.filtrar("selection",
                                          "cut" => { "mode" => "top_n", "value" => "4" })

      expect(resultado).to eq("cut" => { "mode" => "top_n", "value" => 4 })
    end

    # El handler hace `.to_f`, así que un string no explota: se arrastra hasta
    # que alguien compara o serializa. Se castea acá, contra el tipo declarado.
    it "castea a número lo que el esquema declara número" do
      resultado = described_class.filtrar("evaluation", "min_assessments" => "3")

      expect(resultado["min_assessments"]).to eq(3)
    end

    it "descarta cualquier clave que el esquema no declare para ese kind" do
      resultado = described_class.filtrar("selection",
                                          "cut" => { "mode" => "top_n" },
                                          "min_assessments" => 9,
                                          "lo_que_sea" => "x")

      expect(resultado).to eq("cut" => { "mode" => "top_n" })
    end

    # `source_step_id` es `column: true`: no vive en config sino en su columna.
    it "no mete en config los campos que son columna" do
      resultado = described_class.filtrar("selection", "source_step_id" => "abc")

      expect(resultado).to eq({})
    end

    it "omite lo ausente y lo vacío en vez de guardar nil" do
      resultado = described_class.filtrar("selection",
                                          "cut" => { "mode" => "manual", "value" => "" })

      expect(resultado).to eq("cut" => { "mode" => "manual" })
    end

    it "no revienta con un kind desconocido" do
      expect(described_class.filtrar("inventado", "x" => 1)).to eq({})
    end

    # Los valores malformados que no coinciden con el tipo se descartan sin error.
    it "ignora un valor que no es hash cuando la ruta es anidada" do
      resultado = described_class.filtrar("selection",
                                          "cut" => "no_es_hash",
                                          "score_source" => { "combine" => "weighted_avg" })

      expect(resultado).to eq("score_source" => { "combine" => "weighted_avg" })
    end

    it "ignora un array cuando el tipo no es multi_select" do
      resultado = described_class.filtrar("evaluation",
                                          "min_assessments" => ["1", "2"],
                                          "evaluator_aggregation" => "mean")

      expect(resultado).to eq("evaluator_aggregation" => "mean")
    end

    it "ignora un hash cuando el tipo no es multi_select" do
      resultado = described_class.filtrar("evaluation",
                                          "min_assessments" => { "a" => "1" },
                                          "evaluator_aggregation" => "median")

      expect(resultado).to eq("evaluator_aggregation" => "median")
    end
  end

  describe "claves anidadas" do
    it "lee y escribe rutas con punto" do
      config = {}
      described_class.write(config, "cut.mode", "top_n")
      described_class.write(config, "cut.value", 10)

      expect(config).to eq("cut" => { "mode" => "top_n", "value" => 10 })
      expect(described_class.read(config, "cut.mode")).to eq("top_n")
    end

    it "no explota leyendo una ruta inexistente" do
      expect(described_class.read({}, "cut.mode")).to be_nil
    end
  end

  describe "defaults" do
    it "arma la config inicial de un módulo desde el esquema" do
      expect(described_class.defaults("selection")).to eq(
        "cut" => { "mode" => "manual", "value" => 10 },
        "score_source" => { "combine" => "weighted_avg" }
      )
    end

    it "no incluye los campos que viven en columnas" do
      expect(described_class.defaults("evaluation")).not_to have_key("criteria_set_id")
    end
  end

  # Lo que la IA puede proponer como `config` de un módulo. Sin esto la tarea
  # declaraba `config` como un objeto cualquiera, y el adapter de Anthropic
  # —que cierra todo objeto con `additionalProperties: false`— se lo mandaba
  # a la API como un objeto sin ninguna clave permitida.
  describe ".json_schema" do
    it "anida las claves como en config y tipa cada una" do
      schema = described_class.json_schema("selection")

      expect(schema.dig("properties", "cut", "properties", "mode", "enum"))
        .to eq(%w[manual top_n top_percent threshold])
      expect(schema.dig("properties", "cut", "properties", "value", "type")).to eq("number")
      expect(schema.dig("properties", "score_source", "properties", "combine", "enum"))
        .to eq(%w[weighted_avg max min last])
    end

    # `source_step_id` y `step_slugs` apuntan a módulos por id o por slug, y al
    # proponer un flujo esos módulos todavía no existen.
    it "deja afuera las columnas y los campos que eligen otros módulos" do
      expect(described_class.json_schema("selection")["properties"].keys).to contain_exactly("cut", "score_source")
      expect(described_class.json_schema("reporting")["properties"].keys).to contain_exactly("mode", "include_eliminated")
    end

    # La API poda `minimum`/`maximum` del pedido: el rango le llega al modelo
    # sólo por la descripción. El schema local los conserva y valida igual.
    it "describe cada campo con su etiqueta, su ayuda y su rango" do
      campo = described_class.json_schema("ideation").dig("properties", "generated_ideas")

      expect(campo["description"]).to include("Cuántas ideas genera la IA", "Solo aplica cuando", "entre 1 y 20")
      expect(campo).to include("minimum" => 1, "maximum" => 20, "default" => 5)
    end

    it "le traduce al modelo cada valor de un select a lo que significa" do
      modo = described_class.json_schema("selection").dig("properties", "cut", "properties", "mode")

      expect(modo["description"]).to include("`threshold` (Puntaje mínimo)", "`top_n` (Top N ideas)")
    end

    it "dice de qué otro campo depende uno que no siempre aplica" do
      valor = described_class.json_schema("selection").dig("properties", "cut", "properties", "value")

      expect(valor["description"]).to include("«Regla de corte»", "«Manual: el dueño decide»")
    end

    it "los defaults de cada kind validan contra su schema" do
      ChallengeStep::KINDS.each do |kind|
        errores = Flow::AI::SchemaValidator.errors_for(described_class.defaults(kind), described_class.json_schema(kind))
        expect(errores).to be_empty, "#{kind}: #{errores.join('; ')}"
      end
    end
  end

  # La cara de ejecución mostraba el valor tal cual sale de `config`: `false`,
  # `trimmed_mean` o `["ideation", "evaluation"]` con la sintaxis de
  # `Array#inspect`. `display_value` resuelve la etiqueta humana desde las
  # `options` del propio campo.
  describe ".display_value" do
    it "un boolean dice Sí o No, no true/false" do
      campo = { type: "boolean" }
      expect(described_class.display_value(campo, true)).to eq("Sí")
      expect(described_class.display_value(campo, false)).to eq("No")
    end

    it "un select busca la etiqueta de su option" do
      campo = described_class.fields("evaluation").find { |f| f[:key] == "evaluator_aggregation" }
      expect(described_class.display_value(campo, "trimmed_mean")).to eq("Promedio sin extremos")
    end

    it "un select sin option que matchee cae al valor crudo" do
      campo = described_class.fields("evaluation").find { |f| f[:key] == "evaluator_aggregation" }
      expect(described_class.display_value(campo, "inventado")).to eq("inventado")
    end

    it "un multi_select junta las etiquetas con comas" do
      campo = { type: "multi_select",
                options: [{ value: "a", label: "Uno" }, { value: "b", label: "Dos" }] }
      expect(described_class.display_value(campo, %w[a b])).to eq("Uno, Dos")
    end

    # `step_slugs` (reporting) es multi_select SIN `options` estáticas: el
    # `source:` es dinámico y este método no tiene ahí ningún desafío contra
    # el que resolver. Sin una `option` que matchee, junta los valores crudos
    # en vez de `Array#inspect`.
    it "un multi_select sin options se junta igual, sin corchetes ni comillas" do
      campo = described_class.fields("reporting").find { |f| f[:key] == "step_slugs" }
      expect(described_class.display_value(campo, %w[ideation evaluation])).to eq("ideation, evaluation")
    end

    it "un número o texto se muestra tal cual, como string" do
      expect(described_class.display_value({ type: "number" }, 7)).to eq("7")
    end
  end

  # La razón de ser del esquema: que no vuelva a haber opciones que el motor lee
  # y nadie puede tocar.
  describe "cobertura contra los handlers" do
    LEIDAS = {
      "ideation" => %w[min_ideas generated_ideas],
      "evolution" => %w[require_response],
      "evaluation" => %w[min_assessments evaluator_aggregation],
      "selection" => %w[cut.mode cut.value score_source.combine],
      "reporting" => %w[mode include_eliminated step_slugs]
    }.freeze

    LEIDAS.each do |kind, keys|
      it "#{kind}: toda opción que el handler lee está en el esquema" do
        declaradas = described_class.fields(kind).map { _1[:key] }
        expect(declaradas).to include(*keys)
      end
    end
  end
end
