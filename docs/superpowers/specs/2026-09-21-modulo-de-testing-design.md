# Módulo de testing: poner a prueba la factibilidad de una idea

Un sexto `kind` en el flujo del desafío. Pone las ideas a prueba contra
situaciones concretas de ejecución —un día puntual, un volumen, una persona
que falta, un proveedor caído— y deja por cada una un veredicto de
factibilidad con la evidencia que lo sostiene.

Como los otros cinco, tiene los tres modos de IA. En **«Solo personas»** una
persona arma las situaciones y dictamina; en **«IA asistida»** la IA propone un
testeo completo y alguien lo acepta; en **«IA automática»** la IA testea todas
las ideas sola al arrancar el módulo.

## 1 · Alcance

**Entra:**

- El `kind` `testing` vivo de punta a punta: enum, CHECK de Postgres, handler,
  esquema de configuración, paso a paso, drawer, rótulos, seeds y capturas.
- La tabla `step_tests`, append-only, con el vigente garantizado por un índice
  parcial.
- Las dos caras de pantalla (configuración y ejecución) más la pantalla del
  testeo por idea.
- La tarea `Flow::AI::Tasks::TestIdea` con su JSON Schema, su fixture
  determinista y los tres modos.
- El check automático `testing_passed`, que es cómo una selección posterior
  consume el veredicto.

**No entra** (ver *Fuera de alcance*): testers asignados, agregación de varios
testeos, y que el testing elimine ideas por sí mismo.

## 2 · Las cinco decisiones, y por qué

### 2.1 · Deja un veredicto; no elimina

`ideas.status` y `eliminated_at_step_id` siguen teniendo **un solo escritor**:
`Flow::Handlers::Selection#decide!`. El testing no toca ninguno de los dos.

Lo contrario —que el testing eliminara— obligaba a duplicar el log de
decisiones, la repesca y las notificaciones de resultado, y dejaba dos módulos
compitiendo por el mismo campo. La invariante «un solo módulo reduce el pool»
es lo que hace que la eliminación de una idea sea siempre rastreable a una
tanda de `SelectionDecision`.

Quien quiera que el testeo corte, pone una selección después con un filtro
`testing_passed` (§6). La decisión de cortar sigue siendo de alguien.

### 2.2 · Las situaciones las arma quien testea, por idea

El módulo configura **el marco**, igual para todas las ideas; las situaciones
concretas son de cada idea y las inventa quien la testea (la IA en automático,
una persona en manual).

Una lista fija de situaciones para todo el desafío sería un checklist, que es
casi exactamente lo que ya hacen los filtros de una selección — y una situación
genérica no rompe ninguna idea en particular. Una idea de logística y una de
onboarding no se rompen por lo mismo.

### 2.3 · Un testeo vigente por idea, con historial

Re-testear **no edita** el testeo anterior: lo marca `superseded_at` y escribe
otro, en la misma transacción. Es la forma de `SelectionDecision`, y por el
mismo motivo: una idea que evoluciona después de ser probada necesita poder
probarse de nuevo sin que se pierda lo que se dijo de la versión anterior.

Cada testeo queda anclado a `idea_version_id`: el veredicto es sobre **la
versión que se probó**, no sobre «la idea».

### 2.4 · Veredicto ternario, más reservas

`factible` · `con_reservas` · `no_factible`.

Un testeo crítico casi nunca da un sí limpio: da «sí, si resolvés esto», y esa
es la información útil. El binario fuerza a tirar al «no» todo lo que tiene
algún pero, y con eso se pierde la idea buena a la que le faltaba una
condición.

`reservations` es **su propia lista**, no las situaciones que fallaron. Una
reserva es una condición a resolver («conseguir un segundo proveedor»); una
situación fallada es evidencia («el viernes a las 18 satura el turno»).
Mezclarlas deja al módulo de evolución sin nada concreto que atacar.

Dónde poner la vara lo decide el filtro de la selección, no el módulo (§6).

### 2.5 · Testear es de quien administra o acompaña el desafío

`Tasks::TestIdea.actua_sobre = :challenge`, o sea `ChallengePolicy#update_pipeline?`.

