# La grabación de la mesa — plan de implementación

> **Para quien ejecute esto con agentes:** SUB-SKILL REQUERIDA: usá
> `superpowers:subagent-driven-development` (recomendada) o
> `superpowers:executing-plans` para implementar tarea por tarea. Los pasos usan
> casillas (`- [ ]`) para seguimiento.

**Goal:** La mesa de un taller aprieta grabar, **ve la línea de sonido moverse
mientras habla**, y la sala muestra qué se dijo y con cuánta confianza de
hablante.

**Architecture:** Un cuarto eje de proveedor (`FLOW_SPEECH_PROVIDER`) que espeja
`embeddings_provider`, con `Providers::Deepgram` para el camino real y
`Providers::Fixture` para el determinista. El audio lo graba `MediaRecorder` en
el navegador —con un `AnalyserNode` en paralelo que alimenta la onda en vivo—, se
sube en un POST, vive en Active Storage detrás de una fila `workshop_recordings`
con `TenantScoped`, y lo transcribe un job calcado de `EmbedVersionJob`. La
transcripción se guarda normalizada —20 veces más chica que la respuesta cruda,
medido— y el audio se conserva porque re-transcribir es el arreglo de una
diarización colapsada.

**Tech Stack:** Rails 7.1, Postgres con `structure.sql`, Active Storage (servicio
`local`), Sidekiq, Net::HTTP de la stdlib, `MediaRecorder` + `getUserMedia` +
Web Audio (`AnalyserNode`), Playwright para el recorrido.

**Spec:** `docs/superpowers/specs/2026-10-08-grabacion-de-la-mesa-design.md`

## Global Constraints

- **El código va en inglés; los comentarios y los mensajes de commit, en
  español.** Toda tabla y toda columna nueva, en inglés sin excepción.
- **Todo corre en Docker. Nunca `bundle exec` en el host.** Los specs van por
  `make spec*`, que usa `app_test`; `docker compose exec app bundle exec rspec`
  devuelve 403 «Blocked hosts» en todos los request specs.
- **`schema_format = :sql`:** después de `make migrate`, commitear
  `db/structure.sql`.
- **Tocaste `app/javascript/` o agregaste utilidades de Tailwind → `make
  yarn-build` ANTES de `make screens`.** `app/assets/builds/*` está
  gitignoreado: un `.js` nuevo no existe para el navegador hasta compilarlo, y
  el recorrido validaría en verde una app que no es la que escribiste.
- **Zeitwerk: una constante por archivo.**
- **Pundit, no CanCanCan.** Cada policy declara su `Scope` explícitamente.
- **No se introduce webmock ni VCR.** El repo no los tiene y los adapters HTTP
  reales (`Providers::Openai`, `Providers::Voyage`) no tienen specs: lo que se
  prueba es la normalización como función pura. Una gema nueva pediría `make
  rebuild`.
- **Sin `bundle add` ni `yarn add`:** todo lo que hace falta ya está. La onda va
  con Web Audio de la plataforma; **ninguna librería de visualización**.
- **La onda va en barras del DOM, NUNCA en un `<canvas>`.** No hay un solo canvas
  en el repo, y un canvas es una caja negra para todas las guardas: `[CLASES]`,
  `[CONTRASTE]` y `[SOMBRA]` no ven adentro, y una guarda que no puede ver da
  permiso.
- **El color de la onda es `--dato` / `--dato-fuerte`**, por la regla «el acento
  es de las ACCIONES; los gráficos van con la tinta de datos». **No** el morado
  `#8520BD` del Figma: no pinta un pixel en la app, adoptarlo es una decisión
  abierta que nadie tomó, y además es uno de los dos colores del Figma que no
  pasan el piso de 4,5:1 de `[CONTRASTE]`.
- **Clases literales, nunca interpoladas.** `spec/lint/clases_interpoladas_spec.rb`
  mira HAML, `.vue` **y `.js`**: una clase armada con un template literal no
  llega a la hoja de Tailwind y el elemento queda sin ninguna regla detrás.
- **`FLOW_SPEECH_PROVIDER` NO se declara en `.env`.** La cascada cae al fixture
  sola, así que `make spec` y `make screens` no facturan. `DEEPGRAM_API_KEY` ya
  está en `.env`.
- **Los commits van con `ribarahonaa@gmail.com`** (ya está en el `git config`
  local) y **sin línea `Co-Authored-By`**.
- Rama: `grabacion-de-la-mesa`, ya creada, con la spec commiteada en `6af497d`.

## Review Focus

Cinco clases de entrada que la spec implica y que ninguna tarea exercitaría si
no se dijera acá. Cada línea tiene su test asignado a la tarea dueña del código:

1. **Un POST sin archivo**, o con un archivo que no es audio. La mesa esperaría
   un código y un motivo, no un 500 al adjuntar. → Tarea 4.
2. **Un audio de duración cero** (alguien aprieta grabar y parar en el mismo
   segundo). Deepgram contesta 200 con texto vacío —medido—, así que el camino
   no falla: tiene que quedar `ready` sin utterances y decirlo. → Tarea 5.
3. **Dos personas de la mesa grabando a la vez.** No hay índice único, así que
   son dos filas y las dos se transcriben; lo que no puede pasar es que una pise
   la transcripción de la otra. → Tarea 5.
4. **Una grabación de otra empresa pedida por id.** Tiene que dar 404 y no 403:
   un 403 es un oráculo de existencia. → Tarea 4.
5. **La respuesta de Deepgram sin `utterances`** (si alguien saca
   `utterances=true` de la query, o la API cambia). Normalizar tiene que caer a
   las palabras del canal o dejar la lista vacía, nunca reventar con
   `NoMethodError` sobre `nil`. → Tarea 2.
6. **Un micrófono que entrega silencio** (tapado, en mute por hardware, o el
   equipo equivocado elegido en el sistema). La onda queda plana y es la única
   señal que lo dice: el cronómetro corre igual. Es la razón de existir de la
   onda y lo que `[GRABAR]` mide por la corrida de silencio. → Tarea 7.

---

## Estructura de archivos

| Archivo | Responsabilidad | Tarea |
|---|---|---|
| `app/lib/flow/errors.rb` | suma `TranscriptionFailed` | 1 |
| `app/lib/flow/ai/provider.rb` | suma `transcription?` y `transcribe` a la interfaz | 1 |
| `app/lib/flow/ai.rb` | suma `speech_provider` y su cascada | 1 |
| `app/lib/flow/ai/providers/fixture.rb` | suma `transcribe` determinista | 1 |
| `app/lib/flow/ai/providers/deepgram.rb` | **nuevo** · HTTP + normalización | 2 |
| `spec/fixtures/ai/deepgram_response.json` | **nuevo** · respuesta REAL medida | 2 |
| `db/migrate/20261008120000_create_workshop_recordings.rb` | **nuevo** | 3 |
| `app/models/workshop_recording.rb` | **nuevo** · validaciones y predicados | 3 |
| `app/controllers/workshop_recordings_controller.rb` | **nuevo** · `create` y `show` | 4 |
| `config/routes.rb` | suma `resources :recordings` en la sala | 4 |
| `app/jobs/flow/workshops/transcribe_recording_job.rb` | **nuevo** | 5 |
| `app/lib/flow/workshops/transcribe_recording.rb` | **nuevo** · el servicio | 5 |
| `app/views/workshop_rooms/_recording.html.haml` | **nuevo** · control + onda + transcripción | 6 |
| `app/javascript/workshop_recording.js` | **nuevo** · estado en el módulo + el `AnalyserNode` | 6 |
| `app/assets/stylesheets/application.css` | suma `.waveform` y `.waveform__bar` | 6 |
| `app/javascript/application.js` | importa el nuevo | 6 |
| `config/locales/es.yml` | textos de estado y de fallo | 6 |
| `script/capture_screens.js` | la guarda `[GRABAR]` y las flags | 7 |
| `script/fake_audio.wav` | **nuevo** · el audio del micrófono falso | 7 |
| `CLAUDE.md` | el octavo `arrival?`, el onceavo número, el eje nuevo | 8 |

---

## Tarea 1: El eje de proveedor y el fixture

**Files:**
- Modify: `app/lib/flow/errors.rb`
- Modify: `app/lib/flow/ai/provider.rb`
- Modify: `app/lib/flow/ai.rb`
- Modify: `app/lib/flow/ai/providers/fixture.rb`
- Test: `spec/lib/flow/ai/speech_provider_spec.rb` (nuevo)

**Interfaces:**
- Consumes: nada.
- Produces: `Flow::AI.speech_provider` → un `Provider`.
  `Provider#transcription?` → `Boolean`.
  `Provider#transcribe(audio:, content_type:, language:)` → `Array<Hash>` con
  claves string `"speaker"` (Integer), `"start"` / `"end"` (Float),
  `"transcript"` (String), `"confidence"` / `"speaker_confidence"` (Float).
  `Flow::Errors::TranscriptionFailed < Flow::Errors::Error`.

- [ ] **Paso 1: Escribir el spec que falla**

Crear `spec/lib/flow/ai/speech_provider_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# El cuarto eje. Son TRES variables y no una porque son tres capacidades
# distintas y ningún proveedor tiene las tres: Anthropic no expone embeddings ni
# transcripción, Voyage sólo vectores, Deepgram sólo voz.
RSpec.describe "Flow::AI.speech_provider" do
  after { Flow::AI.reset_provider! }

  it "usa el declarado en FLOW_SPEECH_PROVIDER" do
    Flow::AI.reset_provider!
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("FLOW_SPEECH_PROVIDER").and_return("fixture")

    expect(Flow::AI.speech_provider).to be_a(Flow::AI::Providers::Fixture)
  end

  it "cae al fixture cuando el de chat no sabe transcribir" do
    Flow::AI.reset_provider!
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
    expect(Flow::AI.instance_variable_get(:@speech_provider)).to be_nil
  end

  describe "el fixture" do
    let(:utterances) do
      Flow::AI::Providers::Fixture.new.transcribe(
        audio: "bytes", content_type: "audio/webm", language: "es"
      )
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
      )

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

  it "un proveedor que no sabe levanta NotImplementedError" do
    expect { Flow::AI::Providers::Null.new.transcribe(audio: "x", content_type: "y", language: "es") }
      .to raise_error(NotImplementedError)
  end
end
```

- [ ] **Paso 2: Correr el spec y verificar que falla**

```bash
make spec-file FILE=spec/lib/flow/ai/speech_provider_spec.rb
```

Esperado: FAIL con `NoMethodError: undefined method 'speech_provider'`.

- [ ] **Paso 3: Sumar el error**

En `app/lib/flow/errors.rb`, después de `EmbeddingFailed`:

```ruby
    # El proveedor de voz no pudo responder: falta credencial, la API rechazó
    # el pedido, o contestó algo que no se puede normalizar. Hermana de
    # `EmbeddingFailed` y por el mismo motivo: el job la reintenta.
    class TranscriptionFailed < Error; end
```

- [ ] **Paso 4: Sumar la interfaz**

En `app/lib/flow/ai/provider.rb`, después de `embed`:

```ruby
      # ¿Este proveedor sabe transcribir audio?
      #
      # Tercera capacidad y tercer predicado, por el mismo motivo que
      # `embeddings?`: ninguno de los proveedores tiene las tres. Anthropic no
      # expone ni embeddings ni transcripción; Deepgram sólo transcribe.
      def transcription? = false

      # Audio → utterances con hablante, MÁS la metadata de la llamada.
      #
      # Las dos cosas en un valor inmutable y no en dos llamadas, porque el
      # proveedor se MEMOIZA —una instancia por proceso— y Sidekiq corre con
      # cinco hilos: un accesor que se pregunta después de `transcribe` es
      # estado compartido, y dos grabaciones en vuelo se pisarían la metadata.
      # Mismo idioma que el `Result` de arriba.
      #
      # `utterances` es un arreglo de hashes con claves string: "speaker",
      # "start", "end", "transcript", "confidence", "speaker_confidence". NO es
      # la respuesta cruda del proveedor: normalizar es parte del adapter.
      # Medido, la respuesta completa de Deepgram son 0,80 MB por 20 minutos de
      # reunión y esta forma 0,040 MB, veinte veces menos, sin perder nada que
      # el dominio use.
      Transcription = Data.define(:utterances, :duration, :request_id, :model)

      def transcribe(audio:, content_type:, language:)
        raise NotImplementedError
      end
```

- [ ] **Paso 5: Sumar la resolución**

En `app/lib/flow/ai.rb`, dentro de `class << self`, junto a los otros dos:

```ruby
      # El tercer eje. Mismo motivo que `embeddings_provider`: una capacidad que
      # el proveedor de chat no tiene. Anthropic no transcribe, así que sin
      # declarar nada esto cae al fixture y el camino entero corre sin
      # credenciales ni gasto —que es lo que deja a `make screens` no facturar—.
      def speech_provider
        @speech_provider ||= build_speech_provider
      end

      def speech_provider=(value)
        @speech_provider = value
      end
```

Cambiar `reset_provider!` para que limpie los tres:

```ruby
      def reset_provider!
        @provider = nil
        @embeddings_provider = nil
        @speech_provider = nil
      end
```

Y en `private`:

```ruby
      def build_speech_provider
        declarado = ENV["FLOW_SPEECH_PROVIDER"].presence
        return resolve(declarado) if declarado
        return provider if provider.transcription?

        Flow::AI::Providers::Fixture.new
      end
```

- [ ] **Paso 6: Sumar el fixture**

En `app/lib/flow/ai/providers/fixture.rb`, después de `embedding_model`:

```ruby
        def transcription? = true

        # Transcripción determinista, sin red y sin credenciales.
        #
        # DOS hablantes a propósito: con uno solo el aviso de diarización
        # colapsada —«todas las utterances son del mismo hablante y hay dos o
        # más sentados»— dispararía en toda corrida del recorrido, y la guarda
        # que lo mide no podría distinguir «colapsó de verdad» de «así es el
        # fixture».
        #
        # No depende del audio: los bytes del micrófono falso cambian con la
        # duración de la grabación, y un fixture que variara con ellos dejaría
        # de ser reproducible.
        def transcribe(audio:, content_type:, language:)
          # Sin `duration` ni `request_id`: no hubo llamada que medir. El modelo
          # sí, porque identifica de dónde salió el texto, y es lo que deja a la
          # pantalla decir que una transcripción es canneada.
          Provider::Transcription.new(
            duration: nil, request_id: nil, model: model_name,
            utterances: [
            { "speaker" => 0, "start" => 0.0, "end" => 4.2,
              "transcript" => "Tenemos que bajar la merma de la bodega reusando las barricas.",
              "confidence" => 0.99, "speaker_confidence" => 0.91 },
            { "speaker" => 1, "start" => 5.1, "end" => 9.4,
              "transcript" => "No estoy de acuerdo: el problema real es la inducción de los operarios nuevos.",
              "confidence" => 0.97, "speaker_confidence" => 0.88 }
            ]
          )
        end
```

- [ ] **Paso 7: Correr el spec y verificar que pasa**

```bash
make spec-file FILE=spec/lib/flow/ai/speech_provider_spec.rb
```

Esperado: PASS, 8 ejemplos.

- [ ] **Paso 8: Correr la suite entera**

```bash
make spec
```

Esperado: 1694 + 8 = **1702 ejemplos, 0 fallas**. Si algo más se rompió, es
`reset_provider!`: revisá que ningún spec dependa de que `@speech_provider`
sobreviva.

- [ ] **Paso 9: Commit**

```bash
git add app/lib/flow/errors.rb app/lib/flow/ai/provider.rb app/lib/flow/ai.rb \
        app/lib/flow/ai/providers/fixture.rb spec/lib/flow/ai/speech_provider_spec.rb
git commit -m "El cuarto eje de proveedor: transcribir es una capacidad más, y el fixture la tiene"
```

---

## Tarea 2: El adapter de Deepgram

**Files:**
- Create: `app/lib/flow/ai/providers/deepgram.rb`
- Create: `spec/fixtures/ai/deepgram_response.json`
- Test: `spec/lib/flow/ai/providers/deepgram_spec.rb` (nuevo)

**Interfaces:**
- Consumes: `Flow::AI::Provider`, `Flow::Errors::TranscriptionFailed`,
  `Flow::Errors::ProviderUnsupported` (Tarea 1 y lo que ya existía).
