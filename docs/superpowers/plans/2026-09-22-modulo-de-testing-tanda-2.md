# Módulo de testing · Tanda 2 — la IA y el filtro

> **Para quien ejecute esto:** SUB-SKILL REQUERIDA: usá
> `superpowers:subagent-driven-development` (recomendado) o
> `superpowers:executing-plans` para implementar tarea por tarea. Los pasos
> usan checkbox (`- [ ]`).

**Objetivo:** que el módulo de testing corra en los tres modos de IA, y que
una selección posterior pueda consumir el veredicto como filtro.

**Arquitectura:** una tarea de IA más (`Tasks::TestIdea`) que se aplica
llamando al `testear!` que ya existe; el `on_activate` que en modo automático
encola una corrida por idea; y un check automático más
(`Checks::TestingPassed`) que resuelve «el testeo» como el vigente del módulo
de testing más reciente que probó esa idea.

**Stack:** Rails 7.1 · Postgres (`schema_format = :sql`) · HAML · RSpec ·
Docker (`make spec`, `make screens`).

**Spec:** `docs/superpowers/specs/2026-09-21-modulo-de-testing-design.md`,
§5 y §6.

**La tanda 1 ya está mergeada** (`00b5abc` y `0fdad72`). Existen el kind
`testing`, la tabla `step_tests`, el modelo, `Flow::Handlers::Testing` con
`#testear!`, `#vigente_para`, `#dimensions`, `#min_situations`, `#severity`,
las dos caras de pantalla y la pantalla del testeo por idea.

## Restricciones globales

- **Todo en español**: código, comentarios y mensajes de commit.
- **Los commits NO llevan línea `Co-Authored-By`** ni ninguna otra atribución.
- **Todo corre en Docker. Nunca `bundle exec` en el host.** Los specs con
  `make spec` / `make spec-file FILE=…` / `make spec-line FILE=… LINE=…`. Un
  `docker compose exec app bundle exec rspec` corre en **desarrollo** y
  devuelve 403 «Blocked hosts» en todos los request specs.
- **`make rails ARGS="…"` NO funciona**: el target abre una consola y descarta
  `ARGS`. Los targets reales son `make migrate`, `make seed`,
  `make db-prepare-test`, `make spec`, `make spec-file`, `make screens`,
  `make yarn-build`.
- **Nunca un worktree.** `docker-compose.yml` monta `.` en `/rails`.
- **Migraciones:** `schema_format = :sql`. Después de migrar, commitear
  `db/structure.sql`.
- **Tenencia en los specs:** toda lectura del dominio va dentro de
  `as_company(company) { … }`, incluido un `.new`.
- **TDD**: el test primero, verlo fallar, el mínimo para pasarlo, verlo pasar,
  commit.
- **`FLOW_AI_PROVIDER=fixture` es el default** y es lo que corre en los specs y
  en `make screens`. El adapter real cuesta plata: nunca es el default.

## Decisiones ya tomadas, que no se re-discuten

1. **El fixture es estático.** Un `default.json` con las cinco dimensiones por
   defecto y tres situaciones. Contra un módulo que estreche las dimensiones o
   suba `min_situations` va a fallar la validación del schema y el run va a
   quedar en error explicado — igual que hoy `evaluate_idea` contra criterios
   que no son los sembrados. Es aceptado a propósito: la alternativa era
   maquinaria nueva en el proveedor para una sola tarea.
2. **No hay botón de lote «testear todas con IA».** La IA testea en lote sólo
   en modo automático, desde `on_activate`. Es coherente con
   `applies_on_request? = false`: cada propuesta hay que revisarla, así que un
   lote de veinte deja veinte propuestas pendientes en el panel. Es lo que hace
   `Selection#request_ai_verdicts!`, y **no** lo que hace evaluación, que sí
   tiene `evaluate_all` porque su tarea es aditiva.
3. **El botón de pedir a la IA va en su propia tarjeta, FUERA del
   `form_with`.** Un `button_to` es un `<form>`, y uno dentro de otro lo aplana
   el parser: el botón interno pasa a pertenecer al formulario externo. Es el
   precedente exacto de `app/views/assessments/new.html.haml`, donde el
   `button_to` de la línea 78 está a cuatro espacios y el `form_with` de la 32
   a ocho — hermanos, no anidados.

## Lo que el riesgo nº2 de la spec da por mitigado y no lo está

La spec §Riesgos nº2 dice que el prompt «puede seguir siendo demasiado duro
aun con el contrapeso» y que **«se mide con el fixture primero»**. Eso es
falso: el fixture resuelve por hash del prompt a un archivo y **devuelve un
payload fijo sin leer el prompt**. La dureza del prompt sólo se puede medir
con el proveedor real, y cada llamada cuesta plata.

No se arregla en esta tanda. Se deja escrito para que nadie crea que la
corrida del fixture dice algo sobre el prompt.

## Estructura de archivos

| Archivo | Responsabilidad |
|---|---|
| `db/migrate/20260922120000_add_test_idea_purpose.rb` | El CHECK de `ai_runs.purpose` |
| `app/models/ai_run.rb` | +1 en `PURPOSES` |
| `app/lib/flow/ai/tasks/test_idea.rb` | Qué se le pide al modelo y cómo se aplica |
| `spec/fixtures/ai/test_idea/default.json` | La respuesta determinista |
| `app/lib/flow/handlers/testing.rb` | `on_activate` y `request_ai_tests!` |
| `app/views/steps/testing.html.haml` | El botón de IA por fila |
| `app/views/step_tests/new.html.haml` | El botón de IA en su propia tarjeta |
| `app/lib/flow/checks/testing_passed.rb` | El filtro que consume el veredicto |
| `app/lib/flow/checks/base.rb` | +1 en `TYPES` |
| `app/lib/flow/criterion_settings.rb` | +1 entrada en `CHECKS` |
| `config/locales/es.yml` | El rótulo del check |
| `db/seeds.rb` | Un desafío con testing → selección filtrando |
| `script/capture_screens.js` | Las capturas nuevas |

---

### Task 1: El propósito nuevo, en sus dos puertas

