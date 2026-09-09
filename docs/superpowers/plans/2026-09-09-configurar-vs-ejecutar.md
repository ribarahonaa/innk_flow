# Configurar y ejecutar: plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que la pantalla de un módulo tenga dos caras —configurar mientras está `pending`, ejecutar una vez tocado— y que configurar un módulo pase a ocurrir en un solo lugar.

**Architecture:** `StepsController#show` despacha a `steps/config/<kind>` o a `steps/<kind>` según `step.touched?`. La configuración se escribe por un solo camino (`PATCH /challenges/:cid/steps/:id`), y el builder deja de ser dueño de `config`, `source_step_id` y `criteria_set_id`. Los editores de criterios y de campos se embeben en la cara de configuración y sus pantallas sueltas se eliminan con redirect.

**Tech Stack:** Rails 7.1.3.4 · Ruby 3.3.0 · PostgreSQL 17 · Vue 3 en islas montadas por `app/javascript/islands.js` · esbuild · Tailwind 4 + DaisyUI 5 · RSpec · Playwright (`make screens`).

**Spec:** `docs/superpowers/specs/2026-09-09-configurar-vs-ejecutar-design.md`

## Global Constraints

- Todo corre en Docker. **Nunca `bundle exec` en el host.** Specs con `make spec`, `make spec-file FILE=…`, `make spec-line FILE=… LINE=…`. `make screens` para el recorrido E2E. `make yarn-build` después de tocar JS o CSS.
- **El código, los comentarios y los mensajes de commit van en español.**
- Los commits van con `ribarahonaa@gmail.com` (ya está en el `git config` local; no lo pises).
- Rama: `configurar-vs-ejecutar`, creada desde `rediseno-tailwind`.
- **No corras `db:seed` nunca.** Hay desafíos de prueba del usuario en la base de desarrollo (`onboarding-remoto`, `optimizacion-de-la-experiencia-de-onboarding`) que no se tocan.
- Pundit, no CanCanCan. Cada policy declara su `Scope` explícitamente.
- Los controllers devuelven **404, nunca 403**.
- Toda lectura del dominio en un spec va dentro de `as_company(company) { … }`, incluido un `.new`.
- HAML no acepta bloques Ruby en una línea (`- coll.each { |e| %li= e }`).
- Nunca una clase de CSS interpolada (`"chip--#{x}"`): Tailwind escanea texto y esa clase no llega a la hoja. Los helpers de `app/helpers/estilos_helper.rb` devuelven el nombre completo, literal. Hay guarda en `spec/lint/clases_interpoladas_spec.rb`.
- `ChallengeStep::ADJUSTABLE_ATTRIBUTES` es `%w[name ai_mode]`. `TOUCHED_STATUSES` es `%w[activating active completed skipped]`.

---

## Estructura de archivos

**Se crean:**

| Archivo | Responsabilidad |
|---|---|
| `app/views/steps/config/_shell.html.haml` | Cabecera y layout común de la cara de configuración |
| `app/views/steps/config/_modulo.html.haml` | El form de Rails: nombre, modo de IA, isla de ajustes, submit |
| `app/views/steps/config/ideation.html.haml` | Cara A de Idear: módulo + editor de campos |
| `app/views/steps/config/evolution.html.haml` | Cara A de Evolución: módulo + gestores |
| `app/views/steps/config/evaluation.html.haml` | Cara A de Evaluación: módulo + criterios + evaluadores |
| `app/views/steps/config/selection.html.haml` | Cara A de Selección: módulo + filtros |
| `app/views/steps/config/reporting.html.haml` | Cara A de Reportería: módulo |
| `app/views/steps/_criterios_editor.html.haml` | Bloque embebible del editor de criterios |
| `app/views/steps/_campos_editor.html.haml` | Bloque embebible del editor de campos |
| `app/views/steps/_asignaciones_evaluadores.html.haml` | Extraído de `steps/evaluation.html.haml` |
| `app/views/steps/_asignaciones_gestores.html.haml` | Extraído de `steps/evolution.html.haml` |
| `app/views/steps/_config_congelada.html.haml` | El resumen de sólo lectura de la cara B |
| `app/javascript/packs/step_settings.js` | Entrypoint de la isla `step-settings` |
| `app/javascript/components/step_settings/step_settings.vue` | Raíz de la isla (era `step_config.vue`) |
| `app/javascript/components/step_settings/config_field.vue` | Movido desde `pipeline_builder/` |
| `app/presenters/step_settings_presenter.rb` | Props de la isla `step-settings` |
| `spec/lint/una_vista_de_configuracion_spec.rb` | Guarda: cuenta declaraciones de isla |

**Se modifican:**

| Archivo | Qué cambia |
|---|---|
| `app/lib/flow/step_settings.rb` | Suma `.filtrar`, `.campos_de` |
| `app/policies/challenge_step_policy.rb` | Suma `configure?` |
| `app/controllers/steps_controller.rb` | `show` despacha por cara; `update` acepta lo estructural |
| `app/controllers/api/v1/pipelines_controller.rb` | `update_existing` deja de escribir config/source/criteria_set |
| `app/presenters/pipeline_presenter.rb` | El hash del step deja de emitir `settings`, `sourceStepId`, `criteriaSetId` |
| `app/javascript/components/pipeline_builder/pipeline_builder.vue` | Pierde el `<aside>` del panel; la tarjeta lleva link |
| `app/lib/flow/setup.rb` | `form_step` y `criteria_step` apuntan a las caras nuevas |
| `app/controllers/step_criteria_controller.rb` | `show` redirige |
| `app/controllers/form_fields_controller.rb` | `show` redirige |
| `script/capture_screens.js` | Capturas de las dos caras |
| `CLAUDE.md`, `README.md` | La sección de configuración |

**Se eliminan:** `app/views/step_criteria/show.html.haml`, `app/views/form_fields/show.html.haml`, `app/javascript/components/pipeline_builder/step_config.vue`, `app/javascript/components/pipeline_builder/config_field.vue`.

---

### Task 0: La rama

- [ ] **Step 1: Crear la rama desde `rediseno-tailwind`**

```bash
cd /home/ribarahonaa/innk_flow
git checkout rediseno-tailwind
git status --short   # tiene que estar limpio
git checkout -b configurar-vs-ejecutar
```

- [ ] **Step 2: Verificar el punto de partida**

Run: `make spec`
Expected: `674 examples, 0 failures`

---

### Task 1: `Flow::StepSettings.filtrar`

Filtra un `config` que llega por parámetros contra el esquema del `kind`, y castea al tipo declarado. Sin esto, `steps#update` sería un escritor de jsonb arbitrario y `cut.value` llegaría como `"4"`.

**Files:**
- Modify: `app/lib/flow/step_settings.rb`
- Test: `spec/lib/flow/step_settings_spec.rb` (crear si no existe)

**Interfaces:**
- Produces: `Flow::StepSettings.filtrar(kind, hash) -> Hash` (claves string, anidado). `Flow::StepSettings.campos_de(kind) -> Array<Hash>` (esencial + avanzado, en ese orden).

- [ ] **Step 1: Escribir el test que falla**

```ruby
# spec/lib/flow/step_settings_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flow::StepSettings do
  describe ".campos_de" do
    it "junta esencial y avanzado, en ese orden" do
      claves = described_class.campos_de("selection").map { |f| f[:key] }

      expect(claves).to eq(%w[source_step_id cut.mode cut.value
                              score_source.combine cut.tie_break])
    end

    it "devuelve vacío para un kind que no existe" do
      expect(described_class.campos_de("inventado")).to eq([])
    end
  end

  describe ".filtrar" do
    it "arma las claves anidadas que declara el esquema" do
      resultado = described_class.filtrar("selection",
                                          "cut" => { "mode" => "top_n", "value" => "4" })

      expect(resultado).to eq("cut" => { "mode" => "top_n", "value" => 4 })
    end

    # El handler hace `.to_f`, así que un string no explota: se arrastra hasta
    # que alguien compara o serializa. Se castea acá, contra el tipo declarado.
    it "castea a número lo que el esquema declara número" do
      resultado = described_class.filtrar("evaluation", "min_assessments" => "3")

      expect(resultado["min_assessments"]).to eq(3)
    end

    it "descarta cualquier clave que el esquema no declare para ese kind" do
      resultado = described_class.filtrar("selection",
                                          "cut" => { "mode" => "top_n" },
                                          "min_assessments" => 9,
                                          "lo_que_sea" => "x")

      expect(resultado).to eq("cut" => { "mode" => "top_n" })
    end

    # `source_step_id` es `column: true`: no vive en config sino en su columna.
    it "no mete en config los campos que son columna" do
      resultado = described_class.filtrar("selection", "source_step_id" => "abc")

      expect(resultado).to eq({})
    end

    it "omite lo ausente y lo vacío en vez de guardar nil" do
      resultado = described_class.filtrar("selection",
                                          "cut" => { "mode" => "manual", "value" => "" })

      expect(resultado).to eq("cut" => { "mode" => "manual" })
    end

    it "no revienta con un kind desconocido" do
      expect(described_class.filtrar("inventado", "x" => 1)).to eq({})
    end
  end
end
```

