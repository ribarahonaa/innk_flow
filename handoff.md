# Handoff

## Objetivo

El punto 1 del handoff anterior: las dos guardas que salieron del repaso de
capturas, que son lo único de esa lista con consecuencia sobre datos. Que la
IA no siga trabajando sobre un módulo cerrado, y que nadie pueda sacarse a sí
mismo de la empresa.

## Estado actual

- **`master` está en `ebffd85` y pusheado.** Verificado contra el remoto con
  `gh api`, no con `git rev-parse origin/master` —que lee una foto local—. El
  merge fue local por decisión de Raúl y el push lo hizo él. Sin ramas vivas.

  Si hiciera falta pushear desde acá, el remoto es SSH y en este entorno no
  autentica; lo que funciona sin tocar la config global ni exponer el token:

  ```bash
  git -c credential.helper='!gh auth git-credential' \
      push https://github.com/ribarahonaa/innk_flow.git master
  ```

- **`make spec` → 1105 ejemplos, 0 fallas** (venía de 1092: +13 nuevos), y
  **`make screens` → 66 capturas, 0 errores**, los dos corridos sobre el
  RESULTADO DEL MERGE y no sólo sobre la rama.
- La rama `guardas-de-modulo-abierto-y-autobaja` se borró al mergear.
- El stack quedó levantado. La base no se tocó.

### Decisiones de Raúl en esta sesión

- **Arrancar por el punto 1**, las dos guardas juntas y en rama propia.
- **`summarize_challenge` entra** en la lista de tareas que exigen módulo
  abierto (era la única que quedaba en duda al aprobar el diseño).
- **Mergear a master localmente**, sin PR. El push lo hizo Raúl después, a
  mano.

## Archivos y cambios

### `fa697ea` · La IA no trabaja sobre un módulo cerrado

**Lo primero que hay que saber es que el handoff anterior se equivocaba.**
Decía «no hay ninguna guarda de estado, ni en el partial ni en ningún
llamador». Falso: de los ocho llamadores de `shared/_ai_actions`, cuatro la
tenían escrita a mano —`selection:40`, `evaluation:33`, `testing:78`,
`ideas/show:100`—. O sea que el problema no era una guarda ausente sino **la
misma regla repetida en cada llamador, donde dos se la olvidaron**.

Los huecos reales eran dos, y son las dos pantallas que se vieron en las
capturas: `ideation:28` (`generate_ideas`, el grave: crea ideas y las postula,
y `Flow::Cohort.sync!` ya armó las `step_entries`, así que quedan sin fila) y
`evolution:16` (`suggest_feedback`, que archiva el comentario con su
`challenge_step_id` dentro de una ronda cerrada). Un tercero marginal en
`reporting:41,55`, casi siempre tapado porque completar el último módulo
cierra el desafío (`pipeline.rb:233`) y `update_pipeline?` exige `!closed?`.

La regla ahora la declara la tarea —`requires_active_step?`, hermana de
`actua_sobre`— y la resuelve `Flow::AI::Tasks::Base.step_ready?(purpose,
step)`. **Tres puertas la consultan**, que es el mismo patrón que la regla de
evaluación: el partial (un lugar, así que el próximo llamador no se la puede
olvidar), `AiSuggestionPolicy#accept?` —que al ser también `request?` cubre el
pedido Y el aceptar tardío de una propuesta pendiente— y
`StepsController#evaluate_all`, que no pasa por el partial.

En `true`: `generate_ideas`, `suggest_feedback`, `decide_verdicts`,
`evaluate_idea`, `test_idea`, `summarize_challenge`. En `false` (el default,
que es el lado seguro): las tres de autoría, `detect_duplicates` —sólo lee— y
`evolve_idea`, que se explica abajo.

**Consecuencia asumida:** una propuesta pendiente sobre un módulo que acaba de
cerrar desaparece del panel, porque `shared/_ai_suggestions` filtra por
`accept?`. Es el mismo comportamiento que ya producía un desafío cerrado.

### `92d66b5` · Nadie se saca a sí mismo de la empresa

`quita_al_ultimo_admin?` guarda contra quedarse sin nadie que administre, no
contra sacarse uno mismo: con otro admin en la empresa, «Sacar» sobre la
propia fila funcionaba. Guarda hermana de la que `ChallengeGestoresController
#destroy` ya tenía un nivel más abajo, y la vista esconde el botón en la
propia fila como `challenges/_gestores`.

**Cambiarse el propio ROL no entra**, a propósito: es recuperable por otro
admin, y lo que de verdad no debe pasar ya lo ataja la guarda del último
admin.

## Intentos fallidos

**El diseño aprobado tenía una tarea de más, y no lo descubrió la suite: lo
descubrió grepear los specs existentes ANTES de escribir código.** El diseño
incluía `evolve_idea`, y `spec/requests/gestor_spec.rb:409` afirma
explícitamente lo contrario —«y también con la ronda cerrada»— con un
comentario que dice que es la decisión del rol gestor: desde que el gestor
administra el desafío, trabajar la idea no depende de que haya una ronda en
curso. Si lo hubiera implementado primero, la suite habría fallado y el
reflejo es «arreglar el test», que ahí habría sido revertir una decisión en
silencio. La ventana de la ronda ya vive donde corresponde
(`IdeaPolicy#update?`: `draft? || evolution_open?`, con `administers?`
exento).