**Archivos:**
- Crear: `db/migrate/20260922120000_add_test_idea_purpose.rb`
- Modificar: `app/models/ai_run.rb:8-13`
- Crear: `spec/models/ai_run_purpose_spec.rb`
- Commitear: `db/structure.sql`

**Interfaces:**
- Produce: `AiRun` acepta `purpose: "test_idea"`, y el CHECK de Postgres
  también.

**Por qué las dos juntas en una tarea:** sumar una tarea de IA es tocar la
clase, `AiRun::PURPOSES` y el CHECK de Postgres. Si el CHECK va en una tarea
aparte, el run revienta con `PG::CheckViolation` **antes de crearse** y el
error llega truncado. La clase va en la Task 2; estas dos van juntas porque
una sin la otra deja el modelo mintiendo.

- [ ] **Paso 1: escribir el spec**

`spec/models/ai_run_purpose_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# El propósito vive en el modelo Y en un CHECK de Postgres. El spec prueba los
# dos: la validación de Rails con un `valid?`, y el CHECK saltándose la
# validación, porque es la única forma de ver si la base lo acepta.
RSpec.describe AiRun do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:challenge) { create(:challenge) }

  it "acepta el propósito test_idea" do
    run = described_class.new(challenge: challenge, purpose: "test_idea",
                              mode: "ai_assisted", status: "queued")

    expect(run).to be_valid
  end

  it "la base también lo acepta, no sólo la validación" do
    run = described_class.new(challenge: challenge, purpose: "test_idea",
                              mode: "ai_assisted", status: "queued")

    expect { run.save!(validate: false) }.not_to raise_error
  end
end
```

- [ ] **Paso 2: verlo fallar**

Correr: `make spec-file FILE=spec/models/ai_run_purpose_spec.rb`
Esperado: FALLA. El primero por la validación de inclusión; el segundo con
`PG::CheckViolation` sobre `ai_runs_purpose_check`.

**Si el segundo pasa y el primero no**, el CHECK no existe o no lista los
propósitos: andá a mirar `db/structure.sql` antes de seguir.

- [ ] **Paso 3: la migración**

`db/migrate/20260922120000_add_test_idea_purpose.rb`:

```ruby
# frozen_string_literal: true

# Sumar una tarea de IA es tocar TRES lugares: la clase, `AiRun::PURPOSES` y
# este CHECK. Sin el CHECK el run revienta con `PG::CheckViolation` antes de
# crearse, y el error llega truncado hasta la pantalla.
class AddTestIdeaPurpose < ActiveRecord::Migration[7.1]
  PURPOSES = %w[
    propose_pipeline suggest_form_fields suggest_criteria generate_ideas
    coauthor_field detect_duplicates suggest_feedback evaluate_idea
    decide_verdicts evolve_idea summarize_challenge test_idea
  ].freeze

  def up = reemplazar_check(PURPOSES)
  def down = reemplazar_check(PURPOSES - ["test_idea"])

  private

  def reemplazar_check(purposes)
    lista = purposes.map { |p| connection.quote(p) }.join(", ")
    execute "ALTER TABLE ai_runs DROP CONSTRAINT ai_runs_purpose_check"
    execute "ALTER TABLE ai_runs ADD CONSTRAINT ai_runs_purpose_check CHECK (purpose IN (#{lista}))"
  end
end
```

- [ ] **Paso 4: el modelo**

En `app/models/ai_run.rb`, sumar `test_idea` a `PURPOSES`:

```ruby
  PURPOSES = %w[
    suggest_criteria
    propose_pipeline suggest_form_fields generate_ideas coauthor_field
    detect_duplicates suggest_feedback evaluate_idea decide_verdicts evolve_idea
    summarize_challenge test_idea
  ].freeze
```

- [ ] **Paso 5: migrar y ver pasar**

```bash
make migrate
make db-prepare-test
make spec-file FILE=spec/models/ai_run_purpose_spec.rb
```

Esperado: 2 ejemplos, 0 fallas.

- [ ] **Paso 6: commit**

```bash
git add db/migrate/20260922120000_add_test_idea_purpose.rb db/structure.sql \
        app/models/ai_run.rb spec/models/ai_run_purpose_spec.rb
git commit -m "El propósito test_idea, en el modelo y en el CHECK

Las dos puertas juntas: con una sola, el run revienta con
PG::CheckViolation antes de crearse y el error llega truncado."
```

---

### Task 2: La tarea de IA y su fixture

**Archivos:**
- Crear: `app/lib/flow/ai/tasks/test_idea.rb`
- Crear: `spec/fixtures/ai/test_idea/default.json`
- Crear: `spec/lib/flow/ai/tasks/test_idea_spec.rb`

**Interfaces:**
- Consume: `Flow::Handlers::Testing#testear!`, `#dimensions`,
  `#min_situations`, `#severity` (tanda 1). `AiRun::PURPOSES` de la Task 1.
- Produce: `Flow::AI::Tasks::TestIdea`, que `Tasks::Base.for("test_idea",
  challenge:, step:, idea:)` encuentra sola por `camelize`. **No hay que tocar
  el despacho.**

- [ ] **Paso 1: escribir el spec**

