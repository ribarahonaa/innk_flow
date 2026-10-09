# Orientación: el primer día

Esto es lo que hay que leer antes de tocar nada, en el orden en que conviene
leerlo, más el mapa de dónde vive cada cosa. No explica el dominio —para eso
están los deep-dives— sino **cómo ubicarse**.

## Qué es innk_flow

Una maqueta de módulo de ideas **configurable**: el dueño de cada desafío arma
su propio proceso eligiendo qué módulos usar, en qué orden y cuántas veces, y
decide en cada uno si el trabajo lo hace la IA, la IA con supervisión humana, o
sólo personas.

Reemplaza el `ideas.stage` 0..7 de `innk_r5` —un entero hardcodeado, idéntico
para todos los clientes, con las transiciones en un `case` del controller—.

**Es una maqueta funcional para validar el modelo de datos y la
infraestructura, no un reemplazo listo para producción.** Eso condiciona lo que
tiene sentido pedirle: el aislamiento por empresa, el motor del flujo y la
auditoría de IA están para romperlos a propósito; la operación a escala no.

## Arrancar

```bash
make setup     # build + up + db:prepare + seed + assets. Primera vez.
```

→ **http://localhost:3001** · `admin@demo.test` / `Test1234`

La pantalla de login **lista todas las cuentas sembradas** con su empresa y su
rol, y un clic precarga el correo. Nueve cuentas de demo sin saber cuál es cuál
es lo mismo que no tenerlas. Fuera de producción, obviamente
(`Flow::Demo.available?` es `!Rails.env.production?`).

Los puertos van corridos (3001 / 5434 / 6381) para poder tener `innk_r5` arriba
al mismo tiempo.

**Todo corre en Docker. Nunca `bundle exec` en el host.**

## Qué leer, en qué orden

| # | Archivo | Qué te da | Cuándo |
|---|---|---|---|
| 1 | [`README.md`](../README.md) | Los seis módulos, la regla dura del flujo, las cuatro decisiones que sostienen el diseño | Antes de todo |
| 2 | este archivo | El mapa del código y cómo se verifica | Antes de abrir el editor |
| 3 | [`datos.md`](datos.md) | Las 34 tablas de dominio, las relaciones que importan, las invariantes | Antes de escribir una migración |
| 4 | [`pipeline.md`](pipeline.md) | El motor: handlers, `insertion_floor`, late binding, concurrencia | Si tocás el flujo |
| 5 | [`tenancy.md`](tenancy.md) | Las cuatro capas del aislamiento por empresa | **Antes de escribir cualquier query** |
| 6 | [`permisos.md`](permisos.md) | Los cuatro roles, las doce policies, la regla 404-vs-403 | Si tocás un controller |
| 7 | [`criteria.md`](criteria.md) | Criterios, escalas, fórmulas, versionado de la biblioteca | Si tocás evaluación o selección |
| 8 | [`ai.md`](ai.md) | Los tres modos, las trece tareas, los tres proveedores, pgvector | Si tocás IA |
| 9 | [`taller.md`](taller.md) | El taller: mesas, check-in, la sala, borrador, grabación | Si tocás talleres |
| 10 | [`frontend.md`](frontend.md) | Turbo morph, las cuatro islas, las tres capas de CSS, las guardas visuales | Si tocás una vista |
| 11 | [`../CLAUDE.md`](../CLAUDE.md) | **Las trampas**: 2.400 líneas de «esto ya se rompió, así se rompió» | Como referencia, cuando algo no cierra |

Y dos diagramas, que se abren en el navegador:

| Archivo | Qué muestra |
|---|---|
| [`arquitectura.html`](arquitectura.html) | Las piezas y por dónde pasa un pedido |
| [`proceso.html`](proceso.html) | Cómo se arma y corre un desafío, con sus tres caminos |

Se regeneran desde su `.json` con la skill `archify`; el comando exacto está en
`CLAUDE.md`.

## El mapa del código

La regla de oro: **`app/lib/flow/` es el dominio.** Los controllers autorizan y
despachan; los modelos validan; la lógica de negocio vive en `Flow::*`, en
objetos que se prueban con datos pelados.

