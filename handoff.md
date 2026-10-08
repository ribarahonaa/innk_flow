# Handoff — la grabación de la mesa (C1), y lo que quedó sin medir (2026-10-08)

## 1. Objetivo

Construir **C1** de un sub-proyecto de tres: la mesa de un taller graba su
conversación desde el navegador, el audio se transcribe con etiquetas de
hablante, y la sala dibuja una línea de sonido en vivo mientras graba.

- **C1 (esta rama):** grabar, subir, transcribir, mostrar. Hecho.
- **C2 (pendiente):** darle esa transcripción al modelo para que resuma/proponga.
  Su premisa central son las **etiquetas de hablante**, y están **sin verificar
  con voces reales** (ver §4).
- **C3 (pendiente):** el tercero del sub-proyecto; no se diseñó.

La última tarea (8) era sólo documentación: dejar `CLAUDE.md` y la spec contando
la verdad. Sin cambios de código.

## 2. Estado actual

Rama **`grabacion-de-la-mesa`**, 29 commits sobre `master` antes de los de esta
tarea. **No verifiqué el remoto:** el `ls-remote` por SSH da `Permission denied`
(el push va por HTTPS con el helper de `gh`; preguntar por la RAMA, no por
`master`: `gh api repos/ribarahonaa/innk_flow/branches/grabacion-de-la-mesa
--jq .commit.sha`).

- `make spec`: **1769 ejemplos, 0 fallas** (corrido sobre el árbol final, tras la
  tanda de arreglos de la revisión de rama).
- `make screens` (tras `make seed` y `make yarn-build`): verde, "Sin errores de
  JS ni respuestas >= 400", 76 capturas. Las ONCE cifras:
  `[RITMO] 40 · [RELLENO] 299 · [PASTILLA] 789 · [CRITERIO] 195 · [LIVE] 1 ·
  [RIEL] 71 · [BANDA] 71 · [SOMBRA] 302 · [CAMPO] 289 · [DRAFT] 2 · [GRABAR] 2`.

**Proveedores, tal como queda el stack — Y CAMBIÓ RESPECTO DEL HANDOFF
ANTERIOR.** Lo dejo en **`FLOW_AI_PROVIDER=fixture`** en `app` y `sidekiq`, no en
`anthropic`: recreé los dos contenedores para correr el recorrido sin facturar, y
lo dejo así porque es el lado seguro —el handoff anterior se quejaba justamente de
haber heredado `anthropic` sin saberlo y de que cada corrida costara plata—.
Para devolverlo:

```bash
FLOW_AI_PROVIDER=anthropic docker compose up -d --force-recreate app sidekiq
```

El recreate tiene que incluir `sidekiq` (`Flow::AI.provider` memoiza por proceso)
y **no** sirve `make reup`, que baja el stack entero. `FLOW_SPEECH_PROVIDER` está **sin declarar a propósito**: la cascada cae al
fixture (Anthropic no transcribe), así que ni la suite ni el recorrido facturan
voz. `DEEPGRAM_API_KEY` está en `.env` y **autentica desde el host**: lo medido es
un `curl` a `/v1/listen` que devolvió HTTP 200, no un pedido hecho desde la app.

**Corrección de la revisión final:** hasta ella `docker-compose.yml` **no
reenviaba ninguna de las tres variables de voz a los contenedores** —enumera el
entorno con `${VAR:-default}` y no tiene `env_file:`, así que el `.env` sólo
interpola—, y en `sidekiq`, que es el proceso que corre el job,
`env | grep -cE "FLOW_SPEECH|DEEPGRAM"` daba **0**. O sea que el eje era
imposible de encender editando el `.env`, y quien lo intentara se habría comido
el `TranscriptionFailed, "falta DEEPGRAM_API_KEY"` del adapter. Las tres ya están
en el anchor con default vacío, y `app_test` fija `FLOW_SPEECH_PROVIDER: fixture`
con `DEEPGRAM_API_KEY: ""`. Encender el eje es poner las dos variables.

**Y esto quedó verificado EMPÍRICAMENTE y no leyendo el compose**: tras recrear
`app` y `sidekiq`, `docker compose exec -T sidekiq env | grep -E
"FLOW_SPEECH|DEEPGRAM"` devuelve las tres —las dos de voz vacías, la credencial
presente—. Antes del arreglo devolvía **cero**. Ojo con esto: **el cambio de
compose no lo toma un contenedor ya corriendo**, hace falta
`up -d --force-recreate`.

**Riesgo abierto que ningún documento cerraba:** la diarización colapsa en las dos
mediciones que hay (§4) y el español no se midió nunca.

