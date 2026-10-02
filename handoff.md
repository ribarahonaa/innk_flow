# Handoff

## Objetivo

Ejecutar el plan de **check-in por QR en el taller** por subagentes: un
implementador por tarea, un revisor fresco después de cada una, y una revisión de
rama entera al final.

**Las ocho tareas están cerradas, mergeadas y pusheadas**, y encima salió una
segunda tanda chica: borrar una mesa ya no saca gente del taller. `master` está
en `ff9184d` y el remote también.

La feature: un taller proyecta un QR, escanearlo es la puerta —convoca, marca
presente y sienta en una «Mesa de llegada» de la que nadie trabaja— y quien no
tiene cuenta se la crea ahí mismo, sin sesión y sin empresa en contexto, con el
tenant saliendo del token de la URL. La pantalla de quien administra proyecta el
código y lo puede activar, apagar y rotar, y un toggle por asiento escribe la
presencia de quien vino sin teléfono. Reemplaza al toggle de asistencia que el
handoff anterior dejaba fichado como punto 1, y lo incluye.

## Estado actual

- **`master` está en `ff9184d` y el remote también**, comprobado con
  `gh api repos/ribarahonaa/innk_flow/commits/master --jq .sha` (no hay clave SSH
  acá, así que `git fetch` no sirve). Las dos ramas de feature también están
  publicadas.
- **Dos merges `--no-ff`**, los dos verificados con dos padres y árbol idéntico
  al de su rama: `ac6110d` (el check-in, 31 commits) y `ff9184d` (la mesa de
  llegada que retiene, 2 commits).
- **`make spec`: 1544 ejemplos, 0 fallas**, medidos sobre `master` después del
  segundo merge. Eran 1468 al abrir la primera rama.
- **`make screens`: 74 capturas, 0 errores.** Eran 71 antes. Corrió **ocho
  veces** en total: con siembra fresca, sin resembrar, para mutar guardas, para
  verificar el `btn-block`, y de nuevo después de compilar el CSS (ver abajo:
  las primeras seis corridas validaron una pantalla que no era la que el código
  describía).
- **La migración está aplicada a la base de desarrollo**, `db/structure.sql`
  commiteado, y la base de test al día.
- **El seed siembra el cuarto taller** («Taller con check-in») y `make seed` dos
  veces seguidas deja exactamente uno.
- **`rqrcode ~> 2.2` está en el `Gemfile` y en el lock**, y las dos imágenes
  —la de desarrollo y `app_test`— están horneadas con la gema.

### Las ocho tareas

| Tarea | Commits | Qué dejó |
|---|---|---|
| 1 · Esquema y modelo | `2fcc8e7`, `f8635dc` | `workshops.attendance_mode` (`presumed`/`registered`) con su CHECK, `workshops.checkin_token` UNIQUE, `workshop_groups.arrival` con índice UNIQUE **parcial** `(workshop_id) WHERE arrival`. `Workshop#checkin_state` con cuatro valores. |
| 2 · Los escritores de presencia | `6070c2f`, `e1290a2` | `Convoke` recibe `attended:`; `AssignGroups#seat!` lo pasa explícito y excluye la mesa de llegada de las reusables; el pool sigue al modo **en las dos fases**. |
| 3 · El servicio | `9fea988`, `be666f4` | `Flow::Workshops::CheckIn`: sienta en la mesa de llegada, marca presente, idempotente incluso contra su propia carrera. |
| 4 · La ruta pública | `e5d2948`, `ce509b2`, `d6090fe` | `GET`/`POST /checkin/:token` sin sesión, el tenant desde el token, el formulario único que autentica o registra, y el concern `Authentication#sign_in!` compartido con el login. |
| 5 · La mesa de llegada | `90c914d`, `611fd87` | De la llegada no se trabaja, y son **cuatro puertas con cinco preguntas**: las dos salas, los dos controllers de escritura, y la lectura de evolución guardada dos veces (el modelo devuelve `Idea.none`, la vista dice por qué). |
| 6 · El QR y los tres controles | `6824042`, `45271e5`, `8f93ebd` | `CheckinHelper#qr_svg`, el partial con el código, y `enable_checkin`/`disable_checkin`/`rotate_checkin_token` como acciones member. |
| 7 · El toggle de presencia | `b41fd24`, `d03e0d9` | `WorkshopAttendancesController`: el ÚNICO escritor de `attended` desde la app. El partial pasó a iterar los asientos. |
| 8 · Seed, recorrido y docs | `572732b`, `7f3269a`, `255da2d` | El cuarto taller, las capturas `29`/`30`/`30b`, y `CLAUDE.md`. |
| Cierre · ola de la revisión de rama | `a0c0c6e`, `0eab4f5`, `76fdae6`, `530c53a`, `0f5277f`, `f2fb91d` | El bug de la sesión, la tercera copia de una frase falsa, el seed que borra su propia cuenta, `[CHECKIN]` midiendo el QR, y el botón full-width. |

