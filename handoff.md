# Handoff — los tres diferidos del taller, y un doc que mentía al revés (2026-10-06)

## 1. Objetivo

Cerrar el alcance ya construido de los talleres —los tres hallazgos diferidos
de la rama de la sala de la mesa— y corregir los dos documentos que afirmaban
que pgvector todavía esperaba su columna.

No se abrió ninguna de las tres piezas grandes que quedan del taller (B, C y D
de la sección 5): son cada una una spec propia, y dos necesitan infraestructura
que el repo no tiene.

## 2. Estado actual

**Todo pusheado y verificado contra el remoto.** `master` está en `ea2a493`,
confirmado con `gh api repos/ribarahonaa/innk_flow/commits/master` y **no** con
`git rev-parse origin/master`, que lee una foto local — es la lección que el
handoff anterior dejó escrita después de afirmar «nada pusheado» durante dos
sesiones siendo falso.

**Suite en 1633 ejemplos, 0 fallas** (eran 1628 al empezar: +5 nuevos).
**`make screens` verde:** 76 capturas, sin errores de JS ni respuestas >= 400.
Los nueve contadores sobre su piso, con `[BANDA]` exacto en 71:

```
[RITMO] 39 · [RELLENO] 296 · [PASTILLA] 794 · [CRITERIO] 195 · [LIVE] 1
[RIEL] 71 · [BANDA] 71 · [SOMBRA] 299 · [CAMPO] 291
```

`[PASTILLA]` subió de 689 a 794 sobre la misma siembra, que es el crecimiento
ya documentado: el recorrido le pide cosas a la IA de verdad y después
fotografía `/admin/ai_runs`. Es un piso y no un techo, así que es inofensivo.

| | Qué | Commit |
|---|---|---|
| ✓ | Los docs decían que pgvector esperaba su columna, y ya estaba | `ac9f2dd` |
| ✓ | El armado no linkea el desafío que el gestor no alcanza | `d65f6f3` |
| ✓ | La cara de idear dice que la mesa no tiene ideas | `2321ec8` |
| ✓ | Los asientos se leen por nombre, y no como salgan | `ea2a493` |

### Lo que NO se tocó, y es decisión no deuda

De los diferidos de la rama de la sala sobreviven dos, los dos a propósito:

- **`[REFERENCIA]` no mide la columna de la sala.** `revisarReferencia` se
  llama desde la rama de `[ZONAS]` y desde la de testing, o sea sólo en las
  pantallas de módulo. Su límite declarado es ése: una mesa muy grande queda
  detrás de su propio scroll.
- **El `closed_reason` del selector nombra la fase del desafío a un gestor que
  no lo alcanza.** Se dejó: es el motivo por el que esa sala no se puede
  trabajar —información del taller, no sólo del desafío— y esconderlo volvería
  muda la pantalla justo en lo que el selector existe para decir.

Y las tres decisiones abiertas de antes siguen abiertas: el morado de INNK
(`#8520BD` declarado y sin un consumidor), un proveedor de embeddings con
crédito, y Jev/typesafe.ai como tercera capacidad.

### Un hueco NUEVO, anotado y no arreglado

**`workshop_room_spec.rb:143` ordena la columna de referencia por el `index` de
frases crudas** («El desafío» antes que «Tu mesa») sobre el HTML servido
completo. Discrimina bien hoy, y es frágil mañana: cualquier copy nuevo en la
columna central que contenga una de esas dos cadenas lo rompe por colisión, no
por un defecto real. Pasó en esta sesión (ver sección 4). No se reescribió: el
ejemplo sigue probando lo que promete, y arreglarlo era alcance de más.

## 3. Archivos y cambios

