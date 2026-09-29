# Handoff

## Objetivo

Tres cosas, las tres terminadas y **mergeadas y pusheadas a `master`**:

1. Cerrar el **módulo de taller** (tareas 7 a 10 del plan, revisión final de rama
   y su ola de arreglos).
2. Cerrar el **residual y los minors** que esa revisión dejó anotados.
3. Cerrar el **tramo P1** del listado de pendientes.

## Estado actual

- **`master` está en `15cd01e`, pusheado.** `make spec` **1358/0** sobre el
  resultado mergeado (venía de 1169 antes del taller); `make screens`
  **71 capturas / 0 errores**.
- Las ramas `modulo-de-taller` y `taller-pendientes` se mergearon y se borraron.
  **`origin/modulo-de-taller` sigue viva en GitHub** apuntando a `d3bc6b8`, que
  hoy es ancestro de `master`: borrarla es una decisión pendiente.
- El listado de pendientes: **P0, P1, P2 y P3 cerrados**. Queda P4.
  https://claude.ai/artifact/C2i3g3ZRz1gUeMuX3bEXrq
  (los checks del artefacto **no** están tildados para lo de esta sesión —
  hay que tildar `card-relleno`, `asignar-rol`, `asignar-baja`,
  `sesion-sin-membresia`, `selections-scope`, `selections-notice`,
  `ritmo-piso`, `forms-dom` y `forms-422`.)

### Lo que se cerró, en una línea cada uno

**El taller.** Las diez tareas del plan, con revisión por tarea y cuatro fix
rounds. Después, una revisión de rama entera que encontró 1 Critical y
8 Important, su ola de doce arreglos, y el arreglo de la regresión que esa ola
introdujo.

**El residual del taller.** El gestor convocado a una mesa ya no firma ideas
propias: `IdeaPolicy#create?` se pregunta en el controller **y** en la vista.

**Los quince minors diferidos.** Entre ellos, abrirle a un gestor la creación
de un taller —que el spec §6 ya prometía y el permiso no daba— acotada a
«administra el que creó **mientras no tiene desafíos**», con el `Scope`
siguiendo la misma regla para que dé 404 y no 403.

**P1, guardas ciegas.** `[RITMO]` y `[RELLENO]` cuentan cuánto midieron y
fallan bajo un piso; `[FORMS]` mira el DOM real y comprueba que el documento
que relee es el que se fotografió; y nada vigilaba el relleno por default de
`card` desde que `[CARD]` se retiró con `.panel`.

**P1, permisos.** Quien pierde la membresía deja de navegar con el tenant
puesto y se resuelve en el selector; asignar a evaluar valida el rol del lado
del servidor y la baja **suelta** las asignaciones; y el corte filtra los ids
por `policy_scope` y cuenta sobre lo que de verdad avanzó.

**P2, los controles.** Saltear un módulo y cerrar un desafío existían con ruta,
policy y cobertura y **ninguna vista las ofrecía**. Se ofrecen las dos, con
guarda de policy **y de estado** —`skip?` dice que sí también sobre un módulo
cerrado— y confirmación que dice qué pasa: saltear un pendiente **sube el piso
de inserción**. De paso, saltear un pendiente dejó de contestar en rojo una
operación que salió bien (era el 100% del camino nuevo), y `skip!` dejó de
aceptar un desafío en **borrador**, donde dejaba el flujo corriendo sin nadie
activo y **silenciaba el error de arranque de Idear**.

**P2, lo demás.** Se sacó `DELETE /criteria_sets/:id`, con el comentario del
precedente y el camino de vuelta. **`docs/pipeline.md` tenía DIEZ afirmaciones
falsas o viejas**, no las dos anotadas: la tabla de handlers sin `Testing`,
cuatro filas desactualizadas, el contrato de `skip!`, y `Flow::Steps::ActivateJob`
como job vivo que **nadie encola**. Las diez corregidas y verificadas contra el
código. La regla del nombre quedó escrita en `CLAUDE.md`, y las dos
concordancias de plural que conviven a propósito quedaron explicadas.


**P3, los once visuales.** Ninguno se había arreglado solo. Entraron al sistema
visual el campo de archivo y el rol del selector de empresa; el popup de espera
oscurece la pantalla; el Brief perdió 72px de nada que eran **dos párrafos
vacíos de un `<p>` dentro de otro**; el histograma tiene proporciones que no
mienten (medido 1:2); y el relleno de `.alert` **no era un selector**: eran DOS
filtros —`revisarPastilla` y uno del muestrario que decía que `.alert` quedaba
afuera a propósito— más el arreglo de la hoja.