- [ ] **Step 2: Correrlo y ver que falla**

Run: `make spec-file FILE=spec/lib/flow/step_settings_spec.rb`
Expected: FAIL con `undefined method 'campos_de' for Flow::StepSettings:Module`

- [ ] **Step 3: Implementar**

Al final de `app/lib/flow/step_settings.rb`, dentro del `module StepSettings`, después de la constante `SCHEMA`:

```ruby
    # Los campos declarados para un kind, esenciales primero.
    def self.campos_de(kind)
      grupos = SCHEMA[kind.to_s]
      return [] if grupos.nil?

      Array(grupos[:essential]) + Array(grupos[:advanced])
    end

    # Filtra un `config` que llegó por parámetros contra lo que el esquema
    # declara para ese kind, y castea al tipo declarado.
    #
    # Dos motivos, los dos aprendidos a la mala:
    #
    #   · `params.permit(config: {})` es un escritor de jsonb arbitrario.
    #   · Un `cut.value` que llega `"4"` no explota —el handler hace `.to_f`—
    #     así que el string se arrastra hasta que alguien compara o serializa.
    #
    # Los campos `column: true` (source_step_id, criteria_set_id) NO son
    # config: viven en su columna y se permiten aparte.
    def self.filtrar(kind, hash)
      entrada = (hash || {}).to_h.deep_stringify_keys

      campos_de(kind).reject { |campo| campo[:column] }.each_with_object({}) do |campo, acc|
        segmentos = campo[:key].to_s.split(".")
        valor = entrada.dig(*segmentos)
        next if valor.nil? || valor == ""

        escribir(acc, segmentos, castear(valor, campo[:type]))
      end
    end

    # El default del esquema es número: en `config_field.vue` el `v-else` es un
    # input numérico. Se espeja acá para que la UI y el server no discrepen.
    def self.castear(valor, tipo)
      case tipo.to_s
      when "select" then valor.to_s
      when "multi_select" then Array(valor).map(&:to_s)
      when "boolean" then ActiveModel::Type::Boolean.new.cast(valor).present?
      else valor.to_s.include?(".") ? valor.to_f : valor.to_i
      end
    end

    def self.escribir(hash, segmentos, valor)
      *padres, ultimo = segmentos
      nodo = padres.reduce(hash) { |acc, seg| acc[seg] ||= {} }
      nodo[ultimo] = valor
    end

    private_class_method :castear, :escribir
```

- [ ] **Step 4: Correr y ver que pasa**

Run: `make spec-file FILE=spec/lib/flow/step_settings_spec.rb`
Expected: `7 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add app/lib/flow/step_settings.rb spec/lib/flow/step_settings_spec.rb
git commit -m "El esquema filtra y castea el config que llega por parámetros

Sin esto el endpoint de configuración sería un escritor de jsonb arbitrario,
y un \`cut.value\` que llega \"4\" no explota —el handler hace .to_f— así que
el string se arrastra hasta que alguien compara o serializa."
```

---

### Task 2: `configure?` y `steps#update` estructural

**Files:**
- Modify: `app/policies/challenge_step_policy.rb`
- Modify: `app/controllers/steps_controller.rb:36-46` (`update`) y `:115-117` (`step_params`)
- Test: `spec/requests/step_config_spec.rb` (crear)

**Interfaces:**
- Consumes: `Flow::StepSettings.filtrar` (Task 1)
- Produces: `ChallengeStepPolicy#configure?`. `PATCH /challenges/:challenge_id/steps/:id` acepta `challenge_step[name]`, `[ai_mode]`, `[source_step_id]`, `[criteria_set_id]` y `[config]` anidado.

- [ ] **Step 1: Escribir el test que falla**

```ruby
# spec/requests/step_config_spec.rb
# frozen_string_literal: true

require "rails_helper"

# El ÚNICO camino de escritura de la configuración de un módulo.
RSpec.describe "configurar un módulo", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  let!(:admin) do
    without_tenant do
      u = create(:user, email: "admin@test.dev", name: "Ana Admin")
      create(:membership, :admin, company: company, user: u)
      u
    end
  end

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma", ai_default_mode: "human")
      seed_form!(c.steps.create!(kind: "ideation", position: 1))
      c.steps.create!(kind: "evaluation", position: 2, name: "Comité")
      c.steps.create!(kind: "selection", position: 3, name: "Corte")
      c
    end
  end

  def corte = as_company(company) { challenge.steps.reload.find(&:selection?) }

  before { sign_in(admin, company: company) }

  it "guarda el corte con los tipos que declara el esquema" do
    patch challenge_step_path(challenge, corte),
          params: { challenge_step: { config: { cut: { mode: "top_n", value: "4" } } } }

    expect(corte.config).to eq("cut" => { "mode" => "top_n", "value" => 4 })
  end

  it "descarta claves que el esquema no declara para ese kind" do
    patch challenge_step_path(challenge, corte),
          params: { challenge_step: { config: { cut: { mode: "top_n" }, colado: "x" } } }

    expect(corte.config).to eq("cut" => { "mode" => "top_n" })
  end

  it "guarda el módulo de origen del puntaje, que es columna y no config" do
    evaluacion = as_company(company) { challenge.steps.reload.find(&:evaluation?) }

    patch challenge_step_path(challenge, corte),
          params: { challenge_step: { source_step_id: evaluacion.id } }

    expect(corte.source_step_id).to eq(evaluacion.id)
  end

  it "sigue guardando nombre y modo de IA, como hasta ahora" do
    patch challenge_step_path(challenge, corte),
          params: { challenge_step: { name: "Corte final", ai_mode: "ai_assisted" } }

    expect(corte.name).to eq("Corte final")
    expect(corte.ai_mode).to eq("ai_assisted")
  end

  describe "con el módulo ya en curso" do
    before do
      as_company(company) do
        create(:idea, challenge: challenge, author: admin, status: "active")
          .update!(submitted_at: Time.current)
        challenge.pipeline.start!
      end
    end

    def idear = as_company(company) { challenge.steps.reload.find(&:ideation?) }

    # `config` es FROZEN_ATTRIBUTE: lo cuida el modelo, no el controller, para
    # que no haya dos copias de la regla que se puedan desincronizar.
    it "rechaza un cambio estructural" do
      antes = idear.config

      patch challenge_step_path(challenge, idear),
            params: { challenge_step: { config: { min_ideas: 99 } } }

      expect(idear.config).to eq(antes)
      expect(flash[:alert]).to be_present
    end

    it "acepta el cambio de modo de IA, que es política operativa" do
      patch challenge_step_path(challenge, idear),
            params: { challenge_step: { ai_mode: "ai_assisted" } }

      expect(idear.ai_mode).to eq("ai_assisted")
    end
  end

  # `update_pipeline?` suma `&& !closed? && !archived?` sobre `manager?`. Ésa
  # es toda la diferencia entre las dos autorizaciones, y es la que importa.
  describe "con el desafío cerrado" do
    before { as_company(company) { challenge.update!(status: "closed") } }

    it "no deja reescribir la configuración" do
      antes = corte.config

      patch challenge_step_path(challenge, corte),
            params: { challenge_step: { config: { cut: { mode: "top_n", value: "9" } } } }

      expect(corte.config).to eq(antes)
    end

    it "sí deja ajustar el modo de IA" do
      patch challenge_step_path(challenge, corte),
            params: { challenge_step: { ai_mode: "human" } }

      expect(corte.ai_mode).to eq("human")
    end
  end
end
```

- [ ] **Step 2: Correrlo y ver que falla**

Run: `make spec-file FILE=spec/requests/step_config_spec.rb`
Expected: FAIL — el `config` no se guarda (hoy `step_params` sólo permite `name` y `ai_mode`).

- [ ] **Step 3: Sumar el predicado a la policy**

En `app/policies/challenge_step_policy.rb`, junto a `advance?`:

```ruby
  # Reescribir la configuración de un módulo, que es más que ajustarlo en
  # curso: `update_pipeline?` suma `&& !closed? && !archived?` sobre
  # `manager?`. Con el desafío cerrado, cambiar el modo de IA sigue siendo
  # legítimo —es política operativa— y reescribir el corte no.
  def configure? = ChallengePolicy.new(membership, record.challenge).update_pipeline?
```

