# Handoff

## Objetivo

Tres cosas, y las tres terminadas.

**La tanda 1 del módulo de testing** —el sexto `kind` del flujo— ejecutada,
revisada y mergeada. **La tanda 2** —la IA y el filtro— diseñada, planificada,
ejecutada, revisada y mergeada. Y una **limpieza de la base de desarrollo**,
que quedó con las cuentas y un solo desafío.

Las dos tandas se ejecutaron con `superpowers:subagent-driven-development`: un
subagente fresco por tarea, revisión por tarea con dos veredictos, y un review
final de rama entera en Opus.

## Estado actual

- **`master` está en `d0c1878` y pusheado.** Local y remoto coinciden,
  verificado con `ls-remote` contra el remoto de verdad y no contra la foto
  local. No queda ninguna rama viva.
- **`make spec` → 1002 ejemplos, 0 fallas**, corrido sobre el merge y no sólo
  sobre la rama. **`make screens` → 66 capturas, 0 errores**, dos corridas
  seguidas sin resembrar.
- **El módulo de testing está completo**: funciona a mano, en IA asistida y en
  IA automática, y una selección posterior puede filtrar por su veredicto.

### La base de desarrollo quedó limpia

Con respaldo previo en **`tmp/respaldos/innk_flow_development_20260922_171541.sql`**
(1,6 MB, verificado que contiene los datos hechos a mano). **Ojo: `tmp/` está
fuera de git y un `git clean -fdx` se lo lleva** — si ese respaldo importa,
movelo afuera del repo.

- Queda **`merma-bodega`**, íntegro: siete módulos, flujo corrido de punta a
  punta, reportería activa.
- **Cuentas intactas**: 2 empresas, 9 usuarios, 11 membresías.
- Se borraron 18 desafíos. **Diez de ellos no están en el seed y `make seed` NO
  los devuelve** —incluido `mantenimiento-y-sostenibilidad`, que tenía 16
  ideas, y `optimizacion-de-la-experiencia-de-onboarding`, el que CLAUDE.md
  señala como dato real armado a mano—. Sólo el respaldo los tiene.
- **`make seed` reconstruye los nueve sembrados**, así que `make screens`
  vuelve a funcionar corriéndolo antes.

### Un subagente pusheó sin que se lo pidieran

Al ir a borrar la rama local, git avisó que existía
`refs/remotes/origin/modulo-de-testing-ia`. Verificado contra el remoto: la
rama de feature estaba **publicada en `0ad2e09`**, un commit de la mitad de la
ola de arreglos, y `master` había avanzado a `b1dac07`. **Ningún subagente
tenía encargo de pushear** y no se lo pedí a ninguno.

Sin daño de contenido —es el mismo trabajo— pero una rama a medio arreglar
quedó publicada. Se borró del remoto con autorización de Raúl. **Si en una
próxima sesión se despachan subagentes, conviene decirles explícitamente que no
pushean.**

## Archivos y cambios

### Tanda 1 — el `kind` a mano (merge `00b5abc`)

La tabla `step_tests` append-only con el vigente garantizado por un índice
parcial, `Flow::Handlers::Testing`, el esquema de configuración, las dos caras
de pantalla, la pantalla del testeo por idea, seeds y capturas.

Y **dos arreglos que no eran del módulo**: `add_tenant_fk` no acotaba la
columna en `ON DELETE SET NULL` —CLAUDE.md decía que sí y era falso—, con
guarda por mutación; y cuatro guardas de specs que enumeraban los cinco kinds a
mano, así que el sexto se les escapó en silencio.

### `on_complete` autocorrectivo (merge `0fdad72`)

El prerequisito que el review final de la tanda 1 marcó como «antes de la tanda
2». `complete!` no pregunta `can_complete?` —lo pregunta quien lo llama—, así
que un `done` incondicional le cree al llamador. Sin testeo vigente la entry
queda `in_progress`, como hace `Evaluation#recompute_entry!`.

### Tanda 2 — la IA y el filtro (merge `d0c1878`)

| Archivo | Qué es |
|---|---|
| `app/lib/flow/ai/tasks/test_idea.rb` | La tarea de IA, con el contrapeso del prompt |
| `spec/fixtures/ai/test_idea/default.json` | Su fixture determinista |
| `app/lib/flow/checks/testing_passed.rb` | El filtro que consume el veredicto |
| `db/migrate/20260922120000_add_test_idea_purpose.rb` | El CHECK de `ai_runs.purpose` |

Más `on_activate` con los tres modos, los botones de IA en las dos pantallas,
`CriterionSettings::CHECKS`, el seed de `filtro-por-testeo` y su captura.

### Se descubrió una CUARTA puerta para una tarea de IA

