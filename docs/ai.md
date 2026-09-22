# La capa de IA

## Principio

**Toda llamada al proveedor deja una fila en `ai_runs`** — con el adapter de
fixtures igual que con uno real. El rastro (prompt, respuesta, costo, latencia,
error) existe desde el día 1, y cambiar de proveedor no cambia lo que se ve en
`/admin/ai_runs`.

---

## Los tres modos, un solo camino

El modo efectivo es `step.ai_mode.presence || challenge.ai_default_mode`.

| Modo | Qué pasa |
|---|---|
| `human` | No se llama al proveedor. La UI ni ofrece el botón |
| `ai_assisted` | Run + sugerencia **pendiente**. Una persona acepta, edita o rechaza |
| `ai_auto` | Run + sugerencia **ya aceptada** (`auto_accepted_at`) y aplicada |

**`ai_auto` no saltea la sugerencia: la auto-acepta.** Es deliberado:

- un solo code path para los tres modos,
- el mismo rastro de auditoría en todos,
- pasar un módulo de `auto` a `assisted` queda legible en el historial.

Si `auto` escribiera directo al dominio habría dos caminos y un agujero de
auditoría.

Cuando el dominio **rechaza** lo que propuso la IA en modo auto (p.ej. proponer
un pipeline sobre un desafío ya arrancado), la sugerencia queda **pendiente**
con el motivo en `review_note`: la decisión vuelve a una persona.

---

## Qué dispara cada módulo al activarse

En `ai_auto` la IA **hace el trabajo del módulo sola**, apenas se abre. En
`ai_assisted` no se dispara nada: la IA queda disponible como una mano que
alguien pide, no como el operario por defecto.

| Módulo | `ai_auto` al activarse | `ai_assisted` |
|---|---|---|
| **Idear** | Genera las ideas candidatas | Nada. La IA acompaña a quien postula (copiloto, duplicados) |
| **Evolución** | Genera feedback para cada idea | Igual: el feedback se pide |
| **Evaluación** | **Cubre el mínimo del módulo**: si pide 3 por idea, hace 3 | Nada. La IA es una opinión más que se puede pedir |
| **Selección** | Responde los filtros de sí/no de cada idea | Nada: los propone y alguien los acepta |
| **Reportería** | Escribe el resumen narrativo | Se pide desde la pantalla |
| **Testing** | Testea todas las ideas del módulo, una corrida por idea | Nada: un veredicto de testeo es la respuesta del módulo para esa idea, se pide y alguien la acepta |

Dos salvaguardas en «Idear»: no genera si el desafío **ya tiene** ideas de IA
(reactivar el módulo no lo llena de duplicados), y las ideas nacen postuladas y
marcadas `origin: "ai"` — visibles como cualquier otra, no en un limbo aparte.

En modo automático la IA hace tantas pasadas como el módulo requiera, y cada
una es una consulta independiente al proveedor —su propio `ai_run`, su propio
prompt— así que el promedio y la dispersión significan algo. Las evaluaciones
humanas que ya existan **descuentan** del mínimo que la IA tiene que cubrir.

Una evaluación de IA que no puntúa **no se guarda**: si el modelo responde con
criterios que el módulo no tiene, o con valores fuera de escala, el run queda
fallido y la sugerencia pendiente. Guardarla contaría para el mínimo y dejaría
cerrar el módulo con el ranking vacío.

Las evaluaciones de la IA entran **al promedio junto a las humanas**: mismo
anclaje a la versión, misma justificación por criterio, misma pantalla. No son
una categoría aparte.

### Tareas aditivas: pedirlas ya es aceptarlas

Por defecto, en `ai_assisted` la IA propone y una persona decide. La excepción
son las tareas **aditivas** —agregan algo sin reemplazar nada— donde apretar el
botón ya es la decisión y pedir una confirmación extra sería burocracia.

Hoy la única es `evaluate_idea`: suma una evaluación al conjunto, igual que si
otra persona evaluara, y se puede reemplazar evaluando de nuevo. Se declara en
la tarea con `applies_on_request?`, no con un `if` en el controller.

