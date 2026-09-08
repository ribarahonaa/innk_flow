# frozen_string_literal: true

require "rails_helper"

RSpec.describe EstilosHelper, type: :helper do
  it "devuelve el nombre completo, no un fragmento" do
    expect(helper.chip_de_estado("completed")).to eq("status-chip status-chip--completed")
  end

  # Sin esto, un estado nuevo dejaría el elemento sin ninguna clase y el
  # síntoma sería un chip invisible en vez de un error.
  it "cae al neutro con un estado que no conoce" do
    expect(helper.chip_de_estado("inventado")).to eq("status-chip status-chip--pending")
    expect(helper.chip_de_estado(nil)).to eq("status-chip status-chip--pending")
  end

  it "acepta símbolos igual que strings" do
    expect(helper.chip_de_estado(:active)).to eq(helper.chip_de_estado("active"))
  end

  it "traduce una corrida de IA sin que la vista sepa el ternario" do
    ok = instance_double("AiRun", succeeded?: true, failed?: false)
    mal = instance_double("AiRun", succeeded?: false, failed?: true)
    curso = instance_double("AiRun", succeeded?: false, failed?: false)

    expect(helper.chip_de_corrida_de_ia(ok)).to include("--completed")
    expect(helper.chip_de_corrida_de_ia(mal)).to include("--skipped")
    expect(helper.chip_de_corrida_de_ia(curso)).to include("--pending")
  end
end