CLAUDE.md, `docs/ai.md` y la spec decían que sumar una tarea de IA es tocar
**tres** lugares: la clase, `AiRun::PURPOSES` y el CHECK de Postgres. **Son
cuatro**: `config/locales/es.yml` tiene un bloque `flow.ai_purposes` que se
había quedado en once, y el rótulo salía «Test idea», en inglés, en la tarjeta
de propuesta —que es donde una persona se encuentra con la tarea—.

La afirmación está corregida en los dos archivos operativos. La spec de diseño
sigue diciendo «tres» a propósito: es un documento histórico.

## Intentos fallidos

El patrón de estas dos tandas: **los planes estaban mal en doce lugares, y los
doce se encontraron porque alguien fue a medir en vez de creerle.** Siete en la
tanda 1 (ver el handoff anterior en el historial de git) y cinco en la tanda 2:

- **Un estado de `AiRun` que no existe.** Escribí `status: "pending"` y los
  válidos son `queued/running/succeeded/failed`. Peor: existe un
  `ai_runs_status_check`, así que el ejemplo que se saltea la validación para
  probar el CHECK de **propósito** habría fallado por el de **estado** — se
  habría visto como un RED correcto y habría seguido fallando después de la
  migración. Lo cazó el escaneo previo, antes de despachar.
- **Un `AiSuggestion` con dos objetivos.** El modelo valida `exactly_one_target`
  y mi spec le pasaba `challenge:` **e** `idea:`; el runner real arma la
  sugerencia con `**target_attributes`, que para esta tarea es sólo la idea.
- **`fixtures_spec.rb` armaba un solo `step` de ideación para cualquier tarea.**
  `TestIdea#schema` llama `handler.min_situations` y reventaba. Resultó que
  **ninguna de las diez tareas existentes toca `step.handler` dentro de
  `#schema`** —`decide_verdicts` lo usa en `apply!`, que ese spec no ejercita—,
  así que hasta hoy alcanzaba y nadie lo había notado.
- **Un snippet que contradecía su propia prosa.** Mi Paso 3 traía
  `form_class: "inline-form"` mientras el texto decía copiar un precedente que
  no usa `form_class`. **`.inline-form` no existe en ninguna hoja ni vista del
  repo**: habría dejado un elemento sin ninguna regla detrás.
- **Un seed que no arrancaba.** `Pipeline#validate` exige para **toda**
  selección un `score_source` resoluble sin mirar si el módulo tiene criterios
  propios, mientras `Selection#can_activate?` sí los mira. Ver «Próximos
  pasos».

### Cuatro cosas que yo adjudiqué mal

- **Diferí como «combinación rara» un texto roto en el caso común.** El `detail`
  del filtro descartaba el «con reservas» del veredicto y devolvía «Factible
  con 1 reserva»; con `accepts: solo_factible` la celda quedaba **«✗ Factible
  con 1 reserva»**: un rechazo cuyo texto empieza diciendo «Factible» y borró
  justo la palabra por la que se lo rechazó. Yo lo miré por la rama rara
  (`factible` + reservas) y el review final me mostró que el daño estaba en la
  común — `con_reservas` con reservas es lo que devuelve el fixture.
- **Dejé un hueco con mi propio arreglo.** Hice poner una guarda de permiso a
  una tarjeta y no pedí ninguna prueba de que la tarjeta **se mostrara**: una
  guarda mal escrita la habría hecho desaparecer para todos con la suite en
  verde. Es el riesgo que yo mismo había nombrado al mandar el arreglo.
- **Escribí un ruling en el ledger y no lo puse en el encargo.** El que cerraba
  el punto ciego de las capturas salió en un round extra que no hacía falta.
- **Afirmé que hacía falta `make yarn-build` y no hacía falta** (tanda 1): las
  clases ya estaban en la hoja compilada.

### Cosas que los subagentes encontraron y valen para la próxima

- **`destroy_all` sobre desafíos revienta con `StaleObjectError`.** El bloqueo
  optimista de `ChallengeStep` mueve `lock_version` durante la cascada mientras
  el lote ya está cargado. Se borra de a uno con carga fresca.
- **`[CONTRASTE]` sólo mide `.badge` y `.alert`, nunca `.btn`.** Así que el
  contraste de texto de cualquier botón de la app no lo mide ninguna guarda.
- **`Flow::Cohort.sync!` arma las `step_entries` al ACTIVAR el módulo**: una
  idea postulada después no tiene fila para nadie.
- **Trampa de HAML**: un comentario `-#` como hermano justo antes de un `- else`
  en un `case/when` tira «Got 'else' with no preceding 'if'» aunque la
  indentación sea idéntica. Se resuelve moviéndolo adentro del `else`.
- **`button_to` es un `<form>` y muerde también en las capturas**: un selector
  `input[type=submit]` matcheaba el botón «Salir» del header global.

## Próximos pasos

1. **La guarda de paridad `flow.ai_purposes` ↔ `AiRun::PURPOSES`.** Es lo
   primero. Nada la cuida hoy, y es exactamente la guarda que habría cazado
   sola el hallazgo que bloqueó el merge de la tanda 2, en vez de depender de
   que un revisor leyera el locale. Es un spec de lint corto, con la forma de
   los que ya cuidan los mapeos de `EstilosHelper` contra sus enums.

