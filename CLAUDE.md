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
app corriendo con un navegador y falla si hay error de JS, HTTP >= 400, si
queda un `.island-placeholder` sin montar o si una clase quedó **sin ninguna
regla detrás** porque Tailwind no la vio al escanear —eso se revisa en las 35
pantallas, no en algunas: vive en `capturar()`—. Corrélo después de tocar
vistas, islas o CSS — un bug de Vue no lo atrapa ningún spec de Ruby (un
`__VUE_OPTIONS_API__` mal puesto dejó el builder en blanco y la suite en verde).

Al escribir capturas nuevas en `script/capture_screens.js`:

- Navegá **por link**, no con `goto`. Turbo no dispara `DOMContentLoaded` al
  navegar por link; un `goto` monta la isla igual y esconde el bug.
- Después de un clic, esperá `waitForURL` o un selector — `networkidle` se
  calma antes de que Turbo ponga el body nuevo, y la captura sale de la
  pantalla anterior.
- Las islas exponen `data-island-mounted="true"` como señal determinista.
- **Nunca apuntes una captura a un desafío que también se usa a mano.**
  `optimizacion-de-la-experiencia-de-onboarding` ni siquiera vive en
  `db/seeds.rb` —es dato real armado a mano—, así que un `goto` ahí revienta
  en cualquier entorno recién sembrado. `onboarding-remoto` sí está en el
  seed, y aun así compartirlo con pruebas manuales rompió la corrida dos
  veces en cuanto alguien le tocaba algo (`3e437d6`). `sin-formulario` existe
  **solo** para el recorrido —y esta rama reintrodujo el antipatrón de todas
  formas, dos veces (`04f2d00`, y de nuevo en la Task 11 antes de que la
  revisión lo cortara)—. Hoy siembra los cinco `kind` pendientes y un set de
  criterios inline en su módulo de selección (`db/seeds.rb:360` en
  adelante), del que dependen varias capturas de las dos caras.

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
| `Flow::StepSettings` | Qué configura cada `kind` de módulo | la cara de configuración (isla `step-settings`), el resumen congelado de la cara de ejecución (`_config_congelada`, `steps/selection`) y el schema con el que la IA propone un flujo (`json_schema`, en `ProposePipeline`) |
| `Flow::CriterionSettings` | Qué parámetros pide cada verificación y cada escala | editor de criterios |
| `Flow::FlowTemplates` | Puntos de partida del flujo | creación del desafío y builder vacío |

**En `config` un hueco no es «sin valor»: es el default del esquema.** Sólo
`Api::V1::PipelinesController#create_added` siembra `StepSettings.defaults`;
`Flow::FlowTemplates` manda configs PARCIALES y `db/seeds.rb` no manda ninguna,
así que los dos caminos normales dejan claves ausentes — y los handlers leen
con `fetch(clave, default)`, o sea que el módulo corre con el default igual.
Mostrar la ausencia como ausencia dejaba la tarjeta «Cómo quedó configurado» de
evolución y de reportería **entera vacía**: encabezado, aviso del candado y un
`<ul>` sin una sola fila, que es el mismo control fantasma que esta rama existe
para sacar. Se lee con `StepSettings.efectivo(kind, settings)` y se filtra con
`StepSettings.visible?`, que espeja el `depends_on` de `config_field.vue` (con
la regla de corte en «manual», «Valor del corte» no describe nada). Ojo con la
suite: el fixture que probaba esa tarjeta ponía `config:` a mano en los cinco
kinds, que es justo el caso que no ocurre en la práctica.

**Todo `config` que llega de afuera pasa por `StepSettings.filtrar`**, venga
de un formulario (`steps#update`) o de un modelo (`ProposePipeline#apply!`).
El JSON Schema de la tarea no alcanza: localmente no cierra los objetos, y una
sugerencia editada a mano o un fixture pueden traer cualquier clave. Y el
filtro no avisa: una clave mal escrita se descarta y el módulo corre con el
default. El fixture de `propose_pipeline` mandaba `cut_mode` plano —nadie lo
lee, la clave es `cut.mode`— y «Corte a top 10» nacía con el corte en manual;
la guarda está en `spec/lib/flow/ai/fixtures_spec.rb`.

