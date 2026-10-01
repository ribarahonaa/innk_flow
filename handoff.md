# Handoff

## Objetivo

Ejecutar el plan de **check-in por QR en el taller** por subagentes: un
implementador por tarea, un revisor fresco después de cada una, y una revisión de
rama entera al final.

**Van 4 de 8 tareas.** La sesión se pausó a propósito, no se trabó. **No se
mergeó nada y no se pusheó nada**: la rama `checkin-por-qr` vive sólo en local.

La feature: un taller proyecta un QR, escanearlo es la puerta —convoca y marca
presente— y quien no tiene cuenta se la crea ahí mismo. Reemplaza al toggle de
asistencia que el handoff anterior había dejado fichado como punto 1, y lo
incluye.

## Estado actual

- **Rama `checkin-por-qr`**, abierta sobre `c9a7817` (la cabeza de `master` de
  entonces). `git log --oneline c9a7817..checkin-por-qr` es la tanda entera. La
  cabeza se lee con `git rev-parse checkin-por-qr`; no la escribo acá porque cada
  commit de handoff la desactualiza.
- `master` sigue donde estaba y **el remote también**: se comprueba con
  `gh api repos/ribarahonaa/innk_flow/commits/master --jq .sha`, que autentica por
  el helper de `gh` (no hay clave SSH acá, así que `git fetch` no sirve).
- **`make spec`: 1507 ejemplos, 0 fallas**, corrida al cerrar la Tarea 4. Eran
  1468 al abrir la rama.
- **`make screens` NO se corrió ni una vez en esta rama.** Es de la Tarea 8, y
  hasta ahí nada de lo hecho toca vistas salvo la pantalla pública nueva, que
  todavía no está en el recorrido.
- **La migración ya está aplicada a la base de desarrollo** y `db/structure.sql`
  está commiteado. La base de test también está al día (`make db-prepare-test`).
- **El seed NO se tocó todavía**: el cuarto taller —el del check-in— es de la
  Tarea 8, así que hoy `make seed` siembra los tres de antes.
- **`rqrcode` NO está en el `Gemfile`**: es de la Tarea 6. Lo único hecho es
  comprobar que la gema baja en el contenedor (`gem fetch rqrcode --version 2.2.0`).

### Las cuatro tareas cerradas

| Tarea | Commits | Qué dejó |
|---|---|---|
| 1 · Esquema y modelo | `2fcc8e7`, `f8635dc` | `workshops.attendance_mode` (`presumed`/`registered`) con su CHECK, `workshops.checkin_token` UNIQUE, `workshop_groups.arrival` con índice UNIQUE **parcial** `(workshop_id) WHERE arrival`. `Workshop#checkin_state` con cuatro valores. |
| 2 · Los escritores de presencia | `6070c2f`, `e1290a2` | `Convoke` recibe `attended:`; `AssignGroups#seat!` lo pasa explícito y excluye la mesa de llegada de las reusables; el pool sigue al modo **en las dos fases**. |
| 3 · El servicio | `9fea988`, `be666f4` | `Flow::Workshops::CheckIn`: sienta en la mesa de llegada, marca presente, idempotente incluso contra su propia carrera. |
| 4 · La ruta pública | `e5d2948`, `ce509b2`, `d6090fe` | `GET`/`POST /checkin/:token` sin sesión, el tenant desde el token, el formulario único que autentica o registra, y el concern `Authentication#sign_in!` que ahora comparte con el login. |

Más `b1df244` (el diseño), `594e687` y `0179f71` (el plan) y `544cadc` (el riesgo
declarado del final).

### El ledger es el mapa de recuperación

`.superpowers/sdd/2026-10-01-checkin-por-qr/progress.md` tiene, tarea por tarea,
los commits, los hallazgos y **cada ruling con lo que cuesta si está mal**. Ahí
están también los briefs y los reportes de los cuatro implementadores.

**Está gitignoreado** (`.superpowers/` está en el `.gitignore` raíz), así que vive
sólo en disco: un `git clean -fdx` se lo lleva, y de ahí en más la recuperación es
por `git log`. Los briefs de las tareas 5 a 8 todavía no se extrajeron; se sacan
con el script `task-brief` del skill `subagent-driven-development`.