## 3. Archivos y cambios

| Pieza | Dónde |
|---|---|
| El eje de voz: `Provider#transcription?`/`#transcribe`, `Flow::AI.speech_provider`, `Provider::Transcription` (Data), `TranscriptionFailed` | `app/lib/flow/ai.rb`, `ai/provider.rb`, `errors.rb` |
| Adapter de Deepgram (normaliza; `transcription_from` público) y fixture | `app/lib/flow/ai/providers/deepgram.rb`, `fixture.rb`, `spec/fixtures/ai/` |
| Tabla y modelo `workshop_recordings` (`collapsed_diarization?` cuenta sólo a los presentes) | `db/migrate`, `app/models/workshop_recording.rb`, `db/structure.sql` |
| Subida y entrega (cuatro guardas, entre ellas `arrival?`) | `app/controllers/workshop_recordings_controller.rb`, `config/routes.rb` |
| Servicio y job (idempotente: sale con `ready`, porque cada llamada se cobra) | `app/lib/flow/workshops/transcribe_recording.rb`, `app/jobs/flow/workshops/transcribe_recording_job.rb` |
| Pantalla: partial, JS, onda en barras, chip, locale | `app/views/workshop_rooms/_recording.html.haml`, `app/javascript/workshop_recording.js`, `application.css` (`.waveform`), `EstilosHelper` |
| La guarda `[GRABAR]` y el wav voz → silencio → voz | `script/capture_screens.js`, `script/fake_audio.wav` |
| Los documentos (tarea 8) | `CLAUDE.md`, `docs/superpowers/specs/2026-10-08-grabacion-de-la-mesa-design.md`, este archivo |

### Lo que CLAUDE.md dice ahora (tarea 8)

- Los lugares que preguntan `arrival?` ya **no llevan número**: CLAUDE.md los enumera
  por lo que el chequeo hace (controllers que rechazan, caras de la sala, panel
  «Tu mesa», lecturas que devuelven nada). El conteo viejo ya estaba corto.
- **Tres** proveedores (`FLOW_AI_PROVIDER`, `FLOW_EMBEDDINGS_PROVIDER`,
  `FLOW_SPEECH_PROVIDER`), y por qué la tercera no se declara.
- **Once** guardas que cuentan; pisos `36, 250, 300, 100, «al menos una», 66, 71,
  275, 270, 2, 2`. `[GRABAR]` es exacto, como `[DRAFT]`.
- Una sección nueva en «El taller» con lo que no se lee del código (onda en DOM,
  `data-level`, el JS que no para en `turbo:before-render`, la navegación que pierde
  el audio, la tarjeta que no se refresca, el contexto seguro).

### Números medidos (los que más cuesta reconstruir)

- **Contrato de Deepgram:** `results.channels[0].alternatives[0]` →
  `transcript`, `confidence`, `words[]` (`word`, `punctuated_word`, `start`, `end`,
  `confidence`, `speaker`, `speaker_confidence`); `results.utterances[]` →
  `speaker`, `start`, `end`, `transcript`, `confidence`, `words[]`;
  `metadata` → `duration`, `request_id`, `model_info`. Con audio de duración cero
  contesta **200 con texto vacío**. Query usada:
  `model=nova-3&diarize=true&utterances=true&punctuate=true`.
- **Tamaño de la transcripción:** utterances normalizadas **0,040 MB por 20 min**
  contra **0,80 MB** crudas (veinte veces menos). `speaker_confidence` de la
  utterance = mínimo de sus palabras.
- **Bitrate:** Chromium graba a **115 kbps** por default (17,4 MB por 20 min); el
  `MediaRecorder` va con **32 kbps** explícitos (~4,8 MB).
- **Cuerpo subido por `[GRABAR]`:** ~**22,4 KB** (22.445 idear, 22.575 evolución)
  contra un piso de **2000** bytes: unas diez veces de margen.
- **Serie de la onda** (muestreo cada 100 ms, `data-level`): pico ~**0,605** contra
  `VOZ_MINIMA = 0,05`; el hueco da **17** muestras seguidas bajo `SILENCIO_MAXIMO =
  0,01` contra `MUESTRAS_DE_SILENCIO = 8`; ruido del opus en el hueco ≤ 0,006; la
  voz de la cola arranca en 0,013. La ventana de muestreo **termina dentro de la
  segunda voz**, así que la corrida sale del hueco interior y no de una cola muda.
  El wav dura 6,50 s, 16 kHz mono: voz 2,5 s (`slt`) → 1,5 s de silencio → voz 2,5 s
  (`awb`). La estimación teórica "~15 muestras" quedó en un comentario junto al
  valor medido (17): las dos son ciertas, pero juntas confunden.