- Produces: `Flow::AI::Providers::Deepgram#transcribe(audio:, content_type:,
  language:)` → `Array<Hash>` con la forma de la Tarea 1, y dos métodos públicos
  más, públicos para poder probarlos sin red:
  `#normalize(body)` → el mismo `Array<Hash>` a partir de un cuerpo ya parseado,
  y `#metadata_from(body)` → `Hash` con las claves string `"duration"`,
  `"request_id"` y `"model"`.
  **NO hay `last_metadata`.** `transcribe` devuelve un
  `Flow::AI::Provider::Transcription` —`Data.define(:utterances, :duration,
  :request_id, :model)`— con las dos cosas en un valor inmutable. Un accesor
  que se pregunta DESPUÉS de la llamada es estado compartido en un proveedor
  memoizado, y con los cinco hilos de Sidekiq dos grabaciones en vuelo se
  pisarían la metadata.

**Por qué la normalización es pública y la llamada HTTP no tiene spec:** el repo
no tiene webmock ni VCR, y ni `Providers::Openai` ni `Providers::Voyage` tienen
spec. Lo que se puede probar sin red es convertir una respuesta en utterances, y
eso es justo donde están los errores. El fixture de esta tarea es la respuesta
**real** de una llamada medida, no una inventada.

- [ ] **Paso 1: Guardar la respuesta real como fixture**

Crear `spec/fixtures/ai/deepgram_response.json` con esto, que es una respuesta
real de `nova-3` recortada a dos utterances y tres palabras cada una,
conservando todas las claves:

```json
{
  "metadata": {
    "duration": 16.906187,
    "request_id": "01a11c7e-3b94-7b50-b9d0-d064768a409e",
    "model_info": {
      "2187e11a-3532-4498-b076-81fa530bdd49": {
        "name": "general-nova-3",
        "version": "2025-07-31.0",
        "arch": "nova-3"
      }
    }
  },
  "results": {
    "channels": [
      {
        "alternatives": [
          {
            "transcript": "We should reduce the waste in the winery by reusing the barrels. I disagree.",
            "confidence": 0.99902344,
            "words": [
              { "word": "we", "start": 0.08, "end": 0.56, "confidence": 0.9819336, "speaker": 0, "speaker_confidence": 0.6869923, "punctuated_word": "We" },
              { "word": "should", "start": 0.56, "end": 0.88, "confidence": 1.0, "speaker": 0, "speaker_confidence": 0.6869923, "punctuated_word": "should" },
              { "word": "reduce", "start": 0.88, "end": 1.52, "confidence": 0.9980469, "speaker": 0, "speaker_confidence": 0.4120001, "punctuated_word": "reduce" }
            ]
          }
        ]
      }
    ],
    "utterances": [
      {
        "start": 0.08,
        "end": 5.12,
        "confidence": 0.99538165,
        "channel": 0,
        "transcript": "We should reduce the waste in the winery by reusing the barrels.",
        "words": [
          { "word": "we", "start": 0.08, "end": 0.56, "confidence": 0.9819336, "speaker": 0, "speaker_confidence": 0.6869923, "punctuated_word": "We" },
          { "word": "should", "start": 0.56, "end": 0.88, "confidence": 1.0, "speaker": 0, "speaker_confidence": 0.6869923, "punctuated_word": "should" },
          { "word": "reduce", "start": 0.88, "end": 1.52, "confidence": 0.9980469, "speaker": 0, "speaker_confidence": 0.4120001, "punctuated_word": "reduce" }
        ],
        "speaker": 0
      },
      {
        "start": 6.55,
        "end": 10.55,
        "confidence": 0.9912,
        "channel": 0,
        "transcript": "I disagree. The real problem is the onboarding of the new operators.",
        "words": [
          { "word": "i", "start": 6.55, "end": 6.79, "confidence": 0.9941, "speaker": 1, "speaker_confidence": 0.7312, "punctuated_word": "I" },
          { "word": "disagree", "start": 6.79, "end": 7.43, "confidence": 0.9988, "speaker": 1, "speaker_confidence": 0.7312, "punctuated_word": "disagree." },
          { "word": "the", "start": 7.6, "end": 7.84, "confidence": 0.9995, "speaker": 1, "speaker_confidence": 0.5501, "punctuated_word": "The" }
        ],
        "speaker": 1
      }
    ]
  }
}
```

- [ ] **Paso 2: Escribir el spec que falla**

Crear `spec/lib/flow/ai/providers/deepgram_spec.rb`:

```ruby
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
```

- [ ] **Paso 3: Correr el spec y verificar que falla**

```bash
make spec-file FILE=spec/lib/flow/ai/providers/deepgram_spec.rb
```

Esperado: FAIL con `uninitialized constant Flow::AI::Providers::Deepgram`.

- [ ] **Paso 4: Escribir el adapter**

Crear `app/lib/flow/ai/providers/deepgram.rb`:

```ruby
# frozen_string_literal: true

module Flow
  module AI
    module Providers
      # Transcripción con hablantes. SÓLO transcribe: no hace chat ni
      # embeddings, igual que los adapters de embeddings sólo hacen `embed`.
      #
      # No hereda de `HttpEmbeddings` —esa clase base existe porque hay DOS
      # proveedores de vectores que comparten lo difícil (respetar el índice de
      # cada fila, partir en lotes, validar la dimensión)—. Acá hay uno solo; la
      # base se escribe cuando aparezca el segundo.
      #
      # El resumen NO lo hace este proveedor, aunque la competencia lo ofrezca:
      # sería una segunda llamada de IA sin rastro en `ai_runs`, sin schema
      # validado y sin modos. El resumen es un propósito de chat.
      class Deepgram < Provider
        ENDPOINT = "https://api.deepgram.com/v1/listen"
        DEFAULT_MODEL = "nova-3"
        TIMEOUT = 120

        def transcription? = true

        def complete(messages:, schema:, purpose:, temperature: 0.2)
          raise Flow::Errors::ProviderUnsupported,
                "deepgram transcribe audio; no hace chat. Usá FLOW_AI_PROVIDER para el chat."
        end

        def transcribe(audio:, content_type:, language:)
          body = post(audio, content_type, language)
          metadata = metadata_from(body)
          # Las dos cosas en UN valor inmutable, y no un arreglo más un accesor
          # que se pregunta después. Un accesor sería estado compartido: el
          # proveedor se memoiza, o sea UNA instancia para el proceso, y Sidekiq
          # corre con cinco hilos — dos grabaciones en vuelo se pisarían la
          # metadata y la fila de auditoría de una llevaría el `request_id` de
          # la otra.
          Provider::Transcription.new(
            utterances: normalize(body),
            duration: metadata["duration"],
            request_id: metadata["request_id"],
            model: metadata["model"]
          )
        end

        # Pública para poder probarla sin red. Es donde están los errores.
        def normalize(body)
          utterances = body.dig("results", "utterances")
          return [] unless utterances.is_a?(Array)

          utterances.map do |u|
            {
              "speaker" => u["speaker"],
              "start" => u["start"],
              "end" => u["end"],
              "transcript" => u["transcript"],
              "confidence" => u["confidence"],
              # El MÍNIMO y no el de la primera palabra: es la señal de que el
              # diarizador dudó, y el mínimo es el lado conservador.
              "speaker_confidence" => min_speaker_confidence(u["words"])
            }
          end
        end

        def metadata_from(body)
          metadata = body["metadata"] || {}
          {
            "duration" => metadata["duration"],
            "request_id" => metadata["request_id"],
            # `model_info` viene con el UUID del modelo como clave, así que el
            # nombre está un nivel más abajo y no se puede pedir por clave fija.
            "model" => metadata.dig("model_info")&.values&.first&.dig("name")
          }
        end

        private

        def min_speaker_confidence(words)
          valores = Array(words).filter_map { |w| w["speaker_confidence"] }
          valores.min
        end

        def api_key
          ENV["DEEPGRAM_API_KEY"].presence ||
            raise(Flow::Errors::TranscriptionFailed, "falta DEEPGRAM_API_KEY")
        end

        def model_name = ENV["FLOW_SPEECH_MODEL"].presence || DEFAULT_MODEL

        def post(audio, content_type, language)
          uri = URI("#{ENDPOINT}?#{query(language)}")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = TIMEOUT
          http.read_timeout = TIMEOUT

          pedido = Net::HTTP::Post.new(uri)
          pedido["Authorization"] = "Token #{api_key}"
          pedido["Content-Type"] = content_type
          pedido.body = audio

          respuesta = http.request(pedido)
          parsed = parse(respuesta)
          return parsed if respuesta.is_a?(Net::HTTPSuccess)

          raise Flow::Errors::TranscriptionFailed,
                "deepgram respondió #{respuesta.code}: #{detail(parsed)}#{hint(respuesta.code)}"
        rescue Net::OpenTimeout, Net::ReadTimeout => e
          raise Flow::Errors::TranscriptionFailed, "deepgram no respondió en #{TIMEOUT}s (#{e.class})"
        end

        def query(language)
          URI.encode_www_form(
            model: model_name,
            # Sin esto no hay hablantes, y la diarización es el motivo por el
            # que se eligió este proveedor.
            diarize: true,
            # Sin esto no hay `results.utterances` y `normalize` devuelve vacío.
            utterances: true,
            punctuate: true,
            language: language
          )
        end

        def parse(respuesta)
          JSON.parse(respuesta.body.to_s)
        rescue JSON::ParserError
          {}
        end

        def detail(parsed) = parsed["err_msg"] || parsed["message"] || "sin detalle"

        # La pista de Voyage, por si pasa lo mismo: una cuenta que autentica
        # pero no tiene inferencia habilitada contesta 500 en TODO pedido.
        def hint(codigo)
          return "" unless codigo.to_s == "500"

          ". Un 500 en todo pedido suele ser una cuenta sin inferencia " \
            "habilitada, no un problema del audio: probá un clip de un segundo."
        end
      end
    end
  end
end
```

- [ ] **Paso 5: Correr el spec y verificar que pasa**

```bash
make spec-file FILE=spec/lib/flow/ai/providers/deepgram_spec.rb
```

Esperado: PASS, 8 ejemplos.

- [ ] **Paso 6: Verificar contra la API real, una sola vez**

Esto cuesta ~0,0006 USD y confirma que el adapter que acabás de escribir habla
con la API de verdad y no sólo con su fixture:

```bash
docker compose exec app ./bin/rails runner '
  audio = File.binread("script/fake_audio.wav") rescue nil
  if audio.nil?
    puts "sin script/fake_audio.wav todavía (lo crea la Tarea 7): salteá este paso"
  else
    p Flow::AI::Providers::Deepgram.new.transcribe(
      audio: audio, content_type: "audio/wav", language: "en"
    )
  end
'
```

Esperado: un arreglo de hashes con texto real. Si da
`TranscriptionFailed ... 500`, leé la pista: es la cuenta, no el audio. Si
`script/fake_audio.wav` todavía no existe, salteá y volvé después de la Tarea 7.

- [ ] **Paso 7: Commit**

```bash
git add app/lib/flow/ai/providers/deepgram.rb \
        spec/fixtures/ai/deepgram_response.json \
        spec/lib/flow/ai/providers/deepgram_spec.rb
git commit -m "El adapter de Deepgram normaliza la respuesta, y su fixture es una medición y no un invento"
```

---

## Tarea 3: La tabla y el modelo

**Files:**
- Create: `db/migrate/20261008120000_create_workshop_recordings.rb`
- Create: `app/models/workshop_recording.rb`
- Modify: `app/models/workshop_group.rb` (suma `has_many :workshop_recordings`)
- Modify: `db/structure.sql` (lo regenera `make migrate`)
- Test: `spec/models/workshop_recording_spec.rb` (nuevo)
- Test: `spec/factories/workshop_recordings.rb` (nuevo)

**Interfaces:**
- Consumes: nada de las tareas anteriores.
- Produces: `WorkshopRecording` con `status` en
  `%w[pending transcribing ready failed]`, `utterances` (jsonb, array de hashes
  con la forma de la Tarea 1), `has_one_attached :file`, y tres predicados:
  `#collapsed_diarization?` → `Boolean`, `#transcript_text` → `String`,
  `#speakers` → `Array<Integer>`.
  `WorkshopGroup#workshop_recordings`.

- [ ] **Paso 1: Escribir la factory**

Crear `spec/factories/workshop_recordings.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :workshop_recording do
    workshop_group
    workshop_challenge
    recorded_by factory: :user
    status { "pending" }
    utterances { [] }

    trait :ready do
      status { "ready" }
      duration_seconds { 16.9 }
      provider { "fixture" }
      model { "fixture-v1" }
      utterances do
        [
          { "speaker" => 0, "start" => 0.0, "end" => 4.2, "transcript" => "Primera.",
            "confidence" => 0.99, "speaker_confidence" => 0.91 },
          { "speaker" => 1, "start" => 5.1, "end" => 9.4, "transcript" => "Segunda.",
            "confidence" => 0.97, "speaker_confidence" => 0.88 }
        ]
      end
    end

    trait :colapsada do
      status { "ready" }
      utterances do
        [
          { "speaker" => 0, "start" => 0.0, "end" => 4.2, "transcript" => "Primera.",
            "confidence" => 0.99, "speaker_confidence" => 0.32 },
          { "speaker" => 0, "start" => 5.1, "end" => 9.4, "transcript" => "Segunda.",
            "confidence" => 0.97, "speaker_confidence" => 0.19 }
        ]
      end
    end
  end
end
```

- [ ] **Paso 2: Escribir el spec que falla**

Crear `spec/models/workshop_recording_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# La grabación de una mesa. Clavijada como `WorkshopDraft` pero SIN índice
# único: una mesa graba varias veces en una sesión.
RSpec.describe WorkshopRecording do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  # Toda lectura del dominio va dentro de `as_company`, incluido un `.new`: toca
  # el `default_scope` de `TenantScoped`.
  def armar
    as_company(company) do
      challenge = create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: "ideation", status: "active")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge,
                                         challenge_step: step)
      group = create(:workshop_group, workshop: workshop)
      { workshop: workshop, link: link, group: group, challenge: challenge }
    end
  end

  it "una mesa puede tener VARIAS grabaciones de la misma sala" do
    s = armar
    as_company(company) do
      create(:workshop_recording, workshop_group: s[:group], workshop_challenge: s[:link])

      expect {
        create(:workshop_recording, workshop_group: s[:group], workshop_challenge: s[:link])
      }.to change { s[:group].workshop_recordings.count }.by(1)
    end
  end

  it "rechaza una mesa y una sala de talleres distintos" do
    s = armar
    as_company(company) do
      otra_mesa = create(:workshop_group, workshop: create(:workshop, status: "open"))
      grabacion = WorkshopRecording.new(workshop_group: otra_mesa,
                                        workshop_challenge: s[:link],
                                        recorded_by: create(:user), status: "pending")

      expect(grabacion).not_to be_valid
      expect(grabacion.errors[:workshop_group]).to be_present
    end
  end

  it "rechaza un status que no está en la lista" do
    s = armar
    as_company(company) do
      grabacion = build(:workshop_recording, workshop_group: s[:group],
                                             workshop_challenge: s[:link], status: "wat")

      expect(grabacion).not_to be_valid
    end
  end

  describe "#transcript_text" do
    it "concatena las utterances con su hablante" do
      s = armar
      as_company(company) do
        grabacion = build(:workshop_recording, :ready, workshop_group: s[:group],
                                                       workshop_challenge: s[:link])

        expect(grabacion.transcript_text).to eq(
          "Hablante 1: Primera.\nHablante 2: Segunda."
        )
      end
    end

    it "sin utterances devuelve cadena vacía y no revienta" do
      s = armar
      as_company(company) do
        grabacion = build(:workshop_recording, workshop_group: s[:group],
                                               workshop_challenge: s[:link])

        expect(grabacion.transcript_text).to eq("")
      end
    end
  end

  describe "#collapsed_diarization?" do
    it "es true con un solo hablante y dos sentados en la mesa" do
      s = armar
      as_company(company) do
        2.times { create(:workshop_group_member, workshop_group: s[:group], user: create(:user)) }
        grabacion = create(:workshop_recording, :colapsada, workshop_group: s[:group],
                                                            workshop_challenge: s[:link])

        expect(grabacion.collapsed_diarization?).to be(true)
      end
    end

    it "es false con dos hablantes, aunque la confianza sea baja" do
      # A propósito: NO hay umbral sobre `speaker_confidence`. Se midió
      # 0,196–0,687 sobre entrada degenerada y no hay línea base de voces
      # reales, así que cualquier corte sería un número inventado — y un umbral
      # inventado es la guarda que da permiso. La condición es estructural.
      s = armar
      as_company(company) do
        2.times { create(:workshop_group_member, workshop_group: s[:group], user: create(:user)) }
        grabacion = create(:workshop_recording, :ready, workshop_group: s[:group],
                                                        workshop_challenge: s[:link])

        expect(grabacion.collapsed_diarization?).to be(false)
      end
    end

    it "es false con una sola persona sentada: ahí un hablante es correcto" do
      s = armar
      as_company(company) do
        create(:workshop_group_member, workshop_group: s[:group], user: create(:user))
        grabacion = create(:workshop_recording, :colapsada, workshop_group: s[:group],
                                                            workshop_challenge: s[:link])

        expect(grabacion.collapsed_diarization?).to be(false)
      end
    end

    it "es false sin utterances: no se avisa de una transcripción que no existe" do
      s = armar
      as_company(company) do
        2.times { create(:workshop_group_member, workshop_group: s[:group], user: create(:user)) }
        grabacion = create(:workshop_recording, workshop_group: s[:group],
                                                workshop_challenge: s[:link], status: "ready")

        expect(grabacion.collapsed_diarization?).to be(false)
      end
    end
  end
end
```

