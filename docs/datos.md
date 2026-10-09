# El modelo de datos

**34 tablas de dominio** (más cinco de infraestructura: las tres de Active
Storage, `schema_migrations` y `ar_internal_metadata`). Esto es el mapa, y
después las invariantes del esquema —las que Postgres hace valer, y que por eso
no se pueden romper desde Ruby—.

## Las cuatro invariantes del esquema

Antes de las tablas, porque explican cómo están escritas.

### 1. La idea es identidad; la versión es contenido

`ideas` **no tiene columna `title`**. El contenido vive en `idea_versions`, que
es inmutable: cada cambio publica `v(n+1)` con snapshot completo en
`payload jsonb`, y `ideas.current_version_id` apunta a la vigente.

Toda nota, feedback, evaluación y decisión guarda **qué versión juzgó**
(`idea_version_id`), así que nada queda huérfano cuando la idea avanza: queda
*anclado*, y la UI lo marca.

> **Trampa de specs:** `Idea#title` sale de `current_version&.title` y sin
> versión publicada devuelve `"(sin título)"` para TODAS. Una aserción que
> compara títulos entre ideas sin versión no distingue ninguna de otra —y pasa
> sola—. Se asevera sobre la URL, o se le publica una versión con título propio.

### 2. FKs compuestas `(x_id, company_id)`

**70 de las 126 FKs del esquema son compuestas**, apuntando a un
`UNIQUE (id, company_id)` del padre (hay **30**). Postgres **rechaza** atar una
fila de la empresa A a un padre de la B: el aislamiento es del motor, no del
código.

Las otras 31 son el `company_id → companies(id)` de cada tabla con tenant, y el
resto son FKs a tablas globales (`users`, `sessions`).

```sql
ADD CONSTRAINT ai_runs_challenge_id_same_company
  FOREIGN KEY (challenge_id, company_id)
  REFERENCES public.challenges(id, company_id) ON DELETE CASCADE;
```

Se escriben con `lib/flow/migration_helpers.rb` (`tenant_table`,
`add_tenant_fk`). **Trampa:** `ON DELETE SET NULL` sobre una FK compuesta nulea
**todas** las columnas, incluida `company_id` que es NOT NULL — el helper usa
`SET NULL (columna)`, que pide PG 15+.

De ahí sale `schema_format = :sql`: `schema.rb` no serializa FKs compuestas y se
perderían en cada `db:prepare`. **Después de migrar, commiteá
`db/structure.sql`.**

### 3. PKs UUIDv7

Todas. No adivinables —un id secuencial es un oráculo de enumeración
cross-tenant— y ordenados por tiempo, así que los índices no se fragmentan.

De rebote hay una propiedad de seguridad que **no se lee del código**: una
columna `uuid` hace que `OID::Uuid#cast_value` convierta basura, un no-entero o
una clave ausente en `nil` **antes** de llegar al SQL. Dos lugares dependen de
eso —`workshop_drafts.based_on_version_id`, que lo manda el cliente, y el
parámetro `mesa` de la sala—: la consulta queda `id IS NULL` y cae al lado
seguro. Si una de esas columnas cambiara de tipo, se iría la mitad de la
defensa sin que nada se ponga rojo.

### 4. La posición es mutable, las referencias van por `slug`

`challenge_steps."position"` es `numeric(20,10)` con
`UNIQUE (challenge_id, position) DEFERRABLE INITIALLY DEFERRED`: insertar entre
A y B es `(a+b)/2`, y el `DEFERRABLE` es lo que deja reordenar en un solo
UPDATE sin pasar por posiciones temporales.

Por eso **las referencias entre módulos van por `slug`, no por posición**
(`challenge_steps.source_step_id` existe, pero lo que la configuración guarda es
el slug). La posición es mutable por diseño.

## Las tablas, por subsistema

### Tenencia e identidad — las cuatro globales

| Tabla | Qué es |
|---|---|
| `companies` | El tenant. `name`, `slug` |
| `users` | La persona. `email`, `name`, `password_digest`. **Global**: una persona puede estar en varias empresas |
| `memberships` | `(company_id, user_id, role)`. **El rol es por empresa** |
| `sessions` | `token`, `user_id`, **`company_id`**: la empresa elegida vive en la sesión |
| `identities` | `provider`, `uid`, `data`. La costura para SSO real, desde el día 1. Sin usar |

