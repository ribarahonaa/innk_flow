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

## Aceptar es un solo lugar

`Flow::AI::ApplySuggestion` corre exactamente el mismo `task.apply!` que usa la
auto-aceptación. Editar antes de aceptar guarda el payload que **realmente se
aplicó** (`status: "edited"`), no el que propuso el modelo.

---

## El proveedor es abstracto

```ruby
Flow::AI::Provider
  #complete(messages:, schema:, purpose:, temperature:) -> Result
  #embed(texts:) -> [[Float]]
```

| Adapter | Para qué |
|---|---|
| `Providers::Fixture` | **Default.** Determinista, sin red, sin API key |
| `Providers::Null` | Siempre falla: ejercita el camino de error |

Se elige con `FLOW_AI_PROVIDER`. Enchufar uno real es agregar un adapter y
cambiar la variable — nada más del sistema cambia.

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
| `GenerateIdeas` | ideation | Crea ideas `origin: "ai"`, ya postuladas |
| `CoauthorField` | ideation | **Publica una versión nueva** — no pisa |
| `DetectDuplicates` | ideation | Nada: es informativa |
| `SuggestFeedback` | evolution | Crea `feedback_items` |
| `SummarizeChallenge` | reporting | Crea un `report` de kind `narrative` |

### `context_snapshot`

Una tarea tiene que poder **reconstruirse** cuando alguien acepta la sugerencia
más tarde. Lo que no se deduce de los ids del run (qué campo se estaba
redactando, cuántas ideas se pidieron) se persiste en
`ai_runs.prompt["context"]`.

Sin eso, aceptar una sugerencia de `CoauthorField` en modo assisted falla porque
la tarea se rearma sin saber sobre qué campo trabajaba.

### `DetectDuplicates` tiene camino propio

No pasa por `#complete`: usa `#embed` y calcula similitud coseno localmente. El
Runner lo detecta con `respond_to?(:run_locally)` en vez de forzar la forma
equivocada. Con fixtures los embeddings son deterministas pero **sin semántica
real** — el flujo se ejercita entero, la utilidad requiere un proveedor de
verdad.

---

## Idempotencia

`ai_runs.idempotency_key` es un hash de `(purpose, messages)`, único por
empresa. Un pedido idéntico **no vuelve a llamar** al proveedor, y un retry de
Sidekiq no duplica la llamada ni las sugerencias.
