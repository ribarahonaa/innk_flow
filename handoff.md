# Handoff — la sala de la mesa (2026-10-03)

## Empezá por acá: B, el guardado automático como versión

Lo de abajo está cerrado y pusheado. Lo que sigue es **B**, la segunda de las
cuatro partes del pedido original (la lista completa está más abajo, en «Lo que
queda abierto»).

**Qué pidió Raúl, textual:** «todos los cambios que vayan haciendo, la idea es
que se vayan guardando de forma automática y como se hace en la idea normal, que
cuando se hace un cambio de idea se guarda como una nueva versión».

**La decisión que hay que tomar antes de escribir una línea, y es de producto:**
hoy, en la sala de evolución, la mesa **propone** y el autor acepta o rechaza
(`WorkshopProposal`, nace `pending`). Un guardado automático que publique una
`idea_version` directa borra esa regla —«nadie reescribe la idea de otro»— y hay
que decidir qué pasa con las propuestas pendientes y con `WorkshopProposal`
entero. En la conversación de diseño de A se eligió **no** tocarlo, justamente
para decidirlo completo acá y no de costado. Las tres salidas que se ven:

1. El autosave escribe **sobre la propuesta** (`workshop_proposals.payload`), y
   aceptar sigue siendo del autor. Conserva la regla; el autosave deja de ser
   «como en la idea normal».
2. El autosave publica **versión directa** cuando quien edita participa de la
   idea, y propuesta cuando no. Dos caminos de escritura en la misma pantalla.
3. El autosave publica versión directa para toda la mesa, y `WorkshopProposal`
   queda sólo para lo que venga de afuera de la mesa. Es la más simple y la que
   más cambia el dominio.

**Lo que ya está medido y no hay que volver a averiguar:**

- `Flow::Ideas::PublishVersion` es el único camino para publicar una versión, y
  toma `payload:`, `author:`, `source_step:`, `title:`, `files:` y
  `enqueue_embedding:`. Publicar encola `EmbedVersionJob` **fuera** de la
  transacción: adentro, un worker que tome el job antes del commit no encuentra
  la versión y falla en silencio.
- **Una versión por tecla es inviable**: hay que decidir el debounce y qué
  cuenta como «un cambio». `idea_versions` es contenido inmutable y cada una
  calcula su vector.
- `IdeaPolicy#update?` ya abre la edición a quien participa de la idea mientras
  está en borrador **o** hay una ronda de evolución abierta. Esa ventana es la
  que el autosave de la mesa tendría que respetar o ensanchar a propósito.
- La sala de evolución ya tiene el payload vigente precargado en el formulario
  (`workshop_rooms/_evolution`), así que el lugar donde enganchar el autosave ya
  existe.
- **Turbo con debounce alcanza**: no hace falta una isla Vue. Las cuatro que hay
  son todas de configuración, y en A se descartó una quinta por lo mismo.
- Ojo con el morph: un POST que redirige a la misma URL morfea el DOM, y este
  repo ya pagó que un `<dialog>` abierto no sobrevive un morph y que un
  `<details>` se cerraba solo. Un formulario que se guarda solo mientras alguien
  escribe es la misma familia de problema — ahí está el riesgo real de B.

**Lo primero que haría:** invocar la skill de brainstorming y cerrar la decisión
de arriba con Raúl, antes de tocar código. B no es acotado: cambia el modelo de
escritura.

## Qué se hizo

El trabajo de una mesa de taller dejó de ser una pila de formularios en la
pantalla del taller. Mergeado a `master` en `8579e87`, once commits de la rama
`sala-de-la-mesa` más el de `CLAUDE.md`.

- `workshops#show` es un **selector**: una fila por vínculo, con el `brief` del
  desafío y «Entrar». Los no trabajables se listan con su motivo y sin botón.
- El trabajo vive en `GET /workshops/:workshop_id/salas/:id` →
  `WorkshopRoomsController#show`. Dos caras: **idear** (las ideas de la mesa +
  el formulario) y **evolución** (selector de ideas de la mesa con la
  participación de cada integrante, el contenido de la elegida, un formulario de
  propuesta, y lo que la mesa ya propuso).
- Columna de referencia: el `brief` del desafío y **«Tu mesa»** —que es lo que
  empezó todo: con quiénes estás sentado no se veía en ninguna pantalla—.
- Con un solo vínculo el taller redirige a la sala, y el breadcrumb pregunta lo
  mismo (`Flow::Workshops::Rooms#redirects?`) para no hacer bucle.

**No se agregó ningún camino de escritura**: en evolución la mesa sigue
proponiendo y el autor sigue decidiendo.

## Verificación

- `make spec` sobre `master`: **1612 ejemplos, 0 fallas** (baseline antes de la
  rama: 1558).
- `make yarn-build && make screens`: **76 capturas, sin errores de JS ni
  respuestas >= 400**. `[RITMO] 39/76 · [RELLENO] 290 · [PASTILLA] 643 ·
  [CRITERIO] 195 · [LIVE] 1`.
- Cinco hallazgos Important se arreglaron y **se probaron por mutación**, no por
  reporte. En uno la mutación la corrí yo, porque la evidencia que llegó no
  alcanzaba.

## Lo que queda abierto, y es decisión no deuda

Esto era **A de cuatro**. Las otras tres piden spec propia, en este orden:

1. **B — guardado automático como versión nueva.** Choca de frente con
   `WorkshopProposal`: hoy la mesa propone y el autor decide. Autosave directo
   borra esa regla, y hay que decidir qué pasa con las propuestas pendientes.