`companies`, `users`, `sessions` e `identities` son las **cuatro que no llevan
`TenantScoped`**: son globales por definición. Todo lo demás lo lleva.

`memberships.role` ∈ `admin · gestor · evaluator · participant`.

> **Nota:** `challenge_gestores` y el valor `"gestor"` están en español. Es
> herencia de una regla anterior y **no se renombran**: es una migración con
> cambio de datos que toca modelo, rutas, policies, seeds, el CHECK de Postgres
> y las capturas. **Toda tabla y toda columna nueva va en inglés.**

### El desafío y su flujo

| Tabla | Qué es |
|---|---|
| `challenges` | `slug`, `name`, `brief`, `status` ∈ `draft · running · closed · archived`, `ai_default_mode`, `lock_version` |
| `challenge_steps` | Un módulo del flujo. `kind`, `slug`, `name`, `position`, `status`, `ai_mode`, `config`, `resolved_config`, `criteria_set_id`, `source_step_id`, `lock_version` |
| `challenge_gestores` | `(challenge_id, user_id)`: a qué desafíos llega un gestor |
| `step_assignments` | `(challenge_step_id, user_id, role, weight)`: **quién evalúa y cuánto pesa** |
| `step_entries` | Una idea dentro de un módulo. `status`, `input_version_id`, `output_version_id`, `result jsonb`. **Es el cohorte** |

`challenge_steps.kind` ∈ `ideation · evolution · evaluation · selection ·
reporting · testing`. `ideation` es el único singleton.

`challenge_steps.status` ∈ `pending · activating · active · completed ·
skipped`. Los cuatro últimos son `TOUCHED_STATUSES`, y `touched?` es lo que
decide **qué cara de la pantalla se renderiza**: pendiente muestra la
configuración, tocado muestra el trabajo.

`step_entries.status` ∈ `pending · in_progress · done · advanced · eliminated`.

**`config` vs `resolved_config` es el late binding**: `config` guarda la
intención («el módulo de evaluación anterior»), `resolved_config` se escribe
**una sola vez** en `activate!` con ids concretos. Se lee siempre por
`step.settings`, el único accesor público, que devuelve el resuelto si el módulo
ya arrancó.

**En `config` un hueco no es «sin valor»: es el default del esquema.** Sólo un
camino siembra `StepSettings.defaults`; las plantillas mandan configs parciales
y el seed no manda ninguna, y los handlers leen con `fetch(clave, default)`. Se
lee con `StepSettings.efectivo(kind, settings)`.

### La idea

| Tabla | Qué es |
|---|---|
| `ideas` | Identidad. `author_id`, `current_version_id`, `status` ∈ `draft · active · eliminated · withdrawn`, `origin` ∈ `human · ai`, `eliminated_at_step_id` |
| `idea_versions` | **Contenido inmutable.** `number`, `title`, `payload jsonb`, `actor_type` ∈ `human · ai · workshop`, `source_step_id`, `change_note`, **`embedding vector(1024)`**, `embedding_model`, `embedded_at` |
| `idea_contributors` | `(idea_id, user_id, role)` ∈ `contributor · sponsor · reviewer`. **Colaborar es una de las dos formas de participar** |
| `idea_attachments` | Cuelga de la **versión**, con su `field_key` |
| `form_fields` | Los campos del formulario de postulación, por módulo de ideación. `key`, `label`, `field_type`, `required`, `config` |

**El vector vive en la versión y no en la idea** porque la versión es contenido
inmutable: se calcula una vez y nunca queda viejo. Al lado se guarda
`embedding_model`, porque dos modelos distintos no producen vectores
comparables y sin ese dato no habría forma de saber cuáles rehacer. Índice HNSW
`vector_cosine_ops`. Ver [`ai.md`](ai.md).

### Criterios y puntuación

