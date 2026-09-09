# Handoff

## Objetivo

Que configurar un módulo pase a ocurrir en **un solo lugar**: la pantalla del
módulo, con dos caras —si está pendiente se configura, si ya arrancó se trabaja y
la configuración se ve congelada—. Antes estaba repartido en seis pantallas y
ninguna era la del módulo.

Rama `configurar-vs-ejecutar`, sobre `rediseno-tailwind`. Plan y spec en
`docs/superpowers/plans/2026-09-09-configurar-vs-ejecutar.md` y
`docs/superpowers/specs/2026-09-09-configurar-vs-ejecutar-design.md`.

## Estado actual

**8 de 14 tareas cerradas**, cada una con revisión y ronda de arreglos. 20
commits. `make spec` en 732 ejemplos (0 fallas, 1 pending explicado abajo),
`make screens` 30 capturas, `make yarn-build` limpio.

Funciona hoy:

- `PATCH /challenges/:cid/steps/:id` es el único camino de escritura de la
  configuración. Autoriza según lo que llega: `advance?` para el modo de IA,
  `configure?` para lo estructural. El `config` se filtra contra el esquema.
- El builder es dueño sólo del armado (kind, orden, alta, baja). Ya no manda ni
  escribe `settings`, `criteria_set_id`, `source_step_id`, `name` ni `ai_mode`.
  Sus tarjetas son links a la pantalla del módulo.
- La pantalla del módulo despacha por `step.touched?` a `steps/config/<kind>` o
  `steps/<kind>`, en los cinco kinds.
- El editor de criterios está embebido en la cara de configuración;
  `/challenges/:cid/steps/:sid/criteria` redirige.

Falta: **tasks 7 a 13**. La 7 (embeber el editor de campos del formulario y
eliminar `/challenges/:id/form`) es la siguiente.

**Un `pending` real, no cosmético:** `spec/requests/gestor_spec.rb:191`. Asignar
un gestor a un módulo de evolución **pendiente** no funciona hasta la task 8. Es
`pending` y no `skip` a propósito: cuando la 8 lo arregle, RSpec va a fallar con
«se esperaba que fallara y pasó», así que no puede quedar enterrado.

## Archivos y cambios

| Archivo | Qué cambió |
|---|---|
| `app/lib/flow/step_settings.rb` | `filtrar` (sanea y castea el config que llega por params) y `display_value`; se sacó `cut.tie_break` |
| `app/controllers/steps_controller.rb` | `show` despacha por cara; `update` acepta lo estructural con autorización según lo que llega |
| `app/policies/challenge_step_policy.rb` | `configure?` |
| `app/controllers/api/v1/pipelines_controller.rb` | `update_existing` no escribe atributos; `create_added` usa los defaults del esquema |
| `app/presenters/pipeline_presenter.rb` | el hash del step ya no emite `settings`/`sourceStepId`/`criteriaSetId`; `settings_schema` público |
| `app/presenters/step_settings_presenter.rb` | nuevo, props de la isla |
| `app/javascript/components/step_settings/` | isla nueva, mudada del builder; renderiza `name=` dentro del form de Rails |
| `app/javascript/components/pipeline_builder/pipeline_builder.vue` | sin panel; la tarjeta entera es el link |
| `app/views/steps/config/` | shell, form del módulo y las cinco vistas |
| `app/views/steps/_config_congelada.html.haml` | resumen de sólo lectura de la cara B |
| `app/views/steps/_criterios_editor.html.haml` | editor de criterios embebido |
| `app/models/challenge_step.rb` | `criteria_set_id` congelado; validación de pertenencia al desafío; normalización de `ai_mode` |
| `script/capture_screens.js` | recorrido actualizado al builder sin panel y a la pantalla nueva |

## Intentos fallidos

Lo que se probó y **no** hay que repetir:

1. **Parchear el síntoma en vez de la estructura.** El trabajo empezó como un bug
   («no puedo poner el corte») y el primer arreglo fue agregar un link «Cambiar
   el corte» al builder. Estaba mal: el problema no era que faltara un link, era
   que configurar exigía rebotar entre pantallas. Ese commit quedó en
   `rediseno-tailwind`; esta rama lo reemplaza.
2. **`campos_de` / `escribir` en `Flow::StepSettings`.** Se escribieron y se
   borraron: `fields` y `write` ya existían y hacían lo mismo.
3. **`indexOf(this.step)` para filtrar por posición.** Compara por identidad de
   referencia. Funcionaba en el builder porque el objeto salía del mismo array;
   al mudar a la isla dejó de funcionar en silencio y el corte ofrecía
   evaluaciones posteriores a él. Ahora compara por `id`.
4. **`display: contents` en el link de la tarjeta.** Resolvió el clic accidental
   y rompió el foco por teclado: un elemento sin caja no entra en el tab order ni
   tiene dónde pintar el `outline`. Medido en Chromium, no supuesto. Ahora es
   `display: flex` con `:focus-visible`.
5. **`git add -A` con un subagente trabajando en el mismo árbol.** Barrió el
   archivo de tests de otro proceso dentro de un commit de documentación. Desde
   entonces, siempre por ruta explícita.
6. **Dos implementadores en paralelo.** No se puede: comparten el árbol de
   trabajo, y varias tareas escriben `script/capture_screens.js`.
7. **Confiar en que la suite ve los defectos visuales.** No los ve. Todo lo caro
   de esta rama (foco inalcanzable, clase sin regla, `name` sin `[]`, filtrado
   roto) apareció midiendo en un navegador o pidiendo el HTML servido, con
   `make spec` y `make screens` en verde.

## Próximos pasos

1. **Decidir un minor abierto:** `app/views/steps/_criterios_editor.html.haml:98`
   usa `criterion.summary` en la rama de sólo lectura, que para un criterio de
   fórmula imprime la expresión literal. La vista análoga de la cara B muestra
   sólo un chip «derivado». Cambiarlo por `source_label` + `scale_type` traducido,
   o dejarlo para el triaje de la revisión final.
2. **Task 7** — embeber el editor de campos en la cara de configuración de
   idear, redirigir `/challenges/:id/form`. El brief está en
   `.superpowers/sdd/2026-09-09-configurar-vs-ejecutar/task-7-brief.md` e incluye
   el paso de las sugerencias de IA (sin él, una sugerencia pendiente se queda
   sin pantalla al borrar la vieja).
3. **Task 8** — asignaciones en las dos caras. **Tiene que quitar el `pending` de
   `gestor_spec.rb:191`.**
4. Tasks 9 a 13: `Flow::Setup` y borrar el índice de criterios · la guarda de una
   sola vista de configuración · capturas de las dos caras · documentación ·
   este handoff.
5. **Revisión final de toda la rama** y `superpowers:finishing-a-development-branch`.
   El ledger tiene los minors diferidos para triaje.

**Cómo se ejecuta:** un subagente por tarea, revisión después de cada una, ronda
de arreglos, re-revisión acotada. El ledger vive en
`.superpowers/sdd/2026-09-09-configurar-vs-ejecutar/progress.md` (gitignored) y
tiene los rulings, los hallazgos parkeados y el estado de cada tarea. **Preguntar
antes de avanzar a la tarea siguiente**, siempre.

**No tocar:** los desafíos `onboarding-remoto` y
`optimizacion-de-la-experiencia-de-onboarding` son datos de prueba del usuario.
**Nunca correr `db:seed`.**