- [ ] **Step 4: Cambiar `update` y `step_params`**

En `app/controllers/steps_controller.rb`, reemplazar `update` y `step_params`:

```ruby
  # El ÚNICO camino de escritura de la configuración de un módulo.
  #
  # Autoriza según lo que llega, porque las dos cosas no piden lo mismo: el
  # selector de modo de IA de la cara de ejecución pide `advance?`, y
  # reescribir la configuración pide `configure?`.
  #
  # El congelamiento NO se revisa acá: lo impone `FROZEN_ATTRIBUTES` como
  # validación de modelo. Repetirlo en el controller sería una segunda copia
  # de la regla, que es exactamente como se desincronizan.
  def update
    authorize @step, estructural? ? :configure? : :advance?

    if @step.update(step_params)
      redirect_to challenge_step_path(@step.challenge, @step), notice: "Módulo actualizado."
    else
      redirect_to challenge_step_path(@step.challenge, @step),
                  alert: @step.errors.full_messages.to_sentence
    end
  end
```

Y en la sección privada, reemplazando `step_params`:

```ruby
  ESTRUCTURALES = %w[config source_step_id criteria_set_id].freeze

  def estructural? = crudos.keys.intersect?(ESTRUCTURALES)

  # Ojo con el default: `params.fetch(:challenge_step, {})` devuelve un Hash
  # pelado cuando la clave falta, y `to_unsafe_h` no existe ahí.
  def crudos
    @crudos ||= params.fetch(:challenge_step, ActionController::Parameters.new)
                      .to_unsafe_h.stringify_keys
  end

  # `config` no se permite con `permit(config: {})` —eso es un escritor de
  # jsonb arbitrario—: se filtra contra el esquema del kind, que además
  # castea al tipo declarado.
  def step_params
    permitidos = params.require(:challenge_step)
                       .permit(*ChallengeStep::ADJUSTABLE_ATTRIBUTES,
                               :source_step_id, :criteria_set_id)

    return permitidos unless crudos.key?("config")

    permitidos.merge(config: Flow::StepSettings.filtrar(@step.kind, crudos["config"]))
  end
```

- [ ] **Step 5: Correr y ver que pasa**

Run: `make spec-file FILE=spec/requests/step_config_spec.rb`
Expected: `8 examples, 0 failures`

- [ ] **Step 6: Correr la suite entera, que hay un `update` que ya existía**

Run: `make spec`
Expected: `0 failures`. Si `spec/requests/selection_screen_spec.rb` falla por el texto del notice, actualizá ese `expect` — el mensaje ya no nombra sólo a la IA.

- [ ] **Step 7: Commit**

```bash
git add app/policies/challenge_step_policy.rb app/controllers/steps_controller.rb spec/requests/step_config_spec.rb
git commit -m "steps#update es el único camino de escritura de la configuración

Autoriza según lo que llega: \`advance?\` para el modo de IA, \`configure?\`
para lo estructural. La única diferencia real entre los dos predicados es que
\`update_pipeline?\` suma !closed? && !archived?, y es justo la que se busca.

El congelamiento sigue donde estaba —FROZEN_ATTRIBUTES, validación de modelo—
para no tener dos copias de la regla."
```

---

### Task 3: Cortarle al builder la propiedad de la configuración

La regresión más cara del cambio, y la que ningún test actual atrapa: si el builder sigue mandando `settings` desde props cargadas antes, guardar el flujo revierte lo que configuraste. `lock_version` no lo ataja porque es del desafío y un PATCH al módulo no lo incrementa.

**Files:**
- Modify: `app/controllers/api/v1/pipelines_controller.rb:103-125`
- Modify: `app/presenters/pipeline_presenter.rb:70-95`
- Test: `spec/requests/api/v1/pipeline_no_pisa_config_spec.rb` (crear)

**Interfaces:**
- Consumes: `PATCH /challenges/:cid/steps/:id` (Task 2)
- Produces: el hash de step del `PipelinePresenter` ya no trae `settings`, `sourceStepId` ni `criteriaSetId`.

- [ ] **Step 1: Escribir el test que falla**

```ruby
# spec/requests/api/v1/pipeline_no_pisa_config_spec.rb
# frozen_string_literal: true

require "rails_helper"

# La regresión más cara de mover la configuración al módulo: el builder guarda
# la lista ENTERA de steps. Si sigue mandando `settings` desde props cargadas
# antes de que alguien configurara el módulo, guardar el flujo lo revierte.
#
# El bloqueo optimista no lo ataja: `lock_version` es del desafío y un PATCH
# al módulo no lo incrementa.
RSpec.describe "guardar el flujo no pisa la configuración de un módulo", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  let!(:admin) do
    without_tenant do
      u = create(:user, email: "admin@test.dev", name: "Ana Admin")
      create(:membership, :admin, company: company, user: u)
      u
    end
  end

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma", ai_default_mode: "human")
      seed_form!(c.steps.create!(kind: "ideation", position: 1))
      c.steps.create!(kind: "selection", position: 2, name: "Corte")
      c
    end
  end

  def corte = as_company(company) { challenge.steps.reload.find(&:selection?) }
  def idear = as_company(company) { challenge.steps.reload.find(&:ideation?) }

  before { sign_in(admin, company: company) }

  it "conserva el config aunque el builder mande el viejo" do
    patch challenge_step_path(challenge, corte),
          params: { challenge_step: { config: { cut: { mode: "top_n", value: "4" } } } }

    # El builder guarda con las props de antes: `settings` vacío.
    put api_v1_challenge_pipeline_path(challenge),
        params: { lock_version: challenge.reload.lock_version,
                  steps: [{ id: idear.id, kind: "ideation", name: idear.name },
                          { id: corte.id, kind: "selection", name: "Corte", settings: {} }] },
        as: :json

    expect(response).to have_http_status(:ok)
    expect(corte.config).to eq("cut" => { "mode" => "top_n", "value" => 4 })
  end

  it "conserva el set de criterios aunque el builder mande null" do
    set = as_company(company) do
      s = CriteriaSet.create!(name: "Filtros", scope: "inline", owner_step: corte, status: "valid")
      s.criteria.create!(name: "¿Claro?", key: "claro", weight: 1, source: "manual",
                         scale_type: "boolean")
      s
    end
    patch challenge_step_path(challenge, corte),
          params: { challenge_step: { criteria_set_id: set.id } }

    put api_v1_challenge_pipeline_path(challenge),
        params: { lock_version: challenge.reload.lock_version,
                  steps: [{ id: idear.id, kind: "ideation", name: idear.name },
                          { id: corte.id, kind: "selection", name: "Corte", criteriaSetId: nil }] },
        as: :json

    expect(corte.criteria_set_id).to eq(set.id)
  end

  it "sigue guardando el nombre y el orden, que son suyos" do
    put api_v1_challenge_pipeline_path(challenge),
        params: { lock_version: challenge.reload.lock_version,
                  steps: [{ id: idear.id, kind: "ideation", name: idear.name },
                          { id: corte.id, kind: "selection", name: "Corte final" }] },
        as: :json

    expect(corte.name).to eq("Corte final")
  end

  it "no publica en las props lo que dejó de ser suyo" do
    get builder_challenge_path(challenge)

    props = JSON.parse(response.body[/data-props="([^"]*)"/, 1].gsub("&quot;", '"'))
    paso = props["steps"].find { |s| s["kind"] == "selection" }

    expect(paso).not_to have_key("settings")
    expect(paso).not_to have_key("criteriaSetId")
    expect(paso).not_to have_key("sourceStepId")
  end
end
```

- [ ] **Step 2: Correrlo y ver que falla**

Run: `make spec-file FILE=spec/requests/api/v1/pipeline_no_pisa_config_spec.rb`
Expected: FAIL — el config vuelve a `{}` y las props todavía traen `settings`.

- [ ] **Step 3: Que `update_existing` deje de escribirlo**

En `app/controllers/api/v1/pipelines_controller.rb`, reemplazar el cuerpo del bloque de `update_existing` (líneas 110-119):

```ruby
          # El builder es dueño del ARMADO del flujo: kind, orden, alta y baja.
          # La configuración de un módulo —config, criterios, de dónde saca el
          # puntaje— se escribe en la pantalla del módulo, por `steps#update`.
          #
          # Si esto siguiera escribiéndolas, guardar el flujo con props
          # cargadas antes revertiría lo configurado, y `lock_version` no lo
          # atajaría: es del desafío, y un PATCH al módulo no lo incrementa.
          step.name = attrs[:name] if attrs.key?(:name) && attrs[:name].present?
          step.ai_mode = attrs[:aiMode].presence if attrs.key?(:aiMode)
