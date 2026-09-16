# innk_flow

Maqueta de un módulo de ideas **configurable**: el dueño de cada desafío arma su
propio proceso eligiendo qué módulos usar, en qué orden y cuántas veces, y
decide en cada uno si el trabajo lo hace la IA, la IA con supervisión humana, o
solo personas.

Reemplaza el `ideas.stage` 0..7 de `innk_r5` — un entero hardcodeado, idéntico
para todos los clientes, con las transiciones en un `case` del controller.

```
cd innk_flow
make setup          # build + up + db:prepare + seed + assets
```
→ **http://localhost:3001** · `admin@demo.test` / `Test1234`

La pantalla de login **lista todas las cuentas sembradas** con su empresa y su
rol: tener nueve cuentas de demo y no saber cuál es cuál es lo mismo que no
tenerlas. Un clic precarga el correo. Fuera de producción, obviamente.

Los puertos van corridos (3001 / 5434 / 6381) para poder tener `innk_r5` arriba
al mismo tiempo.

---

## Los cinco módulos

| kind | Qué hace | Repetible |
|---|---|---|
| `ideation` | Generación de la idea, con formulario dinámico | **No — exactamente 1** |
| `evolution` | Feedback; el autor actualiza → versión nueva | Sí |
| `evaluation` | Puntuación por criterios, notas, rúbrica o fórmula | Sí |
| `selection` | Reduce el pool: solo avanzan las mejores | Sí |
| `reporting` | Reportes del estado en ese punto del flujo | Sí |

**La regla dura:** en borrador el flujo se edita libremente; una vez arrancado
solo se pueden agregar módulos **a partir del último ya ejecutado**. Nunca antes,
nunca intercalado. El builder la *muestra* —una "línea de agua" con los módulos
bloqueados— y el server la revalida igual.

---

## Cuatro decisiones que sostienen el diseño

**1. La idea es identidad; la versión es contenido.** Cada cambio crea una
`idea_version` inmutable con snapshot completo. Editar no pisa: publica `v(n+1)`.
Toda nota, feedback y decisión guarda **qué versión juzgó**, así que nada queda
huérfano cuando la idea avanza — queda *anclado*, y la UI lo marca.

**2. El aislamiento por empresa es del motor, no del código.** Las FKs
compuestas `(x_id, company_id)` hacen que Postgres **rechace** atar una fila de
una empresa a un padre de otra. Y sin tenant en contexto las queries **revientan**
en vez de devolver todo. → [`docs/tenancy.md`](docs/tenancy.md)

**3. La IA propone; el dominio decide.** Toda llamada deja rastro en `ai_runs`,
incluso con el adapter de fixtures. `ai_auto` no saltea la revisión: la
auto-acepta, para que haya un solo camino y ninguna laguna de auditoría.
→ [`docs/ai.md`](docs/ai.md)

El proveedor real es un adapter más. Para usarlo:

```bash
echo "FLOW_AI_PROVIDER=anthropic"        >> .env
echo "ANTHROPIC_API_KEY=sk-ant-..."      >> .env
make reup
```

El default sigue siendo `fixture`: sin red, sin credenciales y determinista,
porque cada llamada real cuesta plata. El mismo JSON Schema valida los dos
caminos, así que el adapter real no descubre drift en producción.

**Chat y vectores son dos proveedores, no uno.** Anthropic no expone
embeddings, así que con una sola variable no se podía tener chat real y vectores
reales a la vez:

```bash
echo "FLOW_EMBEDDINGS_PROVIDER=openai" >> .env    # o voyage
echo "OPENAI_API_KEY=sk-..."           >> .env
```

Sin declararlo se usa el de chat si sabe hacer vectores, y si no el fixture.
«Detectar duplicados» funciona igual con cualquiera de los dos: con vectores
compara por coseno, y sin ellos le pregunta al modelo —que además **explica** el
parecido, que es lo que una persona necesita para decidir si fusiona—.

**4. Toda escala aterriza en [0,1].** Una nota 1-10, una letra A-F y una fórmula
ICE terminan siendo comparables, así que la selección ordena sin saber de dónde
vino cada puntaje. Las fórmulas las escribe el usuario y **nunca** llegan a
`eval`. → [`docs/criteria.md`](docs/criteria.md)

---

## Los cuatro roles

`admin` administra · `gestor` acompaña la evolución · `evaluator` evalúa lo que
se le asigna · `participant` postula y comenta.

Dos reglas **no viven en el rol**, y son las que más se rompen si se olvidan:

- **Evaluar depende de la asignación**, no del rol. Y nadie evalúa una idea de
  la que participa, ni siquiera quien administra.
- **Quien participa ve solo las ideas en las que participa** —las que creó y
  aquellas en las que colabora—. Lo que no se ve da 404, no 403: un 403 es un
  oráculo de existencia.

---

## Dos diagramas

| Archivo | Qué muestra |
|---|---|
| [`docs/arquitectura.html`](docs/arquitectura.html) | Las piezas y por dónde pasa un pedido |
| [`docs/proceso.html`](docs/proceso.html) | Cómo se arma y corre un desafío, con sus tres caminos posibles |

Se regeneran desde su `.json` con la skill `archify`; el comando exacto está en
`CLAUDE.md`.

---

## Comandos

| | |
|---|---|
| `make up` / `down` / `reup` | Stack |
| `make rails` / `shell` / `psql` | Consola, bash, psql |
| `make migrate` / `seed` | Base de datos |
| `make yarn-build` | Recompilar JS/CSS |
| `make spec` | Suite completa |
| `make spec-file FILE=…` | Un archivo |
| `make screens` | **Recorrido visual** con Playwright → `tmp/screenshots/` |
| `make logs-app` / `logs-sidekiq` | Logs |

### Verificación

```
make spec       # la suite completa
make screens    # recorre la app con un navegador; falla si alguna pantalla tira error JS o HTTP >= 400
```

`make screens` es la verificación end-to-end real: recorre la app corriendo con
un navegador de verdad. Los system specs con navegador **no** cubren el
recorrido completo porque los servicios usan `with_lock` (SELECT FOR UPDATE) y
eso deadlockea contra el pool compartido de Rails en system tests — el spec se
cuelga sin dar error. Está anotado en `spec/system/smoke_spec.rb`.

---

## Stack

Rails 7.1.3.4 · Ruby 3.3.0 · Postgres 17 · Redis · Sidekiq 7.2 · esbuild + Vue 3
(islas) · Pundit · dentaku · caxlsx · wicked_pdf.

Mismas versiones que `innk_r5` a propósito: el equipo no cambia de terreno entre
repos, y mover código de uno a otro es trivial.

**Vue solo donde el estado es del cliente.** Casi todo es server-rendered. Hay
cuatro islas: tres son editores de listas que se reordenan y validan en vivo
—el builder del pipeline, el del formulario de postulación y el de
criterios—, y la cuarta son los ajustes de un módulo, que renderiza el
esquema de configuración de cada `kind` sin guardado propio. Sus props las
serializa el server —el fetch queda solo para lo interactivo, y la tenencia
la garantiza el scope de Ruby.

**Y las pantallas se actualizan sin recargarse.** Turbo 8 con
`turbo-refresh-method: morph`: un POST que vuelve a la misma pantalla —que es lo
que hace casi todo, empezando por los pedidos a la IA— morfea el DOM en vez de
repintar la página, conservando el scroll.

### Decisiones de infraestructura no obvias

| | Por qué |
|---|---|
| `schema_format = :sql` | `schema.rb` no serializa FKs compuestas: se perderían en cada `db:prepare` |
| `postgresql-client-17` en las imágenes | El `pg_dump` 15 de Debian se niega a dumpear un server 17 |
| PKs **UUIDv7** | No adivinables (un id secuencial es un oráculo de enumeración cross-tenant) y ordenados por tiempo, así los índices no se fragmentan |
| `connection_pool ~> 2.4` | La 3.x exige Ruby ≥3.4 |
| npm `playwright` == gema `playwright-ruby-client` | Con versiones distintas cada spec pierde ~2 minutos en el handshake |
| Al agregar una gema, `make rebuild` (no solo `app`) | `sidekiq` corre en su propia imagen: si no se rebuildea, arranca con el bundle viejo y falla con `Could not find <gema> in locally installed gems` |

---

## Estado

Maqueta funcional para validar el modelo de datos y la infraestructura. **No** es
un reemplazo listo para producción.

Fuera de alcance: migración de datos desde `innk_r5` y SSO real (la costura
está — tabla `identities` desde el día 1).

Lo único que queda abierto no es deuda: **`pgvector` espera un proveedor de
embeddings con crédito**. Hoy no hace falta —sin vectores los duplicados los
juzga el modelo—; haría falta para escalar más allá de
`DetectDuplicates::MAX_CANDIDATES`, cuando mandar la lista entera en el prompt
deje de ser razonable.
