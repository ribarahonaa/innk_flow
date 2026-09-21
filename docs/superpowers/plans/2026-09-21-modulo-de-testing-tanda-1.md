# Módulo de testing · Tanda 1 — el `kind` en «Solo personas»

> **Para quien ejecute esto:** SUB-SKILL REQUERIDA: usá
> `superpowers:subagent-driven-development` (recomendado) o
> `superpowers:executing-plans` para implementar tarea por tarea. Los pasos
> usan checkbox (`- [ ]`).

**Objetivo:** dejar vivo el sexto `kind` del flujo —`testing`— funcionando
entero a mano, sin una línea de IA.

**Arquitectura:** un `kind` más en `ChallengeStep`, su handler, una tabla
`step_tests` append-only con el vigente garantizado por un índice parcial, las
dos caras de pantalla que `StepsController#show` ya despacha por `kind`, y una
pantalla propia para el testeo de cada idea. Nada elimina ideas: eso sigue
siendo exclusivo de la selección.

**Stack:** Rails 7.1 · Postgres (`schema_format = :sql`) · HAML · RSpec ·
Docker (`make spec`, `make screens`).

**Spec:** `docs/superpowers/specs/2026-09-21-modulo-de-testing-design.md`

## Restricciones globales

- **Todo en español**: código, comentarios y mensajes de commit.
- **Los commits NO llevan línea `Co-Authored-By`.**
- **Todo corre en Docker.** Nunca `bundle exec` en el host. Los specs con
  `make spec` / `make spec-file FILE=… ` / `make spec-line FILE=… LINE=…`; un
  `docker compose exec app bundle exec rspec` corre en **desarrollo** y devuelve
  403 «Blocked hosts» en todos los request specs.
- **Nunca un worktree.** `docker-compose.yml` monta `.` en `/rails`: los specs
  corren siempre contra el checkout principal.
- **Migraciones:** `schema_format = :sql`. Después de migrar, commitear
  `db/structure.sql`.
- **Tenencia en los specs:** toda lectura del dominio va dentro de
  `as_company(company) { … }`, incluido un `.new`.
- **`Flow::MigrationHelpers` ya está incluido globalmente**
  (`config/initializers/migration_helpers.rb:9`): `tenant_table` y
  `add_tenant_fk` están disponibles sin `include`.
- **TDD**: el test primero, verlo fallar, el mínimo para pasarlo, verlo pasar,
  commit.

## Estructura de archivos

| Archivo | Responsabilidad |
|---|---|
| `db/migrate/20260921120000_create_step_tests.rb` | El CHECK del kind y la tabla |
| `app/models/step_test.rb` | El registro de un testeo |
| `app/lib/flow/handlers/testing.rb` | El comportamiento del módulo |
| `app/lib/flow/step_settings.rb` | +1 entrada en `SCHEMA` |
| `app/lib/flow/setup.rb` | +1 rama en `estado_de` |
| `config/locales/es.yml` | 3 claves |
| `app/views/steps/config/testing.html.haml` | Cara de configuración |
| `app/views/steps/testing.html.haml` | Cara de ejecución |
| `app/views/step_tests/new.html.haml` | El formulario del testeo de una idea |
| `app/controllers/step_tests_controller.rb` | `new` y `create` |

---

### Task 1: La migración, el enum y el modelo

**Archivos:**
- Crear: `db/migrate/20260921120000_create_step_tests.rb`
- Crear: `app/models/step_test.rb`
- Modificar: `app/models/challenge_step.rb:10`
- Crear: `spec/models/step_test_spec.rb`
- Commitear: `db/structure.sql`

**Interfaces:**
- Produce: `StepTest` con `scope :vigentes`, `#by_ai?`, `#tested_by_name`.
  `ChallengeStep::KINDS` incluye `"testing"`, y por el `KINDS.each` de la
  línea 62 queda definido `ChallengeStep#testing?`.

- [ ] **Paso 1: escribir el spec del modelo**

`spec/models/step_test_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe StepTest do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:challenge) { create(:challenge) }
  let!(:paso) { challenge.steps.create!(kind: "testing", position: 1, slug: "testeo") }
  let(:idea) do
    i = create(:idea, challenge: challenge, status: "active")
    Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" }).call
    i.reload
  end

  def testear(atributos = {})
    described_class.create!({ challenge_step: paso, idea: idea,
                              idea_version_id: idea.current_version_id,
                              verdict: "factible", tested_at: Time.current }.merge(atributos))
  end

  it "acepta los tres veredictos" do
    %w[factible con_reservas no_factible].each do |veredicto|
      expect { testear(verdict: veredicto) }.not_to raise_error
      described_class.delete_all
    end
  end

  # La unicidad del vigente NO es una validación de Rails: es un índice parcial.
  # Se prueba contra la base porque es ahí donde vive la garantía — una
  # validación se saltea con `save(validate: false)` o con un camino de
  # escritura nuevo, el índice no.
  it "la base rechaza dos testeos vigentes para la misma idea" do
    testear

    expect { testear }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "pero acepta otro si el anterior quedó superado" do
    primero = testear
    primero.update!(superseded_at: Time.current)

    expect { testear(verdict: "no_factible") }.not_to raise_error
    expect(described_class.vigentes.count).to eq(1)
  end

  it "el nombre de quien testeó dice «IA» cuando la dejó la IA" do
    expect(testear(actor_type: "ai").tested_by_name).to eq("IA")
  end
end
```

- [ ] **Paso 2: verlo fallar**

Correr: `make spec-file FILE=spec/models/step_test_spec.rb`
Esperado: FALLA. Primero con `NameError: uninitialized constant StepTest`.

- [ ] **Paso 3: la migración**

`db/migrate/20260921120000_create_step_tests.rb`:

```ruby
# frozen_string_literal: true

# El sexto kind del flujo y la tabla donde vive cada testeo.
#
# La lista de kinds vive en el modelo Y en un CHECK de Postgres: sumar uno es
# tocar los dos. El check es lo que impide que una migración de datos o un job
# viejo metan un kind que `Handlers::Base.for` no sabe despachar.
class CreateStepTests < ActiveRecord::Migration[7.1]
  KINDS = %w[ideation evolution evaluation selection reporting testing].freeze
  VERDICTS = %w[factible con_reservas no_factible].freeze
  ACTOR_TYPES = %w[human ai].freeze

  def up
    reemplazar_check_de_kind(KINDS)

    tenant_table :step_tests do |t|
      t.references :challenge_step, null: false, type: :uuid, index: true
      t.references :idea, null: false, type: :uuid, index: true
      t.references :idea_version, null: false, type: :uuid

      t.string :verdict, null: false
      t.jsonb :situations, null: false, default: []
      t.jsonb :reservations, null: false, default: []
      t.text :summary

      t.string :actor_type, null: false, default: "human"
      t.references :tested_by, type: :uuid, foreign_key: { to_table: :users }
      t.references :ai_run, type: :uuid, foreign_key: true

      t.datetime :superseded_at
      t.datetime :tested_at, null: false
      t.timestamps
    end

    agregar_check :step_tests, :verdict, VERDICTS
    agregar_check :step_tests, :actor_type, ACTOR_TYPES

    # UN solo testeo vigente por idea, garantizado por la base y no por una
    # convención que un camino de escritura nuevo pueda romper.
    add_index :step_tests, %i[challenge_step_id idea_id],
              unique: true, where: "superseded_at IS NULL",
              name: "index_step_tests_vigente"

    # Postgres rechaza atar una fila de la empresa A a un padre de la B.
    add_tenant_fk :step_tests, :challenge_steps, column: :challenge_step_id
    add_tenant_fk :step_tests, :ideas, column: :idea_id
    add_tenant_fk :step_tests, :idea_versions, column: :idea_version_id
  end

  def down
    drop_table :step_tests
    reemplazar_check_de_kind(KINDS - ["testing"])
  end

  private

  def reemplazar_check_de_kind(kinds)
    lista = kinds.map { |k| connection.quote(k) }.join(", ")
    execute "ALTER TABLE challenge_steps DROP CONSTRAINT challenge_steps_kind_check"
    execute "ALTER TABLE challenge_steps ADD CONSTRAINT challenge_steps_kind_check CHECK (kind IN (#{lista}))"
  end

  def agregar_check(tabla, columna, valores)
    lista = valores.map { |v| connection.quote(v) }.join(", ")
    execute "ALTER TABLE #{tabla} ADD CONSTRAINT #{tabla}_#{columna}_check CHECK (#{columna} IN (#{lista}))"
  end
end
```

- [ ] **Paso 4: el modelo y el enum**

`app/models/step_test.rb`:

```ruby
# frozen_string_literal: true

# Un testeo de factibilidad sobre UNA versión de UNA idea.
#
# Append-only: re-testear no edita el anterior, lo marca `superseded_at` y
# escribe otro. El vigente es el que tiene `superseded_at` en nil, y que haya
# uno solo lo garantiza un índice parcial, no una validación.
class StepTest < ApplicationRecord
  include TenantScoped

  VERDICTS = %w[factible con_reservas no_factible].freeze

  belongs_to :challenge_step
  belongs_to :idea
  belongs_to :idea_version
  belongs_to :tested_by, class_name: "User", optional: true
  belongs_to :ai_run, optional: true

  validates :verdict, inclusion: { in: VERDICTS }

  scope :vigentes, -> { where(superseded_at: nil) }
  scope :recientes, -> { order(tested_at: :desc) }

  def by_ai? = actor_type == "ai"
  def tested_by_name = by_ai? ? "IA" : (tested_by&.name || "—")

  # Las situaciones que se rompieron: la evidencia que sostiene el veredicto.
  def situaciones_rotas = situations.select { |s| s["resultado"] == "se_rompe" }
end
```

En `app/models/challenge_step.rb:10`:

```ruby
  KINDS = %w[ideation evolution evaluation selection reporting testing].freeze
```

- [ ] **Paso 5: migrar y ver pasar**

```bash
make rails ARGS="db:migrate"
make spec-file FILE=spec/models/step_test_spec.rb
```

Esperado: 4 ejemplos, 0 fallas.

- [ ] **Paso 6: la suite entera**

Correr: `make spec`
Esperado: 0 fallas. Presta atención a `spec/tenancy/schema_spec.rb`, que
introspecciona `pg_constraint` y falla si aparece una FK **simple** entre dos
tablas con `company_id` — si falla ahí, falta un `add_tenant_fk`.

- [ ] **Paso 7: commit**

```bash
git add db/migrate/20260921120000_create_step_tests.rb db/structure.sql \
        app/models/step_test.rb app/models/challenge_step.rb \
        spec/models/step_test_spec.rb
git commit -m "El kind «testing» y la tabla de testeos

La lista de kinds vive en el modelo y en un CHECK de Postgres. El vigente
por idea lo garantiza un índice parcial y no una validación: una
validación se saltea con save(validate: false) o con un camino de
escritura nuevo, el índice no."
```

---

### Task 2: El handler

**Archivos:**
- Crear: `app/lib/flow/handlers/testing.rb`
- Crear: `spec/lib/flow/handlers/testing_spec.rb`

**Interfaces:**
- Consume: `StepTest` de la Task 1.
- Produce: `Flow::Handlers::Testing` con `#testear!(idea:, verdict:, situations:, reservations:, summary:, tested_by:, ai_run_id:)`,
  `#vigente_para(idea_id)`, `#historial_de(idea_id)`, `#sin_testear`,
  `#dimensions`, `#min_situations`, `#severity`.
  `Handlers::Base.for` lo encuentra solo: hace
  `const_get("Flow::Handlers::#{step.kind.camelize}")`, y `"testing".camelize`
  es `"Testing"`. **No hay que tocar el despacho.**

- [ ] **Paso 1: escribir el spec del handler**