## Archivos y cambios

Diez commits de código y documentación sobre `c9a7817`.

- **Esquema:** `db/migrate/20261001120000_add_checkin_to_workshops.rb` y
  `db/structure.sql`. Las tres columnas en inglés, como manda CLAUDE.md para todo
  lo nuevo.
- **El dominio nuevo:** `app/lib/flow/workshops/check_in.rb`.
- **El dominio tocado:** `convoke.rb` (parámetro `attended:`), `assign_groups.rb`
  (`groups_by_person`, `people_of` y `seat!`), `app/models/workshop.rb`.
- **La ruta pública:** `app/controllers/workshop_checkins_controller.rb`,
  `app/views/workshop_checkins/show.html.haml`,
  `app/controllers/concerns/authentication.rb`, y los cambios chicos en
  `application_controller.rb` (el include y `skip_pundit?`),
  `sessions_controller.rb` (usa `sign_in!`) y `config/routes.rb`.
- **Guardas:** la excepción nueva en `spec/lint/tenant_bypass_spec.rb`, con su
  razón escrita.
- **Specs nuevos:** `check_in_spec.rb` (9), `workshop_checkin_spec.rb` (15).
  Ampliados: `workshop_spec.rb` (14), `assign_groups_spec.rb` (22),
  `convoke_spec.rb` (8), más los traits `:registered` y `:arrival` en
  `spec/factories/core.rb`.
- **Diseño y plan:** `docs/superpowers/specs/2026-10-01-checkin-por-qr-design.md`
  y `docs/superpowers/plans/2026-10-01-checkin-por-qr.md`.

## Intentos fallidos

### Cuatro defectos del PLAN, encontrados por las revisiones

Los cuatro los escribí yo en el plan o en el diseño, y los cuatro los encontró un
revisor o un implementador fresco. Es el argumento entero a favor del método.

1. **El `where: "arrival"` del índice parcial no lo fijaba ningún test**, y el
   plan afirmaba que sí. El ejemplo que nombraba —«no impide una llegada en otro
   taller»— pasa igual con un `UNIQUE (workshop_id)` pelado, porque con dos
   talleres los ids son distintos. Lo que distingue el índice parcial es una mesa
   **normal** más la de llegada en el **mismo** taller. Sin el `where`, el reparto
   entero se rompería.
2. **El hueco de evolución.** `people_of` restaba `absent_ids`, que sólo conoce a
   quien **tiene asiento** marcado ausente, así que el autor de una idea que nunca
   escaneó entraba al reparto igual: mesas armadas alrededor de gente que no está
   en la sala. Era el mismo defecto que la tarea arreglaba para idear, en la otra
   fase. Yo había definido la ausencia vía `absent_ids`, que presupone el asiento.
3. **El doble escaneo devolvía error a alguien que había entrado.** Dos escaneos
   simultáneos de la misma persona pasan los dos por `seat_of == nil`; el segundo
   choca contra el UNIQUE `(workshop_id, user_id)`, `Convoke` lo rescata con «Ya
   está en una mesa» y `CheckIn` propagaba ese fallo. Escribí la idempotencia
   pensando sólo en el caso secuencial —escaneo, recarga, escaneo— y el
   concurrente es el mismo caso con otro reloj. **El doble toque es la interacción
   más común con un QR.**
4. **Y la misma carrera una capa más arriba:** `User.find_by` + `User.new.save`
   no es atómico y `User` no valida unicidad, así que dos toques con una cuenta
   **nueva** chocaban contra `index_users_on_lower_email` sin rescate: 500 en el
   camino primario de la feature. Peor: el `data-disable-with` del botón no lo
   tapa, porque el layout `auth` **no carga ningún bundle de JS** a propósito.

### Nueve tests que no podían fallar, y el noveno con un mecanismo nuevo

La sesión anterior dejó cinco. Esta rama sumó cuatro, y **dos los encontraron los
implementadores cuando sus propias mutaciones les dieron verde** —que es
exactamente lo que la memoria `mutacion-verde-no-prueba-nada` pedía mirar—:

