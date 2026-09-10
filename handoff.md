# Handoff

## Objetivo

Que configurar un módulo pase a ocurrir en **un solo lugar**: la pantalla del
módulo, con dos caras —`step.touched?` decide si se configura o si se trabaja
sobre la configuración ya congelada—. Antes estaba repartido en seis pantallas
y ninguna era la del módulo. El detalle de cómo quedó armado ya está en
`CLAUDE.md` (sección del pipeline, de las islas y del sistema visual) y en
`docs/criteria.md`; este archivo no lo repite.

## Estado actual

**Rama terminada, revisada, mergeada y pusheada.** Las 13 tareas del plan (más
la Task 14, insertada por decisión del usuario) están cerradas, cada una con su
revisión y su ronda de arreglos. Corrió además una revisión amplia de toda la
rama, con una única ola de arreglos y su re-revisión, ya aplicada.

Cerrada con `superpowers:finishing-a-development-branch`: merge fast-forward a
`rediseno-tailwind`, suite y capturas verificadas **sobre el resultado
mergeado**, y `configurar-vs-ejecutar` borrada con `-d` (sin forzar) una vez
contenida en la base y pusheada. Local y `origin` quedaron 0/0.

Después del merge se sumó un commit que la rama no había tocado: **los dos
diagramas de `docs/` estaban viejos** y ninguna tarea del plan los tenía en su
lista de archivos. Se corrigieron tres hechos —las islas Vue son cuatro y no
tres; lo ajustable con el módulo en curso son tres cosas y no dos (nombre, modo
de IA y asignaciones); «Formulario y criterios» figuraba como etapa aparte del
recorrido, que es justo el reparto en pantallas sueltas que esta rama
eliminó— y se regeneraron los dos HTML con archify (showcase, 9/9 checks, cero
warnings). Al hacerlo se pegó contra la trampa que `CLAUDE.md` documenta
(`composition/desktop-readability` a 1440px): se resolvió ensanchando el nodo de
170 a 200 —el ancho que ya tenían los otros ocho— y recién después acortando
«formulario» a «campos».

- `make spec`: **756 ejemplos, 0 fallas, 0 pending.**
- `make screens`: **35 capturas.**
- `make yarn-build`: limpio.
- `git log --oneline 9b7b10f..HEAD`: 34 commits (`9b7b10f` es el punto de
  partida sobre `rediseno-tailwind`).

Este handoff **no corrió `make spec` ni `make screens`** — es un archivo
Markdown, esos números son los que dejó la revisión final documentada en el
ledger (ya borrado).

Próximo paso literal: `superpowers:finishing-a-development-branch`.

**Dos hechos del entorno que conviene saber antes de tocar nada:**

- `gestor@demo.test` está sembrado como **admin**, no como gestor
  (`db/seeds.rb:38`). La lista de cuentas de demo es engañosa en ese punto:
  preexistente, no lo introdujo esta rama.
- `CLAUDE.md` documenta «los controllers devuelven 404, nunca 403», pero un
  `authorize` de Pundit rechazado renderiza **403**
  (`app/controllers/concerns/tenant_resolution.rb:18,70`). Es la premisa
  entera de la clase de defecto que esta rama encontró y resolvió cuatro
  veces —una isla o un botón que se sirve a quien no puede usarlo y rebota
  403 al apretar—: dos veces ya embarcada en el código y corregida en su
  ronda de arreglos (Task 5, Task 6), dos veces prevenida antes de escribir
  código (Task 7, Task 8). Sigue abierta; no se decidió cambiar el código
  ni la doc.

**Decisiones «dejar así» de la revisión final** (no son bugs, no tienen acción
pendiente, pero si alguien las redescubre no hace falta que las vuelva a
juzgar):

- El botón «Volver» del editor de criterios y del de campos navega a la
  pantalla donde ya está, cuando `back` apunta a sí mismo. Dos instancias de
  una sola decisión sin tomar: sacar el botón o apuntarlo al builder.
- `api/v1/form_fields_controller.rb#serialize` duplica `form_field_json`
  (extraído a `form_fields_helper.rb` en Task 7) con internals distintos
  (`config["is_title"]` vs `title?`). Hoy inerte: la isla sólo reasigna
  `body.fields`.
- `_criterios_editor.html.haml:98` usa `criterion.summary` en la rama de
  sólo lectura, que para un criterio `formula` imprime la expresión literal.
  La vista análoga de la cara congelada sólo muestra un chip «derivado».