```
app/
├── lib/flow/              EL DOMINIO
│   ├── pipeline.rb          el motor: ordenar, insertar, arrancar, avanzar, cerrar
│   ├── handlers/            uno por kind: qué hace un módulo al activarse y al cerrar
│   ├── checks/              criterios automáticos (field_present, version_count, …)
│   ├── scales/              numeric · letter · rubric · boolean · formula → todas a [0,1]
│   ├── formula/             validador + calculador (dentaku, NUNCA eval)
│   ├── ai/                  runner, proveedores, tareas, validador de schema
│   ├── workshops/           abrir, repartir mesas, check-in, cerrar, transcribir
│   ├── ideas/               publicar versión, diff, embeddings
│   ├── reports/             builder + escritor de xlsx
│   ├── evaluation/          puntuar una evaluación
│   ├── step_settings.rb     ┐
│   ├── criterion_settings.rb├ los TRES esquemas de configuración (fuente única)
│   ├── flow_templates.rb    ┘
│   ├── setup.rb             el paso a paso de configuración
│   ├── tenant.rb            `Flow::Tenant.with(company)` — la válvula de entrada
│   └── demo.rb              las cuentas sembradas que el login lista
├── models/                34 modelos. Todos `include TenantScoped` salvo cuatro
├── policies/              12 policies de Pundit. `user` es el MEMBERSHIP, no el User
├── controllers/           autorizan y despachan. `api/v1/` sirve a las islas Vue
├── presenters/            serializan las props de las tres islas con estado
├── helpers/               estilos (estado → clase), shell (drawer, banda), formularios
├── jobs/flow/             run (IA), embed_version, generate (reportes), transcribe
├── views/                 HAML server-rendered. `shared/` son los partials compartidos
├── javascript/            4 islas Vue + 4 módulos JS planos + islands.js
└── assets/stylesheets/    application.css: Tailwind 4 + DaisyUI 5, config por CSS
```

Cuatro cosas que no se adivinan mirando el árbol:

- **`app/lib/` y no `lib/`**: así Zeitwerk lo autocarga y recarga en
  desarrollo. Una constante por archivo (`AiRunPolicy` y `AssessmentPolicy`
  tienen archivo propio por esto).
- **`app/assets/builds/` está gitignoreado entero.** Ahí viven la hoja
  compilada y el bundle de JS. **Tocaste `app/javascript/` o agregaste
  utilidades de Tailwind → `make yarn-build`.** Si no, el navegador sirve lo
  anterior y la verificación valida una app que no es la que escribiste.
- **`db/structure.sql`, no `schema.rb`** (`schema_format = :sql`): `schema.rb`
  no serializa FKs compuestas y se perderían en cada `db:prepare`. Después de
  migrar, commiteá `db/structure.sql`.
- **El código va en inglés; los comentarios y los commits, en español.** Hay
  identificadores en español repartidos por el repo —son herencia de una regla
  anterior y **se quedan como están**—. La regla rige para lo nuevo.

## Cómo se verifica

Son **dos** verificaciones y hacen cosas distintas. Las dos hacen falta.

```bash
make spec                                   # la suite completa (~128 archivos)
make spec-file FILE=spec/requests/x_spec.rb
make spec-line  FILE=spec/requests/x_spec.rb LINE=42

make yarn-build                             # SI tocaste JS o clases de Tailwind
make screens                                # el recorrido con navegador
```

`spec/` está repartido así: **58 request specs** (el grueso), **38 de
`lib/`** (el dominio), **9 de lint** (guardas de código: clases interpoladas,
ideas por `policy_scope`, reglas de CSS sin elemento…), **6 de tenancy**,
10 de modelos, 3 de policies, 2 de helpers, 2 de system.

**Los specs corren en `app_test`, no en `app`.** `make spec` usa
`docker compose --profile test run --rm app_test`. Correr
`docker compose exec app bundle exec rspec` usa el contenedor de
**desarrollo**: `RAILS_ENV` queda en `development`, `config.hosts` trae los
defaults de dev y **todos los request specs devuelven 403 «Blocked hosts»**. Se
ve como si la app estuviera rota. Usá siempre `make spec*`.

**`make screens` es la verificación end-to-end real, no un extra.** Recorre la
app con Playwright, saca 76 capturas a `tmp/screenshots/` y corre **42 guardas**
contra el navegador: falla si hay error de JS, si una respuesta da >= 400, si
una isla no montó, si un elemento se quedó sin ninguna regla de CSS detrás, si
un chip no llega a 4,5:1 de contraste, si la mesa de llegada no se refresca
sola, si el autoguardado del borrador no sobrevive una recarga… El detalle de
qué mide cada una —y de qué NO ve— está en [`frontend.md`](frontend.md) y en
`CLAUDE.md`.

