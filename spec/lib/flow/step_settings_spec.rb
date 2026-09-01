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
        "cut" => { "mode" => "manual", "value" => 10, "tie_break" => "earliest_submission" },
        "score_source" => { "combine" => "weighted_avg" }
      )
    end

    it "no incluye los campos que viven en columnas" do
      expect(described_class.defaults("evaluation")).not_to have_key("criteria_set_id")
    end
  end

  # La razón de ser del esquema: que no vuelva a haber opciones que el motor lee
  # y nadie puede tocar.
  describe "cobertura contra los handlers" do
    LEIDAS = {
      "ideation" => %w[min_ideas generated_ideas],
      "evolution" => %w[require_response],
      "evaluation" => %w[min_assessments evaluator_aggregation],
      "selection" => %w[cut.mode cut.value score_source.combine cut.tie_break],
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