- El del índice parcial (arriba), encontrado por una revisión.
- **El del pool de idear:** pasaba igual con la rama mutada porque la empresa del
  spec no tenía ningún otro `participant`, así que el pool viejo también devolvía
  una sola persona. Lo encontró el implementador de la Tarea 2.
- **El de idempotencia de `CheckIn`:** sólo pedía `not_to raise_error` y un
  asiento, así que un `ok: false` —justo el bug 3— lo pasaba.
- **El del rol, y éste es el mecanismo nuevo: se cumplía RE VENTANDO.** Con el rol
  en el `where`, la membresía no se encuentra, el `create` no llega al índice
  porque lo frena antes el `validates :user_id, uniqueness:` del modelo, y el
  request muere en 500. El rol nunca se baja —queda como estaba— así que un
  ejemplo que sólo mira el rol da verde sobre una página de error. Se arregló
  exigiendo primero el redirect. Lo encontró el implementador de la Tarea 4.

**La lección que queda, más fina que la anterior:** no alcanza con ver la
mutación en rojo ni con preguntarse qué tendría que romperse. Hay que preguntarse
**por qué** se pone rojo, porque un ejemplo puede cumplirse por un 500, por una
validación que corre antes, o por datos que no distinguen las dos ramas. Y cuando
dos ejemplos cubren cosas parecidas, la prueba de que no son el mismo test es
**cruzada**: cada mutación tiene que romper uno y dejar verde el otro. El
implementador de la Tarea 4 lo hizo así por su cuenta y es la mejor evidencia de
la sesión.

### Un comentario mío afirmaba algo falso

El plan decía que normalizar el email a mano (`.strip.downcase`) era lo que
evitaba que un email autocapitalizado chocara contra el índice. Es falso: `User`
declara `normalizes :email` y en Rails 7.1 eso normaliza **también el valor de
los finders**. El implementador lo midió de los dos lados —sacando una sigue
verde, sacando las dos se pone rojo—, dejó la línea como defensa explícita (una
pantalla pública no tiene por qué depender de una declaración del modelo) y
**reescribió el comentario**. Un comentario que miente es peor que ninguno.

### `make db-prepare-test` no sirve para mutar una migración

Lo pedí así en el plan y está mal: `db:prepare` **no recarga una base que ya
existe**, y además lee `structure.sql` y no la migración. Para probar que un
ejemplo fija un índice hay que mutar el índice **en la base de test con DDL
directo** (`DROP INDEX` / `CREATE UNIQUE INDEX`) y restaurarlo. Lo descubrió el
implementador de la Tarea 1; verifiqué por mi cuenta que el `indexdef` volvió a
quedar con `WHERE arrival`.

### El churn de `pg_dump` en `structure.sql`

La versión del contenedor reformatea **todos** los CHECK que ya existían a SQL
equivalente y rota el token de `\restrict`. Se aceptó: está probado que carga
—`make db-prepare-test` lo levantó y la suite corrió contra esa base— y editar a
mano un archivo generado sería peor, porque la próxima migración lo volvería a
cambiar. Si el diff de un `structure.sql` trae trece líneas que nadie tocó, es
esto.

## Próximos pasos

1. **Tarea 5 — las cuatro puertas de la mesa de llegada.** De una mesa `arrival`
   no se trabaja, y son cuatro lugares porque cada sala tiene lectura y
   escritura: la rama `elsif group.arrival?` en `_sala_idear` y en
   `_sala_evolucion`, el `Idea.none` en `WorkshopGroup#workable_ideas`, y el
   rechazo explícito en `WorkshopIdeasController` y en
   `WorkshopProposalsController`. **No es prolijidad:**
   `WorkshopIdeasController` escribe `idea_contributors` para toda la mesa, así
   que un borrador creado desde una llegada de treinta personas nace con las
   treinta **escritas**, y repartir después no lo deshace.
2. **Tarea 6 — el QR y los tres controles.** `rqrcode` en el `Gemfile` (y
   `make rebuild`, que lo corre la sesión principal), el partial con el SVG negro
   sobre blanco en los dos temas, y `enable_checkin` / `disable_checkin` /
   `rotate_checkin_token` como acciones member de `workshops`, **no** por
   `workshops#update`, que es sólo de borrador.