```

- [ ] **Step 4: Que el presenter deje de publicarlo**

En `app/presenters/pipeline_presenter.rb`, en el hash del step, borrar las tres líneas `sourceStepId:`, `criteriaSetId:` y `settings:`. Dejar `criteriaSetName:`, `touched:`, `locked:` y `removable:`, que la tarjeta sigue usando. Sumar arriba del hash:

```ruby
    # Sin `settings`, `sourceStepId` ni `criteriaSetId`: son de la pantalla del
    # módulo. Publicarlas acá es lo que permitía que guardar el flujo con props
    # viejas revirtiera la configuración.
```

- [ ] **Step 5: Correr y ver que pasa**

Run: `make spec-file FILE=spec/requests/api/v1/pipeline_no_pisa_config_spec.rb`
Expected: `4 examples, 0 failures`

- [ ] **Step 6: Correr la suite**

Run: `make spec`
Expected: fallan specs del builder que esperaban `settings` en las props. Actualizalos: esas claves ya no son suyas.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/api/v1/pipelines_controller.rb app/presenters/pipeline_presenter.rb spec/
git commit -m "El builder deja de ser dueño de la configuración de un módulo

Guarda la lista entera de steps. Con la configuración mudada a la pantalla del
módulo, seguir mandando \`settings\` desde props cargadas antes revertía lo
configurado, y el bloqueo optimista no lo ataja: \`lock_version\` es del
desafío y un PATCH al módulo no lo incrementa.

Ahora el builder es dueño del armado —kind, orden, alta y baja— y nada más."
```

---

### Task 4: La isla `step-settings`

Mudanza, no reescritura: `depends_on`, el filtrado de `source_step_id` por posición y los defaults ya están escritos y probados. Lo que cambia es que la isla **pierde su guardado propio** y renderiza `name=` para que la mande el form de Rails.

**Files:**
- Create: `app/javascript/components/step_settings/step_settings.vue`, `app/javascript/components/step_settings/config_field.vue`, `app/javascript/packs/step_settings.js`, `app/presenters/step_settings_presenter.rb`
- Delete: `app/javascript/components/pipeline_builder/step_config.vue`, `app/javascript/components/pipeline_builder/config_field.vue`
- Modify: `app/javascript/components/pipeline_builder/pipeline_builder.vue`

**Interfaces:**
- Produces: isla `step-settings`, props `{ kind, stepId, settings, sourceStepId, steps, schema }`. Renderiza inputs con `name="challenge_step[config][<ruta>]"` y `name="challenge_step[source_step_id]"`.

- [ ] **Step 1: Mover los dos componentes**

```bash
mkdir -p app/javascript/components/step_settings
git mv app/javascript/components/pipeline_builder/config_field.vue app/javascript/components/step_settings/config_field.vue
git mv app/javascript/components/pipeline_builder/step_config.vue app/javascript/components/step_settings/step_settings.vue
```

- [ ] **Step 2: Convertir `step_settings.vue` en la raíz de la isla**

En `app/javascript/components/step_settings/step_settings.vue`:

1. `name: 'StepConfig'` → `name: 'StepSettings'`.
2. Borrar del `<template>` todo lo anterior al comentario `<!-- Lo propio del kind, desde el esquema del server -->`: el nombre, el modo de IA y el bloque de criterios pasan a ser HAML de la cara de configuración. Queda sólo el bloque `essential` y el `<details>` de `advanced`.
3. Los props pasan a ser los de la isla, y `step` se arma de ellos:

```js
  props: {
    kind: { type: String, required: true },
    stepId: { type: String, required: true },
    settings: { type: Object, default: () => ({}) },
    sourceStepId: { type: String, default: null },
    steps: { type: Array, default: () => [] },
    schema: { type: Object, required: true }
  },

  // Las props son el estado INICIAL, no el estado: Vue no las hace reactivas
  // en la raíz. Se copia a data() una vez y se trabaja sobre la copia.
  data() {
    return {
      step: {
        id: this.stepId,
        kind: this.kind,
        settings: JSON.parse(JSON.stringify(this.settings)),
        sourceStepId: this.sourceStepId,
        locked: false
      }
    };
  },
```

4. En el `<template>`, los dos `<config-field>` pierden `:disabled="step.locked"` (la cara de configuración sólo existe si el módulo está pendiente) y ganan `:fields="todos"`, que ya está.

- [ ] **Step 3: Que `config_field.vue` renderice `name=`**

En `app/javascript/components/step_settings/config_field.vue`, agregar al `computed`:

```js
    // El input viaja DENTRO del form de Rails: la isla no guarda, renderiza.
    // Un solo botón «Guardar el módulo» manda nombre, modo de IA y ajustes
    // juntos contra un solo endpoint.
    inputName() {
      if (this.field.column === true) {
        return `challenge_step[${this.field.key}]`;
      }
      const rutas = this.field.key.split('.').map((s) => `[${s}]`).join('');
      return `challenge_step[config]${rutas}`;
    },
```

Y en el `<template>`, sumar `:name="inputName"` a los cuatro controles (`select`, `select multiple`, `input[type=checkbox]`, `input[type=number]`).

Para el checkbox hace falta además el hidden que Rails espera, justo antes del input:

```html
      <input type="hidden" :name="inputName" value="0" />
```

- [ ] **Step 4: Escribir el entrypoint**

```js
// app/javascript/packs/step_settings.js
// Isla de los ajustes de un módulo. Renderiza los campos que declara
// Flow::StepSettings DENTRO del form de Rails: no guarda por su cuenta.
import StepSettings from '../components/step_settings/step_settings.vue';
import { mountIsland } from '../islands';

mountIsland('step-settings', StepSettings);
```

- [ ] **Step 5: El presenter de las props**

```ruby
# app/presenters/step_settings_presenter.rb
# frozen_string_literal: true

# Props de la isla `step-settings`: los ajustes de UN módulo.
#
# `steps` viaja porque `source_step_id` se filtra contra la posición: una
# selección sólo puede tomar puntaje de una evaluación ANTERIOR.
class StepSettingsPresenter
  def initialize(step, membership:)
    @step = step
    @membership = membership
  end

  attr_reader :step, :membership

  def as_json(*)
    {
      kind: step.kind,
      stepId: step.id,
      settings: step.config || {},
      sourceStepId: step.source_step_id,
      steps: step.challenge.steps.ordered.map do |s|
        { id: s.id, slug: s.slug, kind: s.kind, name: s.name, position: s.position.to_f }
      end,
      schema: esquema
    }
  end

  private

  # El mismo transform que ya hace PipelinePresenter#settings_schema: las
  # opciones que apuntan a otros módulos se resuelven contra este desafío.
  def esquema
    PipelinePresenter.new(step.challenge, membership: membership).settings_schema
  end
end
```

> Si `PipelinePresenter#settings_schema` es privado, hacelo público (`public :settings_schema` o moverlo arriba del `private`). Es el mismo dato, y duplicarlo sería tener dos esquemas que se desincronizan.

- [ ] **Step 6: Sacarle el panel al builder**

En `app/javascript/components/pipeline_builder/pipeline_builder.vue`:

1. Borrar el `<aside class="builder__config card">` entero (el bloque del Step 1 de esta tarea).
2. Borrar el `import StepConfig` y su entrada en `components`.
3. En la tarjeta del módulo, sumar el link a configurar. Dentro del `<li>` de cada step, después del nombre:

```html
        <a
          v-if="step.id"
          class="step-card__config"
          :href="`/challenges/${localChallenge.slug}/steps/${step.id}`"
        >Configurar →</a>
        <span v-else class="step-card__unsaved">sin guardar</span>
```

4. Borrar de `data()`/`computed` lo que quedó sin uso: `selected`, `settingsSchema`, `criteriaSets`, `aiModes`, si ya no los lee nadie.

- [ ] **Step 7: Compilar y correr**

Run: `make yarn-build && make spec`
Expected: compila sin error; `0 failures`.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Los ajustes de un módulo son una isla propia, no un panel del builder

Es una mudanza y no una reescritura: depends_on, el filtrado de source_step_id
por posición y los defaults ya estaban escritos y probados.