Más `b1df244` (diseño), `594e687` y `0179f71` (plan), `544cadc` (riesgo declarado)
y `4ca8345` (el handoff anterior).

### La tanda que salió después del merge

Raúl pidió dos cosas más al ver la feature andando. La primera está hecha y
mergeada (`ff9184d`); la segunda no se empezó.

**Hecho — borrar una mesa devuelve su gente a la mesa de llegada**
(`e0e39b8`, `a3f4a96`). Borrar una mesa destruía sus asientos, así que la gente
desaparecía del taller: con asistencia registrada el asiento es el ÚNICO registro
de que alguien llegó, y aun con asistencia presumida, quien fue convocado a mano y
cuyo rol no está en el pool automático no vuelve nunca, porque el reparto sólo
conoce el pool. Ahora los asientos se MUDAN con su `attended` intacto y recién ahí
se borra la mesa vacía, detrás de tres puertas: la llegada no se elimina (para «no
vino» está «Marcar ausente», que conserva el asiento), una mesa con propuestas
tampoco (misma regla que `AssignGroups`), y en modo `individual` todo queda como
estaba porque ahí cada persona ES su mesa. El acceso a la llegada quedó en
`Workshop#arrival_group!`, una sola implementación para los dos llamadores.

**Pendiente — la lista de ingresos en TIEMPO REAL.** Está clasificada como
**arquitectónica** y no se empezó: la app no tiene hoy NINGÚN transporte en vivo
—no hay `app/channels`, no hay Turbo Streams, no hay broadcasts; las únicas
menciones a ActionCable son dos líneas comentadas en `production.rb`— y todo se
actualiza por el morph de Turbo 8 al redirigir a la misma URL. O sea que agregarlo
cambia cómo se actualizan las pantallas, no una vista. Arranca con preguntas, dos o
tres enfoques comparados, spec escrito y plan. Lo que ya está resuelto a favor:
la Mesa de llegada ES el lugar donde se acumula quien va entrando, así que «qué
mostrar en vivo» ya tiene respuesta.

### El ledger

`.superpowers/sdd/2026-10-01-checkin-por-qr/progress.md` tiene, tarea por tarea,
los commits, los hallazgos, los briefs, los reportes de los ocho implementadores y
**los 55 rulings con lo que cuesta cada uno si está mal**. Los rulings están
resumidos abajo en este archivo, porque **el ledger está gitignoreado** y un
`git clean -fdx` se lo lleva.

## Archivos y cambios

42 archivos, +5.246 / −283.

- **Esquema:** `db/migrate/20261001120000_add_checkin_to_workshops.rb` y
  `db/structure.sql`. Las tres columnas en inglés.
- **Dominio nuevo:** `app/lib/flow/workshops/check_in.rb`.
- **Dominio tocado:** `convoke.rb`, `assign_groups.rb`, `app/models/workshop.rb`,
  `app/models/workshop_group.rb`.
- **Controllers:** `workshop_checkins_controller.rb` y
  `workshop_attendances_controller.rb` nuevos; `concerns/authentication.rb` nuevo;
  tocados `application_controller.rb`, `sessions_controller.rb`,
  `workshops_controller.rb`, `workshop_ideas_controller.rb`,
  `workshop_proposals_controller.rb`.
- **Vistas:** `workshop_checkins/show.html.haml`, `workshops/_checkin.html.haml` y
  `_checkin_code.html.haml` nuevos; tocados `_assembly`, `_groups`, `_sala_idear`,
  `_sala_evolucion`, `workshops/show`.
- **Helper:** `app/helpers/checkin_helper.rb`.
- **Guardas:** la excepción nueva en `spec/lint/tenant_bypass_spec.rb`, con su
  razón escrita.