Quien participa **no testea ni pide el testeo de su idea**. A diferencia de una
evaluación de IA —que es una opinión más en un promedio, y por eso hasta el
autor puede pedirla— el testeo es **la** respuesta del módulo para esa idea y
habilita un filtro después.

Esto cierra de raíz un agujero que sale de combinar 2.3 con un permiso más
amplio: con un solo testeo vigente donde el último manda, alguien que pueda
pedirle a la IA que teste su propia idea re-tira el dado hasta que salga
«factible».

Quien participa **ve** el resultado de su idea cuando el módulo cierra, igual
que ve su puntaje.

## 3 · Modelo de datos

Tabla nueva `step_tests`. Espeja a `selection_verdicts` en tenencia y autoría,
y a `selection_decisions` en que es append-only.

```
step_tests
  id              uuid  (uuid_generate_v7)
  company_id      uuid  NOT NULL          ← TenantScoped
  challenge_step_id uuid NOT NULL
  idea_id         uuid  NOT NULL
  idea_version_id uuid  NOT NULL          ← QUÉ versión se probó
  verdict         varchar NOT NULL        CHECK (factible|con_reservas|no_factible)
  situations      jsonb  NOT NULL DEFAULT '[]'
  reservations    jsonb  NOT NULL DEFAULT '[]'
  summary         text
  actor_type      varchar NOT NULL DEFAULT 'human'  CHECK (human|ai)
  tested_by_id    uuid
  ai_run_id       uuid
  superseded_at   timestamp               ← NULL = es el vigente
  tested_at       timestamp NOT NULL
  created_at / updated_at
```

Forma de `situations`:

```json
[{ "dimension": "operativa",
   "escenario": "Viernes 18h, 400 pedidos simultáneos",
   "resultado": "se_rompe",
   "detalle": "El pico satura el único turno de tarde" }]
```

### El vigente lo garantiza Postgres

```sql
CREATE UNIQUE INDEX index_step_tests_vigente
  ON step_tests (challenge_step_id, idea_id)
  WHERE superseded_at IS NULL;
```

«Un solo testeo vigente por idea» pasa a ser una invariante de la base y no una
convención que un camino de escritura nuevo pueda romper. Es la misma decisión
que hizo que `selection_verdicts` use `find_or_initialize_by` en vez de confiar
en que nadie escriba dos veces.

### Tenencia

`tenant_table` y `add_tenant_fk` de `lib/flow/migration_helpers.rb`: FKs
compuestas `(x_id, company_id)` contra `challenge_steps`, `ideas` e
`idea_versions`, para que Postgres rechace atar una fila de la empresa A a un
padre de la B. El modelo incluye `TenantScoped`.

Trampa ya documentada y que aplica acá: `ON DELETE SET NULL` sobre una FK
compuesta nulea **todas** las columnas, `company_id` incluida, que es NOT NULL.
El helper usa `SET NULL (columna)`.

### La proyección a `step_entries`

Al cerrar el módulo, `on_complete` resuelve cada entry con el veredicto en
`result`, igual que `recompute_entry!` en evaluación:

```ruby
entry.resolve!(status: "done", result: { "verdict" => …, "tested_at" => … })
```

Nadie se elimina: todas las entries se resuelven `done`.

## 4 · Las dos caras

`StepsController#show` ya despacha por `step.touched?`. El módulo solo aporta
sus plantillas.

### 4.1 · Configuración — `steps/config/testing`

Sin nada propio: el `form_with` de `steps/config/_modulo` con la isla
`step-settings` renderizando el esquema nuevo.

`Flow::StepSettings::SCHEMA["testing"]`:

| clave | tipo | default | qué es |
|---|---|---|---|
| `dimensions` | `multi_select` | las cinco | qué hay que cubrir: técnica, operativa, económica, legal, de adopción |
| `min_situations` | `number` (min 1) | `3` | cuántas situaciones como mínimo por idea |
| `severity` | `select` | `exigente` | valores `exigente` / `estandar` (sin tilde: es la clave guardada; el rótulo la lleva). Qué tan dura es la vara. |

Recordar que **en `config` un hueco no es «sin valor»: es el default del
esquema**. El handler lee con `fetch(clave, default)` y la tarjeta congelada se
arma con `StepSettings.efectivo("testing", settings)`.

