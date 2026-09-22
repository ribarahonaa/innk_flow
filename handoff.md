# Handoff

## Objetivo

Ejecutar la **tanda 1 del módulo de testing** —el sexto `kind` del flujo—
según el plan y la spec que la sesión anterior dejó escritos. Al terminar hay
un módulo que pone las ideas a prueba contra situaciones concretas de
ejecución y deja un veredicto de factibilidad con su evidencia, **funcionando
entero a mano, sin una línea de IA**.

Se ejecutó con `superpowers:subagent-driven-development`: un subagente fresco
por tarea, revisión por tarea, y un review final de rama entera en Opus.

## Estado actual

- **Mergeado a `master`**: merge `--no-ff` `00b5abc`, 20 commits de rama. El
  árbol del merge es **idéntico** al de la rama (`git diff --stat` vacío entre
  los dos), así que las capturas de la rama valen para el merge.
- **`make spec` → 963 ejemplos, 0 fallas**, corrido sobre el merge y no sólo
  sobre la rama. **`make screens` → 65 capturas, 0 errores**, corrido dos
  veces seguidas sin resembrar para probar idempotencia.
- **`master` está 21 commits adelante de `origin/master`. NO se pusheó.**
- La rama `modulo-de-testing` ya está borrada (local; nunca se pusheó).
- **La tanda 2 no existe todavía.** Sale del mismo spec, §5 y §6.

### Qué quedó funcionando

El `kind` `testing` de punta a punta: enum + CHECK de Postgres, tabla
`step_tests` append-only con el vigente garantizado por un índice parcial,
handler, esquema de configuración, paso a paso, rótulos, las dos caras de
pantalla, la pantalla del testeo por idea, seeds y capturas.

**No elimina a nadie**: `ideas.status` sigue con un solo escritor,
`Selection#decide!`. Quien quiera que el testeo corte, pone una selección
después con un filtro `testing_passed` — que es la tanda 2.

## Archivos y cambios

### Lo nuevo del módulo

| Archivo | Qué es |
|---|---|
| `db/migrate/20260921120000_create_step_tests.rb` | El CHECK del sexto kind y la tabla |
| `app/models/step_test.rb` | Un testeo sobre UNA versión de UNA idea |
| `app/lib/flow/handlers/testing.rb` | El comportamiento del módulo |
| `app/views/steps/config/testing.html.haml` | Cara de configuración |
| `app/views/steps/testing.html.haml` | Cara de ejecución |
| `app/views/step_tests/new.html.haml` | El formulario del testeo de una idea |
| `app/controllers/step_tests_controller.rb` | `new` y `create` |

Más las entradas en `Flow::StepSettings::SCHEMA`, `Flow::Setup#estado_de`,
`EstilosHelper::CHIP_DE_VEREDICTO`, `config/locales/es.yml`, `config/routes.rb`,
`db/seeds.rb` y `script/capture_screens.js`.

### Dos arreglos que NO son del módulo y salieron al paso

**`lib/flow/migration_helpers.rb` — `add_tenant_fk` no hacía lo que CLAUDE.md
decía que hacía.** Con `on_delete: :nullify` emitía `ON DELETE SET NULL`
**pelado**, sin el `(columna)` que acota qué se nulea: borrar una fila padre
nulearía también `company_id`, que es NOT NULL, y reventaría con
`PG::NotNullViolation`. La única FK que tenía la forma correcta
(`assessments_ai_run_id_same_company`) la había parcheado a mano una migración
del 31/8, no el helper. Arreglado en `596f328`, **con guarda por mutación** en
`c1af363`: un ejemplo que borra una fila de `ai_runs` de verdad y afirma las
dos mitades —`ai_run_id` en `nil` **y** la fila viva con su `company_id`—,
visto en rojo antes de darlo por bueno.

**Las guardas que enumeraban cinco kinds a mano.** Cuatro lugares de
`dos_caras_spec.rb` y `pantalla_del_modulo_spec.rb` tenían
`%w[ideation evolution evaluation selection reporting]` literal, así que el
sexto kind **se les escapó en silencio**. Ahora derivan de
`ChallengeStep::KINDS`. El contraste que lo hace evidente:
`step_settings_spec.rb:9` ya era dinámico, y por eso ahí el rojo apareció solo.

### La documentación, que contaba cinco

`README.md`, `docs/pipeline.md` y tres líneas de `CLAUDE.md` decían cinco
módulos. Actualizadas. **Tres menciones de «cinco» se dejaron a propósito** y
conviene no «arreglarlas»: `CLAUDE.md:727` y `:804` describen hechos
históricos ocurridos cuando había cinco pantallas de módulo —cambiarlas
inventaría una historia que no pasó— y `CLAUDE.md:1037` habla de los cinco
colores del PDF, que no tiene nada que ver con los kinds.

