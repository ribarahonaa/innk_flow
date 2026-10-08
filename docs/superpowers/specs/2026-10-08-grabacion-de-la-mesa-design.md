# La grabación de la mesa: la conversación se vuelve texto

## El problema

Una mesa de taller **conversa**. Hoy la sala sólo sabe recibir lo que alguien
teclea: el borrador de B guarda las teclas y el formulario publica una versión.
Lo que se dijo en voz alta no deja rastro, y quien escribe se pierde la mitad de
la discusión por estar escribiendo.

Lo que esto construye es el primer tramo del camino de la voz: la mesa aprieta
grabar, **ve la línea de sonido moverse mientras habla**, y después lee en
pantalla **qué se dijo y con cuánta confianza de hablante**. Convertir eso en una
idea es el tramo siguiente y no está acá.

La onda no es adorno: es lo único que distingue «está grabando» de «el
cronómetro corre con el micrófono tapado», y un cronómetro corre igual en los dos
casos.

## Alcance: esto es C1 de tres, y C era una de cuatro

La spec de A (`2026-10-02-sala-de-la-mesa-design.md`) fichó **C** como «dictado
por voz, resumen de la reunión con IA y "armar la idea desde el resumen"», en
una sola línea de tabla. Medida, C son **nueve piezas**, dos de ellas tocando
los cuatro lugares que pide un propósito nuevo. Para comparar: A y B fueron una
spec y un plan cada una, y B salió en 25 commits. C entera sería tres o cuatro
veces B, así que se parte.

| | Subsistema | Estado |
|---|---|---|
| **C1** | la mesa graba, se transcribe con hablantes, y la sala lo muestra | **esta spec** |
| **C2** | resumen de la reunión y «armar la idea desde el resumen» | pendiente, spec propia |
| **C3** | dictado al campo del formulario | pendiente, spec propia |

Dos cosas quedan decididas acá y condicionan las otras dos:

- **C1 estrena el cuarto eje de proveedor** y es la única de las tres con riesgo
  técnico real. Por eso va primero: si algo de C va a fallar, falla acá, y más
  vale saberlo antes de escribir las otras dos specs.
- **C2 no depende de C1 para desarrollarse.** Sus dos propósitos de chat corren
  sobre una transcripción pegada a mano. Lo que C1 le deja es de dónde sale esa
  transcripción en la vida real.

Y la condición de entrada de A vale igual: esto corre **con las mesas ya
repartidas**. Desde la mesa de llegada no se graba, con la misma guarda
(`arrival?`) que ya protegen las otras siete puertas de la sala — ésta es la
octava.

## Lo que se midió antes de diseñar, y por qué está acá

Casi todo lo que sigue sale de haberlo medido y no de haberlo supuesto. Los
números están en el cuerpo de la spec donde deciden algo; esta tabla es para
quien quiera saber qué está verificado y qué no.

| Pregunta | Respuesta medida | Cómo |
|---|---|---|
| ¿La cuenta de Deepgram tiene inferencia? | **sí**, HTTP 200 en 1,36s | POST a `/v1/listen` con un clip de 8s |
| ¿Cuál es la forma de la respuesta? | ver «El dato» | respuesta real, no documentación |
| ¿Deepgram acepta lo que produce `MediaRecorder`? | **sí**, `audio/webm` → 200 | POST del webm/opus del navegador |
| ¿Qué `mimeType` elige Chromium? | `audio/webm;codecs=opus` | `MediaRecorder` en la imagen del recorrido |
| ¿Funciona el micrófono falso en esa imagen? | **sí**, `Fake Default Audio Input` en `live` | `--use-file-for-fake-audio-capture` |
| ¿Cierra el camino de punta a punta? | **sí**: micrófono falso → navegador → Deepgram → la frase correcta | los tres pasos encadenados |
| ¿Cuánto pesa el audio? | **17,4 MB** por 20 min al default de Chromium | 115 kbps medidos |
| ¿Cuánto pesa la transcripción cruda? | **0,80 MB** por 20 min | extrapolado de la respuesta real |
| ¿Y normalizada? | **0,040 MB** por 20 min | la misma respuesta, recortada |
| ¿`%noloop` se honra en el micrófono falso? | **sí**: 12s grabados de un wav de 5s dan la frase UNA vez | transcrito; comparar el tamaño del blob NO discrimina |
| ¿El Figma tiene componente de audio? | **no**, ninguno | búsqueda en el design system |
| ¿Hay algún `canvas` en el repo? | **ninguno** | de ahí que la onda vaya en DOM |
| ¿Separa hablantes? | **NO SE SABE** | ver «La diarización, sin verificar» |
| ¿Transcribe español? | **NO SE SABE** | `flite` sólo habla inglés |

