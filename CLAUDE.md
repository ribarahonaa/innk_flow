# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Lee primero el `README.md`: tiene los cinco módulos, la regla de mutación del
pipeline y las decisiones de infraestructura. Los `docs/*.md` (`tenancy`, `ai`,
`criteria`, `pipeline`) tienen el detalle. Esto es lo que no está ahí.

El código, los comentarios y los mensajes de commit van **en español**.

## Comandos

Todo corre en Docker. Nunca `bundle exec` en el host.

```bash
make setup                                  # primera vez
make up / down / reup / rebuild             # stack (rebuild al agregar una gema)
make spec                                   # suite completa
make spec-file FILE=spec/requests/x_spec.rb
make spec-line FILE=spec/requests/x_spec.rb LINE=42
make screens                                # recorrido E2E con Playwright
make embeddings                             # calcula los vectores que falten
make yarn-build                             # recompilar JS/CSS
make rails / psql / logs-app / logs-sidekiq
```

**Los specs corren en `app_test`, no en `app`.** `make spec` usa
`docker compose --profile test run --rm app_test`. Correr `docker compose exec
app bundle exec rspec` usa el contenedor de **desarrollo**: `RAILS_ENV` queda en
`development`, `config.hosts` trae los defaults de dev y **todos los request
specs devuelven 403 «Blocked hosts: www.example.com»**. Se ve como si la app
estuviera rota. Usá siempre `make spec*`.

Para bajar el contenedor de test: `docker compose --profile test stop app_test`.
`docker compose --profile test down` se lleva puesto el stack entero, base
incluida.

No hay linter configurado.

## Verificación

**`make screens` es la verificación end-to-end real**, no un extra. Recorre la
app corriendo con un navegador y falla si hay error de JS, HTTP >= 400 o si
queda un `.island-placeholder` sin montar. Corrélo después de tocar vistas,
islas o CSS — un bug de Vue no lo atrapa ningún spec de Ruby (un
`__VUE_OPTIONS_API__` mal puesto dejó el builder en blanco y la suite en verde).

Al escribir capturas nuevas en `script/capture_screens.js`:

- Navegá **por link**, no con `goto`. Turbo no dispara `DOMContentLoaded` al
  navegar por link; un `goto` monta la isla igual y esconde el bug.
- Después de un clic, esperá `waitForURL` o un selector — `networkidle` se
  calma antes de que Turbo ponga el body nuevo, y la captura sale de la
  pantalla anterior.
- Las islas exponen `data-island-mounted="true"` como señal determinista.

**Los system specs con navegador no cubren el recorrido.** Los servicios usan
`with_lock` (SELECT FOR UPDATE) y eso deadlockea contra el pool compartido de
Rails: el spec se **cuelga sin dar error**. Anotado en
`spec/system/smoke_spec.rb`. Los system specs existentes borran todo en un
`after`; si agregás uno, hacé lo mismo o dejás datos que ensucian corridas
posteriores.

`spec/system_support/driver.rb` se requiere **solo desde los system specs**:
cargar Capybara globalmente cuelga la suite entera.

**Nunca `click_link` a secas en un system spec.** Turbo pinta la copia cacheada
de una página mientras pide la definitiva; si el clic cae en esa ventana,
Capybara toma un elemento que Turbo está por reemplazar y Playwright falla con
«Element is not attached to the DOM». Usá `click_link_settled`
(`spec/system_support/turbo.rb`), que espera a que se vaya
`<html data-turbo-preview>`. El síntoma es una falla de una cada tres corridas
**solo con la suite completa** — en aislamiento pasa siempre.

## Arquitectura: lo que hay que leer junto

### El motor del pipeline

`app/lib/flow/pipeline.rb` es el corazón. `insertion_floor` implementa la regla
dura del producto (con el flujo en curso solo se inserta después del último
módulo tocado; `skipped` cuenta como tocado). La regla vive acá **y** replicada
como validación de modelo, y el builder solo la dibuja.

`Flow::Handlers::Base.for(step)` despacha por `kind` a los cinco handlers.
`activate!` y `complete!` son idempotentes; toda mutación va con
`challenge.with_lock` + `lock_version` optimista.

**Late binding:** `step.config` guarda la intención, `resolved_config` se
escribe una sola vez en `activate!` con ids concretos. Leé siempre
`step.settings` — es el único accesor público y devuelve el resuelto si el
módulo ya arrancó.

