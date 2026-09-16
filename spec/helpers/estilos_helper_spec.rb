# frozen_string_literal: true

require "rails_helper"

RSpec.describe EstilosHelper, type: :helper do
  it "devuelve el nombre completo, no un fragmento" do
    expect(helper.chip_de_estado("completed")).to eq("badge badge-soft badge-success badge-sm font-semibold whitespace-nowrap")
  end

  # Sin esto, un estado nuevo dejaría el elemento sin ninguna clase y el
  # síntoma sería un chip invisible en vez de un error.
  it "cae al neutro con un estado que no conoce" do
    neutro = EstilosHelper::CHIP_DE_ESTADO.fetch("pending")
    expect(helper.chip_de_estado("inventado")).to eq(neutro)
    expect(helper.chip_de_estado(nil)).to eq(neutro)
  end

  it "acepta símbolos igual que strings" do
    expect(helper.chip_de_estado(:active)).to eq(helper.chip_de_estado("active"))
  end

  it "traduce una corrida de IA sin que la vista sepa el ternario" do
    ok = instance_double("AiRun", succeeded?: true, failed?: false)
    mal = instance_double("AiRun", succeeded?: false, failed?: true)
    curso = instance_double("AiRun", succeeded?: false, failed?: false)

    expect(helper.chip_de_corrida_de_ia(ok)).to eq(helper.chip_de_estado("completed"))
    expect(helper.chip_de_corrida_de_ia(mal)).to eq(helper.chip_de_estado("skipped"))
    expect(helper.chip_de_corrida_de_ia(curso)).to eq(helper.chip_de_estado("pending"))
  end

  it "pinta el flash de un redirect como alert" do
    expect(helper.clase_de_flash("notice")).to eq("alert alert-soft alert-success")
    expect(helper.clase_de_flash("alert")).to eq("alert alert-soft alert-error")
  end

  # Todas las familias de chip son `badge`. Un valor que quedó con el nombre
  # viejo (`status-chip`, `source-chip`…) se ve bien mientras la hoja todavía
  # tiene su regla, y se rompe en silencio el día que la Tarea 7 la borra.
  it "todos los chips son badge" do
    chips = [EstilosHelper::CHIP_DE_ESTADO, EstilosHelper::CHIP_DE_ORIGEN, EstilosHelper::CLASE_DE_FEEDBACK]
            .flat_map(&:values) << EstilosHelper::CHIP_DE_IA
    chips.each { |clase| expect(clase).to start_with("badge "), "«#{clase}» no es un badge" }
  end

  it "el chip de IA es uno solo" do
    expect(helper.chip_de_ia).to eq("badge badge-soft badge-secondary badge-xs font-bold tracking-wide")
  end

  # Escritos contra el ENUM y no contra una lista a mano: así un estado que
  # alguien agregue mañana al modelo rompe este spec en vez de pintarse con el
  # color del fallback.
  #
  # Contra las CLAVES del hash y no contra el sufijo de la clase: con `badge`
  # varios estados comparten la misma clase —el neutro—, así que la clase ya
  # no dice qué estado la pidió. Que el estado sea clave es exactamente «no cae
  # al fallback».
  def sin_mapear(enum, mapa) = enum.map(&:to_s) - mapa.keys

  it "cubre todos los estados de un desafío" do
    expect(sin_mapear(Challenge::STATUSES, EstilosHelper::CHIP_DE_ESTADO)).to be_empty
  end

  it "cubre todos los estados de un módulo" do
    expect(sin_mapear(ChallengeStep::STATUSES, EstilosHelper::CHIP_DE_ESTADO)).to be_empty
  end

  it "cubre todos los orígenes de un criterio" do
    expect(sin_mapear(Criterion::SOURCES, EstilosHelper::CHIP_DE_ORIGEN)).to be_empty
  end

  it "cubre todos los tipos de feedback" do
    expect(sin_mapear(FeedbackItem::KINDS, EstilosHelper::CLASE_DE_FEEDBACK)).to be_empty
  end

  it "cubre todos los estados de una entrada de módulo" do
    expect(sin_mapear(StepEntry::STATUSES, EstilosHelper::CLASE_DE_RESULTADO)).to be_empty
  end

  it "cubre todos los estados de un módulo en el mapa del flujo" do
    expect(sin_mapear(ChallengeStep::STATUSES, EstilosHelper::CLASE_DE_NODO_DE_FLUJO)).to be_empty
  end

  # `pipeline_builder.vue` pinta el chip de un módulo recién agregado —que
  # todavía no pasó por `PipelinePresenter`— con la cadena escrita a mano.
  # Tiene que ser la MISMA que devuelve el helper para "pending", o un módulo
  # nuevo se ve distinto de uno guardado.
  it "el builder usa el mismo chip de pendiente que el helper" do
    vue = File.read(Rails.root.join("app/javascript/components/pipeline_builder/pipeline_builder.vue"))
    expect(vue).to include("statusClass: '#{EstilosHelper::CHIP_DE_ESTADO.fetch("pending")}'")
  end

  # El muestrario de `make screens` mide el contraste de cada chip en los dos
  # temas. Un chip que el helper devuelve y el muestrario no tiene nunca se
  # mide en el tema en que ninguna pantalla lo muestre, y la guarda pasa en
  # verde sin haberlo mirado.
  it "el muestrario de las capturas tiene cada chip del helper" do
    script = File.read(Rails.root.join("script/capture_screens.js"))
    chips = [EstilosHelper::CHIP_DE_ESTADO, EstilosHelper::CHIP_DE_ORIGEN, EstilosHelper::CLASE_DE_FEEDBACK]
            .flat_map(&:values) << EstilosHelper::CHIP_DE_IA
    faltan = chips.uniq.reject { |clase| script.include?("'#{clase}'") }
    expect(faltan).to be_empty, "El muestrario no mide: #{faltan.join(" · ")}"
  end
end