`spec/lib/flow/ai/tasks/test_idea_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flow::AI::Tasks::TestIdea do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:challenge) { create(:challenge) }
  let!(:ideation) { seed_form!(challenge.steps.create!(kind: "ideation", position: 1)) }

  let!(:idea) do
    i = create(:idea, challenge: challenge, status: "active")
    Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Bicis eléctricas" }).call
    i.update!(submitted_at: Time.current)
    i.reload
  end

  def paso(config = {})
    step = challenge.steps.create!(kind: "testing", position: 2,
                                   name: "Prueba de factibilidad", config: config)
    challenge.update!(status: "running")
    Flow::Handlers::Base.for(step).activate!
    step.reload
  end

  def tarea(step) = described_class.new(challenge: challenge, step: step, idea: idea)

  it "actúa sobre el desafío, no sobre la idea" do
    expect(described_class.actua_sobre).to eq(:challenge)
  end

  # Pedirla NO la aplica: el veredicto es LA respuesta del módulo para esa
  # idea y habilita un filtro después. Es el criterio de `decide_verdicts`,
  # no el de `evaluate_idea`.
  it "se propone y alguien la acepta; no se aplica al pedirla" do
    expect(tarea(paso).applies_on_request?).to be(false)
  end

  # La lección de EvaluateIdea: aceptar una propuesta admitiendo un payload
  # editado dejaba a una persona poniendo su veredicto con el nombre de la IA
  # encima.
  it "no se edita antes de aceptarla" do
    expect(tarea(paso).editable?).to be(false)
  end

  it "produce algo que se aplica, así que no es informativa" do
    expect(tarea(paso).informativa?).to be(false)
  end

  describe "#schema" do
    it "las dimensiones van como enum de las que el módulo configuró" do
      step = paso("dimensions" => %w[tecnica legal])
      dimension = tarea(step).schema.dig("properties", "situaciones", "items",
                                         "properties", "dimension")

      expect(dimension["enum"]).to eq(%w[tecnica legal])
    end

    it "el mínimo de situaciones sale de la configuración" do
      step = paso("min_situations" => 4)

      expect(tarea(step).schema.dig("properties", "situaciones", "minItems")).to eq(4)
    end

    # La API poda `minItems` y `minimum`, así que el mínimo tiene que estar
    # ADEMÁS en la descripción: es lo único que el modelo ve.
    it "el mínimo se repite en la descripción, porque la API poda minItems" do
      step = paso("min_situations" => 4)
      descripcion = tarea(step).schema.dig("properties", "situaciones", "description")

      expect(descripcion).to include("4")
    end
  end

  describe "#messages" do
    it "el rigor va en las situaciones y el veredicto lo dicta lo encontrado" do
      system = tarea(paso).messages.first[:content]

      expect(system).to include("no_factible")
      expect(system).to match(/con_reservas/)
    end

    it "la severidad configurada llega al prompt" do
      system = tarea(paso("severity" => "estandar")).messages.first[:content]

      expect(system).to include("estandar").or include("previsible")
    end
  end

  describe "#apply!" do
    let(:payload) do
      { "veredicto" => "con_reservas",
        "resumen" => "Aguanta el día normal, no el pico",
        "reservas" => ["Conseguir un segundo proveedor"],
        "situaciones" => [
          { "dimension" => "operativa", "escenario" => "Viernes 18h, 400 pedidos",
            "resultado" => "se_rompe", "detalle" => "El turno de tarde satura" }
        ] }
    end

    it "deja el testeo vigente a nombre de la IA, con su run" do
      step = paso
      run = AiRun.create!(challenge: challenge, purpose: "test_idea",
                          mode: "ai_assisted", status: "succeeded")
      sugerencia = AiSuggestion.create!(ai_run: run, challenge: challenge, idea: idea,
                                        payload: payload, status: "pending")

      ok, errores = tarea(step).apply!(payload, suggestion: sugerencia)

      expect([ok, errores]).to eq([true, []])
      test = step.handler.vigente_para(idea.id)
      expect(test.verdict).to eq("con_reservas")
      expect(test.actor_type).to eq("ai")
      expect(test.tested_by_id).to be_nil
      expect(test.ai_run_id).to eq(run.id)
      expect(test.reservations).to eq(["Conseguir un segundo proveedor"])
    end
  end

  it "el preview dice el veredicto y por dónde se rompe" do
    payload = { "veredicto" => "no_factible", "resumen" => "No da",
                "reservas" => [],
                "situaciones" => [{ "dimension" => "tecnica", "escenario" => "Pico de carga",
                                    "resultado" => "se_rompe", "detalle" => "Se cae" }] }

    expect(tarea(paso).preview(payload)).to include("Pico de carga")
  end
end
```

- [ ] **Paso 2: verlo fallar**

Correr: `make spec-file FILE=spec/lib/flow/ai/tasks/test_idea_spec.rb`
Esperado: FALLA con `NameError: uninitialized constant Flow::AI::Tasks::TestIdea`.

- [ ] **Paso 3: la tarea**

`app/lib/flow/ai/tasks/test_idea.rb`:

```ruby
# frozen_string_literal: true

module Flow
  module AI
    module Tasks
      # La IA pone una idea a prueba contra situaciones concretas de ejecución
      # y dictamina si es factible.
      #
      # El rigor va en las SITUACIONES, no en el veredicto. Una IA crítica por
      # mandato dice «no factible» a casi todo; el filtro de la selección lo
      # consume y el desafío se queda sin finalistas. Por eso el prompt pide
      # buscar dónde se rompe, y al mismo tiempo ata el veredicto a lo que
      # encontró: `no_factible` sólo con una situación rota y un detalle
      # concreto, y si lo roto es arreglable, `con_reservas` con la condición
      # en `reservas`.
      class TestIdea < Base
        # Testear es de quien administra el desafío. Quien participa no testea
        # ni pide el testeo de su idea: con un solo testeo vigente donde el
        # último manda, pedirlo sería re-tirar el dado hasta que salga
        # «factible».
        def self.actua_sobre = :challenge

        def messages
          [
            { role: "system", content: <<~TXT.squish },
              Ponés una idea a prueba contra situaciones concretas de ejecución para decidir si
              es factible. Planteá situaciones donde la idea YA esté funcionando —un día puntual,
              un volumen, una persona que falta, un proveedor caído— y probá dónde se rompe.
              #{instruccion_de_severidad}
              El veredicto lo dicta lo que encontraste, no la actitud: poné no_factible sólo si
              al menos una situación se rompe y podés decir con qué detalle concreto; si lo que
              se rompe es arreglable, el veredicto es con_reservas y la condición a resolver va
              en reservas. Si nada se rompe, es factible. Una reserva es una condición a
              resolver, no una situación que falló.
            TXT
            { role: "user", content: <<~TXT }
              Desafío: #{challenge.name}
              Brief: #{challenge.brief}

              Idea: #{idea.title}
              #{idea.payload.map { |k, v| "#{k}: #{v}" }.join("\n")}

              Dimensiones que hay que cubrir: #{dimensiones.join(', ')}
              Mínimo de situaciones: #{handler.min_situations}
            TXT
          ]
        end

        def schema
          {
            "type" => "object",
            "required" => %w[situaciones veredicto reservas resumen],
            "properties" => {
              "situaciones" => {
                "type" => "array",
                "minItems" => handler.min_situations,
                # El mínimo se repite acá porque la API poda `minItems`: la
                # descripción es lo único que el modelo ve.
                "description" => "Al menos #{handler.min_situations} situaciones concretas de " \
                                 "la idea en ejecución.",
                "items" => {
                  "type" => "object",
                  "required" => %w[dimension escenario resultado detalle],
                  "properties" => {
                    # Enum con las dimensiones del módulo: el modelo no puede
                    # señalar una que nadie declaró.
                    "dimension" => { "type" => "string", "enum" => dimensiones },
                    "escenario" => { "type" => "string" },
                    "resultado" => { "type" => "string", "enum" => %w[aguanta se_rompe] },
                    "detalle" => { "type" => "string" }
                  }
                }
              },
              "veredicto" => { "type" => "string", "enum" => StepTest::VERDICTS },
              "reservas" => { "type" => "array", "items" => { "type" => "string" } },
              "resumen" => { "type" => "string" }
            }
          }
        end

        def target_attributes = { idea: idea }

        # Un veredicto de testeo es LA respuesta del módulo para esa idea y
        # habilita un filtro después: se propone y alguien lo acepta. Es el
        # criterio de `decide_verdicts`, no el de `evaluate_idea`.
        def applies_on_request? = false

        # Editado, un veredicto de la IA deja de serlo y sigue diciendo que lo
        # es. Es la lección de `EvaluateIdea`.
        def editable? = false

        def apply!(payload, suggestion:)
          handler.testear!(
            idea: idea,
            verdict: payload["veredicto"],
            situations: payload["situaciones"],
            reservations: Array(payload["reservas"]),
            summary: payload["resumen"],
            tested_by: nil,
            ai_run_id: suggestion.ai_run_id
          )

          [true, []]
        end

        def preview(payload)
          rotas = Array(payload["situaciones"]).select { _1["resultado"] == "se_rompe" }
          detalle = rotas.any? ? rotas.map { _1["escenario"] }.join(" · ") : "nada se rompió"

          "#{I18n.t("flow.verdicts.#{payload['veredicto']}")} — #{detalle}"
        end

        private

        def handler = step.handler
        def dimensiones = handler.dimensions

        def instruccion_de_severidad
          return "Probá lo previsible: las situaciones que la idea va a encontrar seguro." if
            handler.severity == "estandar"

          "Buscá activamente dónde se rompe: elegí las situaciones más exigentes que sean realistas."
        end
      end
    end
  end
end
```

- [ ] **Paso 4: el fixture**

`spec/fixtures/ai/test_idea/default.json`:

```json
{
  "situaciones": [
    { "dimension": "operativa",
      "escenario": "Viernes de lluvia con 40 entregas en la franja de la tarde",
      "resultado": "se_rompe",
      "detalle": "Con lluvia la ventana de entrega se estira unos 25 minutos y el turno no alcanza a cerrar el reparto." },
    { "dimension": "economica",
      "escenario": "Con el costo actual por entrega y el volumen de un mes normal",
      "resultado": "aguanta",
      "detalle": "La inversión se paga en unos 14 meses, dentro de lo que el área ya aprueba sin comité." },
    { "dimension": "tecnica",
      "escenario": "Carga de baterías entre el turno de la mañana y el de la tarde",
      "resultado": "aguanta",
      "detalle": "Dos horas de carga alcanzan para el segundo turno completo." }
  ],
  "veredicto": "con_reservas",
  "reservas": [
    "Definir el protocolo para los días de lluvia antes de comprometer la ventana de entrega"
  ],
  "resumen": "Funciona en el día normal y se paga en plazo razonable; el problema es la lluvia, y hace falta un plan para esos días antes de prometer la ventana."
}
```

**El fixture es estático a propósito** (decisión 1). Trae tres situaciones
sobre tres de las cinco dimensiones por defecto, así que valida contra un
módulo con la configuración por defecto (`min_situations: 3`, las cinco
dimensiones). Contra un módulo que estreche las dimensiones o suba el mínimo,
el proveedor devuelve «la respuesta no valida contra el schema» y el run queda
en error explicado.

- [ ] **Paso 5: verlo pasar**

Correr: `make spec-file FILE=spec/lib/flow/ai/tasks/test_idea_spec.rb`
Esperado: 11 ejemplos, 0 fallas.

- [ ] **Paso 6: el spec de fixtures**

Correr: `make spec-file FILE=spec/lib/flow/ai/fixtures_spec.rb`

Ese spec valida **cada fixture contra su schema**: es la guarda que atrapó el
`cut_mode` plano que nadie leía. Si falla, leé qué clave reporta antes de
tocar el fixture — puede ser que el schema esté mal, no el JSON.

**Ojo:** ese spec tiene que armar la tarea para conocer su schema, y `TestIdea`
necesita `challenge:`, `step:` e `idea:`. Mirá cómo resuelve el contexto de
`decide_verdicts`, que también los necesita, y seguí esa forma.

- [ ] **Paso 7: la suite entera y commit**

```bash
make spec
git add app/lib/flow/ai/tasks/test_idea.rb spec/fixtures/ai/test_idea/default.json \
        spec/lib/flow/ai/tasks/test_idea_spec.rb
git commit -m "La tarea de IA que testea una idea

El rigor va en las situaciones y no en el veredicto: no_factible sólo con
una situación rota y un detalle concreto, y si lo roto es arreglable,
con_reservas con la condición en reservas. Sin ese contrapeso una IA
crítica por mandato vacía el pool.

No se aplica al pedirla ni se edita antes de aceptarla: el veredicto es LA
respuesta del módulo para esa idea."
```

---

### Task 3: Los tres modos

**Archivos:**
- Modificar: `app/lib/flow/handlers/testing.rb`
- Modificar: `spec/lib/flow/handlers/testing_spec.rb`

**Interfaces:**
- Consume: `Flow::AI::Tasks::TestIdea` de la Task 2.
- Produce: `Flow::Handlers::Testing#on_activate`, que en `ai_auto` encola una
  corrida por idea.