## Intentos fallidos

El patrón de esta sesión es distinto al de la anterior: **el plan estaba mal en
siete lugares, y los siete se encontraron porque alguien fue a medir en vez de
creerle.**

- **El plan mandaba una FK simple a `ai_runs`.** Las dos tablas tienen
  `company_id`: es exactamente la FK que `spec/tenancy/schema_spec.rb` existe
  para cazar. El implementador se apartó del texto del brief, y bien.

- **`make rails ARGS="db:migrate"` no hace nada.** El target abre una consola
  y descarta `ARGS`. El plan lo usaba así en dos tareas. Los reales son
  `make migrate`, `make seed`, `make db-prepare-test`.

- **`render "steps/progreso", handler: handler`** — el partial recibe
  `progress:`. Como estaba en el plan, la pantalla reventaba.

- **Un `describe` nuevo usaba un `challenge` que no existe.** En
  `pantalla_del_modulo_spec.rb` cada `describe` define el suyo.

- **El plan afirmaba que las tres cadenas del chip de veredicto «ya están en
  `MUESTRARIO`» y sólo había que confirmarlo. Faltaba una.** De haberla dado
  por buena, `make screens` reventaba recién en la última tarea.

- **El `filter_map do |_, fila|` del plan estaba roto en los DOS caminos**, no
  sólo en el del formulario. Medido con `bin/rails runner` contra un
  `ActionController::Parameters` real: no responde a `to_ary`, así que el
  bloque de dos argumentos no desestructura y `fila` queda en `nil`. El plan
  traía una nota diciendo «si el spec falla acá, normalizá con…», o sea que el
  autor sospechaba y lo dejó como adivinanza en vez de medirlo.

- **La guarda que el plan pedía sumar a `MODULOS_EN_ZONAS` era decorativa.**
  Esa lista sólo se consulta dentro del loop de `stepLinks` de `merma-bodega`,
  que no tiene módulo de testing: la regex nunca se habría ejercitado.

### Tres cosas que yo adjudiqué mal o de más

- **Diferí como «cosmético» algo que era una aserción tautológica.** La
  captura del envío del formulario elegía siempre `verdict: 'factible'` y
  afirmaba que el badge decía «Factible». Yo lo miré como «el veredicto de la
  captura deriva entre corridas» y dije «la idempotencia vale más que el
  matiz». El review final lo reencuadró: desde la **segunda** corrida sin
  resembrar el badge ya decía «Factible» antes de enviar, así que un POST que
  no hiciera nada pasaba igual — y es el único chequeo del camino que usa una
  persona. Estaba juzgando el síntoma equivocado.

- **Afirmé que hacía falta `make yarn-build` y no hacía falta.** Verifiqué
  después: las cinco clases del chip ya estaban en la hoja compilada.

- **Clasifiqué como Menor diferible una fuga de lectura.** Que quien participa
  vea filas de ideas ajenas es la clase de bug que este repo ya shippeó una
  vez. Se cerró en la Task 6 en vez de diferirse.

### Cosas que los subagentes encontraron sobre el dominio

- **Los `step_entries` los arma `Flow::Cohort.sync!` al ACTIVAR el módulo.**
  Una idea postulada después del arranque no tiene fila **para nadie**. El
  primer intento de probar el filtro de visibilidad postulaba a la segunda
  persona después del `advance!`, y la fila no aparecía ni para quien
  administra: el test habría pasado en verde probando nada.

- **Trampa de HAML:** un comentario `-#` puesto como hermano justo antes de un
  `- else` en un `case/when` tira «Got 'else' with no preceding 'if'» aunque
  la indentación sea idéntica a la de los `when`. Se resuelve moviendo el
  comentario adentro del cuerpo del `else`.

- **`button_to` es un `<form>`, y muerde también del lado de las capturas.** Un
  selector `input[type=submit], button[type=submit]` matcheaba el
  `button_to "Salir"` del header global y apretaba eso en vez del botón del
  formulario.

- **El repo distingue DOS familias de chips**, y parece una incoherencia hasta
  que se mira: las marcas sueltas que se piden por nombre (`chip("version")`)
  **revientan** ante un nombre desconocido, porque es un error de código; los
  mapeos de un enum de dominio (`chip_de_estado`, `chip_de_origen`,
  `punto_de_estado`) **todos** caen a un default, para un valor de dominio que
  el código todavía no contempla.

## Próximos pasos