- [ ] **Paso 3: Correr el spec y verificar que falla**

```bash
make spec-file FILE=spec/models/workshop_recording_spec.rb
```

Esperado: FAIL con `uninitialized constant WorkshopRecording`.

- [ ] **Paso 4: Escribir la migración**

Crear `db/migrate/20261008120000_create_workshop_recordings.rb`:

```ruby
# frozen_string_literal: true

# La grabación de la conversación de una mesa.
#
# El audio vive en Active Storage, que NO tiene `company_id`: la tenencia la
# lleva esta fila, igual que `IdeaAttachment` y `Report`. Y como
# `config.active_storage.draw_routes = false`, no hay rutas públicas de blob que
# esquiven la policy.
#
# SIN índice único, a diferencia de `workshop_drafts`: una mesa graba varias
# veces en una sesión, y cada grabación es una conversación distinta.
class CreateWorkshopRecordings < ActiveRecord::Migration[7.1]
  include Flow::MigrationHelpers

  def change
    tenant_table :workshop_recordings do |t|
      t.uuid :workshop_group_id,     null: false
      t.uuid :workshop_challenge_id, null: false
      # Qué idea tenía la sala elegida al apretar grabar. Es CONTEXTO y no
      # pertenencia: sirve para que el resumen de C2 no le dé la conversación
      # sobre la idea X al borrador de la idea Y. NULL en idear, donde la idea
      # todavía no existe.
      t.uuid :idea_id
      t.references :recorded_by, type: :uuid, null: false,
                   foreign_key: { to_table: :users }
      t.string :status, null: false, default: "pending"
      # Las utterances NORMALIZADAS y no la respuesta cruda: medido, 0,040 MB
      # por 20 minutos contra 0,80 MB. Lo que se tira es reconstruible porque el
      # audio se conserva, y re-transcribir es justamente cómo se arregla una
      # diarización colapsada.
      t.jsonb :utterances, null: false, default: []
      t.float :duration_seconds
      # Auditoría. A diferencia de los embeddings, transcribir se COBRA por
      # minuto, y alguien va a preguntar cuánto salió y con qué modelo. Mismo
      # precedente que `idea_versions.embedding_model`: el dato va al lado del
      # artefacto y no en una tabla aparte. De paso es lo que deja a la pantalla
      # decir que una transcripción salió del fixture.
      t.string :provider
      t.string :model
      t.string :request_id
      t.text :error
      t.timestamps
    end

    execute <<~SQL.squish
      ALTER TABLE workshop_recordings
        ADD CONSTRAINT workshop_recordings_status_check
        CHECK (status IN ('pending', 'transcribing', 'ready', 'failed'))
    SQL

    # El par por el que se lista en la sala. Plano y no único.
    add_index :workshop_recordings, %i[workshop_group_id workshop_challenge_id],
              name: "index_workshop_recordings_on_group_and_room"
    # Por la FK con cascade, igual que en `workshop_drafts`.
    add_index :workshop_recordings, :idea_id
    # Lo que el job busca para no re-transcribir: las que están esperando.
    add_index :workshop_recordings, :status

    add_tenant_fk :workshop_recordings, :workshop_groups,     column: :workshop_group_id
    add_tenant_fk :workshop_recordings, :workshop_challenges, column: :workshop_challenge_id
    # `nullify` y no `cascade`: borrar una idea no puede llevarse la grabación
    # de una conversación que habló de varias. El helper acota el SET NULL a la
    # columna para no nulear `company_id`, que es NOT NULL.
    add_tenant_fk :workshop_recordings, :ideas, column: :idea_id, on_delete: :nullify
  end
end
```

- [ ] **Paso 5: Correr la migración**

```bash
make migrate
```

Esperado: `CreateWorkshopRecordings: migrated`. Verificá que
`db/structure.sql` cambió:

```bash
git diff --stat db/structure.sql
```

- [ ] **Paso 6: Escribir el modelo**

Crear `app/models/workshop_recording.rb`:

```ruby
# frozen_string_literal: true

# La conversación de una mesa, grabada y transcrita.
#
# El audio se CONSERVA, y no por prolijidad: re-transcribir con otros parámetros
# es exactamente cómo se arregla una diarización colapsada, y sin el audio una
# transcripción mala es definitiva. El precio está declarado en la spec: queda
# una grabación de voces guardada y nadie escribió una política de retención.
#
# Sin `WorkshopRecordingPolicy`, por el mismo motivo que `WorkshopDraft` no tiene
# una: lo que autoriza es la SALA, y una policy vacía heredaría
# `show? = membership.present?`, o sea «cualquiera de la empresa».
class WorkshopRecording < ApplicationRecord
  include TenantScoped

  STATUSES = %w[pending transcribing ready failed].freeze

  belongs_to :workshop_group
  belongs_to :workshop_challenge
  belongs_to :idea, optional: true
  belongs_to :recorded_by, class_name: "User"

  has_one_attached :file

  validates :status, inclusion: { in: STATUSES }
  validate :group_and_room_share_workshop
  validate :idea_matches_room

  scope :recent_first, -> { order(created_at: :desc) }

  # El texto para EL MODELO: es lo que C2 le va a pasar en el prompt. Se DERIVA
  # y no se guarda: una columna con el texto plano sería la segunda fuente que
  # el día que difiera miente.
  #
  # Los hablantes se numeran desde 1 porque Deepgram los numera desde 0, y
  # «Hablante 0» no se lee como una persona.
  #
  # **Y no pasa por I18n a propósito, aunque la pantalla diga lo mismo.** El
  # partial rotula cada utterance con `t("flow.recordings.speaker")` para una
  # PERSONA; esto arma la entrada de un modelo. Que hoy las dos digan «Hablante
  # N» es una coincidencia, no una duplicación: unificarlas ataría el prompt al
  # idioma de la interfaz, y el día que la app se traduzca el prompt cambiaría
  # de idioma sin que nadie lo decida. Si alguien viene a «DRYear» esto, es
  # esto.
  #
  # En C1 no lo consume ninguna pantalla —existe para C2— y por eso lo cubre su
  # propio ejemplo: sin él sería código que nadie ejercita.
  def transcript_text
    utterances.map { |u| "Hablante #{u['speaker'].to_i + 1}: #{u['transcript']}" }.join("\n")
  end

  def speakers = utterances.map { |u| u["speaker"] }.uniq

  # ¿La diarización colapsó?
  #
  # Condición ESTRUCTURAL y no un umbral: todas las utterances del mismo
  # hablante mientras en la mesa hay dos o más personas. No hay corte sobre
  # `speaker_confidence` a propósito — se midió 0,196–0,687 sobre audio
  # sintético y no hay línea base de voces reales, así que cualquier número
  # sería inventado, y un umbral inventado es la guarda que da permiso. El
  # número se MUESTRA en la pantalla; no se juzga acá.
  #
  # Sin utterances es false: no se avisa sobre una transcripción que no existe.
  def collapsed_diarization?
    return false if utterances.empty?

    speakers.size == 1 && workshop_group.workshop_group_members.count > 1
  end

  private

  # La mesa y la sala tienen que ser del mismo taller. Las FK compuestas sólo
  # atan a la misma EMPRESA, así que esto no lo cubre Postgres. Mismo par de
  # validaciones que `WorkshopDraft`.
  def group_and_room_share_workshop
    return if workshop_group.nil? || workshop_challenge.nil?
    return if workshop_group.workshop_id == workshop_challenge.workshop_id

    errors.add(:workshop_group, "no es de este taller")
  end

  def idea_matches_room
    return if idea.nil? || workshop_challenge.nil?
    return if idea.challenge_id == workshop_challenge.challenge_id

    errors.add(:idea, "no es de este desafío")
  end
end
```

- [ ] **Paso 7: Colgar la asociación de la mesa**

En `app/models/workshop_group.rb`, junto a `has_many :workshop_drafts`:

```ruby
  # `dependent: :destroy` como los borradores y las propuestas: borrar una mesa
  # a mano se lleva su grabación, y el aviso de la pantalla lo dice.
  has_many :workshop_recordings, dependent: :destroy
```

- [ ] **Paso 8: Correr el spec y verificar que pasa**

```bash
make spec-file FILE=spec/models/workshop_recording_spec.rb
```

Esperado: PASS, 9 ejemplos.

- [ ] **Paso 9: Correr los specs de tenencia**

```bash
make spec-file FILE=spec/tenancy/schema_spec.rb
```

Esperado: PASS. Ese spec introspecciona `pg_constraint` y falla si aparece una
FK **simple** entre dos tablas con `company_id`: si falla, te olvidaste un
`add_tenant_fk`.

- [ ] **Paso 10: Commit**

```bash
git add db/migrate/20261008120000_create_workshop_recordings.rb db/structure.sql \
        app/models/workshop_recording.rb app/models/workshop_group.rb \
        spec/models/workshop_recording_spec.rb spec/factories/workshop_recordings.rb
git commit -m "La grabación de la mesa tiene tabla, y el aviso de diarización colapsada es estructural y no un umbral"
```

---

## Tarea 4: El POST que sube el audio, y el que lo sirve

**Files:**
- Create: `app/controllers/workshop_recordings_controller.rb`
- Modify: `config/routes.rb:136-144` (dentro de `resources :workshop_challenges`)
- Test: `spec/requests/workshop_recordings_spec.rb` (nuevo)

**Interfaces:**
- Consumes: `WorkshopRecording` (Tarea 3),
  `Flow::Workshops::TranscribeRecordingJob` (Tarea 5 — se encola acá y se
  escribe allá; hasta la Tarea 5 el spec la stubea).
- Produces: `POST /workshops/:workshop_id/salas/:sala_id/recordings` → 201 con
  el id en el cuerpo JSON `{"id": "<uuid>"}`.
  `GET /workshops/:workshop_id/salas/:sala_id/recordings/:id` → el audio.

**Por qué 201 con JSON y no un redirect:** lo dispara un `fetch` del JS al parar
de grabar, igual que el autoguardado. Un `redirect_to` haría que el `fetch`
siga la redirección y traiga la pantalla entera. El JS necesita el id para
después poder consultar el estado.

- [ ] **Paso 1: Escribir el spec que falla**

Crear `spec/requests/workshop_recordings_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# La subida del audio de la mesa. Lo dispara un `fetch` al parar de grabar, así
# que contesta códigos y JSON, nunca un redirect.
RSpec.describe "sala del taller: la grabación de la mesa", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email, rol = :participant)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, rol, company: company, user: u)
      u
    end
  end

  let!(:ana) { member("ana@test.dev") }
  let!(:beto) { member("beto@test.dev") }

  let!(:idear) do
    as_company(company) do
      challenge = create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: "ideation", status: "active")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge,
                                         challenge_step: step)
      group = create(:workshop_group, workshop: workshop)
      [ ana, beto ].each { |u| create(:workshop_group_member, workshop_group: group, user: u) }
      { workshop: workshop, link: link, group: group, challenge: challenge }
    end
  end

  def audio
    Rack::Test::UploadedFile.new(
      StringIO.new("bytes-de-audio-que-no-se-transcriben-en-el-spec"),
      "audio/webm", original_filename: "mesa.webm"
    )
  end

  def post_recording(setup, params = { file: audio })
    post workshop_sala_recordings_path(setup[:workshop], setup[:link]), params: params
  end

  before { allow(Flow::Workshops::TranscribeRecordingJob).to receive(:perform_later) }

  describe "las guardas, en el mismo orden que los otros POST de la sala" do
    it "sin sesión manda al login" do
      post_recording(idear)

      expect(response).to redirect_to(login_path)
    end

    it "quien administra y no está sentado en ninguna mesa: 403" do
      # `work?` da true por `administers_any?` SIN mesa: es lo que cierra el
      # `group_of`. Un `participant` sin mesa no llega: el scope le da 404.
      admin = member("admin@test.dev", :admin)
      sign_in(admin, company: company)

      post_recording(idear)

      expect(response).to have_http_status(:forbidden)
    end

    it "desde la mesa de llegada, 403" do
      as_company(company) do
        llegada = create(:workshop_group, workshop: idear[:workshop], arrival: true)
        idear[:group].workshop_group_members.destroy_all
        create(:workshop_group_member, workshop_group: llegada, user: ana)
      end
      sign_in(ana, company: company)

      post_recording(idear)

      expect(response).to have_http_status(:forbidden)
    end

    it "con el vínculo cerrado, 409" do
      as_company(company) { idear[:link].update!(status: "closed") }
      sign_in(ana, company: company)

      post_recording(idear)

      expect(response).to have_http_status(:conflict)
    end
  end

  describe "el POST sin archivo" do
    it "contesta 400 y no crea nada" do
      # Sin esto, `attach(nil)` revienta con un 500 y la mesa ve una pantalla de
      # error en vez de un motivo.
      sign_in(ana, company: company)

      expect { post_recording(idear, {}) }.not_to change { as_company(company) { WorkshopRecording.count } }
      expect(response).to have_http_status(:bad_request)
    end

    it "con un archivo que no es audio, 415" do
      sign_in(ana, company: company)
      texto = Rack::Test::UploadedFile.new(
        StringIO.new("no soy audio"), "text/plain", original_filename: "x.txt"
      )

      post_recording(idear, { file: texto })

      expect(response).to have_http_status(:unsupported_media_type)
    end
  end

  describe "el camino feliz" do
    it "crea la grabación pendiente, adjunta el audio y encola el job" do
      sign_in(ana, company: company)

      post_recording(idear)

      expect(response).to have_http_status(:created)
      grabacion = as_company(company) { WorkshopRecording.last }
      expect(grabacion.status).to eq("pending")
      expect(grabacion.recorded_by).to eq(ana)
      as_company(company) do
        expect(grabacion.workshop_group).to eq(idear[:group])
        expect(grabacion.file).to be_attached
      end
      expect(Flow::Workshops::TranscribeRecordingJob)
        .to have_received(:perform_later).with(company.id, grabacion.id)
    end

    it "acepta el tipo con parámetro, que es lo que manda MediaRecorder" do
      # Chromium manda `audio/webm;codecs=opus`: se compara el tipo base.
      sign_in(ana, company: company)
      opus = Rack::Test::UploadedFile.new(
        StringIO.new("bytes"), "audio/webm;codecs=opus", original_filename: "mesa.webm"
      )

      post_recording(idear, { file: opus })

      expect(response).to have_http_status(:created)
    end

    it "devuelve el id en el cuerpo, que es lo que el JS necesita" do
      sign_in(ana, company: company)

      post_recording(idear)

      expect(response.parsed_body["id"]).to eq(as_company(company) { WorkshopRecording.last.id })
    end

    it "dos personas de la mesa pueden grabar a la vez: son dos filas" do
      # No hay índice único, a diferencia del borrador. Lo que no puede pasar es
      # que una pise a la otra.
      sign_in(ana, company: company)
      post_recording(idear)
      sign_in(beto, company: company)
      post_recording(idear)

      expect(as_company(company) { WorkshopRecording.count }).to eq(2)
    end
  end

  describe "servir el audio" do
    it "lo devuelve a quien está en la mesa" do
      sign_in(ana, company: company)
      post_recording(idear)
      grabacion = as_company(company) { WorkshopRecording.last }

      get workshop_sala_recording_path(idear[:workshop], idear[:link], grabacion)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("audio/webm")
    end

    it "una grabación de otra empresa da 404, no 403" do
      # Un 403 sería un oráculo de existencia. La fila se busca DENTRO de la
      # sala, que ya se buscó por `policy_scope`.
      otra = without_tenant { create(:company, slug: "otra") }
      ajena = as_company(otra) do
        challenge = create(:challenge)
        step = create(:challenge_step, challenge: challenge, kind: "ideation", status: "active")
        workshop = create(:workshop, status: "open")
        link = create(:workshop_challenge, workshop: workshop, challenge: challenge,
                                           challenge_step: step)
        group = create(:workshop_group, workshop: workshop)
        create(:workshop_recording, :ready, workshop_group: group, workshop_challenge: link,
                                            recorded_by: create(:user))
      end
      # Con audio adjunto: sin él, el 404 lo daría `send_attached_file` aunque la
      # búsqueda encontrara la fila ajena, y el ejemplo no probaría el scope.
      as_company(otra) { ajena.file.attach(io: StringIO.new("x"), filename: "a.webm", content_type: "audio/webm") }
      sign_in(ana, company: company)

      get workshop_sala_recording_path(idear[:workshop], idear[:link], ajena)

      expect(response).to have_http_status(:not_found)
    end

    it "una grabación sin audio adjunto da 404 y no 500" do
      # El caso llega de verdad: la fila se crea antes de adjuntar.
      grabacion = as_company(company) do
        create(:workshop_recording, workshop_group: idear[:group],
                                    workshop_challenge: idear[:link], recorded_by: ana)
      end
      sign_in(ana, company: company)

      get workshop_sala_recording_path(idear[:workshop], idear[:link], grabacion)

      expect(response).to have_http_status(:not_found)
    end
  end
end
```

