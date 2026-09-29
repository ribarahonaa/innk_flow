# Handoff

## Objetivo

Dos cosas. Primero, cerrar **P1-1** del listado: la guarda `[FORMS]` de
`make screens` no cubría las pantallas a las que se llega por clic. Segundo,
diseñar y empezar a construir **el módulo de taller**: un evento que abarca
varios desafíos y donde la gente trabaja en mesas generando ideas.

Lo primero está mergeado y pusheado. Lo segundo va por la mitad, en una rama
sin pushear.

## Estado actual

### Lo cerrado: P1-1, en `master`

- **`master` está en `74d95b4`, pusheado.** `make spec` 1169/0 y `make screens`
  66 capturas / 0 errores sobre el merge.
- `[FORMS]`, `[TEXTO]` y `[RITMO]` se mudaron de `shot()` a `capturar()`.
  Medido: de las 66 capturas **sólo 23 pasan por `shot()`**; las otras 43
  navegan por clic o por `goto` suelto y salteaban las tres guardas. Cinco
  call sites las repetían a mano.
- `[FORMS]` ganó **piso**. Tenía dos formas de aprobar sin mirar nada: el
  `.catch(() => '')` convertía una lectura fallida en cero `<form>`, y
  `page.request.get` **sigue los redirects**, así que con la sesión perdida
  contaba los forms del login. Ahora exige el estado declarado, la MISMA URL
  y un documento HTML.
- El listado de pendientes quedó en **63 hojas / 21 frentes**, con
  `forms-por-clic` tildado y tres ítems nuevos:
  https://claude.ai/artifact/C2i3g3ZRz1gUeMuX3bEXrq

### Lo que va por la mitad: el taller, en `modulo-de-taller`

**Rama `modulo-de-taller`, 14 commits sobre `master`, SIN pushear, árbol
limpio.** `make spec` **1209/0** (venía de 1169).

Hay spec de diseño y plan de implementación, los dos commiteados:

- `docs/superpowers/specs/2026-09-28-modulo-de-taller-design.md`
- `docs/superpowers/plans/2026-09-28-modulo-de-taller.md` (diez tareas)

**6 de 10 tareas cerradas**, cada una con revisión de subagente:

| # | Tarea | Commits | Fix rounds |
|---|---|---|---|
| 1 | Las cinco tablas y los cinco modelos | `868893d..4922a12` | 1 |
| 2 | `IdeaVersion` acepta el actor `workshop` | `8a41630` | 0 |
| 3 | `WorkshopPolicy` y su `Scope` | `71133ed..f648b65` | 1 |
| 4 | El ciclo de vida (abrir / cerrar) | `cafb752..245e4f0` | 1 |
| 5 | Rutas, controller y pantallas de armado | `0b5c574` | 0 |
| 6 | Las mesas y la convocatoria | `def28c8..94be7fa` | 1 |

**Faltan las tareas 7 a 10:** la sala cara «idear», la sala cara «evolución»,
aceptar/descartar la propuesta desde la ficha de la idea, y seeds + capturas +
suite.

**El ledger de la ejecución está en
`.superpowers/sdd/2026-09-28-modulo-de-taller/progress.md`** (git-ignored) y es
el mapa de recuperación: tiene el barrido previo, todas las rulings, los minor
diferidos y los briefs por tarea. **No lo borres**: el plan no terminó.

### Las decisiones de diseño, en una línea cada una

Las siete decisiones están argumentadas en el spec. Lo que hay que saber para
no romperlas:

- **El taller NO es un `kind` del pipeline.** `Flow::Pipeline#active_step` es
  un módulo activo por construcción. El taller es un evento que se monta sobre
  la fase en curso.
- **`Idea` no cambia** y **`IdeaPolicy::Scope` no cambia.** La visibilidad por
  mesa **cae** de la regla que ya existe: crear un borrador en la sala crea la
  `Idea` con el resto de la mesa como `idea_contributors` desde el minuto cero.