**No hay botón de lote** (decisión 2). En `ai_assisted` se pide de a una,
desde la pantalla (Task 4).

- [ ] **Paso 1: escribir el test**

En `spec/lib/flow/handlers/testing_spec.rb`, junto a los que ya están:

```ruby
  describe "los modos de IA al arrancar" do
    # Nunca un fan-out síncrono en el request: una corrida por idea, encolada.
    it "en automático encola un testeo por idea" do
      expect do
        armar_con_modo("ai_auto")
      end.to have_enqueued_job(Flow::AI::RunJob).exactly(2).times
    end

    # En asistido no se dispara solo: el veredicto se propone y alguien lo
    # acepta, así que arrancar el módulo no puede dejar dos propuestas
    # esperando sin que nadie las haya pedido.
    it "en asistido no encola nada" do
      expect { armar_con_modo("ai_assisted") }.not_to have_enqueued_job(Flow::AI::RunJob)
    end

    it "en «solo personas» tampoco" do
      expect { armar_con_modo("human") }.not_to have_enqueued_job(Flow::AI::RunJob)
    end
  end
```

Y el helper, junto a `armar`:

```ruby
  def armar_con_modo(modo)
    step = challenge.steps.create!(kind: "testing", position: 2,
                                   name: "Prueba de factibilidad", ai_mode: modo)
    challenge.update!(status: "running")
    Flow::Handlers::Base.for(step).activate!
    described_class.new(step.reload)
  end
```

**Si `have_enqueued_job` no está disponible**, mirá cómo lo prueban los specs
de selección y evaluación, que ya ejercitan el mismo `RunJob`, y seguí esa
forma. No inventes un doble.

- [ ] **Paso 2: verlo fallar**

Correr: `make spec-file FILE=spec/lib/flow/handlers/testing_spec.rb`
Esperado: FALLA — el primero encola 0 en vez de 2, porque `Testing` todavía no
define `on_activate`.

- [ ] **Paso 3: el `on_activate`**

En `app/lib/flow/handlers/testing.rb`, en la sección `protected`, junto a
`on_complete`:

```ruby
      def on_activate
        request_ai_tests! if effective_ai_mode == "ai_auto"
      end

      # En modo automático la IA testea todas las ideas al arrancar. Una
      # corrida por idea y encolada: nunca un fan-out síncrono en el request.
      #
      # En `ai_assisted` NO se dispara sola. Un veredicto de testeo es la
      # respuesta del módulo para esa idea y habilita un filtro después, así
      # que se propone y alguien la acepta — y un lote de propuestas
      # pendientes que nadie pidió no es una ayuda. Es lo que hace
      # `Selection#request_ai_verdicts!`, y no lo que hace evaluación, cuya
      # tarea es aditiva.
      def request_ai_tests!
        step.step_entries.each do |entry|
          Flow::AI::RunJob.perform_later(
            step.company_id, "test_idea",
            { "step_id" => step.id, "idea_id" => entry.idea_id }
          )
        end
      end
```

- [ ] **Paso 4: verlo pasar**

```bash
make spec-file FILE=spec/lib/flow/handlers/testing_spec.rb
make spec
```
Esperado: 0 fallas en los dos.

- [ ] **Paso 5: commit**

```bash
git add app/lib/flow/handlers/testing.rb spec/lib/flow/handlers/testing_spec.rb
git commit -m "Los tres modos de IA del módulo de testing

En automático, una corrida por idea encolada al arrancar. En asistido no
se dispara sola: el veredicto se propone y alguien lo acepta, así que
arrancar el módulo no puede dejar propuestas esperando que nadie pidió."
```

---

### Task 4: Pedirle a la IA que testee, desde las dos pantallas

**Archivos:**
- Modificar: `app/views/steps/testing.html.haml`
- Modificar: `app/views/step_tests/new.html.haml`
- Crear: `spec/requests/testing_ia_spec.rb`

**Interfaces:**
- Consume: la tarea de la Task 2, servida por
  `challenge_ai_requests_path(challenge, purpose: "test_idea", step_id:, idea_id:)`,
  que ya existe y no hay que crear.

- [ ] **Paso 1: escribir el request spec**

`spec/requests/testing_ia_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "pedirle a la IA que testee", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  let!(:admin) do
    without_tenant do
      u = create(:user, email: "admin@test.dev", name: "Ana Admin")
      create(:membership, :admin, company: company, user: u)
      u
    end
  end

  let!(:paula) do
    without_tenant do
      u = create(:user, email: "paula@test.dev", name: "Paula Participante")
      create(:membership, company: company, user: u, role: "participant")
      u
    end
  end

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Reparto", ai_default_mode: "ai_assisted")
      seed_form!(c.steps.create!(kind: "ideation", position: 1))
      c.steps.create!(kind: "testing", position: 2, name: "Prueba de factibilidad")
      c
    end
  end

  let!(:idea) do
    as_company(company) do
      i = create(:idea, challenge: challenge, author: paula, status: "active")
      Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Bicis" }, author: paula).call
      i.update!(submitted_at: Time.current)
      i
    end
  end

  def paso
    as_company(company) do
      p = challenge.steps.reload.find(&:testing?)
      Flow::Handlers::Base.for(p).activate! unless p.touched?
      p.reload
    end
  end

  it "quien administra ve el botón en la fila de la idea" do
    sign_in(admin, company: company)
    get challenge_step_path(challenge, paso)

    expect(response.body).to include("test_idea")
  end

  # Quien participa no testea ni PIDE el testeo de su idea: con un solo
  # vigente donde el último manda, pedirlo sería re-tirar el dado hasta que
  # salga «factible». Es la decisión 2.5 del spec de diseño.
  it "a quien participa no se le ofrece, ni sobre su propia idea" do
    sign_in(paula, company: company)
    get challenge_step_path(challenge, paso)

    expect(response.body).not_to include("test_idea")
  end

  it "y si lo postea igual, se lo rebota" do
    sign_in(paula, company: company)
    post challenge_ai_requests_path(challenge, purpose: "test_idea",
                                    step_id: paso.id, idea_id: idea.id)

    expect(response).to have_http_status(:forbidden)
  end

  # `button_to` es un <form>, y uno dentro de otro es HTML inválido: el
  # navegador descarta el interno y sus botones pasan a pertenecer al
  # externo. No se ve en el DOM ni en un request spec que postea directo: se
  # mira el HTML SERVIDO.
  it "el botón de la pantalla del testeo no queda dentro del formulario" do
    sign_in(admin, company: company)
    get new_challenge_step_step_test_path(challenge, paso, idea_id: idea.id)

    formularios = Nokogiri::HTML(response.body).css("form")
    expect(formularios.map { |f| f.css("form").size }).to all(eq(0))
  end