- [ ] **Paso 2: Correr el spec y verificar que falla**

```bash
make spec-file FILE=spec/requests/workshop_recordings_spec.rb
```

Esperado: FAIL. **Ojo: NO falla por el helper de ruta que falta**, como decía
antes esta línea, sino con `uninitialized constant
Flow::Workshops::TranscribeRecordingJob`: el `before` del spec stubea esa
constante y por lo tanto revienta primero.

- [ ] **Paso 3: Sumar las rutas**

En `config/routes.rb`, dentro de `resources :workshop_challenges ... do`, junto
a `resource :draft`:

```ruby
      # Plural y con `show`, a diferencia del borrador: una mesa graba VARIAS
      # veces en una sesión, y cada grabación se puede escuchar. El `show`
      # sirve el audio por un controller propio y no por `rails_blob_path`, que
      # verifica la firma del blob y nada más —sin sesión, sin membresía, sin
      # Pundit y sin tenant—.
      resources :recordings, only: %i[create show], controller: "workshop_recordings"
```

- [ ] **Paso 4: Escribir el controller**

Crear `app/controllers/workshop_recordings_controller.rb`:

```ruby
# frozen_string_literal: true

# El audio de la conversación de una mesa: el ÚNICO escritor de
# `WorkshopRecording`.
#
# Contesta códigos y JSON, nunca un redirect: lo dispara un `fetch` del JS al
# parar de grabar, igual que el autoguardado, y un `redirect_to` haría que el
# `fetch` siga la redirección y traiga la pantalla entera.
class WorkshopRecordingsController < ApplicationController
  # Tipos que `MediaRecorder` puede producir. Medido: Chromium elige
  # `audio/webm;codecs=opus`, y Safari da `audio/mp4`. El parámetro `codecs`
  # viaja en el Content-Type, así que se compara el tipo base.
  AUDIO_TYPES = %w[audio/webm audio/ogg audio/mp4 audio/wav audio/mpeg].freeze

  before_action :set_link

  def create
    authorize @workshop, :work?
    # Las mismas guardas que `WorkshopDraftsController` y en el mismo orden.
    # Divergir es cómo se abrió la fuga que esos documentan: `work?` da true por
    # `administers_any?` SIN mesa.
    return head :conflict unless @link.workable?

    group = @workshop.group_of(current_user)
    return head :forbidden unless group
    # La mesa de llegada no trabaja. Misma pregunta que los otros siete lugares;
    # éste es el octavo. El número está en CLAUDE.md y no acá: escrito en ocho
    # comentarios, el día que cambie miente en siete.
    return head :forbidden if group.arrival?

    archivo = params[:file]
    # Sin esto, `attach(nil)` levanta un 500 y la mesa ve una pantalla de error
    # en vez de un motivo. El caso lo causa el propio JS con un cuerpo mal
    # armado.
    return head :bad_request if archivo.blank?
    return head :unsupported_media_type unless audio?(archivo)

    grabacion = crear!(group, archivo)
    Flow::Workshops::TranscribeRecordingJob.perform_later(Current.company.id, grabacion.id)
    render json: { id: grabacion.id }, status: :created
  end

  def show
    authorize @workshop, :work?
    # DENTRO de la sala, que ya se buscó por `policy_scope`: una grabación de
    # otra empresa o de otra sala no se encuentra, así que da 404 y no 403. Un
    # 403 sería un oráculo de existencia.
    grabacion = @link.workshop_recordings.find_by!(id: params[:id])

    # Levanta `RecordNotFound` si no hay archivo adjunto, que es el caso real de
    # una fila creada antes de adjuntarle nada.
    send_attached_file(grabacion.file)
  end

  private

  def set_link
    @workshop = policy_scope(Workshop).find_by!(id: params[:workshop_id])
    @link = @workshop.workshop_challenges.find_by!(id: params[:sala_id])
  end

  def audio?(archivo)
    tipo = archivo.content_type.to_s.split(";").first.to_s.strip
    AUDIO_TYPES.include?(tipo)
  end

  def crear!(group, archivo)
    # La idea es CONTEXTO: qué tenía la sala elegida al grabar. En idear no hay
    # ninguna, y la fase la decide la SALA y no el cliente —un `idea_id` mandado
    # a idear se ignora—, igual que en el borrador.
    idea = @link.kind == "evolution" ? workable_idea(group) : nil

    grabacion = group.workshop_recordings.create!(
      workshop_challenge: @link, idea: idea, recorded_by: current_user, status: "pending"
    )
    grabacion.file.attach(archivo)
    grabacion
  end

  # El mismo idioma que `WorkshopDraftsController` y `WorkshopProposalsController`:
  # `policy_scope(Idea)` deja ver a quien participa sólo lo que creó o comparte,
  # y la mesa trabaja la idea de CUALQUIERA de sus integrantes.
  def workable_idea(group)
    return nil if params[:idea_id].blank?

    group.workable_ideas(@link.challenge).find_by(id: params[:idea_id])
  end
end
```

- [ ] **Paso 5: Colgar la asociación de la sala**

En `app/models/workshop_challenge.rb`, junto a las otras `has_many`:

```ruby
  # Por acá entra `show`: la grabación se busca DENTRO de la sala para que lo de
  # otra empresa dé 404 y no 403.
  has_many :workshop_recordings, dependent: :destroy
```

- [ ] **Paso 6: Correr el spec y verificar que pasa**

```bash
make spec-file FILE=spec/requests/workshop_recordings_spec.rb
```

Esperado: FAIL todavía, con `uninitialized constant
Flow::Workshops::TranscribeRecordingJob` — el job es de la Tarea 5. Agregá un
archivo mínimo para desbloquear:

```ruby
# app/jobs/flow/workshops/transcribe_recording_job.rb
module Flow
  module Workshops
    class TranscribeRecordingJob < ApplicationJob
      queue_as :flow_ai
    end
  end
end
```

Volvé a correr. Esperado: PASS, **13** ejemplos.

- [ ] **Paso 7: Commit**

```bash
git add config/routes.rb app/controllers/workshop_recordings_controller.rb \
        app/models/workshop_challenge.rb app/jobs/flow/workshops/transcribe_recording_job.rb \
        spec/requests/workshop_recordings_spec.rb
git commit -m "La mesa sube su audio con las mismas cuatro guardas que los otros POST de la sala"
```

---

## Tarea 5: El job que transcribe

**Files:**
- Modify: `app/jobs/flow/workshops/transcribe_recording_job.rb`
- Create: `app/lib/flow/workshops/transcribe_recording.rb`
- Test: `spec/lib/flow/workshops/transcribe_recording_spec.rb` (nuevo)

**Interfaces:**
- Consumes: `Flow::AI.speech_provider` (Tarea 1), `WorkshopRecording` (Tarea 3),
  `Flow::Errors::TranscriptionFailed` (Tarea 1).
- Produces: `Flow::Workshops::TranscribeRecording.call(recording)` → `Boolean`
  (true si transcribió, false si no había nada que hacer).
  `Flow::Workshops::TranscribeRecordingJob.perform_later(company_id,
  recording_id)`.

- [ ] **Paso 1: Escribir el spec que falla**

Crear `spec/lib/flow/workshops/transcribe_recording_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# Transcribir llama a un servicio externo, así que va a un job: parar una
# grabación no puede depender de que Deepgram responda.
RSpec.describe Flow::Workshops::TranscribeRecording do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }
  let!(:ana) { without_tenant { u = create(:user); create(:membership, :participant, company: company, user: u); u } }

  def grabacion(status: "pending", con_audio: true)
    as_company(company) do
      challenge = create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: "ideation", status: "active")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge,
                                         challenge_step: step)
      group = create(:workshop_group, workshop: workshop)
      create(:workshop_group_member, workshop_group: group, user: ana)
      rec = create(:workshop_recording, workshop_group: group, workshop_challenge: link,
                                        recorded_by: ana, status: status)
      if con_audio
        rec.file.attach(io: StringIO.new("bytes"), filename: "mesa.webm",
                        content_type: "audio/webm")
      end
      rec
    end
  end

  before { Flow::AI.reset_provider! }
  after  { Flow::AI.reset_provider! }

  it "escribe las utterances, la duración y la auditoría" do
    rec = grabacion
    as_company(company) do
      Flow::Workshops::TranscribeRecording.call(rec)
      rec.reload

      expect(rec.status).to eq("ready")
      expect(rec.utterances.size).to eq(2)
      expect(rec.utterances.first["transcript"]).to be_present
      expect(rec.provider).to eq("fixture")
      expect(rec.model).to eq("fixture-v1")
    end
  end

  it "es idempotente: sobre una `ready` no vuelve a llamar al proveedor" do
    # No es prolijidad: a diferencia de los embeddings, CADA transcripción se
    # cobra por minuto. Un reintento reintenta una llamada que falló, no
    # re-transcribe una que salió bien.
    rec = grabacion(status: "ready")
    as_company(company) do
      # El objeto REAL con `transcribe` espiado, y no un `instance_double`:
      # devuelve un `Provider::Transcription` y un doble verificador obliga a
      # construirlo a mano para nada.
      proveedor = Flow::AI::Providers::Fixture.new
      allow(proveedor).to receive(:transcribe).and_call_original
      Flow::AI.speech_provider = proveedor

      expect(Flow::Workshops::TranscribeRecording.call(rec)).to be(false)
      expect(proveedor).not_to have_received(:transcribe)
    end
  end

  it "una grabación sin audio queda `failed` con su motivo, y no revienta" do
    rec = grabacion(con_audio: false)
    as_company(company) do
      Flow::Workshops::TranscribeRecording.call(rec)

      expect(rec.reload.status).to eq("failed")
      expect(rec.error).to include("sin audio")
    end
  end

  it "una transcripción vacía queda `ready` y NO `failed`" do
    # Medido: silencio o ruido devuelve 200 con texto vacío. Marcarlo `failed`
    # sería mentir —la llamada salió bien—, y dejarlo `ready` con una tarjeta en
    # blanco sería el control fantasma. La pantalla lo dice.
    rec = grabacion
    as_company(company) do
      # El objeto real, con una transcripción vacía.
      proveedor = Flow::AI::Providers::Fixture.new
      allow(proveedor).to receive(:transcribe).and_return(
        Flow::AI::Provider::Transcription.new(
          utterances: [], duration: nil, request_id: nil, model: "fixture-v1"
        )
      )
      Flow::AI.speech_provider = proveedor

      Flow::Workshops::TranscribeRecording.call(rec)

      expect(rec.reload.status).to eq("ready")
      expect(rec.utterances).to eq([])
      expect(rec.error).to be_nil
    end
  end

  it "si el proveedor falla, la grabación queda `failed` y la excepción se propaga" do
    # Se propaga para que `retry_on` del job la vea: el reintento es del job y no
    # del servicio. El estado se escribe ANTES de propagar, así que la pantalla
    # dice algo aunque los tres reintentos se agoten.
    rec = grabacion
    as_company(company) do
      proveedor = Flow::AI::Providers::Fixture.new
      allow(proveedor).to receive(:transcribe)
        .and_raise(Flow::Errors::TranscriptionFailed, "deepgram respondió 500")
      Flow::AI.speech_provider = proveedor

      expect { Flow::Workshops::TranscribeRecording.call(rec) }
        .to raise_error(Flow::Errors::TranscriptionFailed)

      expect(rec.reload.status).to eq("failed")
      expect(rec.error).to include("500")
    end
  end

  it "dos grabaciones de la misma mesa no se pisan" do
    una = grabacion
    otra = grabacion
    as_company(company) do
      Flow::Workshops::TranscribeRecording.call(una)
      Flow::Workshops::TranscribeRecording.call(otra)

      expect(una.reload.utterances).to be_present
      expect(otra.reload.utterances).to be_present
      expect(una.id).not_to eq(otra.id)
    end
  end

  describe "el job" do
    it "no revienta si la empresa ya no existe" do
      expect { Flow::Workshops::TranscribeRecordingJob.perform_now(SecureRandom.uuid, SecureRandom.uuid) }
        .not_to raise_error
    end

    it "no revienta si la grabación ya no existe" do
      expect { Flow::Workshops::TranscribeRecordingJob.perform_now(company.id, SecureRandom.uuid) }
        .not_to raise_error
    end
  end
end
```

- [ ] **Paso 2: Correr el spec y verificar que falla**

```bash
make spec-file FILE=spec/lib/flow/workshops/transcribe_recording_spec.rb
```

Esperado: FAIL con `uninitialized constant
Flow::Workshops::TranscribeRecording`.

- [ ] **Paso 3: Escribir el servicio**

Crear `app/lib/flow/workshops/transcribe_recording.rb`:

```ruby
# frozen_string_literal: true

module Flow
  module Workshops
    # Audio → utterances con hablante.
    #
    # Le pide la transcripción a `Flow::AI.speech_provider` y NO al de chat. Son objetos distintos, y
    # preguntarle al de chat es exactamente el error que `DetectDuplicates` pagó
    # con los embeddings: el proveedor específico quedaba sin usarse nunca, con
    # la credencial puesta y todo.
    class TranscribeRecording
      def self.call(recording) = new(recording).call

      def initialize(recording)
        @recording = recording
      end

      def call
        # Idempotencia con factura atrás: cada transcripción se COBRA por
        # minuto, a diferencia de un embedding que se recalcula gratis. El
        # reintento del job reintenta una llamada que falló; no re-transcribe
        # una que salió bien.
        return false if recording.status == "ready"

        unless recording.file.attached?
          fallar!("sin audio adjunto: la fila existe pero el blob no llegó")
          return false
        end

        recording.update!(status: "transcribing")
        transcribir!
        true
      rescue Flow::Errors::TranscriptionFailed => e
        # El estado se escribe ANTES de propagar: así la pantalla dice algo
        # aunque los tres reintentos del job se agoten.
        fallar!(e.message)
        raise
      end

      private

      attr_reader :recording

      def transcribir!
        proveedor = Flow::AI.speech_provider
        # `transcribe` devuelve un `Provider::Transcription` —utterances Y
        # metadata en el mismo valor inmutable— y no un arreglo más un
        # `last_metadata` que se pregunta después.
        #
        # El porqué es una carrera que el diseño anterior tenía: el proveedor se
        # memoiza (`Flow::AI.speech_provider` usa `||=`), así que UNA instancia
        # sirve al proceso entero, y Sidekiq corre con cinco hilos. Con dos
        # grabaciones en vuelo, el hilo A dejaba su metadata en el objeto, el B
        # la pisaba, y acá se escribía el `request_id` del B en la fila del A.
        # Auditoría cruzada, en el camino que la spec marca como riesgo —«dos
        # personas de la mesa grabando a la vez»— e invisible para todo spec.
        resultado = proveedor.transcribe(
          audio: recording.file.download,
          content_type: recording.file.content_type,
          language: idioma
        )

        # Una transcripción vacía NO es un fallo: silencio o ruido devuelve 200
        # con texto vacío. Queda `ready` con cero utterances y la pantalla lo
        # dice; marcarla `failed` sería mentir sobre una llamada que salió bien.
        recording.update!(
          status: "ready",
          utterances: resultado.utterances,
          error: nil,
          duration_seconds: resultado.duration,
          request_id: resultado.request_id,
          provider: proveedor.name,
          # El fixture no tiene de dónde sacar un modelo, así que cae al nombre
          # del proveedor. Deepgram sí lo trae, en `metadata.model_info`.
          model: resultado.model || proveedor.name
        )
      end

      # El idioma de la app. No sale del audio: Deepgram lo quiere declarado, y
      # `nova-3` con el idioma puesto acierta más que adivinando.
      #
      # OJO: todo lo que se midió de este proveedor se midió en INGLÉS, porque
      # `flite` —lo único que sintetiza voz en esta máquina— no habla otro
      # idioma. Que transcriba español con la misma calidad es una afirmación
      # del proveedor y no una medición. La Tarea 8 la mide.
      def idioma = I18n.locale.to_s.split("-").first

      def fallar!(mensaje)
        recording.update!(status: "failed", error: mensaje)
      end
    end
  end
end
```