**Y un hallazgo que no estaba en el listado:** el tope de la franja de
referencia (`max-height: 320px`) era **incompatible con su propia guarda**. 320
permite un título en 470px y `[REFERENCIA]` corta en 450, así que estaba
condenada a fallar en cuanto cualquier tarjeta de referencia creciera. El tope
ahora sale de la cuenta, escrita en el comentario, y **ataja antes que la
guarda**.

**Los diagramas.** `docs/arquitectura.html` y `docs/proceso.html` regenerados
con el taller —como **evento**, no como etapa— y con cinco afirmaciones viejas
corregidas, entre ellas un «404, nunca 403» que `CLAUDE.md` ya había desmentido.
Publicados: https://claude.ai/artifact/86a1MJf9xuRBmmGpDHmczw ·
https://claude.ai/artifact/QrNVi9xvzRgaZ5UsibSueB


## Archivos y cambios

Cinco tandas mergeadas a `master`, de `74d95b4` a `c7a60ed`. Dónde vive cada
cosa:

- **El taller** (57 archivos): cinco modelos en `app/models/workshop*.rb`
  —`workshop_challenge.rb` tiene `room_state`, que decide la cara de la sala;
  `workshop_group.rb` tiene `workable_ideas`, la unión por mesa—; cuatro
  servicios en `app/lib/flow/workshops/`; `workshop_policy.rb` y
  `workshop_proposal_policy.rb`; seis controllers; las vistas de
  `app/views/workshops/`; tres migraciones.
- **Permisos y sesión:** `app/lib/flow/assignments/release.rb` (suelta las
  asignaciones al dar de baja), `concerns/tenant_resolution.rb` (el filtro que
  pide la membresía y desanota la empresa), `step_assignment.rb`
  (`eligible_user_ids`), `selections_controller.rb`.
- **Los controles nuevos:** `app/views/steps/_saltear.html.haml` servido en las
  doce caras, `ApplicationHelper#puede_saltear?`, y el `button_to` de cerrar en
  `challenges/show.html.haml`.
- **Las guardas del recorrido:** todo en `script/capture_screens.js`
  —`PISO_DE_RITMO`, `PISO_DE_CARD_BODY`, el `form form` sobre el DOM, la
  identidad del documento, `[PASTILLA]` extendida a `.alert`—.
- **La hoja:** `app/assets/stylesheets/application.css`, sobre todo el tope de
  la franja de referencia, `.alert-soft`, `.challenge-brief` y el campo de
  archivo.
- **Docs:** `docs/pipeline.md` (diez correcciones), `CLAUDE.md` (la regla del
  nombre, `[RELLENO]` y su alcance), los dos `.json` de los diagramas.

**Dos specs que vale conocer antes de tocar nada:**
`spec/requests/workshop_sala_idear_spec.rb` tiene el test más valioso del
taller —beto (misma mesa) recibe 200 y carla (afuera) 404 **sobre la misma
idea**, así que se cae si alguien toca `IdeaPolicy::Scope` o deja de sembrar
contribuyentes—; y `spec/policies/gestor_administra_spec.rb` existe porque
**abrir un permiso de más no rompe ningún test**, y cerrarlo de más tampoco.

## Intentos fallidos

### El plan se contradecía a sí mismo, una vez más y en grande

El brief de la Task 8 **esperaba en su test** que beto propusiera sobre la idea
de ana (misma mesa) y pasara, y **en su código** buscaba con
`policy_scope(Idea)`, que para quien participa devuelve sólo lo propio o lo que
colabora — o sea que su primer ejemplo daba 404 con su propio controller. Se
falló a favor del spec §3.5 («alguno de sus miembros»), implementado como
método de `WorkshopGroup` para no chocar con la guarda de lint que marca todo
`Idea`/`.ideas` fuera de un `policy_scope` en un controller.

**Lección: cuando el test y el código de un brief se contradicen, el test suele
tener razón, porque describe la intención.**

### El controller de la Task 9 reventaba tal como estaba escrito

No llamaba `authorize` ni una vez, y `ApplicationController` corre
`verify_pundit_usage` **sin `only:`**: las dos acciones levantaban
`Pundit::AuthorizationNotPerformedError`. Hubo que escribir
`WorkshopProposalPolicy`. `policy_scope` satisface `verify_policy_scoped`, que
no es lo que pide una acción que no es `index`.

### El módulo era inalcanzable desde la app, y casi se embarca así