**Qué se congela al arrancar** (`ChallengeStep::FROZEN_ATTRIBUTES`): `kind`,
`slug`, `position`, `config`, `source_step_id` y los criterios.
**Qué sigue ajustable** (`ADJUSTABLE_ATTRIBUTES`): `name` y `ai_mode`. Cambiar
el modo de IA de un módulo en curso es una política operativa, no una reescritura
del pasado.

Las referencias entre módulos van **por `slug`**, no por posición: la posición
es mutable por diseño (`decimal(20,10)`, insertar entre A y B es `(a+b)/2`).

### Los tres esquemas de configuración

Son fuente única: la UI los renderiza, no declara campos propios. Agregar una
opción es agregar una línea al esquema, sin tocar Vue.

| Archivo | Qué declara | Quién lo consume |
|---|---|---|
| `Flow::StepSettings` | Qué configura cada `kind` de módulo | panel del builder |
| `Flow::CriterionSettings` | Qué parámetros pide cada verificación y cada escala | editor de criterios |
| `Flow::FlowTemplates` | Puntos de partida del flujo | creación del desafío y builder vacío |

### Criterios: dos ejes independientes

`source` (quién produce el valor: `manual` / `automatic` / `ai` / `formula`) y
`scale_type` (qué forma tiene: `numeric` / `letter` / `rubric` / `boolean`).
**El origen manda cuando determina la forma**: `align_scale_with_source` fuerza
`boolean` para automático y `numeric` para fórmula, así que el editor ni ofrece
la opción.

Toda escala aterriza en `[0,1]`. Las fórmulas van por dentaku, **nunca** `eval`.

Un `criteria_set` con `scope: "library"` se comparte entre desafíos; uno
`inline` es de un módulo. Editar un set de biblioteca desde un módulo tocaría
todos los desafíos que lo usan — por eso se copia (`StepCriteriaController`).

**La biblioteca no se pisa: se versiona.** Guardar un set de biblioteca que ya
usa algún módulo crea la versión siguiente (`family_id`, `version`,
`superseded_at`) y deja la anterior intacta; los módulos que la usaban siguen
con ella hasta que alguien los pase a la nueva desde el builder. Un set que no
usa nadie se edita en el lugar: versionar lo que nadie tiene asignado no
protege a nadie.

Esto reemplaza al candado por evaluaciones **solo en la biblioteca**: sobre una
versión nueva nadie puntuó nada, así que peso y escala vuelven a ser editables.
En un set `inline` no hay a quién proteger copiando, y el candado sigue siendo
la respuesta (`locked?` en `Api::V1::CriteriaSetsController`).

Dos trampas: el fork va **dentro** de la transacción del guardado (si falla, no
queda una versión huérfana), y los criterios que llegan traen los ids de la
versión anterior — `fork_version!` los traduce por `key` a los de la copia, o
la reconciliación borraría todo y lo crearía de nuevo.

### Los cuatro roles

`admin` administra · `gestor` acompaña la evolución · `evaluator` evalúa lo que
se le asigna · `participant` postula y comenta. `owner` **no existe**: daba los
mismos permisos que `admin`.

Dos reglas que no viven en el rol:

- **Evaluar depende de la asignación**, no del rol (`step_assignments`). Y
  **nadie evalúa una idea de la que participa**, ni siquiera quien administra.
  Por eso el mínimo de evaluaciones baja por idea cuando su autor está entre
  quienes evalúan: esperar el mínimo entero trabaría el módulo esperando una
  evaluación imposible.
- **No todas las voces pesan igual.** `step_assignments.weight` entra en el
  agregado, en la dispersión y en el promedio por criterio. Dos reglas que no
  se ven en el código si no se buscan: los pesos **solo** entran cuando alguien
  puso pesos distintos (con todos iguales la mediana ponderada no devuelve lo
  mismo que la mediana de siempre, y asignar gente sin tocar pesos no puede
  mover un puntaje ya calculado); y **cambiar un peso recalcula todas las
  entries del módulo**, porque si no la tabla sigue mostrando el número viejo.
  Quien ya evaluó no se desasigna —su nota quedaría sin respaldo—, y con el
  módulo cerrado no se toca nada.
