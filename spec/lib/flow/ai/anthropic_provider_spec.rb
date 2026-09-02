# frozen_string_literal: true

require "rails_helper"

# El proveedor real.
#
# No se llama a la API en los specs: cada llamada cuesta plata y dependería de
# la red. Se prueba lo que es del adapter — cómo arma el pedido, cómo lee la
# respuesta y qué hace con cada forma de fallar.
RSpec.describe Flow::AI::Providers::Anthropic do
  subject(:provider) { described_class.new }

  let(:client) { instance_double(Anthropic::Client, messages: messages_api) }
  let(:messages_api) { instance_double(Anthropic::Resources::Messages) }

  before { allow(provider).to receive(:client).and_return(client) }

  let(:schema) do
    {
      "type" => "object",
      "required" => ["fields"],
      "properties" => {
        "fields" => {
          "type" => "array",
          "minItems" => 2,
          "maxItems" => 10,
          "items" => {
            "type" => "object",
            "required" => ["key"],
            "properties" => { "key" => { "type" => "string", "pattern" => "^[a-z]+$" } }
          }
        }
      }
    }
  end

  def response(content:, stop_reason: :end_turn, stop_details: nil, model: "claude-opus-5")
    instance_double(
      Anthropic::Models::Message,
      content: content, stop_reason: stop_reason, stop_details: stop_details,
      model: model, usage: instance_double(Anthropic::Models::Usage, input_tokens: 120, output_tokens: 45)
    )
  end

  def text_block(text) = instance_double(Anthropic::Models::TextBlock, type: :text, text: text)

  def valid_payload = { "fields" => [{ "key" => "titulo" }, { "key" => "problema" }] }

  describe "cómo arma el pedido" do
    it "manda el schema como salida estructurada y separa el turno system" do
      expect(messages_api).to receive(:create) do |**params|
        expect(params[:model]).to eq("claude-opus-5")
        expect(params[:system_]).to eq("Sos un asistente.")
        expect(params[:messages]).to eq([{ role: "user", content: "Proponé campos." }])
        expect(params.dig(:output_config, :format, :type)).to eq("json_schema")
        response(content: [text_block(valid_payload.to_json)])
      end

      provider.complete(
        messages: [{ role: "system", content: "Sos un asistente." },
                   { role: "user", content: "Proponé campos." }],
        schema: schema, purpose: "suggest_form_fields"
      )
    end

    # La API rechaza con 400 varias palabras de JSON Schema. Se sacan SOLO del
    # pedido: el schema local las conserva y sigue siendo el contrato real.
    it "saca del schema las palabras que la API rechaza, y cierra los objetos" do
      sent = nil
      allow(messages_api).to receive(:create) do |**params|
        sent = params.dig(:output_config, :format, :schema)
        response(content: [text_block(valid_payload.to_json)])
      end

      provider.complete(messages: [{ role: "user", content: "x" }], schema: schema,
                        purpose: "suggest_form_fields")

      fields = sent["properties"]["fields"]
      expect(fields).not_to have_key("minItems")
      expect(fields).not_to have_key("maxItems")
      expect(fields["items"]["properties"]["key"]).not_to have_key("pattern")
      expect(fields["items"]["additionalProperties"]).to be(false)
      expect(sent["additionalProperties"]).to be(false)
      # El original queda intacto: se valida contra él, no contra el podado.
      expect(schema["properties"]["fields"]["minItems"]).to eq(2)
    end
  end

  describe "cómo lee la respuesta" do
    it "devuelve los datos y el consumo cuando valida contra el schema" do
      allow(messages_api).to receive(:create).and_return(response(content: [text_block(valid_payload.to_json)]))

      result = provider.complete(messages: [{ role: "user", content: "x" }], schema: schema,
                                 purpose: "suggest_form_fields")

      expect(result).to be_ok
      expect(result.data).to eq(valid_payload)
      expect(result.tokens_in).to eq(120)
      expect(result.tokens_out).to eq(45)
      expect(result.model).to eq("claude-opus-5")
    end

    # El schema podado que viaja es más laxo que el real. Si la respuesta
    # cumple el laxo pero no el estricto, es un fallo: el contrato es el local.
    it "rechaza lo que no cumple el schema local, aunque la API lo haya aceptado" do
      corto = { "fields" => [{ "key" => "titulo" }] }
      allow(messages_api).to receive(:create).and_return(response(content: [text_block(corto.to_json)]))

      result = provider.complete(messages: [{ role: "user", content: "x" }], schema: schema,
                                 purpose: "suggest_form_fields")

      expect(result).not_to be_ok
      expect(result.error).to include("no valida contra el schema")
      expect(result.raw).to eq(corto)
    end

    it "rechaza una respuesta que no es JSON" do
      allow(messages_api).to receive(:create).and_return(response(content: [text_block("perdón, no puedo")]))

      result = provider.complete(messages: [{ role: "user", content: "x" }], schema: schema,
                                 purpose: "suggest_form_fields")

      expect(result).not_to be_ok
      expect(result.error).to include("no era JSON")
    end
  end

  describe "las formas de fallar que no son excepciones" do
    # Un rechazo por política llega con HTTP 200. Sin mirarlo, el error diría
    # "vino vacía" y mandaría a investigar el lugar equivocado.
    it "un rechazo por política se reporta como tal, no como respuesta vacía" do
      allow(messages_api).to receive(:create).and_return(
        response(content: [], stop_reason: :refusal,
                 stop_details: instance_double(Anthropic::Models::RefusalStopDetails, category: :cyber))
      )

      result = provider.complete(messages: [{ role: "user", content: "x" }], schema: schema,
                                 purpose: "suggest_form_fields")

      expect(result).not_to be_ok
      expect(result.error).to include("declinó responder", "cyber")
    end

    it "una respuesta cortada por max_tokens lo dice: el JSON quedó a medias" do
      allow(messages_api).to receive(:create).and_return(
        response(content: [text_block('{"fields": [{"key": "titu')], stop_reason: :max_tokens)
      )

      result = provider.complete(messages: [{ role: "user", content: "x" }], schema: schema,
                                 purpose: "suggest_form_fields")

      expect(result).not_to be_ok
      expect(result.error).to include("max_tokens")
    end
  end

  describe "los errores de la API se explican distinto según qué hay que hacer" do
    {
      Anthropic::Errors::AuthenticationError => "ANTHROPIC_API_KEY",
      Anthropic::Errors::RateLimitError => "límite de la API"
    }.each do |klass, expected|
      it "#{klass.name.demodulize} dice qué revisar" do
        allow(messages_api).to receive(:create).and_raise(
          klass.new(url: URI("https://api.anthropic.com"), status: 401, headers: {},
                    body: nil, request: nil, response: nil)
        )

        result = provider.complete(messages: [{ role: "user", content: "x" }], schema: schema,
                                   purpose: "suggest_form_fields")

        expect(result).not_to be_ok
        expect(result.error).to include(expected)
      end
    end
  end

  # Anthropic no tiene endpoint de embeddings. Devolver los del fixture sería
  # peor que fallar: la detección de duplicados diría que compara significados
  # cuando estaría comparando hashes.
  describe "#embed" do
    it "falla explicando que hace falta un proveedor de embeddings aparte" do
      expect { provider.embed(texts: ["una idea"]) }
        .to raise_error(Flow::Errors::ProviderUnsupported, /embeddings/)
    end
  end
end
