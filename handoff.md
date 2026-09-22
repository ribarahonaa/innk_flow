# Handoff

## Objetivo

El módulo de testing —el sexto `kind` del flujo— de punta a punta, en dos
tandas, más lo que salió de mirar las capturas por primera vez en cinco
sesiones y un bug del proveedor real que reportó Raúl desde la app.

Las dos tandas se ejecutaron con `superpowers:subagent-driven-development`: un
subagente fresco por tarea, revisión por tarea con dos veredictos, y un review
final de rama entera en Opus.

## Estado actual

- **`master` está en `c795616` y pusheado.** Local y remoto verificados con
  `ls-remote` contra el remoto de verdad, no contra la foto local. Sin ramas
  vivas.
- **`make spec` → 1017 ejemplos, 0 fallas.** **`make screens` → 66 capturas,
  0 errores.** Las dos corridas antes del último commit.
- **El módulo de testing está completo**: funciona a mano, en IA asistida y en
  IA automática, y una selección posterior puede filtrar por su veredicto.
- **El stack de Docker quedó caído** al cerrar la sesión. `make up` antes de
  cualquier cosa.

### La base quedó a medio camino, y es un desprolijo mío

Raúl pidió dejarla con las cuentas y **un solo desafío** (`merma-bodega`). Se
hizo, con respaldo previo. **Después la deshice sin querer**: correr las
capturas necesita `make seed`, y eso recreó los nueve desafíos sembrados.

Hoy la base está en el peor de los dos mundos:

- **No está limpia**: tiene los nueve sembrados.
- **Y le faltan los diez hechos a mano** —`mantenimiento-y-sostenibilidad` con
  sus 16 ideas, `optimizacion-de-la-experiencia-de-onboarding` y ocho más—,
  que el borrado se llevó y `make seed` no devuelve.

**Lo único que los tiene es el respaldo**:
`tmp/respaldos/innk_flow_development_20260922_171541.sql` (1,6 MB, verificado
que contiene los datos hechos a mano). **`tmp/` está fuera de git y un
`git clean -fdx` se lo lleva** — si ese respaldo importa, moverlo afuera del
repo antes que nada.

Tres salidas, ninguna obvia: restaurar el respaldo y volver a limpiar; limpiar
de nuevo sobre lo que hay, perdiendo definitivamente los diez; o dejarlo así,
sabiendo que `make screens` necesita los nueve sembrados para correr.

### Un subagente pusheó sin que se lo pidieran

Durante la tanda 2, al ir a borrar la rama local, git avisó que existía
`refs/remotes/origin/modulo-de-testing-ia`. La rama de feature estaba
**publicada a mitad de la ola de arreglos**. Ningún subagente tenía encargo de
pushear. Se borró del remoto con autorización de Raúl. **Si se despachan
subagentes, hay que decirles explícitamente que no pushean.**

## Archivos y cambios

### Tanda 1 — el `kind` a mano (merge `00b5abc`)

La tabla `step_tests` append-only con el vigente garantizado por un índice
parcial, `Flow::Handlers::Testing`, el esquema de configuración, las dos caras
de pantalla, la pantalla del testeo por idea, seeds y capturas.

Más **dos arreglos que no eran del módulo**: `add_tenant_fk` no acotaba la
columna en `ON DELETE SET NULL` —CLAUDE.md decía que sí y era falso—, con
guarda por mutación; y cuatro guardas de specs que enumeraban los cinco kinds
a mano, así que el sexto se les escapó en silencio.

### `on_complete` autocorrectivo (merge `0fdad72`)

`complete!` no pregunta `can_complete?` —lo pregunta quien lo llama—, así que
un `done` incondicional le cree al llamador. Sin testeo vigente la entry queda
`in_progress`, como hace `Evaluation#recompute_entry!`.

### Tanda 2 — la IA y el filtro (merge `d0c1878`)

`Flow::AI::Tasks::TestIdea` con su fixture y el contrapeso del prompt,
`on_activate` con los tres modos, los botones de IA en las dos pantallas,
`Flow::Checks::TestingPassed` con sus dos params, la migración del CHECK de
`ai_runs.purpose`, el seed de `filtro-por-testeo` y su captura.

### La guarda de paridad de rótulos (merge `700b6a5`)

