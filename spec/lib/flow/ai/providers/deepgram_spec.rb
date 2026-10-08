# frozen_string_literal: true

require "rails_helper"

# Lo que se prueba es la NORMALIZACIÓN y no la llamada: el repo no tiene webmock
# y sus otros dos adapters HTTP no tienen spec. El fixture es una respuesta real
# de nova-3, recortada; las claves son las que la API devuelve de verdad.
RSpec.describe Flow::AI::Providers::Deepgram do
  subject(:provider) { described_class.new }

  let(:body) { JSON.parse(Rails.root.join("spec/fixtures/ai/deepgram_response.json").read) }

  it "declara que transcribe y que no completa" do
    expect(provider.transcription?).to be(true)
    expect { provider.complete(messages: [], schema: {}, purpose: "x") }
      .to raise_error(Flow::Errors::ProviderUnsupported)
  end

  describe "#normalize" do
    it "devuelve una fila por utterance, con las seis claves" do
      filas = provider.normalize(body)

      expect(filas.size).to eq(2)
      expect(filas.first).to eq(
        "speaker" => 0, "start" => 0.08, "end" => 5.12,
        "transcript" => "We should reduce the waste in the winery by reusing the barrels.",
        "confidence" => 0.99538165, "speaker_confidence" => 0.4120001
      )
    end

    it "el speaker_confidence es el MÍNIMO de las palabras, no el de la primera" do
      # Las tres palabras de la primera utterance traen 0.6869923, 0.6869923 y
      # 0.4120001. Tomar la primera diría 0.69 sobre una utterance donde el
      # diarizador dudó bastante más: el mínimo es el lado conservador, y esta
      # señal existe justamente para delatar una diarización insegura.
      expect(provider.normalize(body).first["speaker_confidence"]).to eq(0.4120001)
    end

    it "no revienta si no vienen utterances" do
      # Pasa si alguien saca `utterances=true` de la query, o si la API cambia.
      # Caer a una lista vacía deja la grabación `ready` sin texto, que es un
      # estado que el dominio ya sabe mostrar; un NoMethodError sobre nil
      # dejaría la fila en `transcribing` para siempre.
      sin = body.tap { |b| b["results"].delete("utterances") }

      expect(provider.normalize(sin)).to eq([])
    end

    it "no revienta con un cuerpo vacío" do
      expect(provider.normalize({})).to eq([])
    end

    it "una utterance sin words no se cae: el speaker_confidence queda en nil" do
      body["results"]["utterances"].first.delete("words")

      expect(provider.normalize(body).first["speaker_confidence"]).to be_nil
    end
  end

  describe "#metadata_from" do
    it "saca duración, request_id y el nombre del modelo" do
      expect(provider.metadata_from(body)).to eq(
        "duration" => 16.906187,
        "request_id" => "01a11c7e-3b94-7b50-b9d0-d064768a409e",
        "model" => "general-nova-3"
      )
    end

    it "sin metadata devuelve el hash con nils y no revienta" do
      expect(provider.metadata_from({})).to eq(
        "duration" => nil, "request_id" => nil, "model" => nil
      )
    end
  end
end
