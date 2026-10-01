# frozen_string_literal: true

require "rails_helper"

# El reparto, sin base de datos: grupos indivisibles y un tamaño.
#
# Idear no es otro algoritmo: es este con grupos de una persona.
RSpec.describe Flow::Workshops::Seating do
  def repartir(groups, size) = described_class.new(groups: groups, size: size).call

  describe "sin nada compartido (el caso de idear)" do
    it "reparte por cabeza hasta el tamaño" do
      grupos = (1..5).to_h { |i| ["g#{i}", ["u#{i}"]] }

      result = repartir(grupos, 2)

      expect(result.tables.map(&:size)).to eq([2, 2, 1])
      expect(result.tables.flatten.sort).to eq(%w[u1 u2 u3 u4 u5])
      expect(result.splits).to be_empty
    end
  end

  describe "con gente compartida" do
    it "deja el racimo junto si entra" do
      # i1 y i2 comparten a b: un solo racimo de tres personas.
      result = repartir({ "i1" => %w[a b], "i2" => %w[b c] }, 4)

      expect(result.tables).to eq([%w[a b c]])
      expect(result.splits).to be_empty
    end

    it "desprende la idea de menor solape, y la compartida se queda" do
      # i1 y i2 comparten a y b; i3 comparte sólo a c. Con tamaño 4 el racimo
      # tiene cinco personas: i3 se va, y i1 + i2 (a b c d) entran justas.
      result = repartir({ "i1" => %w[a b c], "i2" => %w[a b d], "i3" => %w[c e] }, 4)

      expect(result.tables).to include(%w[e])
      expect(result.tables.find { |t| t.include?("c") }).to include("a", "b")
      expect(result.splits.map(&:group_key)).to eq(["i3"])
      expect(result.splits.first.shared_user_ids).to eq(["c"])
      expect(result.splits.first.inside).to be(false)
    end

    it "no arma una mesa vacía cuando la idea desprendida no tiene gente propia" do
      # Review Focus 4: la gente de i2 está toda en i1.
      result = repartir({ "i1" => %w[a b c], "i2" => %w[a b] }, 2)

      expect(result.tables).to all(be_present)
    end

    it "ante un empate de solape desprende la de menos gente" do
      # El desempate por tamaño es lo único que decide acá: i1 e i2 empatan en
      # solape, así que se desprende la de MENOS gente. Sin ese desempate se
      # desprendería i1, y las mesas saldrían iguales — por eso se mira `splits`
      # y no `tables`.
      result = repartir({ "i1" => %w[a b c], "i2" => %w[a b] }, 2)

      # i1 queda sola con tres personas y no entra: de ahí el segundo aviso.
      expect(result.splits.map { |s| [s.group_key, s.inside] }).to eq([["i2", false], ["i1", true]])
    end
  end

  describe "un grupo sin nadie" do
    it "no arma mesa ni aparece entre lo partido" do
      # En evolución, una idea cuya única persona está ausente llega así.
      result = repartir({ "i1" => %w[a], "i2" => [] }, 2)

      expect(result.tables).to eq([%w[a]])
      expect(result.splits).to be_empty
    end
  end

  describe "el caso extremo: una sola idea más grande que el tamaño" do
    it "la parte, y lo dice con su propio aviso" do
      result = repartir({ "i1" => %w[a b c d e] }, 2)

      expect(result.tables.map(&:size)).to eq([2, 2, 1])
      expect(result.splits.map(&:inside)).to eq([true])
      expect(result.splits.first.group_key).to eq("i1")
    end
  end

  describe "el tamaño" do
    # Review Focus 3.
    it "menor que 1 se trata como 1" do
      expect(repartir({ "i1" => %w[a b] }, 0).tables).to eq([%w[a], %w[b]])
    end

    it "mayor que todo el pool da una sola mesa" do
      expect(repartir({ "i1" => %w[a], "i2" => %w[b] }, 99).tables).to eq([%w[a b]])
    end
  end

  # Dos corridas del mismo taller tienen que dar las mismas mesas, y el orden
  # en que llegan los grupos no puede filtrarse al resultado. Se afirma una
  # salida concreta: comparar una corrida contra sí misma no puede fallar.
  it "es determinista" do
    grupos = { "i3" => %w[c e], "i1" => %w[a b c], "i2" => %w[a b d] }
    esperado = [%w[a b d], %w[c e]]

    expect(repartir(grupos, 3).tables).to eq(esperado)
    expect(repartir(grupos.to_a.reverse.to_h, 3).tables).to eq(esperado)
  end
end