Lo que cambia es que la isla pierde su guardado propio. Renderiza
name=\"challenge_step[config][cut][mode]\" dentro del form de Rails, así que
hay un solo botón y un solo endpoint."
```

---

### Task 5: La cara de configuración

**Files:**
- Create: `app/views/steps/config/_shell.html.haml`, `_modulo.html.haml`, `ideation.html.haml`, `evolution.html.haml`, `evaluation.html.haml`, `selection.html.haml`, `reporting.html.haml`
- Modify: `app/controllers/steps_controller.rb` (`show`)
- Test: `spec/requests/dos_caras_spec.rb` (crear)

**Interfaces:**
- Consumes: isla `step-settings` (Task 4), `PATCH steps#update` (Task 2)
- Produces: `steps/config/<kind>` para los cinco kinds.

- [ ] **Step 1: Escribir el test que falla**

```ruby
# spec/requests/dos_caras_spec.rb
# frozen_string_literal: true

require "rails_helper"

# La pantalla de un módulo tiene dos caras y la decide `step.touched?`, no el
# estado del desafío: un desafío en curso sigue teniendo módulos pendientes
# más adelante, y ésos son configurables.
RSpec.describe "las dos caras de un módulo", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  let!(:admin) do
    without_tenant do
      u = create(:user, email: "admin@test.dev", name: "Ana Admin")
      create(:membership, :admin, company: company, user: u)
      u
    end
  end

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma", ai_default_mode: "human")
      seed_form!(c.steps.create!(kind: "ideation", position: 1))
      c.steps.create!(kind: "evaluation", position: 2, name: "Comité")
      c.steps.create!(kind: "selection", position: 3, name: "Corte")
      c.steps.create!(kind: "reporting", position: 4, name: "Informe")
      c.steps.create!(kind: "evolution", position: 5, name: "Mejorar")
      c
    end
  end

  def paso(kind) = as_company(company) { challenge.steps.reload.find { |s| s.kind == kind } }

  before { sign_in(admin, company: company) }

  describe "cara A: el módulo está pendiente" do
    it "monta la isla de ajustes en los cinco kinds" do
      %w[ideation evolution evaluation selection reporting].each do |kind|
        get challenge_step_path(challenge, paso(kind))

        expect(response.body).to include('data-island="step-settings"'),
                                 "faltó la isla en #{kind}"
      end
    end

    it "trae el form del módulo, con nombre y modo de IA" do
      get challenge_step_path(challenge, paso("selection"))

      expect(response.body).to include('name="challenge_step[name]"')
      expect(response.body).to include('name="challenge_step[ai_mode]"')
    end

    it "no muestra el trabajo del módulo, que todavía no existe" do
      get challenge_step_path(challenge, paso("selection"))

      expect(response.body).not_to include("Confirmar el corte")
    end
  end

  describe "cara B: el módulo ya arrancó" do
    before do
      as_company(company) do
        create(:idea, challenge: challenge, author: admin, status: "active")
          .update!(submitted_at: Time.current)
        challenge.pipeline.start!
      end
    end

    it "no monta la isla de ajustes" do
      get challenge_step_path(challenge, paso("ideation"))

      expect(response.body).not_to include('data-island="step-settings"')
    end

    it "muestra la configuración congelada" do
      get challenge_step_path(challenge, paso("ideation"))

      expect(response.body).to include("quedó fijado")
    end

    # Las tres cosas que siguen vivas: modo de IA, nombre y asignaciones.
    it "deja ajustar el modo de IA" do
      get challenge_step_path(challenge, paso("ideation"))

      expect(response.body).to include('name="challenge_step[ai_mode]"')
    end

    it "los módulos de más adelante siguen en cara A" do
      get challenge_step_path(challenge, paso("selection"))

      expect(response.body).to include('data-island="step-settings"')
    end
  end
end
```

- [ ] **Step 2: Correrlo y ver que falla**

Run: `make spec-file FILE=spec/requests/dos_caras_spec.rb`
Expected: FAIL — no existe `data-island="step-settings"` en ninguna pantalla.

- [ ] **Step 3: Despachar por cara en el controller**

En `app/controllers/steps_controller.rb#show`, reemplazar la última línea (`render "steps/#{@step.kind}"`):

```ruby
    # Dos caras, y la decide el módulo y no el desafío: uno en curso sigue
    # teniendo módulos pendientes más adelante, y ésos son configurables. Es
    # la misma regla de la línea de agua que ya aplica el pipeline.
    if @step.touched?
      render "steps/#{@step.kind}"
    else
      @settings_props = StepSettingsPresenter.new(@step, membership: current_membership).as_json
      render "steps/config/#{@step.kind}"
    end
```

- [ ] **Step 4: El shell y el form del módulo**

```haml
-# app/views/steps/config/_shell.html.haml
-# Cabecera de la cara de configuración. La de ejecución es `steps/_header`:
-# son dos cosas distintas y compartir una las volvía condicional adentro.
.page-head
  %div
    %p.breadcrumb
      = link_to "Desafíos", challenges_path
      = " › "
      = link_to step.challenge.name, challenge_path(step.challenge)
      = " › "
      = link_to "Flujo", builder_challenge_path(step.challenge)
    %h1.page-title= step.name
    %p.muted
      %span{ class: chip_de_estado(step.status) }= t("flow.statuses.#{step.status}")
      %span= " · #{t("flow.kinds.#{step.kind}")}"
      %span  · configurá cómo va a funcionar antes de que arranque
```

```haml
-# app/views/steps/config/_modulo.html.haml
-# El form de Rails que guarda nombre, modo de IA y los ajustes del kind, todo
-# junto. La isla `step-settings` renderiza los campos del esquema ADENTRO de
-# este form: no guarda por su cuenta, así que hay un solo botón y un solo
-# endpoint.
= form_with model: step, url: challenge_step_path(step.challenge, step), method: :patch do |f|
  .card
    %h2.section-title El módulo
    .field
      = f.label :name, "Nombre"
      = f.text_field :name, required: true
    .field
      = f.label :ai_mode, "Modo de IA"
      = f.select :ai_mode,
                 Challenge::AI_MODES.map { |m| [t("flow.ai_modes.#{m}"), m] },
                 include_blank: "Heredar del desafío (#{t("flow.ai_modes.#{step.challenge.ai_default_mode}")})"
      %p.field-hint= t("flow.ai_mode_descriptions.#{step.effective_ai_mode}")

    %div{ "data-island": "step-settings", data: { props: props.to_json } }
      .island-placeholder
        %p.muted Cargando los ajustes…

    .form-actions
      = f.submit "Guardar el módulo", class: "btn btn-primary"

= javascript_include_tag "packs/step_settings", defer: true, nonce: content_security_policy_nonce
```

- [ ] **Step 5: Las cinco vistas**

```haml
-# app/views/steps/config/reporting.html.haml
- content_for :title, "Configurar · #{@step.name}"
= render "steps/config/shell", step: @step
= render "shared/setup_progress", challenge: @challenge, current: :flow
= render "steps/config/modulo", step: @step, props: @settings_props
```

Las otras cuatro, completas. Los bloques que todavía no existen los crean las
tareas 6, 7 y 8: escribí **ahora** sólo las tres primeras líneas de cada una, y
sumá el `render` que falta cuando su tarea cree el partial.

```haml
-# app/views/steps/config/ideation.html.haml
- content_for :title, "Configurar · #{@step.name}"
= render "steps/config/shell", step: @step
= render "shared/setup_progress", challenge: @challenge, current: :form
= render "steps/config/modulo", step: @step, props: @settings_props
-# ↓ lo suma la Task 7
= render "steps/campos_editor", step: @step
```

```haml
-# app/views/steps/config/evolution.html.haml
- content_for :title, "Configurar · #{@step.name}"
= render "steps/config/shell", step: @step
= render "shared/setup_progress", challenge: @challenge, current: :flow
= render "steps/config/modulo", step: @step, props: @settings_props
-# ↓ lo suma la Task 8
= render "steps/asignaciones_gestores", step: @step, candidates: @gestor_candidates
```

```haml
-# app/views/steps/config/evaluation.html.haml
- content_for :title, "Configurar · #{@step.name}"
= render "steps/config/shell", step: @step
= render "shared/setup_progress", challenge: @challenge, current: :criteria
= render "steps/config/modulo", step: @step, props: @settings_props
-# ↓ los suman las Tasks 6 y 8
= render "steps/criterios_editor", step: @step
= render "steps/asignaciones_evaluadores", step: @step, assignable: @assignable
```

```haml
-# app/views/steps/config/selection.html.haml
- content_for :title, "Configurar · #{@step.name}"
= render "steps/config/shell", step: @step
= render "shared/setup_progress", challenge: @challenge, current: :criteria
= render "steps/config/modulo", step: @step, props: @settings_props
-# ↓ lo suma la Task 6
= render "steps/criterios_editor", step: @step
```

- [ ] **Step 6: El bloque de configuración congelada de la cara B**