| Tabla | Qué es |
|---|---|
| `criteria_sets` | `name`, `scope` ∈ `library · inline`, `owner_step_id`, `status`, **`family_id`, `version`, `superseded_at`** |
| `criteria` | **La tabla se llama `criteria`**, el modelo `Criterion`. `key`, `name`, `weight`, `source`, `source_config`, `scale_type`, `scale_config`, `active` |
| `assessments` | Una evaluación de una idea. `evaluator_id`, `actor_type` ∈ `human · ai`, `status` ∈ `pending · submitted`, `normalized_score`, `raw_score`, `superseded_at` |
| `assessment_scores` | Un criterio dentro de una evaluación. `criterion_key`, `weight_used`, `raw_value`, `numeric_value`, `normalized_value` |

`criteria.source` ∈ `manual · automatic · ai · formula` (quién produce el
valor) y `criteria.scale_type` ∈ `numeric · letter · rubric · boolean` (qué
forma tiene). **Son dos ejes independientes, y el origen manda cuando determina
la forma**: `automatic` fuerza `boolean` y `formula` fuerza `numeric`.

**La biblioteca no se pisa: se versiona.** `family_id` + `version` +
`superseded_at`: guardar un set de biblioteca que ya usa algún módulo crea la
versión siguiente y deja la anterior intacta. Ver [`criteria.md`](criteria.md).

`Criterion` fija `self.table_name = "criteria"` **explícitamente**: un proceso
que arranque antes del initializer de inflexiones busca `criterions`.

`assessment_scores` guarda `criterion_key` **además** de `criterion_id`: la FK
es `ON DELETE SET NULL (criterion_id)`, así que borrar el criterio no se lleva
el puntaje histórico y la `key` sigue diciendo de qué era.

### Feedback, selección y testing

| Tabla | Qué es |
|---|---|
| `feedback_items` | `challenge_step_id` (**a qué ronda pertenece**), `kind` ∈ `suggestion · question · issue`, `body`, `addressed`, `addressed_by_version_id`, `resolution` ∈ `answered · acknowledged · dismissed` |
| `selection_decisions` | `outcome` ∈ `advance · eliminate · reinstate`, `rank`, `score`, `decided_by_id`, `reason` |
| `selection_verdicts` | El filtro criterio por criterio: `criterion_key`, `passed`, `note` |
| `step_tests` | `verdict` ∈ `factible · con_reservas · no_factible`, `situations jsonb`, `reservations jsonb`, `summary`, `superseded_at` |

**`feedback_items.challenge_step_id` no es un dato de auditoría: es a qué
conversación pertenece el comentario.** Un desafío puede tener varias rondas de
evolución, y mezclarlas hace que lo viejo se lea como lo que hay que atender
ahora. De ahí tres consecuencias que están en el código y no en el esquema:
el tablero filtra por su paso, la ficha agrupa por ronda, y `evolve_idea` toma
**sólo el feedback abierto de SU ronda**.

### La IA

| Tabla | Qué es |
|---|---|
| `ai_runs` | **Toda** llamada deja una fila, también con el adapter de fixtures. `purpose`, `mode` ∈ `ai_assisted · ai_auto`, `status` ∈ `queued · running · succeeded · failed`, `prompt`, `response`, `provider`, `model`, `tokens_in/out`, `latency_ms`, `error`, `idempotency_key`, `redacted_at` |
| `ai_suggestions` | Lo que propuso. `payload jsonb`, `status` ∈ `pending · accepted · edited · rejected`, `reviewed_by_id`, `auto_accepted_at` |

`ai_runs.purpose` son **trece**: `suggest_criteria`, `propose_pipeline`,
`suggest_form_fields`, `generate_ideas`, `coauthor_field`, `detect_duplicates`,
`suggest_feedback`, `evaluate_idea`, `decide_verdicts`, `evolve_idea`,
`summarize_challenge`, `test_idea`.

Y **hay un CHECK de Postgres sobre esa columna**: sumar una tarea sin la
migración revienta con `PG::CheckViolation` antes de crear el run, y el error
llega truncado.

`ai_auto` **no saltea la sugerencia**: la auto-acepta (`auto_accepted_at`), para
que haya un solo code path y el mismo rastro de auditoría.

### El taller

