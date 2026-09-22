# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flow::Checks::TestingPassed do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:tester) { without_tenant { create(:user) } }
  let(:challenge) { create(:challenge) }
  let!(:ideation) { seed_form!(challenge.steps.create!(kind: "ideation", position: 1)) }

  let!(:idea) do
    i = create(:idea, challenge: challenge, status: "active")
    Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Bicis" }).call
    i.update!(submitted_at: Time.current)
    i.reload
  end

  def modulo_de_testing(position)
    step = challenge.steps.create!(kind: "testing", position: position,
                                   name: "Prueba #{position}")
    challenge.update!(status: "running")
    Flow::Handlers::Base.for(step).activate!
    step.reload
  end

  def testear!(step, veredicto, reservas: [])
    step.handler.testear!(idea: idea, verdict: veredicto, tested_by: tester,
                          situations: [], reservations: reservas, summary: "Probado")
  end

  def check(params = {})
    criterion = Criterion.new(source: "automatic",
                              source_config: { "check" => "testing_passed" }.merge(params))
    described_class.new(criterion)
  end

  describe "accepts" do
    it "con el default, «con reservas» pasa" do
      testear!(modulo_de_testing(2), "con_reservas", reservas: %w[una otra])
      resultado = check.call(idea)

      expect(resultado).to be_passed
      expect(resultado.detail).to eq("Factible con 2 reservas")
    end

    it "con solo_factible, «con reservas» no pasa" do
      testear!(modulo_de_testing(2), "con_reservas")

      expect(check("accepts" => "solo_factible").call(idea)).not_to be_passed
    end

    it "«no factible» no pasa con ninguno de los dos" do
      testear!(modulo_de_testing(2), "no_factible")

      expect(check.call(idea)).not_to be_passed
      expect(check("accepts" => "solo_factible").call(idea)).not_to be_passed
    end
  end

  describe "sin_testeo" do
    # El default es `pasa`, por simetría con `feedback_addressed` («no se puede
    # tener sin atender lo que nadie comentó») y porque un check permisivo por
    # defecto se aprieta, mientras que uno restrictivo sorprende.
    it "sin testeo, por default pasa" do
      modulo_de_testing(2)
      resultado = check.call(idea)

      expect(resultado).to be_passed
      expect(resultado.detail).to eq("sin testear")
    end

    it "pero se puede configurar que no" do
      modulo_de_testing(2)

      expect(check("sin_testeo" => "no_pasa").call(idea)).not_to be_passed
    end
  end

  # La trampa de `feedback_addressed` con otra tabla: un check no sabe en qué
  # módulo lo corren, así que «el testeo» es el del módulo de testing MÁS
  # RECIENTE que probó esta idea. Mirando todos, un veredicto viejo decidiría
  # para siempre.
  it "con dos módulos de testing mira el más reciente" do
    testear!(modulo_de_testing(2), "no_factible")
    testear!(modulo_de_testing(3), "factible")

    expect(check.call(idea)).to be_passed
  end

  # Un testeo superado no es el vigente: re-testear no edita, marca el
  # anterior y escribe otro.
  it "ignora los testeos superados" do
    step = modulo_de_testing(2)
    testear!(step, "no_factible")
    testear!(step, "factible")

    expect(check.call(idea)).to be_passed
  end

  it "declara su tipo en TYPES" do
    expect(Flow::Checks::Base::TYPES).to include("testing_passed")
  end

  # El detail no es texto de debug: se lee en la celda del filtro del
  # ranking (Task 6), así que tiene que decir cuál caso fue y no tartamudear
  # cuando el veredicto ya trae la palabra «reservas» adentro. Las seis
  # combinaciones: tres veredictos, con y sin reservas cargadas.
  describe "detail" do
    it "factible, sin reservas" do
      testear!(modulo_de_testing(2), "factible")
      expect(check.call(idea).detail).to eq("Factible")
    end

    it "factible, con reservas cargadas" do
      testear!(modulo_de_testing(2), "factible", reservas: %w[una otra])
      expect(check.call(idea).detail).to eq("Factible con 2 reservas")
    end

    it "con reservas, sin reservas cargadas" do
      testear!(modulo_de_testing(2), "con_reservas")
      expect(check.call(idea).detail).to eq("Factible con reservas")
    end

    # El bug: el label de `con_reservas` YA dice «con reservas», así que
    # sumarle el conteo encima con la redacción vieja duplicaba la frase
    # («Factible con reservas con 2 reservas»).
    it "con reservas, con reservas cargadas" do
      testear!(modulo_de_testing(2), "con_reservas", reservas: %w[una otra])
      expect(check.call(idea).detail).to eq("Factible con 2 reservas")
    end

    it "no factible, sin reservas" do
      testear!(modulo_de_testing(2), "no_factible")
      expect(check.call(idea).detail).to eq("No factible")
    end

    # Nada en el modelo impide que un testeo no factible traiga reservas
    # cargadas: el texto tiene que servir igual.
    it "no factible, con reservas cargadas" do
      testear!(modulo_de_testing(2), "no_factible", reservas: %w[una otra])
      expect(check.call(idea).detail).to eq("No factible con 2 reservas")
    end
  end
end