`spec/lint/paridad_de_rotulos_spec.rb` compara **las siete** listas de `es.yml`
contra su enum y falla si falta un rótulo o si sobra uno. Existe porque al
sumar `test_idea` se tocaron las tres puertas que CLAUDE.md nombraba y quedó
una cuarta sin tocar: el rótulo salía «Test idea», en inglés, justo en la
tarjeta donde una persona se encuentra con la tarea.

**Son CUATRO puertas, no tres**, y la afirmación está corregida en CLAUDE.md y
en `docs/ai.md`. La spec de diseño sigue diciendo «tres» a propósito: es un
documento histórico.

### Tres cosas que sólo se vieron mirando las capturas (merge `709f8fd`)

- **«Faltan 1 idea por testear»**: el verbo no acordaba. `Flow::Texto.faltan`
  lo resuelve, y se aplicó también en selección, que tenía el mismo defecto.
  **Evaluación no**: ahí el verbo concuerda con «evaluaciones», no con el
  conteo. Se verificó uno por uno antes de tocar.
- **«3 situaciones en la que»**: se sacó el relativo entero en vez de
  acordarlo, así funciona igual con una que con tres.
- **El multi-select cortaba la quinta opción por la mitad.** La regla de altura
  estaba calculada para cuatro filas; ahora el alto sale de `size`, así que el
  navegador nunca parte una fila.

### El schema que excedía el límite de la API (merge `c795616`)

**Lo reportó Raúl desde la app, con el proveedor real.** La API rechaza con 400
un schema con más de 24 parámetros **opcionales**. `propose_pipeline` arma una
variante por kind, y cada una aporta su `ai_mode`, su `config` y los campos de
ese config: con cinco kinds eran **23 —uno por debajo del límite—** y el sexto
lo llevó a **28**.

`ai_mode` y `config` pasan a obligatorios: 28 → 16. No cambia lo que el modelo
puede proponer (`nil` sigue significando «heredá del desafío» y un `config`
vacío son todos los defaults); sólo cambia que los tiene que escribir.

`spec/lib/flow/ai/limite_de_opcionales_spec.rb` cuenta lo que cuenta la API,
falla nombrando lo que sobra, y **exige margen para un kind más**.

**Nada podía verlo**: el fixture valida contra el mismo schema pero no tiene
ese límite, y el adapter real nunca corre en los tests porque cada llamada
cuesta plata. Medidas las doce tareas: sólo `propose_pipeline` (16) y
`suggest_criteria` (10) son no triviales, y sólo la primera crece con el
dominio.

## Intentos fallidos

El patrón de la sesión: **los planes estaban mal en catorce lugares, y los
catorce se encontraron midiendo, no leyendo.** Los de las dos tandas están en
los handoffs anteriores, en el historial de git. Los de esta última parte:

- **Un estado de `AiRun` que no existe.** Escribí `status: "pending"` y los
  válidos son `queued/running/succeeded/failed`. Peor: existe un
  `ai_runs_status_check`, así que el ejemplo que se saltea la validación para
  probar el CHECK de **propósito** habría fallado por el de **estado**, y
  habría seguido fallando después de la migración.
- **Un snippet que contradecía su propia prosa**: `form_class: "inline-form"`,
  una clase que **no existe en ninguna hoja ni vista del repo**.
- **`fixtures_spec.rb` armaba un solo `step` de ideación para cualquier tarea.**
  `TestIdea` es la primera tarea cuyo `#schema` toca `step.handler`, así que
  hasta hoy alcanzaba y nadie lo había notado.

### Cinco cosas que yo adjudiqué mal

- **Diferí como «combinación rara» un texto roto en el caso común.** El
  `detail` del filtro descartaba el «con reservas» y con `accepts:
  solo_factible` la celda quedaba **«✗ Factible con 1 reserva»**: un rechazo
  cuyo texto empieza diciendo «Factible».
- **Dejé un hueco con mi propio arreglo**: puse una guarda de permiso a una
  tarjeta sin pedir ninguna prueba de que la tarjeta **se mostrara**.
- **Escribí un ruling en el ledger y no lo puse en el encargo.**
- **Afirmé que hacía falta `make yarn-build` y no hacía falta.**
- **Deshice la limpieza de la base** al resembrar para las capturas, sin
  advertirlo hasta después.

### Tres cosas que se rompieron al arreglar el límite de la API

Las tres las encontraron guardas, no yo:

- El fixture de `propose_pipeline` dejó de validar: cinco de sus siete pasos no
  traían `ai_mode`.
