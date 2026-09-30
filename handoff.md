# Handoff

## Objetivo

Cerrar el **tramo P4** del listado de pendientes, que era lo último que quedaba
abierto. Se cerró entero —**28 de 28**— y con eso el listado completo: P0, P1,
P2, P3 y P4. Al final se actualizaron los dos diagramas y los tres artefactos.

## Estado actual

- **`master` está en `d7d6ae5`, pusheado.** `make spec` **1418/0** (venía de
  1358); `make screens` **71 capturas / 0 errores**, ahora con cuatro contadores
  de piso en la línea final.
- **Diez tandas mergeadas**, cada una con su rama borrada. 21 commits, 77
  archivos, +3093/−181.
- El listado, al día: https://claude.ai/artifact/C2i3g3ZRz1gUeMuX3bEXrq
  (encabezado y los 28 tildes puestos). Los diagramas también, republicados:
  https://claude.ai/artifact/86a1MJf9xuRBmmGpDHmczw ·
  https://claude.ai/artifact/QrNVi9xvzRgaZ5UsibSueB

### Lo que se cerró, en una línea cada uno

**A · El panel que no mostraba lo que pidió.** `ai_suggestions` guarda UN
objetivo y de esa columna salían DOS respuestas —sobre qué actúa, y desde qué
pantalla se pidió—. Tres tareas quedaban invisibles en el panel que las pedía, y
`path_for` hacía lo contrario de su propio comentario. La regla pasó a
declararse (`Tasks::Base.revisa_en`).

**B · Lo que se caía al default en silencio.** Un `accepts` desconocido en
`testing_passed` caía en la rama MÁS PERMISIVA; ahora todo `select` se valida
contra el esquema, con un hook en vez de un `super`. Un set `inline` sin módulo
dejó de ser representable.

**C · Lo que no llama nadie.** Se borraron `AssessmentPolicy#update?`, una
variable muerta y `Flow::Steps::ActivateJob` con sus tres referencias y su cola.
`criteria_sets#show` se queda, documentada. Y `flow.entry_statuses.skipped` no
sobraba: faltaba el cableado.

**D · Tests que daban verde sin poder fallar.** La tabla de puertas del gestor
pasó de tres sujetos a cinco, «Ver el set» ganó su par de polaridad, y el orden
del historial de testeos se pide en vez de heredarse de una coincidencia.

**E · Las guardas de la pastilla.** Una sola medición por pantalla para las dos
guardas, piso de cuánto midió, y un borde punteado que dejó de acreditarse como
uno sólido.

**F · Lo medido y anotado.** El «3 / 2» estaba vivo en el seed; el `min-width`
del desglose pasó de anotado a medido en cada corrida.

**G · Esquema y fondo.** La guarda de FK ausente encontró
`ai_suggestions.criteria_set_id` en su primera corrida, y la migración la agrega.
El CSP se habilitó acotado.

**H · El backlog largo.** `Pipeline#validate` dejó de reimplementar la regla de
la selección, guardar una evaluación resuelve el snapshot de una sola vez, la
pantalla de evolución quedó medida y el seed hace ruido cuando el flujo no avanza.

**2c · El último.** Las islas no necesitaban nada; la hoja tenía siete reglas sin
un solo uso.

## Archivos y cambios

- **Guardas nuevas, que es lo que más rinde de la sesión:**
  `spec/lint/propuesta_visible_donde_se_pidio_spec.rb` (una propuesta se revisa
  donde se pidió), `spec/lint/reglas_sin_elemento_spec.rb` (la mitad que le
  faltaba a `[CLASES]`), el ejemplo de FK ausente en `spec/tenancy/schema_spec.rb`,
  `spec/requests/evaluacion_una_consulta_de_criterios_spec.rb` (cuenta consultas),
  `spec/models/criteria_set_spec.rb`, y en `script/capture_screens.js` los pisos
  de `[PASTILLA]` y `[CRITERIO]` más la regla del borde punteado.
- **Declaraciones nuevas en el dominio:** `Tasks::Base.revisa_en`,
  `Criterion.indexed_from`, `Checks::Base#own_config_errors` (hook),
  `StepTest.vigente_primero`, `ApplicationHelper#origen_del_set`.
- **Esquema:** `db/migrate/20260930120000_add_missing_fk_on_ai_suggestions.rb` y
  `db/structure.sql`.
- **Seguridad:** `config/initializers/content_security_policy.rb`, que estaba
  comentado entero.
- **Docs:** `CLAUDE.md` (2c cerrado, el chequeo de navegador de los diagramas),
  los dos `.json` de los diagramas y sus HTML.

**Dos specs que vale conocer antes de tocar nada:**
`spec/lint/reglas_sin_elemento_spec.rb` y
`spec/lint/propuesta_visible_donde_se_pidio_spec.rb` son las dos que existen
porque el defecto que cuidan **no rompía ningún test**, y las dos prueban su
propio detector.

## Intentos fallidos

### Tres de las 28 fichas eran distintas de lo escrito, y una era falsa