- **Costo:** la única llamada real de la tarea 7 fue ~0,0006 USD.

### Qué mutación puso en rojo a qué

| Mutación | Rojo en |
|---|---|
| T1: se comenta `return resolve(declarado) if declarado` | speech_provider_spec, el ejemplo de la variable declarada (1 falla) |
| T1: se comenta `return provider if provider.transcription?` | el ejemplo de identidad del proveedor de chat |
| T2: `transcribe` con `duration`/`request_id`/`model` en nil | **verde** con el diseño inicial; tras extraer `transcription_from`, el ejemplo nuevo (`expected: 16.906187`) |
| T3: `== 1` → `<= 1` en `collapsed_diarization?` | «la condición es una igualdad y no un `<=`» |
| T3: `presentes` → `count` | sólo el ejemplo de "dos sentados, uno ausente"; los otros cuatro verdes |
| T3: `return if true` en `idea_matches_room` | sólo el ejemplo de `errors[:idea]` |
| T4: se borra `unless group` | "admin sin mesa 403" |
| T4: se borra `group.arrival?` | "mesa de llegada 403" |
| T4: se borra `workable?` | "vínculo cerrado 409" |
| T4: se saca `split(";")` del content-type | el ejemplo agregado del `codecs` |
| T4: `WorkshopRecording.unscoped.find_by!` / `find_by!` sin scope | el ejemplo de otra empresa (con audio adjunto) y el de otra sala |
| T4: `where(workshop_group:)` fuera de `show` | el ejemplo de otra mesa (1 falla) |
| T4: `find_by!` → `find_by` para `idea_id` | "bogus → 404 y sin fila" |
| T5: se borra `return false if recording.status == "ready"` | "idempotente" (8 ejemplos, 1 falla) |
| T5: `rescue TranscriptionFailed` → `rescue StandardError` | **verde** al principio (nada lo distinguía); con el ejemplo del `NoMethodError` rojo (`expected "transcribing" got "failed"`) |
| T6: `load_recordings` sin el filtro de mesa | "no lista las grabaciones de OTRA mesa" |
| T6: `%details{ open: i.zero? }` → `%details` | "la última grabación abre su transcripción sola" |
| T7-B: `mismoNodo = false` (el `start()` no repinta en el morph) | `[GRABAR]`, **fase del morph**: «el botón dice "Grabar" (antes "Parar")»; cae de 2 a 0 |
| T7-C: `nivel()` devuelve `Math.random() * 0.3` | `[GRABAR]`, **por la corrida de silencio** ("1 muestras y hacen falta 8"), NO por el pico |
| T7-A (reemplazo): se borra `caja.dataset.level = ...` | `[GRABAR]`, **por el pico** ("0.000", "AnalyserNode no está leyendo"): espejo exacto de C |
| T7-D: se comenta la llamada de evolución | `[GRABAR] sólo 1 de 2 caras`, cae de 2 a 1 |

A y C son independientes: C falla donde A pasa y al revés, que es lo que prueba que
las dos aserciones de la onda miden cosas distintas.

## 4. Intentos fallidos (los que no funcionaron)

- **Medir el español y la diarización con audio real: BLOQUEADO.** El archivo
  (veinte segundos de dos personas hablando español) lo tenía que producir Raúl y
  no llegó. No se sintetizó un sustituto ni se llamó a la API. El resultado está
  escrito en la spec como un `Ojo:` fechado: las dos mediciones que hay (un sondeo
  de diseño con dos voces `flite` y la llamada de la tarea 7 con el wav del repo)
  dieron **un solo `speaker 0`** (`speaker_confidence` 0,196–0,687 y 0,69 / 0,0),
  y las dos son **voces de síntesis**, que un diarizador no separa por razones que
  no dicen nada del proveedor. **Inconcluso, riesgo 1 abierto.** El español nunca
  se midió: `flite` no habla otro idioma.
- **La mutación A original de la tarea 7 era imposible.** Borrar las dos líneas
  `impedimento()` de `start()` quedó **verde**: el recorrido corre en `localhost`
  (contexto seguro) con micrófono falso, y la rama nunca se alcanza. Se reemplazó
  por borrar `caja.dataset.level`. La detección de contexto seguro **no tiene
  testigo**.
- **Un refresco que nunca existió.** La spec decía que la tarjeta se refrescaba con
  "el mismo mecanismo de `arrival_live.js`". No se construyó (no hay frame, ni
  `data-live`, ni poller). `[GRABAR]` pasaba igual porque su primera versión
  esperaba una `details` en una página que nunca se refresca; se arregló
  re-visitando con `Turbo.visit` (hasta 20 veces, ~2 s). Un `[GRABAR]` verde no
  prueba el refresco. Hay una nota fechada en la spec.