2. **C — dictado por voz y resumen de la reunión con IA.** Necesita un tercer
   eje de proveedor: **no hay speech-to-text en el repo y Anthropic no lo
   expone**. Las opciones medidas: Web Speech API del navegador (gratis, sólo
   Chrome, calidad floja), un proveedor nuevo (Whisper/Deepgram/AssemblyAI, con
   su credencial y su costo), o notas tipeadas + resumen con el chat que ya está.
3. **D — videollamada.** WebRTC/SFU o embed de un tercero. Cero infraestructura
   de esto en el repo: no hay `getUserMedia`, ni `MediaRecorder`, ni WebRTC.

Diferidos de la revisión final que se decidió dejar (ninguno bloquea):

- **`[REFERENCIA]` no mide la sala**: `revisarReferencia` se llama sólo en
  pantallas de módulo, así que la columna nueva —pegada, `max-height: 100vh`—
  no está medida en ninguna captura, y su límite declarado es justamente que una
  mesa muy grande queda detrás de su propio scroll.
- El `closed_reason` del selector nombra la fase del desafío a un gestor que no
  alcanza ese desafío. Se dejó: es el motivo por el que esa sala no se puede
  trabajar, y esconderlo volvería muda la pantalla justo en lo que el selector
  existe para decir. También se muestra sin gatear en `workshop_rooms/show:34`.
- Varios ejemplos con una mitad floja (una aserción negativa sin control
  positivo, un conteo que pasa con una sola ocurrencia). En todos la mitad
  fuerte sí discrimina.
- Los asientos no llevan `order`, ni en `_my_group` ni en `_group_body`.
- La cara de idear no tiene estado vacío; evolución sí.
- `workshops/_assembly:34` linkea el desafío sin guarda: el mismo link muerto
  para el gestor que la rama arregló en la referencia. Es anterior a la rama,
  pero ahora conviven los dos patrones.

## Los intentos fallidos, que es lo que más vale de esta sesión

- **Un hallazgo de la revisión final era FALSO, y lo descubrió el implementador
  midiendo en vez de obedecer.** La revisión dijo que el aviso del check-in se
  perdía en la cadena de dos redirects, razonando sobre
  `FlashHash.from_session_value` y `discard`. El aviso ya llegaba: Rails sólo
  marca para descartar las claves que se **cargaron**, y esa rama del redirect
  no instancia el flash. La línea de `flash.keep` se quedó igual, pero el
  comentario dice la verdad medida y no la del informe.
- **El arreglo obvio del N+1 habría introducido un bug invisible.**
  `includes(workshop_group_members: :user)` dentro de `Workshop#group_of` deja
  la asociación con **sólo el asiento de quien mira** —su `find_by` filtra por
  `workshop_group_members.user_id` y Rails pasa a `eager_load`— y todos los
  specs del panel seguirían verdes, porque todos miran a quien está logueado.
  Está escrito en `CLAUDE.md` y en el código.
- **Un ejemplo que no podía fallar.** «No lista la propuesta de otra mesa»
  aseveraba la ausencia de un texto que la vista nunca dibuja: pasaba igual con
  el filtro ensanchado. Hubo que reescribirlo contra lo que la vista **sí**
  dibuja, y probarlo con mutación.
- **Tres de mis propios briefs tenían errores**, los tres encontrados por los
  implementadores: dos leían un atributo del dominio fuera de `as_company`
  (`MissingTenant`), uno usaba `t(...)` en un request spec, uno pedía un test
  imposible (al completarse la ronda, `MaterializeClosures` cierra el vínculo y
  la cara de evolución deja de dibujarse, así que el aviso de «venció» no se
  puede ver por ese camino), y uno inventaba el nombre de un desafío del seed.
- **La spec mandaba `policy_scope(Idea)` pelado**, y para quien administra ese
  scope es `all`: el bloque listaba las ideas de otras mesas bajo un título que
  decía que eran de la mesa. El filtro por integrantes va **adentro** del scope.
- **El preflight encontró que ninguna tarea dejaba la suite verde**: la del
  selector rompía las aserciones de los dos specs de sala y las arreglaban las
  dos tareas siguientes, o sea que el revisor de esa tarea no podía distinguir
  el rojo esperado de uno nuevo.
- **Un bloque que ninguna captura dibujaba.** La participación de idear quedó
  al costado del título en vez de debajo, y `taller-idear` no tenía ideas
  sembradas: la captura `25` fotografió el bloque ausente, con `[CLASES]` en
  verde porque las cuatro clases sí tienen regla. Mismo patrón que la tarjeta
  del QR. Se arregló con la indentación **y** sembrando el borrador.

## Dónde seguir

- El plan ejecutado: `docs/superpowers/plans/2026-10-02-sala-de-la-mesa.md`.
- La spec, con el alcance de las cuatro partes:
  `docs/superpowers/specs/2026-10-02-sala-de-la-mesa-design.md`.
- `CLAUDE.md` ya está actualizado: la sección «El taller» describe el
  comportamiento nuevo, y están escritas las trampas de `group_of`, de las dos
  fuentes de ideas, del `links.one?` del redirect y del bloque que sólo se
  dibuja con datos.
- **Pusheado.** `origin/master` quedó en el mismo commit que el local; el merge
  es `8579e87`. Lo subió Raúl a mano: el push desde la sesión lo frena el
  clasificador de auto mode, y la regla de permiso angosta —si alguna vez se
  quiere habilitar— es `"Bash(git push https://github.com/ribarahonaa/innk_flow.git:*)"`
  en `.claude/settings.local.json`.