```haml
-# app/views/steps/_config_congelada.html.haml
-# La configuración en la cara de ejecución: se muestra, no se toca.
-#
-# Decirlo importa: sin esta línea, la ausencia de controles se lee como que
-# falta el control, que es exactamente el reporte con el que empezó todo.
.card
  .section-head
    %h2.section-title Cómo quedó configurado
  %p.field-hint 🔒 Quedó fijado cuando arrancó el módulo. Se pueden cambiar el nombre, el modo de IA y quién participa; la regla no.
  %ul.field-list
    - Flow::StepSettings.campos_de(step.kind).each do |campo|
      - valor = campo[:column] ? step.public_send(campo[:key]) : step.settings.dig(*campo[:key].to_s.split("."))
      - next if valor.nil? || valor == ""
      %li.field-list__item
        %span= campo[:label]
        %span.field-list__type= valor
```

Sumalo arriba de `steps/_header` en las cinco vistas de ejecución (`app/views/steps/<kind>.html.haml`). En `selection.html.haml` reemplaza al bloque «Cómo se decide» sólo en su parte de sólo lectura: el detalle del corte con su fuente de puntaje ya está resuelto ahí y se conserva.

- [ ] **Step 7: Correr y ver que pasa**

Run: `make spec-file FILE=spec/requests/dos_caras_spec.rb`
Expected: `7 examples, 0 failures`

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "La pantalla del módulo tiene dos caras

Pendiente: la pantalla ES la configuración. Tocado: es el trabajo, con la
configuración como resumen con candado.

La cara la decide \`step.touched?\` y no el estado del desafío, porque uno en
curso sigue teniendo módulos pendientes más adelante y ésos son configurables
—la misma regla de la línea de agua que ya aplica el pipeline—."
```

---

### Task 6: Los criterios, embebidos

**Files:**
- Create: `app/views/steps/_criterios_editor.html.haml`
- Delete: `app/views/step_criteria/show.html.haml`
- Modify: `app/controllers/step_criteria_controller.rb`, `app/controllers/steps_controller.rb`, `app/views/steps/config/evaluation.html.haml`, `selection.html.haml`

**Interfaces:**
- Consumes: `CriteriaSetPresenter.new(set, membership:, back_url:)`
- Produces: partial `steps/_criterios_editor` que recibe `step`.

- [ ] **Step 1: Escribir el test que falla**

Agregá a `spec/requests/dos_caras_spec.rb`, dentro de `describe "cara A"`:

```ruby
    it "trae el editor de criterios en los dos kinds que puntúan o filtran" do
      %w[evaluation selection].each do |kind|
        get challenge_step_path(challenge, paso(kind))

        expect(response.body).to include("Criterios propios de este módulo")
          .or include("todavía no tiene criterios propios")
      end
    end

    it "la pantalla suelta de criterios redirige al módulo" do
      get challenge_step_criteria_path(challenge, paso("selection"))

      expect(response).to redirect_to(challenge_step_path(challenge, paso("selection")))
    end
```

- [ ] **Step 2: Correr y ver que falla**

Run: `make spec-file FILE=spec/requests/dos_caras_spec.rb`
Expected: FAIL en los dos.

- [ ] **Step 3: Extraer el partial**

Creá `app/views/steps/_criterios_editor.html.haml` con **el contenido de `app/views/step_criteria/show.html.haml` desde el `- if @set.nil?` hasta el `javascript_include_tag`**, cambiando `@set` por `set`, `@step` por `step`, `@challenge` por `step.challenge` y `@props` por `props`. Encabezalo con:

```haml
-# El editor de criterios, embebido en la cara de configuración del módulo.
-#
-# Antes era pantalla propia. Configurar un módulo exigía rebotar entre cuatro
-# pantallas y ninguna era la del módulo; ésa era la queja que originó todo.
- set = step.criteria_set&.library? ? nil : step.criteria_set
- props = set ? CriteriaSetPresenter.new(set, membership: current_membership, back_url: challenge_step_path(step.challenge, step)).as_json : nil
.card
  .section-head
    %h2.section-title= step.selection? ? "Los filtros" : "Los criterios"
  %p.muted= step.selection? ? "Condiciones que la idea tiene que cumplir para avanzar. Se aplican antes del corte." : "Con qué se puntúa cada idea en este módulo."
```

- [ ] **Step 4: Renderizarlo en las dos vistas**

Sumá a `app/views/steps/config/evaluation.html.haml` y `selection.html.haml`, antes del cierre:

```haml
= render "steps/criterios_editor", step: @step
```

Y en `StepsController#show`, dentro de la rama de configuración:

```ruby
      @pending_suggestions = AiSuggestion.pending_review.where(challenge_step_id: @step.id).recent
```

(ya está en `show`; verificá que siga cargándose para la cara A).

- [ ] **Step 5: Redirigir la pantalla vieja**

En `app/controllers/step_criteria_controller.rb`, reemplazar `show`:

```ruby
  # Los criterios se configuran en la pantalla del módulo. Esta URL vivía en
  # links, marcadores y `back_url`, así que redirige en vez de dar 404: un 404
  # acá se lee como una función que se perdió.
  def show
    authorize @step, :manage_criteria?

    redirect_to challenge_step_path(@challenge, @step), status: :moved_permanently
  end
```

Y borrar la vista:

```bash
git rm app/views/step_criteria/show.html.haml
```

- [ ] **Step 6: Correr y ver que pasa**

Run: `make spec && make screens`
Expected: `0 failures`; 30 capturas. Si `make screens` falla porque una captura entraba a `/steps/:id/criteria`, actualizá esa navegación en `script/capture_screens.js`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Los criterios se editan en la pantalla del módulo

Eran pantalla propia, y configurar un módulo exigía rebotar entre cuatro
pantallas donde ninguna era la del módulo. La URL vieja redirige en vez de
dar 404: vive en links, marcadores y back_url."
```

---

### Task 7: Los campos del formulario, embebidos

**Files:**
- Create: `app/views/steps/_campos_editor.html.haml`
- Delete: `app/views/form_fields/show.html.haml`
- Modify: `app/controllers/form_fields_controller.rb`, `app/views/steps/config/ideation.html.haml`, `app/views/steps/ideation.html.haml`

**Interfaces:**
- Produces: partial `steps/_campos_editor` que recibe `step`.

- [ ] **Step 1: Escribir el test que falla**

Agregá a `spec/requests/dos_caras_spec.rb`:

```ruby
    it "trae el editor de campos en Idear" do
      get challenge_step_path(challenge, paso("ideation"))

      expect(response.body).to include('data-island="form-editor"')
    end

    it "la pantalla suelta del formulario redirige al módulo de idear" do
      get challenge_form_path(challenge)

      expect(response).to redirect_to(challenge_step_path(challenge, paso("ideation")))
    end
```

Y dentro de `describe "cara B"`, la excepción documentada en el spec §6:

```ruby
    # El formulario NO se congela con `touched?`: su candado es
    # `ideas.submitted.exists?`, que es más fino. Con el módulo abierto pero
    # sin postulaciones, corregir el label de un campo es sano.
    it "en Idear sigue mostrando el editor de campos, con su propio candado" do
      get challenge_step_path(challenge, paso("ideation"))

      expect(response.body).to include('data-island="form-editor"')
    end
```

- [ ] **Step 2: Correr y ver que falla**

Run: `make spec-file FILE=spec/requests/dos_caras_spec.rb`
Expected: FAIL en los tres.

- [ ] **Step 3: Extraer el partial**

Creá `app/views/steps/_campos_editor.html.haml` con el contenido de `app/views/form_fields/show.html.haml` **desde el `- if @locked`** hasta el `javascript_include_tag`, cambiando `@challenge` por `step.challenge`, `@step` por `step`, y calculando arriba:

```haml
-# El editor de campos, embebido en la pantalla del módulo de idear.
-#
-# Su candado NO es `touched?` sino `ideas.submitted.exists?`, que es más fino
-# y se conserva: con el módulo ya abierto pero sin ninguna postulación,
-# corregir el label de un campo es sano y no reescribe nada.
- campos = step.form_fields.ordered
- bloqueado = step.challenge.ideas.submitted.exists?
- props = { fields: campos.map { |f| form_field_json(f) },
            fieldTypes: FormField::TYPES.map { |k| { value: k, label: t("flow.field_types.#{k}") } },
            locked: bloqueado,
            urls: { save: api_v1_challenge_form_fields_path(step.challenge),
                    back: challenge_step_path(step.challenge, step) } }
