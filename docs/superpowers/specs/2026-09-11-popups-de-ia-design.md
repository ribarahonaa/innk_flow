# Popups de la IA: esperar y responder

> Estado: diseño aprobado, sin implementar.
> Rama: `popups-de-ia`, desde `master`.

## El problema

Pedirle algo a la IA tiene dos momentos —mientras piensa y cuando responde— y
ninguno de los dos se ve bien hoy.

**Mientras piensa.** El aviso «La IA está pensando» vive arriba de todo adentro
del `turbo-frame#ai-suggestions`, y aparece por CSS cuando Turbo le pone
`aria-busy` al marco. Con un proveedor real la respuesta tarda de 10 a 70
segundos, y durante ese tiempo:

- el aviso es una franja más en la pantalla, fácil de pasar por alto;
- no bloquea nada: se puede navegar a otra pantalla con el pedido en vuelo;
- sólo existe cuando el pedido responde al marco. Los pedidos que responden a la
  pantalla entera —cualquier módulo en «IA automática», «Mejorar con IA», el
  «IA» de la evaluación, «Pedir la guía de la IA»— no marcan ningún marco, así
  que no muestran nada más que la barrita de progreso de Turbo.

**Cuando responde.** Un pedido en modo asistido responde al marco: Turbo
reemplaza el panel de propuestas y nada más. El mensaje del pedido viaja en el
flash, que el layout pinta arriba de `.app-main` —**afuera** del marco—, así que
Turbo lo descarta. La confirmación no se ve, y **el error tampoco**: si la IA
falla, la espera desaparece y la pantalla queda igual, sin decir nada.

Verificado: el repo no tiene la gema `turbo-rails` —Turbo entra sólo por npm—,
así que Rails renderiza el layout completo aun cuando el pedido es de un marco,
y Turbo recorta el marco de esa respuesta.

## Decisión

**El servidor deja la respuesta en un `<template>`, y un solo módulo JS maneja
los dos popups a partir de los eventos de Turbo.**

- Mientras la IA piensa, un popup modal que no se puede cerrar, con una
  animación de carga, que deja la página inerte y se cierra solo cuando llega
  la respuesta.
- Cuando responde, otro popup con qué pasó y —si quedó una propuesta por
  revisar— la propuesta entera con sus botones de Aplicar y Descartar.
- Si falla, el popup de espera se cierra y el de respuesta dice qué falló.

El flujo que ya existe no cambia: el pedido sigue redirigiendo, sigue
respondiendo al marco o a la pantalla según `marco_para_pedido_de_ia`, y el
morph sigue igual.

### Alternativas descartadas

- **Turbo Streams.** El pedido respondería con un stream que reemplaza el marco
  y agrega el popup. Menos JS, pero rompe el flujo de redirect del que dependen
  `marco_para_pedido_de_ia`, el morph y los tests, y en modo automático igual
  habría que refrescar la pantalla entera.
- **Todo en el cliente.** El JS leería la respuesta del fetch y armaría el
  popup. Frágil: parsea HTML y adivina qué pasó sin la información que ya tiene
  el servidor.

## 1 · El servidor

### Lo que registra el pedido

`AiRequestsController#create` deja de usar `notice`/`alert` y guarda un flash
propio:

```ruby
flash[:ia] = { "tipo" => "ok" | "error", "mensaje" => "…", "sugerencia_id" => "…" | nil }
```

Claves en string: el flash viaja en la cookie como JSON. `sugerencia_id` va
sólo cuando la propuesta quedó **pendiente**.

| Qué pasó | tipo | mensaje | propuesta |
|---|---|---|---|
| Propuesta para revisar | ok | «La IA respondió. Revisá la propuesta antes de aplicarla.» | sí |
| Ya había una igual pendiente (`reused?`) | ok | «Ya había una propuesta esperando tu revisión.» | sí |
| Se aplicó sola (`ai_auto`) | ok | «La IA respondió y se aplicó automáticamente.» | no |
| Evaluación de la IA (aditiva) | ok | «Listo: la evaluación de la IA ya está en la lista.» | no |
| Respondió, pero no se pudo aplicar (`ai_auto`) | error | «La IA respondió, pero no se pudo aplicar: …» | sí |
| Falló | error | «La IA no pudo responder: …» | no |
| Propósito desconocido (`ArgumentError`) | error | el mensaje de la excepción | no |

Dos mensajes cambian respecto de hoy. «Ya hay una propuesta esperando tu
revisión **más abajo**» pierde el «más abajo», porque ahora la propuesta está
en el popup. Y «respondió pero no se pudo aplicar» deja de decir «no pudo
responder», que no era cierto: la IA respondió, y lo que falló fue aplicarlo.

### Dónde se pinta