`spec/lib/flow/handlers/testing_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flow::Handlers::Testing do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:tester) { without_tenant { create(:user) } }
  let(:challenge) { create(:challenge) }
  let!(:ideation) { seed_form!(challenge.steps.create!(kind: "ideation", position: 1, slug: "ideation")) }

  let!(:ideas) do
    %w[Sensores Cámaras].map do |titulo|
      idea = create(:idea, challenge: challenge, status: "active")
      Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => titulo }).call
      idea.update!(submitted_at: Time.current)
      idea
    end
  end

  def armar(config = {})
    step = challenge.steps.create!(kind: "testing", position: 2, name: "Prueba de factibilidad",
                                   config: config)
    challenge.update!(status: "running")
    Flow::Handlers::Base.for(step).activate!
    described_class.new(step.reload)
  end

  def testear(handler, idea, veredicto, **resto)
    handler.testear!(idea: idea, verdict: veredicto, tested_by: tester,
                     situations: [{ "dimension" => "operativa", "escenario" => "Viernes 18h",
                                    "resultado" => veredicto == "factible" ? "aguanta" : "se_rompe",
                                    "detalle" => "El turno de tarde" }],
                     reservations: [], summary: "Probado", **resto)
  end

  it "el despacho por kind lo encuentra sin tocar Handlers::Base" do
    handler = armar
    expect(Flow::Handlers::Base.for(handler.step)).to be_a(described_class)
  end

  it "arranca sin precondiciones: no necesita nada de un módulo anterior" do
    step = challenge.steps.create!(kind: "testing", position: 2)
    ready, = described_class.new(step).can_activate?
    expect(ready).to be(true)
  end

  describe "#testear!" do
    it "deja el testeo vigente de esa idea, anclado a la versión probada" do
      handler = armar
      test = testear(handler, ideas[0], "con_reservas")

      expect(test.idea_version_id).to eq(ideas[0].reload.current_version_id)
      expect(handler.vigente_para(ideas[0].id).verdict).to eq("con_reservas")
    end

    # Append-only: re-testear no edita, marca el anterior y escribe otro.
    it "re-testear supera al anterior y lo deja en el historial" do
      handler = armar
      testear(handler, ideas[0], "no_factible")
      testear(handler, ideas[0], "factible")

      expect(handler.vigente_para(ideas[0].id).verdict).to eq("factible")
      expect(handler.historial_de(ideas[0].id).map(&:verdict)).to eq(%w[factible no_factible])
      expect(StepTest.where(idea_id: ideas[0].id).count).to eq(2)
    end
  end

  describe "#progress y #can_complete?" do
    it "cuenta las ideas testeadas" do
      handler = armar
      testear(handler, ideas[0], "factible")

      expect(handler.progress.done).to eq(1)
      expect(handler.progress.total).to eq(2)
    end

    it "no se puede cerrar con ideas sin testear" do
      handler = armar
      ready, reasons = handler.can_complete?

      expect(ready).to be(false)
      expect(reasons.join).to match(/Faltan 2 ideas por testear/)
    end

    it "se puede cerrar con todas testeadas" do
      handler = armar
      ideas.each { |idea| testear(handler, idea, "factible") }

      expect(handler.can_complete?.first).to be(true)
    end
  end

  # Nadie se elimina acá: eso es exclusivo de la selección. Todas las entries
  # se resuelven `done` con el veredicto adentro, que es donde el resto de la
  # app busca el resultado de un módulo.
  it "al cerrar proyecta el veredicto a step_entries y no elimina a nadie" do
    handler = armar
    testear(handler, ideas[0], "factible")
    testear(handler, ideas[1], "no_factible")
    handler.complete!

    entries = handler.step.step_entries.reload
    expect(entries.map(&:status).uniq).to eq(["done"])
    expect(entries.map { _1.result["verdict"] }).to match_array(%w[factible no_factible])
    expect(challenge.ideas.alive.count).to eq(2)
  end
end
```

- [ ] **Paso 2: verlo fallar**

Correr: `make spec-file FILE=spec/lib/flow/handlers/testing_spec.rb`
Esperado: FALLA con `NameError: uninitialized constant Flow::Handlers::Testing`.

- [ ] **Paso 3: el handler**

`app/lib/flow/handlers/testing.rb`:

```ruby
# frozen_string_literal: true

module Flow
  module Handlers
    # «Testing»: pone la idea a prueba contra situaciones concretas de
    # ejecución y deja un veredicto de factibilidad con su evidencia.
    #
    # NO elimina a nadie: `ideas.status` sigue teniendo un solo escritor, que
    # es `Selection#decide!`. Quien quiera que el testeo corte, pone una
    # selección después con un filtro `testing_passed`.
    class Testing < Base
      SEVERITIES = %w[exigente estandar].freeze
      DIMENSIONS = %w[tecnica operativa economica legal adopcion].freeze

      # Arranca sin precondiciones: no lee el resultado de ningún módulo
      # anterior, solo las ideas que le llegan.
      def can_activate? = [true, []]

      def dimensions = Array(settings.fetch("dimensions", DIMENSIONS)).presence || DIMENSIONS
      def min_situations = settings.fetch("min_situations", 3).to_i
      def severity = settings.fetch("severity", "exigente")

      def vigente_para(idea_id) = vigentes[idea_id]

      # Del más nuevo al más viejo, el vigente primero.
      def historial_de(idea_id)
        StepTest.where(challenge_step_id: step.id, idea_id: idea_id).recientes.to_a
      end

      def sin_testear
        step.step_entries.includes(:idea).reject { |entry| vigentes.key?(entry.idea_id) }
      end

      def progress
        Progress.new(done: vigentes.size, total: step.step_entries.size, label: "ideas testeadas")
      end

      def can_complete?
        faltan = sin_testear.size
        return [true, []] if faltan.zero?

        [false, ["Faltan #{Flow::Texto.contar(faltan, "idea")} por testear."]]
      end

      # Escribe el testeo nuevo y supera al anterior EN LA MISMA transacción:
      # si se escribiera primero el nuevo, el índice parcial lo rechazaría, y
      # si se superara primero y fallara el nuevo, la idea quedaría sin testeo
      # vigente.
      def testear!(idea:, verdict:, situations:, reservations:, summary:,
                   tested_by: nil, ai_run_id: nil)
        ActiveRecord::Base.transaction do
          StepTest.where(challenge_step_id: step.id, idea_id: idea.id, superseded_at: nil)
                  .update_all(superseded_at: Time.current)

          @vigentes = nil
          StepTest.create!(
            challenge_step: step, idea: idea, idea_version_id: idea.current_version_id,
            verdict: verdict, situations: situations, reservations: reservations,
            summary: summary, tested_by: tested_by, ai_run_id: ai_run_id,
            actor_type: tested_by ? "human" : "ai", tested_at: Time.current
          )
        end
      end

      def veredictos_contados
        StepTest::VERDICTS.index_with { |v| vigentes.values.count { |t| t.verdict == v } }
      end

      protected

      # El resultado queda donde el resto de la app lo busca, igual que
      # `recompute_entry!` en evaluación. Todas `done`: nadie se elimina.
      def on_complete
        step.step_entries.each do |entry|
          test = vigente_para(entry.idea_id)
          entry.resolve!(status: "done",
                         result: entry.result.merge("verdict" => test&.verdict,
                                                    "tested_at" => test&.tested_at))
        end
      end

      private

      def vigentes
        @vigentes ||= StepTest.where(challenge_step_id: step.id, superseded_at: nil)
                              .index_by(&:idea_id)
      end
    end
  end
end
```

- [ ] **Paso 4: verlo pasar**

Correr: `make spec-file FILE=spec/lib/flow/handlers/testing_spec.rb`
Esperado: 9 ejemplos, 0 fallas.

- [ ] **Paso 5: commit**

```bash
git add app/lib/flow/handlers/testing.rb spec/lib/flow/handlers/testing_spec.rb
git commit -m "El handler del módulo de testing

Un testeo vigente por idea, append-only. Re-testear supera al anterior y
escribe otro en la misma transacción: al revés, el índice parcial
rechazaría el nuevo o la idea quedaría sin vigente si el insert fallara.