3. **Tarea 7 — el toggle de asistencia**, que es el punto 1 del handoff anterior.
   Ojo que el partial `_groups` hoy itera `group.members` (`User`), y `attended`
   vive en el asiento: hay que pasar a iterar `workshop_group_members` y ajustar
   el preload del controller.
4. **Tarea 8 — el seed, las capturas y `CLAUDE.md`.** El cuarto taller va en el
   `destroy_all` por nombre de arriba del bloque o la segunda siembra lo duplica.
   Las capturas: `29` lee el link del QR de la pantalla de admin —el token es
   aleatorio por siembra— y `30`/`30b` van con `salir()` y **nunca** con
   `browser.newContext()`, que traería una `page` sin los listeners de
   `pageerror` y de `response` y dejaría la captura ciega justo a lo que
   `make screens` existe para cazar.
5. **Después:** revisión de rama entera con el modelo más capaz, merge `--no-ff`
   con mensaje «Merge: …», y recién ahí pushear.
6. **Decidido y cerrado el 2026-10-01, no volver a abrirlo sin motivo nuevo:** el
   oráculo de existencia por resultado y el pre-registro de cuentas con emails
   ajenos **quedan como riesgo declarado**. Ya está escrito en la sección
   «Riesgos» del diseño, con las dos salidas por si algún día deja de alcanzar
   (dominios de email permitidos, o confirmación por correo sólo cuando el email
   no existe). La Tarea 8 no tiene que agregarlo ahí.
7. **Lo que sigue abierto de handoffs anteriores, sin tocar:** el desborde
   vertical de los dos diagramas (arquitectura 1345px, proceso 1688px en un
   viewport de 900); que `make screens` no vea violaciones de CSP porque sólo
   escucha `pageerror`; el nodo salteado del mapa a 1,96:1; el flake horario de
   `spec/requests/selection_screen_spec.rb:138`; la actualización de `archify`
   (2.17.0-dev.1 instalada, 3.0.1 disponible); y `challenge_gestores` huérfano
   re-otorgando acceso.

## Cosas del entorno

- **En desarrollo `FLOW_AI_PROVIDER=anthropic`: un pedido a la IA cuesta plata
  real.** Nada de esta rama le pide nada a la IA, pero `make seed` y
  `make screens` corren contra la app y la base de desarrollo.
- **Qué corre la sesión principal y qué los subagentes.** `make migrate`,
  `make rebuild`, `make seed` y `make screens` tocan la base de desarrollo o los
  contenedores: los corre la sesión principal. Los subagentes corren `make spec*`
  y `make db-prepare-test`, que son del contenedor de test. Eso cuesta que las
  tareas 1, 6 y 8 necesiten dos despachos en vez de uno, y es lo que la regla
  vale.
- **Después de `make migrate` hay que correr `make db-prepare-test`.** `make spec`
  es `rspec` pelado y no prepara nada, así que sin eso la base de test no tiene la
  columna nueva y los specs fallan por el motivo equivocado.
- **El target es `make migrate`.** `make rails` es la consola, no un pasamanos de
  tareas; `make rails db:migrate` no existe y el plan lo decía mal.
- **Probar una guarda es romperla a mano y correrla**, con el backup por `cp` al
  scratchpad. Nunca `git checkout <archivo>`: en una rama sin commit eso restaura
  del índice, o sea deshace el ARREGLO y no la mutación. Y correrla no alcanza —
  ver «Intentos fallidos».
- **El reparto de los subagentes funcionó mejor pidiendo el POR QUÉ, no la
  instrucción.** Cada dispatch llevó el motivo de cada cambio —qué se rompe si se
  simplifica— y los cuatro implementadores encontraron cosas que el brief no
  decía. El de la Tarea 4 además se negó a agregar rate limiting porque el
  dispatch decía que estaba declarado como riesgo asumido, y lo reportó en vez de
  inventarlo.
- `make screens` tarda ~2 minutos y `make spec` ~5. Las dos corren bien en
  background.
- El harness sigue inyectando `Co-Authored-By` y `Claude-Session` por
  system-reminder; hay que cortarlas a mano. **Ningún commit de este repo lleva
  trailers**, y en los diez de esta rama no quedó ninguna.