- **El `start()` que no repintaba.** Con retorno temprano en un morph, el servidor
  devolvía el botón en «Grabar» y el micrófono seguía abierto: quien veía la onda
  moverse apretaba "Grabar" y cortaba. Arreglado en dos rondas (`repintar()` desde
  el estado del módulo; la bandera `subiendo`; la onda sólo si hay `analizador`).
- **Mutación del `rescue` que no discriminaba** (T5): el único ejemplo de fallo
  lanzaba `TranscriptionFailed`, que `StandardError` también atrapa. Hizo falta un
  proveedor que lance `NoMethodError`.
- **Estado compartido en el proveedor** (`last_metadata`): una carrera entre hilos.
  Se reemplazó por un valor de retorno (`Data`).
- **El helper de sesión del plan era inventado** y cuatro conteos estaban mal
  (commit `3d9dd49`); la mutación B del plan nombraba código viejo.
- **El conteo de `arrival?` del brief (ocho) no cierra** y ningún número es estable
  (depende de cómo se agrupen las cuatro lecturas de `WorkshopRoomsController`):
  por eso CLAUDE.md enumera y no cuenta. `grep -rn "arrival?" app` es la verificación.

## 5. Próximos pasos

1. **Conseguir los veinte segundos de audio real** (dos personas, español) y correr
   el comando del paso 1 de la tarea 8 (`curl` a `/v1/listen?...&language=es`, ver
   el brief). Es lo único que cierra el riesgo 1, y **decide si C2 vale la pena
   como está diseñada**. Escribir el resultado como un `Ojo:` fechado encima del de
   hoy.
2. ~~**La revisión final de la rama entera.**~~ **Hecha**, en el modelo más
   capaz y con cuatro pasadas. Veredicto inicial: **no lista para mergear**, con
   **1 Critical** —el barrido de mesas vacías de `AssignGroups#seat!` destruía
   grabaciones y **purgaba su audio**, en silencio, en cualquier taller de
   idear— más 6 Important. Una sola tanda de arreglos cubrió **16 ítems** (6
   commits), y la re-revisión acotada los dio por los 16 ADDRESSED sin breakage.
   Los *minors* diferidos de abajo quedaron triados: **ninguno bloquea el
   merge**.

   **Los residuales que la re-revisión dejó abiertos, y uno importa:**

   - **La cara de EVOLUCIÓN tiene el mismo defecto que se arregló en idear.**
     `_evolution.html.haml` deja que `ideas.empty?` reemplace la sala entera, y
     el render de grabación vive adentro del `else`. Así que una mesa sentada en
     un taller de evolución **sin idea trabajable** —convocatoria a mano, o sus
     ideas eliminadas/retiradas, porque `workable_ideas` filtra con
     `Idea.alive`— no sólo no graba: **pierde el acceso a transcripciones que
     ya grabó**, mientras el POST las aceptaría igual. Es la misma
     contradicción con la spec («graba quien pasa `work?` y está sentado en una
     mesa que no es la de llegada») contra la que se arregló el ítem 4.
     **NO se arregló acá a propósito**: el proceso tiene una sola tanda, y un
     render movido sin su ciclo de revisión es cómo se deshace el cuidado del
     resto. Es el mismo arreglo que el ítem 4 —sacar el render del `else`— y
     **es el primer candidato de un round más**.
   - `.env.example` documenta los ejes de chat y de vectores y **omite el de
     voz**. Es el único documento cuyo trabajo es decir cómo se enciende un eje.
     Tres líneas comentadas.
   - **Un fallo de subida le dice a la mesa lo equivocado**: el JS pinta «No se
     pudo transcribir.» cuando lo que pasó es que se perdió la grabación entera
     (`trozos` se limpia antes del `fetch`). Hace falta un texto propio.
   - **El comentario de `crear!` atribuye a la transacción más de lo que
     compra**: Rails 7.1 difiere el upload físico a `after_commit`, así que un
     fallo de disco revienta DESPUÉS del commit y deja la fila `pending` sin
     archivo igual. Lo que la transacción sí compra es atomicidad de fila.
   - **El ejemplo del Critical fija la fila pero no el blob**: la factory no
     adjunta archivo, así que la mitad `purge_later` del hallazgo de pérdida de
     datos **no tiene testigo**.
   - `workshop_recordings_controller.rb:27` dice «**cuántos** son lo dice
     CLAUDE.md» y CLAUDE.md se niega a dar un número a propósito; va «cuáles».
   - **Borrar un taller entero** cascadea todas las grabaciones y su audio bajo
     un «Taller eliminado.» pelado. Simétrico con cómo trata los borradores, o
     sea preexistente, pero es el otro lugar donde aplicaría el aviso del
     ítem 7.