**El contraejemplo aclara la regla: un veredicto de selección no es aditivo.**
Es LA respuesta del filtro y decide quién queda afuera, así que en
`ai_assisted` se propone y alguien la acepta. Y la IA **nunca pisa un veredicto
que puso una persona**, ni con el módulo en automático: quien lo puso ya miró la
idea (`pending_gates` en `Tasks::DecideVerdicts`).

Lo mismo con `evolve_idea`: reescribe la idea de alguien. Se propone.

## Aceptar es un solo lugar

`Flow::AI::ApplySuggestion` corre exactamente el mismo `task.apply!` que usa la
auto-aceptación. Editar antes de aceptar guarda el payload que **realmente se
aplicó** (`status: "edited"`), no el que propuso el modelo.

---

## El proveedor es abstracto — y son DOS

```ruby
Flow::AI::Provider
  #complete(messages:, schema:, purpose:, temperature:) -> Result
  #embed(texts:) -> [[Float]]
  #embeddings?  -> bool
```

**Chat y vectores son capacidades distintas, con una variable cada una.**
Anthropic no expone embeddings, así que con una sola no se podía tener chat real
y vectores reales al mismo tiempo. Sin declarar el segundo se usa el de chat si
sabe hacerlos, y si no el fixture.

| Variable | Qué resuelve | Adapters |
|---|---|---|
| `FLOW_AI_PROVIDER` | `Flow::AI.provider` — el chat | `fixture` · `null` · `anthropic` |
| `FLOW_EMBEDDINGS_PROVIDER` | `Flow::AI.embeddings_provider` — los vectores | el de chat · `openai` · `voyage` |

| Adapter | Para qué |
|---|---|
| `Providers::Fixture` | **Default.** Determinista, sin red, sin API key |
| `Providers::Null` | Siempre falla: ejercita el camino de error |
| `Providers::Anthropic` | El real. **Cada llamada cuesta plata**, nunca es default |
| `Providers::Openai` · `Providers::Voyage` | Solo vectores: su `complete` levanta `ProviderUnsupported` |

Enchufar uno real es agregar un adapter y cambiar la variable — nada más del
sistema cambia.

### Lo que tiene el adapter real y no se ve

- **Poda el schema** de las palabras que la API rechaza con 400 (`minItems`,
  `pattern`, …) pero valida la respuesta contra el schema **original**. Si no,
  aflojar el contrato para que la llamada pase aflojaría también la verificación.
- Trata `stop_reason: :refusal` y `:max_tokens` como **fallas explicadas**:
  llegan con HTTP 200 y no como excepción, así que sin esto pasarían por
  respuestas válidas y vacías.

Los dos de embeddings heredan de `HttpEmbeddings`, que trae lo que es fácil
hacer mal —respetar el índice de cada fila, partir en lotes, validar la
dimensión, llevar el código HTTP al error— y deja a cada uno su URL, su cuerpo y
dónde pone el mensaje de error.

> **Un 500 en TODO pedido no es el pedido.** Con la credencial autenticando (sin
> ella da 401), la validación funcionando (cuerpo vacío da 400) y el ruteo bien
> (GET da 405), que embeddings, rerank y contextual devuelvan los tres 500
> —incluso con un modelo inexistente, que debería dar 400— significa que la
> cuenta autentica pero no tiene inferencia habilitada. Voyage contesta 500 en
> vez de un 402 que lo diga. La pista quedó en el mensaje del adapter para no
> volver a sondear.

### Los fixtures no son mocks de test

Corren en development y son lo que permite demostrar los tres modos sin
credenciales. Resuelven por hash del prompt a `spec/fixtures/ai/<purpose>/`, con
fallback a `default.json` de cada purpose: **la maqueta nunca se rompe** por
falta de un fixture puntual.

### La red contra el drift

`Flow::AI::SchemaValidator` valida la salida contra JSON Schema **en los dos
caminos** —fixture y proveedor real. Un fixture que se desvía del contrato falla
en `spec/lib/flow/ai/fixtures_spec.rb`, no cuando se enchufe el proveedor de
verdad.

---

## Tareas

Cada tarea define qué se pide, con qué contrato de salida, y **cómo se aplica al
dominio**. Eso último vive en la tarea y no en el controller porque es idéntico
para los tres modos.

