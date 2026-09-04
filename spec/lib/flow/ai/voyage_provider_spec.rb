# frozen_string_literal: true

require "rails_helper"

# El proveedor de embeddings.
#
# No se llama a la API en los specs: se prueba lo que es del adapter —cómo lee
# la respuesta, cómo la parte en lotes y qué hace con cada forma de fallar—.
RSpec.describe Flow::AI::Providers::Voyage do
  subject(:provider) { described_class.new }

  let(:dims) { Flow::AI::EMBEDDING_DIMENSIONS }

  def vector(seed) = Array.new(dims) { |i| ((i + seed) % 10) / 10.0 }

  def fila(index, seed) = { "index" => index, "embedding" => vector(seed) }

  it "es de embeddings, no de chat" do
    expect(provider.embeddings?).to be(true)
    expect { provider.complete(messages: [], schema: {}, purpose: "x") }
      .to raise_error(Flow::Errors::ProviderUnsupported, /solo hace embeddings/)
  end

  # La API no promete el orden. Sin respetar el índice, los vectores terminan
  # pegados a otro texto: cada idea con el significado de su vecina.
  it "respeta el índice de cada fila y no el orden en que llegan" do
    allow(provider).to receive(:post).and_return(
      { "data" => [fila(2, 30), fila(0, 10), fila(1, 20)] }
    )

    resultado = provider.embed(texts: %w[uno dos tres])

    expect(resultado.map(&:first)).to eq([vector(10).first, vector(20).first, vector(30).first])
  end

  it "parte en lotes lo que no entra en una llamada" do
    llamadas = []
    allow(provider).to receive(:post) do |lote|
      llamadas << lote.size
      { "data" => lote.each_with_index.map { |_, i| fila(i, i) } }
    end

    provider.embed(texts: Array.new(described_class::BATCH + 5) { |n| "texto #{n}" })

    expect(llamadas).to eq([described_class::BATCH, 5])
  end

  # La dimensión está fijada en la columna: un vector de otro tamaño no entra,
  # y enterarse acá es mucho mejor que a mitad de un backfill.
  it "rechaza vectores de otra dimensión, diciendo qué revisar" do
    allow(provider).to receive(:post).and_return({ "data" => [{ "index" => 0, "embedding" => [1.0, 2.0] }] })

    expect { provider.embed(texts: ["uno"]) }
      .to raise_error(Flow::Errors::EmbeddingFailed, /2 dimensiones.*espera #{dims}.*FLOW_EMBEDDINGS_MODEL/m)
  end

  it "explica el rechazo de la API en vez de reventar con un NoMethodError" do
    allow(provider).to receive(:post).and_return({ "detail" => "Invalid API key" })

    expect { provider.embed(texts: ["uno"]) }
      .to raise_error(Flow::Errors::EmbeddingFailed, /Invalid API key/)
  end

  it "sin texto no llama a nadie" do
    expect(provider).not_to receive(:post)
    expect(provider.embed(texts: [])).to eq([])
  end
  describe "qué modelo declara" do
    around do |example|
      previo = ENV["FLOW_EMBEDDINGS_MODEL"]
      example.run
    ensure
      previo.nil? ? ENV.delete("FLOW_EMBEDDINGS_MODEL") : ENV["FLOW_EMBEDDINGS_MODEL"] = previo
    end

    # Se guarda junto a cada vector: si dijera solo «voyage», cambiar de
    # voyage-3.5-lite a voyage-3.5 mezclaría vectores incomparables sin que
    # nadie se entere.
    it "identifica el modelo, no el proveedor" do
      ENV.delete("FLOW_EMBEDDINGS_MODEL")

      expect(provider.embedding_model).to eq(described_class::DEFAULT_MODEL)
      expect(provider.name).to eq("voyage")
    end

    # El compose declara la variable como string vacío cuando no está en el
    # .env, y `ENV.fetch(clave, default)` solo usa el default si la clave está
    # AUSENTE: con fetch se le mandaba a la API un modelo vacío.
    it "una variable vacía no es un modelo" do
      ENV["FLOW_EMBEDDINGS_MODEL"] = ""

      expect(provider.embedding_model).to eq(described_class::DEFAULT_MODEL)
    end

    it "respeta el modelo declarado" do
      ENV["FLOW_EMBEDDINGS_MODEL"] = "voyage-3.5"

      expect(provider.embedding_model).to eq("voyage-3.5")
    end
  end
  # Diagnosticar esto a mano llevó media hora de sondeos: el mensaje tiene que
  # llevar la conclusión, no obligar a repetirlos.
  it "ante un 5xx apunta a la cuenta, no al pedido" do
    allow(provider).to receive(:post).and_return({ "__status" => "500", "detail" => "Internal Server Error" })

    expect { provider.embed(texts: ["uno"]) }
      .to raise_error(Flow::Errors::EmbeddingFailed, /HTTP 500.*activada.*dashboard/m)
  end

  it "ante un 4xx no manda a mirar la cuenta: el pedido es el sospechoso" do
    allow(provider).to receive(:post).and_return({ "__status" => "400", "detail" => "bad input" })

    mensaje = begin
      provider.embed(texts: ["uno"])
    rescue Flow::Errors::EmbeddingFailed => e
      e.message
    end

    expect(mensaje).to include("HTTP 400", "bad input")
    expect(mensaje).not_to include("dashboard")
  end
end