3. ~~**Dos comentarios del código con el número viejo**: `workshop_drafts_controller.rb`
   y `workshop_rooms/_ideation`.~~ **Hecho en la revisión final**, y eran tres: el
   del spec de la pantalla de la sala decía «el octavo lugar». Los tres remiten
   ahora a CLAUDE.md, como ya hacía el controller de grabaciones; en el código no
   queda ningún número.
4. **C2 y C3 siguen pendientes.** C2 no puede diseñarse con confianza mientras las
   etiquetas de hablante estén sin verificar.
5. Antes de mostrar la grabación desde un teléfono: **HTTPS**. Hoy no hay
   grabación fuera de `localhost` y ninguna corrida verde lo dice.
6. Retención del audio: se conserva a propósito (re-transcribir es cómo se arregla
   una diarización colapsada) y **nadie escribió la política**.

### *Minors* diferidos (de `progress.md`, líneas «minor (deferred)»)

- T2: «canneada» en un comentario de `fixture.rb` no es español estándar (viene del
  plan y está en los dos lados).
- T3: `speakers` devuelve `[nil]` si una utterance no trae `"speaker"` y se
  anunciaría como «diarización colapsada». Teórico: Deepgram con `diarize=true`
  siempre manda `speaker`.
- T3: `db/structure.sql` churnea dos líneas por migración (`\restrict` /
  `\unrestrict` de pg_dump 17+): ruido.
- T3: el CHECK de Postgres no está ejercitado (el ejemplo del status inválido
  prueba la validación de Ruby).
- T3: nada prueba el `SET NULL` a nivel base (borrar una idea y ver la grabación
  sobrevivir con `idea_id` nil).
- T4: el job stub no llevaba `frozen_string_literal` (la tarea 5 lo restauró).
- T4: ~~los dos comentarios «los otros seis lugares» están viejos (ver §5.3).~~
  Arreglado en la revisión final, y eran tres.
- T6: ~~si la mesa navega a una pantalla SIN el contenedor mientras graba, `caja`
  queda en null y la grabación sigue corriendo (Turbo no dispara `pagehide`); al
  volver, `subir()` descarta el audio porque `url` es null.~~ **Era peor que
  eso, y la revisión final lo arregló:** el audio no se descartaba, se subía a
  donde hubieras aterrizado. `start()` hace `caja = encontrado` ANTES del
  `rec.stop()`, así que la subida leía el `recording-url` de la pantalla nueva y
  la conversación de la mesa A quedaba guardada como grabación de la mesa B
  —reproducible por sus integrantes—; en evolución, un clic a otra idea la
  etiquetaba con la idea nueva. Hoy el destino se captura en `arrancar()`
  (`urlDeSubida`, `ideaDeSubida`). Lo que SÍ se pierde es cerrar la pestaña
  estando en una pantalla sin contenedor, y por el límite ya conocido: un
  `fetch` sin `keepalive` no sobrevive al unload, y con `keepalive` el tope son
  64 KB.
- T6: tras un morph las barras quedan en blanco un instante (idiomorph resetea sus
  `height` en línea) y el historial se rellena en los frames siguientes.
- T7: una segunda corrida de `make screens` sin `make seed` falla `[CHECKIN]`
  (Lucía Llegada queda sentada). Preexistente y documentado.
- T7: el sello del morph es testigo débil (el tick de 1 s reescribe el cronómetro
  dentro de la espera); el texto del botón es la única aserción fuerte de esa fase.
- T7: `Math.max` sobre una serie con NaN devuelve NaN y `NaN < VOZ_MINIMA` es
  false, así que el chequeo del pico se saltea; la corrida de silencio sí lo caza.
- T7: la ruta interceptada del POST queda registrada tras un `return` temprano,
  por el resto de la corrida (sólo continúa pedidos).
- T7: ~~en el bloque de comentario conviven la estimación teórica («~15 muestras») y
  el valor medido (17).~~ La estimación se borró en la revisión final: queda el 17
  medido.

### Si hay que repetir algo de esto

- Mutar una guarda: restaurar con `cp` de un backup tomado **después** del arreglo;
  `git checkout` deshace el arreglo, no la mutación.
- `make seed` antes de cada `make screens`; `make yarn-build` antes de ambos si se
  tocó `app/javascript/` o Tailwind.