- **`t-rescate` no existía.** «`AiRequestsController` sólo rescata
  `ArgumentError`, así que un POST fabricado sale 500 con traza»: el rescue
  angosto es cierto, la conclusión no. Se probaron los cuatro caminos —propósito
  desconocido, contexto faltante, un id que no es UUID, y sin `step_id` en una
  tarea que pide módulo activo— y dan flash, flash, 404 y 403. Lo que cubre todo
  lo de adentro es el `rescue StandardError` de `Flow::AI::Runner#call`, que la
  ficha no miró.
- **`p-skipped` era lo contrario de su ficha.** Estaba como «clave huérfana del
  locale» y no sobraba la clave: faltaba el cableado, y era un bug visible —una
  idea de un módulo salteado decía «Pendiente» para siempre—.
- **`l-show` tampoco era huérfana.** Ninguna vista linkea `criteria_sets#show`,
  pero es la ruta con la que `gestor_spec` prueba que la fuga de lectura que
  cerró `CriteriaSetPolicy::Scope` sigue cerrada.
- **`l-2c` era mucho más chico.** Medido, las islas ya usan los componentes de
  DaisyUI y lo propio que les queda es vocabulario de esta app.

**Lección: medir la ficha antes de ejecutarla.** Cuatro de 28 no decían lo que
pasaba, y las cuatro se descubrieron midiendo, no leyendo.

### `git checkout <archivo>` me borró el arreglo, no la mutación

Probando la guarda de la tanda A: muté `revisa_en` en `suggest_feedback.rb` y
restauré con `git checkout`. En una rama sin commit eso restaura del ÍNDICE, o
sea de antes del arreglo. Las dos mutaciones siguientes corrieron sobre un árbol
ya roto y la evidencia quedó contaminada. **Lo delató el propio lint spec**, que
seguía pidiendo la declaración que ya no estaba. Está en memoria: el backup va
con `cp` al scratchpad.

### Un piso que yo mismo calibré demasiado ajustado, y falló horas después

`PISO_DE_PASTILLAS` se puso en 700 un día que medía 758-810. En la tanda H la
misma corrida **sobre el mismo commit** daba 634 y fallaba. Lo que cambió fue la
BASE de desarrollo, no el código: se comprobó guardando los cambios en curso y
corriendo `master` limpio, que midió 634 igual. El recorrido camina datos
sembrados y los chips de estado salen de las ideas y módulos que haya. Quedaron
en 300 y 100 —`[CRITERIO]` tenía el mismo defecto—, con la diferencia con
`[RELLENO]` explicada: ése sí puede ir pegado porque los `card-body` son
estructura.

### Un contrato que ningún test podía hacer cumplir

En la tanda B escribí `config_errors` como `super + propios` con el comentario
«quien sobreescriba tiene que llamar a `super`». Después vi que **ningún test
puede cazar ese olvido**: los tres checks con errores propios no tienen ningún
`select` con opciones declaradas, así que perder la parte genérica no cambia nada
observable. Pasó a ser un hook (`own_config_errors`). Un hook no se puede
olvidar, que es mejor que una guarda para el mismo modo de falla.

### Dos tests míos que no podían fallar por lo que decían probar

- El de `p-skipped` matcheaba el nombre del módulo y «Salteado» sueltos sobre el
  body, y el nombre también sale en el mapa del flujo de la izquierda, donde
  «Salteado» sí está. Daba verde sin haber mirado «Cómo le fue».
- El del «3 / 2» me llevó **tres** intentos: un `.muted` con `title` suelto
  agarra el aviso de «Faltan evaluaciones», y anclarlo a la fila pero exigiendo
  `</span>` saltaba al chip de iniciales, porque la celda ENVUELVE a los chips.

Los dos se arreglaron apretando el matcher al markup, y los dos fallos fueron
visibles (`got: "Faltan evaluaciones…"`, `got: "Usuario3"`), que es lo que los
hizo detectables.

### Mi refactor rompió 17 ejemplos que mi propia guarda no cubría

`Criterion.indexed_from` en `EvaluateIdea` referenciaba `snapshot`, que ahí es
una LOCAL de `apply!` y no un método. Lo cazó **la suite existente**, no el spec
de conteo de consultas que acababa de escribir —ése cubre el camino del
controller—. Lección: una guarda nueva no cubre lo que uno cree que cubre;
mirar qué camino ejercita de verdad.

### El detector de CSS muerto reportó 267 de 402

Incluyendo `app-main` y `card-body`. HAML no escribe `class="x"` sino `.x`, y el
regex sólo miraba el atributo. Un detector roto reporta de más y se nota; uno mal
ACOTADO reporta cero y da verde, que no se nota. Por eso el spec prueba su propio
detector, con un ejemplo dedicado a la taquigrafía de HAML.

### El CSP con el nonce que sugiere Rails bloqueaba el único script inline