- En un desafío **cerrado** con un módulo de evaluación pendiente,
  `manage_assignments?` no mira `closed?` y sigue ofreciendo el bloque de
  asignaciones, mientras `configure?` ya deja `config/_modulo` de sólo
  lectura en la misma pantalla. Cada control coincide con su propio
  controller, así que nada rebota; es asimetría, no bug, y era alcanzable
  desde antes de esta rama.
- El índice `/challenges/:id/criteria` (`challenge_criteria`) se borró por
  decisión explícita del plan. Se perdió la única pantalla que mostraba los
  criterios de TODOS los módulos que puntúan a la vez, de un vistazo. Nadie
  la reconstruyó en otro lado; es una pérdida de producto aceptada, no un
  olvido.

**Una escritura en la base de desarrollo:** el desafío `sin-formulario` pasó
de 2 a 5 `ChallengeStep` (los cinco `kind` pendientes) más 1 `CriteriaSet`
inline en el módulo de selección, para que `make screens` tenga las cinco
caras de configuración que fotografiar. Es idempotente, aditiva, y
**`db/seeds.rb` ya la reproduce** (línea ~372 en adelante): una base nueva
sembrada da lo mismo sin ningún paso manual. No se tocó `onboarding-remoto` ni
`optimizacion-de-la-experiencia-de-onboarding` (datos reales del usuario) ni
`merma-bodega`.

## Archivos y cambios

`git diff --stat 9b7b10f..HEAD`: 69 archivos, +3293/−1116. La arquitectura que
resultó ya está en `CLAUDE.md`; acá sólo la ubicación de lo tocado, para no
tener que releer 34 commits:

- **Escritura de configuración:** `app/controllers/steps_controller.rb`
  (`show` despacha por cara, `update` autoriza según lo que llega),
  `app/policies/challenge_step_policy.rb` (`configure?`),
  `app/lib/flow/step_settings.rb` (`filtrar`/`fields`/`write`/`defaults`),
  `app/models/challenge_step.rb` (`FROZEN_ATTRIBUTES` con
  `criteria_set_id`).
- **El builder deja de escribir configuración:**
  `app/controllers/api/v1/pipelines_controller.rb`,
  `app/presenters/pipeline_presenter.rb` (barrido de props muertas en la
  ola final), `app/javascript/components/pipeline_builder/`
  (`step_config.vue` se borró entero).
- **La isla nueva:** `app/javascript/components/step_settings/`,
  `app/presenters/step_settings_presenter.rb`.
- **Las cinco vistas de configuración y los partials embebidos:**
  `app/views/steps/config/` (shell + las cinco), `app/views/steps/_modulo`,
  `app/views/steps/_config_congelada.html.haml` (resumen congelado, ahora
  con defaults + `depends_on`), `app/views/steps/_criterios_editor.html.haml`
  (editor de criterios + los dos controles de biblioteca restaurados en la
  ola final), `app/views/steps/_campos_editor.html.haml`,
  `app/views/steps/_asignaciones_evaluadores.html.haml`,
  `app/views/steps/_asignaciones_gestores.html.haml`.
- **Pantallas y controllers borrados** (URLs redirigen, no 404):
  `challenge_criteria_controller.rb` + su vista, `form_fields_controller.rb`
  reescrito a puro redirect, `step_criteria_controller.rb` idem,
  `config/routes.rb` sin `/challenges/:id/criteria`.
- **Verificación:** `spec/requests/dos_caras_spec.rb` (nuevo, 593 líneas —
  las dos caras de los cinco kinds), `spec/requests/step_config_spec.rb`,
  `spec/lint/una_vista_de_configuracion_spec.rb` (guarda de isla única),
  `script/capture_screens.js` (+261/−neto, recorrido por las dos caras).
- **Documentación:** `CLAUDE.md` (+171), `docs/criteria.md`,
  `docs/superpowers/specs/2026-09-09-configurar-vs-ejecutar-design.md`.

**La ola de arreglos final** (commit `d006fcb`, base `1e3bd75`, 15 archivos)
restauró tres cosas que el borrado del panel del builder se había llevado sin
que nadie lo pidiera:

1. Los dos controles de biblioteca (elegir un set compartido, pasar a la
   versión siguiente) — hoy viven en `_criterios_editor.html.haml`, escriben
   por el mismo `PATCH steps#update` de siempre, y sólo aparecen si el módulo
   **no** tiene ya un set `inline` propio.