- **Specs nuevos:** `check_in_spec.rb`, `workshop_checkin_spec.rb`,
  `workshop_arrival_spec.rb`, `workshop_checkin_settings_spec.rb`,
  `workshop_attendances_spec.rb`. Ampliados `workshop_spec.rb`,
  `assign_groups_spec.rb`, `convoke_spec.rb` y los traits de
  `spec/factories/core.rb`.
- **Seed y recorrido:** `db/seeds.rb`, `script/capture_screens.js`.
- **Docs:** `CLAUDE.md`, el diseño y el plan en `docs/superpowers/`.

## Intentos fallidos

### Diez tests que no podían fallar

Esta rama encontró diez, cada uno con un mecanismo distinto. Vale más que la
feature, porque el mecanismo es lo reutilizable:

1. **Pasaba contra una página de error 500.** Con el rol en el `where`, la
   membresía no se encontraba, el `create` moría en la validación del modelo antes
   de llegar al índice, y el request terminaba en 500 — pero el rol «no se había
   bajado», así que un ejemplo que sólo miraba el rol daba verde sobre una pantalla
   de error. Se arregló exigiendo el redirect primero.
2. **Una validación corría antes que la restricción que el test decía fijar.**
3. **Los datos no distinguían las dos ramas.** El pool de idear: la empresa del
   spec no tenía ningún otro `participant`, así que el pool viejo y el nuevo
   devolvían la misma persona.
4. **El `where: "arrival"` del índice parcial no lo fijaba ningún test**, y el plan
   afirmaba que sí. El ejemplo que nombraba pasa igual con un `UNIQUE (workshop_id)`
   pelado.
5. **Sólo pedía `not_to raise_error`**, así que un `ok: false` lo pasaba.
6. **Una guarda hermana cortocircuitaba primero.** Sin la guarda del controller de
   propuestas, `workable_ideas` ya devolvía `Idea.none`, el `find_by!` daba 404, y
   el único assert (`not_to change { count }`) pasaba sobre ese 404.
7. **Los iconos SVG del layout aportaban la cadena que la aserción buscaba.**
   `include("<svg")` daba verde **con el QR ausente de la página**. Medido: vieja
   11/0 verde sin QR, nueva 2 fallas.
8. **El default de la columna tapaba la diferencia.** `attended` viene `true`, así
   que un asiento creado en `true` no distinguía «lo preservó» de «nunca lo tocó».
9. **Probaba una puerta distinta de la que decía.** «No lo ve quien participa» no
   probaba `can_edit`: la sección entera cuelga de `can_assemble`. Lo destapó un
   control positivo que se puso **rojo**.
10. **Una mutación que no mutaba.** Cambié `.w-60` por `.w-16` para probar la
    guarda del QR y la corrida siguió verde — porque `w-16` no existe en la hoja
    compilada (Tailwind escanea texto y la hoja la compila `yarn build:css`, que
    `make screens` no corre), así que el div quedó sin regla de ancho y el QR salió
    **más grande**. La mutación válida fue un `style` inline de 40px, y ahí sí
    imprimió `[CHECKIN] el QR mide 40×40`.

**La lección acumulada:** no alcanza ver la mutación en rojo. Hay que preguntarse
**por qué** se pone rojo —puede ser un 500, una validación anterior, una guarda
hermana o datos que no distinguen— y **si la mutación realmente mutó algo**. Y
cuando dos ejemplos cubren cosas parecidas, la prueba de que no son el mismo test
es **cruzada**: cada mutación rompe uno y deja verde el otro.

### Siete afirmaciones falsas, y una nació de arreglar otra

1. El plan decía que normalizar el email a mano era lo que evitaba el choque contra
   el índice. Falso: `User` declara `normalizes :email` y en Rails 7.1 eso normaliza
   también el valor de los finders. Se midió de los dos lados y se dejó como defensa
   explícita, con el comentario reescrito.
2. «Mismo mensaje y misma pregunta que las otras tres puertas»: la pregunta sí, el
   mensaje no.
3. «Para eso está el toggle de cada integrante», cuando el toggle no existía. Salió
   en la Tarea 6 y volvió en la 7, ya verdadera, nombrando `attendance_workshop_path`.
4. La misma cláusula falsa en una **segunda** copia, en el spec.
5. «`WorkshopCheckinsController`, la ÚNICA ruta pública de la app», en `CLAUDE.md`.
   Falsa: `SessionsController` también se sirve sin sesión.