La guarda de permiso va **en la vista**, con la forma que ya fijaron
`_criterios_editor` y `_campos_editor`: **nada que no sea el encabezado se
sirve sin la guarda**, y la guarda es UNA variable (`puede_configurar`,
calculada una vez arriba), no un predicado escrito en cada bloque. El predicado
es `configure?`.

**La pantalla tiene que renderizar `setup_nav`.** Es lo único que avanza el
paso a paso; sin él el recorrido se corta ahí y ni `make spec` ni `make screens`
lo notan — pasó con `:form` (`2029528`) y estuvo por repetirse con `:criteria`.

`Flow::Setup#estado_de` suma su rama: un testing **no traba el arranque** y
nace configurado (las tres claves tienen default). Pista: las dimensiones
elegidas.

### 4.2 · Ejecución — `steps/testing`

**Centro:** la lista de ideas con su veredicto vigente y un link «Testear» por
fila.

Ese link pregunta **la misma policy que autoriza al controller**, no
`step.active?` a secas. Es la lección exacta del link «Evaluar», que se le
mostraba a quien se comía un 403 al apretarlo.

**Referencia** (orden fijo): `Progreso` · `Veredictos` · `Cómo quedó
configurado`. Sin bloque de «quién participa»: no hay testers asignados (§2.5).

**Ajustes plegados** al final: nombre y modo de IA. Nada más — son los dos
`ADJUSTABLE_ATTRIBUTES`.

### 4.3 · El testeo de una idea — pantalla propia

Como `assessments/new`. Es trabajo por idea, no configuración, así que no choca
con «un módulo se configura en un solo lugar» (`spec/lint/una_vista_de_configuracion_spec.rb`
cuenta declaraciones de isla, y esta pantalla no declara ninguna).

Formulario: N situaciones (dimensión, escenario, resultado, detalle), el
veredicto, las reservas y el resumen. Guardar escribe el testeo nuevo y marca
`superseded_at` en el anterior, en una transacción.

## 5 · La tarea de IA

`Flow::AI::Tasks::TestIdea`, propósito `test_idea`.

| predicado | valor | por qué |
|---|---|---|
| `actua_sobre` | `:challenge` | §2.5 |
| `applies_on_request?` | `false` | En `ai_assisted` propone y alguien acepta. Mismo criterio que `decide_verdicts`: es **la** respuesta del módulo para esa idea, no una opinión más en un promedio. |
| `editable?` | `false` | La lección de `EvaluateIdea`: aceptar una propuesta pendiente admitía un payload editado. Acá sería editar `no_factible` → `factible` y que quede con el nombre de la IA encima. Se acepta como vino o se descarta. |
| `informativa?` | `false` | Produce algo que se aplica. |

En **`ai_auto`**, `on_activate` encola **un `RunJob` por idea**, como
`request_ai_verdicts!` de selección. Nunca un fan-out síncrono en el request.

### El schema

```
situaciones: [{ dimension : enum(las configuradas en el módulo)
                escenario : string
                resultado : enum(aguanta | se_rompe)
                detalle   : string }]    minItems: min_situations
veredicto  : enum(factible | con_reservas | no_factible)
reservas   : [string]
resumen    : string
```

`dimension` va como `enum` por el mismo motivo por el que `detect_duplicates`
manda los ids candidatos como enum: el modelo no puede señalar una dimensión
que el módulo no declaró.

Dos cosas del adapter real que el schema tiene que respetar: cierra todo objeto
con `additionalProperties: false` —así que cada clave se declara o la propuesta
llega vacía—, y la API **poda** `minItems`, `minimum` y `pattern`, por lo que el
mínimo de situaciones se repite **en la descripción**, que es lo único que el
modelo ve. La validación sigue corriendo contra el schema original.

### El prompt: crítico en las situaciones, no en el veredicto

La instrucción es adversarial: plantear situaciones concretas de la idea **en
ejecución** y tratar de romperla. `severity` mueve la vara.

Pero el veredicto **lo dicta lo que encontró, no la actitud**:

- `no_factible` sólo si hay al menos una situación con `resultado: se_rompe` y
  un detalle concreto.