- **Quien participa ve solo las ideas en las que participa** —las que creó y
  aquellas en las que colabora—: compite por el mismo corte que las demás. La
  regla vive UNA vez, en `IdeaPolicy::Scope`, y las pantallas la aplican:
  `StepsController#show` publica `@ideas_visibles` y los módulos filtran con
  eso lo que listan. Lo que no se ve da **404**, no 403. Quien administra,
  acompaña o evalúa las ve todas: las tres cosas se hacen sobre el pool entero.
- **Pedirle a la IA que evalúe no es evaluar.** El botón —y el lote «evaluar
  todas con IA»— es de quien evalúa en el módulo, por asignación o por
  administrarlo, no de `update_pipeline?`. Y va **sin idea**: quien participa
  de una idea no la puntúa, pero sí puede pedir que la IA la evalúe, porque la
  nota es de la IA. Bloquearlo trabaría el módulo, ya que `min_assessments_for`
  baja el mínimo contando a la IA justamente como quien evalúa lo que su autor
  no puede. La regla está en un solo lugar y las tres puertas la consultan
  (`AiSuggestionPolicy#evaluacion`, `AiRequestsController#autorizar!`,
  `StepsController#evaluate_all`).
- **El puntaje y el desglose son cosas distintas.** Quien participa de una idea
  ve su resultado agregado cuando el módulo cierra; **quién puso qué** lo ven
  solo quien administra y quien evaluó esa idea. Por eso hay dos predicados en
  el handler (`score_visible_for?` y `breakdown_visible_for?`) y no uno.
- **El gestor es interempresa**: una membresía con rol `gestor` por cada
  empresa, igual que cualquiera que esté en más de una. Lo nuevo es que tener
  membresía dejó de significar ver todo: un gestor solo ve los desafíos de
  `challenge_gestores`. Se **asigna desde el módulo de evolución**, que es donde
  tiene algo que hacer —igual que los evaluadores se asignan desde el módulo de
  evaluación—, aunque el acceso que otorga es al desafío entero y la pantalla lo
  dice. La ficha del desafío solo lo ofrece si quedaron gestores sin módulo de
  evolución donde administrarlos. Por eso **los controllers buscan el desafío con
  `policy_scope(Challenge).find_by!`** y no con `Challenge.find_by!` — así lo
  no asignado da 404 y no 403, que sería un oráculo de existencia.

### El feedback pertenece a su ronda

`feedback_items.challenge_step_id` no es un dato de auditoría: es a qué
conversación pertenece el comentario. Un desafío puede tener varias rondas de
evolución, y mezclarlas hace que lo viejo se lea como lo que hay que atender
ahora.

- El tablero del módulo ya filtraba por su paso (`feedback_index`).
- La **ficha de la idea** agrupa por ronda: la que está en curso, abierta; las
  cerradas, en un `details` plegado —la historia no se esconde, pero plegada no
  se confunde—. Solo la ronda abierta ofrece cerrar comentarios, porque
  `puede_resolver` mira `step.active?`.
- **`evolve_idea` toma solo el feedback abierto de SU ronda.** Arrastrar lo que
  quedó sin atender en una ronda anterior mezcla dos conversaciones.

- El criterio automático **`feedback_addressed` mira solo la última ronda**. Un
  check no sabe en qué módulo lo están corriendo —solo tiene su `criterion`—,
  así que «la última» es la ronda más reciente que LE DIO feedback a esa idea:
  no se puede tener sin atender lo que nadie comentó. Mirando todas, lo que
  quedó abierto en una ronda vieja bloqueaba a la idea para siempre, porque
  nadie vuelve a cerrar comentarios de una conversación que ya terminó.

### Multi-tenancy: cuatro capas

1. `Flow::Tenant.with(company)` para entrar. `bypass!` es la única válvula de
   escape: explícita y greppable (jobs, seeds, tasks).
2. `TenantScoped` tiene un `default_scope` que **revienta** con `MissingTenant`
   sin tenant en contexto, en vez de devolver todo.
3. Los controllers devuelven **404, nunca 403**: un 403 es un oráculo de
   existencia.
4. FKs compuestas `(x_id, company_id)`: Postgres rechaza atar una fila de la
   empresa A a un padre de la B.