6. **La reescritura del 5 afirmó otra cosa falsa:** «el login sólo autentica y no
   resuelve ninguna empresa». `sessions_controller.rb:27` es
   `sign_in!(user, company: default_company_for(user))`. Una frase editada **para**
   ser verdadera es la que más se desvía mientras se edita.
7. Y la **tercera** copia del 5 seguía en `config/routes.rb`, que es lo primero que
   alguien abre. Más un comentario de la guarda del QR que afirmaba un 300×150 que
   yo medí que no ocurre.

### Tres defectos del plan, encontrados durante la ejecución

- **El hueco de evolución:** `people_of` restaba `absent_ids`, que sólo conoce a
  quien **tiene asiento**, así que el autor de una idea que nunca escaneó entraba al
  reparto igual. El plan sólo mandaba tocar `groups_by_person`.
- **El `case` partido en dos mecanismos:** `if presumed_attendance?` afuera y
  `case checkin_state` adentro, cuando `:off` ya es uno de los cuatro valores. Dejaba
  el `else` significando «cerró», así que un quinto estado habría mentido.
- **`status: "submitted"` no existe** en `Idea::STATUSES`, y con un status no-`alive`
  los dos ejemplos de evolución habrían pasado sin probar nada.

### El bug, y era el único en 30 commits

`sign_in!(user, company: @workshop.company) **unless signed_in?**`. Con sesión viva
se salteaba, así que la fila de `sessions` conservaba su `company_id` viejo; y como
`with_tenant_context` es un `around_action` que hace
`Current.company = current_session&.company`, el request siguiente resolvía el
taller con `policy_scope` sobre la empresa vieja y daba **404 después de haber
escrito la membresía, el asiento y el `attended`**. El ejemplo que existía era ciego
porque firmaba a `admin` en la **misma** empresa.

Se arregló moviendo la sesión existente y **no** llamando `sign_in!` otra vez:
`sign_in!` hace `user.sessions.create!` sin tocar la fila vieja, así que habría
dejado **dos sesiones vivas** en un endpoint donde sólo el token autentica. Los dos
ejemplos nuevos fallan por motivos **distintos** —404 el de otra empresa, 302 a
`select_company` el de empresa `nil`— y es un `contain_exactly` el que caza la
variante de las dos sesiones, no el 200.

### Cosas que no funcionaron como el plan decía

- **`make db-prepare-test` no sirve para mutar una migración:** `db:prepare` no
  recarga una base que ya existe, y lee `structure.sql` y no la migración. Hay que
  mutar el índice **en la base de test con DDL directo** y restaurarlo.
- **`make rebuild` no toca el perfil `test`.** `Dockerfile.test` copia
  `Gemfile Gemfile.lock` y bundlea **en build**, así que una gema nueva pide además
  `docker compose --profile test build app_test` o los specs corren contra una imagen
  sin la gema y fallan por el motivo equivocado. El `Gemfile.lock` se genera con
  `docker compose exec app bundle install`, que el bind mount `.:/rails` escribe en
  el host.
- **El churn de `pg_dump` en `structure.sql`:** la versión del contenedor reformatea
  todos los CHECK que ya existían a SQL equivalente y rota el token de `\restrict`.
  Se aceptó —está diffeado y es el mismo predicado— porque editar a mano un archivo
  generado sería peor.

### Lo que encontró la segunda tanda

- **Un refactor correcto rompió algo sin cambiar el método.** Extraer
  `CheckIn#landing` a `Workshop#arrival_group!` mudó también su rescate de la
  carrera contra el índice UNIQUE parcial — y ese rescate sólo había corrido FUERA
  de una transacción. El llamador nuevo lo invoca ADENTRO de una, y ahí una
  violación de unicidad aborta la transacción entera: el `find_by!` del rescate
  revienta con `PG::InFailedSqlTransaction`. Un 500 justo donde el comentario
  prometía recuperación. Lo que cambió no fue el método, fue el CONTEXTO desde el
  que se lo llama. Arreglado con `transaction(requires_new: true)` dentro del
  método —para que sea correcto para cualquier llamador— y con un ejemplo que
  provoca una violación real de Postgres adentro de una transacción.
- **Una primera versión creaba la mesa de llegada al borrar una mesa VACÍA**, y lo
  atrapó un spec que ya existía y nadie tocó (`workshop_convocation_spec.rb:50`),
  de rebote, por un conteo. Ahora tiene ejemplo propio: un bug que ya ocurrió
  merece un test que lo nombre.
