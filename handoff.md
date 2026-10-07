# Handoff — el borrador de la mesa, y trece tests que no podían fallar (2026-10-07)

## 1. Objetivo

Construir **B** de los tres subsistemas de taller que quedaban: que lo que una
mesa teclea en la sala no se pierda.

El brainstorming lo redujo antes de escribir una línea, y ese recorte es lo más
importante de la sesión. La spec anterior
(`2026-10-02-sala-de-la-mesa-design.md`) había fichado B como «guardado
automático que **publica** una `idea_version` nueva», y con eso arrastraba los
dos bloqueos que el handoff anterior declaraba: qué pasa con las propuestas
pendientes cuando el autoguardado publica, y cómo se coalescen versiones que son
inmutables y llevan un `embedding vector(1024)` cada una.

La decisión fue **durabilidad, no inmediatez**: B guarda un borrador de trabajo
que **no es una versión**, y publicar sigue siendo un acto explícito. Eso
disolvió los dos bloqueos de una vez —nada publica, así que no hay conflicto con
las propuestas; y un borrador es mutable, así que se pisa en vez de coalescerse—.

Las otras dos decisiones de producto, las dos del dueño del repo:

- **El borrador es de la MESA, no de cada persona** (servidor, último que escribe
  gana). Es lo que la pantalla ya promete («el borrador se comparte con…: es de
  la mesa, no solo tuyo») y es la única opción que sobrevive al caso que B existe
  para evitar: que al que escribe se le muera la máquina o se vaya, y el texto
  quede para el resto.
- **Si la versión vigente avanzó desde que la mesa guardó, gana el borrador CON
  aviso.** Que ganara la versión tira el trabajo de la mesa sin preguntar; que
  ganara en silencio hace que la mesa mande una propuesta que revierte la versión
  nueva sin enterarse.

Spec: `docs/superpowers/specs/2026-10-07-borrador-de-mesa-design.md`.
Plan: `docs/superpowers/plans/2026-10-07-borrador-de-mesa.md` (seis tareas).

## 2. Estado actual

Rama **`borrador-de-mesa`**, 17 commits sobre `master`, **toda pusheada y en
sincronía**: `origin/borrador-de-mesa` está en `36d0ff1`. `master` sigue en
`acda95a`, local y remoto, así que **la rama está publicada pero sin mergear**.

Verificado así, que es el punto:

```bash
git branch -vv                                                   # ahead/behind
gh api repos/ribarahonaa/innk_flow/branches/borrador-de-mesa --jq .commit.sha
```

**Preguntá por la RAMA, no por `master`.** La primera versión de este handoff
decía «nada pusheado, verificado con `gh api`»: la verificación era real pero
medía el ref de al lado —el sha de `master` no dice nada sobre si la rama se
publicó— y en ese momento ya había ocho commits allá. Es la misma familia de
error que el handoff anterior ya había pagado.

Y un hueco de método que vale para la próxima: la rama apareció en el remoto a
mitad de la sesión (`branch_creation` en `40d9318`, el commit de la Tarea 4) sin
que ningún paso lo pidiera. **Los despachos a los implementadores prohibían
`rebase` y `reset` y no prohibían pushear.** Prohibilo explícito.

- `make spec`: **1682 ejemplos, 0 fallas** — corrido por mí y no declarado por un
  subagente, porque el verde declarado de una ronda resultó falso y la rama
  estuvo roja sin que el reporte lo dijera.
- `make screens`: verde. Última corrida, con los diez contadores:
  `[RITMO] 39 · [RELLENO] 296 · [PASTILLA] 793 · [CRITERIO] 195 · [LIVE] 1 ·
  [RIEL] 71 · [BANDA] 71 · [SOMBRA] 299 · [CAMPO] 291 · [DRAFT] 2`.
- **Diez corridas del recorrido en total**, todas con `FLOW_AI_PROVIDER=fixture`,
  o sea **cero costo de IA**. Son seis más de las que el plan preveía, porque
  cada ronda de arreglo que tocó el navegador se volvió a medir.

**OJO: la app quedó en `fixture`.** Para devolverla al proveedor real:

```bash
docker compose up -d --force-recreate app sidekiq   # lee FLOW_AI_PROVIDER del .env
```

El recreate tiene que incluir `sidekiq`: `Flow::AI.provider` memoiza por proceso.
Y **no** uses `make reup` para esto: hace `down` del stack entero, base incluida.