No toca ideas.status: al cerrar proyecta el veredicto a step_entries y
todas quedan done."
```

---

### Task 3: El esquema de configuración, el paso a paso y los rótulos

**Archivos:**
- Modificar: `app/lib/flow/step_settings.rb` (entrada nueva en `SCHEMA`)
- Modificar: `app/lib/flow/setup.rb:123` (rama nueva en `estado_de`)
- Modificar: `config/locales/es.yml`
- Modificar: `spec/lib/flow/step_settings_spec.rb`

**Interfaces:**
- Consume: `Flow::Handlers::Testing::DIMENSIONS` y `SEVERITIES` de la Task 2.
- Produce: `StepSettings.for("testing")` con las claves `dimensions`,
  `min_situations`, `severity`.

- [ ] **Paso 1: escribir el test**

En `spec/lib/flow/step_settings_spec.rb`, junto a los demás (mirá el de la
línea 41 como molde — chequea las claves en orden):

```ruby
  it "declara los tres campos de un módulo de testing" do
    claves = described_class.fields("testing").map { |c| c[:key] }
    expect(claves).to eq(%w[dimensions min_situations severity])
  end

  # En `config` un hueco no es «sin valor»: es el default del esquema. Un
  # testing sembrado sin config tiene que correr con las cinco dimensiones.
  it "un testing sin config corre con los defaults" do
    efectivo = described_class.efectivo("testing", {})
    expect(efectivo["min_situations"]).to eq(3)
    expect(efectivo["severity"]).to eq("exigente")
  end
```

Y en `spec/lib/flow/setup_spec.rb` (o donde viva el spec de `Flow::Setup`):

```ruby
  it "un módulo de testing nace configurado y no traba el arranque" do
    paso = challenge.steps.create!(kind: "testing", position: 2, name: "Prueba")
    entrada = Flow::Setup.new(challenge).steps.find { |s| s.key == paso.id }

    expect(entrada.status).to eq(:done)
    expect(entrada.blocking).to be(false)
  end
```

- [ ] **Paso 2: verlos fallar**

```bash
make spec-file FILE=spec/lib/flow/step_settings_spec.rb
```
Esperado: FALLA — `fields("testing")` devuelve `[]`, así que `claves` es `[]`.

- [ ] **Paso 3: la entrada del esquema**

En `app/lib/flow/step_settings.rb`, dentro de `SCHEMA`, después de la entrada
`"selection"`:

```ruby
      "testing" => {
        essential: [
          { key: "dimensions", type: "multi_select",
            default: Flow::Handlers::Testing::DIMENSIONS,
            label: "Dimensiones que hay que cubrir",
            options: [
              { value: "tecnica", label: "Técnica" },
              { value: "operativa", label: "Operativa" },
              { value: "economica", label: "Económica" },
              { value: "legal", label: "Legal" },
              { value: "adopcion", label: "De adopción" }
            ],
            hint: "Cada situación que se prueba pertenece a una de éstas. " \
                  "Vacío = las cinco." },
          { key: "min_situations", type: "number", default: 3, min: 1,
            label: "Mínimo de situaciones por idea",
            hint: "Cuántos escenarios de ejecución hay que plantear antes de " \
                  "dictaminar. Menos de tres rara vez encuentra dónde se rompe." }
        ],
        advanced: [
          { key: "severity", type: "select", default: "exigente",
            label: "Qué tan dura es la vara",
            options: [
              { value: "exigente", label: "Exigente: busca activamente dónde se rompe" },
              { value: "estandar", label: "Estándar: prueba lo previsible" }
            ],
            hint: "Mueve el rigor de las SITUACIONES, no del veredicto: el " \
                  "veredicto lo dicta lo que se encontró." }
        ]
      },
```

- [ ] **Paso 4: la rama del paso a paso**

En `app/lib/flow/setup.rb`, dentro de `estado_de` (línea 123):

```ruby
      when "testing" then [true, "#{Flow::Texto.contar(dimensiones_de(modulo).size, "dimensión")} a cubrir"]
```

y el privado, junto a los otros `estado_de_*`:

```ruby
    # Un testing nace configurado: las tres claves del esquema tienen default,
    # así que no hay nada obligatorio que decidir y no traba el arranque.
    def dimensiones_de(modulo)
      Array(Flow::StepSettings.efectivo("testing", modulo.settings)["dimensions"])
    end
```

- [ ] **Paso 5: los rótulos**

En `config/locales/es.yml`, sumar una línea a cada una de las **tres** claves
que enumeran kinds (`kinds`, `kind_descriptions`, `ai_mode_invites`).
`ai_mode_descriptions` es por MODO y no por kind: no se toca.

```yaml
    kinds:
      testing: "Testing"
    kind_descriptions:
      testing: "Pone la idea a prueba contra situaciones concretas de ejecución y dictamina si es factible."
    ai_mode_invites:
      testing: "que plantee las situaciones de prueba y dictamine"
```

- [ ] **Paso 6: verlos pasar y correr la suite**

```bash
make spec-file FILE=spec/lib/flow/step_settings_spec.rb
make spec
```
Esperado: 0 fallas. Si falla un spec de i18n por claves faltantes, es que
quedó una de las tres sin agregar.

- [ ] **Paso 7: commit**

```bash
git add app/lib/flow/step_settings.rb app/lib/flow/setup.rb config/locales/es.yml \
        spec/lib/flow/step_settings_spec.rb spec/lib/flow/setup_spec.rb
git commit -m "El esquema de configuración de un testing, y sus rótulos

Tres campos, y los tres con default: un testing nace configurado y no
traba el arranque. La severidad mueve el rigor de las situaciones, no el
del veredicto."
```

---

### Task 4: La cara de configuración

**Archivos:**
- Crear: `app/views/steps/config/testing.html.haml`
- Crear: `spec/requests/testing_config_spec.rb`

**Interfaces:**
- Consume: el esquema de la Task 3, que `StepSettingsPresenter` serializa a
  `@settings_props`. `StepsController#show` ya renderiza
  `steps/config/#{kind}` sin cambios.

- [ ] **Paso 1: escribir el request spec**