**`make screens` estaba FIJANDO el bug.** El chequeo del selector de cantidad
(`[IA] el selector de cantidad no ofrece 1..5`) miraba el módulo de idear de
`merma-bodega`, donde el flujo corre entero y por lo tanto está cerrado: o
sea, exigía que el botón siguiera ofrecido justo en la pantalla donde el
handoff había visto el bug. Pasó a `recorrido-ia`, que existe sólo para el
recorrido y tiene idear abierto. **Sacar un bug puede poner en rojo un test
que lo afirmaba, y eso no es una regresión** — pero hay que mirar cada falla
antes de decidir eso, no asumirlo.

**Y `panel_de_propuestas_spec.rb` se acoplaba a un setup que no le
correspondía:** un `before` de arriba hacía `pipeline.advance!` para abrir la
evolución —lo necesitaba un solo describe, el de la ficha de la idea— y de
paso cerraba la ideación, que era la pantalla que otro describe fotografiaba.
Bajó al describe que lo usa; ninguna aserción cambió.

**Lo que sí funcionó, y conviene repetir:** romper cada guarda a mano y
confirmar que falla **sólo** lo nuevo. Las cinco están cubiertas de a una
—vista de IA: 2 ejemplos; policy: 3; `evaluate_all`: 1; controller de
miembros: 1; vista de miembros: 1— y la polaridad del `unless` de la vista
también (invertirlo pone en rojo el ejemplo, así que no pasa con el botón
escondido para todos).

**Una desviación del proceso, deliberada:** no se usó worktree. El stack de
Docker está atado a `/home/ribarahonaa/innk_flow`, así que `make spec` desde
un worktree correría contra otro compose. Rama en el lugar.

## Próximos pasos

1. **Lo que queda del handoff anterior, sin tocar.** Ninguno es bloqueante:
   - **Los menores diferidos del rol gestor**: la variable local muerta
     (`- desafio = step.challenge`) en `_referencia_evaluacion.html.haml:8`;
     `AssessmentPolicy#update?` sin cobertura y sin llamador vivo;
     `CriteriaSetPolicy#update?` con `owner_step: nil` sin cobertura (no se
     alcanza y falla cerrado); «Ver el set» sin test de polaridad propio; la
     tabla de `gestor_administra_spec.rb` sin columna de `participant` ni
     `evaluator`.
   - **Dos rastros del renombre dejados a propósito** (no son deuda):
     `gestor_administra_spec.rb` conserva el nombre aunque prueba
     `administers?`, y la spec y el plan en `docs/superpowers/` siguen
     diciendo `administra?` porque son documentos históricos.
   - **La «fuga» de `CriteriaSetPolicy::Scope` NO existe: descartada con
     evidencia, no la vuelvas a abrir.** El handoff anterior decía que un
     participante abre por id un set `inline` «de un desafío que no ve». Esa
     premisa es falsa: `ChallengePolicy::Scope` devuelve TODOS los desafíos a
     quien no es gestor (`application_policy.rb:40`, `reaches_challenge?`
     sale por `true unless gestor?`), que es el producto —cualquiera de la
     empresa ve los desafíos— y además ya veía esos mismos criterios en
     `steps/_referencia_evaluacion.html.haml:14-32`. Medido por rol sobre un
     set `inline`: participante 200, evaluador 200, admin 200, **gestor no
     asignado 404** en la URL del set y 404 en la pantalla del módulo. O sea
     que el único rol donde la premisa se sostenía ya está cerrado, y el ítem
     venía de antes de ese arreglo.

     Lo único que queda de ahí es una nota defensiva, no un bug: el `Scope`
     sale por `return scope.all unless gestor?`, así que **un rol nuevo
     nacería abierto**. Derivarlo de `ChallengePolicy::Scope` para todos lo
     haría correcto por construcción y hoy es un no-op. No se hizo: es
     cambiar código que funciona por una hipótesis.
   - **Un preexistente que sigue en pie:** el breadcrumb de
     `criteria_sets/edit.html.haml` siempre enlaza a `criteria_sets_path`,
     que sólo lista biblioteca, así que para un set `inline` la vuelta va a
     una lista que nunca lo muestra. No verificado en esta sesión.

2. **Las 45 capturas que todavía no se miraron.** De las 21 miradas, lo visual
   pendiente sigue igual y está listado entero en el handoff anterior
   (`git show 794205a:handoff.md`): la previsualización repetida en 5 de 7
   tarjetas, el popup de la IA que dice lo mismo tres veces, el desglose que
   muestra claves en vez de nombres, el drawer que se corta, el hueco muerto
   de «Brief», «En curso» sin badge, las filas de «Cómo quedó configurado» que
   se encabalgan, los separadores colgando, la columna «Acción» que apila, el
   «3 / 2», «Armar el flujo con IA» sin controles, el embudo en gris plano,
   «Distribución de puntajes» con dos filas de números y «Quién evalúa»
   duplicado sin el peso.

3. **Y el resto del backlog largo**, también intacto: `Pipeline#validate` vs
   `Selection#can_activate?`; las once FKs con `ON DELETE SET NULL` sin
   acotador; `[FORMS]` que no cubre las pantallas a las que se llega por clic;
   los cuatro menores del módulo de testing; el plan 2c (el resto de las islas
   Vue), `SelectionsController#update` sin validación server-side,
   `criteria_sets#show` huérfana, las 3 consultas de evolución, los tres temas
   de seguridad preexistentes, y que nada vigila el relleno por default de
   `card` desde que se retiró `[CARD]`.