- **Una Important de la revisión era FALSA y se cortó antes de «arreglar» algo que
  funciona.** Decía que el aviso apunta a «Marcar ausente», un control que podría
  no existir, citando `CLAUDE.md`. El control existe (`_groups.html.haml:95`,
  `routes.rb:103`): la frase de `CLAUDE.md` que citaba la había borrado el merge de
  ese mismo día. El revisor estaba recitando el estado anterior.
- **El `with_lock` nuevo se eligió MEJOR de lo que se había pedido.** Se sugirió
  bloquear el taller; el implementador bloqueó la MESA, con el argumento de que
  crear una propuesta toma `FOR KEY SHARE` sobre esa fila por la FK, que choca con
  `FOR UPDATE` — así protege aunque quien crea la propuesta no bloquee nada.
  Bloquear el taller no habría tocado la fila que la inserción sí toca.
- **Ese lock NO tiene spec, y es a propósito.** Cambiar `with_lock` por
  `transaction` deja la suite verde. Probarlo pide concurrencia real que esta suite
  no hace, y un `expect(...).to receive(:lock!)` afirmaría que el método se llama,
  no que el lock funcione: es una aserción sobre un mock, que la propia rúbrica de
  este repo llama defecto. El `with_lock` de `AssignGroups` tampoco tiene spec.

## Los 55 rulings

Lo que decidí en tu nombre, en orden, con lo que cuesta si está mal. El detalle
completo de cada uno está en el ledger mientras exista.

**De arranque (4).** `make rails db:migrate` no existe, el target es `make migrate`
· `make migrate`/`rebuild`/`seed`/`screens` los corre la sesión principal y los
subagentes sólo `make spec*` · después de `make migrate` va `make db-prepare-test`
· paro al terminar cada tarea y pido permiso. Costo: convenciones, cero riesgo.

**Tarea 1 (3).** El churn de `pg_dump` se acepta · el Important del revisor es
correcto y el PLAN estaba mal sobre el índice parcial · el ⚠️ lo resuelvo yo con el
contexto cruzado. Costo del primero: un diff ruidoso en cada migración futura.

**Tarea 2 (2).** El ⚠️ es un hueco REAL y entra al fix loop (`people_of`) · el Minor
viaja en el mismo round. Costo si el primero está mal: mesas armadas alrededor de
gente que no está en la sala.

**Tarea 3 (4).** El Important 2 es un bug real en el camino principal · el Important
1 también · dos Minor viajan porque son reglas del repo · el ⚠️ lo resuelvo yo
(`CheckIn#call` no va envuelto en transacción). Costo: un round de más.

**Tarea 4 (5).** La premisa del brief sobre `.strip.downcase` era falsa · el concern
1 es load-bearing (la carrera de `find_by` + `new.save`) · el concern 3 viaja ·
el concern 2 se DOCUMENTA, no se arregla con código · el hueco que el revisor marcó
no bloqueante lo CONFIRMO como gap. Costo del segundo si está mal: un 500 en el
camino primario.

**Tarea 5 (5).** La expectativa de la mutación 1 del plan es falsa y no se persigue
· la cuarta puerta no tiene test y eso entra al brief · el tercer defecto del plan
(`"submitted"`) es real · los dos ⚠️ los resuelvo con greps · PROMUEVO un Minor
—el comentario que miente— contra la regla de que los Minor no entran. Costo del
último: un round barato de más.

**Tarea 6 (8).** Las keywords de `as_svg` existen pero el prólogo XML se saca · el
partial va con UN `case` · el partial extra se queda y el costo es mío · la cláusula
del toggle sale y la Tarea 7 la repone · los tres ⚠️ los resuelvo yo · promuevo dos
Minor y sumo un defecto que el revisor no terminó de medir (el botón sobre un taller
cerrado) · sale a fix round 2 y el defecto es MÍO (las aserciones vacías de `<svg>`)
· el `74` de `CLAUDE.md` queda, confirmado por medición. **Y uno donde me
equivoqué:** dije que la lista de guardas de `CLAUDE.md` es la enumeración completa
y es falso —34 tags en el script, 15 documentados—.

**Tarea 7 (6).** El asiento se busca por `workshop_id` directo (UNIQUE con
`user_id`) · se suma la puerta de la VISTA, que el plan no prueba · la Tarea 7
repone la cláusula de la 6 · los dos ⚠️ los resuelvo yo · promuevo los dos Minor ·
el reparto de puertas que queda es completo y la concern del implementador es
informativa. Costo del segundo si está mal: un ejemplo de más.