- [ ] **Paso 4: Escribir el job**

Reemplazar `app/jobs/flow/workshops/transcribe_recording_job.rb`:

```ruby
# frozen_string_literal: true

module Flow
  module Workshops
    # Transcribir llama a un servicio externo y parar una grabación no puede
    # depender de que responda. Calcado de `EmbedVersionJob`, incluido el
    # `bypass!` para encontrar la empresa antes de entrar a su tenant.
    class TranscribeRecordingJob < ApplicationJob
      queue_as :flow_ai
      retry_on Flow::Errors::TranscriptionFailed, attempts: 3, wait: :polynomially_longer

      def perform(company_id, recording_id)
        company = Flow::Tenant.bypass! { Company.find_by(id: company_id) }
        return if company.nil?

        Flow::Tenant.with(company) do
          recording = WorkshopRecording.find_by(id: recording_id)
          next if recording.nil?

          Flow::Workshops::TranscribeRecording.call(recording)
        end
      end
    end
  end
end
```

- [ ] **Paso 5: Correr el spec y verificar que pasa**

```bash
make spec-file FILE=spec/lib/flow/workshops/transcribe_recording_spec.rb
```

Esperado: PASS, 8 ejemplos.

- [ ] **Paso 6: Correr la suite entera**

```bash
make spec
```

Esperado: **0 fallas**.

- [ ] **Paso 7: Commit**

```bash
git add app/lib/flow/workshops/transcribe_recording.rb \
        app/jobs/flow/workshops/transcribe_recording_job.rb \
        spec/lib/flow/workshops/transcribe_recording_spec.rb
git commit -m "El job transcribe fuera del request, y sale temprano sobre una grabación lista porque cada llamada se cobra"
```

---

## Tarea 6: La pantalla y el JavaScript

**Files:**
- Create: `app/views/workshop_rooms/_recording.html.haml`
- Create: `app/javascript/workshop_recording.js`
- Modify: `app/javascript/application.js`
- Modify: `app/views/workshop_rooms/_ideation.html.haml`
- Modify: `app/views/workshop_rooms/_evolution.html.haml`
- Modify: `app/controllers/workshop_rooms_controller.rb` (publica `@recordings`)
- Modify: `config/locales/es.yml`
- Test: `spec/requests/pantalla_de_la_sala_grabacion_spec.rb` (nuevo)

**Interfaces:**
- Consumes: `WorkshopRecording#transcript_text`, `#collapsed_diarization?`,
  `#speakers` (Tarea 3); la ruta `workshop_sala_recordings_path` (Tarea 4).
- Produces: el partial `workshop_rooms/_recording`, que las dos caras
  renderizan; `data-recording-url` en el contenedor, que es lo que enciende el
  JS —mismo principio que `data-draft-url` y `data-live`—; y
  **`data-level`** en el mismo contenedor, el RMS crudo de 0 a 1 con tres
  decimales, que el bucle de dibujo reescribe en cada frame. Es el **único**
  puente por el que una guarda puede medir la onda, y por eso existe como
  atributo y no sólo como alto de una barra.
- Produces: las clases `.waveform` y `.waveform__bar`, literales, con regla
  propia en la hoja.

- [ ] **Paso 1: Escribir el spec que falla**

Crear `spec/requests/pantalla_de_la_sala_grabacion_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# El bloque de grabación en las DOS caras de la sala.
RSpec.describe "sala del taller: el bloque de grabación", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }
  let!(:ana) { without_tenant { u = create(:user); create(:membership, :participant, company: company, user: u); u } }
  let!(:beto) { without_tenant { u = create(:user); create(:membership, :participant, company: company, user: u); u } }

  def sala(kind: "ideation", arrival: false)
    as_company(company) do
      challenge = create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: kind, status: "active")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge,
                                         challenge_step: step)
      group = create(:workshop_group, workshop: workshop, arrival: arrival)
      [ ana, beto ].each { |u| create(:workshop_group_member, workshop_group: group, user: u) }
      { workshop: workshop, link: link, group: group }
    end
  end

  def visitar(s)
    get workshop_sala_path(s[:workshop], s[:link])
  end

  it "la cara de idear trae el control, con la URL que enciende el JS" do
    s = sala
    sign_in(ana, company: company)

    visitar(s)

    expect(response.body).to include("data-recording-url")
    expect(response.body).to include(workshop_sala_recordings_path(s[:workshop], s[:link]))
  end

  it "trae la onda con sus 40 barras, escondida hasta que haya micrófono" do
    # Las barras van en el MARKUP y no las crea el JS: así Tailwind ve las
    # clases y un morph que borre los `style` en línea se arregla en el frame
    # siguiente. `hidden` porque una onda plana sin grabar se lee como un
    # micrófono que no toma nada.
    s = sala
    sign_in(ana, company: company)

    visitar(s)

    expect(response.body.scan('class="waveform__bar"').size).to eq(40)
    expect(response.body).to match(/<div[^>]*class="waveform"[^>]*hidden/)
  end

  it "la última grabación abre su transcripción sola, y la anterior no" do
    # Hacer clic para ver lo que acabás de grabar es un paso que no agrega nada.
    # `recent_first`, así que la primera del listado es la última grabada.
    s = sala
    as_company(company) do
      create(:workshop_recording, :ready, workshop_group: s[:group],
                                          workshop_challenge: s[:link], recorded_by: ana,
                                          created_at: 2.minutes.ago)
      create(:workshop_recording, :ready, workshop_group: s[:group],
                                          workshop_challenge: s[:link], recorded_by: ana,
                                          created_at: 1.minute.ago)
    end
    sign_in(ana, company: company)

    visitar(s)

    expect(response.body.scan(/<details open/).size).to eq(1)
    expect(response.body.scan(/<details/).size).to eq(2)
  end

  it "desde la mesa de llegada NO trae el control" do
    # Es el octavo lugar que pregunta `arrival?`. Ofrecerlo igual sería un
    # control que rebota en el 403 del POST.
    s = sala(arrival: true)
    sign_in(ana, company: company)

    visitar(s)

    expect(response.body).not_to include("data-recording-url")
  end

  it "lista las grabaciones de la mesa con su transcripción" do
    s = sala
    as_company(company) do
      create(:workshop_recording, :ready, workshop_group: s[:group],
                                          workshop_challenge: s[:link], recorded_by: ana)
    end
    sign_in(ana, company: company)

    visitar(s)

    expect(response.body).to include("Hablante 1")
    expect(response.body).to include("Primera.")
  end

  it "avisa cuando la diarización colapsó" do
    s = sala
    as_company(company) do
      create(:workshop_recording, :colapsada, workshop_group: s[:group],
                                              workshop_challenge: s[:link], recorded_by: ana)
    end
    sign_in(ana, company: company)

    visitar(s)

    expect(response.body).to include(I18n.t("flow.recordings.collapsed_diarization"))
  end

  it "dice que no se detectó habla cuando la transcripción quedó vacía" do
    s = sala
    as_company(company) do
      create(:workshop_recording, workshop_group: s[:group], workshop_challenge: s[:link],
                                  recorded_by: ana, status: "ready", utterances: [])
    end
    sign_in(ana, company: company)

    visitar(s)

    expect(response.body).to include(I18n.t("flow.recordings.no_speech"))
  end

  it "dice de qué proveedor salió, para que un fixture no se lea como real" do
    s = sala
    as_company(company) do
      create(:workshop_recording, :ready, workshop_group: s[:group],
                                          workshop_challenge: s[:link], recorded_by: ana)
    end
    sign_in(ana, company: company)

    visitar(s)

    expect(response.body).to include("fixture-v1")
  end

  it "no lista las grabaciones de OTRA mesa del mismo taller" do
    s = sala
    as_company(company) do
      otra = create(:workshop_group, workshop: s[:workshop])
      create(:workshop_recording, :ready, workshop_group: otra, workshop_challenge: s[:link],
                                          recorded_by: beto,
                                          utterances: [ { "speaker" => 0, "start" => 0.0, "end" => 1.0,
                                                          "transcript" => "SECRETO-DE-OTRA-MESA",
                                                          "confidence" => 0.9,
                                                          "speaker_confidence" => 0.9 } ])
    end
    sign_in(ana, company: company)

    visitar(s)

    expect(response.body).not_to include("SECRETO-DE-OTRA-MESA")
  end
end
```

- [ ] **Paso 2: Correr el spec y verificar que falla**

```bash
make spec-file FILE=spec/requests/pantalla_de_la_sala_grabacion_spec.rb
```

Esperado: FAIL — no hay `data-recording-url` en ninguna parte.

- [ ] **Paso 3: Sumar los textos al locale**

En `config/locales/es.yml`, dentro de `flow:`:

```yaml
    recordings:
      title: "Grabar la conversación"
      hint: "Se graba lo que se habla en la mesa y se transcribe con quién dijo qué."
      start: "Grabar"
      stop: "Parar"
      recording: "Grabando"
      uploading: "Subiendo…"
      transcribing: "Transcribiendo…"
      failed: "No se pudo transcribir."
      no_speech: "No se detectó habla en esta grabación."
      collapsed_diarization: "Esta transcripción salió con un solo hablante aunque en la mesa hay varias personas: la separación de voces no funcionó."
      transcript: "Qué se dijo"
      speaker: "Hablante %{n}"
      listen: "Escuchar el audio"
      # Los tres fallos del navegador. Van con su propio texto porque el motivo
      # y lo que hay que hacer son distintos en cada uno.
      insecure_context: "Este navegador no puede grabar porque la página no se sirve por HTTPS. Abrila en la máquina donde corre la app, o servila con certificado."
      denied: "El navegador bloqueó el micrófono. Dale permiso en la barra de direcciones y volvé a intentar."
      no_device: "No se encontró ningún micrófono en este equipo."
```

- [ ] **Paso 4: Escribir el partial**

Crear `app/views/workshop_rooms/_recording.html.haml`:

```haml
-# Grabar la conversación de la mesa.
-#
-# Va al CENTRO y no a la columna de referencia, y es por una regla más un
-# límite medido. La regla: «el centro es lo que se hace», y grabar es lo que se
-# hace. El límite: `[REFERENCIA]` declaradamente NO mide la sala, y la columna
-# es de 320px con `max-height: 100vh` — una transcripción de 20 minutos ahí
-# queda detrás de su propio scroll.
-#
-# La transcripción va en un `<details>`, que es el único mecanismo plegable de
-# la app y el que `application.js` protege del morph cancelando la remoción del
-# `open`.
.card
  .card-body
    .section-head
      %h2.section-title= t("flow.recordings.title")
    %p.muted= t("flow.recordings.hint")

    -# `data-recording-url` es lo que enciende el JS: el JS no sabe ni tiene que
    -# saber si esta sala admite trabajo. Mismo principio que `data-draft-url` y
    -# que `data-live` en `arrival_live.js`.
    -#
    -# `data-level` lo reescribe el bucle de dibujo con el RMS crudo. Es el ÚNICO
    -# puente por el que `[GRABAR]` puede medir la onda: las alturas de las
    -# barras dicen cómo quedó el dibujo, y esto dice qué midió el micrófono.
    %div{ data: { recording_url: workshop_sala_recordings_path(workshop, link),
                  bitrate: 32_000, level: "0" } }
      -# UN control, y el botón ES el estado: «Grabar» → onda con cronómetro y
      -# «Parar» → deshabilitado mientras sube. Ningún menú, ningún formato,
      -# ninguna opción de calidad: la mesa está en una reunión.
      .form-actions
        %button.btn.btn-primary{ type: "button", data: { recording_role: "toggle" } }
          = t("flow.recordings.start")
        -# Mientras graba dice el cronómetro y nada más: un texto «Grabando» al
        -# lado de una onda que se mueve es decir dos veces lo mismo. Fuera de
        -# ese momento lleva el motivo de por qué no se puede grabar.
        %p.muted{ data: { recording_role: "status" } }

      -# Las barras las dibuja el JS reescribiendo su `height`. Van en el DOM y
      -# NO en un `<canvas>` porque no hay un solo canvas en el repo y un canvas
      -# es una caja negra para todas las guardas. Nacen en el markup —40, fijas—
      -# para que el JS sólo toque alturas: así un morph que borre los `style` en
      -# línea se arregla en el frame siguiente, y Tailwind ve las clases.
      -#
      -# `hidden` hasta que haya micrófono abierto: una onda plana sin grabar se
      -# lee como un micrófono que no toma nada.
      .waveform{ hidden: true, data: { recording_role: "wave" } }
        - 40.times do
          %span.waveform__bar

- if recordings.any?
  -# `recent_first`, así que la primera es la última grabada y es la que se abre
  -# sola: hacer clic para ver lo que acabás de grabar es un paso que no agrega
  -# nada. Un `open` que pone el SERVIDOR sobrevive al morph — el guardia de
  -# `application.js` cancela la REMOCIÓN del `open`, no su agregado.
  - recordings.each_with_index do |recording, i|
    .card
      .card-body
        .section-head
          %h2.section-title
            = l(recording.created_at, format: :short)
            %span{ class: chip_de_grabacion(recording.status) }
              = t("flow.recording_statuses.#{recording.status}")
        -# Chicos y apagados, no en el encabezado: `provider` y `model` hacen
        -# falta para que una transcripción de fixture no se lea como real, y no
        -# son lo que la mesa vino a ver.
        %p.muted
          = recording.recorded_by.name
          - if recording.model.present?
            = "· #{recording.model}"
          - if recording.duration_seconds.present?
            = "· #{recording.duration_seconds.round} s"

        - if recording.status == "failed"
          .alert.alert-soft.alert-error
            %div
              %strong= t("flow.recordings.failed")
              %p.muted= recording.error
        - elsif recording.status == "ready" && recording.utterances.empty?
          %p.muted= t("flow.recordings.no_speech")
        - elsif recording.status == "ready"
          - if recording.collapsed_diarization?
            .alert.alert-soft.alert-warning
              %div= t("flow.recordings.collapsed_diarization")
          %details{ open: i.zero? }
            %summary= t("flow.recordings.transcript")
            %ul.field-list
              - recording.utterances.each do |u|
                %li.field-list__item
                  %div
                    %p.muted= t("flow.recordings.speaker", n: u["speaker"].to_i + 1)
                    = u["transcript"]

        - if recording.file.attached?
          = link_to t("flow.recordings.listen"),
                    workshop_sala_recording_path(workshop, link, recording),
                    class: "btn btn-ghost"
```

- [ ] **Paso 5: Sumar el chip al helper**

En `app/helpers/estilos_helper.rb`, junto a los otros mapeos. **Nunca
`"badge-#{x}"`:** una clase interpolada no llega a la hoja y el elemento queda
sin ninguna regla detrás.

```ruby
  # El estado de una grabación. Va acá y no como ternario en la vista: un mapeo
  # en la vista queda afuera del spec que compara contra el enum, que es cómo
  # un cuarto estado se habría pintado con la rama de otro sin que nada se
  # pusiera rojo.
  CHIP_DE_GRABACION = {
    "pending" => "badge badge-soft",
    "transcribing" => "badge badge-soft badge-info",
    "ready" => "badge badge-soft badge-success",
    "failed" => "badge badge-soft badge-error"
  }.freeze

  def chip_de_grabacion(status) = CHIP_DE_GRABACION.fetch(status)
```

Y en `config/locales/es.yml`, dentro de `flow:`:

```yaml
    recording_statuses:
      pending: "en cola"
      transcribing: "transcribiendo"
      ready: "lista"
      failed: "falló"
```

Sumar el ejemplo contra el enum en `spec/helpers/estilos_helper_spec.rb`:

```ruby
  it "tiene un chip para cada estado de grabación" do
    WorkshopRecording::STATUSES.each do |status|
      expect(EstilosHelper::CHIP_DE_GRABACION).to have_key(status)
      expect(EstilosHelper::CHIP_DE_GRABACION[status]).to start_with("badge ")
    end
  end
```

