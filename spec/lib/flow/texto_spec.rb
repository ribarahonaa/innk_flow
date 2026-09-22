# frozen_string_literal: true

require "rails_helper"

# El inflector de Rails es inglés: le pega una «s» a todo. En una app en
# español eso se ve en pantalla —«2 condicións», «3 evaluacións»— y quedó así
# hasta que alguien miró una captura.
RSpec.describe Flow::Texto do
  # `contar` acuerda el SUSTANTIVO, y con eso no alcanza: la frase que lo
  # envuelve trae su propio verbo, y «Faltan 1 idea» se lee mal en la pantalla
  # aunque «1 idea» esté bien. Mismo bug que el de arriba, un nivel más afuera,
  # y descubierto igual: mirando una captura.
  describe ".faltan" do
    it "acuerda el verbo con el número, no sólo el sustantivo" do
      expect(described_class.faltan(1, "idea")).to eq("Falta 1 idea")
      expect(described_class.faltan(2, "idea")).to eq("Faltan 2 ideas")
    end

    it "pluraliza el sustantivo como `contar`" do
      expect(described_class.faltan(2, "veredicto")).to eq("Faltan 2 veredictos")
      expect(described_class.faltan(3, "condición")).to eq("Faltan 3 condiciones")
    end

    # Cero es plural en español: «Faltan 0 ideas», no «Falta 0 idea».
    it "trata el cero como plural" do
      expect(described_class.faltan(0, "idea")).to eq("Faltan 0 ideas")
    end
  end

  describe ".contar" do
    it "acuerda el sustantivo con el número" do
      expect(described_class.contar(1, "idea")).to eq("1 idea")
      expect(described_class.contar(3, "idea")).to eq("3 ideas")
    end

    # Aguda terminada en n: suma sílaba y pierde la tilde.
    it "pluraliza las agudas como corresponde" do
      expect(described_class.contar(2, "condición")).to eq("2 condiciones")
      expect(described_class.contar(2, "evaluación")).to eq("2 evaluaciones")
      expect(described_class.contar(2, "versión")).to eq("2 versiones")
      expect(described_class.contar(2, "interés")).to eq("2 intereses")
    end

    it "resuelve consonante, vocal y -z" do
      expect(described_class.plural("gestor")).to eq("gestores")
      expect(described_class.plural("módulo")).to eq("módulos")
      expect(described_class.plural("voz")).to eq("voces")
      expect(described_class.plural("campo")).to eq("campos")
    end
  end

  # Las reglas del español viven en su propio juego de inflexiones: el de
  # inglés es el que Rails usa para deducir nombres de tabla y de clase, y una
  # regla como «consonante → -es» ahí rompería medio framework.
  it "no toca la pluralización que usa Rails por dentro" do
    expect("user".pluralize).to eq("users")
    expect("challenge_step".pluralize).to eq("challenge_steps")
    expect("criterion".pluralize).to eq("criteria")
    expect("gestor".pluralize).to eq("gestores")
  end
end