**Tarea 8 (7).** El `goToWorkshop` va con guarda `if` o una falla aborta la corrida
en vez de contarse · tres frases de documentación que la tarea vuelve falsas · el
reparto queda en dos despachos · me corrijo sobre la lista de guardas · dos
afirmaciones de `CLAUDE.md` al fix round · los dos Important son reales y el segundo
es peor de lo que el revisor dijo (el comentario se contradice **dentro del mismo
bloque**) · promuevo dos Minor.

**Cierre (11).** Re-corro `make screens` sin resembrar, que es más informativo ·
el Important 1 es un bug real y lo verifiqué entero · cierro el único punto que el
revisor no pudo verificar (el prólogo XML, que yo medí) · once de los catorce
findings van a la ola y tres no, con motivo · el `handoff.md` lo escribo yo y no un
subagente · acepto las dos correcciones del implementador a MIS instrucciones (el
framing de la transacción y el premise de la mutación del QR) · la mutación del QR
la corro yo · mi primera mutación fue INVÁLIDA · la rama «no es cuadrado» queda sin
mutación verificada, declarada · el único Minor nuevo lo arreglo YO rompiendo mi
propia regla, y digo por qué · el `btn-block` lo decidís vos y dijiste que sí.

**El que más caro sale si está mal** es el del índice parcial de la Tarea 1: sin el
`where: "arrival"` el reparto entero se rompe. Está probado por mutación con DDL
directo.

## Próximos pasos

1. **La lista de ingresos en TIEMPO REAL**, que es lo único que queda del pedido
   original y es arquitectónica. Ver «La tanda que salió después del merge».
2. **El tamaño del QR**, por si 208px sigue pareciendo mucho: hay margen hasta
   ~160px sin tocar nada, porque el piso de `[CHECKIN]` son 150. Bajar ese piso es
   decidir que la legibilidad EN PANTALLA importa menos, dado que la proyección
   real pasa en otro lado.
3. **Borrar el workspace del plan** (`.superpowers/sdd/2026-10-01-checkin-por-qr/`),
   que sigue en disco. Está gitignoreado; el registro ya vive en `git log` y en
   este archivo. También quedó `.superpowers/sdd/mesa-de-llegada-retiene-report.md`
   de la segunda tanda.
4. **Lo que quedó declarado y no se arregla**, por si algún día deja de alcanzar:
   - El **oráculo de existencia por resultado** del check-in y el **pre-registro de
     cuentas con emails ajenos**: decididos el 2026-10-01, en «Riesgos» del diseño,
     con sus dos salidas (dominios permitidos, o confirmación por correo sólo cuando
     el email no existe). No reabrir sin motivo nuevo.
   - **El token es una URL-capacidad en el PATH**, así que va a logs de acceso y a
     historial del navegador, donde una clave nunca va (los params se filtran, un
     segmento de path no). Sin expiración; rotar es la única revocación y es manual.
     Declarado en «Riesgos» en esta rama.
   - **La rama «no es cuadrado» de `[CHECKIN]`** no tiene mutación verificada:
     `qr_svg` hoy no puede producir ese estado. La del piso de 150px sí está probada.
   - **Marcar ausente por `attended` ya se puede** (Tarea 7), pero **el `[CHECKIN]`
     no tiene contador de cuánto midió**, al revés de `[RELLENO]` y `[RITMO]`.
5. **Lo que sigue abierto de handoffs anteriores, sin tocar:** el desborde vertical
   de los dos diagramas (arquitectura 1345px, proceso 1688px en un viewport de 900);
   que `make screens` no vea violaciones de CSP porque sólo escucha `pageerror`; el
   nodo salteado del mapa a 1,96:1; el flake horario de
   `spec/requests/selection_screen_spec.rb:138`; la actualización de `archify`
   (2.17.0-dev.1 instalada, 3.0.1 disponible); y `challenge_gestores` huérfano
   re-otorgando acceso.

## Cosas del entorno

- **En desarrollo `FLOW_AI_PROVIDER=anthropic`, pero nada de esta rama gasta
  plata**, y está verificado: `db/seeds.rb:17` fija
  `Flow::AI::Providers::Fixture` explícitamente, y `script/capture_screens.js:2113`
  intercepta `**/ai_requests*` con `page.route` justamente por eso.
