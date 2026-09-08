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

  # Escritos contra el ENUM y no contra una lista a mano: así un estado que
  # alguien agregue mañana al modelo rompe este spec en vez de pintarse con
  # el color del fallback. `CHIP_DE_ESTADO` cubre DOS enums a la vez —el de
  # Challenge y el de ChallengeStep, que la hoja agrupa con el mismo color—,
  # así que se prueban los dos. Esto es lo que hubiera atrapado, en su
  # momento, que "draft"/"running"/"closed" (Challenge::STATUSES) y "issue"
  # (FeedbackItem::KINDS) y "advanced"/"eliminated" (StepEntry::STATUSES)
  # caían al fallback en vez de tener su propia clase.
  #
  # `end_with` y no `include`: la clase termina en el nombre del estado. Con
  # `include`, un helper que devolviera "--issued" pasaba el test de "issue"
  # —el sufijo es lo que distingue un estado del que lo tiene de prefijo—.
  it "cubre todos los estados de un desafío" do
    Challenge::STATUSES.each do |estado|
      expect(helper.chip_de_estado(estado)).to end_with("--#{estado}"),
        "«#{estado}» cae al fallback: es un color equivocado que nadie ve fallar"
    end
  end

  it "cubre todos los estados de un módulo" do
    ChallengeStep::STATUSES.each do |estado|
      expect(helper.chip_de_estado(estado)).to end_with("--#{estado}"),
        "«#{estado}» cae al fallback: es un color equivocado que nadie ve fallar"
    end
  end

  it "cubre todos los orígenes de un criterio" do
    Criterion::SOURCES.each do |source|
      expect(helper.chip_de_origen(source)).to end_with("--#{source}"),
        "«#{source}» cae al fallback: es un color equivocado que nadie ve fallar"
    end
  end

  it "cubre todos los tipos de feedback" do
    FeedbackItem::KINDS.each do |kind|
      expect(helper.clase_de_feedback(kind)).to end_with("--#{kind}"),
        "«#{kind}» cae al fallback: es un color equivocado que nadie ve fallar"
    end
  end

  it "cubre todos los estados de una entrada de módulo" do
    StepEntry::STATUSES.each do |status|
      expect(helper.clase_de_resultado(status)).to end_with("--#{status}"),
        "«#{status}» cae al fallback: es un color equivocado que nadie ve fallar"
    end
  end

  # El mapa compacto del flujo pinta los MISMOS estados que los chips, con otra
  # forma y en otro hash. Era el único de los seis sin nadie que lo recorriera
  # contra su enum, que es justo el agujero por el que ya se colaron
  # "draft"/"running"/"closed" en los chips y "advanced"/"eliminated" en los
  # resultados.
  it "cubre todos los estados de un módulo en el mapa del flujo" do
    ChallengeStep::STATUSES.each do |estado|
      expect(helper.clase_de_nodo_de_flujo(estado)).to end_with("--#{estado}"),
        "«#{estado}» cae al fallback: es un color equivocado que nadie ve fallar"
    end
  end
end