end
```

- [ ] **Paso 2: verlo fallar**

Correr: `make spec-file FILE=spec/requests/testing_ia_spec.rb`
Esperado: FALLA — los dos primeros, porque ninguna vista menciona `test_idea`
todavía. El de los formularios anidados **puede pasar desde el principio**: es
una guarda de regresión, no un RED. Para darlo por bueno, metelo a propósito
dentro del `form_with` una vez, vela fallar, y sacalo.

- [ ] **Paso 3: el botón en la fila**

En `app/views/steps/testing.html.haml`, en la celda de acción de cada fila,
junto al link de «Testear», con la misma guarda `puede_testear && @step.active?`
y sólo si el módulo no está en «Solo personas»:

```haml
            - if puede_testear && @step.active? && @step.effective_ai_mode != "human"
              = button_to "IA", challenge_ai_requests_path(@challenge, purpose: "test_idea",
                                                           step_id: @step.id, idea_id: entry.idea_id),
                          class: "btn btn-ghost btn-sm", form_class: "inline-form"
```

**Mirá antes `app/views/steps/_fila_de_evaluacion.html.haml:80`**, que hace
exactamente esto para `evaluate_idea`, y copiá su forma —incluida la clase del
form— en vez de inventar una.

- [ ] **Paso 4: el botón en la pantalla del testeo**

En `app/views/step_tests/new.html.haml`, **fuera del `form_with` y en su
propia tarjeta** (decisión 3). El precedente exacto es
`app/views/assessments/new.html.haml`: el `button_to` de la línea 78 está a
cuatro espacios y el `form_with` de la 32 a ocho, o sea hermanos.

```haml
- if @step.effective_ai_mode != "human"
  .card
    .card-body
      %h2.section-title ¿Querés que la IA la ponga a prueba?
      %p.muted.field-hint
        Plantea las situaciones, prueba dónde se rompe y deja un veredicto con su evidencia.
      = button_to "Pedir el testeo de la IA",
                  challenge_ai_requests_path(@challenge, purpose: "test_idea",
                                             step_id: @step.id, idea_id: @idea.id),
                  class: "btn btn-ghost btn-sm btn-block"
```

**Cuidado con la indentación:** hoy la pantalla envuelve todo en un solo
`.card` con el `form_with` adentro. Esta tarjeta va como **hermana** de esa, no
adentro. Si queda adentro, el `button_to` cae dentro del `form_with` y es
justamente el bug que el Paso 1 vigila.

- [ ] **Paso 5: verlo pasar**

```bash
make spec-file FILE=spec/requests/testing_ia_spec.rb
make spec
```
Esperado: 0 fallas en los dos.

- [ ] **Paso 6: commit**

```bash
git add app/views/steps/testing.html.haml app/views/step_tests/new.html.haml \
        spec/requests/testing_ia_spec.rb
git commit -m "Pedirle a la IA que testee, desde las dos pantallas

El botón de la pantalla del testeo va en su propia tarjeta, fuera del
form_with: un button_to es un form, y uno dentro de otro lo aplana el
parser y sus botones pasan a pertenecer al externo."
```

---

### Task 5: El check que consume el veredicto

**Archivos:**
- Crear: `app/lib/flow/checks/testing_passed.rb`
- Modificar: `app/lib/flow/checks/base.rb:12`
- Modificar: `app/lib/flow/criterion_settings.rb` (entrada en `CHECKS`)
- Modificar: `config/locales/es.yml`
- Crear: `spec/lib/flow/checks/testing_passed_spec.rb`

**Interfaces:**
- Consume: `StepTest` y sus scopes (tanda 1).
- Produce: `Flow::Checks::TestingPassed`, que `Checks::Base.for(criterion)`
  encuentra por `camelize` sobre `source_config["check"]`. **No hay que tocar
  el despacho**, sólo sumar el tipo a `TYPES`.

**La trampa de esta tarea, y es la misma que ya pagó `feedback_addressed`:**
un check **no sabe en qué módulo lo están corriendo** — sólo tiene su
`criterion` y la idea. Así que «el testeo» no puede ser «el de este módulo».
Es **el testeo vigente del módulo de testing más reciente que probó esa
idea**: se juntan los `step_tests` vigentes de la idea, se toma el del paso con
la posición más alta. Mirando todos, un testeo viejo de una ronda anterior
decidiría para siempre.

- [ ] **Paso 1: escribir el spec**

`spec/lib/flow/checks/testing_passed_spec.rb`:

```ruby
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
      expect(resultado.detail).to include("2")
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
      expect(resultado.detail).to include("sin testear")
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
end
```

- [ ] **Paso 2: verlo fallar**

Correr: `make spec-file FILE=spec/lib/flow/checks/testing_passed_spec.rb`
Esperado: FALLA con `NameError: uninitialized constant Flow::Checks::TestingPassed`.

- [ ] **Paso 3: el check**

`app/lib/flow/checks/testing_passed.rb`:

```ruby
# frozen_string_literal: true