### La diarización, sin verificar — y es lo que elegimos el proveedor para hacer

Se eligió Deepgram **por la diarización**: quién dijo qué es la diferencia entre
un resumen que se lee y un muro de texto. Y es justo lo que el sondeo no pudo
confirmar.

Dos sondeos, los dos con dos voces sintéticas distintas de `flite`. El primero
devolvió **una sola utterance** con `speaker 0` y `speaker_confidence` 0,324. El
segundo, con las voces a tonos distintos y un segundo de silencio entre turnos,
partió bien en **tres utterances por pausa** — y las tres salieron otra vez
`speaker 0`, con `speaker_confidence` entre 0,196 y 0,687.

No distingo entre las dos explicaciones posibles con lo que tengo: que `flite`
con el tono corrido no mueva la estructura de formantes en la que un diarizador
se apoya —y la confianza baja apunta ahí, el modelo avisa que no está seguro—, o
que la diarización de nova-3 sea más floja de lo que promete. **Lo cierra un
audio real de dos personas hablando veinte segundos**, y eso no lo sintetiza
nadie: va como tarea del plan.

**Y tiene consecuencia de diseño, no es sólo una anotación: nada de C1 depende
de que la diarización funcione.** La transcripción se guarda y se muestra con
hablantes cuando los hay, y sirve igual sin ellos. Es la misma forma que
`DetectDuplicates`, que elige su camino según lo que el proveedor sabe hacer.

## La forma: el cuarto eje de proveedor

### Lo que se descartó, y por qué

- **Un propósito más por el `Runner`** (`transcribe_meeting` con su `AiRun` y su
  `AiSuggestion`). Pelea con la interfaz en los dos extremos:
  `Provider#complete(messages:, schema:)` no sabe expresar «la entrada son
  bytes de audio», y la salida no es una propuesta que alguien revisa —no tiene
  `apply!`, no hay pendiente, nadie la acepta—, así que habría que torcer
  `informativa?` para que no la ofrezca en ningún panel. La forma entera de
  `Tasks::Base` es sobre propuestas revisables.
- **El resumen del propio proveedor de voz.** AssemblyAI lo ofrece (LeMUR), y
  usarlo sería una segunda llamada de IA **sin rastro en `ai_runs`**, sin schema
  validado y sin modos asistido/automático: por fuera de toda la disciplina de
  `Flow::AI::Runner`. El proveedor de voz devuelve transcripción y nada más. Esto
  no es de C1 —el resumen es de C2— pero la puerta se cierra acá, que es donde
  se elige el proveedor.
- **La Web Speech API del navegador.** Gratis y sin credencial, y está hecha
  para un hablante dictando en vivo: no acepta un archivo, no separa voces, y en
  Chrome manda el audio a servidores de Google igual. Sirve para C3; para una
  reunión, no.
- **Streaming por WebSocket.** La mesa vería el texto al hablar, y el precio son
  tres cosas: una credencial llega al cliente, el audio **no pasa por Rails**
  —así que el blob y su `company_id` quedan fuera de la tenencia—, y la
  diarización en streaming es peor que la de archivo, que ve el audio entero
  antes de decidir. Encima pediría la primera infraestructura de websocket de la
  app: `turbo-rails` es sólo paquete de JS, no hay una sola `app/channels`, y la
  spec de la lista de llegada en vivo ya rechazó agregarla por una razón más
  débil que ésta.
- **Transcodificar en el servidor.** Innecesario, y medido: Deepgram acepta el
  `audio/webm;codecs=opus` que produce `MediaRecorder` tal cual. Habría
  significado meter ffmpeg en la imagen de Docker para nada.
- **Una clase base de proveedores de voz.** `HttpEmbeddings` existe porque hay
  **dos** adapters de embeddings. Hay un solo proveedor de voz; la abstracción
  se escribe cuando aparezca el segundo.

### El eje

Espeja `embeddings_provider` exactamente, porque es el mismo problema: una
capacidad que el proveedor de chat no tiene.

```ruby
# Flow::AI::Provider — la interfaz
def transcription? = false

def transcribe(audio:, content_type:, language:)
  raise NotImplementedError
end
```