- [ ] **Paso 6: Escribir el JavaScript**

Crear `app/javascript/workshop_recording.js`:

```javascript
// La mesa graba su conversación.
//
// El estado vive ACÁ, en variables de módulo, y el DOM es una vista de él. Es
// lo que lo diferencia de sus dos hermanos, y copiarlos cortaría grabaciones:
//
//   · `arrival_live.js` PARA en `turbo:before-render`: un temporizador
//     apuntando a una pantalla muerta está mal.
//   · `workshop_draft.js` DESCARGA en `turbo:before-render`: los últimos dos
//     segundos no se pueden perder.
//   · esto no hace ninguna de las dos. `turbo:before-render` dispara también en
//     un morph, y un morph ocurre con cualquier POST que vuelva a la misma URL
//     —alguien de la mesa apretando «Crear borrador»—. Pararse ahí cortaría la
//     grabación de la reunión.
//
// Como el grabador y los trozos son de módulo, un morph que reemplaza el botón
// y el indicador no los toca: `turbo:load` vuelve a derivar el DOM, con la
// misma prueba de identidad de nodo que usa el borrador.
let caja = null;
let rec = null;
let trozos = [];
let stream = null;
let desde = null;
let cronometro = null;
// La onda. `audio` es el AudioContext, que hay que CERRAR al parar: sin eso
// queda uno por grabación y el navegador termina negándose a dar más.
let audio = null;
let analizador = null;
let muestras = null;
let frame = null;

const TEXTOS = {
  start: 'Grabar',
  stop: 'Parar',
  uploading: 'Subiendo…',
};

// Cuántas barras hay NO se declara acá: el bucle lee `onda.children`, así que la
// cantidad vive en un solo lugar, el markup del partial. Una constante al lado
// sería una segunda fuente que el día que difiera deja barras sin dibujar o un
// índice fuera de rango.
//
// Abajo de esto la barra se dibuja en su mínimo. Es un umbral de PRESENTACIÓN y
// decide un alto en pixeles, no si se avisa algo: a diferencia del de la
// diarización, acá no hay decisión que un número inventado pueda falsear. El
// nivel CRUDO se publica igual en `data-level`, así que lo que se mide es la
// causa y no el dibujo.
const PISO_VISIBLE = 0.01;

function nodo(rol) {
  return caja ? caja.querySelector(`[data-recording-role="${rol}"]`) : null;
}

function pintar(estado, detalle = '') {
  const boton = nodo('toggle');
  const sello = nodo('status');
  if (!boton || !sello) return;

  if (estado === 'bloqueado') {
    boton.hidden = true;
    sello.textContent = detalle;
    return;
  }
  boton.hidden = false;
  boton.disabled = estado === 'subiendo';
  boton.textContent = estado === 'grabando' ? TEXTOS.stop : TEXTOS.start;
  sello.textContent = detalle;
}

// Por qué este navegador no puede grabar, o null si puede.
//
// `getUserMedia` NO EXISTE fuera de un contexto seguro, y `docker-compose`
// publica el puerto en plano: en la máquina que corre Docker es `localhost` y
// anda, y en el teléfono de al lado por `http://<ip>:3001` es `undefined`. Un
// botón que no hace nada es el control fantasma que este repo persigue, así que
// se pregunta ANTES de dibujarlo.
function impedimento() {
  if (!window.isSecureContext) return caja.dataset.insecureText;
  if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
    return caja.dataset.insecureText;
  }
  if (typeof MediaRecorder === 'undefined') return caja.dataset.noDeviceText;
  return null;
}

function tictac() {
  if (!desde) return;
  const seg = Math.floor((Date.now() - desde) / 1000);
  const mm = String(Math.floor(seg / 60)).padStart(2, '0');
  const ss = String(seg % 60).padStart(2, '0');
  // Sólo el cronómetro: la onda que se mueve al lado ya dice «grabando».
  pintar('grabando', `${mm}:${ss}`);
}

// ── La onda ───────────────────────────────────────────────────────────────
//
// Barras del DOM y NO un `<canvas>`: no hay un solo canvas en el repo, y un
// canvas es una caja negra para todas las guardas —`[CLASES]`, `[CONTRASTE]`,
// `[SOMBRA]` no ven adentro— y una guarda que no puede ver DA PERMISO. De paso
// el color lo pone la hoja con `--dato`, en vez de que el JS tenga que leer el
// token y re-leerlo al cambiar de tema.
function abrirAnalizador() {
  const Ctx = window.AudioContext || window.webkitAudioContext;
  if (!Ctx) return false;
  audio = new Ctx();
  analizador = audio.createAnalyser();
  // 1024 en el dominio del tiempo alcanza de sobra para un RMS y cuesta menos
  // que el default de 2048.
  analizador.fftSize = 1024;
  muestras = new Uint8Array(analizador.fftSize);
  audio.createMediaStreamSource(stream).connect(analizador);
  return true;
}

// RMS de 0 a 1. Los bytes del dominio del tiempo vienen centrados en 128, así
// que el silencio da ~0 y no ~0,5.
function nivel() {
  if (!analizador) return 0;
  analizador.getByteTimeDomainData(muestras);
  let suma = 0;
  for (let i = 0; i < muestras.length; i++) {
    const v = (muestras[i] - 128) / 128;
    suma += v * v;
  }
  return Math.sqrt(suma / muestras.length);
}

function dibujar() {
  frame = null;
  if (!caja || !caja.isConnected) return;
  const onda = nodo('wave');
  // Se re-consulta cada frame y no se cachea: un morph puede haber reemplazado
  // las barras, y con la referencia vieja el bucle dibujaría sobre nodos
  // desconectados sin que se vea nada.
  if (!onda) return;

  const n = nivel();
  // El nivel CRUDO, que es lo que `[GRABAR]` mide. Tres decimales alcanzan y
  // evitan reescribir el atributo con ruido de punto flotante.
  caja.dataset.level = n.toFixed(3);

  const barras = onda.children;
  // Se corre todo una posición y la nueva entra al final: la onda SCROLLEA, que
  // es lo que deja ver dónde hubo silencio hace tres segundos. Un osciloscopio
  // instantáneo no muestra historia.
  for (let i = 0; i < barras.length - 1; i++) {
    barras[i].style.height = barras[i + 1].style.height;
  }
  const alto = n < PISO_VISIBLE ? 2 : Math.min(100, Math.round(n * 260));
  barras[barras.length - 1].style.height = `${alto}%`;

  if (rec && rec.state === 'recording') frame = requestAnimationFrame(dibujar);
}

function pararOnda() {
  if (frame !== null) cancelAnimationFrame(frame);
  frame = null;
  // CERRAR el contexto, no sólo soltarlo: uno por grabación se acumula.
  if (audio) audio.close().catch(() => {});
  audio = null;
  analizador = null;
  muestras = null;
  const onda = nodo('wave');
  if (onda) {
    onda.hidden = true;
    Array.from(onda.children).forEach((b) => { b.style.height = ''; });
  }
  if (caja) caja.dataset.level = '0';
}

// Mientras graba, irse de la página AVISA. No es prolijidad: `keepalive` tiene
// un tope de 64 KB por especificación y el audio son megabytes, así que una
// navegación real pierde lo grabado y no hay despedida que lo salve. Avisar es
// lo único que se puede hacer sin subida progresiva.
function alDescargar(e) {
  if (!rec || rec.state !== 'recording') return;
  e.preventDefault();
  // Los navegadores modernos ignoran el texto y muestran el suyo; hay que
  // asignar `returnValue` igual para que el diálogo aparezca.
  e.returnValue = '';
}

async function arrancar() {
  try {
    stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  } catch (e) {
    // Dos motivos distintos y dos textos distintos: qué hacer no es lo mismo.
    const texto = e && e.name === 'NotFoundError'
      ? caja.dataset.noDeviceText
      : caja.dataset.deniedText;
    pintar('idle', texto);
    return;
  }
  trozos = [];
  // Bitrate EXPLÍCITO. Medido: el default de Chromium son 115 kbps, o sea 17,4
  // MB por 20 minutos. Para transcribir, 32 kbps de opus alcanzan de sobra y
  // bajan eso a ~4,8 MB.
  const bits = Number(caja.dataset.bitrate) || 32000;
  rec = new MediaRecorder(stream, { audioBitsPerSecond: bits });
  rec.ondataavailable = (e) => { if (e.data && e.data.size) trozos.push(e.data); };
  rec.onstop = subir;
  rec.start(1000);
  desde = Date.now();
  cronometro = setInterval(tictac, 1000);
  tictac();

  // La onda arranca DESPUÉS del grabador: si el analizador no se puede abrir
  // —un navegador sin Web Audio— se graba igual. La onda es la mejor señal que
  // hay, no una condición para grabar.
  const onda = nodo('wave');
  if (abrirAnalizador() && onda) {
    onda.hidden = false;
    frame = requestAnimationFrame(dibujar);
  }
}

function soltarMicrofono() {
  pararOnda();
  if (stream) stream.getTracks().forEach((t) => t.stop());
  stream = null;
  if (cronometro !== null) clearInterval(cronometro);
  cronometro = null;
  desde = null;
}

async function subir() {
  const url = caja && caja.dataset.recordingUrl;
  const tipo = rec ? rec.mimeType : 'audio/webm';
  const blob = new Blob(trozos, { type: tipo });
  trozos = [];
  rec = null;
  soltarMicrofono();
  if (!url || !blob.size) { pintar('idle'); return; }

  pintar('subiendo', TEXTOS.uploading);
  const cuerpo = new FormData();
  // La extensión sale del mimeType y no se fija a .webm: Safari da audio/mp4.
  const ext = tipo.includes('mp4') ? 'm4a' : 'webm';
  cuerpo.append('file', blob, `mesa.${ext}`);
  const idea = caja.dataset.ideaId;
  if (idea) cuerpo.append('idea_id', idea);

  try {
    const res = await fetch(url, {
      method: 'POST',
      body: cuerpo,
      headers: { 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || '' },
    });
    // 201 y NO `res.ok`: un `before_action` que redirige —sesión caída,
    // membresía revocada— le llega al `fetch` como 200, porque el `fetch` sigue
    // el 302 y convierte el POST en GET. Es el mismo bug que el autoguardado
    // pagó, y acá costaría la reunión entera.
    if (res.status !== 201) { pintar('idle', caja.dataset.failedText); return; }
    // Se devuelve el botón a `idle` ANTES de navegar, y no es redundante: la
    // navegación es un morph a la misma URL, y `start()` sale temprano cuando el
    // nodo es el mismo —ahí está grabando o acaba de grabar—, así que no vuelve
    // a pintar. El morph le sacaría el `disabled` igual, porque el HTML del
    // servidor no lo trae, pero eso es un accidente afortunado y no una
    // garantía: si mañana el botón nace deshabilitado en el markup, queda
    // muerto después de cada subida.
    pintar('idle');
    // La pantalla la refresca el servidor: se visita la misma URL y Turbo
    // morfea, así que la tarjeta nueva aparece con su estado «en cola».
    window.Turbo ? window.Turbo.visit(window.location.href, { action: 'replace' })
                 : window.location.reload();
  } catch (_e) {
    pintar('idle', caja.dataset.failedText);
  }
}

function alApretar() {
  if (rec && rec.state === 'recording') { rec.stop(); return; }
  arrancar();
}

function start() {
  const encontrado = document.querySelector('[data-recording-url]');
  // Turbo 8 morfea: después de un POST que vuelve a la misma URL el NODO puede
  // ser el mismo y `turbo:load` corre de nuevo. Si es el mismo nodo ya está
  // cableado, y además puede estar GRABANDO: recablearlo duplicaría el
  // listener, y pararlo cortaría la reunión.
  if (encontrado && encontrado === caja) return;
  caja = encontrado;
  if (!caja) return;

  const boton = nodo('toggle');
  if (!boton) return;
  const motivo = impedimento();
  if (motivo) { pintar('bloqueado', motivo); return; }
  boton.addEventListener('click', alApretar);
  // Si venía grabando y el nodo cambió por una navegación real, el micrófono se
  // suelta: el estado anterior ya no tiene dónde mostrarse.
  if (rec && rec.state === 'recording') rec.stop(); else pintar('idle');
}

addEventListener('turbo:load', start);
// Irse de la página de verdad sí para: el micrófono no puede quedar abierto.
addEventListener('pagehide', () => { if (rec && rec.state === 'recording') rec.stop(); });
addEventListener('beforeunload', alDescargar);
```

- [ ] **Paso 7: Importarlo, pasar los textos, y la regla de la onda**

En `app/javascript/application.js`, junto a los otros imports:

```javascript
import './workshop_recording';
```

En `app/assets/stylesheets/application.css`, junto a `.histogram__bar` —que es el
otro gráfico de barras de la app y comparte la tinta—:

```css
/* La onda del micrófono. Clase propia y no doce utilidades: es vocabulario de
   esta app y aparece con su regla, que es lo que `[CLASES]` puede ver. Va en
   barras del DOM y no en un `<canvas>` porque un canvas es una caja negra para
   todas las guardas.

   En TINTA DE DATOS y no en el acento: el acento es de las acciones, y una
   barra pintada con el violeta del botón de al lado se lee como un control.
   Misma regla que los dos gráficos de reportería. */
.waveform {
  display: flex;
  align-items: flex-end;
  gap: 2px;
  height: 48px;
  margin: 12px 0 0;
  padding: 0 2px;
}

/* El `height` lo escribe el JS en línea, en porcentaje. El mínimo de 2px es lo
   que hace que el silencio se vea como una línea y no como un hueco: una barra
   de alto 0 desaparece, y una onda con agujeros no se lee como silencio sino
   como que algo se rompió. */
.waveform__bar {
  flex: 1 1 0;
  min-height: 2px;
  height: 2px;
  background: var(--dato);
  border-radius: 2px;
  /* Sin transición: el dato ES la altura instantánea, y un suavizado de 100ms
     le miente al ojo sobre cuándo hubo silencio. */
}

/* La última barra es la que acaba de entrar: un paso más oscura para que se lea
   dónde está el "ahora" de la onda. Mismo recurso que `--dato-fuerte` en el
   contorno del histograma. */
.waveform__bar:last-child { background: var(--dato-fuerte); }
```

**No lleva `@media (prefers-reduced-motion)`, y es una decisión con
precedente.** La hoja ya dice por qué, para el spinner de la IA: «sigue girando
—que es lo que hace falta: es la ÚNICA señal de que la IA sigue trabajando, y
quieto se lee como colgado—». La onda es exactamente eso para el micrófono:
quieta se lee como un micrófono que no toma nada, que es justo el estado que
tiene que poder distinguir.

En el partial, sumar los textos al `data` del contenedor (el JS los lee de ahí
para no duplicar el locale en JavaScript):

```haml
    %div{ data: { recording_url: workshop_sala_recordings_path(workshop, link),
                  bitrate: 32_000,
                  idea_id: defined?(selected) && selected ? selected.id : nil,
                  insecure_text: t("flow.recordings.insecure_context"),
                  denied_text: t("flow.recordings.denied"),
                  no_device_text: t("flow.recordings.no_device"),
                  failed_text: t("flow.recordings.failed") } }
```

- [ ] **Paso 8: Renderizarlo en las dos caras**

En `app/views/workshop_rooms/_ideation.html.haml`, dentro del `else` final (o
sea donde la mesa puede trabajar), antes del card de «Crear borrador»:

```haml
  = render "workshop_rooms/recording", workshop: workshop, link: link,
                                       recordings: recordings
```

En `app/views/workshop_rooms/_evolution.html.haml`, en el lugar equivalente
—donde la mesa ya tiene trabajo disponible—, con la idea elegida:

```haml
  = render "workshop_rooms/recording", workshop: workshop, link: link,
                                       recordings: recordings, selected: selected
```

Y en `app/views/workshop_rooms/show.html.haml`, pasarle `recordings:` a los dos
renders existentes:

```haml
- when :ideation
  = render "workshop_rooms/ideation", workshop: @workshop, link: @link, group: @group,
                                      mesa_ideas: @mesa_ideas, draft: @draft,
                                      recordings: @recordings
- when :evolution
  = render "workshop_rooms/evolution", workshop: @workshop, link: @link, group: @group,
                                       ideas: @workable_ideas, selected: @selected_idea,
                                       proposals: @mesa_proposals, draft: @draft,
                                       recordings: @recordings