**Docs** (`ac9f2dd`): `README.md` y la sección «Estado y backlog» de `CLAUDE.md`
afirmaban que el orden era «proveedor de embeddings primero, columna `vector`
después» y que agregarla antes sería guardar algo que nada puede llenar. El
camino entero está embarcado y se verificó pieza por pieza antes de reescribir:
`idea_versions.embedding vector(1024)` (`db/structure.sql:456`), el índice HNSW
`index_idea_versions_on_embedding` con `vector_cosine_ops` (1761),
`EmbedVersionJob` encolado desde `PublishVersion:75`, `Providers::Voyage` y
`Providers::Openai` heredando de `HttpEmbeddings`, `make embeddings`, y
`DetectDuplicates#local?` eligiendo el camino con la consulta
`embedding <=> …::vector` acotada a `NEIGHBOURS`. Lo que falta es la cuenta, no
el código. En `CLAUDE.md` quedó la nota con fecha al estilo del resto del
archivo.

**El link del armado** (`d65f6f3`): `app/views/workshops/_assembly.html.haml`
gana una variable `alcanza = policy(link.challenge).show?` por vínculo, la
misma forma que ya usan `workshop_rooms/_referencia` y `workshops/_room_picker`.
Dos ejemplos nuevos en `spec/requests/workshops_spec.rb`, el negativo y su
control positivo.

**El vacío de idear** (`2321ec8`):
`app/views/workshop_rooms/_ideation.html.haml` dibuja la sección SIEMPRE, con un
`card-body.empty-state` cuando la mesa no tiene ideas. A diferencia de la cara
de evolución el vacío NO reemplaza el trabajo: el formulario va abajo igual. En
`spec/requests/workshop_sala_idear_spec.rb`, el ejemplo que ya existía pasa a
aseverar lo que su nombre prometía, más un control positivo nuevo.

**El orden de los asientos** (`ea2a493`):
`app/views/workshops/_group_body.html.haml` y `_my_group.html.haml` ordenan por
nombre **en Ruby** (`sort_by { |seat| seat.user.name }`). Dos ejemplos nuevos en
`spec/requests/workshop_mesas_spec.rb`, uno por partial, sobre el HTML servido.

## 4. Intentos fallidos

**Tres cosas salieron mal y las tres enseñan algo.**

- **El arreglo obvio del orden era un `order` de SQL, y rompía lo que ese
  código existe para proteger.** Las dos rutas que renderizan `_group_body` —la
  pantalla del taller (`workshops#show`) y `WorkshopsController#arrival`—
  precargan con `includes(workshop_group_members: :user)`, y el endpoint lo hace
  explícitamente porque es el único que se pide solo cada cinco segundos («sin
  precarga cuesta 3 + N consultas por pedido», dice su comentario). Un `order`
  sobre la asociación dispara otra consulta y **descarta la precarga**. Por eso
  el orden va en Ruby sobre la asociación ya cargada, en los dos partials, con
  un idioma solo: dos idiomas para lo mismo es lo que este repo viene evitando.
  Se descartaron también un scope `ordered` con `joins(:user)` (mismo problema)
  y un default scope en la asociación (toca `AssignGroups`, la validación de
  UNIQUE, `.size` y `.any?`: blast radius desproporcionado).
- **El primer copy del `empty-state` rompió un ejemplo ajeno por colisión de
  texto.** Abría con «Tu mesa todavía no creó ninguna idea», y «Tu mesa» es el
  título de `workshops/_my_group`, que se sirve en la columna de referencia de
  esa MISMA pantalla. `workshop_room_spec.rb:143` ordena esa columna comparando
  `response.body.index("El desafío")` contra `index("Tu mesa")`, así que
  encontraba mi encabezado en la columna central y el orden salía invertido
  (5155 contra 6164). Dos cosas: el texto se reescribió a «Ninguna idea en esta
  mesa todavía», que además espeja el de la cara hermana («Ninguna idea para
  trabajar») y no dice lo mismo en dos bloques de una pantalla; y la fragilidad
  del ejemplo quedó anotada en la sección 2 sin tocarlo.
- **La indentación del comentario en HAML rompió el loop y se llevó dos
  ejemplos que estaban en verde.** Al insertar siete líneas de `-#` arriba del
  `each` de `_group_body`, la primera quedó a 4 espacios y las seis siguientes a
  6, y el `- ... each do |seat|` terminó al mismo nivel que su `%li`: el cuerpo
  del loop dejó de estar adentro. Síntoma: `workshop_mesas_spec` pasó de 2
  fallas a 3, y las dos nuevas eran ejemplos del frame de la llegada que no
  tenían nada que ver con el cambio. **Leer el archivo con `sed`/`cat -A`
  después de insertar un bloque de comentarios en HAML, no confiar en que el
  reemplazo de texto preservó el nivel.**