```ruby
# Flow::AI — la resolución, con la misma cascada que los vectores
def speech_provider
  @speech_provider ||= build_speech_provider
end

# Si no se declara uno, se usa el de chat cuando sabe transcribir, y si no el
# fixture. Anthropic no sabe, así que sin declarar nada C1 corre contra el
# fixture y el camino entero funciona sin credenciales ni gasto.
def build_speech_provider
  declarado = ENV["FLOW_SPEECH_PROVIDER"].presence
  return resolve(declarado) if declarado
  return provider if provider.transcription?

  Flow::AI::Providers::Fixture.new
end
```

`reset_provider!` limpia los **tres**.

`Providers::Deepgram` sólo hace `transcribe`; su `complete` levanta
`ProviderUnsupported`, igual que hacen hoy los dos adapters de embeddings.
`Providers::Fixture#transcribe` devuelve utterances canneadas, determinista y
sin red.

**Son TRES variables de entorno y no una.** `FLOW_AI_PROVIDER` (chat),
`FLOW_EMBEDDINGS_PROVIDER` (vectores) y `FLOW_SPEECH_PROVIDER` (voz) son tres
capacidades distintas, y ningún proveedor tiene las tres: Anthropic no expone
embeddings ni transcripción, Voyage sólo vectores, Deepgram sólo voz. Con una
sola variable no se puede tener chat real y voz real a la vez.

## El dato

### La respuesta de Deepgram, medida

```
results.channels[0].alternatives[0] → transcript, confidence, words[]
  cada word → word, punctuated_word, start, end, confidence,
              speaker, speaker_confidence
results.utterances[]                → speaker, start, end, transcript,
                                      confidence, words[]
metadata                            → duration, request_id, model_info
```

### Qué se guarda, y qué no

**Las utterances normalizadas, no la respuesta cruda.** Medido: **0,040 MB**
por 20 minutos contra **0,80 MB**, veinte veces menos. Una fila:

```json
{ "speaker": 0, "start": 0.0, "end": 5.44,
  "transcript": "...", "confidence": 0.996, "speaker_confidence": 0.675 }
```

El `speaker_confidence` de la utterance es el **mínimo** de sus palabras: es la
señal de una diarización que no está segura, y el mínimo es el lado
conservador.

**Lo que se tira es reconstruible porque el audio se conserva.** Las dos
decisiones se apoyan: si algún día hace falta el detalle por palabra, se
re-transcribe. Y guardar el audio no es prolijidad — **re-transcribir con otros
parámetros es exactamente cómo se arregla una diarización colapsada**, y sin el
audio una transcripción mala es definitiva. El precio, declarado: una grabación
de voces queda guardada, y eso pide una política de retención que nadie
escribió.

**El texto plano se deriva, no se guarda.** Lo que C2 le va a dar al modelo es
la concatenación de las utterances; guardarlo aparte sería la segunda fuente que
el día que difiera miente.

### El modelo

```
workshop_recordings
  id, company_id            NOT NULL          → TenantScoped
  workshop_group_id         NOT NULL          → la mesa
  workshop_challenge_id     NOT NULL          → la sala
  idea_id                   NULL              → contexto, no pertenencia
  recorded_by_id            NOT NULL
  status                    NOT NULL + CHECK  → pending|transcribing|ready|failed
  utterances                jsonb NOT NULL DEFAULT '[]'
  duration_seconds          NULL
  provider                  NULL              → auditoría
  model                     NULL              → auditoría
  request_id                NULL              → el de Deepgram
  error                     NULL
  created_at, updated_at    NOT NULL
  has_one_attached :file                      → el audio
```

Clavijado como `WorkshopDraft` —`(workshop_group_id, workshop_challenge_id)`—
pero **sin índice único**: una mesa graba varias veces en una sesión. Índice
plano sobre ese par, más `company_id`.

`idea_id` guarda qué idea tenía la sala elegida al apretar grabar. Es
**contexto**, para que C2 no le dé la conversación sobre la idea X al borrador
de la idea Y; no es dueño del registro, y una reunión puede hablar de varias.

Las validaciones que `WorkshopDraft` ya tiene y acá valen igual: la mesa y la
sala tienen que ser del mismo taller (`group_and_room_share_workshop`) y la idea
tiene que ser de esa sala (`idea_matches_room`). Las FK compuestas sólo atan a
la misma **empresa**, así que esas dos reglas no las cubre Postgres.