```

- [ ] **Paso 9: Publicar `@recordings` en el controller**

En `app/controllers/workshop_rooms_controller.rb`, dentro de `show`, junto a
donde se carga `@draft`:

```ruby
    # Las de ESTA mesa y nada más. El filtro por mesa es PORTANTE y no
    # prolijidad: quien administra no es `participant`, así que un scope por
    # policy le devolvería todo, y vería la conversación de las otras mesas bajo
    # un título que dice que es la suya. Es la misma trampa que `load_ideation`
    # documenta para las ideas. Y desde la llegada no se lista nada: ahí están
    # sentados los treinta que esperan.
    @recordings = load_recordings
```

Y como método privado del mismo controller:

```ruby
  def load_recordings
    return WorkshopRecording.none if @group.nil? || @group.arrival?

    @group.workshop_recordings.where(workshop_challenge: @link).recent_first
  end
```

- [ ] **Paso 10: Compilar el bundle**

**Sin esto el `.js` nuevo NO EXISTE para el navegador** y el recorrido validaría
en verde una app que no es la que escribiste:

```bash
make yarn-build
```

Verificá **las dos mitades**, porque son dos archivos compilados distintos y se
puede tener uno sin el otro:

```bash
docker compose exec app grep -c "recordingUrl" app/assets/builds/application-build.js
docker compose exec app grep -c "waveform__bar" app/assets/builds/application-build-css.css
```

**Ojo, y esto se descubrió midiendo: grepear una cadena que YA existía no prueba
que el bundle se reconstruyó.** En la ronda de arreglos de esta tarea,
`recordingUrl` daba 1 contra el bundle **viejo**, porque esa cadena había entrado
en el build anterior — o sea que el chequeo pasaba sin haber compilado nada. Para
verificar un rebuild hay que grepear algo que **sólo exista después del cambio**;
en esa ronda sirvió el literal `'subiendo'`, que la minificación conserva porque
es un string y no un nombre de variable (3 en el bundle, y en el fuente). Cada
vez que se toca el JS, elegí una cadena nueva de ESE cambio.

Esperado: los dos mayores que 0. Si el primero da 0, el import no entró; si el
segundo da 0, la regla no se compiló y la onda sale **sin alto, sin color y sin
`display:flex`** — o sea las barras apiladas en una columna, y
`spec/lint/reglas_sin_elemento_spec.rb` no lo caza porque ese lint busca reglas
SIN elemento y acá pasa lo contrario.

- [ ] **Paso 11: Correr el spec y verificar que pasa**

```bash
make spec-file FILE=spec/requests/pantalla_de_la_sala_grabacion_spec.rb
make spec-file FILE=spec/helpers/estilos_helper_spec.rb
```

Esperado: PASS los dos.

- [ ] **Paso 12: Correr la suite entera**

```bash
make spec
```

Esperado: **0 fallas**. Si falla
`spec/requests/pantalla_del_modulo_spec.rb`, es la secuencia de títulos: no
debería, porque la sala no es una pantalla de módulo.

- [ ] **Paso 13: Commit**

```bash
git add app/views/workshop_rooms/ app/javascript/workshop_recording.js \
        app/javascript/application.js app/helpers/estilos_helper.rb \
        app/assets/stylesheets/application.css \
        app/controllers/workshop_rooms_controller.rb config/locales/es.yml \
        spec/requests/pantalla_de_la_sala_grabacion_spec.rb \
        spec/helpers/estilos_helper_spec.rb
git commit -m "La mesa graba desde el navegador y ve la línea de sonido; el control dice por qué no puede en vez de no hacer nada"
```

---

## Tarea 7: La guarda `[GRABAR]`

**Files:**
- Create: `script/fake_audio.wav`
- Modify: `script/capture_screens.js:1899` (las flags del `launch`)
- Modify: `script/capture_screens.js:22-27` (el contador y el piso)
- Modify: `script/capture_screens.js:3305` y `:3356` (las dos llamadas)
- Modify: `script/capture_screens.js:3709` (la línea de contadores)
- Modify: `script/capture_screens.js:3722` en adelante (el chequeo del piso)
- Modify: `db/seeds.rb` (nada nuevo: se verifica que no hace falta)

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: `[GRABAR] N caras medidas` en la línea final, con
  `PISO_DE_GRABACIONES = 2`.

- [ ] **Paso 1: Crear el audio del micrófono falso**

`--use-file-for-fake-audio-capture` quiere un `.wav`, y `script/` es justo lo
que el contenedor monta (`-v "$(PWD)/script:/script:ro"` en el `Makefile`), así
que el archivo va ahí y adentro se ve como `/script/fake_audio.wav`.

**La estructura importa y no es decorativa: voz → SILENCIO → voz, con la
grabación de la guarda más corta que el archivo.** Ese silencio del medio es lo
único que distingue una onda real de una decorativa: números al azar o una
animación suelta dan nivel siempre, y nunca producen la corrida de ceros.

Se arma **en el host**, que tiene ffmpeg con `flite`:

```bash
ffmpeg -hide_banner -loglevel error -f lavfi \
  -i "flite=text='We should reduce the waste in the winery by reusing the barrels.':voice=slt" \
  -t 2.5 /tmp/a.wav -y
# 1,5 s de silencio: largo para que la guarda lo vea en varias muestras
# consecutivas, corto para no alargar la corrida.
ffmpeg -hide_banner -loglevel error -f lavfi -i anullsrc=r=16000:cl=mono -t 1.5 /tmp/sil.wav -y
ffmpeg -hide_banner -loglevel error -f lavfi \
  -i "flite=text='I disagree. The real problem is the onboarding of the new operators.':voice=awb" \
  -t 2.5 /tmp/b.wav -y
# Voz PRIMERO, no silencio: así el máximo queda establecido antes del hueco, y
# una onda que nunca arrancó no se confunde con el silencio del medio.
printf "file '/tmp/a.wav'\nfile '/tmp/sil.wav'\nfile '/tmp/b.wav'\n" > /tmp/l.txt
ffmpeg -hide_banner -loglevel error -f concat -safe 0 -i /tmp/l.txt \
  -ar 16000 -ac 1 script/fake_audio.wav -y
ffprobe -hide_banner script/fake_audio.wav 2>&1 | grep Duration
```

Esperado: ~6,5 segundos. La guarda graba **6**, así que la ventana cubre
voz → silencio → voz.

**Y una aclaración para que nadie se confunda después:** con
`FLOW_SPEECH_PROVIDER` sin declarar, la transcripción la da el **fixture**, que
no mira el audio. O sea que el CONTENIDO de este wav no cambia lo que `[GRABAR]`
ve: lo único que tiene que lograr es que `getUserMedia` resuelva y que el blob
salga con bytes. El contenido importa en un solo lugar, el Paso 6 de la Tarea 2,
donde se verifica el adapter contra la API real.

- [ ] **Paso 2: Sumar las flags al `launch`**

En `script/capture_screens.js:1899`, reemplazar:

```javascript
  const browser = await chromium.launch();
```

por:

```javascript
  // El micrófono falso, para `[GRABAR]`. Son flags de LANZAMIENTO, así que
  // aplican a la corrida entera; inofensivo, ninguna otra pantalla pide
  // micrófono. Medido: la pista aparece como `Fake Default Audio Input` en
  // estado `live`, el permiso se auto-concede, y el `mimeType` que elige
  // Chromium es `audio/webm;codecs=opus` — el mismo que Deepgram acepta.
  //
  // `%noloop` está MEDIDO y se honra: grabando 12 segundos de un wav de 5, la
  // frase aparece UNA vez en la transcripción y el resto es silencio. Importa
  // porque sin él Chromium repite el archivo, y una grabación larga
  // transcribiría la misma frase tres veces — lo que haría imposible distinguir
  // «grabó bien» de «grabó el loop».
  //
  // Ojo si se verifica de nuevo: comparar el TAMAÑO del blob no discrimina
  // nada. A bitrate fijo los bytes siguen a la duración y no al contenido, así
  // que con y sin el sufijo dan el mismo número exacto (15.989 bytes los dos,
  // medido). Hay que transcribir, y grabar MÁS que el largo del archivo.
  const browser = await chromium.launch({
    args: [
      '--use-fake-ui-for-media-stream',
      '--use-fake-device-for-media-stream',
      '--use-file-for-fake-audio-capture=/script/fake_audio.wav%noloop',
    ],
  });
```

- [ ] **Paso 3: Sumar el contador y el piso**

En `script/capture_screens.js`, junto a `draftMeasurements` (línea ~22):

```javascript
// En cuántas de las dos caras de la sala `[GRABAR]` midió el viaje completo:
// grabar, parar, subir, y que la transcripción aparezca.
let recordingMeasurements = 0;
// EXACTO en 2, por el mismo motivo que `PISO_DE_BORRADORES`: cuenta CARAS
// —idear y evolución— y no hay una tercera, así que un piso flojo no cazaría
// que una dejó de medirse.
//
// Una cara cuenta como medida sólo si pasaron TODAS las fases —el control, la
// onda con su silencio, la subida y la transcripción—, igual que en `[DRAFT]`.
// Un contador por fase volvería el piso 4 y rompería la semántica de «caras».
const PISO_DE_GRABACIONES = 2;

// Los umbrales de la onda. **Se CALIBRAN midiendo, no se adivinan**: el Paso 7
// manda imprimir la serie real del micrófono falso y pinchar estos tres con lo
// que salga. Los valores de abajo son el punto de partida.
//
// `VOZ_MINIMA` es el piso del pico durante la voz; `SILENCIO_MAXIMO` el techo de
// una muestra que cuenta como silencio —el mismo orden de magnitud que
// `PISO_VISIBLE` del JS, a propósito—; y `MUESTRAS_DE_SILENCIO`, cuántas
// seguidas hacen falta. El silencio del wav dura 1,5 s y se muestrea cada
// 100 ms, o sea ~15 muestras: pedir 8 deja margen para el ataque y la cola de
// las voces de al lado.
const VOZ_MINIMA = 0.02;
const SILENCIO_MAXIMO = 0.005;
const MUESTRAS_DE_SILENCIO = 8;
```

- [ ] **Paso 4: Escribir la guarda**

Junto a `revisarBorrador`, en `script/capture_screens.js`:

```javascript
// El viaje completo de la grabación: apretar, grabar unos segundos, parar,
// subir, y que la transcripción del fixture aparezca en pantalla.
//
// Es lo único que ve el camino entero. El POST, el job y el partial pueden
// estar los tres en verde y el botón no grabar: `getUserMedia` fuera de
// contexto seguro, el bundle sin compilar, el estado guardado en el DOM y
// borrado por un morph. Nada de eso lo ve un spec de Ruby.
async function revisarGrabacion(page, nombre) {
  const caja = page.locator('[data-recording-url]').first();
  if (!(await caja.count())) {
    failures++;
    console.error(`[GRABAR] ${nombre}: la sala no tiene bloque de grabación`);
    return;
  }

  const boton = caja.locator('[data-recording-role="toggle"]');
  // Un botón escondido significa que el JS encontró un impedimento. En el
  // recorrido corre sobre `localhost`, que es contexto seguro, así que esto
  // sólo pasa si el bundle no se compiló o si el micrófono falso no llegó.
  if (await boton.isHidden()) {
    failures++;
    const motivo = await caja.locator('[data-recording-role="status"]').innerText();
    console.error(`[GRABAR] ${nombre}: el control está bloqueado y dice «${motivo}». Si dice que falta HTTPS, el micrófono falso no llegó; si está vacío, falta \`make yarn-build\``);
    return;
  }

  const onda = caja.locator('[data-recording-role="wave"]');
  // Antes de grabar la onda está escondida: una onda plana sin micrófono abierto
  // se lee como un micrófono que no toma nada.
  if (!(await onda.isHidden())) {
    failures++;
    console.error(`[GRABAR] ${nombre}: la onda se ve antes de grabar y tendría que estar escondida`);
    return;
  }
  const barras = await onda.locator('.waveform__bar').count();
  if (barras !== 40) {
    failures++;
    console.error(`[GRABAR] ${nombre}: la onda tiene ${barras} barras y el markup declara 40`);
    return;
  }

  const antes = await page.locator('details summary').count();
  await boton.click();
  // Que el cronómetro corra es la prueba de que `getUserMedia` resolvió: el
  // texto cambia recién cuando hay stream.
  await page.waitForFunction(
    () => /\d\d:\d\d/.test(document.querySelector('[data-recording-role="status"]')?.textContent || ''),
    null, { timeout: 10000 },
  ).catch(() => {});
  const sello = await caja.locator('[data-recording-role="status"]').innerText();
  if (!/\d\d:\d\d/.test(sello)) {
    failures++;
    console.error(`[GRABAR] ${nombre}: después de apretar grabar el sello dice «${sello}» y tendría que traer un cronómetro: el micrófono no se abrió`);
    return;
  }

  // ── El morph en medio de la grabación ──────────────────────────────────
  //
  // Es el ÚNICO testigo de un bug que ya ocurrió: el servidor renderiza el
  // botón diciendo «Grabar» y el sello vacío, así que un morph le devolvía esos
  // valores mientras el micrófono seguía abierto —y la onda SÍ se recuperaba,
  // porque el bucle de dibujo reescribe las barras en el frame siguiente—.
  // Quien veía onda moviéndose al lado de un botón que decía «Grabar» lo
  // apretaba creyendo que arrancaba, y PARABA la reunión.
  //
  // Se fuerza con `Turbo.visit` a la misma URL en vez de apretando un botón de
  // la pantalla: un POST real —«Crear borrador»— dejaría datos sembrados de más
  // en el recorrido, y lo que se quiere probar es el morph, no el POST.
  const textoAntes = await boton.innerText();
  await page.evaluate(() => window.Turbo.visit(window.location.href, { action: 'replace' }));
  await page.waitForTimeout(1500);
  const textoDespues = await boton.innerText();
  const selloDespues = await caja.locator('[data-recording-role="status"]').innerText();
  if (textoDespues !== textoAntes || !/\d\d:\d\d/.test(selloDespues)) {
    failures++;
    console.error(`[GRABAR] ${nombre}: después de morfear en medio de la grabación el botón dice «${textoDespues}» (antes «${textoAntes}») y el sello «${selloDespues}»: el morph le devolvió el HTML del servidor y \`start()\` no repintó desde el estado del módulo`);
    return;
  }

  // ── La onda ────────────────────────────────────────────────────────────
  //
  // Se muestrea `data-level` —el RMS CRUDO, no el alto de la barra— mientras
  // graba. Es el único puente medible: las barras dicen cómo quedó el dibujo y
  // esto dice qué midió el micrófono.
  const niveles = [];
  for (let i = 0; i < 60; i++) {
    niveles.push(Number(await caja.getAttribute('data-level')));
    await page.waitForTimeout(100);
  }

  await boton.click();

  // Dos aserciones sobre la serie, y la SEGUNDA es la que discrimina.
  //
  // Que el máximo esté arriba de cero sólo prueba que algo se mueve: una onda
  // decorativa con números al azar también lo logra. Lo que una onda falsa NO
  // puede producir es la corrida de muestras cerca de cero del silencio que el
  // wav tiene a propósito entre las dos voces. Por eso el archivo se arma
  // voz → silencio → voz y la grabación dura menos que él.
  const pico = Math.max(...niveles);
  let corrida = 0;
  let mayorCorrida = 0;
  for (const n of niveles) {
    corrida = n <= SILENCIO_MAXIMO ? corrida + 1 : 0;
    if (corrida > mayorCorrida) mayorCorrida = corrida;
  }
  const serie = niveles.map((n) => n.toFixed(3)).join(' ');
  if (pico < VOZ_MINIMA) {
    failures++;
    console.error(`[GRABAR] ${nombre}: el pico de la onda fue ${pico.toFixed(3)} y el mínimo esperado es ${VOZ_MINIMA}: el AnalyserNode no está leyendo el micrófono. Serie: ${serie}`);
    return;
  }
  if (mayorCorrida < MUESTRAS_DE_SILENCIO) {
    failures++;
    console.error(`[GRABAR] ${nombre}: la corrida de silencio más larga fue de ${mayorCorrida} muestras y hacen falta ${MUESTRAS_DE_SILENCIO}: la onda da nivel incluso en el silencio del wav, o sea que no está midiendo audio real. Serie: ${serie}`);
    return;
  }
  if (!(await onda.isHidden())) {
    failures++;
    console.error(`[GRABAR] ${nombre}: después de parar la onda sigue visible: el bucle de dibujo o el AudioContext no se cerraron`);
    return;
  }

  // El POST y después la visita que morfea la pantalla. Se espera un `details`
  // MÁS que antes —la tarjeta nueva de la grabación—, que es una señal que sólo
  // puede existir con la pantalla nueva pintada.
  await page.waitForFunction(
    (n) => document.querySelectorAll('details summary').length > n,
    antes, { timeout: 30000 },
  ).catch(() => {});

  const tarjetas = await page.locator('details summary').count();
  if (tarjetas <= antes) {
    failures++;
    console.error(`[GRABAR] ${nombre}: después de parar hay ${tarjetas} plegables y antes había ${antes}: la grabación no llegó al servidor o el job no la transcribió`);
    return;
  }

  // Y que lo que apareció sea la transcripción del fixture y no «algo»: pedir
  // que no esté vacío no discrimina, porque esta guarda deja grabaciones en la
  // base y en la corrida siguiente ya hay tarjetas antes de tocar nada.
  const texto = await page.locator('.card-body').first().innerText();
  const esperado = 'barricas';
  if (!(await page.locator('details', { hasText: esperado }).count())) {
    failures++;
    console.error(`[GRABAR] ${nombre}: la tarjeta nueva no trae la transcripción del fixture (buscaba «${esperado}»); lo que hay dice «${texto.slice(0, 120)}»`);
    return;
  }

  recordingMeasurements++;
}
```

- [ ] **Paso 5: Llamarla en las dos caras**

Junto a cada `await revisarBorrador(...)` (líneas ~3305 y ~3356):

```javascript
      await revisarGrabacion(page, 'sala de idear');