Un bug de Vue, de Turbo o de CSS **no lo atrapa ningún spec de Ruby**: un
`__VUE_OPTIONS_API__` mal puesto dejó el builder en blanco con la suite entera
en verde.

**Los system specs con navegador no cubren el recorrido.** Los servicios usan
`with_lock` (SELECT FOR UPDATE) y eso deadlockea contra el pool compartido de
Rails: el spec se **cuelga sin dar error**. Está anotado en
`spec/system/smoke_spec.rb`.

No hay linter configurado.

## Cuatro recetas

### Agregar un `kind` de módulo

1. `ChallengeStep::KINDS` (y `SINGLETON_KINDS` si no es repetible).
2. El CHECK de Postgres sobre `challenge_steps.kind` — **hace falta una
   migración**; sin ella el módulo revienta antes de crearse.
3. `Flow::Handlers::<Kind>` heredando de `Base`: `can_activate?`, `on_activate`,
   `progress`, `can_complete?`, `on_complete`. `Base.for(step)` despacha solo.
4. `Flow::StepSettings` — qué configura ese kind. La UI lo renderiza; no
   declara campos propios.
5. `app/views/steps/config/<kind>.html.haml` (la cara de configuración) y
   `app/views/steps/<kind>.html.haml` (la de ejecución).
6. `flow.kinds.<kind>` en `config/locales/es.yml`.
7. `Flow::Setup` y `ShellHelper#estado_de` si el módulo necesita algo para
   contarse configurado.

### Agregar una tarea de IA

Son **cuatro** lugares, y olvidarse de uno falla de formas distintas:

1. `Flow::AI::Tasks::<Nombre>` heredando de `Base`, con `self.actua_sobre`
   —eso decide **quién** la puede pedir y aceptar— y su JSON Schema.
2. `AiRun::PURPOSES`.
3. **El CHECK de Postgres sobre `ai_runs.purpose`** (migración). Sin esto el
   run revienta con `PG::CheckViolation` antes de crearse y el error llega
   truncado.
4. `flow.ai_purposes.<nombre>` en `es.yml`. Sin esa clave el chip y la
   auditoría muestran el propósito en inglés por el fallback `humanize`.

Y un fixture en el proveedor de fixtures, que es el default: sin él la tarea no
corre sin credenciales. Hay guarda —`spec/lib/flow/ai/fixtures_spec.rb`— porque
un fixture que manda una clave mal escrita la pierde en silencio.

### Agregar un criterio automático

1. `Flow::Checks::<Nombre>` heredando de `Base`: devuelve un booleano y su
   evidencia.
2. `Flow::CriterionSettings` — qué parámetros pide. El editor los renderiza.
3. Nada más: el origen `automatic` fuerza `scale_type: "boolean"`
   (`align_scale_with_source`), así que el editor ni ofrece la opción.

### Agregar una pantalla

1. El controller busca con **`policy_scope`**, no con `find_by!`: lo que no se
   ve tiene que dar **404, no 403**. Ver [`permisos.md`](permisos.md).
2. `content_for :banda` para el encabezado y `content_for :referencia` para la
   columna derecha. El layout lee la referencia **después** del `yield`.
3. Si es una pantalla de módulo: las tres zonas (trabajo al centro, referencia
   a la derecha, «Ajustes del módulo» plegados al final). La referencia va en
   **orden fijo** y hay guarda que lo mide.
4. `make yarn-build` si usaste utilidades de Tailwind nuevas, y después
   `make screens`.
5. Si borrás o mudás una pantalla de configuración, **revisá `Flow::Setup` y
   los renders de `setup_nav` a mano**: `setup_nav` es lo único que avanza el
   paso a paso, y sin su render ahí el recorrido se corta sin que ningún test
   se ponga rojo.

## Antes de mandar

- **Un permiso de más no rompe ningún test.** Si tocaste una policy, abrí
  `spec/policies/gestor_administra_spec.rb`, que existe por eso.
- **Un texto que da permiso a creer que algo no está hecho es un bug.** Si
  cambiaste el comportamiento, buscá qué documento lo describía.
- **Una guarda que mide cero da verde** y es indistinguible de una que
  funciona. Si agregaste una, **vela fallar** — y contra un baseline que pasa.
- Los commits de este repo van con `ribarahonaa@gmail.com` (ya está en el
  `git config` local; no lo pises).