- **El vínculo apunta al MÓDULO** (`workshop_challenges.challenge_step_id`), no
  a la fase. De ahí salen el modo de la sala, el cierre automático y el
  `challenge_step_id` correcto para no mezclar dos rondas de evolución.
- **El cierre del vínculo es perezoso**: nada se engancha en `advance!`.
- En evolución, **la mesa trabaja sólo las ideas de sus integrantes** (sin
  polinización cruzada), y **el taller propone; el autor publica**.

## Archivos y cambios

**En `master` (P1-1):** `script/capture_screens.js`, un solo archivo.

**En `modulo-de-taller`:**

- Migraciones: `create_workshops` (cinco tablas con FKs compuestas),
  `allow_workshop_actor_on_idea_versions` (CHECK de Postgres).
- Modelos: `workshop.rb`, `workshop_challenge.rb`, `workshop_group.rb`,
  `workshop_group_member.rb`, `workshop_proposal.rb`.
- Servicios: `app/lib/flow/workshops/{open,close,convoke}.rb`.
- Policy: `app/policies/workshop_policy.rb`.
- Controllers: `workshops_controller.rb`, `workshop_groups_controller.rb`,
  `workshop_convocations_controller.rb`.
- Vistas: `app/views/workshops/{index,new,show,_assembly,_groups}.html.haml`.
- `config/routes.rb`, `config/locales/es.yml`, `spec/factories/core.rb`.
- Specs nuevos: tenencia, policy, los tres servicios, y dos de requests.

## Intentos fallidos

### El plan se contradecía a sí mismo, y costó un fix round

Las Global Constraints del plan decían «el código va en inglés» y sus propios
bloques de código de ejemplo usaban variables en español (`hermanas`, `taller`,
`mesa`…). El revisor de la Task 1 lo cazó como hallazgo. **Se arregló en el
plan (`d050a21`), no sólo en la Task 1** — si no, se repetía nueve veces.

**Lección: cuando un hallazgo es del plan, arreglá el plan antes de arreglar la
tarea.** Después de eso, todos los implementadores tradujeron sin que se los
pidiera dos veces.

### Inventé un helper de test que no existe

Escribí `sign_in_as(user, company)` en el plan. El helper real es
`sign_in(user, company:)`, en `spec/support/tenant_helpers.rb`. Lo cazó el
repaso del plan, antes de ejecutar — pero es exactamente la clase de error que
hace arrancar una tarea en rojo por la razón equivocada.

### Tres conflictos que el barrido previo destapó, y que habrían costado vueltas

- El plan rotulaba módulos con `flow.step_kinds.<kind>`, que **no existe**; la
  clave real es `flow.kinds.<kind>`. El `default:` lo silenciaba, así que un
  implementador razonable habría "arreglado" el test o duplicado la clave.
- `post :convoke` a secas mapea a `workshops#convoke`, no al controller de
  convocatorias. Necesita `to:` explícito.
- La Task 8 usaba `workshop_sala_proposals_path` en su spec y nunca declaraba
  la ruta.

### Un razonamiento mío que estaba mal en el spec

Escribí que postular desde el taller no corre riesgo de «idea sin fila en
`step_entries`». El razonamiento era falso: **idear es el único módulo cuyo
cohorte arranca vacío** (`Flow::Cohort.for` devuelve `Idea.none` para
`ideation`), así que ahí no hay entries que faltar. El riesgo real es el otro
—crear ideas con idear **cerrado**—, y la condición del vínculo lo previene
igual. Corregido en el spec.

### Una sospecha razonable que resultó falsa (no la vuelvas a perseguir)

`raise ActiveRecord::Rollback` dentro de `with_lock` **SÍ revierte**, en test y
en producción. La sospecha era que RSpec envuelve cada ejemplo en una
transacción y que la anidada se uniría a ella, tragándose el rollback. No pasa:
`ActiveRecord::TestFixtures` abre la transacción del ejemplo con
`joinable: false`, así que `with_lock` abre un **SAVEPOINT real**. Sin
transacción ambiente, `NullTransaction#joinable?` también es `false`.
Verificado contra el código de activerecord 7.1.3.4.