**Y el modelo sólo puede proponer las claves que el schema declara.** El
adapter de Anthropic cierra todo objeto con `additionalProperties: false`, así
que un `config` declarado `object` a secas le llegaba a la API como un objeto
donde no entra ninguna clave: con el proveedor real la propuesta nunca traía
configuración. `StepSettings.json_schema(kind)` arma una variante por kind (un
`anyOf` con `kind` como `const`), sin los campos `column:` ni los `source:`
—eligen módulos que al proponer todavía no existen—, y pone en la descripción
el rango y lo que significa cada valor: es lo único que el modelo ve, porque
la API poda `minimum`/`maximum`.

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
con ella hasta que alguien los pase a la nueva **desde la pantalla del
módulo**. Un set que no usa nadie se edita en el lugar: versionar lo que nadie
tiene asignado no protege a nadie.

**Elegir un set de la biblioteca y pasar un módulo a la versión nueva son dos
controles de la cara de configuración**, en el bloque de criterios
(`steps/_criterios_editor.html.haml`, detrás del mismo `configure?` que el
resto). Ninguno tiene endpoint propio: los dos escriben `criteria_set_id` por
`PATCH steps#update`, que es el único camino de escritura de la configuración
de un módulo. `CriteriaSet.asignables_para` arma las opciones (la vigente de
cada familia, más la que el módulo tenga puesta aunque ya no lo sea) y
`CriteriaSet#newer_version` dice si hay una más nueva. Los dos vivían en el
panel del builder (`step_config.vue`) y se perdieron al borrarlo (`58bd076`):
durante esa ventana **nada** podía apuntar un módulo a la biblioteca —el único
escritor era la copia `inline` de `StepCriteriaController#create`— mientras dos
textos de la app seguían instruyendo a hacerlo (`Flow::Pipeline#validate`,
`CriteriaSetPresenter#version_notice`). Volvieron en HAML y no en la isla: el
builder es dueño del armado, no de la configuración.

**Con criterios propios no hay vuelta a la biblioteca.** Los dos controles
aparecen solo mientras el módulo no tiene un set `inline` (el `set.nil?` del
partial): en cuanto copia uno o empieza en blanco, desaparecen. «Guardarlos
también en la biblioteca» (`promote_to_library!`) no es el camino de vuelta:
crea una copia en la biblioteca y deja al módulo con la suya. Es paridad
exacta con el panel del builder que se borró, no una regresión. La regla es de
la pantalla y no del modelo —`criteria_set_belongs_to_challenge` acepta
cualquier set de biblioteca—, así que abrir la vuelta sería solo de vista.

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
- **El morph no rompe las islas**, medido en la cara de configuración de
  Idear —la pantalla del módulo que hoy monta el editor de formulario,
  destino del redirect 301 que dejó `/challenges/:id/form`—: reemplaza el
  contenedor entero y `turbo:load` vuelve a montar con las props nuevas.
  `make screens` lo verifica sin gastar una llamada al proveedor
  (`revisarMorphing` en `script/capture_screens.js`), pidiendo a mano la misma
  navegación.

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
incrementa. El payload del PUT es literalmente `{ id, kind }` por módulo, y
`create_added` lee sólo `kind`: ni `name` ni `ai_mode`, que el builder no tiene
cómo escribir. `update_existing` no existe — de un módulo que ya existe no se
escribe ningún atributo.

**Y tampoco manda para el otro lado.** `PipelinePresenter` publica sólo lo que
la tarjeta dibuja. Cuando la configuración se mudó a la pantalla del módulo
quedaron 6,4 KB de 10,4 KB de props que ningún `.vue` leía —el resumen de
criterios y el del formulario enteros, `settingsSchema`, `criteriaSets`,
`position`, `touched`, `effectiveAiMode`, tres URLs—, y no era sólo peso: el
resumen de criterios corría `newer_version_for` (una consulta por módulo que
puntúa) y el del formulario cargaba `form_fields.ordered` en **cada** render
del builder. Además `createApp(component, props)` convierte toda prop no
declarada en atributo del elemento raíz, así que lo que sobra se serializa al
DOM. Antes de sumar una clave, buscá quién la lee.

Tres cosas NO se congelan al arrancar y la cara B las muestra como vivas:
el nombre, el modo de IA (`ADJUSTABLE_ATTRIBUTES`) y las asignaciones.

El formulario de postulación tiene un candado más fino que `touched?`:
`ideas.submitted.exists?`. Con el módulo abierto pero sin postulaciones,
corregir el label de un campo es sano. Por eso su editor aparece en las dos
caras.

