# La lista de la mesa de llegada, en vivo

## El problema

Un taller proyecta su QR y la gente va escaneando. Quien administra está parado
adelante, con la pantalla del taller abierta, y hoy **no se entera de nada hasta
que recarga a mano**: la Mesa de llegada sólo cambia en el DOM cuando algo más
provoca una navegación. Lo que pidió Raúl, textual: «la lista de las personas que
van ingresando lo ideal es que esté en tiempo real, así vamos viendo de una
quiénes van entrando al taller».

## Qué se decidió, y qué no

Tres decisiones tomadas en la conversación de diseño, cada una descartando
alternativas concretas:

- **Lo ve sólo quien administra**, en la pantalla del taller donde ya está el QR.
  No se hace una pantalla de proyección aparte —nombres grandes, sin controles—:
  eso es otra feature, aunque suene cercana.
- **Se refresca sola la lista de la llegada y su contador**, y nada más. No el
  bloque «Mesas» entero: ahí viven el campo «Personas por mesa», el `select` de
  convocar y el campo «Nombre de la mesa», y una región que se repinta sola cada
  pocos segundos le borraría a alguien lo que está tipeando. Este repo ya pagó esa
  familia de problemas dos veces con el morph (el `<dialog>` que no sobrevive, el
  `<details>` que se cerraba solo).
- **Se recarga un `turbo-frame` cada pocos segundos, no se empuja por websocket.**
  El porqué está abajo.

## Por qué recargar un frame y no Turbo Streams

Medido en el repo antes de elegir:

- **La gema `turbo-rails` no está instalada.** Sólo está el paquete npm
  (`@hotwired/turbo-rails` en `package.json`). O sea que hoy no existen
  `turbo_stream_from`, `broadcast_replace_to` ni `Turbo::StreamsChannel`: todo eso
  viene de la gema.
- **No hay nada en vivo en la app:** no hay `app/channels`, no hay un solo
  broadcast, y las únicas menciones a ActionCable son dos líneas comentadas en
  `config/environments/production.rb`. Todo se actualiza por el morph de Turbo 8
  cuando un POST redirige a la misma URL.
- **Hay exactamente un `turbo-frame`** en toda la app (el panel de propuestas de
  IA), y su comentario muestra el patrón entendido: se renderiza siempre, aunque
  esté vacío, para que haya destino.

El push real costaría: gema nueva y `make rebuild`, encender ActionCable, y una
`ActionCable::Connection` **autenticada y scopeada por empresa** — en una app cuya
tenencia revienta a propósito sin tenant y que tiene cuatro capas para impedir
fugas. Y quien escribe es el controller público del check-in, que corre bajo
`Flow::Tenant.bypass!` y resuelve la empresa desde el token: el broadcast tendría
que renderizar el partial dentro del tenant correcto o filtra. Encima **`make
screens` no puede verificar un websocket** con lo que hoy tiene, así que la única
verificación end-to-end real del repo quedaría sin cubrir la feature.

Recargar un frame cae dentro de patrones que la app ya usa y que sus guardas ya
miran, y no agrega ninguna superficie de autenticación nueva. El push se justifica
el día que esto tenga muchos espectadores o haga falta latencia sub-segundo. Hoy
es un admin proyectando.

## Cómo funciona

### El frame y dónde corta

En `app/views/workshops/_groups.html.haml` cada mesa es un bloque con, en orden:
el nombre y el contador, la lista de asientos con sus botones, y **después** el
`select` de convocar a mano.

El `turbo-frame` envuelve, de la Mesa de llegada, **el encabezado con su contador
y la lista de asientos**. El `select` de convocar queda **afuera**: ahí está el
estado que no se puede perder.

Los botones por asiento («Marcar ausente», «Sacar») quedan **adentro** a
propósito. Son `button_to`, o sea formularios sin texto tipeado: reemplazarlos no
pierde nada, y afuera mostrarían el estado viejo de alguien que acaba de entrar.

El frame se renderiza **siempre**, aunque la llegada esté vacía o todavía no
exista, por el mismo motivo que el panel de propuestas de IA: un frame que
siempre está es el que tiene destino. Sin mesa de llegada o sin nadie en ella
muestra una línea que lo dice —«Todavía no llegó nadie»— y no una tarjeta vacía:
una región que aparece y desaparece movería el resto de la pantalla cada vez que
alguien entra.

**El mismo partial se renderiza en los dos lados**, con el MISMO id de frame: la
pantalla completa y la respuesta del endpoint. Si los ids no coinciden, Turbo no
reemplaza nada y la pantalla se queda quieta sin un solo error — un fallo mudo,
que es el que más caro sale.

**La llegada ya no es sólo del check-in**, y el frame lo refleja: desde
`ff9184d`, borrar una mesa manda a su gente ahí. Así que esto muestra «quién está
sin mesa», que incluye a quien escaneó y a quien quedó suelto. Es más de lo
pedido y se aceptó a propósito.

### El endpoint

`GET /workshops/:id/arrival`, acción `arrival` en `WorkshopsController` —donde ya
viven `enable_checkin`, `disable_checkin` y `rotate_checkin_token`—, sumada al
`only:` de `set_workshop`. Devuelve nada más que el frame.