```

> `form_field_json` es el `serialize` privado de `FormFieldsController`. Movelo a un helper (`app/helpers/form_fields_helper.rb`) para que lo puedan usar los dos, en vez de duplicarlo.

- [ ] **Step 4: Renderizarlo**

En `app/views/steps/config/ideation.html.haml` y también en `app/views/steps/ideation.html.haml` (la cara B, por la excepción del candado):

```haml
= render "steps/campos_editor", step: @step
```

En la cara B, sacá el `link_to "Editar el formulario"` que hoy apunta a `challenge_form_path`: el editor ya está ahí.

- [ ] **Step 5: Redirigir la pantalla vieja**

En `app/controllers/form_fields_controller.rb`, reemplazar `show`:

```ruby
  # El formulario se edita en la pantalla del módulo de idear. Redirige en vez
  # de dar 404 por el mismo motivo que los criterios: la URL vive en links y
  # en marcadores.
  def show
    authorize @step, :manage_form?

    redirect_to challenge_step_path(@challenge, @step), status: :moved_permanently
  end
```

```bash
git rm app/views/form_fields/show.html.haml
```

- [ ] **Step 6: Correr**

Run: `make yarn-build && make spec && make screens`
Expected: `0 failures`; 30 capturas.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "El formulario de postulación se edita en el módulo de idear

Se conserva su candado propio —ideas.submitted.exists?— que es más fino que
touched?: con el módulo abierto pero sin postulaciones, corregir el label de
un campo es sano. Por eso el editor también aparece en la cara de ejecución."
```

---

### Task 8: Las asignaciones, en las dos caras

**Files:**
- Create: `app/views/steps/_asignaciones_evaluadores.html.haml`, `app/views/steps/_asignaciones_gestores.html.haml`
- Modify: `app/views/steps/evaluation.html.haml`, `app/views/steps/evolution.html.haml`, `app/views/steps/config/evaluation.html.haml`, `app/views/steps/config/evolution.html.haml`, `app/controllers/steps_controller.rb`

- [ ] **Step 1: Escribir el test que falla**

En `spec/requests/dos_caras_spec.rb`, dentro de `describe "cara A"`:

```ruby
    it "deja asignar evaluadores antes de que el módulo arranque" do
      get challenge_step_path(challenge, paso("evaluation"))

      expect(response.body).to include("Elegí a quién sumar")
    end
```

- [ ] **Step 2: Correr y ver que falla**

Run: `make spec-file FILE=spec/requests/dos_caras_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Extraer los dos partials**

Mové el bloque de evaluadores de `app/views/steps/evaluation.html.haml` (el `%h2.section-title` de quiénes evalúan, la tabla con pesos, el `button_to "Quitar"` y el form de sumar) a `app/views/steps/_asignaciones_evaluadores.html.haml`, con `step` y `assignable` como locales. Encabezalo:

```haml
-# Quién evalúa este módulo y cuánto pesa su voto.
-#
-# Va en las DOS caras: se puede sumar a alguien con el módulo en curso. Lo que
-# no se puede es desasignar a quien ya puntuó —su nota quedaría sin respaldo—
-# ni tocar nada con el módulo cerrado.
```

Lo mismo con el bloque de gestores de `evolution.html.haml` → `_asignaciones_gestores.html.haml`, con `step` y `candidates`.

- [ ] **Step 4: Renderizarlos en las cuatro vistas**

En `steps/evaluation.html.haml` y `steps/config/evaluation.html.haml`:

```haml
= render "steps/asignaciones_evaluadores", step: @step, assignable: @assignable
```

En `steps/evolution.html.haml` y `steps/config/evolution.html.haml`:

```haml
= render "steps/asignaciones_gestores", step: @step, candidates: @gestor_candidates
```

- [ ] **Step 5: Que el controller los cargue en las dos caras**

`StepsController#show` ya calcula `@assignable` y `@gestor_candidates` antes del `render`, así que sirven a las dos ramas. Verificalo leyendo el método.

- [ ] **Step 6: Correr**

Run: `make spec`
Expected: `0 failures`

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Las asignaciones viven en las dos caras del módulo

Sumar a alguien con el módulo en curso es legítimo y ya lo era; lo que no se
puede es desasignar a quien ya puntuó. Que estén sólo en la cara de ejecución
obligaba a arrancar el módulo para poder armar el comité."
```

---

### Task 9: `Flow::Setup` y el índice de criterios

`Flow::Setup` enruta el paso a paso a través de dos pantallas que ya no existen. Y `/challenges/:id/criteria` es un índice de módulos que puntúan, que ahora duplica lo que hace el builder.

> **DECISIÓN DE ALCANCE:** este plan elimina `challenge_criteria`. El builder ya lista los módulos y ahora lleva a cada uno; un segundo índice es la sexta pantalla de configuración que el requisito prohíbe. Si se prefiere conservarlo como índice de sólo lectura, saltear los Steps 4 y 5 y apuntar `criteria_step.path` ahí.

**Files:**
- Modify: `app/lib/flow/setup.rb:88-110`
- Delete: `app/controllers/challenge_criteria_controller.rb`, `app/views/challenge_criteria/`
- Modify: `config/routes.rb`
- Test: `spec/lib/flow/setup_spec.rb`

- [ ] **Step 1: Escribir el test que falla**

```ruby
# spec/lib/flow/setup_spec.rb — sumar a lo que exista
    it "el paso del formulario lleva al módulo de idear, no a una pantalla suelta" do
      as_company(company) do
        setup = described_class.new(challenge)
        idear = challenge.steps.find(&:ideation?)

        expect(setup.find(:form).path)
          .to eq(Rails.application.routes.url_helpers.challenge_step_path(challenge, idear))
      end
    end

    it "el paso de los criterios lleva al flujo, desde donde se entra a cada módulo" do
      as_company(company) do
        setup = described_class.new(challenge)

        expect(setup.find(:criteria).path)
          .to eq(Rails.application.routes.url_helpers.builder_challenge_path(challenge))
      end
    end
```

- [ ] **Step 2: Correr y ver que falla**

Run: `make spec-file FILE=spec/lib/flow/setup_spec.rb`
Expected: FAIL — devuelve `challenge_form_path` y `challenge_criteria_path`.

- [ ] **Step 3: Reapuntar los dos pasos**

En `app/lib/flow/setup.rb`, en `form_step`:

```ruby
               path: ideation ? routes.challenge_step_path(challenge, ideation) : routes.builder_challenge_path(challenge),
```

En `criteria_step`:

```ruby
               # El flujo es el índice: desde ahí se entra a configurar cada
               # módulo. Un índice aparte de criterios sería una segunda
               # pantalla de configuración.
               path: routes.builder_challenge_path(challenge),
```

- [ ] **Step 4: Borrar el índice de criterios**

```bash
git rm -r app/controllers/challenge_criteria_controller.rb app/views/challenge_criteria
```

En `config/routes.rb`, borrar la ruta `challenge_criteria`. Grepeá los usos:

```bash
grep -rn "challenge_criteria_path" app/ spec/ script/
```

Reemplazá cada uno por `builder_challenge_path`.

- [ ] **Step 5: Correr**

Run: `make spec && make screens`
Expected: `0 failures`; 30 capturas.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "El paso a paso enruta a las caras de configuración

Flow::Setup llevaba a dos pantallas que dejaron de existir. Y el índice de
criterios duplicaba lo que hace el flujo, que ya lista los módulos y ahora
lleva a cada uno: era una sexta pantalla de configuración."
```

---

### Task 10: La guarda de una sola vista de configuración

**Files:**
- Create: `spec/lint/una_vista_de_configuracion_spec.rb`

- [ ] **Step 1: Escribir la guarda**

```ruby
# spec/lint/una_vista_de_configuracion_spec.rb
# frozen_string_literal: true

require "rails_helper"

# Requisito del diseño: un módulo se configura en UN solo lugar.
#
# No alcanza con haberlo hecho una vez. Configurar estaba repartido en seis
# pantallas que se fueron sumando de a una, cada una razonable por su cuenta.
# Esto cuenta declaraciones de isla en vez de confiar en que el diff se vea
# bien, que es lo que falló las seis veces.
RSpec.describe "una sola vista de configuración", type: :lint do
  def vistas_con(isla)
    Dir[Rails.root.join("app/views/**/*.haml")].select do |archivo|
      File.read(archivo).include?(%(data-island": "#{isla}"))
    end.map { |a| a.sub("#{Rails.root}/", "") }
  end

  it "el editor de campos vive en una sola vista" do
    expect(vistas_con("form-editor")).to contain_exactly("app/views/steps/_campos_editor.html.haml")
  end

  # Dos: la cara de configuración del módulo, y el form de la biblioteca. La
  # biblioteca no es la configuración de un módulo: es el CRUD de otro objeto,
  # para reusar un set entre desafíos distintos.
  it "el editor de criterios vive en la cara del módulo y en la biblioteca" do
    expect(vistas_con("criteria-editor"))
      .to contain_exactly("app/views/steps/_criterios_editor.html.haml",
                          "app/views/criteria_sets/_form.html.haml")
  end

  it "los ajustes del módulo viven en una sola vista" do
    expect(vistas_con("step-settings"))
      .to contain_exactly("app/views/steps/config/_modulo.html.haml")
  end

  # El panel del builder era la primera de las seis.
  it "el builder no volvió a tener panel de configuración" do
    builder = File.read(Rails.root.join("app/javascript/components/pipeline_builder/pipeline_builder.vue"))

    expect(builder).not_to include("builder__config")
    expect(builder).not_to include("step-config")
  end
end
```