1. **Pushear.** `master` está 21 commits adelante de `origin/master`. Es lo
   único pendiente del árbol. El SSH de este entorno no anda: va por HTTPS con
   el token de `gh`.

2. **`on_complete` del handler, ANTES de la tanda 2.** Marca `done` todas las
   entries sin guarda propia, incluida una sin testeo vigente (`verdict` en
   `nil`). Hoy es inalcanzable —el único invocador de `complete!` es
   `Pipeline#advance!`, que pregunta `can_complete?` antes, y `skip!` no lo
   llama—, pero **la tanda 2 suma un `on_activate` que encola un `RunJob` por
   idea, y ahí aparece el segundo camino de cierre que lo activa**. El arreglo
   es copiar la forma autocorrectiva de `Evaluation#on_complete`, que deja
   `in_progress` si no llega al mínimo: tres líneas.

3. **La tanda 2**: la tarea de IA `TestIdea` con su fixture, el CHECK de
   `ai_runs_purpose_check`, y el check `Flow::Checks::TestingPassed`. Spec §5 y
   §6. Ojo con el contrapeso del prompt (§5): el rigor va en las
   **situaciones**, no en el veredicto.

4. **Nadie miró todavía las 65 capturas.** Sigue siendo lo único de las últimas
   cuatro sesiones que no hizo una máquina.

5. **Las once FKs con `ON DELETE SET NULL` sin acotador.** El helper ya está
   arreglado, así que no nacen nuevas, pero las viejas siguen rotas:
   `selection_verdicts.ai_run_id`, `idea_versions.source_step_id`,
   `ideas.current_version_id`, `step_entries.input_version_id` y
   `.output_version_id`, `challenge_steps.criteria_set_id` y `.source_step_id`,
   `assessment_scores.criterion_id`, `reports.ai_run_id`,
   `feedback_items.addressed_by_version_id` y `.ai_run_id`. Están dormidas
   —ningún camino de la app borra esas filas padre— pero cualquiera que se
   agregue revienta con `PG::NotNullViolation`. Es una migración de parche
   propia, con la forma de `20260831210000_fix_composite_fk_set_null.rb`.

6. **`[FORMS]` no cubre las pantallas de formulario a las que se llega por
   clic.** `revisarFormsAnidados` corre desde `shot()`, y las capturas que
   navegan y llaman `capturar()` directo se lo saltean — hoy son dos, incluida
   la del formulario del testeo. Es la guarda que CLAUDE.md nombra por el bug
   del corte. Arreglo del recorrido entero, no de una pantalla.

7. **Tres cosas menores del módulo, sin decidir:**
   - `historial_de` ordena por `tested_at DESC` sin desempate.
   - `StepTestsController` no comprueba que el paso sea un testing: un id de
     otro kind da `NoMethodError` (500) en vez de 404. `AssessmentsController`
     tiene el mismo hueco, así que es patrón preexistente.
   - `min_situations` no se valida en el camino manual: se puede guardar un
     veredicto con cero situaciones. En la tanda 2 el `minItems` del schema lo
     hará cumplir del lado de la IA, y entonces la misma clave valdrá para una
     cara y no para la otra.

8. **Lo de handoffs anteriores que sigue abierto**: plan 2c (las islas Vue),
   `SelectionsController#update` sin validación server-side de a quién se hace
   avanzar, `criteria_sets#show` huérfana, las 3 consultas de evolución, los
   tres temas de seguridad preexistentes, y que nada vigila el relleno por
   default de `card` desde que se retiró `[CARD]`.

## Decisiones de Raúl en esta sesión

- **Ejecutar con subagentes** (un subagente fresco por tarea con revisión
  entre tareas), no inline con checkpoints.
- **Rama `modulo-de-testing`** y no directo en `master`.
- **Merge `--no-ff` local**, no PR. Sin pushear.

### Lo que está esperando una decisión suya

- **Quien acompaña no puede testear.** La spec §2.5 dice «testear es de quien
  administra **o acompaña**» pero nombra `update_pipeline?`, que es `manager?`,
  que es `admin?` a secas: **el gestor queda afuera de los dos**. Se siguió el
  plan (`advance?`, admin-only). Si se abre a gestores, el predicado con la
  forma de `curate_pool?` —`manager? || (gestor? && reaches_challenge?)`— hay
  que ponerlo en **los dos** lugares que hoy preguntan `advance?`:
  `step_tests_controller.rb` (dos veces) y `steps/testing.html.haml`, donde
  además manda el bloque de ajustes plegados.
- **Las once FKs** (punto 5 de arriba): si se parchean o se dejan.