**La guarda de permiso vive en la VISTA, no en el controller.** Un editor o un
bloque de controles que antes vivía en pantalla propia —con su propio
controller pidiendo `manage_criteria?`, `manage_form?`— pasa a embeberse en la
pantalla del módulo, que sirve `ChallengeStepPolicy#show?`: cualquiera de la
empresa. Heredar ese permiso amplio sin poner uno más estricto en el partial
deja la isla y los botones montados para quien no puede usarlos, y apretarlos
rebota en un 403 — el mismo control-que-no-responde que esta rama entera
existe para arreglar, ahora adentro de la pantalla que se supone lo soluciona.
El mismo defecto apareció así de repetido: primero el form completo de
`steps/config/_modulo` se servía sin ninguna policy; después, en
`_criterios_editor`, el panel de sugerencias de IA quedó afuera de la guarda
que sí envolvía el resto. La forma que quedó, en `_criterios_editor.html.haml`
y `_campos_editor.html.haml`: **un solo `if` que envuelve todo menos el
encabezado**, no guardas sueltas por bloque — una guarda que se olvida se
encuentra más fácil que dos. Cuál predicado según qué bloque:
`configure?` para los ajustes del módulo y para sus criterios, `manage_form?`
para los campos del formulario, `manage_assignments?` para quién evalúa y
cuánto pesa, `update_pipeline?` para quién acompaña la evolución
(`_asignaciones_gestores.html.haml`, que sólo envuelve `challenges/_gestores`
con esa guarda y no tiene policy propia).

El panel de propuestas de la IA (`shared/_ai_suggestions`) es la excepción al
«un solo `if`»: filtra propuesta por propuesta con `AiSuggestionPolicy#accept?`,
porque quién revisa depende de sobre qué actúa cada tarea. Se sirve en diez
pantallas, y sin ese filtro les mandaba a quien participa y a quien evalúa
propuestas que no podían revisar, con la vista previa incluida.

**Borrar o mudar una pantalla de configuración le puede sacar el sonido a
`Flow::Setup`.** El paso a paso apunta cada paso a una URL
(`Flow::Setup::Step#path`). `setup_nav` necesita que quien lo renderiza le
pase el `current:` que le toca para calcular anterior y siguiente
(`setup.before(current)`, `setup.after(current)`): sin ese render no hay
ningún «siguiente →» que ofrecer. `setup_progress` no depende de lo mismo —
pinta los seis pasos siempre; `current` sólo resalta cuál está activo
(`setup__step--current`)—, así que el paso sigue apareciendo en la lista
aunque el pie que avanza haya desaparecido. Pasó de verdad con el paso
`:form` al mudarlo a la cara del módulo: **`make spec` y `make screens`
quedaron en verde igual**, porque ninguna aserción existente miraba el pie
del paso a paso en la pantalla que se había quedado sin su render (`2029528`,
recién notado en la ronda de revisión de Task 7). Con `:criteria` estuvo por
repetirse al borrar su índice, y se atajó antes de embarcarse: `711ed9b`
borra el índice y suma los dos renders de `setup_nav` en el mismo commit, así
que nunca corrió huérfano. La ceguera de la suite es igual de real ahí, por
otra vía: el test del pie sólo pasaba por `evaluation`, y sacar nada más que
el render de `selection` (el otro kind que embebe el bloque de criterios)
dejaba `make spec` y `make screens` en verde igual (`df0681d`). Quien borre o
mude una pantalla de configuración tiene que revisar `Flow::Setup` y los
renders de `setup_nav`/`setup_progress` a mano, no confiar en la suite para
que avise.

### Islas Vue

Cuatro: `pipeline_builder`, `form_editor`, `criteria_editor`, `step_settings`.
Se montan con `app/javascript/islands.js`, que cubre `DOMContentLoaded`,
`turbo:load` y el script que llega tarde, y desmonta en `turbo:before-cache`.

Las props las serializa el **server** (`PipelinePresenter`,
`CriteriaSetPresenter`, `StepSettingsPresenter`) y viajan en un `data-props`:
una vuelta de red menos y la tenencia la garantiza el scope de Ruby, no una
ruta JSON que alguien podría olvidar scopear.

**Las props son el estado INICIAL, no el estado.** Vue no hace reactivas las
props de la raíz: mutarlas cambia los datos y **no redibuja nada**. Copiá a
`data()` una vez y trabajá sobre la copia. El builder
mutaba sus props (`steps.push`, `steps.splice`) y por eso agregar, quitar y
reordenar módulos no se veían — y el segundo clic en una tarjeta fantasma
reventaba con «Cannot read properties of undefined».

Las primeras tres guardan la **lista completa** contra su API (`PUT`), y el
server reconcilia. No agregues un segundo camino de escritura (nested
attributes, endpoints por fila): la pantalla de criterios los tenía y se
sacó. `step-settings` es la excepción: no tiene guardado propio, renderiza sus
campos DENTRO del `form_with` de Rails de `steps/config/_modulo` y viaja en el
mismo PATCH que el nombre y el modo de IA — un solo botón, un solo endpoint
(`steps#update`).