- [ ] **Step 2: Correr y ver que pasa**

Run: `make spec-file FILE=spec/lint/una_vista_de_configuracion_spec.rb`
Expected: `4 examples, 0 failures`. Si falla, es una vista de configuración que quedó viva: eliminala, no relajes la guarda.

- [ ] **Step 3: Commit**

```bash
git add spec/lint/una_vista_de_configuracion_spec.rb
git commit -m "Guarda: un módulo se configura en un solo lugar

Cuenta declaraciones de isla en vez de confiar en el diff. Configurar estaba
repartido en seis pantallas que se sumaron de a una, cada una razonable por
su cuenta: sin una guarda, la séptima llega igual."
```

---

### Task 11: Las capturas de las dos caras

**Files:**
- Modify: `script/capture_screens.js`

- [ ] **Step 1: Sumar las capturas**

En `script/capture_screens.js`, después del recorrido del builder. **Navegá por link**, no con `goto`: Turbo no dispara `DOMContentLoaded` al navegar por link, y un `goto` monta la isla igual y esconde el bug — que es justo el camino nuevo (tarjeta del builder → pantalla del módulo).

```js
  // Las dos caras de un módulo. Por LINK desde el builder, que es el camino
  // nuevo: un goto montaría la isla igual y escondería el bug.
  await page.goto(`${BASE}/challenges/${CHALLENGE}/builder`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-island-mounted="true"]');

  const configurables = await page.$$eval('.step-card__config', els => els.map(e => e.getAttribute('href')));
  for (const [i, href] of configurables.entries()) {
    await page.click(`.step-card__config[href="${href}"]`);
    await page.waitForURL(u => String(u).includes('/steps/'));
    await shot(page, `31-config-${i + 1}`, null);
    await page.goBack({ waitUntil: 'networkidle' });
    await page.waitForSelector('[data-island-mounted="true"]');
  }
```

- [ ] **Step 2: Correr**

Run: `make screens`
Expected: capturas nuevas en `tmp/screenshots/`, sin errores de JS ni HTTP >= 400, y sin `.island-placeholder` sin montar.

- [ ] **Step 3: Mirar las capturas**

```bash
ls tmp/screenshots/31-config-*.png
```

Abrí al menos la de una selección y la de idear. **Mirarlas de verdad**: la suite no ve CSS, y `make screens` falla por errores de JS y HTTP, no por que algo se vea mal.

- [ ] **Step 4: Commit**

```bash
git add script/capture_screens.js
git commit -m "Las capturas recorren las dos caras, por link desde el flujo"
```

---

### Task 12: La documentación

**Files:**
- Modify: `CLAUDE.md`, `README.md`
- Modify: `docs/superpowers/specs/2026-09-09-configurar-vs-ejecutar-design.md` (marcar implementado)

- [ ] **Step 1: Actualizar `CLAUDE.md`**

En la sección de arquitectura, sumá antes de «Islas Vue»:

```markdown
### Configurar y ejecutar son dos caras de la misma pantalla

`StepsController#show` despacha por `step.touched?`: pendiente renderiza
`steps/config/<kind>` —la configuración entera del módulo—, tocado renderiza
`steps/<kind>` —el trabajo, con la configuración como resumen con candado—.

La cara la decide el MÓDULO y no el desafío: uno en curso sigue teniendo
módulos pendientes más adelante, y ésos son configurables. Es la misma regla
que `insertion_floor`.

**Un módulo se configura en UN solo lugar.** Estuvo repartido en seis
pantallas que se sumaron de a una, cada una razonable por su cuenta, y
configurar exigía rebotar entre todas. Hay guarda:
`spec/lint/una_vista_de_configuracion_spec.rb` cuenta declaraciones de isla.

**El builder es dueño del ARMADO, no de la configuración.** Manda kind, orden,
alta y baja; no manda `settings`, `criteria_set_id` ni `source_step_id`. Si los
mandara, guardar el flujo con props cargadas antes revertiría lo configurado, y
`lock_version` no lo ataja: es del desafío, y un PATCH al módulo no lo
incrementa.

Tres cosas NO se congelan al arrancar y la cara B las muestra como vivas:
el nombre, el modo de IA (`ADJUSTABLE_ATTRIBUTES`) y las asignaciones.

El formulario de postulación tiene un candado más fino que `touched?`:
`ideas.submitted.exists?`. Con el módulo abierto pero sin postulaciones,
corregir el label de un campo es sano. Por eso su editor aparece en las dos
caras.
```

Y borrá de la sección de islas la mención al panel del builder que configura los módulos.

- [ ] **Step 2: Actualizar `README.md`**

En la tabla de superficie de UI, sacá `/challenges/:id/form` y `/challenges/:id/criteria`, y anotá que `/challenges/:id/steps/:id` tiene dos caras.

- [ ] **Step 3: Marcar el spec como implementado**

En `docs/superpowers/specs/2026-09-09-configurar-vs-ejecutar-design.md`, cambiar el encabezado:

```markdown
> Estado: implementado.
```

Y en «Decisiones abiertas», anotar cómo se resolvió lo de la biblioteca.

- [ ] **Step 4: Verificación final**

Run: `make spec && make screens`
Expected: `0 failures`; capturas sin errores.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "La documentación, con las dos caras y el dueño de cada cosa"
```

---

### Task 13: El handoff

Toda sesión cierra con un `handoff.md`. Lo que se pierde cuando una sesión se
corta no es el código —eso está en git— sino los callejones sin salida ya
recorridos: sin la sección 4, la sesión siguiente vuelve a probar lo mismo.

**Files:**
- Create: `handoff.md` (raíz del repo)

- [ ] **Step 1: Escribirlo, con estas cinco secciones y en este orden**

```markdown
# Handoff

## Objetivo
[Qué estamos construyendo, una o dos líneas.]

## Estado actual
[Qué funciona ya y qué queda pendiente.]

## Archivos y cambios
[Qué archivos se tocaron y qué cambió en esta sesión.]

## Intentos fallidos
[Qué se probó que no funcionó, para no repetirlo. Si no falló nada,
decirlo explícitamente en vez de borrar la sección.]

## Próximos pasos
[Las acciones exactas que siguen, en orden.]
```

Corto y factual: sólo lo que la próxima sesión necesita para continuar limpio.
Nada de narrativa ni de resumen de la conversación.

Para la sección 4, revisá el ledger de esta ejecución
(`.superpowers/sdd/2026-09-09-configurar-vs-ejecutar/progress.md`): las líneas
`fix round`, `parked` y `Ruling:` son exactamente los intentos fallidos y las
decisiones que la próxima sesión necesita heredar.

- [ ] **Step 2: Commit**

```bash
git add handoff.md
git commit -m "Handoff de la sesión"
```

---

## Verificación de cierre

- [ ] `make spec` en verde, con los specs nuevos: `step_settings_spec`, `step_config_spec`, `pipeline_no_pisa_config_spec`, `dos_caras_spec`, `una_vista_de_configuracion_spec`, `setup_spec`.
- [ ] `make screens` en verde, con las capturas de las dos caras.
- [ ] **Mirar las capturas.** Ni la suite ni `make screens` ven CSS: fallan por errores de JS y HTTP, no por que algo se vea mal. Todos los defectos visuales caros de este repo aparecieron midiendo en un navegador, no leyendo código.
- [ ] Probar a mano el camino completo sobre un desafío **desechable** (no `onboarding-remoto` ni `optimizacion-de-la-experiencia-de-onboarding`): crear, armar el flujo, entrar a cada módulo desde el builder, configurar el corte, volver al builder, **guardar el flujo**, y verificar que el corte sigue ahí. Ésa es la regresión que este plan existe para evitar.
- [ ] Borrar el desafío desechable.
- [ ] `handoff.md` escrito, con las cinco secciones y con la 4 llena o explícitamente vacía.