En los specs esto muerde: **toda lectura del dominio va dentro de
`as_company(company) { ... }`**, incluido un `.new` (toca el `default_scope`) y
cualquier asociación leída después de salir del bloque. Los specs de guardia
están en `spec/tenancy/`; los tres principales están probados por mutación (un
modelo sin `TenantScoped`, un `.unscoped`, una FK simple: cada uno pone la suite
en rojo).

`lib/flow/migration_helpers.rb` tiene `tenant_table` y `add_tenant_fk`. Trampa:
`ON DELETE SET NULL` sobre una FK compuesta nulea **todas** las columnas,
incluida `company_id` que es NOT NULL — el helper usa `SET NULL (columna)`
(PG 15+).

### La capa de IA

`Flow::AI::Runner` es el único camino para los tres modos. `ai_auto` **no**
saltea la sugerencia: la auto-acepta, para que haya un solo code path y el mismo
rastro de auditoría. Un run se reutiliza solo mientras está "vivo" (en curso, o
con sugerencia pendiente de revisión): pedir de nuevo algo ya descartado tiene
que generar un run nuevo, no devolver la sugerencia muerta.

El proveedor se resuelve en `Flow::AI.provider` desde `FLOW_AI_PROVIDER`.
`fixture` es el default (determinista, sin red ni credenciales); `anthropic` es
el adapter real y **cada llamada cuesta plata**, así que nunca es el default.
Los JSON Schema validan en los dos caminos, así que no hay drift.

El adapter real tiene dos cosas no obvias: poda del schema las palabras que la
API rechaza con 400 (`minItems`, `pattern`, …) pero valida la respuesta contra
el schema **original**; y trata `stop_reason: :refusal` y `:max_tokens` como
fallas explicadas, porque llegan con HTTP 200 y no como excepción.

**Un 500 de Voyage en TODO pedido no es el pedido.** Con la credencial
autenticando (sin ella da 401), la validación funcionando (cuerpo vacío da 400)
y el ruteo bien (GET da 405), que embeddings, rerank y contextual devuelvan los
tres 500 —incluso con un modelo inexistente, que debería dar 400— significa que
la cuenta autentica pero no tiene inferencia habilitada. Voyage contesta 500 en
vez de un 402 que lo diga. La pista está en el mensaje del adapter para no
volver a sondear.

**Hay DOS proveedores, no uno.** `FLOW_AI_PROVIDER` (chat) y
`FLOW_EMBEDDINGS_PROVIDER` (vectores) son capacidades distintas: Anthropic no
expone embeddings, así que con una sola variable no se podía tener chat real y
vectores reales a la vez. Sin declarar el segundo se usa el de chat si sabe
hacerlos, y si no el fixture.

Los adapters de embeddings (`Providers::Openai`, `Providers::Voyage`) heredan
de `HttpEmbeddings`, que trae lo que es fácil hacer mal —respetar el índice de
cada fila, partir en lotes, validar la dimensión, llevar el código HTTP al
error— y deja a cada uno su URL, su cuerpo y dónde pone el mensaje de error.
Solo hacen `embed`: su `complete` levanta `ProviderUnsupported`.

**Ojo con a quién se le piden los vectores.** El runner le pasa a la tarea el
proveedor de CHAT. `DetectDuplicates` usa `Flow::AI.embeddings_provider`, que es
otro objeto: preguntarle al de chat dejaba al de embeddings sin usarse nunca,
con la credencial puesta y todo. Y si el de embeddings falla, `run_locally`
devuelve `nil` y el runner cae a `#complete` — un proveedor caído no puede
romper una tarea que sabe arreglárselas sin él.

**Detectar duplicados tiene dos caminos, y elige el proveedor.**
`Provider#embeddings?` decide: con vectores se compara por coseno local
(determinista y barato, es lo que hace el fixture); sin ellos se le pregunta al
modelo por `#complete`, que además **explica** el parecido —que es lo que una
persona necesita para decidir si fusiona—. El runner no sabe de embeddings:
pregunta `task.local?(provider)`. Dos detalles que se pagan si se olvidan: los
ids posibles viajan como `enum` en el schema (el modelo no puede señalar una
idea inexistente ni de otro desafío), y sin candidatas la tarea se resuelve
local para no gastar una llamada preguntando por una lista vacía.