module Flow
  module Checks
    # La idea pasó su prueba de factibilidad.
    #
    # Un check NO sabe en qué módulo lo están corriendo: sólo tiene su
    # `criterion` y la idea. Así que «el testeo» no puede ser «el de este
    # módulo»: es el vigente del módulo de testing MÁS RECIENTE que probó esta
    # idea. Mirando todos, un veredicto de una ronda vieja decidiría para
    # siempre. Es la misma lógica de `feedback_addressed`, con otra tabla.
    class TestingPassed < Base
      ACEPTA = {
        "solo_factible" => %w[factible],
        "factible_o_con_reservas" => %w[factible con_reservas]
      }.freeze

      def call(idea)
        test = vigente_de(idea)
        return sin_testeo if test.nil?

        return fail(detalle_de(test)) unless aceptados.include?(test.verdict)

        pass(detalle_de(test))
      end

      def description = "pasó su prueba de factibilidad"

      private

      # El vigente del módulo de testing con la posición más alta entre los que
      # probaron esta idea.
      def vigente_de(idea)
        StepTest.vigentes.where(idea_id: idea.id).includes(:challenge_step).to_a
                .max_by { |test| test.challenge_step.position.to_d }
      end

      def aceptados = ACEPTA.fetch(config["accepts"].to_s, ACEPTA.fetch("factible_o_con_reservas"))

      # El detalle se lee en la celda del filtro del ranking, así que dice cuál
      # de los dos casos fue y no sólo si pasó.
      def detalle_de(test)
        reservas = Array(test.reservations).size
        texto = I18n.t("flow.verdicts.#{test.verdict}")
        return texto if reservas.zero?

        "#{texto} con #{Flow::Texto.contar(reservas, 'reserva')}"
      end

      def sin_testeo
        config["sin_testeo"].to_s == "no_pasa" ? fail("sin testear") : pass("sin testear")
      end
    end
  end
end
```

- [ ] **Paso 4: el tipo, los params y el rótulo**

En `app/lib/flow/checks/base.rb:12`:

```ruby
      TYPES = %w[field_present contributors_count version_count feedback_addressed
                 has_attachment testing_passed].freeze
```

En `app/lib/flow/criterion_settings.rb`, dentro de `CHECKS`, después de
`has_attachment`:

```ruby
      "testing_passed" => {
        summary: "Pasó su prueba de factibilidad.",
        params: [
          { key: "accepts", type: "select", default: "factible_o_con_reservas",
            label: "Qué veredicto se acepta",
            options: [
              { value: "factible_o_con_reservas", label: "Factible, o factible con reservas" },
              { value: "solo_factible", label: "Sólo factible" }
            ] },
          { key: "sin_testeo", type: "select", default: "pasa",
            label: "Si nadie la testeó",
            options: [
              { value: "pasa", label: "Pasa el filtro" },
              { value: "no_pasa", label: "No pasa el filtro" }
            ],
            hint: "Una idea que ningún módulo de testing probó. El default la deja pasar: " \
                  "un filtro permisivo se aprieta, y uno restrictivo sorprende." }
        ]
      }
```

En `config/locales/es.yml`, junto a los otros rótulos de `flow.checks`:

```yaml
    checks:
      testing_passed:
        label: "Pasó la prueba de factibilidad"
```

**Verificá la forma de las claves de `flow.checks` que ya están** antes de
escribir ésta: `Checks::Base.label` hace
`I18n.t("flow.checks.#{type}.label", default: type.humanize)`, así que una
clave mal anidada no rompe nada — se cae al `humanize` en silencio y el rótulo
sale en inglés feo.

- [ ] **Paso 5: verlo pasar**

```bash
make spec-file FILE=spec/lib/flow/checks/testing_passed_spec.rb
make spec
```
Esperado: 0 fallas en los dos. Si falla un spec que cuenta los tipos de check
o las entradas de `CHECKS`, es que alguno enumera a mano en vez de derivar de
`TYPES` — arreglalo derivando, como se hizo en la tanda 1 con los kinds.

- [ ] **Paso 6: commit**

```bash
git add app/lib/flow/checks/testing_passed.rb app/lib/flow/checks/base.rb \
        app/lib/flow/criterion_settings.rb config/locales/es.yml \
        spec/lib/flow/checks/testing_passed_spec.rb
git commit -m "El filtro que consume el veredicto del testeo

Un check no sabe en qué módulo lo corren, así que «el testeo» es el
vigente del módulo de testing más reciente que probó esa idea. Mirando
todos, un veredicto de una ronda vieja decidiría para siempre.