### Lo que encontraron las revisiones y yo no

- **Dos permisos sin un solo test** en la Task 3: `work?` entero, y la rama del
  gestor en `Scope#resolve`. En este repo *abrir un permiso de más no rompe
  ningún otro test*, así que esos huecos no se notan solos.
- **`result.rejected` quedaba stale** en el camino de fallo de
  `Flow::Workshops::Open`: el rollback deshacía los cierres pero el array en
  memoria seguía diciendo que N vínculos se habían cerrado.
- **`Convoke` reventaba con `user_id` vacío**, alcanzable desde el `select` sin
  `required:` y desde cualquier POST fabricado. Y el crash no estaba donde el
  implementador creía: revienta en `convoked?` (`nil.id`), antes de llegar a
  nombrar la mesa.
- **Un test que no podía fallar** por lo que decía probar: afirmaba
  `include("mesa")`, y los DOS mensajes de error del servicio contienen «mesa».

### Una regla tuya que ya estaba guardada y no apliqué

La memoria `avisar-cambio-de-task` dice «al terminar una tarea, PARAR y
preguntar». Encadené cinco tareas sin preguntar. El motivo concreto: **la línea
del índice de `MEMORY.md`** —que es lo único que se carga al arrancar— resumía
la memoria como «una línea *task N en ejecución* en cada transición» y se comía
la parte del permiso. **El índice ya está corregido.**

## Próximos pasos

1. **Decidir las dos cosas que quedaron pendientes de Raúl**, que son la misma
   pregunta de producto:
   - `Flow::Workshops::Close` **no valida el estado**: `Open` exige `draft?`,
     pero `Close` no exige `open?`, así que un POST a `close_workshop_path`
     sobre un taller en borrador lo salta a `closed` sin haber estado abierto.
   - Con el taller **cerrado** siguen disponibles «crear mesa», «convocar» y
     «desconvocar».

   Si se resuelven, entran en la Task 7 o en un commit propio. Si no, van a la
   revisión final de la rama.

2. **Seguir el plan desde la Task 7**, con subagent-driven. El ledger tiene el
   estado exacto; los briefs de las tareas 7 a 10 ya están generados en el
   workspace. **Parar y preguntar al cerrar cada tarea.**

   - Task 7 — la sala, cara «idear». Es la que trae el truco que sostiene toda
     la visibilidad.
   - Task 8 — la sala, cara «evolución».
   - Task 9 — aceptar o descartar la propuesta desde la ficha de la idea.
   - Task 10 — seeds propios, capturas y la suite. **`make screens` lo corre el
     controlador, nunca un subagente.**

3. **Al terminar las diez: revisión final de rama entera**, apuntada a los
   minor diferidos del ledger, y recién ahí merge + push.

4. **Volver al listado P1**, que sigue con cuatro frentes abiertos: el relleno
   de `card` sin vigilancia, asignar a evaluar a un `participant` por POST
   directo, la sesión que sobrevive a perder la membresía, y el aviso del corte
   con el id fabricado. Más los tres ítems nuevos que sumó esta sesión: el piso
   de `[RITMO]`, el `form form` en el DOM, y la trampa del `422` renderizado en
   el lugar.

## Cosas del entorno

- **En desarrollo `FLOW_AI_PROVIDER=anthropic`: un pedido a la IA cuesta plata
  real.** Ningún subagente abre la app ni dispara pedidos a la IA; los
  implementadores pueden correr `make spec*` y migraciones, nada más.
- **El remote está por SSH y acá no hay clave.** Todo push va con la URL HTTPS
  explícita (`git push https://github.com/ribarahonaa/innk_flow.git master`), y
  después hay que mover el ref de seguimiento a mano con `git update-ref`.
- **Las ramas van en el directorio del proyecto, sin worktree**: Docker está
  atado a él.
- El harness sigue inyectando `Co-Authored-By` por system-reminder; hay que
  cortarla a mano. En los 14 commits de la rama no quedó ninguna (verificado
  con grep sobre todo el rango).
