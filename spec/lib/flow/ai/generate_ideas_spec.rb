# frozen_string_literal: true

require "rails_helper"

# Generar ideas contra el formulario REAL del desafío.
#
# El bug: la tarea le mandaba al modelo las CLAVES del formulario
# (`titulo, problema, solucion`) y un `payload` de tipo objeto libre. El modelo
# no sabía qué preguntaba cada campo, y cualquier objeto validaba. Después un
# `slice` se quedaba con la intersección —que podía ser vacía—, la idea se
# creaba sin una sola respuesta y se auto-postulaba. Nadie se enteraba.
RSpec.describe Flow::AI::Tasks::GenerateIdeas do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:challenge) { create(:challenge, name: "Merma", brief: "Bajar la merma en bodega.") }

  # `apply!` necesita a quién atribuirle la idea generada.
  let!(:autor) do
    without_tenant do
      u = create(:user, email: "autor@test.dev")
      create(:membership, company: company, user: u)
      u
    end
  end

  let!(:step) do
    s = challenge.steps.create!(kind: "ideation", position: 1, name: "Postulación")
    s.form_fields.create!(key: "titulo", label: "Título", field_type: "text", required: true,
                          hint: "Una frase.", position: 0, config: { "is_title" => true })
    s.form_fields.create!(key: "impacto_esperado", label: "¿Qué impacto esperás?",
                          field_type: "textarea", required: true,
                          hint: "En números si se puede.", position: 1)
    s.form_fields.create!(key: "area", label: "Área", field_type: "select", required: false,
                          position: 2, config: { "options" => %w[Bodega Compras] })
    s.form_fields.create!(key: "costeo", label: "Costeo", field_type: "file", position: 3)
    s
  end

  subject(:task) { described_class.new(challenge: challenge, step: step, count: 2) }

  describe "lo que se le manda al modelo" do
    # Las claves son identificadores técnicos. «impacto_esperado» no le dice a
    # nadie que la pregunta es «¿Qué impacto esperás?».
    it "describe cada campo con su pregunta, su tipo y su ayuda" do
      prompt = task.messages.last[:content]

      expect(prompt).to include("«¿Qué impacto esperás?»")
      expect(prompt).to include("En números si se puede.")
      expect(prompt).to include("texto largo")
      expect(prompt).to include("Opciones: Bodega, Compras.")
      expect(prompt).to include("Obligatorio.")
    end

    it "manda el brief para que la idea ataque ESE problema" do
      expect(task.messages.last[:content]).to include("Bajar la merma en bodega.")
      expect(task.messages.first[:content]).to include("no proponés algo que serviría para cualquier empresa")
    end

    # Pedirle un adjunto al modelo es pedirle algo imposible.
    it "deja afuera los campos de archivo" do
      expect(task.messages.last[:content]).not_to include("costeo")
    end
  end

  # `count` es una clave de primer nivel del contexto, no anidada bajo :context.
  # Pasarla mal no rompe nada visible: el prompt pide 5 en silencio.
  it "pide la cantidad que le pidieron" do
    expect(task.messages.last[:content]).to include("Generá 2 ideas")
  end

  # Cada idea son cientos de tokens de salida: pedir veinte de una es una
  # factura sorpresa.
  describe "cuántas se piden" do
    it "respeta lo que pidió quien aprieta el botón" do
      expect(task.messages.last[:content]).to include("Generá 2 ideas")
    end

    it "no pasa del tope, aunque se pida más" do
      muchas = described_class.new(challenge: challenge, step: step, count: 50)
      expect(muchas.messages.last[:content]).to include("Generá 5 ideas")
      expect(muchas.schema.dig("properties", "ideas", "maxItems")).to eq(5)
    end

    it "ni baja de una" do
      ninguna = described_class.new(challenge: challenge, step: step, count: 0)
      expect(ninguna.messages.last[:content]).to include("Generá 1 ideas")
    end
  end

  describe "el schema" do
    subject(:payload_schema) { task.schema.dig("properties", "ideas", "items", "properties", "payload") }

    # Esto es lo que hace que la salida estructurada garantice el llenado.
    it "nombra las claves reales del formulario, no un objeto libre" do
      expect(payload_schema["properties"].keys).to eq(%w[titulo impacto_esperado area])
      # TODOS, no solo los obligatorios del formulario: una persona puede dejar
      # uno en blanco, pero una idea generada que los deja vacíos es media idea.
      expect(payload_schema["required"]).to eq(%w[titulo impacto_esperado area])
    end

    it "traduce el tipo del campo: un select solo acepta sus opciones" do
      expect(payload_schema.dig("properties", "area")).to eq(
        "type" => "string", "enum" => %w[Bodega Compras]
      )
    end

    # La regresión de verdad: el schema sale del formulario, no está escrito a
    # mano para un desafío. Otro formulario, otro schema.
    it "cambia con el formulario" do
      step.form_fields.create!(key: "riesgos", label: "Riesgos", field_type: "textarea",
                               required: true, position: 4)

      otro = described_class.new(challenge: challenge, step: step.reload)
      schema = otro.schema.dig("properties", "ideas", "items", "properties", "payload")

      expect(schema["properties"].keys).to include("riesgos")
      expect(schema["required"]).to include("riesgos")
    end
  end

  describe "al aplicar la sugerencia" do
    let(:suggestion) do
      run = AiRun.create!(challenge: challenge, challenge_step: step, purpose: "generate_ideas",
                          mode: "ai_assisted", status: "succeeded", provider: "fixture",
                          idempotency_key: SecureRandom.uuid)
      AiSuggestion.create!(ai_run: run, payload: {}, status: "pending", challenge_step: step)
    end

    def apply(ideas) = task.apply!({ "ideas" => ideas }, suggestion: suggestion)

    it "crea la idea con las respuestas del formulario" do
      ok, = apply([{ "payload" => { "titulo" => "Sensores", "impacto_esperado" => "Baja 15%",
                                    "area" => "Bodega" } }])

      expect(ok).to be(true)
      idea = challenge.ideas.reload.first
      expect(idea.payload).to eq("titulo" => "Sensores", "impacto_esperado" => "Baja 15%",
                                 "area" => "Bodega")
      # El título sale del campo marcado is_title, no de una clave paralela.
      expect(idea.title).to eq("Sensores")
      expect(idea.submitted_at).to be_present
    end

    # ANTES: se creaba igual, vacía, y se postulaba sola.
    it "NO crea la idea que no respondió los campos obligatorios, y dice cuáles" do
      ok, errores = apply([{ "payload" => { "idea" => "algo", "descripcion" => "otra cosa" } }])

      expect(ok).to be(false)
      expect(errores.join).to include("impacto_esperado")
      expect(challenge.ideas.reload).to be_empty
    end

    # El modelo puede devolver de más: el prompt pide una cantidad, no la impone.
    it "entra solo la cantidad que se pidió, aunque el modelo mande de más" do
      ok, = apply(4.times.map { |n| { "payload" => { "titulo" => "Idea #{n}",
                                                     "impacto_esperado" => "Baja 15%" } } })

      expect(ok).to be(true)
      expect(challenge.ideas.reload.size).to eq(2)
    end

    it "descarta lo que no es un campo del formulario" do
      apply([{ "payload" => { "titulo" => "Sensores", "impacto_esperado" => "Baja 15%",
                              "inventado" => "ruido" } }])

      expect(challenge.ideas.reload.first.payload).not_to have_key("inventado")
    end

    # Que una idea venga incompleta no puede tirar a las que sí vinieron bien.
    it "crea las que están completas y reporta las que no" do
      ok, errores = apply([
        { "payload" => { "titulo" => "Buena", "impacto_esperado" => "Baja 15%" } },
        { "payload" => { "titulo" => "Incompleta" } }
      ])

      expect(ok).to be(true)
      expect(errores.join).to include("la idea 2")
      expect(challenge.ideas.reload.map(&:title)).to eq(["Buena"])
    end
  end
end