Cuidado con `.compact` sobre el hash de un step en el presenter: se lleva puesto
`aiMode: nil`, que significa «heredá el modo del desafío» y no es lo mismo que
la clave ausente.

### El sistema visual

**Tailwind 4 + DaisyUI 5.** La hoja propia («sin framework CSS: la maqueta
define sus propios tokens») se revirtió a propósito; el porqué y el orden de
migración están en
`docs/superpowers/specs/2026-09-08-rediseno-tailwind-daisyui-design.md`.

La configuración vive **en el CSS** —Tailwind 4 es config-por-CSS, no hay
`tailwind.config.js`—: `app/assets/stylesheets/application.css` abre con
`@import "tailwindcss"`, `@plugin "daisyui"` y los dos temas, y declara con
`@source` dónde buscar clases (`views`, `helpers`, `javascript`). La compila el
**CLI de Tailwind** (`yarn build:css`), no esbuild, que ya solo ve JavaScript;
Sass se jubiló entero. El archivo de salida conserva el nombre, así que el
`stylesheet_link_tag` del layout nunca cambió.

Esta fase migró la plomería, las clases dinámicas, el tema y el shell. Lo que
sigue —los 18 partials compartidos, pantalla por pantalla y los componentes
Vue— es el plan 2. Por eso `status-chip`, `.step-card` y compañía todavía son
CSS escrito a mano y no `badge` ni `card` de DaisyUI.

#### Lo que más fácil se rompe

- **`data-theme` NO va en el `<html>`.** El tema oscuro es
  `@plugin "daisyui/theme" { name: "flow-oscuro"; prefersdark: true; }`, y
  `prefersdark` engancha
  `@media (prefers-color-scheme: dark) { :root:not([data-theme]) }`. Poner el
  atributo —**aunque sea con el nombre del tema claro**— hace que ese selector
  no matchee nunca y deja el modo oscuro muerto. Es lo primero que uno agrega
  al ver un tema de DaisyUI.
- **El token del color de borde es `--borde`, no `--border`.** DaisyUI usa
  `--border` para el **ancho** de los bordes de sus componentes
  (`border-width: var(--border)`): con el nombre en inglés el color se colaba
  ahí, el ancho quedaba inválido y todos los botones salían con los 3px del
  `medium` por default. No se ve leyendo el CSS; se ve midiendo.
- **Las mezclas van `in oklab`, nunca `in oklch`.** En oklch el tono interpola
  por el arco corto: mezclar el ámbar (82°) con el texto (286°) da la vuelta
  por el rojo y el «amarillo oscuro» sale marrón anaranjado. En oklab no hay
  tono que rotar.
- **Un color con alfa se compone sobre su fondo antes de medir su contraste.**
  `--muted` es `color-mix(… 70%, transparent)`, y medirlo sin componer da un
  número que en pantalla no existe. Si el fondo también es translúcido, se
  compone la cadena hasta el primer opaco.
- **Un tema propio emite SOLO lo que declara**: no hereda nada de los que trae
  la librería. Los 20 colores y los tres escalares van completos **en los dos**
  temas — sin `--depth`, el `color-mix()` del borde de `.btn` queda inválido y
  `border-color` cae en `currentColor`.
- **Lo declarado tiene que ser lo que pinta.** Varios oklch del plan estaban
  fuera del gamut sRGB: el navegador los recorta, y entonces ajustar el croma
  no hace nada hasta cruzar el límite. Los valores de la hoja son la conversión
  exacta del hex y el croma máximo que entra.

#### Las tres capas, y de quién es cada regla

Componentes de DaisyUI donde existan · clases propias con nombre semántico para
el vocabulario que es de esta app y se repite (`.flow-strip`, `.step-card`,
`.empty-state`) · utilidades sueltas solo para lo irrepetible. **Si una clase
aparece en más de dos vistas, es un componente, no doce utilidades.**

`card` de DaisyUI está **excluida** (`exclude: card` en el `@plugin`): además
de pintar declara `display: flex`, y eso convertiría en columna flex las 101
tarjetas de la app, que nunca lo pidieron. Entra en el plan 2, cuando las
pantallas se reescriban con `card-body`.

