# frozen_string_literal: true

require "rails_helper"

# La fórmula la escribe el dueño del desafío. Es entrada de usuario que se
# evalúa: acá se verifica que NUNCA llegue a ejecutarse como código Ruby.
RSpec.describe Flow::Formula::Validator do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:set) { CriteriaSet.create!(name: "ICE") }

  before do
    set.criteria.create!(key: "impacto", name: "Impacto", weight: 0.4, scale_type: "numeric")
    set.criteria.create!(key: "confianza", name: "Confianza", weight: 0.3, scale_type: "numeric")
    set.criteria.create!(key: "esfuerzo", name: "Esfuerzo", weight: 0.3, scale_type: "numeric")
  end

  def formula(expression, key: "score")
    set.criteria.new(key: key, name: "Score", weight: 0, scale_type: "formula",
                     scale_config: { "expression" => expression, "output" => { "min" => 0, "max" => 10 } })
  end

  describe "fórmulas válidas" do
    it "acepta un modelo ICE" do
      expect(described_class.new(formula("(impacto * confianza) / esfuerzo"))).to be_valid
    end

    it "acepta funciones de la whitelist" do
      expect(described_class.new(formula("IF(esfuerzo > 8, 0, impacto)"))).to be_valid
      expect(described_class.new(formula("ROUND(MIN(impacto, confianza), 2)"))).to be_valid
    end
  end

  describe "inyección de código — NUNCA debe ejecutarse" do
    # dentaku es Ruby puro con parser propio: la expresión se convierte en AST
    # y se recorre, no se evalúa como código. Estos casos ni siquiera parsean.
    ataques = [
      'system("rm -rf /")',
      "`ls -la`",
      "`cat /etc/passwd`",
      "File.read('/etc/passwd')",
      "Kernel.exit",
      "eval('1+1')",
      "impacto.send(:class)",
      "%x{whoami}",
      "$stdout.puts(1)",
      "@instance_var",
      "impacto; system('id')"
    ]

    ataques.each do |expression|
      it "rechaza #{expression.inspect}" do
        validator = described_class.new(formula(expression))

        expect(validator).not_to be_valid
        expect(validator.errors).to be_present
      end
    end

    it "no ejecuta comandos ni siquiera al evaluar" do
      expect(File).not_to receive(:read)
      expect(Kernel).not_to receive(:system)

      expect do
        Flow::Formula::Calculator.new('system("id")').evaluate({ "impacto" => 1 })
      end.to raise_error(Flow::Errors::InvalidFormula)
    end

    it "una expresión gigante se rechaza ANTES de parsear" do
      validator = described_class.new(formula("impacto + " * 200 + "1"))

      expect(validator).not_to be_valid
      expect(validator.errors.join).to match(/no puede superar 500 caracteres/)
    end
  end

  describe "referencias" do
    it "rechaza un criterio inexistente y lo nombra" do
      validator = described_class.new(formula("impacto * sinergia"))

      expect(validator).not_to be_valid
      expect(validator.errors.join).to match(/«sinergia», que no es un criterio de este set/)
    end

    it "rechaza la auto-referencia" do
      validator = described_class.new(formula("score + 1", key: "score"))

      expect(validator).not_to be_valid
      expect(validator.errors.join).to match(/no puede referenciarse a sí misma/)
    end

    it "detecta un ciclo entre fórmulas y muestra el camino" do
      # El ciclo no se puede armar de una: cada criterio se valida al nacer.
      # Se construye como en la vida real — «score» existe primero, «neto»
      # lo referencia, y recién ahí alguien intenta cerrar el círculo.
      score = set.criteria.create!(
        key: "score", name: "Score", weight: 0, scale_type: "formula",
        scale_config: { "expression" => "impacto * confianza", "output" => { "min" => 0, "max" => 10 } }
      )
      set.criteria.create!(
        key: "neto", name: "Neto", weight: 0, scale_type: "formula",
        scale_config: { "expression" => "score * 2", "output" => { "min" => 0, "max" => 10 } }
      )
      set.criteria.reload

      score.scale_config = { "expression" => "neto + impacto", "output" => { "min" => 0, "max" => 10 } }
      validator = described_class.new(score)

      expect(validator).not_to be_valid
      expect(validator.errors.join).to match(/ciclo entre criterios: score → neto → score/)
    end
  end

  describe "funciones fuera de la whitelist" do
    it "rechaza una función no permitida" do
      validator = described_class.new(formula("SQRT(impacto)"))

      expect(validator).not_to be_valid
    end
  end

  it "una fórmula vacía no es válida" do
    expect(described_class.new(formula(""))).not_to be_valid
  end
end