Se compara contra **todas** las ideas del desafío, borradores y eliminadas
incluidas: «esto ya se propuso y no avanzó» es de las cosas más útiles que el
chequeo puede decir. El estado lo pone la app en el preview, no el modelo.

### pgvector

Los vectores viven en `idea_versions.embedding vector(1024)` con índice HNSW
(`vector_cosine_ops`). En la **versión** y no en la idea porque la versión es
contenido inmutable: el vector se calcula una vez y nunca queda viejo. Junto al
vector se guarda `embedding_model` — dos modelos distintos no producen vectores
comparables, y sin ese dato no habría forma de saber cuáles rehacer.

Cuatro trampas, las cuatro ya pagadas:

- **`add_column … :vector, limit: N` no sirve.** Rails no conoce el tipo,
  ignora el `limit` y deja una columna sin dimensión que después no se puede
  indexar. Va en SQL: `ADD COLUMN embedding vector(1024)`.
- El tipo desconocido hace que cada proceso escupa «unknown OID». Se registra
  como string en `config/initializers/pgvector.rb`; nunca se lee como número
  en Ruby.
- **La dimensión ata el modelo.** 1024 deja abiertos Voyage (nativa) y OpenAI
  (truncable por parámetro). Cambiarla es recrear la columna.
- El atajo por vector entra **solo arriba de `DetectDuplicates::NEIGHBOURS`**.
  Buscar entre diez no ahorra nada, y con vectores sin semántica real (el
  fixture) podría dejar afuera justo la duplicada. Es un mecanismo de escala,
  no de calidad.

Publicar una versión encola `EmbedVersionJob`: calcular el vector llama a un
servicio externo y publicar una idea no puede depender de que responda.
`make embeddings` completa lo que falte (`FORCE=1` rehace lo de otro modelo).

Qué se aplica al pedirlo y qué no lo decide `applies_on_request?`. Una
evaluación de IA es **aditiva** —una opinión más en el promedio— así que pedirla
ya es aceptarla. Un **veredicto de selección no**: es LA respuesta del filtro y
decide quién queda afuera, así que en `ai_assisted` se propone y alguien la
acepta. Y la IA **nunca pisa un veredicto que puso una persona**, ni con el
módulo en automático: quien lo puso ya miró la idea (`pending_gates` en
`Tasks::DecideVerdicts`).

**Quién puede pedirle algo a la IA —y aceptarlo— depende de sobre qué actúa, y
eso lo declara la tarea** con `self.actua_sobre`:

| Alcance | Tareas | Lo autoriza |
|---|---|---|
| `:idea` | `coauthor_field`, `evolve_idea`, `detect_duplicates` | `IdeaPolicy#update?` |
| `:feedback` | `suggest_feedback` | `FeedbackItemPolicy#create?` |
| `:challenge` (default) | el resto | `ChallengePolicy#update_pipeline?` |

`AiRequestsController` y `AiSuggestionPolicy` preguntan lo mismo
(`Tasks::Base.scope_of`), así que pedir y aceptar no pueden divergir — que es
justo lo que pasaba: era todo `update_pipeline?` para pedir y «admin o autor»
para aceptar, así que quien participa no podía usar ninguna función de IA sobre
su propia idea y quien acompaña no podía aplicar el feedback que es su trabajo.

Sumar una tarea es tocar **tres** lugares: la clase, `AiRun::PURPOSES` y el
CHECK de Postgres sobre `ai_runs.purpose` (hace falta una migración; si no, el
run revienta con `PG::CheckViolation` antes de crearse y el error llega
truncado).

**A dónde responde un pedido a la IA depende de si ya cambió algo.** Por
defecto al `turbo-frame` de las propuestas: así pedir no recarga la pantalla ni
pierde lo que estuvieras editando. Pero en **`ai_auto`** la sugerencia se
auto-acepta, y las tareas **aditivas** se aplican al pedirlas: ahí refrescar
solo el marco deja el resto de la pantalla mostrando lo viejo —una idea
reescrita se seguía viendo como estaba hasta recargar a mano—. Lo decide
`marco_para_pedido_de_ia` en `ApplicationHelper`.

Las tareas de **autoría** (armar el flujo, proponer los campos del formulario)
se ofrecen aunque el módulo esté en «Solo personas»: ese modo define cómo se
trabaja *dentro* del desafío, no si su dueño puede pedir una mano para
diseñarlo. Es el `always: true` del partial `shared/_ai_actions`.