- Si lo que se rompe es arreglable, el veredicto correcto es `con_reservas`,
  con la condición en `reservations`.

**El porqué de este contrapeso.** Una IA crítica por mandato dice «no factible»
a casi todo; el filtro de la selección lo consume y el desafío se queda sin
finalistas. Es exactamente el escenario del bug de `cut.min` arreglado el
2026-09-21 (`8bc0c45`), donde los filtros vaciaban el pool en silencio. El piso
es la red del otro lado, pero una red no reemplaza a un veredicto honesto.

### Fixture

`FLOW_AI_PROVIDER=fixture` es el default, así que el fixture de `test_idea`
tiene que existir y ser determinista. `spec/lib/flow/ai/fixtures_spec.rb` valida
cada fixture contra su schema: es la guarda que atrapó el `cut_mode` plano que
nadie leía.

### Los dos lugares más el CHECK

Sumar una tarea es tocar **tres** cosas: la clase, `AiRun::PURPOSES`
(`app/models/ai_run.rb:8`) y el CHECK `ai_runs_purpose_check` de Postgres
(`db/structure.sql:143`). Sin la migración el run revienta con
`PG::CheckViolation` antes de crearse, y el error llega truncado.

## 6 · El check de la selección

`Flow::Checks::TestingPassed`, sumado a `Checks::Base::TYPES`
(`app/lib/flow/checks/base.rb:11`) y a `CriterionSettings::CHECKS` con sus
params, que es lo que el editor de criterios renderiza solo.

| param | valores | default |
|---|---|---|
| `accepts` | `solo_factible` · `factible_o_con_reservas` | `factible_o_con_reservas` |
| `sin_testeo` | `pasa` · `no_pasa` | `pasa` |

### Qué testeo mira

Hereda el problema que `feedback_addressed` ya resolvió: **un check no sabe en
qué módulo lo están corriendo** — sólo tiene su `criterion` y la idea. Así que
«el testeo» no puede ser «el de este módulo»: es **el testeo vigente del módulo
de testing más reciente que probó esa idea** (`superseded_at IS NULL`,
`max_by` la posición del paso). Es la línea 19 de `feedback_addressed` con otra
tabla.

### Sin testeo, configurable

El default es `pasa`, por simetría con `feedback_addressed` («no se puede tener
sin atender lo que nadie comentó») y porque un check permisivo por defecto se
apreta, mientras que uno restrictivo por defecto sorprende. Quien necesite que
una idea sin probar no avance, lo pone en `no_pasa`.

El `detail` dice cuál de los dos casos fue («sin testear», «factible con 2
reservas»), porque se lee en la celda del filtro del ranking.

### El rebote gratis

Todo check normaliza a `1.0 / 0.0`, así que el mismo criterio sirve **también
como criterio puntuado dentro de una evaluación**, no sólo como filtro de una
selección. No hay trabajo extra para eso.

## 7 · Orden: dos tandas

### Tanda 1 — el módulo, en «Solo personas»

Es la que toca el enum que todo el repo asume en cinco. Al terminar hay un
módulo de testing que funciona entero a mano.

1. Migración: CHECK `challenge_steps_kind_check` + tabla `step_tests` con su
   índice parcial y sus FKs compuestas. Commitear `db/structure.sql`.
2. `ChallengeStep::KINDS` (`app/models/challenge_step.rb:10`), el modelo
   `StepTest` con `TenantScoped`.
3. `Flow::Handlers::Testing` y su despacho en `Base.for`.
4. `Flow::StepSettings::SCHEMA["testing"]` y `Flow::Setup#estado_de`.
5. `config/locales/es.yml`: las tres claves de `step_kinds`.
6. Las dos caras, la pantalla del testeo y su controller.
7. `db/seeds.rb` (un desafío con un módulo de testing) y las capturas.

**`EstilosHelper` NO se toca.** Se verificó: `CLASE_DE_NODO_DE_FLUJO` y
`PUNTO_DE_ESTADO` mapean por **estado** del módulo —`pending`, `active`,
`completed`, `skipped`—, nunca por `kind`. El drawer y el mapa del flujo
dibujan un módulo nuevo sin una línea de CSS ni de helper.