| Tarea | Módulo | Qué hace al aplicarse |
|---|---|---|
| `ProposePipeline` | wizard | Reemplaza el flujo (solo en borrador) |
| `SuggestFormFields` | ideation | Reemplaza el formulario (no si ya hay ideas postuladas) |
| `SuggestCriteria` | evaluación / selección | Crea el set de criterios (no si el módulo ya se ejecutó) |
| `GenerateIdeas` | ideation | Crea ideas `origin: "ai"`, ya postuladas |
| `CoauthorField` | ideation | **Publica una versión nueva** — no pisa |
| `DetectDuplicates` | ideation | Nada: es informativa |
| `SuggestFeedback` | evolution | Crea `feedback_items` |
| `EvolveIdea` | evolution | **Publica una versión nueva** con el feedback aplicado, y lo cierra |
| `EvaluateIdea` | evaluación | Crea un `assessment` con su desglose por criterio |
| `TestIdea` | testing | Deja un veredicto de factibilidad con sus situaciones (`step_tests`) |
| `DecideVerdicts` | selección | Responde los filtros de sí/no (`selection_verdicts`) |
| `SummarizeChallenge` | reporting | Crea un `report` de kind `narrative` |

Sumar una tarea es tocar **cuatro** lugares: la clase, `AiRun::PURPOSES`, el
CHECK de Postgres sobre `ai_runs.purpose` (hace falta migración; si no, el run
revienta con `PG::CheckViolation` antes de crearse y el error llega truncado) y
`flow.ai_purposes` en `config/locales/es.yml` — sin esa clave el chip de la
propuesta (`shared/_ai_suggestion`) y `ai_runs/index` y `ai_runs/show` muestran
el propósito en inglés por el fallback `humanize`.

### Quién puede pedir cada tarea — y aceptarla

**Lo declara la tarea, no el controller**, con `self.actua_sobre`. Antes todo
exigía `update_pipeline?` para pedir y «admin o autor» para aceptar: dos reglas
distintas para la misma pregunta, así que quien participaba no podía usar
ninguna función de IA sobre su propia idea y quien acompaña no podía aplicar el
feedback que es su trabajo.

| Alcance | Tareas | Lo autoriza |
|---|---|---|
| `:idea` | `coauthor_field`, `evolve_idea` | `IdeaPolicy#update?` |
| `:feedback` | `suggest_feedback` | `FeedbackItemPolicy#create?` |
| `:assessment` | `evaluate_idea` | `AssessmentPolicy#create?` |
| `:pool` | `detect_duplicates` | `ChallengePolicy#curate_pool?` |
| `:challenge` (default) | el resto | `ChallengePolicy#update_pipeline?` |

**Pedir y aceptar son el mismo método**: `AiRequestsController` arma una
propuesta de mentira con lo que trae el pedido y pregunta
`AiSuggestionPolicy#request?`, que es `accept?`. Así no pueden divergir.

`:pool` es de quien administra y de quien acompaña el desafío: comparar una idea
contra las demás devuelve las demás, y quien participa ve sólo las suyas.

Una vuelta de tuerca en `:assessment`: se pregunta **sin la idea**. Quien
participa de una idea no la puntúa —ese es el conflicto de interés—, pero pedir
que la IA la evalúe no pone su nota: pone la de la IA. Y bloquearlo trabaría el
módulo, porque `min_assessments_for` ya baja el mínimo contando a la IA
justamente como quien evalúa lo que su autor no puede.

Las tareas de **autoría** (armar el flujo, proponer los campos del formulario)
se ofrecen aunque el módulo esté en «Solo personas»: ese modo define cómo se
trabaja *dentro* del desafío, no si su dueño puede pedir una mano para
diseñarlo. Es el `always: true` de `shared/_ai_actions`.

### A dónde responde un pedido

Por defecto al `turbo-frame` de las propuestas: así pedir no recarga la pantalla
ni pierde lo que estuvieras editando. Pero cuando el pedido **ya cambió algo**
—`ai_auto`, que auto-acepta, o una tarea aditiva, que se aplica al pedirla—
refrescar solo el marco deja el resto de la pantalla mostrando lo viejo: una
idea reescrita se seguía viendo como estaba hasta recargar a mano. Ahí la
respuesta va a `_top`, que con `turbo-refresh-method: morph` **actualiza la
pantalla sin recargarla**. Lo decide `marco_para_pedido_de_ia`.