### Las pantallas se actualizan, no se recargan

El layout declara `turbo-refresh-method: morph`. Turbo 8 trata como *page
refresh* cualquier POST que redirija a la misma URL —que es lo que hace casi
todo acá, empezando por los pedidos a la IA— y con esa meta morfea el DOM en
vez de repintar la página. No hace falta `data-turbo-action` en los
formularios: Turbo ya elige `replace` solo cuando el redirect vuelve a donde
estabas.

Tres cosas que no son obvias:

- **`turbo-refresh-scroll: preserve` no conserva el scroll.** Solo le dice a
  Turbo que no scrollee él. El scroll se pierde *durante* el morph: mientras
  idiomorph tiene nodos afuera la página se acorta y el navegador recorta
  `scrollY`. Lo devuelve el bloque de `app/javascript/application.js`, que lo
  guarda en `turbo:before-render` y lo repone en `turbo:render` **solo si hubo
  `turbo:morph`**.
- **Después de un POST, Turbo NO cachea la página**
  (`shouldCacheSnapshot = formSubmission.isSafe`), así que `turbo:before-cache`
  no se dispara y no sirve para desmontar nada en el camino que importa.
  `islands.js` también escucha `turbo:before-render`.
- **El morph no rompe las islas**, medido en las dos pantallas donde una
  sugerencia de IA vuelve a la misma URL (`/challenges/:id/form` y los
  criterios del módulo): reemplaza el contenedor entero y `turbo:load` vuelve a
  montar con las props nuevas. `make screens` lo verifica sin gastar una
  llamada al proveedor, pidiendo a mano la misma navegación.

### Islas Vue

Tres: `pipeline_builder`, `form_editor`, `criteria_editor`. Se montan con
`app/javascript/islands.js`, que cubre `DOMContentLoaded`, `turbo:load` y el
script que llega tarde, y desmonta en `turbo:before-cache`.

Las props las serializa el **server** (`PipelinePresenter`,
`CriteriaSetPresenter`) y viajan en un `data-props`: una vuelta de red menos y
la tenencia la garantiza el scope de Ruby, no una ruta JSON que alguien podría
olvidar scopear.

**Las props son el estado INICIAL, no el estado.** Vue no hace reactivas las
props de la raíz: mutarlas cambia los datos y **no redibuja nada**. Copiá a
`data()` una vez y trabajá sobre la copia. El builder
mutaba sus props (`steps.push`, `steps.splice`) y por eso agregar, quitar y
reordenar módulos no se veían — y el segundo clic en una tarjeta fantasma
reventaba con «Cannot read properties of undefined».

Cada isla guarda la **lista completa** contra su API (`PUT`), y el server
reconcilia. No agregues un segundo camino de escritura (nested attributes,
endpoints por fila): la pantalla de criterios los tenía y se sacó.

Cuidado con `.compact` sobre el hash de un step en el presenter: se lleva puesto
`aiMode: nil`, que significa «heredá el modo del desafío» y no es lo mismo que
la clave ausente.

### El sistema visual

Tres piezas cargan casi toda la jerarquía, y las tres estaban mal calibradas:

- **El ritmo lo pone `.app-main`**, que es `flex` en columna con `gap`. Las
  tarjetas tienen `margin: 0` a propósito: un margen por tarjeta rompería las
  grillas, donde son hermanas con su propio `gap`. Antes no había ninguno de
  los dos y las tarjetas se **tocaban** — la página era una columna blanca
  continua partida por hairlines. No se ve mirando (el borde doble parece una
  separación): se ve midiendo, y hay guarda en las capturas.
- **`.section-title` es un encabezado, no una etiqueta.** Era 13px en
  mayúsculas y gris, o sea estilo de etiqueta usado en 54 lugares como título
  de sección: nada anunciaba nada. Las mayúsculas chiquitas quedan donde
  corresponden —encabezados de columna, chips—.
- **`--muted` se usa 178 veces**, así que casi todo el texto de la app es gris.
  Subir el contraste del token una vez lo levanta en todos lados; es más
  barato y más parejo que discutir usos.

Un `turbo-frame` que siempre se renderiza pero casi siempre está vacío —el de
sugerencias de IA— necesita `display: contents`, o como hijo flex se lleva dos
gaps y abre un hueco de la nada.