- `tasks_spec.rb:404` **dejó de discriminar**: el caso inválido habría seguido
  pasando por la clave faltante en vez de por el corte mal, que es lo que ese
  ejemplo existe para probar.
- **Mi propio mensaje de error reventaba cuando la aserción pasaba**:
  `last(16 - 24)` con un negativo. RSpec arma el mensaje aunque el test pase.

### Cosas del dominio que aparecieron y valen para la próxima

- **`destroy_all` sobre desafíos revienta con `StaleObjectError`**: el bloqueo
  optimista de `ChallengeStep` mueve `lock_version` durante la cascada. Se
  borra de a uno con carga fresca.
- **`[CONTRASTE]` sólo mide `.badge` y `.alert`, nunca `.btn`.**
- **`Flow::Cohort.sync!` arma las `step_entries` al ACTIVAR el módulo**: una
  idea postulada después no tiene fila para nadie.
- **Trampa de HAML**: un comentario `-#` como hermano justo antes de un
  `- else` tira «Got 'else' with no preceding 'if'».
- **`button_to` es un `<form>` y muerde también en las capturas**: un selector
  `input[type=submit]` matcheaba el botón «Salir» del header.
- **Reformatear un JSON con `json.dump` destruye el alineado a mano.** El
  fixture de `propose_pipeline` está escrito con un paso por línea y columnas
  alineadas; hay que conservarlo.

## Hechos del entorno que muerden

- **`make up` primero**: el stack quedó caído.
- **`make screens` necesita `make seed` antes** si la base no tiene los
  desafíos sembrados — y `make seed` **deshace** cualquier limpieza manual.
- **Los specs corren en `app_test`, no en `app`.** `docker compose exec app
  bundle exec rspec` usa el contenedor de desarrollo y devuelve 403 «Blocked
  hosts» en **todos** los request specs. Siempre `make spec*`.
- **`make rails ARGS="…"` no hace nada**: el target abre una consola y descarta
  `ARGS`. Los reales son `make migrate`, `make seed`, `make db-prepare-test`.
  Para correr un script: `docker compose exec -T app ./bin/rails runner -` por
  stdin.
- **El push por SSH no anda**: va por HTTPS con el token de `gh`.
- **`git rev-parse origin/master` lee una foto local, no el remoto.**
  `ls-remote` antes de concluir nada.
- **Nunca un worktree**: `docker-compose.yml` monta `.` en `/rails`.
- **No corras dos `make screens` en paralelo.**
- **Si despachás subagentes, decíles que no pushean.**

## Próximos pasos

1. **Confirmar que el 400 de la API se fue.** El arreglo está medido contra la
   cuenta de la API (28 → 16) pero **no se probó con una llamada real**. Se
   dispara desde el builder de un desafío en borrador, con «Proponer el flujo».
   Si vuelve a fallar, el mensaje distingue dos cosas muy distintas: si sigue
   diciendo «too many optional parameters», la cuenta de la guarda está mal; si
   dice otra cosa, es un problema nuevo que el arreglo destapó.

2. **Decidir qué hacer con la base** (ver «Estado actual»). Y antes de nada,
   **mover el respaldo fuera de `tmp/`**.

3. **Lo que se vio en las capturas y no se arregló.** Se miraron 9 de 66:
   - El **drawer no llega al fondo** de la página, y en páginas largas el
     contenido queda flotando a media altura en vez de pegado arriba.
   - La columna **«Acción» apila los botones**: «Re-testear» parte en dos
     renglones y el botón «IA» cae debajo, con anchos distintos entre filas.
   - Los **`select` no se distinguen de un campo de texto**: sin flecha, no hay
     forma de saber que se despliegan.
   - Los **15 avisos se ven idénticos**: «tu idea no avanzó» y «tu idea avanzó»
     tienen el mismo peso visual, y con esa lista nadie tría.
   - La **tarjeta del módulo de testing en la previsualización se repite a sí
     misma**, casi palabra por palabra.
   - El **popup de la IA dice lo mismo en el título y en el cuerpo**, y repite
     el bloque que ya está detrás.

4. **Las 57 capturas que no se miraron.**