2. `_config_congelada` deja de servir una tarjeta vacía cuando `config` tiene
   huecos (las plantillas y el seed no llenan todas las claves): ahora
   renderiza con `Flow::StepSettings.defaults` y respeta `depends_on`.
3. Se podó el payload muerto del builder (6.4 KB de 10.4 KB sin consumidor:
   `criteria_json`, `form_json`, `settingsSchema`, `criteriaSets`, y media
   docena de claves más) y se borró `update_existing`, que había quedado como
   no-op.

## Intentos fallidos

**Defectos de brief que la revisión atrapó antes de que llegaran a código**
(la próxima sesión no tiene por qué volver a chocar con ellos si alguna vez
retoma un plan parecido):

1. **Un test que afirmaba un string del bloque equivocado.** El brief de
   Task 8 mandaba un test con `include("Elegí a quién sumar")` sobre la cara
   de **evaluación**; ese string sólo existe en el bloque de **gestores**
   (`challenges/_gestores.html.haml:33`). El form de evaluadores dice
   `include_blank: "Sumar a alguien…"` + `submit_tag "Asignar"`. Escrito tal
   cual, el test fallaba para siempre — o alguien lo hacía pasar cambiando la
   copy del producto para calzar con el typo del plan. Se corrigió contra los
   marcadores reales de cada bloque (Ruling 25).
2. **Un paso del brief dejaba el paso a paso en loop.** Task 9 mandaba
   `criteria_step.path = builder_challenge_path`. Con criterios pendiente, el
   pie de «formulario» ofrecía «Los criterios →» hacia el builder, cuyo pie
   ofrecía «El formulario →» de vuelta: sin salida hacia «Revisar». La regla
   correcta —la que el propio plan ya usaba tres líneas más arriba para
   `form_step`— es apuntar a la cara de configuración del primer módulo que
   puntúa, y al builder sólo si no hay ninguno (Ruling 32).
3. **Un selector que no existe, así que el loop no iteraba nunca.** El brief
   de Task 11 pedía `$$eval('.step-card__config', …)`; esa clase no existe
   desde Task 5 (la tarjeta entera es `.step-card__link`). El `for` recorría
   un array vacío, la tarea agregaba CERO capturas nuevas y `make screens`
   seguía en verde — el peor defecto posible en una tarea de verificación,
   porque parece que funcionó (Ruling 40).
4. **Una guarda que sólo reconocía una de las dos formas idiomáticas.** La
   guarda de isla única (Task 10) matcheaba el literal
   `data-island": "<isla>"`, pero `%div{ data: { island: "form-editor" } }`
   —Rails renderiza igual ese hash a `data-island`— declara la misma isla y
   no lo detectaba. Se corrigió con un regex que cubre las dos formas, y la
   primera versión del regex introdujo un falso positivo propio (cuantificador
   perezoso sin acotar, cruzaba la llave de un `data:` ajeno) que la
   re-revisión reprodujo por ejecución antes de aceptarlo (Ruling 37, 39, T10
   fix round 1).

**Lo que la suite no ve, medido a lo largo de toda la rama** (make spec y
make screens quedaban en verde con el defecto adentro, en los cinco casos):
un `<form>` anidado, un control servido a alguien que no puede usarlo y
rebota 403 al apretar, una clase que Tailwind nunca escaneó, un paso del
recorrido sin «siguiente →», y una tarjeta que anuncia «Cómo quedó
configurado» y no muestra ninguna fila. Los cinco se encontraron pidiendo el
HTML servido o midiendo en un navegador real, nunca leyendo el diff.

**Una mutación que borra dos líneas a la vez sólo prueba que UNA es
load-bearing.** En Task 9 el implementador sacó con un solo `sed` las dos
líneas de `setup_nav` (evaluación y selección) para probar la guarda por
mutación; verde-tras-restaurar sólo demostraba que al menos una de las dos
importaba. `config/selection.html.haml:6` no la cubría nada. Hubo que correr
las dos mutaciones por separado.

**Código escrito y borrado en la misma tarea:** `campos_de` y `escribir` en
`Flow::StepSettings` (Task 1) — duplicaban exactamente a `fields` y `write`,
que ya existían y ya usaba `defaults`. Ganaron los nombres viejos.