### Tanda 2 — la IA y el filtro

8. Migración: CHECK `ai_runs_purpose_check`.
9. `Tasks::TestIdea`, su schema, su fixture y `AiRun::PURPOSES`.
10. `on_activate` → los tres modos.
11. `Flow::Checks::TestingPassed` + `CriterionSettings::CHECKS` + `es.yml`.

Cada tanda se mergea sola y se verifica sola.

## 8 · Verificación

### Las guardas que hay que tocar, y que fallan a propósito si no

- **`ORDEN_DE_LA_REFERENCIA`** (`spec/requests/pantalla_del_modulo_spec.rb:45`)
  suma `"Veredictos"`. Un título que esa lista no conoce vuelve marcado con
  `¿?` en vez de desaparecer, así que sumarlo es obligatorio.
- **`MODULOS_EN_ZONAS`** (`script/capture_screens.js:605`) suma la regex del
  módulo sembrado. Cada módulo tiene que caer en **exactamente una** de las dos
  listas; si no cae en ninguna, `[ZONAS]` falla.
- **`Flow::Setup`** y los renders de `setup_nav`: se revisan a mano. La suite no
  avisa.

### Specs nuevos

- `spec/lib/flow/handlers/testing_spec.rb`: el vigente, el historial, qué pasa
  al re-testear, `can_complete?` con ideas sin testear, la proyección a
  `step_entries`.
- Un spec que pruebe que **el índice parcial** rechaza dos vigentes: la
  invariante está en la base, así que se prueba contra la base.
- `spec/requests/pantalla_del_modulo_spec.rb`: los bloques por rol y la
  secuencia de títulos de la referencia de testing.
- `spec/lib/flow/checks/testing_passed_spec.rb`: las cuatro combinaciones de los
  dos params, y el caso de dos módulos de testing (que mire el más reciente).
- `spec/lib/flow/ai/fixtures_spec.rb` cubre el fixture nuevo solo.

### A mano

- `make screens` después de tocar vistas.
- Mirar la pantalla del testeo con un formulario de varias situaciones: es la
  única del módulo que no se parece a ninguna existente.

## Fuera de alcance

- **Testers asignados y agregación de varios testeos.** Se descartó en la
  pregunta 3: con un testeo vigente por idea no hay trabajo que repartir. Si
  más adelante hiciera falta, `step_assignments` ya existe y la decisión de
  cómo se agregan tres veredictos (¿un «no» manda? ¿mayoría?) queda abierta a
  propósito.
- **Que el testing elimine ideas.** §2.1.
- **Un testeo que dispare acciones reales** (crear un pilot, agendar una
  prueba). Lo «real» acá es el rigor del escenario, no una integración.

## Riesgos

1. **El enum de `kind` está asumido en cinco en más lugares de los que un grep
   encuentra.** `Flow::FlowTemplates`, `PipelinePresenter`, `propose_pipeline`,
   `Cohort` y las vistas que hacen `case kind`. La tanda 1 existe para que esto
   se descubra con un módulo manual y no con una tarea de IA encima.
2. **El prompt puede seguir siendo demasiado duro aun con el contrapeso.** Se
   mide con el fixture primero; con el proveedor real, cada llamada cuesta
   plata. Si pasa, la palanca es `severity`, no el código.
3. **`propose_pipeline` va a empezar a proponer módulos de testing** en cuanto
   el kind exista, porque su schema sale de `StepSettings`. Es deseable, pero
   hay que mirar que la propuesta no lo ponga antes de una ideación.

## Decisiones tomadas

- Veredicto sin eliminación; `ideas.status` sigue con un solo escritor.
- Situaciones por idea; el módulo configura sólo el marco.
- Un vigente por idea con historial, con la unicidad en Postgres y no en el
  código.
- Ternario más lista de reservas; la vara la pone el filtro de la selección.
- Testear es de quien administra o acompaña: cierra el re-roll por permiso.
- El rigor de la IA va en las situaciones; el veredicto lo dicta lo que
  encontró.
- `sin_testeo` es configurable y su default es `pasa`.
- Dos tandas, la del `kind` primero.