## 3. Archivos y cambios

Lo que existe ahora y antes no:

| Pieza | Dónde |
|---|---|
| La tabla y el modelo | `db/migrate/20261007120000_create_workshop_drafts.rb`, `app/models/workshop_draft.rb` |
| El endpoint que autoguarda | `app/controllers/workshop_drafts_controller.rb`, `config/routes.rb` |
| El autoguardado del navegador | `app/javascript/workshop_draft.js` |
| El sello y el aviso de base vieja | `app/views/workshop_rooms/_draft_stamp.html.haml`, `_evolution.html.haml` |
| La guarda del recorrido | `script/capture_screens.js` (`revisarBorrador`, `[DRAFT]`) |

Cuatro decisiones de diseño que no se leen del código y que `CLAUDE.md` ahora
explica:

- **Una tabla propia y no una columna en `workshop_groups`.** El borrador tiene
  identidad compuesta —mesa + sala, y la idea sólo en evolución— y dos índices
  UNIQUE **parciales**, porque Postgres trata los NULL como distintos: un solo
  `UNIQUE(mesa, sala, idea)` dejaría que la mesa acumule una fila por
  autoguardado. El precedente es
  `index_workshop_groups_on_workshop_id_arrival … WHERE arrival`.
- **El sello de la versión se escribe SÓLO al crear la fila**
  (`if draft.new_record?`). Si se reescribiera en cada autoguardado, el aviso de
  base vieja no podría dispararse nunca. Es una línea de la que depende toda esa
  feature.
- **Un `PATCH` sin `payload` es un no-op**, y también si tras filtrar no
  sobrevive ninguna clave. Con `fetch(:payload, {})` un bug de una línea en el JS
  pisaría el texto de la mesa con nada. Los tres caminos responden 204, así que
  los dos que NO escriben mandan `X-Draft-Saved: "0"`; sin esa cabecera el sello
  diría «Guardado ahora.» sobre un guardado que no ocurrió.
- **La cláusula nueva del barrido de mesas vacías de `AssignGroups#seat!`
  acompaña a la de propuestas; el guarda de arriba NO se extendió a borradores,
  a propósito** — y los dos motivos son distintos, aunque se parezcan. El del
  barrido es la carrera: ahí la mesa queda vacía por un efecto del reparto y
  nadie eligió perderla. El de no extender el guarda de arriba lo dice
  `assign_groups.rb:149-152`: negarse a repartir porque alguien tecleó una
  palabra bloquearía una operación común por texto sin mandar, y ese guarda
  existe por la procedencia de versiones publicadas, que un borrador no tiene.
  Borrar una mesa **a mano** sí se lleva el borrador y tampoco se niega, pero
  por un tercer motivo, que vive en `workshop_groups_controller.rb:64-66`:
  ninguna pantalla borra un borrador, así que una mesa con texto tecleado
  quedaría imposible de borrar para siempre. Ahora el aviso lo dice.

## 4. Intentos fallidos

**Lo que esta sesión costó de verdad fueron trece tests y chequeos que no podían
fallar.** No es una cifra retórica: cada uno se encontró preguntándole a un
ejemplo verde «¿qué tendría que romperse para que esto falle?» y descubriendo que
la respuesta era «nada». La mayoría los escribía el plan. Los más caros:

- Un ejemplo aseveraba `include("lo publicado")` y esa cadena llegaba a la
  respuesta por **dos caminos más** —el título de la idea y la tarjeta
  «Contenido»—, así que pasaba con el prellenado roto.
- El ejemplo del sello aseveraba `include(ana.name)`, y ese nombre ya sale en la
  lista de integrantes de la mesa.
- El sello de la cara de **idear** no tenía ningún ejemplo: borrar su `render`
  dejaba la suite entera verde. Peor: ponía *verde* el único ejemplo que estaba
  rojo por su causa.
- El chequeo del sello en `[DRAFT]` pedía que no estuviera **vacío**. Como la
  guarda misma deja un borrador en la base, desde la segunda corrida el servidor
  ya lo renderizaba con texto y el chequeo pasaba sobre un autoguardado muerto.
  Lo probé mutando: con el JS roto, el sello decía «Guardado por Ana Admin hace 2
  minutos.» Ése lo acepté yo, no el plan.