5. **`Pipeline#validate` vs `Selection#can_activate?`.** `validate` exige para
   toda selección un `score_source` resoluble sin consultar los criterios
   propios del módulo; `can_activate?` sí los consulta. O sea que **una
   selección de sólo filtros no arranca el flujo** salvo que se le declare el
   puntaje manual. Ya hay **tres** lugares que documentan el mismo rodeo
   (`db/seeds.rb`, `selection_screen_spec.rb:40`,
   `pantalla_del_modulo_spec.rb:255,303`). Merece issue propio.

6. **Las once FKs con `ON DELETE SET NULL` sin acotador.** El helper ya está
   arreglado, así que no nacen nuevas, pero las viejas siguen rotas:
   `selection_verdicts.ai_run_id`, `idea_versions.source_step_id`,
   `ideas.current_version_id`, `step_entries.input_version_id` y
   `.output_version_id`, `challenge_steps.criteria_set_id` y `.source_step_id`,
   `assessment_scores.criterion_id`, `reports.ai_run_id`,
   `feedback_items.addressed_by_version_id` y `.ai_run_id`. Están dormidas
   —ningún camino de la app borra esas filas padre— pero cualquiera que se
   agregue revienta con `PG::NotNullViolation`. Es una migración de parche
   propia, con la forma de `20260831210000_fix_composite_fk_set_null.rb`.

7. **`[FORMS]` no cubre las pantallas de formulario a las que se llega por
   clic.** `revisarFormsAnidados` corre desde `shot()`, y las capturas que
   navegan y llaman `capturar()` directo se lo saltean. Es la guarda que
   CLAUDE.md nombra por el bug del corte.

8. **Cuatro Menores del módulo de testing, diferidos con triage:**
   - `TestingPassed` no declara `config_errors`: un `accepts` desconocido cae
     al más permisivo en silencio. Sólo alcanzable por payload editado a mano.
   - `AiRequestsController` sólo rescata `ArgumentError`: un POST fabricado con
     `purpose=test_idea` y un `step_id` de otro kind sale 500 con traza.
   - El panel de propuestas de `steps/testing` nunca puede contener un
     `test_idea`. **No es nuevo**: `decide_verdicts` hace lo mismo contra
     `steps/selection`. Si se arregla, se arreglan juntos.
   - `historial_de` ordena por `tested_at DESC` sin desempate.

9. **Lo de handoffs anteriores que sigue abierto**: plan 2c (las islas Vue),
   `SelectionsController#update` sin validación server-side de a quién se hace
   avanzar, `criteria_sets#show` huérfana, las 3 consultas de evolución, los
   tres temas de seguridad preexistentes, y que nada vigila el relleno por
   default de `card` desde que se retiró `[CARD]`.

## Decisiones de Raúl en esta sesión

- **Ejecutar las dos tandas con subagentes**, no inline.
- **Rama por tanda**, merge `--no-ff` local, y push sólo cuando lo pidió.
- **Tanda 2 antes que mirar las capturas**, y `on_complete` antes que la tanda 2.
- **El fixture de `test_idea` es estático** y falla explícito contra una
  configuración exótica, en vez de enseñarle al proveedor a sintetizar.
- **Sin botón de lote «testear todas con IA»**: la IA testea en lote sólo en
  modo automático, porque la tarea no es aditiva.
- **La limpieza es de la BASE, no del seed**, dejando las cuentas y
  `merma-bodega`, **y con respaldo previo** al enterarse de que diez de los
  desafíos no vuelven con `make seed`.
- **Borrar del remoto la rama que un subagente había publicado.**
- **La guarda de paridad cubre las siete listas**, no sólo la que falló: se le
  propuso achicarla a una y eligió dejarla completa.
- **Arreglar los dos errores de texto y el multi-select** de lo que apareció en
  las capturas, y dejar el resto anotado.

### Lo que sigue esperando una decisión suya

- **Quien acompaña no puede testear.** La spec §2.5 dice «quien administra **o
  acompaña**» pero nombra `update_pipeline?`, que es `manager?`, que es
  `admin?` a secas: **el gestor queda afuera de los dos**. Si se abre a
  gestores, el predicado con la forma de `curate_pool?` va en los tres lugares
  que hoy preguntan por el permiso.
- **Las once FKs** (punto 6): si se parchean o se dejan.
- **La base** (punto 2).
- **El seed y el recorrido**: la limpieza fue de la base. Si alguna vez se
  quiere que el seed arme un solo desafío, eso se lleva puesto `make screens`
  —46 referencias a siete desafíos— y necesita su propia rama y su propio plan.