sin_testeo es configurable y su default es pasa: un filtro permisivo se
aprieta, y uno restrictivo sorprende."
```

---

### Task 6: Seeds y capturas

**Archivos:**
- Modificar: `db/seeds.rb`
- Modificar: `script/capture_screens.js`

**Interfaces:**
- Consume: todo lo anterior.

- [ ] **Paso 1: sembrar un desafío con testing → selección**

**De un solo propósito, no compartido.** `onboarding-remoto` y `merma-bodega`
se usan a mano y compartirlos ya rompió la corrida dos veces (`3e437d6`,
`04f2d00`); `comite-abierto`, `con-salteado` y `testeo-abierto` existen cada
uno para su captura. Este sigue esa línea.

En `db/seeds.rb`, junto a `testeo-abierto` y con la misma forma:

```ruby
    # Un desafío donde el testeo CORTA: el módulo de testing ya cerró con dos
    # veredictos distintos, y la selección que sigue filtra por
    # `testing_passed`. Es la única forma de que la captura muestre la celda
    # del filtro con sus dos estados —la factible pasa, la no factible no—.
    # Propio y no compartido, como manda CLAUDE.md: existe sólo para esto.
    Challenge.where(slug: "filtro-por-testeo").destroy_all
    filtro = Challenge.create!(
      slug: "filtro-por-testeo",
      name: "Reducir el tiempo de espera en mesa",
      brief: "Buscamos formas de bajar el tiempo entre que alguien se sienta y recibe lo que pidió.",
      ai_default_mode: "human"
    )
    filtro.pipeline.insert(kind: "ideation", after: :end, name: "Postulación")
    filtro.pipeline.insert(kind: "testing", after: :end, name: "Prueba de factibilidad")
    filtro.pipeline.insert(kind: "selection", after: :end, name: "Corte por factibilidad")

    filtro_ideacion = filtro.pipeline.ideation_step
    filtro_ideacion.form_fields.create!(key: "titulo", label: "Título", field_type: "text",
                                        required: true, position: 0,
                                        config: { "is_title" => true })

    # El filtro vive en un set INLINE del módulo de selección: es de este
    # módulo y no se comparte con ningún otro desafío.
    filtro_seleccion = filtro.pipeline.steps.find { |s| s.kind == "selection" }
    # Un set `inline` cuelga de SU MÓDULO por `owner_step_id`, no del desafío:
    # es la forma que usa el resto del seed (`db/seeds.rb:430`).
    set_de_filtro = CriteriaSet.create!(
      name: "Filtro de factibilidad", scope: "inline", owner_step_id: filtro_seleccion.id,
      description: "Sólo avanzan las ideas que pasaron la prueba."
    )
    set_de_filtro.criteria.create!(
      name: "Pasó la prueba de factibilidad", key: "factible", weight: 1.0,
      source: "automatic", scale_type: "boolean", position: 0,
      source_config: { "check" => "testing_passed",
                       "accepts" => "factible_o_con_reservas",
                       "sin_testeo" => "no_pasa" }
    )
    set_de_filtro.refresh_status!
    filtro_seleccion.update!(criteria_set_id: set_de_filtro.id)

    filtro.pipeline.start!

    ideas_del_filtro = [
      ["Tablet para pedir desde la mesa", "factible"],
      ["Cocina satélite en el subsuelo", "no_factible"]
    ].map do |titulo, _|
      idea = Idea.create!(challenge: filtro, author: User.find_by!(email: "part1@demo.test"),
                          status: "draft", origin: "human")
      Flow::Ideas::PublishVersion.new(
        idea, payload: { "titulo" => titulo }, author: idea.author, actor_type: "human",
        source_step: filtro_ideacion, change_note: "Creación de la idea"
      ).call
      idea.update!(submitted_at: Time.current)
      idea
    end

    filtro.pipeline.advance!  # → Prueba de factibilidad
    paso_de_prueba = filtro.pipeline.active_step

    paso_de_prueba.handler.testear!(
      idea: ideas_del_filtro[0], verdict: "factible",
      situations: [{ "dimension" => "operativa", "escenario" => "Sábado a las 21, salón lleno",
                     "resultado" => "aguanta", "detalle" => "La mesa pide sin esperar al mozo" }],
      reservations: [], summary: "Aguanta el peor turno de la semana.",
      tested_by: User.find_by!(email: "admin@demo.test")
    )
    paso_de_prueba.handler.testear!(
      idea: ideas_del_filtro[1], verdict: "no_factible",
      situations: [{ "dimension" => "economica", "escenario" => "Con el alquiler del subsuelo",
                     "resultado" => "se_rompe", "detalle" => "El costo fijo se come el ahorro del turno" }],
      reservations: [], summary: "No se paga con el volumen actual.",
      tested_by: User.find_by!(email: "admin@demo.test")
    )

    filtro.pipeline.advance!  # → Corte por factibilidad (activo, con el filtro ya respondido)
```

**Los dos correos (`part1@demo.test`, `admin@demo.test`) son los que siembra
el propio seed** — verificalo en `db/seeds.rb:57` antes de correr, porque si
cambiaron el `find_by!` revienta con `RecordNotFound` y el seed se corta a la
mitad.

**`sin_testeo` va en `no_pasa` a propósito acá**, aunque el default del check
sea `pasa`: las dos ideas están testeadas, así que no cambia el resultado, pero
deja el parámetro visible en la tarjeta de configuración congelada de la
captura.

Corré `make seed` y mirá que no reviente. **No es `make rails ARGS="db:seed"`.**

- [ ] **Paso 2: la captura**

Una captura de la pantalla de selección de ese desafío, con la celda del filtro
visible. Reglas que no son negociables:

- **Navegá por link, no con `goto`.** Turbo no dispara `DOMContentLoaded` al
  navegar por link; un `goto` monta la isla igual y esconde el bug.
- **Después de un clic, esperá `waitForURL` o un selector** — `networkidle` se
  calma antes de que Turbo ponga el body nuevo.
- El módulo nuevo tiene que caer en **exactamente una** de las dos listas
  `MODULOS_*`, o en ninguna si su cara no se visita. Si no cae en ninguna y sí
  se visita, `[ZONAS]` falla con «nadie chequea sus zonas».

**Ojo con `MODULOS_EN_ZONAS`:** esa lista sólo se consulta dentro del loop de
`stepLinks`, que recorre `merma-bodega`. Sumar una regex ahí para un desafío
distinto **no se ejercita nunca** — es lo que pasó en la tanda 1. Si tu
captura necesita el chequeo de zonas, repetí la lógica a mano como se hizo en
`22-testing`.

- [ ] **Paso 3: correr el recorrido**

```bash
make screens
```

Esperado: N+1 capturas, sin errores de JS ni respuestas >= 400. **Corrélo dos
veces seguidas sin `make seed` en el medio** y que las dos den verde: si la
segunda falla, la captura no es idempotente.

**No corras dos `make screens` en paralelo:** borra y reescribe
`tmp/screenshots/` entero al arrancar.

- [ ] **Paso 4: la verificación final, a mano**

```bash
make spec
make screens
```

Y lo que ninguna guarda ve: **mirar la captura nueva** y confirmar que la celda
del filtro dice lo que el `detail` del check produce, no un texto genérico.

- [ ] **Paso 5: commit**

```bash
git add db/seeds.rb script/capture_screens.js
git commit -m "Un desafío que filtra por el testeo, y su captura

La idea no factible queda del lado que no pasa y la factible del que sí:
es lo único que hace que la celda del filtro muestre sus dos estados."
```

---

## Al terminar la tanda

`make spec` y `make screens` en verde **sobre el merge y no sólo sobre la
rama**, merge `--no-ff` a `master`, borrar la rama en los dos lados y
actualizar `handoff.md`.

Con esto el módulo de testing queda completo: los tres modos y el filtro que
lo conecta con una selección.

## Lo que esta tanda NO cierra

- **El riesgo nº2 de la spec sigue sin mitigación.** La dureza del prompt sólo
  se mide con el proveedor real, y el fixture no dice nada al respecto.
- **Testers asignados y agregación de varios testeos** siguen fuera de alcance
  (spec §Fuera de alcance).
- **Quien acompaña no puede testear.** La spec §2.5 dice «quien administra o
  acompaña» pero el predicado que nombra deja al gestor afuera. Decisión
  pendiente del dueño del producto, anotada en el handoff.