### Las cuentas de demo

`Flow::Demo` es la fuente única: la contraseña que usa el seed y la lista que
muestra el login. Sale de la base y no de una lista escrita a mano, así no se
desactualiza cuando el seed cambia. Se identifica lo sembrado por el sufijo
`.test`, que RFC 2606 reserva y ninguna cuenta real puede tener.

`available?` es `!Rails.env.production?` — con una base real esto sería un
tablón con las llaves puestas. Hay spec de eso.

Un clic precarga el correo por `?email=`, del lado del servidor: la pantalla de
login no carga ningún bundle de JS y no hace falta que empiece a cargarlo.

## Convenciones que se rompen fácil

- **`button_to` es un `<form>`.** Uno dentro de otro es HTML inválido y el
  navegador no lo deja pasar: descarta el interno y sus botones pasan a
  pertenecer al externo. Pasó en la pantalla del corte —los ✓/✗ de veredicto
  vivían dentro del formulario del ranking, así que apretarlos enviaba el
  corte—. No se ve en el DOM (el parser ya lo aplanó) ni en un request spec que
  postea directo: se mira el HTML **servido**. Hay guarda en las capturas y en
  `spec/requests/selection_screen_spec.rb`. Para atar un control a un
  formulario que no lo envuelve, `form: "id-del-form"`.
- **Pundit, no CanCanCan.** Cada policy declara su `Scope` explícitamente
  (`class Scope < ApplicationPolicy::Scope; end`): Pundit usa
  `const_get(:Scope, false)` y no la hereda.
- **Zeitwerk, una constante por archivo.** `AiRunPolicy` y `AssessmentPolicy`
  viven en archivos propios por esto.
- `Criterion` fija `self.table_name = "criteria"` explícitamente: un proceso que
  arranque antes del initializer de inflexiones busca `criterions`.
- HAML no acepta bloques Ruby en una línea (`- coll.each { |e| %li= e }`).
- `submit_tag` usa el primer argumento **como value**: para mandar un valor
  distinto al texto visible, `button_tag`.
- Migraciones: `schema_format = :sql`. Después de migrar, commiteá
  `db/structure.sql`.
- Los commits de este repo van con `ribarahonaa@gmail.com` (ya está en el
  `git config` local; no lo pises).

## Estado y backlog

Maqueta funcional para validar modelo de datos e infraestructura, no un
reemplazo listo para producción.

Pendiente: nada del backlog original. Lo que sigue son decisiones abiertas, no
deuda: **pgvector queda a la espera de un proveedor de embeddings.** Hoy no hace
falta: sin vectores los duplicados los juzga el modelo. Haría falta para
escalar más allá de `DetectDuplicates::MAX_CANDIDATES`, cuando mandar la lista
entera en el prompt deje de ser razonable — ahí el orden es proveedor de
embeddings primero (Anthropic no tiene), columna `vector` después. Agregar la
columna antes sería guardar algo que nada puede llenar.

El plan vigente y el backlog completo están en
`~/.claude/plans/tu-ya-sabes-como-dazzling-cat.md`.

Dos diagramas, los dos con la skill `archify`:

| Fuente | Qué muestra |
|---|---|
| `docs/arquitectura.architecture.json` | Las piezas y por dónde pasa un pedido |
| `docs/proceso.workflow.json` | Cómo se arma y corre un desafío, con sus tres caminos |

```bash
node ~/.claude/skills/archify/bin/archify.mjs deliver architecture \
  docs/arquitectura.architecture.json docs/arquitectura.html --quality showcase
node ~/.claude/skills/archify/bin/archify.mjs deliver workflow \
  docs/proceso.workflow.json docs/proceso.html --quality showcase
```

Trampa del workflow: `mainPath` exige una espina CONTINUA de aristas
consecutivas, y este proceso se bifurca en tres — se saca. Y tres alternativas
no entran en un carril: comparten corredor y el validador las rechaza. Van en
carriles propios, que además es lo que las hace leer como paralelas.

Trampa: el ancho del lienzo está acotado por la legibilidad a 1440px. Sumar un
componente a la derecha hace fallar `composition/desktop-readability` aunque el
resto valide — es preferible ponerlo en una tarjeta antes que achicarle el texto
a todos los nodos.