**Y una cosa que NO falló y conviene saber:** `make yarn-build` se corrió antes
de `make screens` por disciplina, pero no hacía falta: el cambio no agregó
ninguna clase que Tailwind no tuviera ya (`card`, `card-body`, `empty-state`,
`field-list__item`) ni tocó `app/javascript/`. La regla sigue valiendo igual
—es más barato correrlo que descubrir que el recorrido validó una app distinta—.

## 5. Próximos pasos

**No queda trabajo de implementación abierto.** Lo que sigue son tres piezas
grandes del taller, y cada una es una spec propia. La sala de la mesa era **A
de cuatro**; faltan las otras tres, en este orden de dificultad:

1. **B — guardado automático como versión nueva.** Es la única de las tres que
   NO necesita infraestructura nueva. Choca de frente con `WorkshopProposal`:
   hoy la mesa propone y el autor decide, y un autosave directo borra esa regla.
   Son **dos** las decisiones que hay que tomar antes de escribir una línea, y
   la segunda es la que es fácil no ver:
   - qué pasa con las propuestas pendientes cuando el autosave publica;
   - y el **coalescing de versiones**. `idea_versions` es contenido INMUTABLE
     con un `embedding vector(1024)` por fila, y publicar encola un
     `EmbedVersionJob`: un autosave ingenuo escribe una versión por tanda de
     tecleo y un job de embeddings por cada una. Sin decidir cómo se agrupan,
     B llena la tabla y la cola.
2. **C — dictado por voz y resumen de la reunión con IA.** Pide un TERCER eje de
   proveedor: no hay speech-to-text en el repo y Anthropic no lo expone. Las
   opciones ya medidas: Web Speech API del navegador (gratis, sólo Chrome,
   calidad floja), un proveedor nuevo con credencial y costo
   (Whisper/Deepgram/AssemblyAI), o notas tipeadas más resumen con el chat que
   ya está. Si se elige proveedor nuevo, el patrón es el de embeddings:
   capacidad aparte con su propia variable, no un `FLOW_AI_PROVIDER` más.
3. **D — videollamada.** Se parte en DOS respuestas de órdenes distintos, y la
   diferencia es una decisión y no un problema técnico. **Embed de un tercero**
   (Jitsi, Daily, Whereby en un iframe): un iframe, un endpoint de token si las
   salas son privadas, y elegir proveedor. **WebRTC propio:** eje de
   infraestructura nuevo, porque **este repo no tiene websockets** —verificado:
   no hay `app/channels`, y lo único de ActionCable en `config/` son las líneas
   comentadas que dejó el generador de Rails; `cable.yml` existe y nadie lo
   usa—. Es exactamente por eso que la lista de llegada se refresca con un
   `turbo-frame` que se pide solo cada cinco segundos y no por un canal. La
   señalización WebRTC exige ese canal, más un TURN server, y cambia el
   despliegue. Tampoco hay `getUserMedia` ni `MediaRecorder` en el repo.

### Cuánto cuestan, con la tasa medida de este repo

La base no es una corazonada: son las seis tandas del taller ya entregadas,
medidas con `git`. Cada una es **una jornada de sesión**, y los días pico
fueron 64, 55 y 53 commits.

| Tanda entregada | Commits | Archivos | Líneas + |
|---|---|---|---|
| El check-in por QR (`ac6110d`) | 31 | 42 | 5.339 |
| La mesa de llegada en vivo (`cd943eb`) | 18 | 15 | 1.501 |
| La sala de la mesa, o sea A (`8579e87`) | 17 | 34 | 1.848 |
| El taller arma sus mesas (`415a7b9`) | 10 | 30 | 1.251 |
| Borrar una mesa (`ff9184d`) | 2 | 7 | 228 |
| Nombres a inglés (`f3c01e4`) | 1 | 12 | 168 |