**La capa decide quién gana, y no es la especificidad.** Las clases propias de
la app van **sin capa**, y una regla sin capa le gana a cualquier `@layer` —o
sea a todo Tailwind y todo DaisyUI—: es lo que sostiene las 1.939 líneas
heredadas sin tener que tocarlas. El precio es que un selector genérico sin
capa pisa un componente: `a { color: … }` suelto le ganaba al `.btn` de DaisyUI
y dejaba un `<a class="btn btn-primary">` con el texto del color del fondo. Los
defaults del navegador que el Preflight borra —y ese color de enlace— van en
`@layer base`, desde donde le ganan al Preflight, pierden contra el componente
y pierden contra las utilidades: si estuvieran sin capa, un `<p class="m-0">`
saldría con el default y la utilidad parecería no haber compilado.

#### Tailwind escanea texto: una clase interpolada no existe

`app/helpers/estilos_helper.rb` traduce estado del dominio → clase y devuelve
siempre el nombre **completo**, escrito literal. Nunca `"status-chip--#{x}"`:
esa clase no llega a la hoja, el elemento queda sin ninguna regla detrás y en
el DOM se ve perfecto mientras en pantalla no se ve nada. De rebote, la
traducción estado → estilo queda en un solo lugar.

La guarda es `spec/lint/clases_interpoladas_spec.rb` y mira **HAML y `.vue`**:
las islas son fuente de Tailwind igual que las vistas. En una isla el nombre lo
manda el **presenter** en las props —`PipelinePresenter` resuelve el chip con
el mismo `chip_de_estado` que el HAML— y el componente solo lo liga.

Cada mapeo se prueba **contra su enum**, y con `end_with` y no `include`: un
helper que devolviera `--issued` pasaba el test de `issue`.

#### El shell de tres regiones

`.app-shell` es una grilla: el flujo del desafío a la izquierda (232px), el
trabajo en el medio y la referencia a la derecha (280px). **Las dos laterales
son opcionales y la grilla se acomoda sola con `:has()`**, así que ninguna
pantalla declara su layout.

- La regla de qué va dónde: **el centro es lo que se hace; la derecha es lo que
  se consulta y no se edita** en el curso normal del trabajo.
- El drawer aparece solo si hay un desafío **guardado** en contexto
  (`ShellHelper#desafio_del_shell`). Dos guardas que parecen de más y no lo
  son: `/challenges/new` deja un `Challenge.new` sin slug y el `challenge_path`
  del drawer reventaba la pantalla entera; y sin tenant devuelve `nil`, porque
  un 404 se renderiza **después** del `Current.reset` y la consulta de los
  módulos moriría con `MissingTenant`.
- La referencia la llena el template con `content_for :referencia` y el layout
  la lee **después del `yield`**.
- **No es el componente `drawer` de DaisyUI**: es un `menu` dentro de una
  región de la grilla. El `drawer` pide un checkbox, dos labels y envolver el
  contenido entero. Abajo de 1024px el flujo pasa a ser una tira horizontal
  arriba del contenido, sin una línea de JS y sin que haya que abrir nada.
- La barra es oscura **en los dos temas** (`bg-neutral`): es el shell, no el
  modo oscuro.

#### Lo que carga la jerarquía

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
- **El acento es de las ACCIONES.** Los gráficos van con `--dato` /
  `--dato-fuerte`, una rampa sacada del propio texto: pintar una barra con el
  violeta del botón de al lado la hace leer como un control.

Un `turbo-frame` que siempre se renderiza pero casi siempre está vacío —el de
sugerencias de IA— necesita `display: contents`, o como hijo flex se lleva dos
gaps y abre un hueco de la nada.

#### Las fuentes se auto-hospedan

Bricolage Grotesque (solo títulos) e Inter (todo lo demás) viven en
`public/fonts` y las declara la hoja con `@font-face`. **No entran por Google
Fonts**: una hoja de un tercero bloquea el render y, medido, con la petición
colgada `DOMContentLoaded` no llega nunca y la pantalla queda **en blanco**
—abortada rendía bien; colgada, no, y `preconnect` no ayuda contra un agujero
negro—. Son los mismos dos archivos variables del subconjunto latin que el
navegador ya bajaba (125 KB), con `font-display: swap` y la pila de respaldo
intacta. La licencia OFL acompaña a los archivos, que es lo que pide.

El PDF de reportería es la excepción y **no** cuelga de los tokens: lo arma
wkhtmltopdf sin la hoja de la app y sin nadie que resuelva `var()`, así que
`app/views/layouts/pdf.html.haml` lleva los cinco colores como literales y la
fuente del sistema. Si el tema cambia, ese archivo se actualiza a mano — es el
único lugar donde la paleta llega a un usuario en algo que se descarga.

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