- `[DRAFT]` medía **un solo campo**, así que no podía cazar la única invariante
  que la tarea declaró load-bearing: que el JS mande el formulario entero, porque
  el endpoint reemplaza el hash sin merge. Con `cuerpo()` «optimizado» a un diff,
  el borrador quedaba con un campo y la guarda daba verde.
- La cabecera `X-Draft-Saved`, recién agregada para arreglar otro de éstos, no la
  aseveraba nada: borrarla dejaba `make spec` **y** `make screens` en verde.

**Dos defectos del plan que afectaron cuatro tareas.** La factoría
`:idea_version` no existe y no debe existir —`Flow::Ideas::PublishVersion` es el
único escritor de versiones, porque `ideas.current_version_id` e
`idea_versions.idea_id` forman un ciclo de FK—; y el plan mandaba un
`idea.update!(current_version:)` a mano al lado.

**La rama quedó ROJA y el reporte decía «todos en verde».** El implementador
corrió los dos archivos que el Step 8 del brief nombraba. La cara que tocó tiene
su propio spec, que él mismo había corrido en una tarea anterior. **La lista de
archivos de un brief no es el radio de impacto.**

**Dos arreglos míos trajeron un defecto cada uno, y sólo se vieron leyendo el
código con el cambio ya puesto.** Dicté un `start()` con el `stop()` antes del
return temprano, que cancelaba un guardado pendiente al morfear. Y al sacar el
`form = null` del `catch`, el `stop()` que quedaba —antes inocuo— pasó a cancelar
un guardado **más nuevo** que el que había fallado. El `AbortController` que
agregamos para cerrar una carrera abrió otra: podía abortar el `keepalive` de
otro borrador.

**Un agujero en una decisión mía.** Saqué el link del aviso de base vieja porque
en evolución la mesa trabaja la idea de *cualquier* integrante
(`workable_ideas` es la unión) mientras `IdeaPolicy::Scope` le muestra a quien
participa sólo lo que creó o comparte: el link era un 404 en el caso normal de la
mesa. Justifiqué el reemplazo —«mirá «Contenido» más arriba»— diciendo que el
orden lo fijaba `workshop_room_spec.rb`, y era falso: su única aserción de orden
es de la columna de referencia, en la otra cara. Ahora hay una aserción de orden,
mutada.

**Una sospecha que medí y resultó falsa.** Antes de despachar la última tarea
supuse que el seed reventaría con `PG::ForeignKeyViolation` al destruir una sala
con borrador. `db/structure.sql` lo desmintió: las FK son `ON DELETE CASCADE`. Y
medido, `WorkshopDraft.count` da 2 antes del seed y 0 después **sin ninguna línea
nueva** — así que el `WorkshopDraft.delete_all` que el plan pedía era redundante
y, bajo `bypass!`, habría borrado los borradores de todas las empresas.

**Lo de siempre, que vuelve a aparecer**: `db:migrate:redo` aborta porque
`tenant_table` no es reversible: usa `execute` (el helper tiene tres, uno
en cada método) (13 migraciones
del repo la usan; se deshace con `DROP TABLE` más borrar la fila de
`schema_migrations`). Y un commit salió con las líneas de atribución que el dueño
del repo no quiere; se enmendó antes de pushear.

## 5. Próximos pasos

1. **La revisión final de rama entera**, en el modelo más capaz, apuntada a lo
   que quedó parkeado con ruling en
   `.superpowers/sdd/2026-10-07-borrador-de-mesa/progress.md` (34 rulings). Lo
   que más merece un segundo par de ojos:
   - **Un envío FALLIDO pierde lo tecleado desde la última pausa de dos
     segundos.** El listener de `submit` pone `sucio = false` y tiene que
     hacerlo: si no, cada envío exitoso recrearía el borrador con lo que el
     servidor acaba de publicar y borrar en la misma transacción. Y el cliente no
     puede distinguir éxito de rechazo, porque los rechazos redirigen con un
     `alert:` —302 → 200— y `turbo:submit-end` informa `success: true`.
   - El `keepalive` y el pedido normal ahora conviven sin abortarse, así que en
     una carrera de red el viejo puede pisar al nuevo.
   - `MINIMO_DE_CAMPOS_POR_CARA` mide **2 de 2 sin margen** y su rama **nunca
     corrió**: el mensaje de esa falla no está probado.
2. **Devolver la app a `anthropic`** (ver §2).
3. **Quedan C y D** de la división de cuatro partes del taller. Nada de lo de
   acá los bloquea.