| Tabla | Qué es |
|---|---|
| `workshops` | `mode` ∈ `individual · group`, `status` ∈ `draft · open · closed`, **`attendance_mode`** ∈ `presumed · registered`, **`checkin_token`**, `scheduled_at` |
| `workshop_challenges` | **El vínculo**: `(workshop_id, challenge_id, challenge_step_id)`, `status` ∈ `open · closed`, `closed_reason` |
| `workshop_groups` | Una mesa. `name`, **`arrival boolean`** con índice UNIQUE parcial |
| `workshop_group_members` | El asiento. `(workshop_id, user_id)` UNIQUE, **`attended boolean`** default `true` |
| `workshop_proposals` | Lo que la mesa propone para una idea. `payload`, `status` ∈ `pending · accepted · rejected` |
| `workshop_drafts` | El autoguardado. `payload`, **`based_on_version_id`**, `updated_by_id`. Dos UNIQUE parciales: uno por `(mesa, vínculo)` en idear, uno por `(mesa, vínculo, idea)` en evolución |
| `workshop_recordings` | `status` ∈ `pending · transcribing · ready · failed`, `utterances jsonb`, `duration_seconds`, `provider`, `model`, `request_id` |

**Lo que ata el taller al desafío es el MÓDULO**
(`workshop_challenges.challenge_step_id`), resuelto al abrir con el mismo late
binding del pipeline. `Workshop#phase` **se deriva** de los vínculos vivos y no
se guarda: una columna sería la segunda fuente que el día que difiera miente.

**`attended` y no `present`:** en Rails una columna `present` genera `present?`,
que choca con `Object#present?` de ActiveSupport, y el choque no revienta —
devuelve otra cosa, que es la peor forma de romperse—.

Ver [`taller.md`](taller.md) para el resto.

### Salidas y avisos

| Tabla | Qué es |
|---|---|
| `reports` | `kind` ∈ `funnel · ranking · snapshot · narrative`, `format`, `status` ∈ `pending · ready · failed`, `scope`, `data`, `row_count` |
| `notifications` | `kind` ∈ `assigned_to_evaluate · feedback_received · idea_advanced · idea_eliminated`, `payload`, `read_at` |

### Active Storage

Las tres tablas de Active Storage **quedan afuera de las cuatro capas de
tenencia**: no llevan `company_id` ni FK compuesta. Está anotado en
[`tenancy.md`](tenancy.md), con lo que eso implica.

## Lo que Postgres hace valer y Ruby no

Resumen para cuando algo falla con un error de base en vez de una validación:

| Constraint | Dónde | Qué frena |
|---|---|---|
| FK compuesta `(x_id, company_id)` | 70 lugares | Atar una fila a un padre de otra empresa |
| `UNIQUE (challenge_id, position) DEFERRABLE` | `challenge_steps` | Dos módulos en la misma posición (diferido: el reorden pasa por estados intermedios) |
| `UNIQUE (workshop_id, user_id)` | `workshop_group_members` | Dos asientos para la misma persona. **Es la carrera que `Convoke` y `CheckIn` rescatan** |
| UNIQUE parcial sobre `arrival` | `workshop_groups` | Dos mesas de llegada. **Lo rescata `Workshop#arrival_group!` con un savepoint** |
| CHECK sobre `kind` / `purpose` / `status` / `mode` | varias | Un valor de enum nuevo sin migración |
| `ON DELETE CASCADE` en `workshop_proposals.workshop_group_id` | | **Borrar una mesa se lleva sus propuestas.** De ahí el guarda que se niega a repartir con propuestas |

Los dos rescates de UNIQUE no son prolijidad: son `exists?`-seguido-de-`save` y
`SELECT`-seguido-de-`INSERT`, y dos pedidos concurrentes los atraviesan. Que la
base frene al segundo es correcto; lo que no corresponde es un 500 en la cara de
quien está entrando a un taller.

## Los specs que cuidan esto

`spec/tenancy/` son **seis**, y los tres principales están probados por
mutación: un modelo sin `TenantScoped`, un `.unscoped`, una FK simple donde iba
compuesta — **cada uno pone la suite en rojo**.

En los specs esto muerde: **toda lectura del dominio va dentro de
`as_company(company) { ... }`**, incluido un `.new` (toca el `default_scope`) y
cualquier asociación leída después de salir del bloque.
