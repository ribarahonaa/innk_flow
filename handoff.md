# Handoff

## Objetivo

Tres cosas, las tres terminadas y **mergeadas y pusheadas a `master`**:

1. Cerrar el **módulo de taller** (tareas 7 a 10 del plan, revisión final de rama
   y su ola de arreglos).
2. Cerrar el **residual y los minors** que esa revisión dejó anotados.
3. Cerrar el **tramo P1** del listado de pendientes.

## Estado actual

- **`master` está en `a6c4593`, pusheado.** `make spec` **1343/0** sobre el
  resultado mergeado (venía de 1169 antes del taller); `make screens`
  **71 capturas / 0 errores**.
- Las ramas `modulo-de-taller` y `taller-pendientes` se mergearon y se borraron.
  **`origin/modulo-de-taller` sigue viva en GitHub** apuntando a `d3bc6b8`, que
  hoy es ancestro de `master`: borrarla es una decisión pendiente.
- El listado de pendientes: **P0 cerrado, P1 cerrado**.
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

## Archivos y cambios

57 archivos, +6328/−223. Lo que hay que saber para moverse:

- **Modelos:** `workshop.rb`, `workshop_challenge.rb` (tiene `room_state`, que
  es quien decide la cara de la sala), `workshop_group.rb` (`workable_ideas`,
  la unión por mesa), `workshop_group_member.rb`, `workshop_proposal.rb`.
- **Servicios:** `app/lib/flow/workshops/{open,close,convoke,materialize_closures}.rb`.
- **Policies:** `workshop_policy.rb`, `workshop_proposal_policy.rb`.
- **Controllers:** seis, más `ideas_controller.rb` tocado para publicar
  `@workshop_proposals`.
- **Vistas:** `workshops/{index,new,show,_assembly,_groups,_sala_idear,_sala_evolucion}`,
  `shared/_workshop_proposal`, el link «Talleres» en el layout, y
  `ideas/_form_fields` con un `id_prefix` opcional.
- **Migraciones:** `create_workshops`, `allow_workshop_actor_on_idea_versions`,
  `add_workshop_to_group_members`. `db/structure.sql` commiteado.
- **Specs nuevos:** trece archivos. `spec/requests/workshop_sala_idear_spec.rb`
  tiene el test más valioso de la rama: beto (misma mesa) recibe 200 y carla
  (afuera) 404 **sobre la misma idea**, así que se cae si alguien toca
  `IdeaPolicy::Scope` o deja de sembrar contribuyentes.

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
4. **Seguir por P2**, que son cuatro decisiones tuyas listas para ejecutarse
   (la convención nueva en `CLAUDE.md`, `docs/pipeline.md`, los dos controles
   de dominio sin vista, y para qué existe `DELETE /criteria_sets/:id`), y
   después P3 y P4.
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