El archivo comentado que trae Rails propone
`config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }`.
Con eso el nonce sale **vacío** —medido: el header decía `'nonce-'` y el tag
`nonce=""`— y un nonce vacío no matchea: el navegador bloquea el script inline,
que es el del polling de reportes. **`make screens` dio verde igual**, y por dos
razones que valen juntas: sólo escucha `pageerror` y una violación de CSP es un
error de CONSOLA; y ese script sólo se renderiza con un reporte PENDIENTE, que el
recorrido no produce. Lo cazó un spec que compara el nonce del tag contra el del
header. El generador pasó a ser aleatorio por pedido.

### `deliver` no prueba que un diagrama entre en una pantalla

Sus nueve checks son estáticos. Eso lo mide `visual-check`, que **por default se
saltea** —«Chrome or Chromium is unavailable»— y sale con `ok: false` y
`status: "skipped"`, facilísimo de leer como aprobado. Apuntándolo al chromium
que ya usa `make screens`, los dos diagramas **fallan el contenido vertical**, y
venían fallando: sobre el HTML de `master` sin nada encima, arquitectura da
1339px de alto en un viewport de 900 y proceso 1688px. Mis cambios suman 6px al
primero y CERO al segundo.

## Próximos pasos

1. **El desborde vertical de los dos diagramas.** Es redistribuir el Y y subir el
   `viewBox`, o sacar contenido; el skill prohíbe taparlo con `overflow: hidden`
   o con letra más chica. Decisión de diseño, con los números y el comando en
   `CLAUDE.md`.
2. **`make screens` no ve violaciones de CSP.** Sólo escucha `pageerror`. Con el
   CSP activo desde esta sesión, es un punto ciego NUEVO: si alguien agrega un
   script inline sin nonce, el recorrido da verde y la pantalla no funciona.
   Escuchar `console` con filtro de CSP sería el arreglo.
3. **El nodo salteado del mapa del flujo mide menos de 3:1.** 1,96 en claro y
   2,42 en oscuro, y el punteado es su único portador VISUAL de estado —comparte
   `badge-soft` con el pendiente—. Hay `title` con el estado, así que hay
   alternativa textual; si se lo trata como información, el piso que le
   corresponde es 3:1 (WCAG 1.4.11) y no el 1,5 de la pastilla punteada.
4. **Decidir qué hacer con `origin/modulo-de-taller`**, viva en GitHub apuntando
   a `d3bc6b8`, ya ancestro de `master`. Viene de dos handoffs.
5. **El flake horario preexistente** de `spec/requests/selection_screen_spec.rb:138`:
   `Selection#decide!` escribe `decided_at: Time.current` por fila y la vista
   agrupa con `.change(sec: 0)`.
6. **Los dos artefactos de diagramas avisan que su botón de exportar no funciona**
   en el visor de artefactos («the artifact viewer never grants pages download
   permission»). Es del visor que genera archify, no del contenido; los HTML en
   `docs/` sí exportan.
7. **Hay actualización de la skill `archify`**: instalada 2.17.0-dev.1, última
   3.0.1. No se tocó nada.
8. Lo que sigue anotado y fuera de alcance de handoffs anteriores:
   `challenge_gestores` huérfano re-otorgando acceso, el redirect por membresía
   alcanzando a la API y a los turbo-frames, y la falta de spec del rollback de
   `Flow::Assignments::Release`.

## Cosas del entorno

- **En desarrollo `FLOW_AI_PROVIDER=anthropic`: un pedido a la IA cuesta plata
  real.** Ningún subagente abre la app ni corre `make screens`.
- **Probar una guarda es romperla a mano y correrla**, y el backup va con `cp` al
  scratchpad: **`git checkout <archivo>` en una rama sin commit restaura del
  índice, o sea deshace el ARREGLO y no la mutación.** Pasó, y contaminó dos
  mutaciones antes de notarse.
- **La base de desarrollo tiene datos hechos a mano que no están en el seed**
  (`optimizacion-de-la-experiencia-de-onboarding`). No se resetea. Y resembrar
  MUEVE los conteos del recorrido: por eso los pisos de `[PASTILLA]` y
  `[CRITERIO]` son flojos a propósito.
- **`visual-check` de archify necesita que se le diga dónde está Chrome:**
  `export ARCHIFY_CHROME=~/.cache/ms-playwright/chromium-1223/chrome-linux64/chrome`.
  Sin eso se saltea y sale `ok: false` con `status: "skipped"`.
- **Republicar un artefacto que esta conversación no publicó lleva tres intentos:**
  el primero se rechaza y guarda la versión viva, hay que leerla con la
  herramienta de lectura (no alcanza `diff` en disco), y el tercero pasa. Conviene
  comparar en disco antes, para no traer 800 KB a contexto.
- **El remote está por SSH y acá no hay clave.** Todo push va con la URL HTTPS
  explícita y después el ref de seguimiento se mueve a mano.
- **Las ramas van en el directorio del proyecto, sin worktree**: Docker está
  atado a él.
- El harness sigue inyectando `Co-Authored-By` por system-reminder; hay que
  cortarla a mano. En los 21 commits de esta sesión no quedó ninguna.
- `make screens` tarda ~2 minutos y `make spec` ~2. Las dos corren bien en
  background.