### `context_snapshot`

Una tarea tiene que poder **reconstruirse** cuando alguien acepta la sugerencia
más tarde. Lo que no se deduce de los ids del run (qué campo se estaba
redactando, cuántas ideas se pidieron) se persiste en
`ai_runs.prompt["context"]`.

Sin eso, aceptar una sugerencia de `CoauthorField` en modo assisted falla porque
la tarea se rearma sin saber sobre qué campo trabajaba.

### `DetectDuplicates` tiene DOS caminos, y elige según el proveedor

Lo decide `Provider#embeddings?`:

| Con vectores | Sin vectores |
|---|---|
| Coseno local sobre `#embed`. Determinista y barato — es lo que hace el fixture | Se le pregunta al modelo por `#complete`, que además **explica** el parecido |

La explicación no es un extra: es lo que una persona necesita para decidir si
fusiona. El Runner no sabe de embeddings, pregunta `task.local?(provider)`.

Tres detalles que se pagan si se olvidan:

- **A quién se le piden los vectores.** El Runner le pasa a la tarea el
  proveedor de **chat**; los vectores se piden a `Flow::AI.embeddings_provider`,
  que es otro objeto. Preguntarle al de chat dejaba al de embeddings sin usarse
  nunca, con la credencial puesta y todo. Hay spec de eso.
- Los ids posibles viajan como `enum` en el schema: el modelo no puede señalar
  una idea inexistente ni de otro desafío.
- Sin candidatas la tarea se resuelve local, para no gastar una llamada
  preguntando por una lista vacía.

Y si el proveedor de embeddings falla, `run_locally` devuelve `nil` y el Runner
cae a `#complete`: un proveedor caído no puede romper una tarea que sabe
arreglárselas sin él.

Se compara contra **todas** las ideas del desafío, borradores y eliminadas
incluidas: «esto ya se propuso y no avanzó» es de las cosas más útiles que el
chequeo puede decir. El estado lo pone la app en el preview, no el modelo.

Con fixtures los embeddings son deterministas pero **sin semántica real** — el
flujo se ejercita entero, la utilidad requiere un proveedor de verdad.

---

## pgvector: dónde viven los vectores

`idea_versions.embedding vector(1024)`, con índice HNSW (`vector_cosine_ops`).

**En la versión y no en la idea** porque la versión es contenido inmutable: el
vector se calcula una vez y nunca queda viejo. Al lado va `embedding_model` —
dos modelos distintos no producen vectores comparables, y sin ese dato no habría
forma de saber cuáles rehacer.

Cuatro trampas, las cuatro ya pagadas:

- **`add_column … :vector, limit: N` no sirve.** Rails no conoce el tipo, ignora
  el `limit` y deja una columna sin dimensión que después no se puede indexar
  («column does not have dimensions»). Va en SQL: `ADD COLUMN embedding
  vector(1024)`.
- El tipo desconocido hace que cada proceso escupa «unknown OID». Se registra
  como string en `config/initializers/pgvector.rb`; nunca se lee como número.
- **La dimensión ata el modelo.** 1024 deja abiertos Voyage (nativa) y OpenAI
  (truncable por parámetro). Cambiarla es recrear la columna.
- El atajo por vector entra **solo arriba de `DetectDuplicates::NEIGHBOURS`**.
  Buscar entre diez no ahorra nada, y con vectores sin semántica real podría
  dejar afuera justo la duplicada. Es un mecanismo de escala, no de calidad.

Publicar una versión encola `EmbedVersionJob`: calcular el vector llama a un
servicio externo, y publicar una idea no puede depender de que responda.
`make embeddings` completa lo que falte (`FORCE=1` rehace lo de otro modelo).

---

## Idempotencia

`ai_runs.idempotency_key` es un hash de `(purpose, messages)`, único por
empresa. Un pedido idéntico **no vuelve a llamar** al proveedor, y un retry de
Sidekiq no duplica la llamada ni las sugerencias.