**Las columnas de auditoría existen por algo concreto.** A diferencia de los
embeddings, **transcribir se cobra por minuto**, y alguien va a preguntar cuánto
salió y con qué modelo. El precedente es `idea_versions.embedding_model`: el
repo ya guarda «con qué modelo se produjo esto» al lado del artefacto, en vez de
inventar una tabla de auditoría. De paso, es lo que le deja a la pantalla decir
que una transcripción salió del fixture — sin eso, alguien lee texto canneado
como real.

### Tenencia y quién escucha

El blob de Active Storage **no tiene `company_id`**: la tenencia la lleva
`workshop_recordings`, igual que `IdeaAttachment` y `Report`.

El audio se sirve por un controller propio con `send_attached_file` de
`ApplicationController`, autorizando contra la sala. No por `rails_blob_path`, y
el comentario de `IdeaAttachmentsController` ya explica por qué: ese camino
«verifica la firma del blob y nada más: sin sesión, sin membresía, sin Pundit y
sin tenant, con una firma que no vence». Y como `config.active_storage.draw_routes
= false`, **no existen rutas públicas de blob**: no hay puerta de atrás que
esquivar.

`send_attached_file` ya levanta `RecordNotFound` si no hay archivo adjunto, que
es el caso real de una fila creada antes de adjuntarle nada.

## El navegador

### El estado vive en el módulo, no en el DOM

Acá C1 **se aparta de sus dos hermanos a propósito**, porque copiarlos corta
grabaciones:

- `arrival_live.js` **para** en `turbo:before-render`: un temporizador apuntando
  a una pantalla muerta está mal.
- `workshop_draft.js` **descarga** en `turbo:before-render`: los últimos dos
  segundos no se pueden perder.
- C1 **no hace ninguna de las dos.** `turbo:before-render` dispara también en un
  morph, y un morph ocurre con cualquier POST que vuelva a la misma URL —alguien
  de la mesa apretando «Crear borrador»—. Pararse ahí cortaría la grabación de
  la reunión.

Lo que lo hace posible: el `MediaRecorder` y el arreglo de trozos son
**variables de módulo**, así que un morph que reemplaza el botón y el indicador
no los toca. El DOM es una **vista** del estado del módulo, y `turbo:load` la
vuelve a derivar, con la misma prueba de identidad de nodo que ya usa el
borrador (`workshop_draft.js`: si el nodo encontrado es el mismo objeto, ya está
cableado y no se toca).

Se detiene al apretar parar, y al descargar la página de verdad.

**Lo que NO se hace: parar con la pestaña oculta.** `arrival_live.js` no pide
nada con `document.hidden` —una pantalla proyectada está visible—, pero una
reunión puede tener la pestaña de fondo mientras alguien mira otra cosa. Queda
grabando. El riesgo es que el navegador suspenda o estrangule la pestaña; queda
declarado y sin medir.

### El bitrate va explícito

Medido: Chromium graba a **115 kbps** por default, o sea **17,4 MB por 20
minutos**. Para transcribir, 32 kbps de opus alcanzan de sobra y bajan eso a
~4,8 MB. El `MediaRecorder` se construye con `audioBitsPerSecond` explícito; el
default no es un número elegido.

### El contexto seguro, que es el riesgo de despliegue de C1

**`getUserMedia` no existe fuera de un contexto seguro.** `docker-compose`
publica el puerto 3001 en plano, así que: en la máquina que corre Docker es
`localhost` y funciona, y **en el teléfono o el notebook de al lado, por
`http://<ip-de-la-lan>:3001`, `navigator.mediaDevices` es `undefined`** y no hay
grabación posible. Y la app ya empuja a la gente a sus teléfonos: el check-in
por QR es exactamente eso.

C1 **no lo arregla** —es certificado o túnel, decisión de infraestructura— pero
**sí lo detecta y lo dice**: `!navigator.mediaDevices` se pregunta antes de
dibujar el control, y en vez del botón aparece el motivo. Un botón de grabar que
no hace nada es el control fantasma que este repo entero persigue.

Los otros dos fallos del navegador van por el mismo camino y con su propio
texto: **permiso denegado** (`NotAllowedError`) y **sin micrófono**
(`NotFoundError`).

### La forma de onda: barras del DOM, no un canvas

Mientras graba, la mesa ve **la línea de sonido en vivo**: sube cuando alguien
habla, se achata en los silencios. No es decoración — es la única forma de saber
que el micrófono está tomando algo, y sin ella la única señal es un cronómetro
que corre igual con el micrófono tapado.