**Permisos: la misma puerta, no una nueva.** El taller se busca con
`policy_scope(Workshop).find_by!` —lo que no se ve da 404 y no 403, que sería un
oráculo de existencia— y se autoriza con `update?`, que es exactamente el
predicado detrás del cual ya se esconde el bloque de armado entero
(`can_assemble` en `workshops/show.html.haml`). Eso está verificado: esa puerta es
**una sola** para el QR, el token y los botones. Si la lista en vivo usara su
propio criterio habría dos puertas para lo mismo, y el día que una cambie la otra
miente.

### El refresco

- **Cada 5 segundos.** La gente entra caminando: es imperceptible para esto y son
  doce pedidos por minuto desde una sola pantalla. Es una constante nombrada.
- **Sólo mientras haya algo que esperar.** Con el taller cerrado o el check-in
  apagado no entra nadie solo: el frame se renderiza igual —la lista sigue ahí—
  pero el temporizador no arranca. Lo decide la VISTA con un atributo de dato; el
  JS no adivina estado del dominio.
- **El ciclo de vida usa el idioma que la app ya tiene:** arrancar en
  `turbo:load`, limpiar en `turbo:before-render`, que es el mismo par de
  `islands.js`. Un mecanismo, no dos.
- **Se detiene con la pestaña oculta** (`visibilitychange`) y vuelve al mostrarse.
  Una pantalla proyectada está visible; una pestaña de fondo no tiene por qué
  pedir nada.

**Un detalle a fijar al implementar, no acá:** la llamada exacta para recargar el
frame —`reload()` sobre el elemento o reasignar su `src`— se decide contra la
versión de Turbo instalada, y queda cubierta por la guarda del recorrido. El
mecanismo no cambia; la línea puede.

## Verificación

Hay **dos cosas distintas** que probar, y la trampa sería un test que afirme las
dos y no pruebe ninguna. Se reparten por lo que cada herramienta puede probar.

**El recorrido (`make screens`) prueba que el frame se recarga solo.** No hace
falta una segunda persona: se abre la pantalla como admin, se cuentan los eventos
`turbo:frame-render` de ese frame, se espera algo más que el intervalo —unos seis
segundos sobre una corrida que hoy tarda dos minutos— y se exige que el contador
haya crecido. Es el idioma que el recorrido ya usa para contar
`turbo:morph`. **Tiene que ser probable por mutación** —sacando el temporizador el
contador queda en cero y la guarda se pone roja— y **tiene que imprimir cuánto
midió** al terminar, como `[RITMO]` y `[RELLENO]`: una guarda que mide cero da
verde y se lee igual que una que funciona.

**Un request spec prueba qué devuelve el endpoint**: que lista a la gente de la
mesa de llegada, y que a quien no administra le da 404. Eso es Ruby, determinista
y sin navegador.

**Lo que deliberadamente NO se prueba en el recorrido:** «entró alguien nuevo
mientras yo miraba». Eso pide dos sesiones simultáneas, y hay una regla escrita
contra `browser.newContext()` en las capturas — la `page` nueva viene sin los
listeners de `pageerror` y de `response`, que se registran una sola vez, y la
captura queda ciega justo a lo que `make screens` existe para cazar. Un POST fuera
de banda compartiría la cookie del admin y terminaría registrando al propio admin
en la mesa de llegada: un test raro que ensucia el estado para probar algo que el
request spec ya prueba mejor.

**De rebote, una propiedad a favor:** el recorrido ya cuenta toda respuesta HTTP.
Un `setInterval` sin limpiar —el bug clásico— aparecería como pedidos a `/arrival`
en pantallas que no lo tienen.

## Lo que NO entra

- Pantalla de proyección aparte, para el proyector y no para administrar.
- Que la lista en vivo la vea quien participa o quien ya entró.
- Turbo Streams, ActionCable y la gema `turbo-rails`.
- Sonido, notificación o cualquier aviso al entrar alguien.
- Que el refresco toque el contador de mesas, los campos del armado o el `select`
  de convocar.

## Riesgos

- **Latencia de hasta 5 segundos.** Es el precio explícito de no montar un
  websocket. Si algún día molesta, la salida es bajar la constante antes de
  cambiar de mecanismo.
- **Doce pedidos por minuto por pantalla abierta.** Hoy es una pantalla. Si
  mañana lo mira mucha gente a la vez, el cálculo cambia y ahí sí conviene el
  push — ese es el disparador, no una corazonada.
- **Un temporizador que no se limpia** se lleva pedidos a pantallas que no los
  necesitan. Se ataja con el par `turbo:load` / `turbo:before-render` y lo
  delataría el contador de respuestas del recorrido.

## Lo que esto no prueba

La guarda del recorrido prueba que el frame **se recarga solo**, no que el
contenido recargado refleje a alguien que entró en ese instante. Eso lo cubre el
request spec sobre el endpoint, por separado. Queda dicho para que nadie lea el
verde del recorrido como más de lo que es.