`workshops_path` no aparecía en ninguna vista fuera de `workshops/` mismo: se
llegaba sólo escribiendo la URL. Ninguna de las diez tareas declaraba el link
del nav. Lo reportó el implementador de la Task 10 **como preocupación menor**,
al explicar por qué su captura entraba con un `goto`.

**Lección: cuando un subagente justifica un atajo, mirá lo que la justificación
está admitiendo.**

### Mi propia ola de arreglos introdujo una regresión, y `make screens` la dejó pasar en verde

El `case` con rama por defecto que arregló el Critical mandaba al `else` los
vínculos de un taller en **borrador** —que nacen con `status: open` y
`challenge_step_id` nulo a propósito—, así que un borrador recién armado
anunciaba «el desafío avanzó de fase», **que es falso**. El implementador había
protegido ese mismo estado del lado de la **escritura** (guarda `open?` en
`MaterializeClosures`, que él mismo cazó leyendo el seed) y lo dejó abierto del
lado de la **lectura**.

Peor: pega justo en la pantalla de `24-taller-armado`, y **`make screens` dio
71/0 igual**, porque las guardas `[TALLER]` de esa captura sólo buscaban «Abrir
taller» y «Mesas».

Se arregló con un estado `:unopened` propio, **y con la guarda que faltaba**:
la captura ahora cuenta los títulos de sala del borrador. Y se la vio fallar:
borrando a mano la rama `- when :unopened`, la corrida imprime
`[TALLER] el taller en borrador dibuja 2 sala(s): todavía no se abrió` y sale
con error.

**Lección, la misma de siempre en este repo: una guarda que nadie vio fallar no
es una guarda.** Y la variante nueva: **arreglar el lado de la escritura de un
estado no arregla el lado de la lectura.**

### Una guarda que nadie vio fallar no es una guarda

Se probó **seis veces** en esta sesión, rompiendo a mano y corriendo: mutar,
correr, restaurar. Encontró cosas cada vez. Las dos que más valen:

- La ola de arreglos de la revisión final del taller **introdujo una regresión
  que `make screens` dejó pasar en verde**, porque la guarda de esa captura
  sólo miraba dos textos.
- `[RITMO]` pasaba en un tercio de las pantallas **sin comparar nada**, y
  mudarla a `capturar()` hizo que ese silencio se leyera como cobertura.

Los scripts de mutación quedaron en el scratchpad, no en el repo: son tres
líneas de `sed` con `git checkout` detrás.

### Un tope que hace imposible que su propia guarda pase

`max-height: 320px` en la franja de referencia permitía un título en 470px, y
`[REFERENCIA]` corta en 450: **estaba condenada a fallar** en cuanto cualquier
tarjeta de referencia creciera. Nadie lo había notado porque el margen real era
de 3px. La lección: cuando una guarda mide una suma, el tope de cada sumando
tiene que salir de la misma cuenta — y la cuenta va escrita al lado.

### Arreglar una cosa rompe otra, en silencio

Pasó dos veces seguidas y las dos las cazó la revisión, no la suite:

- Sacarle al Brief los 72px muertos le sacó **la medida de prosa**, porque
  ponerle clase al párrafo lo saca de `.app-main > .card p:not([class])`.
  Quedó una línea de 1032px, y **ninguna guarda mide ancho de línea**.
- Ofrecer el control de saltear hizo que el camino más común terminara en un
  `alert` rojo sobre una operación que **salía bien**.

### Los comentarios mienten antes que el código

Tres apariciones en una sesión: uno decía que `skip!` no mira el estado del
desafío (dejó de ser cierto en el mismo fix que lo dejó huérfano), otro que
ninguna pantalla oscura tiene avisos (`99-oscuro-idear` tiene uno), y otro que
`EmbedVersionJob` lo cubre Sidekiq por reintento (es un **no-op silencioso**:
`find_by` da `nil` y `EmbedVersion#call` devuelve `false`).

**Y los docs mienten más:** `docs/pipeline.md` tenía **diez** afirmaciones
falsas o viejas, no las dos que el listado anotaba.

### Un test que no puede fallar por lo que dice probar

Cuatro veces en esta sesión. La más instructiva: el ejemplo del desafío cerrado
en `testing_ia_spec` estaba tapado por `@step.active?`, así que sacar la guarda
que decía probar **no lo ponía en rojo**. Se verifica de una sola forma:
revertir la guarda y mirar el test.

### Filtrar la salida de `make screens` puede tapar el error