**Va en barras del DOM y NO en un `<canvas>`, y el motivo es de este repo:** no
hay un solo canvas en el código, y un canvas es una caja negra para **todas** las
guardas —`[CLASES]`, `[CONTRASTE]`, `[SOMBRA]` no ven adentro—. La cultura de
este repo es que una guarda que no puede ver **da permiso**. Con barras, las
alturas quedan en el DOM, el color sale de la hoja, y se mide sin leer un pixel.

De paso resuelve dos cosas que un canvas complica: el color lo pone CSS en vez de
que el JS tenga que leer el token y re-leerlo al cambiar de tema, y un morph que
borre los `style` en línea se arregla solo, porque el bucle de dibujo reescribe
las alturas en el frame siguiente.

**El color es `--dato` / `--dato-fuerte`, no el acento.** Lo decide una regla que
ya existe: «el acento es de las ACCIONES. Los gráficos van con `--dato` /
`--dato-fuerte` […] pintar una barra con el violeta del botón de al lado la hace
leer como un control». Una onda es un gráfico.

**Cómo se mide el nivel.** `AudioContext` → `createMediaStreamSource(stream)` →
`AnalyserNode`, y un bucle de `requestAnimationFrame` que lee
`getByteTimeDomainData` y calcula el RMS. El `AudioContext` se **cierra** al
parar: sin eso queda uno por grabación.

**El umbral de silencio es de PRESENTACIÓN y se dice así.** Hace falta un número
para achatar una barra, y a diferencia del de la diarización —donde un corte
inventado habría decidido si se avisa o no— acá sólo decide un alto en pixeles.
El nivel **crudo** se publica igual en `data-level`, así que lo que se mide es la
causa y no el dibujo.

**Sigue moviéndose con `prefers-reduced-motion` activado**, y no es un descuido:
el repo ya tomó esta decisión para el spinner de la IA, con el motivo escrito en
la hoja —«es la ÚNICA señal de que la IA sigue trabajando, y quieto se lee como
colgado»—. La onda es exactamente eso para el micrófono.

### La UX: un control, y lo menos posible alrededor

La mesa está en una reunión, no operando un software. Lo que eso significa acá:

- **Un solo botón, y el botón ES el estado.** «Grabar» → la onda con el
  cronómetro y «Parar» → deshabilitado mientras sube. Ningún menú, ningún
  formato, ninguna opción de calidad.
- **La onda reemplaza al texto mientras graba.** Un texto que dice «Grabando» al
  lado de una onda que se mueve es decir dos veces lo mismo, y lo visual gana.
- **El silencio y la voz se ven en la onda misma**, no en una etiqueta aparte.
- **La transcripción de la última grabación abre sola.** Hacer clic para ver lo
  que acabás de grabar es un paso que no agrega nada; las anteriores quedan
  plegadas. Un `open` que pone el SERVIDOR sobrevive al morph —el guardia de
  `application.js` cancela la remoción del `open`, no su agregado—.
- **El proveedor, el modelo y la duración van chicos y apagados**, no en el
  encabezado: hacen falta para que un fixture no se lea como real, y no son lo
  que la mesa vino a ver.
- **Irse de la página mientras graba AVISA.** Un `beforeunload` mientras hay
  grabación en curso, porque lo que se pierde son los minutos que se hablaron
  (ver el límite más abajo).

### Las condiciones del Figma, medidas, y lo que no contestan

El Figma de INNK (`3xc9srW7XlOlM9jzZ3lGjC`, «General Rediseño») **no tiene
ningún componente de audio, grabación, onda ni micrófono** — verificado por
búsqueda: devuelve «Radio buttom» y «cursor and manipulator» de una
`Biblioteca-2023`, que es cómo se ve un *sin resultados* en una búsqueda difusa.
Así que no hay referencia de forma para esto; lo que hay son condiciones, y la
hoja de innk_flow ya las implementa:

| Condición del Figma | Cómo se cumple |
|---|---|
| Open Sans, 13px de base | ya es la única familia de la app |
| radios 10px campos/botones, 16px tarjetas | `--radius-field` / `--radius-box` |
| sombra en todo campo, borde reemplazado por sombra | `--shadow`, con **una** salida deliberada: `--borde-campo`, por el 3:1 de WCAG 1.4.11 |
| color hardcodeado, sin sistema de tokens | acá va por token, que es lo que deja existir el tema oscuro |

Y tres cosas que el Figma **no puede** contestar, así que las contesta el repo:

- **No hay tema oscuro en ningún frame**, y `capturar()` corre también en
  oscuro. La onda tiene que funcionar en los dos, y por eso su color es un token
  y no un literal.
- **Dos de sus colores no pasan el piso de 4,5:1** que mide `[CONTRASTE]` —el
  placeholder `#808080` da 3,95:1 y el blanco sobre `#F06653`, 3,12:1—, así que
  portar literales pone la corrida en rojo. La onda no porta ninguno.
- **El morado `#8520BD` sigue sin pintar un pixel en la app**, y adoptarlo es una
  decisión abierta que nadie tomó. La onda no la toma por su cuenta.

### Los estados: tres en el navegador y cuatro en la fila

No son una sola secuencia, y confundirlos es fácil porque la pantalla los
muestra seguidos:

- **Del navegador, y no se persisten:** `idle` → `grabando` → `subiendo`. Viven
  en el módulo de JS; nadie los consulta desde el servidor.
- **De la fila, y son los del CHECK:** `pending` → `transcribing` → `ready` |
  `failed`.

**Ojo: NADA los refresca solo, y hasta el 2026-10-08 esta línea decía que los
traía «el refresco del frame, el mismo mecanismo de `arrival_live.js`».** Ese
mecanismo no se construyó: no hay `turbo-frame`, ni `data-live`, ni poller. La
mesa sube, ve «en cola», y la tarjeta no se mueve hasta que navegue o recargue.
Medido —la guarda `[GRABAR]` tuvo que agregar su propio `Turbo.visit` en bucle
para que la tarjeta apareciera, o sea que pasa en verde mientras la app no
refresca—.

Hacerlo es ruta + acción + frame + poller, con su propia fase de guarda: una
tarea, no una línea. Y la alternativa barata está **descartada por una razón
dura**: Turbo 8 morfea llamando a `morphElements` sin `ignoreActiveValue`, así
que `syncInputValue` le devuelve al campo enfocado el valor del servidor — un
poller de página completa **le pisaría a la mesa lo que está tecleando** en el
borrador.

`pending` es el hueco entre «la subida aterrizó» y «el job arrancó», y existe
porque el POST contesta antes de encolar nada: sin ese estado, una grabación
subida y todavía sin job se leería como una que falló.

El indicador es **visible mientras graba**, con el cronómetro al lado: es la
única señal que tiene la mesa de que se está grabando. No es una opción de
diseño.

### La subida: un POST al parar

~4,8 MB por 20 minutos con el bitrate explícito. **El repo no declara ningún
límite de cuerpo** —se buscó en `config/`, el `Dockerfile` y el
`docker-compose.yml`, y no hay nginx en el medio—, así que entra. Ojo con esto
el día que haya un proxy adelante: ahí el límite lo pone él y 4,8 MB es
grande.

**Límite declarado:** si el navegador se muere en medio de la reunión, **el
audio se pierde entero** — a diferencia del borrador, que autoguarda cada dos
segundos. Subir los trozos a medida sobrevive a eso, y no se hace acá: los
trozos de webm después del primero no se decodifican solos (no llevan
encabezado), así que pide concatenarlos en el servidor. Queda escrito como
límite, no como olvido.

**Y el mismo límite tapa una salida que parece obvia: `keepalive` no sirve
acá.** El borrador se despide con `fetch(..., { keepalive: true })` y funciona
porque manda unos kilobytes de texto; la especificación de Fetch le pone un tope
de **64 KB** al cuerpo de un pedido `keepalive`, y el audio son megabytes. O sea
que una navegación real en medio de la grabación **pierde lo grabado**, y no hay
truco de despedida que lo salve: `pagehide` llega a parar el grabador y no a
subirlo. Por eso la pantalla pone un `beforeunload` mientras graba y deja que el
navegador pregunte — avisar es lo único que se puede hacer sin la subida
progresiva.

## La pantalla

**El control y la transcripción van al centro**, y el motivo es una regla del
repo más un límite medido. La regla: «el centro es lo que se hace; la derecha es
lo que se consulta y no se edita», y grabar es lo que se hace. El límite:
`[REFERENCIA]` **declaradamente no mide la sala**, y la columna es de 320px con
`max-height: 100vh` — una transcripción de 20 minutos ahí queda detrás de su
propio scroll, que es el límite que `CLAUDE.md` ya dice en voz alta.

La transcripción va en un **`<details>`**, que es el único mecanismo plegable de
la app y el que `application.js` ya protege del morph cancelando la remoción del
`open`.

### Permisos