```

```javascript
        await revisarGrabacion(page, 'sala de evolución');
```

**Va DESPUÉS de `revisarBorrador` en las dos.** La guarda del borrador tipea en
los campos y recarga; si la grabación corriera antes, su visita morfeante se
llevaría el texto tecleado y `[DRAFT]` fallaría por culpa de esta guarda.

- [ ] **Paso 6: Sumar el onceavo número y su piso**

En `script/capture_screens.js:3709`, al final del template de la línea:

```javascript
 · [GRABAR] ${recordingMeasurements} caras medidas
```

Y junto al chequeo de `PISO_DE_BORRADORES` (~línea 3722):

```javascript
  if (recordingMeasurements < PISO_DE_GRABACIONES) {
    failures++;
    console.error(`[GRABAR] sólo ${recordingMeasurements} de ${PISO_DE_GRABACIONES} caras de la sala midieron el viaje de la grabación: la guarda dejó de ver una`);
  }
```

- [ ] **Paso 7: Calibrar los umbrales de la onda contra lo medido**

**Los tres números no se adivinan: se miden.** Antes de dar la guarda por buena,
hacela imprimir la serie real. Poné temporalmente `VOZ_MINIMA = 99` para forzar
el fallo que imprime la serie:

```bash
make yarn-build
make screens 2>&1 | grep -A1 "el pico de la onda"
```

Leé la serie que sale y pinchá los tres umbrales con lo que viste:

- `VOZ_MINIMA`: bien abajo del pico real, no pegado. Si el pico mide 0,18,
  poner 0,02 deja margen para un `flite` que suene distinto en otra máquina.
- `SILENCIO_MAXIMO`: arriba de lo que marcan las muestras del hueco —que no van
  a ser 0 exacto, porque opus a 32 kbps mete algo de ruido— y bien abajo de la
  voz.
- `MUESTRAS_DE_SILENCIO`: contá cuántas muestras seguidas quedaron abajo de ese
  techo en el hueco, y pedí unas cuantas menos.

**Si el hueco NO aparece en la serie**, no toques los umbrales: o el wav quedó
mal armado (revisá el Paso 1), o la grabación de 6 s no alcanzó a cruzarlo, o la
onda no está leyendo el micrófono — que es el bug que esto existe para cazar.

Anotá los tres valores finales y de dónde salieron en un comentario al lado de
las constantes.

- [ ] **Paso 8: Correr el recorrido entero**

```bash
make yarn-build
make screens
```

Esperado: verde, y la última línea con **once** números, terminando en
`[GRABAR] 2 caras medidas`.

**El proveedor:** verificá antes que el stack NO tenga `FLOW_SPEECH_PROVIDER`
puesto, así la cascada cae al fixture y la corrida no factura. `FLOW_AI_PROVIDER`
es otra cosa y la decide quien corra —el handoff anterior lo dejó en
`anthropic`—:

```bash
docker compose exec app env | grep -E "FLOW_(AI|SPEECH)_PROVIDER"
```

- [ ] **Paso 9: Ver fallar la guarda, en cuatro mutaciones**

Una guarda que nunca se vio en rojo no prueba nada, y **el baseline tiene que
estar verde primero** o la mutación no discrimina. Tomá el backup **después**
del arreglo y restaurá con `cp`, nunca con `git checkout`:

```bash
cp script/capture_screens.js /tmp/bk_screens.js
cp app/javascript/workshop_recording.js /tmp/bk_rec.js
```

**Mutación A — el puente de la onda.** Borrá la línea que publica
`caja.dataset.level` en `dibujar()`:

**Ojo: la mutación que esta línea decía antes era IMPOSIBLE.** Pedía borrar
`impedimento()` esperando el botón fantasma en rojo, y el recorrido corre en
`localhost` con micrófono falso, así que `impedimento()` siempre devuelve null y
esa rama es inalcanzable — la spec ya declaraba que el fallo de contexto seguro
es invisible para este navegador, y el plan la contradecía. Lo que sí es
portante y sí se puede mutar es `data-level`, el único puente por el que la onda
se mide:

```bash
make yarn-build && make screens 2>&1 | grep GRABAR
cp /tmp/bk_rec.js app/javascript/workshop_recording.js && make yarn-build
```

Esperado: rojo. Si queda verde, la guarda no mira el botón escondido.

**Mutación B — el estado en el DOM.** En `start()`, sacá la prueba de
identidad (la rama `mismoNodo`; la Tarea 6 reemplazó el `encontrado === caja`
que esta línea nombraba antes):

```bash
make yarn-build && make screens 2>&1 | grep GRABAR
cp /tmp/bk_rec.js app/javascript/workshop_recording.js && make yarn-build
```

Esperado: rojo, al recablear el listener sobre el mismo nodo.

**Mutación C — la onda decorativa.** Es la más importante de las cuatro, porque
es el bug que nadie vería mirando la pantalla: una onda que se mueve lindo sin
leer el micrófono. En `nivel()`, reemplazá el cuerpo por `return Math.random() *
0.3;`:

```bash
make yarn-build && make screens 2>&1 | grep GRABAR
cp /tmp/bk_rec.js app/javascript/workshop_recording.js && make yarn-build
```

Esperado: rojo **por la corrida de silencio** y no por el pico —`Math.random()`
pasa la primera aserción de sobra—. El mensaje tiene que ser el de
«la corrida de silencio más larga fue de N muestras». Si falla por el pico, los
umbrales están mal calibrados.

**Mutación D — una cara deja de medirse.** Comentá la llamada de la sala de
evolución:

```bash
make screens 2>&1 | grep GRABAR
cp /tmp/bk_screens.js script/capture_screens.js
```

Esperado: `[GRABAR] sólo 1 de 2 caras`.

**Verificá la restauración grepeando lo ARREGLADO y no lo mutado** —lo mutado
ausente no distingue «restaurado» de «restaurado de más»—:

```bash
grep -c "encontrado === caja" app/javascript/workshop_recording.js   # 1
grep -c "impedimento()" app/javascript/workshop_recording.js          # 2
grep -c "getByteTimeDomainData" app/javascript/workshop_recording.js  # 1
grep -c "revisarGrabacion(page, 'sala de evolución')" script/capture_screens.js  # 1
make yarn-build && make screens
```

Esperado: verde otra vez, con `[GRABAR] 2`.

- [ ] **Paso 10: Commit**

```bash
git add script/capture_screens.js script/fake_audio.wav
git commit -m "La guarda [GRABAR] ve el viaje completo y el silencio de la onda, probada con cuatro mutaciones"
```

---

## Tarea 8: La documentación, y medir lo que quedó sin medir

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/superpowers/specs/2026-10-08-grabacion-de-la-mesa-design.md`
- Create: `handoff.md`

**Interfaces:** ninguna. Es la tarea que deja el repo contando la verdad.

- [ ] **Paso 1: Medir el español y la diarización con audio real**

**Esto lo tiene que producir Raúl, no se sintetiza.** Pedile veinte segundos de
audio de **dos personas hablando en español**, grabado en el teléfono, y
guardalo en `/tmp/real.m4a`. Después:

```bash
KEY=$(sed -nE 's/^DEEPGRAM_API_KEY=(.*)/\1/p' .env | tr -d '\r\n"'"'"'')
curl -sS -o /tmp/real.json -w "HTTP %{http_code}\n" \
  -X POST "https://api.deepgram.com/v1/listen?model=nova-3&diarize=true&utterances=true&punctuate=true&language=es" \
  -H "Authorization: Token $KEY" -H "Content-Type: audio/mp4" \
  --data-binary @/tmp/real.m4a
python3 -I -c "
import json
d=json.load(open('/tmp/real.json'))
for u in d['results'].get('utterances',[]):
    print(f\"speaker {u['speaker']} [{u['start']:.1f}-{u['end']:.1f}] {u['transcript']}\")
ws=d['results']['channels'][0]['alternatives'][0]['words']
print('hablantes:', sorted({w['speaker'] for w in ws}))
print('speaker_confidence min/max: %.3f / %.3f' % (
  min(w['speaker_confidence'] for w in ws), max(w['speaker_confidence'] for w in ws)))
"
```

Costo: ~0,0015 USD.

- [ ] **Paso 2: Escribir el resultado en la spec, gane o pierda**

En la sección «La diarización, sin verificar» de
`docs/superpowers/specs/2026-10-08-grabacion-de-la-mesa-design.md`, agregá un
bloque fechado con el número medido. **Si separó las voces**, decilo y cerrá el
riesgo 1. **Si no las separó**, decilo igual y anotá que C2 va a recibir
transcripciones de un solo hablante — es la información que decide si C2 vale la
pena como está diseñada. Lo mismo con el español: si la calidad es mala, va
escrito.

El formato, igual que los otros «Ojo» fechados del repo:

```markdown
**Ojo: medido el 2026-10-XX con audio real.** <qué pasó, con el número.>
```

- [ ] **Paso 3: Actualizar `CLAUDE.md`**

Tres cambios, y el tercero es el que más fácil se olvida:

1. En la sección del taller, donde dice que **siete** lugares preguntan
   `arrival?`, cambiarlo a **ocho** y sumar la grabación a la lista.
2. En «La capa de IA», sumar el tercer eje junto a «Hay DOS proveedores, no
   uno»: ahora son **tres**, con `FLOW_SPEECH_PROVIDER`, y Deepgram sólo
   transcribe igual que Voyage sólo vectoriza.
3. En «Verificación», donde dice que **diez** de las guardas cuentan cuánto
   midieron y que «la corrida imprime los diez números en una sola línea»:
   ahora son **once**, y el piso nuevo es 2 y **exacto**, al lado de `[DRAFT]`
   y por el mismo motivo. Sumar `[GRABAR]` a la lista de pisos.

Y una sección nueva con lo que no se lee del código:

```markdown
**La grabación de la mesa se aparta de sus dos hermanos de JS a propósito.**
`arrival_live.js` para en `turbo:before-render` y `workshop_draft.js` descarga
ahí mismo; `workshop_recording.js` **no hace ninguna de las dos**, porque ese
evento dispara también en un morph y un morph ocurre con cualquier POST a la
misma URL —alguien apretando «Crear borrador» cortaría la reunión—. Lo que lo
permite es que el `MediaRecorder` y los trozos sean variables de MÓDULO: el DOM
es una vista del estado y `turbo:load` lo vuelve a derivar. Si alguien
«arregla» esto copiando a los hermanos, corta grabaciones y ninguna suite se
entera: lo caza `[GRABAR]`.

**Y el riesgo de despliegue que ninguna guarda puede ver:** `getUserMedia` no
existe fuera de un contexto seguro, y `docker-compose` publica el puerto en
plano. Desde la máquina que corre Docker es `localhost` y anda; desde un
teléfono por `http://<ip>:3001`, `navigator.mediaDevices` es `undefined` y no
hay grabación. La pantalla lo detecta y lo dice en vez de dejar un botón
mudo. **`make screens` corre en `localhost`, que es contexto seguro SIEMPRE**,
así que ninguna corrida verde dice nada sobre esto.

**La línea de sonido va en barras del DOM y NUNCA en un `<canvas>`.** No hay un
solo canvas en el repo, y el motivo de que siga así es que un canvas es una caja
negra para todas las guardas —`[CLASES]`, `[CONTRASTE]` y `[SOMBRA]` no ven
adentro— y una guarda que no puede ver **da permiso**. Con barras, el color sale
de `--dato` por la hoja (tinta de DATOS y no el acento: una barra con el violeta
del botón de al lado se lee como un control) y las alturas quedan en el DOM. Las
40 barras nacen en el MARKUP y el JS sólo toca `height`: así Tailwind ve las
clases y un morph que borre los `style` en línea se arregla en el frame
siguiente.

**Lo que hace medible a la onda es `data-level`, y sin eso no habría forma.** El
bucle publica ahí el RMS crudo, y `[GRABAR]` lo muestrea cada 100ms para exigir
dos cosas: un pico durante la voz, **y una corrida de muestras cerca de cero**.
La segunda es la única que discrimina —una onda decorativa con `Math.random()`
pasa la del pico de sobra—, y por eso `script/fake_audio.wav` está armado
voz → SILENCIO → voz y la guarda graba menos que su duración. Si alguien
«simplifica» ese wav a una sola voz corrida, la guarda queda midiendo que algo
se mueve y nada más.

**La onda sigue moviéndose con `prefers-reduced-motion` activado**, y es la misma
decisión que ya está tomada para el spinner de la IA, con el mismo motivo: es la
ÚNICA señal de que el micrófono está tomando algo, y quieta se lee como un
micrófono tapado — que es justo el estado que tiene que poder distinguir.

**Y una navegación en medio de la grabación PIERDE el audio.** No hay despedida
posible: `keepalive` tiene un tope de 64 KB por especificación y el audio son
megabytes, así que el truco que usa el autoguardado del borrador acá no sirve.
Lo único que se hace es avisar con un `beforeunload` mientras graba. Si alguien
lo saca por «limpieza», se pierden reuniones en silencio.
```

- [ ] **Paso 4: Correr todo una última vez**

```bash
make spec
make yarn-build
make screens
```

Esperado: suite en 0 fallas y recorrido verde con `[GRABAR] 2`.

- [ ] **Paso 5: Escribir el handoff**

`handoff.md` con las cinco secciones de siempre —objetivo, estado actual,
archivos y cambios, intentos fallidos, próximos pasos—, **incluidos los intentos
que no funcionaron**. Lo que tiene que estar y es lo que más cuesta
reconstruir:

- Los números medidos: el contrato de Deepgram, los tamaños, el bitrate real de
  Chromium, el resultado del audio real del Paso 1.
- Qué mutación puso en rojo a qué, de las tres de la Tarea 7.
- Que el stack queda con `FLOW_AI_PROVIDER` en lo que estuviera y
  `FLOW_SPEECH_PROVIDER` **sin declarar**, así que `make screens` no factura.
- Que **C2 y C3 siguen pendientes**, y que C2 ahora sabe si puede contar con
  hablantes separados o no.

- [ ] **Paso 6: Commit**

```bash
git add CLAUDE.md docs/superpowers/specs/2026-10-08-grabacion-de-la-mesa-design.md handoff.md
git commit -m "Los documentos cuentan el tercer eje, el octavo arrival? y el onceavo contador"
```

---

## Verificación final de la rama

- [ ] `make spec` en 0 fallas
- [ ] `make yarn-build` corrido después del último cambio a `app/javascript/`
- [ ] `make screens` verde, con once números y `[GRABAR] 2`
- [ ] `db/structure.sql` commiteado
- [ ] Los tres umbrales de la onda **calibrados contra la serie medida**, con el
      comentario que dice de dónde salieron
- [ ] Las cuatro mutaciones de la Tarea 7 vistas en rojo y restauradas, con el
      `grep -c` de lo ARREGLADO — y la de `Math.random()` fallando **por la
      corrida de silencio** y no por el pico
- [ ] `waveform__bar` presente en la hoja compilada, no sólo en el fuente
- [ ] `CLAUDE.md` dice ocho `arrival?`, tres ejes y once contadores
- [ ] El resultado del audio real está escrito en la spec, gane o pierda
- [ ] `FLOW_SPEECH_PROVIDER` sigue **sin declarar** en `.env`