`spec/requests/testing_config_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "la cara de configuración de un testing", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  let!(:admin) do
    without_tenant do
      u = create(:user, email: "admin@test.dev", name: "Ana Admin")
      create(:membership, :admin, company: company, user: u)
      u
    end
  end

  let!(:mirona) do
    without_tenant do
      u = create(:user, email: "mirona@test.dev", name: "Mica Mirona")
      create(:membership, company: company, user: u, role: "participant")
      u
    end
  end

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma")
      seed_form!(c.steps.create!(kind: "ideation", position: 1))
      c.steps.create!(kind: "testing", position: 2, name: "Prueba de factibilidad")
      c
    end
  end

  def paso = as_company(company) { challenge.steps.reload.find(&:testing?) }

  it "monta la isla de ajustes para quien configura" do
    sign_in(admin, company: company)
    get challenge_step_path(challenge, paso)

    expect(response.body).to include("step-settings")
    expect(response.body).to include("Dimensiones que hay que cubrir")
  end

  # La pantalla la sirve `ChallengeStepPolicy#show?` —cualquiera de la
  # empresa—, así que sin una guarda más estricta adentro la isla y el botón
  # quedan montados para quien no puede usarlos, y apretarlos rebota en 403.
  it "a quien no configura no le sirve ni la isla ni el botón" do
    sign_in(mirona, company: company)
    get challenge_step_path(challenge, paso)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("step-settings")
    expect(response.body).not_to include("Guardar")
  end

  # `setup_nav` es lo ÚNICO que avanza el paso a paso. Sin su render acá el
  # recorrido se corta en este módulo, y el paso sigue apareciendo en el
  # drawer igual: no se nota mirando. Pasó de verdad con `:form` (2029528).
  it "renderiza el pie del paso a paso" do
    sign_in(admin, company: company)
    get challenge_step_path(challenge, paso)

    expect(response.body).to include("setup-nav")
  end
end
```

- [ ] **Paso 2: verlo fallar**

Correr: `make spec-file FILE=spec/requests/testing_config_spec.rb`
Esperado: FALLA con `ActionView::MissingTemplate` buscando `steps/config/testing`.

- [ ] **Paso 3: la vista**

`app/views/steps/config/testing.html.haml` — es idéntica a la de reportería,
que es la más simple, porque toda la configuración la renderiza el esquema:

```haml
- content_for :title, "Configurar · #{@step.name}"
= render "steps/config/shell", step: @step
= render "steps/config/modulo", step: @step, props: @settings_props
-# El pie del paso a paso. Sin este render no hay ningún «siguiente →» que
-# ofrecer y el recorrido se corta en este módulo — y no se nota mirando,
-# porque el paso sigue apareciendo en el drawer.
= render "shared/setup_nav", challenge: @challenge
```

- [ ] **Paso 4: verlo pasar**

Correr: `make spec-file FILE=spec/requests/testing_config_spec.rb`
Esperado: 3 ejemplos, 0 fallas.

Si el segundo falla (la isla se sirve a quien no configura), el problema está
en `steps/config/_modulo`, que ya trae su propia guarda `configure?` — leelo
antes de agregar una acá.

- [ ] **Paso 5: commit**

```bash
git add app/views/steps/config/testing.html.haml spec/requests/testing_config_spec.rb
git commit -m "La cara de configuración de un testing

Sin nada propio: el esquema renderiza los tres campos. Con el render de
setup_nav, que es lo único que avanza el paso a paso."
```

---

### Task 5: La cara de ejecución y la columna de referencia

**Archivos:**
- Crear: `app/views/steps/testing.html.haml`
- Modificar: `spec/requests/pantalla_del_modulo_spec.rb:45`

**Interfaces:**
- Consume: `Flow::Handlers::Testing#veredictos_contados`, `#vigente_para`,
  `#sin_testear`, `#progress` de la Task 2; `@ideas_visibles` del controller.
- Produce: la pantalla a la que la Task 6 le cuelga el link «Testear».

- [ ] **Paso 1: sumar el título a la lista de la guarda**

En `spec/requests/pantalla_del_modulo_spec.rb:45`, dentro de
`ORDEN_DE_LA_REFERENCIA`, en el grupo «lo propio del módulo»:

```ruby
  ORDEN_DE_LA_REFERENCIA = [
    "Progreso",
    # Lo propio del módulo.
    "Criterios", "Formulario de postulación", "Descargas", "Veredictos",
    # Quién participa.
    "Quién evalúa", "Quiénes acompañan",
    "Cómo quedó configurado"
  ].freeze
```

- [ ] **Paso 2: escribir el test de forma de pantalla**

En el mismo archivo, un bloque nuevo con la forma de los que ya están (mirá el
de la línea 126 como molde):

```ruby
  describe "la pantalla de un testing en curso" do
    let!(:testing) do
      as_company(company) do
        paso = challenge.steps.create!(kind: "testing", position: 5, name: "Prueba de factibilidad")
        Flow::Handlers::Base.for(paso).activate!
        paso.reload
      end
    end

    # La referencia va en ORDEN FIJO. Sin bloque de «quién participa»: un
    # testing no tiene testers asignados.
    it "la referencia trae sus tres bloques, en orden" do
      sign_in(admin, company: company)
      get challenge_step_path(challenge, testing)

      expect(titulos_de_mas_en_la_referencia).to be_empty
      expect(titulos_de_la_referencia).to eq(["Progreso", "Veredictos", "Cómo quedó configurado"])
    end

    it "los ajustes van plegados al final, con el nombre y el modo de IA" do
      sign_in(admin, company: company)
      get challenge_step_path(challenge, testing)

      expect(response.body).to include("<details")
      expect(response.body).to include("modo de IA")
    end
  end
```

- [ ] **Paso 3: verlo fallar**

Correr: `make spec-file FILE=spec/requests/pantalla_del_modulo_spec.rb`
Esperado: FALLA con `ActionView::MissingTemplate` buscando `steps/testing`.

- [ ] **Paso 4: la vista**

`app/views/steps/testing.html.haml`:

```haml
- content_for :title, @step.name

- handler = @handler
-# Quien participa ve solo las filas de sus ideas: la regla vive una vez, en
-# `IdeaPolicy::Scope`, y el controller la publica en `@ideas_visibles`.
- filas = @step.step_entries.includes(idea: %i[current_version author]).select { |e| @ideas_visibles.include?(e.idea_id) }
- puede_testear = policy(@step).advance?

= render "steps/header", step: @step, handler: handler
= render "shared/ai_suggestions", suggestions: @pending_suggestions

.card
  .card-body
    %h2.section-title
      Ideas a prueba
      %span.muted= " · #{handler.progress.done} de #{handler.progress.total} testeadas"

    %table.table
      %thead
        %tr
          %th Idea
          %th Veredicto
          %th Se rompió en
          %th.text-right Acción
      %tbody
        - filas.each do |entry|
          - test = handler.vigente_para(entry.idea_id)
          %tr
            %td
              = link_to entry.idea.title, challenge_idea_path(@challenge, entry.idea), class: "table-link"
              %span.muted= " · #{entry.idea.author.name}"
            %td
              - if test
                %span{ class: chip_de_veredicto(test.verdict) }= t("flow.verdicts.#{test.verdict}")
                %span.muted= " · #{test.tested_by_name}"
              - else
                %span.muted sin testear
            %td.muted
              - if test
                = test.situaciones_rotas.any? ? test.situaciones_rotas.map { _1["escenario"] }.join(" · ") : "—"
              - else
                = "—"
            %td.text-right
              -# El link pregunta LA MISMA policy que autoriza al controller, no
              -# `step.active?` a secas: con eso se le mostraba a quien se comía
              -# un 403 al apretarlo (la lección del link «Evaluar»).
              - if puede_testear && @step.active?
                = link_to(test ? "Re-testear" : "Testear",
                          new_challenge_step_step_test_path(@challenge, @step, idea_id: entry.idea_id),
                          class: "btn btn-ghost btn-sm")

- content_for :referencia do
  = render "steps/progreso", handler: handler

  = render layout: "steps/bloque" do
    %h3.section-title Veredictos
    %ul.field-list
      - handler.veredictos_contados.each do |veredicto, cuantos|
        %li.field-list__item
          %span= t("flow.verdicts.#{veredicto}")
          %span.field-list__type= cuantos

  = render "steps/config_congelada", step: @step

- if puede_testear
  = render layout: "steps/ajustes", locals: { resumen: ["nombre", "modo de IA"].to_sentence } do
    = render "steps/ai_mode", step: @step
```

Sumar a `config/locales/es.yml`:

```yaml
    verdicts:
      factible: "Factible"
      con_reservas: "Factible con reservas"
      no_factible: "No factible"
```

Y a `EstilosHelper`, junto a los otros mapeos estado → clase (**el nombre
completo, escrito literal: nunca `"badge-#{x}"`, que Tailwind no ve**):

```ruby
  CHIP_DE_VEREDICTO = {
    "factible" => "badge badge-soft badge-success badge-sm font-semibold whitespace-nowrap",
    "con_reservas" => "badge badge-soft badge-warning badge-sm font-semibold whitespace-nowrap",
    "no_factible" => "badge badge-soft badge-error badge-sm font-semibold whitespace-nowrap"
  }.freeze

  def chip_de_veredicto(veredicto) = CHIP_DE_VEREDICTO.fetch(veredicto.to_s, CHIP_DE_VEREDICTO.fetch("con_reservas"))
```

Las tres cadenas ya están en `MUESTRARIO` de `script/capture_screens.js` (son
las de `CHIP_DE_ESTADO`), así que el spec que ata chips y muestrario pasa sin
tocar nada. **Verificalo** antes de asumirlo:

```bash
make spec-file FILE=spec/helpers/estilos_helper_spec.rb
```

Si falla, sumá las cadenas que reporte al arreglo `MUESTRARIO`.

Los cuatro partials de la vista —`_progreso`, `_config_congelada`, `_ajustes`
y `_ai_mode`, todos en `app/views/steps/`— **existen con esos nombres
exactos**: se verificó. Los comparten las otras cuatro pantallas de módulo, así
que se usan como están y no se renombran.

- [ ] **Paso 5: verlo pasar**

```bash
make spec-file FILE=spec/requests/pantalla_del_modulo_spec.rb
make spec-file FILE=spec/helpers/estilos_helper_spec.rb
```
Esperado: 0 fallas en los dos.

Si `titulos_de_la_referencia` devuelve algo con `¿?`, el título de la tarjeta
no coincide con el de `ORDEN_DE_LA_REFERENCIA`: se compara con `start_with?`.

- [ ] **Paso 6: commit**

```bash
git add app/views/steps/testing.html.haml app/helpers/estilos_helper.rb \
        config/locales/es.yml spec/requests/pantalla_del_modulo_spec.rb
git commit -m "La cara de ejecución de un testing

Las ideas con su veredicto vigente al centro, y la referencia con sus
tres bloques en el orden fijo. El link de testear pregunta la misma
policy que autoriza al controller, no step.active? a secas."
```

---

### Task 6: La pantalla del testeo de una idea

**Archivos:**
- Crear: `app/controllers/step_tests_controller.rb`
- Crear: `app/views/step_tests/new.html.haml`
- Modificar: `config/routes.rb`
- Crear: `spec/requests/step_tests_spec.rb`

**Interfaces:**
- Consume: `Flow::Handlers::Testing#testear!` de la Task 2.
- Produce: las rutas `new_challenge_step_step_test_path(challenge, step, idea_id:)`
  y `challenge_step_step_tests_path(challenge, step)` que la Task 5 ya usa.

- [ ] **Paso 1: escribir el request spec**

`spec/requests/step_tests_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "testear una idea", type: :request do
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
      c = create(:challenge, name: "Merma")
      seed_form!(c.steps.create!(kind: "ideation", position: 1))
      c.steps.create!(kind: "testing", position: 2, name: "Prueba de factibilidad")
      c
    end
  end

  let!(:idea) do
    as_company(company) do
      i = create(:idea, challenge: challenge, author: paula, status: "active")
      Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" }, author: paula).call
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

  let(:payload) do
    { verdict: "con_reservas",
      summary: "Aguanta el día normal, no el pico",
      reservations: "Conseguir un segundo proveedor",
      situations: [{ dimension: "operativa", escenario: "Viernes 18h, 400 pedidos",
                     resultado: "se_rompe", detalle: "El turno de tarde satura" }] }
  end

  it "guarda el testeo y vuelve a la pantalla del módulo" do
    sign_in(admin, company: company)
    post challenge_step_step_tests_path(challenge, paso), params: payload.merge(idea_id: idea.id)

    expect(response).to redirect_to(challenge_step_path(challenge, paso))
    test = as_company(company) { StepTest.vigentes.find_by(idea_id: idea.id) }
    expect(test.verdict).to eq("con_reservas")
    expect(test.reservations).to eq(["Conseguir un segundo proveedor"])
    expect(test.tested_by_id).to eq(admin.id)
  end

  # Decisión 2.5 del spec: testear es de quien administra o acompaña. Con un
  # testeo vigente por idea donde el último manda, dejar que el autor lo pida
  # es re-tirar el dado hasta que salga «factible».
  it "quien participa no puede testear, ni su propia idea" do
    sign_in(paula, company: company)
    post challenge_step_step_tests_path(challenge, paso), params: payload.merge(idea_id: idea.id)

    expect(response).to have_http_status(:forbidden)
  end

  # Lo que no se ve da 404, no 403: un 403 sobre una idea que no se debería
  # ver es un oráculo de existencia. Por eso la idea se busca por policy_scope.
  it "una idea de otro desafío da 404, no 403" do
    otra = as_company(company) do
      c2 = create(:challenge, name: "Otro")
      seed_form!(c2.steps.create!(kind: "ideation", position: 1))
      i = create(:idea, challenge: c2, author: paula, status: "active")
      Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Ajena" }, author: paula).call
      i
    end

    sign_in(admin, company: company)
    post challenge_step_step_tests_path(challenge, paso), params: payload.merge(idea_id: otra.id)

    expect(response).to have_http_status(:not_found)
  end

  it "el formulario ofrece las dimensiones que el módulo configuró" do
    sign_in(admin, company: company)
    get new_challenge_step_step_test_path(challenge, paso, idea_id: idea.id)

    expect(response.body).to include("Operativa")
    expect(response.body).to include("Sensores")
  end
end
```