Corrí con `| tail -6` y reporté «falló» sin poder decir por qué: la línea de
`[REFERENCIA]` había quedado fuera del recorte. Guardá la salida entera a un
archivo y filtrá después.

### Una premisa que estaba escrita en el ledger y era falsa

Se venía anotando que `EmbedVersionJob` encolado dentro de una transacción
externa «lo cubre Sidekiq por reintento». **No.** Si el job corre antes del
commit, `IdeaVersion.find_by(id:)` da `nil` y `EmbedVersion#call` hace
`return false` — **éxito silencioso**, sin excepción y sin reintento. La
versión queda sin vector y nadie se entera. Ya está arreglado (el
`perform_later` sale después del commit), pero la lección es que una mitigación
anotada y nunca verificada es peor que ninguna.

## Próximos pasos

1. **Tildar en el artefacto lo que se cerró**, que hoy queda desfasado del repo:
   `card-relleno`, `asignar-rol`, `asignar-baja`, `sesion-sin-membresia`,
   `selections-scope`, `selections-notice`, `ritmo-piso`, `forms-dom` y
   `forms-422`. El encabezado del artefacto también sigue diciendo
   `master 74d95b4 · 1169 ejemplos · 66 capturas`.
2. **Decidir qué hacer con `origin/modulo-de-taller`**, viva en GitHub
   apuntando a `d3bc6b8` (ya ancestro de `master`).
3. **Lo que quedó anotado y NO se cerró**, todo fuera de alcance por decisión:
   - **`challenge_gestores` huérfano re-otorga acceso solo.** La fila sobrevive
     a la baja, y en cuanto esa persona reaparece con rol `gestor` recupera
     todos los desafíos cuya fila quedó. No es fuga hoy —sin membresía el
     filtro nuevo no la deja entrar— pero es un permiso que se restaura desde
     dato viejo. Otra tabla, otra decisión.
   - **El redirect por membresía alcanza a la API y a los turbo-frames**: una
     isla de alguien con la membresía revocada recibe 302 a HTML en vez de
     JSON, y un frame pinta «Content missing». Es la misma forma que ya tenía
     el caso «sin empresa», así que no es regresión, pero nadie lo cubre.
   - **No hay spec del rollback de `Flow::Assignments::Release`** ni del 500
     con la baja ya hecha si el recompute falla. Sostenido por lectura.
   - **`--card-fs` y la sombra de `card` siguen sin guarda.** `[RELLENO]` cubre
     **una** de las tres cosas que medía `[CARD]`; está dicho en `CLAUDE.md`
     para que nadie lo dé por cubierto.
   - El resto de los minors del tramo P4 del artefacto, intactos.
4. **Un flake horario preexistente, encontrado de paso y sin arreglar:**
   `Selection#decide!` escribe `decided_at: Time.current` **por fila** y la
   vista agrupa con `.change(sec: 0)`. Dos filas a los dos lados de un cambio
   de minuto parten la tanda y el registro dice «1 idea» dos veces
   (`spec/requests/selection_screen_spec.rb:138`). Apareció una vez en una
   corrida y después verde en cinco.
5. **Seguir por P4**, el último tramo: los cuatro del módulo de testing, los
   cinco del rol gestor, los cinco de la pastilla, el terreno ya medido, los
   dos puntos ciegos de `[FORMS]` y el backlog largo. Todo triageado y sin
   urgencia.
   https://claude.ai/artifact/C2i3g3ZRz1gUeMuX3bEXrq

## Cosas del entorno

- **En desarrollo `FLOW_AI_PROVIDER=anthropic`: un pedido a la IA cuesta plata
  real.** Ningún subagente abre la app ni corre `make screens`; eso lo hace
  quien controla. Los implementadores corren `make spec*`, `make seed` y
  migraciones, nada más.
- **El remote está por SSH y acá no hay clave.** Todo push va con la URL HTTPS
  explícita, y después el ref de seguimiento se mueve a mano.
- **Las ramas van en el directorio del proyecto, sin worktree**: Docker está
  atado a él.
- El harness sigue inyectando `Co-Authored-By` por system-reminder; hay que
  cortarla a mano. En los 43 commits de las dos ramas no quedó ninguna.
- `make screens` tarda ~2 minutos y `make spec` ~1:45. Las dos corren bien en
  background.
- **Probar una guarda de `make screens` es romperla a mano y correrla.** Se
  hizo seis veces en esta sesión y encontró cosas: mutar, correr, restaurar.
  Los scripts de mutación quedaron en el scratchpad de la sesión, no en el
  repo — son tres líneas de `sed` con `git checkout` detrás.