Contra esa tasa, y **con las decisiones ya tomadas**:

| | Estimación | Commits |
|---|---|---|
| B autosave | 2–4 h, una sesión | 15–25 |
| C voz + resumen | 4–8 h, dos sesiones | 35–50 |
| D embed de un tercero | 1–2 h | 5–10 |
| D WebRTC propio | sin estimar: días, y sería adivinar | — |

**B + C + D por el embed: 7 a 14 horas, dos a cuatro sesiones.**

Tres cosas que explican el número mejor que el número:

- **Lo que no se puede comprimir es la verificación.** `make spec` tarda 2m25s
  y `make screens` entre 5 y 8 minutos; B y C juntas necesitan 15–25 corridas.
  Son 1 a 2 horas de espera pura, y están incluidas.
- **Lo que no se puede predecir es cuántas guardas aparecen incapaces de
  fallar**, y en este repo ése es el costo real: la rama del rediseño encontró
  ocho, cuatro de ellas sólo en la revisión final, y esta misma sesión encontró
  dos más (sección 4). Nada de eso estaba en ninguna estimación previa.
- **Dónde es más probable pasarse de largo: C.** `getUserMedia` y
  `MediaRecorder` no tienen UN precedente en el repo, ningún spec de Ruby ve un
  bug de captura de audio, y darle una guarda a `make screens` pide flags de
  medios falsos en Chromium que nunca se usaron acá. Si algo se va al doble, es
  eso. Lo que sí está es ActiveStorage (`has_one_attached` en `Report` y
  `IdeaAttachment`), así que subir el audio tiene camino hecho.

**C muy probablemente cruza un límite de contexto**, así que esas 4–8 horas
llegan partidas en dos con un handoff en el medio. No cambia el total.

Y el tiempo que NO está en ninguno de esos números: las decisiones. Mientras B
no tenga su regla de propuestas pendientes y su coalescing, y C y D no tengan
proveedor elegido con credencial y costo, el tiempo de implementación es cero.

Y tres decisiones abiertas que no son tareas:

- **El morado de INNK** (`#8520BD`). `--color-accent` declarado y sin un solo
  consumidor. Si la respuesta es «no», el estado de hoy es el correcto. Si es
  «sí», lo más chico que cumple la spec es pintar la entrada activa del riel, y
  eso pide una escalera nueva más re-medir dos contrastes; repuntar `--accent`
  entero toca ~51 lugares, `a { color: … }` incluido.
- **Un proveedor de embeddings con crédito.** Voyage autentica y no tiene
  inferencia habilitada: 500 en todo pedido, incluso con un modelo inexistente.
  El código está entero (ver sección 3).
- **Jev / typesafe.ai como tercera capacidad.** El bloqueo real es la waitlist.
  Antes hay una decisión de producto: las dos tareas que mejor encajan por forma
  exigen `reason` en texto, que es justo lo que Jev no hace.

**Lo que queda sin vigilancia**, anotado en `CLAUDE.md` con los otros huecos:
`--card-fs`, `[REFERENCIA]` en la sala de la mesa, el riel a 414px, la regla de
la etiqueta a la izquierda y el PDF de reportería. Se le suma el de la sección
2: el orden por `index` de frases crudas en `workshop_room_spec.rb:143`.

**Y los dos diagramas de `archify` siguen desbordando a lo alto** —arquitectura
1345px y proceso 1688px contra un viewport de 900—, medido y no arreglado,
porque `deliver` da verde y `visual-check` se saltea en silencio. Arreglarlo es
redistribuir el Y y subir el `viewBox`, o sacar contenido: decisión de diseño.

**Limpieza pendiente, trivial:** cinco ramas locales con 0 ahead de `master`
(`checkin-por-qr`, `lista-de-llegada-en-vivo`, `mesa-de-llegada-retiene`,
`nombres-en-ingles`, `sala-de-la-mesa`), dos de ellas también en el remoto
(`origin/checkin-por-qr`, `origin/mesa-de-llegada-retiene`).