- [ ] **Paso 2: verlo fallar**

Correr: `make spec-file FILE=spec/requests/step_tests_spec.rb`
Esperado: FALLA con `NoMethodError: undefined method 'challenge_step_step_tests_path'`.

- [ ] **Paso 3: la ruta**

En `config/routes.rb`, adentro del bloque `resources :steps` que abre en la
línea 21, **justo debajo de la de `assessments` (línea 31)**: es el precedente
exacto —misma anidación, mismo par de acciones—.

```ruby
      # La ficha de evaluación de una idea dentro de un módulo.
      resources :assessments, only: %i[new create]
      # El testeo de factibilidad de una idea dentro de un módulo.
      resources :step_tests, only: %i[new create]
```

- [ ] **Paso 4: el controller**

`app/controllers/step_tests_controller.rb`:

```ruby
# frozen_string_literal: true

# El testeo de factibilidad de UNA idea.
#
# Pantalla propia y no embebida en la del módulo: es trabajo por idea, como
# `assessments/new`, no configuración.
class StepTestsController < ApplicationController
  before_action :set_context

  def new
    authorize @step, :advance?
    @handler = @step.handler
    @vigente = @handler.vigente_para(@idea.id)
  end

  def create
    authorize @step, :advance?

    @step.handler.testear!(
      idea: @idea,
      verdict: params[:verdict],
      situations: situaciones,
      reservations: params[:reservations].to_s.split("\n").map(&:strip).compact_blank,
      summary: params[:summary].presence,
      tested_by: current_user
    )

    redirect_to challenge_step_path(@challenge, @step),
                notice: "Testeo guardado para «#{@idea.title.truncate(40)}»."
  end

  private

  # El desafío por `policy_scope` y la idea también: buscar con el scope de
  # tenencia y autorizar DESPUÉS devuelve 403 sobre algo que no se debería
  # ver, y esa diferencia con el 404 confirma que existe.
  def set_context
    @challenge = policy_scope(Challenge).find_by!(slug: params[:challenge_id])
    @step = @challenge.steps.find(params[:step_id])
    @idea = policy_scope(Idea).where(challenge_id: @challenge.id).find(params[:idea_id])
  end

  def situaciones
    Array(params[:situations]).filter_map do |_, fila|
      fila = fila.respond_to?(:to_unsafe_h) ? fila.to_unsafe_h : fila
      next if fila["escenario"].blank?

      fila.slice("dimension", "escenario", "resultado", "detalle")
    end
  end
end
```

**Ojo con `situaciones`:** un `params[:situations]` que llega como arreglo
(desde el spec) y uno que llega como hash indexado (desde el formulario) se
recorren distinto. El `Array(...)` sobre un hash de Rails da pares
`[clave, valor]`; sobre un arreglo, los elementos. Si el spec del Paso 1 falla
acá, normalizá con `params[:situations].respond_to?(:values) ? params[:situations].values : params[:situations]`
antes del `filter_map` y sacá el `|_, fila|`.

- [ ] **Paso 5: la vista**

`app/views/step_tests/new.html.haml`:

```haml
- content_for :title, "Testear · #{@idea.title}"

.card
  .card-body
    %h1.page-title= "Testear «#{@idea.title}»"
    %p.muted
      = "Planteá al menos #{Flow::Texto.contar(@handler.min_situations, "situación")} en la que esta idea esté funcionando, y probá dónde se rompe."

    - if @vigente
      .alert.alert-soft
        %div
          = "Ya tiene un testeo del #{l(@vigente.tested_at, format: :short)} por #{@vigente.tested_by_name}. Guardar uno nuevo lo reemplaza y deja el anterior en el historial."

    = form_with url: challenge_step_step_tests_path(@challenge, @step), method: :post do |f|
      = hidden_field_tag :idea_id, @idea.id

      - @handler.min_situations.times do |i|
        %fieldset.field
          %legend.section-title= "Situación #{i + 1}"
          .field
            = label_tag "situations[#{i}][dimension]", "Dimensión"
            = select_tag "situations[#{i}][dimension]",
                         options_for_select(@handler.dimensions.map { |d| [t("flow.dimensions.#{d}"), d] }),
                         class: "select"
          .field
            = label_tag "situations[#{i}][escenario]", "Qué situación se prueba"
            = text_field_tag "situations[#{i}][escenario]", nil,
                             placeholder: "Viernes 18h, 400 pedidos simultáneos", class: "input"
          .field
            = label_tag "situations[#{i}][resultado]", "Qué pasó"
            = select_tag "situations[#{i}][resultado]",
                         options_for_select([["Aguanta", "aguanta"], ["Se rompe", "se_rompe"]]),
                         class: "select"
          .field
            = label_tag "situations[#{i}][detalle]", "Detalle"
            = text_field_tag "situations[#{i}][detalle]", nil, class: "input"

      .field
        = label_tag :verdict, "Veredicto"
        = select_tag :verdict,
                     options_for_select(StepTest::VERDICTS.map { |v| [t("flow.verdicts.#{v}"), v] }),
                     class: "select"
      .field
        = label_tag :reservations, "Reservas (una por línea)"
        = text_area_tag :reservations, nil, rows: 3, class: "textarea",
                        placeholder: "Conseguir un segundo proveedor"
      .field
        = label_tag :summary, "Resumen"
        = text_field_tag :summary, nil, class: "input"

      .form-actions
        = submit_tag "Guardar el testeo", class: "btn btn-primary"
        = link_to "Volver", challenge_step_path(@challenge, @step), class: "btn btn-ghost"
```

Sumar a `config/locales/es.yml`:

```yaml
    dimensions:
      tecnica: "Técnica"
      operativa: "Operativa"
      economica: "Económica"
      legal: "Legal"
      adopcion: "De adopción"
```

- [ ] **Paso 6: verlo pasar**

Correr: `make spec-file FILE=spec/requests/step_tests_spec.rb`
Esperado: 4 ejemplos, 0 fallas.

- [ ] **Paso 7: la suite entera y commit**