2. **`Pipeline#validate` vs `Selection#can_activate?`.** `validate` exige para
   toda selección un `score_source` resoluble sin consultar los criterios
   propios del módulo; `can_activate?` sí los consulta. O sea que **una
   selección de sólo filtros no arranca el flujo** salvo que se le declare el
   puntaje manual. Ya hay **tres** lugares que documentan el mismo rodeo
   (`db/seeds.rb`, `selection_screen_spec.rb:40`,
   `pantalla_del_modulo_spec.rb:255,303`), lo que refuerza que es un gap de
   producto y no ruido de test. Merece issue propio.

3. **Las once FKs con `ON DELETE SET NULL` sin acotador** (del handoff
   anterior, sigue abierto). El helper ya está arreglado, así que no nacen
   nuevas, pero las viejas siguen rotas: `selection_verdicts.ai_run_id`,
   `idea_versions.source_step_id`, `ideas.current_version_id`,
   `step_entries.input_version_id` y `.output_version_id`,
   `challenge_steps.criteria_set_id` y `.source_step_id`,
   `assessment_scores.criterion_id`, `reports.ai_run_id`,
   `feedback_items.addressed_by_version_id` y `.ai_run_id`. Están dormidas
   —ningún camino de la app borra esas filas padre— pero cualquiera que se
   agregue revienta con `PG::NotNullViolation`. Es una migración de parche
   propia, con la forma de `20260831210000_fix_composite_fk_set_null.rb`.

4. **`[FORMS]` no cubre las pantallas de formulario a las que se llega por
   clic.** `revisarFormsAnidados` corre desde `shot()`, y las capturas que
   navegan y llaman `capturar()` directo se lo saltean. Es la guarda que
   CLAUDE.md nombra por el bug del corte. Arreglo del recorrido entero.

5. **Nadie miró todavía las 66 capturas.** Sigue siendo lo único de las últimas
   cinco sesiones que no hizo una máquina.

6. **Cuatro Menores del módulo de testing, diferidos con triage:**
   - `TestingPassed` no declara `config_errors`: un `accepts` desconocido cae
     al más permisivo en silencio. Sólo alcanzable por payload editado a mano;
     el editor es un `select`.
   - `AiRequestsController` sólo rescata `ArgumentError`: un POST fabricado con
     `purpose=test_idea` y un `step_id` de otro kind sale 500 con traza.
   - El panel de propuestas de `steps/testing` nunca puede contener un
     `test_idea` (filtra por `challenge_step_id` y la tarea apunta a la idea).
     **No es nuevo**: `decide_verdicts` hace lo mismo contra `steps/selection`.
     Si alguna vez se arregla, se arreglan juntos.
   - `historial_de` ordena por `tested_at DESC` sin desempate.

7. **Lo de handoffs anteriores que sigue abierto**: plan 2c (las islas Vue),
   `SelectionsController#update` sin validación server-side de a quién se hace
   avanzar, `criteria_sets#show` huérfana, las 3 consultas de evolución, los
   tres temas de seguridad preexistentes, y que nada vigila el relleno por
   default de `card` desde que se retiró `[CARD]`.

## Decisiones de Raúl en esta sesión

- **Ejecutar las dos tandas con subagentes**, no inline.
- **Rama por tanda**, merge `--no-ff` local, y push de `master` sólo cuando lo
  pidió explícitamente.
- **Tanda 2 antes que mirar las capturas**, y `on_complete` antes que la tanda 2.
- **El fixture de `test_idea` es estático** y falla explícito contra una
  configuración exótica, en vez de enseñarle al proveedor a sintetizar.
- **Sin botón de lote «testear todas con IA»**: la IA testea en lote sólo en
  modo automático, porque la tarea no es aditiva.
- **La limpieza es de la BASE, no del seed**, dejando las cuentas y
  `merma-bodega` — y **con respaldo previo**, al enterarse de que diez de los
  desafíos no vuelven con `make seed`.
- **Borrar del remoto la rama que un subagente había publicado.**

### Lo que sigue esperando una decisión suya

- **Quien acompaña no puede testear.** La spec §2.5 dice «quien administra **o
  acompaña**» pero nombra `update_pipeline?`, que es `manager?`, que es
  `admin?` a secas: **el gestor queda afuera de los dos**. Si se abre a
  gestores, el predicado con la forma de `curate_pool?` hay que ponerlo en los
  tres lugares que hoy preguntan por el permiso.
- **Las once FKs** (punto 3): si se parchean o se dejan.
- **El seed y el recorrido**: la limpieza fue de la base. Si alguna vez se
  quiere que el seed arme un solo desafío, eso se lleva puesto `make screens`
  —46 referencias a siete desafíos— y necesita su propia rama y su propio plan.