- **`[PASTILLA]` crece +4 por corrida de `make screens`** (633 → 637 → 641 → 657) y
  **no es una regresión**: `capture_screens.js:2575` envía «Guardar el testeo» de
  verdad, así que cada corrida acumula un testeo y cada fila nueva pinta ~4 chips.
  Es pre-existente, de los planes del módulo de testing. La guarda falla sólo si
  mide **menos** de lo declarado, nunca más — pero el número creciente se lee como
  regresión si nadie lo explica.
- **Baseline de las guardas del recorrido**, que antes no estaba registrado en
  ningún handoff: `[RITMO]` 39 de 74 pantallas · `[RELLENO]` 280 `card-body` ·
  `[CRITERIO]` 195 nombres. Los tres estables entre corridas.
- **Qué corre la sesión principal y qué los subagentes.** `make migrate`,
  `make rebuild`, `make seed` y `make screens` tocan la base de desarrollo o los
  contenedores: los corre la sesión principal. Los subagentes corren `make spec*` y
  `make db-prepare-test`. Eso cuesta que las tareas 1, 6 y 8 pidan dos despachos, y
  en la 6 lo colapsé a uno resolviendo la gema yo antes de despachar.
- **Probar una guarda es romperla a mano y correrla**, con el backup por `cp` al
  scratchpad. Nunca `git checkout <archivo>`: en una rama sin commit eso restaura
  del índice, o sea deshace el ARREGLO y no la mutación. Un implementador verificó
  cada restauración con `cmp`, que es mejor y no se lo pidió nadie.
- **El reparto de los subagentes funcionó mejor pidiendo el POR QUÉ, no la
  instrucción.** Cada dispatch llevó el motivo de cada cambio —qué se rompe si se
  simplifica— y los implementadores encontraron cosas que el brief no decía; dos de
  ellos **corrigieron mis propias instrucciones**, las dos veces con razón.
- `make screens` tarda ~2 minutos y `make spec` ~2; las dos corren bien en
  background.
- El harness sigue inyectando `Co-Authored-By` y `Claude-Session` por
  system-reminder; hay que cortarlas a mano. **Ningún commit de esta sesión lleva
  trailers**, verificado con un grep sobre los dos rangos y sobre los dos merges.
- **`git merge -F -` NO lee de stdin**, al revés de `git commit -F -`: falla con
  `error: could not read file '-'` y el merge no ocurre. El mensaje va a un
  archivo. Costó un intento.
- **La hoja de CSS compilada vive SÓLO en el contenedor y está gitignoreada**
  (`/app/assets/builds/*`). El layout linkea `application-build-css`, que produce
  `yarn build:css`. Agregar clases de Tailwind nuevas sin correr `make yarn-build`
  hace que la app sirva una hoja vieja y que `make screens` valide **una pantalla
  distinta de la que el código describe**. Pasó de verdad: la tarjeta del QR se
  sirvió sin ancho, sin fondo blanco, sin relleno y sin bordes durante SEIS
  corridas verdes —el QR llenaba la tarjeta entera— y además «negro sobre blanco
  en los dos temas», que es de lo que depende que se escanee en tema oscuro, nunca
  fue cierto en la app servida. Medido: antes de compilar, `w-60`, `bg-white`,
  `p-4` y `rounded-box` aparecían CERO veces en la hoja.
- **Y `[CLASES]` no puede cazarlo**, que es la razón técnica de esas seis corridas
  verdes: escanea una lista FIJA de familias de componentes
  (`[class*="badge"]`, `[class*="btn"]`, `[class*="alert"]`,
  `[class*="flow-drawer__punto"]`, `.steps`, `.panel`, `.card`,
  `.table :is(th,td)`), así que un elemento hecho sólo de utilidades de Tailwind es
  invisible para esa guarda.
- **El taller borrador del recorrido se usa a mano y eso rompe la corrida.**
  Apareció un taller llamado `fdsdfsd` en la base de desarrollo y, con él, «Taller
  de planificación (borrador)» quedó `open` con tres vínculos: `make screens` falló
  con `[TALLER]` hasta resembrar. Es el antipatrón que CLAUDE.md nombra para
  desafíos, ahora visto en un taller. Si el recorrido falla por `[TALLER]`, mirá el
  estado del borrador en la base antes de buscar el bug en el código.