**Proceso, no código:** `git add -A` con un subagente escribiendo en el mismo
árbol se llevó puesto el archivo de test de otro proceso una vez, al
principio de esta rama (documentado en el `handoff.md` anterior). Desde
entonces, todo commit de esta ejecución fue por ruta explícita — están todas
las tareas de Task 7 en adelante con esa nota repetida a propósito. Y dos
implementadores en paralelo no funciona: comparten árbol de trabajo y varias
tareas escriben `script/capture_screens.js`.

## Próximos pasos

1. **Dos restos de limpieza, ninguno bloqueante:**
   - `origin/configurar-vs-ejecutar` sigue viva en GitHub. Todos sus commits
     están contenidos en `rediseno-tailwind` y pusheados, así que borrarla no
     pierde nada: `git push origin --delete configurar-vs-ejecutar`.
   - El workspace del SDD (`.superpowers/sdd/2026-09-09-configurar-vs-ejecutar/`,
     gitignored) quedó en disco con el ledger y los 14 reportes de tarea. Todo
     lo que había que conservar de ahí está en este archivo; se puede borrar.
2. **Cuatro minors, parkeados sin segunda ola por regla del proceso** (una
   ola de arreglos por revisión final, ya usada):
   - `app/lib/flow/step_settings.rb:206-213` — el comentario dice que las
     claves peligrosas «viven en `resolved_config`, que `filtrar` no toca
     nunca», pero la lectura vulnerable de verdad es `step.config`
     (`app/lib/flow/selection.rb:262,294`). La conclusión del comentario es
     correcta (nadie las pone hoy en `config`); el mecanismo que describe,
     no. Corregir sólo el texto.
   - `app/views/steps/_criterios_editor.html.haml:85-87` — justifica el
     `id: "asignar-set-de-biblioteca"` explícito diciendo que `form_with`
     generaría el mismo id que el de `_modulo`. Rails 7.1 no autogenera id de
     form; el `id:` sigue siendo necesario (dos `form_with` en la misma
     pantalla) pero el motivo escrito es falso. Corregir sólo el texto.
   - `app/presenters/pipeline_presenter.rb` — quedaron `slug` y `removable`
     sin consumidor en `app/javascript` (además de `insertionFloor`, que el
     propio implementador de la ola final ya se auto-marcó). Barrido
     pendiente, mismo criterio que ya se aplicó al resto del payload muerto.
   - **Regla de producto sin documentar en ningún lado que sobreviva:** los
     dos controles de biblioteca (elegir set, pasar de versión) desaparecen
     en cuanto el módulo tiene su propio set `inline` — no hay camino de
     vuelta de criterios propios a la biblioteca. Es paridad exacta con el
     panel que se borró (no es regresión de esta rama), pero hoy sólo estaba
     escrito en un reporte que se borra junto con el ledger. Si se documenta,
     va junto a la explicación de versionado de biblioteca en `CLAUDE.md`.
3. **Dos ramas de seguimiento, deliberadamente separadas de ésta:**
   - `shared/_ai_suggestions` emite los `button_to` de Aplicar/Descartar
     **sin ninguna guarda de permiso**, en siete pantallas (las cinco caras
     de ejecución más `challenges/show` e `ideas/show`). Es la misma clase de
     defecto que esta rama resolvió cuatro veces dentro de sus propios
     partials nuevos, pero acá es preexistente y más ancho: arreglarlo exige
     auditar cada sitio de render y qué `purpose` de `AiSuggestionPolicy`
     corresponde a cada uno, no una guarda de una línea.
   - `Flow::AI::Tasks::ProposePipeline#apply!` (`propose_pipeline.rb:61`)
     escribe el `config` que devuelve el modelo **sin pasarlo por
     `Flow::StepSettings.filtrar`**, bajo un JSON Schema
     (`{"type" => "object"}`) que no restringe propiedades. Es un escritor de
     jsonb arbitrario alimentado por un LLM — el mismo agujero que Task 1
     cerró del lado HTTP (`permit(config: {})` → filtro de esquema). No se
     tocó porque esta rama nunca abrió ese archivo.
4. **Una nota de limpieza aparte, menor y también fuera de esta rama:** seis
   controllers usan `status: :unprocessable_entity`, deprecado en Rails 7.1 a
   favor de `:unprocessable_content` (`assessments`, `api/v1/base`, `ideas`
   ×2, `sessions`, `challenges`). Preexistente, ajeno al diff de esta rama,
   ensucia la salida de la suite con warnings.
