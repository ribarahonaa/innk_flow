# frozen_string_literal: true

require "rails_helper"

# El adapter de embeddings de OpenAI.
#
# Lo común con Voyage —orden por índice, lotes, validación de dimensión— vive
# en HttpEmbeddings y se prueba allá. Acá va lo que es SUYO: qué manda y cómo
# lee sus errores.
RSpec.describe Flow::AI::Providers::Openai do
  subject(:provider) { described_class.new }

  let(:dims) { Flow::AI::EMBEDDING_DIMENSIONS }

  it "es de embeddings, no de chat" do
    expect(provider.embeddings?).to be(true)
    expect { provider.complete(messages: [], schema: {}, purpose: "x") }
      .to raise_error(Flow::Errors::ProviderUnsupported, /solo hace embeddings/)
  end

  # El modelo sale nativo en 1536: sin pedirle `dimensions`, el vector no
  # entra en la columna y el backfill muere en la primera versión.
  it "pide explícitamente la dimensión de la columna" do
    cuerpo = provider.send(:request_body, %w[uno dos])

    expect(cuerpo[:dimensions]).to eq(dims)
    expect(cuerpo[:model]).to eq(described_class::DEFAULT_MODEL)
    expect(cuerpo[:input]).to eq(%w[uno dos])
    # `input_type` es de Voyage: OpenAI rechaza parámetros que no conoce.
    expect(cuerpo).not_to have_key(:input_type)
  end

  it "apunta al endpoint de embeddings" do
    expect(provider.send(:endpoint).to_s).to eq("https://api.openai.com/v1/embeddings")
  end

  it "lee el error donde OpenAI lo pone" do
    allow(provider).to receive(:post).and_return(
      { "__status" => "400", "error" => { "message" => "Invalid model" } }
    )

    expect { provider.embed(texts: ["uno"]) }
      .to raise_error(Flow::Errors::EmbeddingFailed, /HTTP 400.*Invalid model/)
  end

  # Los dos códigos que más se malinterpretan leyendo el mensaje crudo.
  it "explica el 401 y el 429, que no se leen solos" do
    allow(provider).to receive(:post).and_return(
      { "__status" => "401", "error" => { "message" => "Incorrect API key" } }
    )
    expect { provider.embed(texts: ["uno"]) }.to raise_error(/organización correcta/)

    allow(provider).to receive(:post).and_return(
      { "__status" => "429", "error" => { "message" => "Rate limit" } }
    )
    expect { provider.embed(texts: ["uno"]) }.to raise_error(/crédito agotado/)
  end

  it "sin credencial dice cuál falta y dónde se saca" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return(nil)

    expect { provider.send(:api_key) }
      .to raise_error(Flow::Errors::EmbeddingFailed, /OPENAI_API_KEY.*platform\.openai\.com/)
  end
end