Un partial nuevo, `shared/_ia_respuesta`, pinta el flash como

```haml
%template{ data: { ia_respuesta: true, tipo: "ok" } }
  -# el mensaje, y la propuesta si hay
```

La propuesta usa la misma tarjeta que el panel: el loop de
`shared/_ai_suggestions` se parte y la tarjeta de una propuesta pasa a
`shared/_ai_suggestion`. Pasa por `AiSuggestionPolicy#accept?` igual que en
el panel. Como pedir y aceptar son el mismo método, quien pidió siempre la
puede revisar.

Se renderiza en **dos** lugares, a propósito:

- **adentro del `turbo-frame#ai-suggestions`** (`shared/_ai_suggestions`):
  cuando el pedido responde al marco, es lo único que Turbo conserva;
- **en el layout**, en `.app-main`: cuando responde a la pantalla entera,
  incluidas las que no tienen marco (la ficha de evaluación, donde vive «Pedir
  la guía de la IA»).

En una respuesta de pantalla entera llegan los dos, y el JS abre uno solo y
borra los dos. Un `<template>` es inerte —no se ve y sus formularios no se
envían—, así que tenerlo dos veces no hace daño.

El loop de flash del layout saltea `:ia`: no se pinta además como franja arriba.

### Lo que se va

El aviso de espera de adentro del marco —`.ai-waiting` en
`shared/_ai_suggestions`— con todo su CSS: `.ai-waiting`, `.ai-waiting__dot`,
la regla de `aria-busy` que lo muestra, la que atenúa `.ai-panel` y el
`@keyframes ai-pulse`.

## 2 · El cliente

Un módulo nuevo, `app/javascript/ia_popups.js`, importado desde
`application.js` junto al resto del código compartido.

### La espera

- **Cuándo se abre:** en `turbo:submit-start`, si la URL del envío es la de
  `/ai_requests`. Es el único endpoint que hace pensar a la IA de forma
  síncrona, así que un listener cubre todos los botones de IA —las acciones,
  «Mejorar con IA», el «IA» de la evaluación, «Pedir la guía de la IA»— sin
  tocar cada uno.
- **Cómo es:** un `<dialog class="modal">` de DaisyUI que arma el JS y abre con
  `showModal()`, lo que deja el resto de la página inerte: no se puede apretar
  nada ni moverse con Tab.
- **No se puede cerrar:** el evento `cancel` (Escape) se anula, no tiene botón
  de cerrar y un clic afuera no hace nada.
- **Qué muestra:** un spinner grande de DaisyUI (`loading loading-spinner
  loading-lg`) en el violeta de la IA, «La IA está pensando» y, debajo, «Puede
  tardar un minuto. No cierres ni recargues la página».
- **Irse de la página:** mientras está abierto, un `beforeunload` hace que el
  navegador pida confirmación antes de recargar o cerrar la pestaña.
- **Cuándo se cierra:** justo antes de pintar la respuesta
  (`turbo:before-frame-render` o `turbo:before-render`), y también ante una
  falla (sección 3), para que nunca quede colgado.

### La respuesta

- **Cuándo se abre:** después de pintar (`turbo:frame-render`, `turbo:render`,
  `turbo:load`), el JS busca `template[data-ia-respuesta]`. Si hay, copia el
  contenido del primero a otro `<dialog class="modal">`, lo abre y borra todos
  los templates, para que no se vuelva a abrir.
- **Qué muestra:** el mensaje, con el violeta de la IA si salió bien y el rojo
  de las alertas si falló, y la propuesta con sus botones si viene una.
- **Se puede cerrar:** con ✕, con Escape o con un clic afuera (el
  `modal-backdrop` de DaisyUI).
- **Aplicar o Descartar lo cierran:** son `button_to` con `data-turbo-frame:
  "_top"` y recargan la pantalla, así que el popup se cierra en su
  `turbo:submit-start`, antes de que el morph llegue.

### Por qué los diálogos los arma el JS

Si el servidor pintara el esqueleto del diálogo en el layout, el morph de una
respuesta de pantalla entera se encontraría con un diálogo abierto en el
cliente y uno cerrado en el servidor, y le sacaría el `open` a mitad de camino.
Armados por el JS, el de espera ya se cerró y se sacó antes del render, y el de
respuesta se arma después.

Antes de que Turbo guarde la página en caché (`turbo:before-cache`) se saca
cualquier diálogo, para que volver atrás no muestre un popup viejo.

### Accesibilidad y estilo

- Cada diálogo se nombra con su título (`aria-labelledby`). La espera se
  anuncia con `aria-busy` y `aria-live`, y el foco entra solo al diálogo
  (`showModal`).
- El spinner sigue girando aunque esté activado `prefers-reduced-motion`, a
  propósito: es la única señal de que la IA sigue trabajando.