Graba quien pasa `work?` y está sentado en una mesa que no es la de llegada, así
que **`arrival?` pasa a ser el octavo lugar** que pregunta lo mismo. El número
va en `CLAUDE.md` y no en los comentarios: escrito en ocho lugares, el día que
cambie miente en siete.

La transcripción la lee la mesa entera: es de la mesa, igual que el borrador.

**Sin `WorkshopRecordingPolicy` propia**, por el mismo motivo que `WorkshopDraft`
no tiene una: lo que autoriza es la sala, y una policy vacía heredaría
`show? = membership.present?`, o sea «cualquiera de la empresa». La pregunta se
hace donde se hace el trabajo.

## El job

`Flow::Workshops::TranscribeRecordingJob`, calcado de `EmbedVersionJob`:

```ruby
queue_as :flow_ai
retry_on Flow::Errors::TranscriptionFailed, attempts: 3, wait: :polynomially_longer
```

y `Flow::Tenant.bypass!` para encontrar la empresa antes del `Flow::Tenant.with`.
Transcribir llama a un servicio externo, y parar una grabación no puede depender
de que responda.

**Con una diferencia que los embeddings no tienen: cada transcripción se
cobra.** El job **sale temprano si la grabación ya está `ready`**. El reintento
reintenta una llamada que falló, no re-transcribe una que salió bien. Es la
misma idempotencia de `activate!` y `complete!`, con una factura atrás.

### Tres resultados que NO son fallos

Colapsarlos es el control fantasma de siempre, así que cada uno tiene su estado
visible:

- **Transcripción vacía.** Silencio o ruido devuelve **200** con texto vacío
  —medido—. Queda `ready` con cero utterances y un texto explícito de que no se
  detectó habla. Marcarlo `failed` sería mentir; dejarlo `ready` con una tarjeta
  en blanco sería el fantasma.
- **Diarización colapsada.** Se avisa cuando **todas las utterances traen un
  solo hablante Y hay dos o más sentados en la mesa**: una condición
  estructural. **Sin umbral numérico sobre `speaker_confidence`**: se midió
  0,196–0,687 sobre entrada degenerada y no hay línea base de voces reales, así
  que cualquier corte sería inventado — y un umbral inventado es exactamente la
  guarda que *da permiso*. El número se muestra; no se juzga.
- **Proveedor fixture.** La transcripción es canneada y la pantalla lo dice, con
  las columnas `provider` y `model`.

## Lo que NO cubre, declarado

- **El español.** Todo se midió en inglés, porque `flite` no habla otro idioma.
  Que nova-3 transcriba español con esta calidad es una afirmación del
  proveedor, no una medición.
- **La diarización sobre voces reales.** Ver arriba.
- **La retención.** El audio se conserva para siempre y nadie escribió una
  política.
- **Avisar en vivo que la mesa está grabando a quien no está en la pantalla.**
  Lo más cercano es el indicador, que lo ve quien tiene la sala abierta.
- **El contexto seguro en una LAN.** Se detecta y se explica; no se resuelve.
- **La pestaña de fondo.** Queda grabando, y si el navegador la estrangula no
  hay medición de qué pasa — y la onda, que depende de
  `requestAnimationFrame`, **sí** se congela ahí por definición del navegador:
  lo que se pierde es el dibujo, no el audio.
- **Que el `AudioContext` se cierre de verdad.** Se cierra en el código y nada
  lo verifica: un contexto filtrado por grabación no se ve en ninguna guarda ni
  en ningún spec. Una pestaña con muchas grabaciones seguidas acumularía
  contextos hasta que el navegador se niegue a dar más.
- **La onda en un teléfono.** El riel a 414px tampoco lo mira ninguna captura, y
  esto es lo mismo: el recorrido fotografía 1440×1000 y 1100×900, así que
  cuántas barras caben y si desbordan a ancho de teléfono no está medido.
- **La tarjeta no se refresca sola mientras transcribe.** Ver «Los estados».
  Es el primer incremento obvio de esta feature.
- **Navegar mientras graba pierde el audio.** Se avisa con `beforeunload` y nada
  más: `keepalive` tiene un tope de 64 KB y el audio son megabytes.

## Verificación

### Specs

Request y model specs contra el fixture: las cuatro guardas de escritura en el
mismo orden que los otros POST de la sala, la idempotencia del job, la forma
normalizada de las utterances, el aviso de diarización colapsada, y los tres
resultados que no son fallos. Tenencia en `spec/tenancy/`, con la lectura del
dominio dentro de `as_company`.

