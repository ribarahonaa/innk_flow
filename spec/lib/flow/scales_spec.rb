# frozen_string_literal: true

require "rails_helper"

# La normalización a [0,1] es lo que hace comparables escalas distintas. Sin
# ella, el módulo de selección tendría que saber de qué escala vino cada nota.
RSpec.describe Flow::Scales do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:set) { CriteriaSet.create!(name: "Set") }

  def criterion(scale_type: "numeric", source: "manual", config: {}, key: "c")
    set.criteria.new(key: key, name: "Criterio", weight: 1,
                     source: source, scale_type: scale_type, scale_config: config)
  end

  describe "numeric" do
    it "normaliza 1-10 a 0..1" do
      scale = criterion(scale_type: "numeric", config: { "min" => 1, "max" => 10 }).scale

      expect(scale.call("1")).to eq([1.to_d, 0.to_d])
      expect(scale.call("10")).to eq([10.to_d, 1.to_d])
      expect(scale.call("5.5").last).to eq(0.5.to_d)
    end

    it "invierte la escala cuando menos es mejor" do
      # Costo, esfuerzo, riesgo: un 1 es excelente y un 10 es pésimo.
      scale = criterion(scale_type: "numeric",
                        config: { "min" => 1, "max" => 10, "direction" => "lower_better" }).scale

      expect(scale.call("1").last).to eq(1.to_d)
      expect(scale.call("10").last).to eq(0.to_d)
    end

    it "devuelve nil ante un valor no numérico" do
      expect(criterion(scale_type: "numeric").scale.call("no soy número")).to eq([nil, nil])
    end

    it "clampa fuera de rango en vez de romper" do
      scale = criterion(scale_type: "numeric", config: { "min" => 1, "max" => 10 }).scale
      expect(scale.call("99").last).to eq(1.to_d)
      expect(scale.call("-5").last).to eq(0.to_d)
    end
  end

  describe "letter" do
    let(:scale) do
      criterion(scale_type: "letter", config: {
                  "levels" => [{ "key" => "A", "value" => 4 }, { "key" => "B", "value" => 3 },
                               { "key" => "C", "value" => 2 }, { "key" => "F", "value" => 0 }]
                }).scale
    end

    it "mapea letras a [0,1]" do
      expect(scale.call("A")).to eq([4.to_d, 1.to_d])
      expect(scale.call("F")).to eq([0.to_d, 0.to_d])
      expect(scale.call("C").last).to eq(0.5.to_d)
    end

    it "ignora una letra que no está en la escala" do
      expect(scale.call("Z")).to eq([nil, nil])
    end

    it "exige al menos dos niveles" do
      bad = criterion(scale_type: "letter", config: { "levels" => [{ "key" => "A", "value" => 1 }] }).scale
      expect(bad.config_errors).to include(/al menos dos niveles/)
    end
  end

  describe "rubric" do
    it "es una escala de niveles con prosa: misma matemática que letter" do
      scale = criterion(scale_type: "rubric", config: {
                          "levels" => [
                            { "key" => "1", "value" => 1, "descriptor" => "Sin impacto" },
                            { "key" => "5", "value" => 5, "descriptor" => "Toda la empresa" }
                          ]
                        }).scale

      expect(scale.call("5")).to eq([5.to_d, 1.to_d])
      expect(scale.options.first.first).to eq("1 · Sin impacto")
      expect(scale.descriptors["5"]).to eq("Toda la empresa")
    end
  end

  describe "formula" do
    it "es un criterio DERIVADO: no lo completa el evaluador" do
      scale = criterion(source: "formula", config: { "expression" => "1 + 1" }).scale
      expect(scale).to be_derived
    end

    it "normaliza el resultado contra el rango de salida" do
      scale = criterion(source: "formula",
                        config: { "expression" => "impacto", "output" => { "min" => 0, "max" => 10 } }).scale

      expect(scale.normalize(5.to_d)).to eq(0.5.to_d)
    end
  end

  describe "todas las escalas juntas" do
    it "producen valores comparables entre sí" do
      # Es la propiedad central: 8/10, una B y una fórmula que da 6/10 tienen
      # que poder ordenarse en la misma tabla de selección.
      numeric = criterion(scale_type: "numeric", config: { "min" => 0, "max" => 10 }, key: "n").scale
      letter = criterion(scale_type: "letter", key: "l", config: {
                           "levels" => [{ "key" => "A", "value" => 10 }, { "key" => "B", "value" => 8 },
                                        { "key" => "C", "value" => 0 }]
                         }).scale

      expect(numeric.call("8").last).to eq(letter.call("B").last)
    end
  end
end
