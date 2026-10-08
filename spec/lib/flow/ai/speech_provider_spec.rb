# frozen_string_literal: true

require "rails_helper"

# El cuarto eje. Son TRES variables y no una porque son tres capacidades
# distintas y ningún proveedor tiene las tres: Anthropic no expone embeddings ni
# transcripción, Voyage sólo vectores, Deepgram sólo voz.
RSpec.describe "Flow::AI.speech_provider" do
  after { Flow::AI.reset_provider! }

  # Los dos ejemplos de la CASCADA tienen que ver la variable ausente, y por eso
  # se la stubea en vez de confiar en el ambiente. `app_test` fija
  # `FLOW_SPEECH_PROVIDER: fixture` —igual que los otros dos ejes, para que el
  # contenedor de test no pueda llegar a un proveedor real ni depender de una
  # credencial—, así que sin esto la primera rama de `build_speech_provider` gana
  # siempre: el ejemplo de «la MISMA instancia» quedaba ROJO y el del fallback,
  # verde midiendo nada (los dos caminos devuelven un Fixture). Que la ausencia
  # fuera un dato del entorno era una dependencia escondida.
  def sin_variable_declarada
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("FLOW_SPEECH_PROVIDER").and_return(nil)
  end

  it "usa el declarado en FLOW_SPEECH_PROVIDER" do
    Flow::AI.reset_provider!
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("FLOW_SPEECH_PROVIDER").and_return("null")

    # `null` y no `fixture`: el fallback también da un Fixture, así que con
    # `fixture` el ejemplo pasaría aunque se borrara la rama de la variable.
    # Un Null sólo puede salir de ahí.
    expect(Flow::AI.speech_provider).to be_a(Flow::AI::Providers::Null)
  end

  it "usa el de chat, la MISMA instancia, cuando sabe transcribir" do
    Flow::AI.reset_provider!
    sin_variable_declarada
    chat = Flow::AI::Providers::Fixture.new
    Flow::AI.provider = chat

    # `be` y no `be_a`: sin la rama del medio el fallback arma OTRO Fixture.
    expect(Flow::AI.speech_provider).to be(Flow::AI.provider)
  end

  it "cae al fixture cuando el de chat no sabe transcribir" do
    Flow::AI.reset_provider!
    sin_variable_declarada
    Flow::AI.provider = Flow::AI::Providers::Null.new

    expect(Flow::AI.provider.transcription?).to be(false)
    expect(Flow::AI.speech_provider).to be_a(Flow::AI::Providers::Fixture)
  end

  it "reset_provider! limpia los TRES, no dos" do
    Flow::AI.provider
    Flow::AI.embeddings_provider
    Flow::AI.speech_provider

    Flow::AI.reset_provider!

    # Si `@speech_provider` sobreviviera, un spec que cambia la variable de
    # entorno vería el proveedor de otro spec: contaminación entre ejemplos.
    %i[@provider @embeddings_provider @speech_provider].each do |ivar|
      expect(Flow::AI.instance_variable_get(ivar)).to be_nil, "#{ivar} sobrevivió"
    end
  end

  describe "el fixture" do
    let(:utterances) do
      Flow::AI::Providers::Fixture.new.transcribe(
        audio: "bytes", content_type: "audio/webm", language: "es"
      ).utterances
    end

    it "devuelve utterances con la forma normalizada" do
      expect(utterances).to be_an(Array)
      expect(utterances).not_to be_empty
      expect(utterances.first.keys).to include(
        "speaker", "start", "end", "transcript", "confidence", "speaker_confidence"
      )
    end

    it "es determinista: dos llamadas dan lo mismo" do
      otra = Flow::AI::Providers::Fixture.new.transcribe(
        audio: "bytes", content_type: "audio/webm", language: "es"
      ).utterances

      expect(utterances).to eq(otra)
    end

    it "trae DOS hablantes distintos" do
      # Con un solo hablante el fixture no podría ejercitar el aviso de
      # diarización colapsada: daría el aviso siempre, y la guarda que lo mide
      # no distinguiría «colapsó» de «el fixture es así».
      expect(utterances.map { |u| u["speaker"] }.uniq.size).to eq(2)
    end
  end

  it "el fixture declara que sabe transcribir" do
    expect(Flow::AI::Providers::Fixture.new.transcription?).to be(true)
  end

  it "la interfaz sin implementar levanta NotImplementedError" do
    # El contrato de `Provider`: un adapter nuevo que se olvide de `transcribe`
    # revienta con algo que dice qué falta.
    expect { Flow::AI::Provider.new.transcribe(audio: "x", content_type: "y", language: "es") }
      .to raise_error(NotImplementedError)
  end

  it "el Null levanta TranscriptionFailed y nombra la variable, no NotImplementedError" do
    # Acá cae un `FLOW_SPEECH_PROVIDER` mal escrito —`resolve` loguea y devuelve
    # Null—, y la diferencia es visible para la mesa: con el `NotImplementedError`
    # heredado, el `rescue Flow::Errors::TranscriptionFailed` del servicio no
    # matcheaba, así que la fila no se marcaba `failed`, `retry_on` tampoco, y
    # la tarjeta quedaba en «transcribiendo» sin texto de error para siempre.
    expect { Flow::AI::Providers::Null.new.transcribe(audio: "x", content_type: "y", language: "es") }
      .to raise_error(Flow::Errors::TranscriptionFailed, /FLOW_SPEECH_PROVIDER/)
  end

end