### `make screens`: la guarda `[GRABAR]`

Flags de micrófono falso al lanzar —**medidos, funcionan en la imagen exacta del
recorrido**, `mcr.microsoft.com/playwright:v1.62.0-noble`—:

```
--use-fake-ui-for-media-stream
--use-fake-device-for-media-stream
--use-file-for-fake-audio-capture=<wav>
```

Son flags de lanzamiento, así que aplican a la corrida entera; inofensivo,
ninguna otra pantalla pide micrófono.

La guarda graba unos segundos, para, sube, y asevera que la tarjeta muestra las
utterances del fixture. **Contador y piso 2, exacto**, contando **caras** —idear
y evolución—: la misma semántica y el mismo razonamiento que `[DRAFT]`, porque
no hay una tercera cara y un piso flojo no cazaría que una dejó de medirse.

**Y mide la onda, que es lo que no se puede medir de ninguna otra forma.** El
nivel crudo se publica en `data-level`, así que la guarda lo muestrea cada 100ms
mientras graba y exige **dos** cosas:

1. que el máximo durante la voz esté claramente arriba de cero, y
2. que haya una corrida de muestras **cerca de cero**, que es el silencio que el
   wav del micrófono falso tiene **a propósito** entre las dos voces.

La segunda es la que discrimina, y por eso el wav se arma con silencios
intercalados y la grabación dura más que el primer tramo de voz. **Una onda
decorativa —números al azar, o una animación suelta— pasa la primera y falla la
segunda.** Sin ese silencio adentro de la ventana de grabación, la guarda sólo
probaría que algo se mueve.

**Costo de la corrida: cero.** Sin declarar `FLOW_SPEECH_PROVIDER` la cascada
cae al fixture, porque Anthropic no sabe transcribir.

**Y la línea de contadores pasa a tener once números**, así que la frase de
`CLAUDE.md` que dice «imprime los diez números» cambia en el mismo commit. Este
repo ya se comió más de una vez un documento con un conteo viejo.

### Lo que la guarda NO puede ver

Declarado ahora y no descubierto después:

- El proveedor real: sólo ejercita el fixture.
- El español y la diarización sobre voces reales.
- **El fallo de contexto seguro.** Y éste es el filoso: la guarda corre en
  `localhost`, que es contexto seguro **siempre**. O sea que el riesgo de
  despliegue más grande de C1 es **estructuralmente invisible** para el único
  navegador que la prueba. Ninguna corrida verde dice nada sobre si la mesa
  puede grabar desde un teléfono.

### Las mutaciones que hay que ver fallar

| Mutación | Tiene que ponerse rojo |
|---|---|
| el job no sale temprano con `ready` | el ejemplo de idempotencia (y en el real, cobra dos veces) |
| las utterances se guardan crudas | el ejemplo de la forma normalizada |
| se borra la detección de `!navigator.mediaDevices` | `[GRABAR]`, con el botón fantasma |
| el estado se guarda en el DOM y no en el módulo | `[GRABAR]`, al morfear en medio de la grabación |
| se saca el aviso de diarización colapsada | el ejemplo de un hablante con mesa de dos |
| el fixture deja de medirse en una cara | `[GRABAR]` cae de 2 a 1 |
| se saca la guarda de `arrival?` | el ejemplo de grabar desde la llegada |
| la onda se dibuja con números al azar en vez del `AnalyserNode` | `[GRABAR]`, por la corrida de silencio que no aparece |
| el `AudioContext` no se cierra al parar | ningún test — límite declarado abajo |

## Riesgos

1. **La diarización puede no servir**, y es el motivo por el que se eligió este
   proveedor. Si el audio real tampoco separa voces, C1 sigue siendo útil —la
   transcripción se lee igual— pero C2 pierde la mitad de su valor. **Se mide
   antes de escribir la spec de C2**, con veinte segundos de audio real.
2. **El contexto seguro puede hundir el uso real.** Si las mesas trabajan desde
   teléfonos en una LAN plana, nadie graba. Se detecta y se dice, y arreglarlo es
   una decisión de infraestructura que esta rama no toma.
3. **El audio acumulado sin política de retención.** 4,8 MB por reunión de 20
   minutos se vuelven incómodos antes de volverse caros, y son voces de
   personas.
4. **La factura.** Cada transcripción se cobra por minuto. El job es idempotente
   y la corrida del recorrido no gasta, pero no hay tope por taller ni por
   empresa, y nada avisa.