- Las clases van escritas enteras en el JS: Tailwind escanea `app/javascript`
  y una clase armada con interpolación no llega a la hoja. `modal` no está
  excluido del `@plugin "daisyui"` (sólo `card` lo está).

## 3 · Errores y casos borde

| Caso | Qué pasa |
|---|---|
| Falla la IA o la tarea | El controller lo atrapa: popup de respuesta en rojo con «La IA no pudo responder: …». Arregla, de paso, el error que hoy no se ve en modo asistido. |
| Respondió pero no se pudo aplicar (`ai_auto`) | Popup en rojo con el motivo y la propuesta pendiente, para revisarla ahí. |
| Se cae la red (`turbo:fetch-request-error`) | El servidor no contestó, así que el mensaje lo arma el JS: «No se pudo hablar con el servidor. Revisá tu conexión y probá de nuevo». |
| La respuesta no trae el marco (`turbo:frame-missing`: un 403, un 500, la sesión vencida que devuelve el login) | Se anula el «Content missing» de Turbo y el popup dice «La respuesta no llegó como se esperaba», con un botón «Recargar la página». Si la sesión venció, recargar lleva al login. |
| Falla un pedido de pantalla entera | Turbo pinta la página de error. La espera se cierra antes de pintarla y no se agrega popup: la pantalla ya lo dice. |
| `turbo:submit-end` sin éxito | Cierra la espera igual. Es la red de seguridad para que ningún camino la deje abierta. |
| Doble clic | La página queda inerte apenas se envía: no hay forma de pedir dos veces. |
| Volver atrás | El template se borra al mostrarse y los diálogos no entran al caché de Turbo. |

## 4 · Verificación

### Specs de request

Escritos antes que el código:

- qué deja `flash[:ia]` en cada fila de la tabla de la sección 1;
- que la pantalla a la que vuelve el pedido trae el `<template>` dentro del
  marco **y** en el layout, con la propuesta y sus botones cuando corresponde;
- que `:ia` no aparece como franja de flash;
- que el error en modo asistido llega adentro del marco —el caso que hoy se
  pierde—;
- que en una pantalla sin marco (la ficha de evaluación) el template sale igual
  por el layout.

Los ejemplos de `spec/requests/ai_spec.rb` que miran `flash[:notice]` o
`flash[:alert]` después de pedir pasan a mirar `flash[:ia]`.

### En el navegador: `make screens`

El recorrido corre contra desarrollo, y desarrollo usa el proveedor real
(`FLOW_AI_PROVIDER=anthropic` en `.env`): no puede disparar un pedido que llame
a la IA. Hay dos caminos gratis que pasan por el servidor de verdad:

1. **Error.** Un pedido con un propósito que no existe: el controller lo
   rechaza antes de llamar a nadie. Con `page.route` se retiene el pedido para
   verificar que la espera aparece con su spinner y que Escape no la cierra;
   después se suelta y se verifica que la espera se va y que aparece el popup
   rojo.
2. **Éxito.** «Detectar duplicados». Verificado: en desarrollo el proveedor de
   chat es `anthropic` pero el de vectores es el fixture, así que la tarea
   compara local y no llama a nadie. Se verifica que el popup trae la propuesta
   con Aplicar y Descartar, se captura con el popup abierto —así la guarda de
   clases sin regla de `capturar()` revisa también las del modal— y se aprieta
   Descartar, para no dejar una propuesta pendiente que la corrida siguiente
   encontraría como «ya había una».

Los dos van sobre un desafío que existe **sólo** para el recorrido, como pide
`CLAUDE.md`. `sin-formulario` no sirve: está en borrador, no tiene ideas, y
darle ideas le cambiaría lo que fotografían sus otras capturas. Se siembra uno
nuevo en `db/seeds.rb`, `recorrido-ia`: en curso, con Idear abierto en modo
asistido y dos ideas postuladas. Se llega a él navegando por link.

### A mano, con el proveedor real

Opcional y decisión del usuario, porque cuesta plata: un pedido de verdad para
ver la espera larga (10 a 70 segundos) de punta a punta.

## Fuera de alcance

- **«Evaluar todas con IA».** Encola trabajos en segundo plano y el pedido
  vuelve al instante; no hay espera síncrona que mostrar.
- **Aplicar y Descartar.** Siguen con su flash de siempre: no hacen pensar a la
  IA.
- **Los botones de una propuesta informativa.** Detectar duplicados sigue
  mostrando «Aplicar» y «Descartar», aunque «Aplicar» no aplica nada. Queda
  anotado.
- **Un tope de tiempo.** Si el servidor nunca contesta, la espera no se cierra
  sola; recargar pide confirmación y la corta.

## Decisiones abiertas

Ninguna.