```bash
make spec
git add app/controllers/step_tests_controller.rb app/views/step_tests/ \
        config/routes.rb config/locales/es.yml spec/requests/step_tests_spec.rb
git commit -m "La pantalla del testeo de una idea

Pantalla propia y no embebida: es trabajo por idea, como assessments/new.
El desafío y la idea se buscan por policy_scope, así que lo que no se ve
da 404 y no 403."
```

---

### Task 7: Seeds y capturas

**Archivos:**
- Modificar: `db/seeds.rb`
- Modificar: `script/capture_screens.js:605` y la lista de capturas

**Interfaces:**
- Consume: todo lo anterior.

- [ ] **Paso 1: sembrar un desafío con un testing**

**De un solo propósito, no compartido.** `onboarding-remoto` y `merma-bodega`
se usan a mano y compartirlos ya rompió la corrida dos veces (`3e437d6`,
`04f2d00`); `comite-abierto` y `con-salteado` existen cada uno para su captura.
Este sigue esa línea.

En `db/seeds.rb`, junto a `comite-abierto` (alrededor de la línea 519), con la
misma forma:

```ruby
    # Un desafío con el módulo de TESTING activo, una idea ya testeada y otra
    # sin testear: es la única forma de que la captura muestre las dos filas
    # de la tabla y los dos textos del botón («Testear» y «Re-testear»).
    # Ningún otro desafío sembrado deja un testing en ese estado. Propio y no
    # compartido, como manda CLAUDE.md — existe sólo para estas capturas.
    Challenge.where(slug: "testeo-abierto").destroy_all
    testeo = Challenge.create!(
      slug: "testeo-abierto",
      name: "Reparto en bici para el último kilómetro",
      brief: "Queremos saber si las entregas de menos de 3 km se pueden hacer en bici " \
             "sin perder la ventana de entrega.",
      ai_default_mode: "human"
    )
    testeo.pipeline.insert(kind: "ideation", after: :end, name: "Postulación")
    testeo.pipeline.insert(kind: "testing", after: :end, name: "Prueba de factibilidad")
    testeo_ideacion = testeo.pipeline.ideation_step
    testeo_ideacion.form_fields.create!(key: "titulo", label: "Título", field_type: "text",
                                        required: true, position: 0,
                                        config: { "is_title" => true })
    testeo.pipeline.start!

    ideas_a_probar = ["Bicis eléctricas con caja térmica",
                      "Tercerizar el último kilómetro a un courier local"].map do |titulo|
      idea = Idea.create!(challenge: testeo, author: User.find_by!(email: "part2@demo.test"),
                          status: "draft", origin: "human")
      Flow::Ideas::PublishVersion.new(
        idea, payload: { "titulo" => titulo }, author: idea.author, actor_type: "human",
        source_step: testeo_ideacion, change_note: "Creación de la idea"
      ).call
      idea.update!(submitted_at: Time.current)
      idea
    end

    testeo.pipeline.advance!  # → Prueba de factibilidad (activo, con las dos ideas)

    # La primera queda testeada; la segunda sin testear.
    testeo.pipeline.active_step.handler.testear!(
      idea: ideas_a_probar.first,
      verdict: "con_reservas",
      situations: [
        { "dimension" => "operativa", "escenario" => "Viernes de lluvia, 40 entregas",
          "resultado" => "se_rompe", "detalle" => "Con lluvia la ventana se estira 25 minutos" },
        { "dimension" => "economica", "escenario" => "Con el costo actual por entrega",
          "resultado" => "aguanta", "detalle" => "Se paga en 14 meses" },
        { "dimension" => "tecnica", "escenario" => "Carga de baterías entre turnos",
          "resultado" => "aguanta", "detalle" => "Dos horas alcanzan" }
      ],
      reservations: ["Definir el protocolo para los días de lluvia"],
      summary: "Funciona salvo con lluvia; hace falta un plan para esos días.",
      tested_by: User.find_by!(email: "admin@demo.test")
    )
```

Los dos correos (`part2@demo.test`, `admin@demo.test`) son los que siembra el
propio seed (`db/seeds.rb:57`), verificados.

Correlo y mirá que no reviente:

```bash
make rails ARGS="db:seed"
```

- [ ] **Paso 2: sumar el módulo a la guarda de zonas**

En `script/capture_screens.js:605`:

```js
const MODULOS_EN_ZONAS = [/Evaluaci/i, /Ronda de feedback/i, /Postulaci/i, /Reporte/i, /factibilidad/i];
```

La regex tiene que matchear el **nombre del módulo sembrado**, no el kind.
Cada módulo tiene que caer en **exactamente una** de las dos listas
`MODULOS_*`: si no cae en ninguna, `[ZONAS]` falla con
«nadie chequea sus zonas», y si cae en las dos, falla con «se contradicen».

- [ ] **Paso 3: sumar dos capturas**

Una de la cara de ejecución del módulo y otra de la pantalla del testeo.
Reglas que no son negociables:

- Navegar **por link**, no con `goto`: Turbo no dispara `DOMContentLoaded` al
  navegar por link, y un `goto` esconde el bug.
- Después de un clic, esperar `waitForURL` o un selector — `networkidle` se
  calma antes de que Turbo ponga el body nuevo.

- [ ] **Paso 4: correr el recorrido**

```bash
make yarn-build   # sólo si tocaste la hoja o una isla; esta tanda no debería
make screens
```

Esperado: N+2 capturas, sin errores de JS ni respuestas >= 400. Si falla
`[ZONAS]`, revisá que la regex del Paso 2 matchee el nombre sembrado.

**No corras dos `make screens` en paralelo:** borra y reescribe
`tmp/screenshots/` entero al arrancar.

- [ ] **Paso 5: la verificación final, a mano**

```bash
make spec
make screens
```

Y a mano, lo que ninguna guarda ve:

- Abrir el paso a paso del desafío sembrado y **recorrerlo hasta el final**:
  `Flow::Setup` apunta cada paso a una URL y `setup_nav` es lo único que
  avanza. Si el recorrido se corta en el módulo de testing, falta su render
  (Task 4) — y **ni `make spec` ni `make screens` lo avisan**.
- Mirar las dos capturas nuevas.

- [ ] **Paso 6: commit**

```bash
git add db/seeds.rb db/structure.sql script/capture_screens.js
git commit -m "Un testing sembrado y sus dos capturas

La regex de MODULOS_EN_ZONAS matchea el nombre del módulo, no el kind:
cada módulo tiene que caer en exactamente una de las dos listas."
```

---

## Al terminar la tanda

`make spec` y `make screens` en verde sobre la rama, merge `--no-ff` a
`master`, borrar la rama en los dos lados y actualizar `handoff.md`.

La tanda 2 —la tarea de IA, el segundo CHECK y el check `testing_passed`—
sale del mismo spec, §5 y §6.
