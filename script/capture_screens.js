// Recorrido visual de la maqueta contra la app CORRIENDO.
//
// Es la verificación end-to-end real del proyecto: los system specs con
// navegador chocan con el `with_lock` de los servicios (ver
// spec/system/smoke_spec.rb), así que el recorrido completo se verifica acá,
// contra la app de verdad, y deja las capturas en tmp/screenshots/.
//
//   make screens          # levanta Chromium en un container efímero
//
// Requiere que el stack esté arriba (`make up`) y sembrado (`make seed`).
const { chromium } = require('playwright');
const fs = require('fs');

const BASE = process.env.BASE_URL || 'http://localhost:3001';
const OUT = process.env.OUT_DIR || '/shots';
const CHALLENGE = 'merma-bodega';

const shots = [];
let failures = 0;
// En cuántas pantallas `[LIVE]` midió que la mesa de llegada se refresca sola.
let liveMeasurements = 0;
// En cuántas de las dos caras de la sala `[DRAFT]` midió que el texto vuelve
// después de recargar. Las dos, o la guarda dejó de ver una.
let draftMeasurements = 0;
// EXACTO y no flojo: son las dos caras de la sala, idear y evolución, y no hay
// una tercera. Un piso flojo no cazaría que una dejó de medirse.
const PISO_DE_BORRADORES = 2;

// En cuántas de las dos caras de la sala `[GRABAR]` midió el viaje completo:
// grabar, parar, subir, y que la transcripción aparezca.
let recordingMeasurements = 0;
// EXACTO en 2, por el mismo motivo que `PISO_DE_BORRADORES`: cuenta CARAS
// —idear y evolución— y no hay una tercera, así que un piso flojo no cazaría
// que una dejó de medirse.
//
// Una cara cuenta como medida sólo si pasaron TODAS las fases —el control, la
// onda con su silencio, la subida y la transcripción—, igual que en `[DRAFT]`.
// Un contador por fase volvería el piso 4 y rompería la semántica de «caras».
const PISO_DE_GRABACIONES = 2;

// Los umbrales de la onda. **Se CALIBRAN midiendo, no se adivinan**: el Paso 7
// manda imprimir la serie real del micrófono falso y pinchar estos tres con lo
// que salga. Los valores de abajo son el punto de partida.
//
// `VOZ_MINIMA` es el piso del pico durante la voz; `SILENCIO_MAXIMO` el techo de
// una muestra que cuenta como silencio —el mismo orden de magnitud que
// `PISO_VISIBLE` del JS, a propósito—; y `MUESTRAS_DE_SILENCIO`, cuántas
// seguidas hacen falta: pedir 8 de las 17 que se midieron (abajo) deja margen
// para el ataque y la cola de las voces de al lado.
//
// Al lado de ese 17 había una estimación teórica —«el silencio dura 1,5 s y se
// muestrea cada 100 ms, o sea ~15 muestras»— y se sacó: las dos eran ciertas en
// sus propios términos, y un número plausible pero equivocado al lado del
// medido es justo lo que hace que alguien recalibre contra el que no se midió.
// CALIBRADOS el 2026-10-08 y RE-MEDIDOS tras cambiar la espera del morph (de
// 1500 ms fijos al evento `turbo:morph`), que corrió el muestreo respecto del
// wav. Serie real del micrófono falso, 60 muestras, una cada 100 ms:
//   0.006 0.006 0.605 0.056 0.523 0.211 0.516 0.506 0.506 0.132 0.013 0.564
//   0.492 0.487 0.064 0.286 0.566 0.321 0.294 0.445 0.311 0.279 0.055 0.235
//   | 0.005 0.005 0.005 0.005 0.001 0.000 x9 0.003 0.005 0.005 |
//   0.157 0.061 0.109 0.029 0.029 0.028 0.056 0.006 0.005 0.125 ... 0.119 0.097
// (la segunda cara dio lo mismo: pico 0,600, mismo hueco). El hueco cae en las
// muestras 24 a 40 (17 seguidas bajo 0,01) y la ventana termina DENTRO de la
// segunda voz, así que la corrida sale del hueco del medio y no de una cola.
// Pico de la voz 0,605: 0,05 queda un orden de magnitud abajo. El hueco marca
// 0,000–0,006 (opus mete algo de ruido): 0,01 queda arriba de eso y abajo de la
// cola de la voz. Se piden 8 de 17.
const VOZ_MINIMA = 0.05;
const SILENCIO_MAXIMO = 0.01;
const MUESTRAS_DE_SILENCIO = 8;

// Un módulo por su TIPO, no por su nombre: el nombre es editable y una
// propuesta de la IA lo reescribe entero.
function porTipo(page, label) {
  return page.locator('.step-card', {
    has: page.locator('.step-card__kind', { hasText: label })
  }).first();
}

// Rails pluraliza en inglés y la app habla español: «condición» salía
// «condicións» a la vista de todos. Se revisa en CADA pantalla porque el bug
// aparece donde alguien escriba un contador nuevo, no en un lugar fijo.
const PLURAL_ROTO = /\b\w*(?:ións|óns|áns|éns)\b/i;

async function revisarTexto(page, name) {
  const texto = await page.locator('body').innerText().catch(() => '');
  const roto = texto.match(PLURAL_ROTO);
  if (roto) {
    failures++;
    console.error(`[TEXTO] plural en inglés sobre una palabra española en ${name}: «${roto[0]}»`);
  }
}

// Una acción que vuelve a la MISMA pantalla se tiene que morfear, no
// recargar: es la diferencia entre «el dato se actualizó» y «la pantalla
// parpadeó». Depende de una meta del layout y de que Turbo trate la vuelta
// como page refresh, y las dos se rompen sin que ninguna otra prueba se entere.
//
// No cuesta una llamada al proveedor: se pide a mano la misma navegación que
// produce un POST que redirige a donde ya estabas.
//
// Lo que esto NO cubre es el scroll. Conservarlo importa cuando el contenido
// cambia —ahí idiomorph saca nodos, la página se acorta y el navegador recorta
// scrollY—, y una visita a la misma pantalla sin cambios no mueve un solo
// nodo. Verificarlo acá daría siempre verde; se midió a mano contra el pedido
// de evaluación real (1083 -> 1083).
async function revisarMorphing(page, name) {
  const metodo = await page.evaluate(
    () => document.querySelector('meta[name="turbo-refresh-method"]')?.content
  );
  if (metodo !== 'morph') {
    failures++;
    console.error(`[MORPH] ${name} no declara el refresh por morphing (turbo-refresh-method=${metodo})`);
    return;
  }

  const resultado = await page.evaluate(async () => {
    const cuerpo = document.body;
    let morphs = 0;
    const contar = () => { morphs++; };
    addEventListener('turbo:morph', contar);
    window.Turbo.visit(window.location.href, { action: 'replace' });
    await new Promise((r) => setTimeout(r, 1500));
    removeEventListener('turbo:morph', contar);
    return { morphs, mismoCuerpo: document.body === cuerpo };
  });

  if (!resultado.morphs || !resultado.mismoCuerpo) {
    failures++;
    console.error(`[MORPH] ${name} se repinta en vez de morfearse (${JSON.stringify(resultado)})`);
  }
}

// Un <details> abierto por quien usa la pantalla tiene el `open` puesto por
// el CLIENTE. Guardar algo adentro redirige a la misma URL, Turbo morfea
// contra el HTML del servidor —que no trae `open`— y el plegable se cierra
// justo después de guardar. El gancho de `application.js` lo evita; esto
// prueba que siga ahí, con la misma navegación que produce un POST que
// vuelve a donde estabas.
async function revisarPlegableTrasMorph(page, name, selector) {
  if (!(await page.locator(selector).count())) {
    failures++;
    console.error(`[PLEGABLE] ${name}: no hay ningún ${selector} con qué probar`);
    return;
  }
  const resultado = await page.evaluate(async (sel) => {
    document.querySelector(sel).open = true;
    let morphs = 0;
    const contar = () => { morphs++; };
    addEventListener('turbo:morph', contar);
    window.Turbo.visit(window.location.href, { action: 'replace' });
    await new Promise((r) => setTimeout(r, 1500));
    removeEventListener('turbo:morph', contar);
    return { morphs, abierto: document.querySelector(sel)?.open === true };
  }, selector);
  // Sin morph la guarda no probó nada: pasaría en verde con el gancho roto.
  if (!resultado.morphs) {
    failures++;
    console.error(`[PLEGABLE] ${name}: la pantalla no se morfeó, así que no se probó el plegable`);
  } else if (!resultado.abierto) {
    failures++;
    console.error(`[PLEGABLE] ${name}: ${selector} se cerró al actualizarse la pantalla`);
  }
}

// Un <form> dentro de otro es HTML inválido y el navegador NO lo deja pasar:
// descarta el interno y sus botones pasan a pertenecer al externo. Pasó de
// verdad — los ✓/✗ de veredicto vivían dentro del formulario del corte, así
// que apretarlos enviaba el corte. En el DOM no se ve, porque el parser ya lo
// aplanó: hay que mirar el HTML SERVIDO.
//
// Vive en `capturar()`, o sea que corre en TODAS las pantallas del recorrido.
// Estuvo en `shot()`, que es UNO de los caminos: las que se llegan por clic o
// por `goto` suelto la salteaban, y tres la repetían a mano —justo las que
// juntan varios forms en una pantalla: el editor de campos y el bloque de
// criterios conviven CON el form del módulo, uno detrás del otro—. La guarda
// que `CLAUDE.md` nombra por el bug del corte quedaba ciega en la mayoría del
// recorrido, empezando por todas las pantallas a las que se llega por clic.
//
// La URL sale de `page.url()` y no de un parámetro: escrita a mano se olvida
// el query string, y una pantalla a la que se llegó por un redirect se releía
// por la URL vieja.
async function revisarFormsAnidados(page, name) {
  // El DOM real, que es lo que la lectura del HTML servido NO puede ver. Las
  // dos conviven porque miran dos cosas distintas, no porque una repita a la
  // otra: el parser prohíbe el anidamiento AL PARSEAR —por eso leer lo que
  // sirve el server alcanza para lo que escribe una vista—, pero
  // `appendChild` lo permite, así que el DOM puede tener un `form form` que
  // el documento servido nunca mostró.
  //
  // No es hipotético por dónde entraría: la isla `step-settings` renderiza
  // sus campos ADENTRO del `form_with` de Rails de `steps/config/_modulo`,
  // por diseño —viajan en el mismo PATCH que el nombre y el modo de IA—, o
  // sea justo donde un `<form>` emitido por Vue sería un form dentro de otro.
  // Hoy ningún `.vue` emite uno y esto no puede marcar nada; es latente a
  // propósito, como la guarda del HTML servido antes del bug del corte.
  //
  // `querySelector` no entra en el contenido de un `<template>` —vive en un
  // fragmento aparte, donde el anidamiento es legal—, así que acá tampoco
  // cuenta, igual que en la lectura de abajo.
  if (await page.evaluate(() => document.querySelector('form form') !== null)) {
    failures++;
    console.error(`[FORMS] ${name} tiene un formulario dentro de otro en el DOM: lo armó el cliente, así que el HTML servido no lo muestra`);
  }

  // Sin el fragmento: no viaja al servidor, así que la respuesta vuelve con
  // la URL pelada y la comparación de abajo daría un falso negativo. Y pasada
  // por `new URL`, que es lo que normaliza el otro lado de esa comparación:
  // `page.url()` lo serializa Chromium y la URL de la respuesta la re-parsea
  // Playwright, así que compararlas crudas apuesta a que las dos escriban
  // igual el primer query con un espacio o un acento.
  const pedida = new URL(page.url());
  pedida.hash = '';
  const url = pedida.href;

  // Piso. Sin él una lectura fallida pasa midiendo CERO —sin HTML no hay
  // `<form>` que contar y el conteo da 0—, que es la forma en que una guarda
  // aprueba sin haber mirado nada. Y hay una segunda manera de medir la nada:
  // `page.request.get` SIGUE los redirects, así que con la sesión perdida
  // devolvía el login (200, con su propio form) y la guarda daba verde sobre
  // el documento equivocado. Por eso no alcanza con que la respuesta esté
  // bien: tiene que ser la de ESTA URL.
  let respuesta;
  try {
    respuesta = await page.request.get(url);
  } catch (e) {
    failures++;
    console.error(`[FORMS] ${name}: no se pudo releer el HTML servido de ${url} (${e.message.split('\n')[0]})`);
    return;
  }
  // `estadoEsperado` es el mismo mecanismo declarado que usan las dos
  // pantallas de error: se perdona el estado que se DECLARÓ, no «>= 400».
  //
  // Que esto no le rompa la corrida a `19-forbidden` y `20-not-found` cuelga
  // de un hecho medido: un `page.request.get` NO aflora por
  // `page.on('response')` —cero eventos—, así que releer un 403 no suma un
  // `[HTTP 403]` espurio. Si aflorara, tampoco lo salvaría el perdón del
  // listener: pide `isNavigationRequest()` y esto no lo es.
  const esperado = estadoEsperado || 200;
  if (respuesta.status() !== esperado || respuesta.url() !== url) {
    failures++;
    console.error(`[FORMS] ${name}: releer ${url} dio ${respuesta.status()} en ${respuesta.url()}, y se esperaba ${esperado} en la misma URL`);
    return;
  }
  let html;
  try {
    html = await respuesta.text();
  } catch (e) {
    failures++;
    console.error(`[FORMS] ${name}: se cortó el cuerpo de ${url} (${e.message.split('\n')[0]})`);
    return;
  }
  if (!html.includes('</html>')) {
    failures++;
    console.error(`[FORMS] ${name}: lo que respondió ${url} no es un documento HTML`);
    return;
  }

  // «Este documento es el que se fotografió» y «pedí esta URL y me dieron
  // algo» no son lo mismo, y hasta acá todo lo de arriba sólo prueba lo
  // segundo. Hoy coinciden porque toda escritura de la app redirige —es lo
  // que sostiene el diseño de morph de este repo—, así que `page.url()`
  // siempre es la URL de un GET. Un 422 renderizado en el lugar rompe esa
  // coincidencia sin romper nada de lo de arriba: la pantalla mostraría el
  // documento que devolvió el POST y `page.url()` quedaría en su destino, así
  // que este re-GET leería OTRO documento y lo aprobaría igual —200, la misma
  // URL, su `</html>` y sin un form dentro de otro—, mientras el que está en
  // pantalla no lo mira nadie.
  //
  // El título es lo que ata las dos puntas: lo escribe el servidor
  // (`content_for :title`, en 35 de las 40 plantillas; de las cinco que no lo
  // ponen, cuatro caen en el mismo «innk flow» del layout, y la quinta
  // —`reports/pdf`— va por `layouts/pdf.html.haml`, que no emite `<title>`
  // ninguno: no es una pantalla, así que el recorrido no la abre nunca),
  // Turbo lo mantiene al día al navegar y al morfear, y ningún `.js` de la app
  // lo toca. Dos acciones distintas casi nunca titulan igual —y las que sí,
  // como las dos pantallas de error, ya tienen su propia guarda por estado—,
  // así que un título que no coincide es el documento equivocado.
  const tituloServido = (html.match(/<title[^>]*>([\s\S]*?)<\/title>/i) || [])[1];
  if (tituloServido === undefined) {
    failures++;
    console.error(`[FORMS] ${name}: lo que respondió ${url} no tiene <title>, así que no hay con qué atarlo al documento que está en pantalla`);
    return;
  }
  // Decodificado por el navegador y no a mano: el servidor escapa `&`, `<`,
  // `>` y las comillas, y `document.title` ya viene decodificado. Un desafío
  // con un `&` en el nombre daría un falso positivo comparando crudo.
  const titulos = await page.evaluate((servido) => {
    const caja = document.createElement('textarea');
    caja.innerHTML = servido;
    return { servido: caja.value.trim(), enPantalla: document.title.trim() };
  }, tituloServido);
  if (titulos.servido !== titulos.enPantalla) {
    failures++;
    console.error(`[FORMS] ${name}: releer ${url} devolvió «${titulos.servido}» y en pantalla está «${titulos.enPantalla}»: no es el documento que se fotografió`);
    return;
  }

  // Los `<template>` se sacan antes de contar: su contenido se parsea en un
  // fragmento aparte, así que ahí el navegador NO aplana un form dentro de
  // otro y el anidamiento es legal. No es hipotético —`shared/_ia_respuesta`
  // mete `shared/_ai_suggestion`, con sus `button_to`, adentro de un template
  // y lo dice en su comentario—: hoy ese template se sirve al tope de
  // `.app-main` y nunca cae adentro de un form, pero contarlo haría que la
  // guarda reporte como bug lo que el repo documenta como correcto.
  const servido = html.replace(/<template\b[\s\S]*?<\/template>/gi, '');

  let profundidad = 0;
  let maxima = 0;
  for (const etiqueta of servido.match(/<form\b|<\/form>/g) || []) {
    profundidad += etiqueta === '</form>' ? -1 : 1;
    maxima = Math.max(maxima, profundidad);
  }
  if (maxima > 1) {
    failures++;
    console.error(`[FORMS] ${name} sirve un formulario dentro de otro: el navegador se come el interno`);
  }
}

// En cuántas pantallas `[RITMO]` tiene que encontrar algo que medir.
//
// La guarda compara cada tarjeta contra la anterior, así que con menos de dos
// no hay par: pasa sin haber medido nada, y nadie lo cuenta. Mientras vivía en
// `shot()` corría en unas pocas pantallas; mudarla a `capturar()` la hizo
// correr en las 71 del recorrido, y ese silencio pasó a leerse como cobertura
// universal — que es peor que antes. Un renombre de `.card`, o un div de
// layout entre `.app-main` y las tarjetas —que es lo que `ideas/show` ya hace
// con `.idea-layout` y `steps/config/_modulo` con su `form_with`— la vuelven
// verde sin avisar.
//
// De dónde sale el número: **medido, el 2026-09-29, en 37 de 71 pantallas**.
// Las que no llegan a dos tarjetas raíz son las seis caras de configuración,
// los índices, las dos pantallas de error, la ficha de la idea, el login y las
// de evolución. El piso son esas 37 menos 1: acá el conteo no es de elementos
// sino una propiedad ESTRUCTURAL por pantalla —«¿tiene dos tarjetas raíz?»—, y
// eso no lo mueve el seed, así que vale la convención de `PUNTOS_DE_MERMA`:
// exacto, y se bumpea cuando cambia. Uno de margen tolera una pantalla que
// oscile; tres eran casi el 10% de la cobertura de esta guarda, o sea
// tolerancia a lo único que el piso vino a matar. La corrida imprime el número
// real al terminar, así que moverlo no obliga a contar de nuevo a mano.
const PISO_DE_RITMO = 36;
let pantallasConRitmo = 0;

// Las tarjetas tenían `margin: 0` y se tocaban: la página era una sola columna
// blanca continua partida por hairlines, sin agrupar nada. Se ve midiendo, no
// mirando —a simple vista el borde doble parece una separación—.
async function revisarRitmo(page, name) {
  const { pegadas, pares } = await page.evaluate(() => {
    const paneles = [...document.querySelectorAll('.app-main > .card')];
    let juntas = 0;
    for (let i = 1; i < paneles.length; i++) {
      const anterior = paneles[i - 1].getBoundingClientRect();
      const actual = paneles[i].getBoundingClientRect();
      if (actual.top - anterior.bottom < 8) juntas++;
    }
    return { pegadas: juntas, pares: Math.max(paneles.length - 1, 0) };
  });

  if (pares > 0) pantallasConRitmo++;

  if (pegadas > 0) {
    failures++;
    console.error(`[RITMO] ${name}: ${pegadas} tarjetas pegadas a la anterior, sin separación`);
  }
}

// El relleno de `card-body` contra el que fija la hoja.
//
// `[CARD]` medía el ASPECTO de una `card` contra `.panel` —los 20px, los 14px
// de letra y la sombra— y se retiró con `.panel`, porque sin ella no queda
// contra qué comparar. No se reemplazó, y `[CLASES]` no cubre el hueco: marca
// un elemento sólo si no tiene fondo Y no tiene relleno Y no tiene borde, y en
// una `card` el relleno vive en `card-body` —en la `card` misma siempre es 0—,
// así que ahí el chequeo se reduce a «tiene fondo o tiene borde». Nada vigila
// que DaisyUI recupere sus 24px por default.
//
// Contra qué se compara, ahora que `.panel` no está: contra lo que declara la
// hoja, escrito acá a mano. DaisyUI sirve `padding: var(--card-p, 1.5rem)`, o
// sea que si la regla `.card` de `application.css` se pierde o se renombra el
// token, el relleno cae solo a 24px sin dejar rastro en el DOM. Leer
// `--card-p` del elemento no serviría: ahí ya estaría el 1.5rem de DaisyUI y
// la comparación se cumpliría sola.
const RELLENO_DE_CARD = 20;              // `.card { --card-p: 20px }`
const RELLENO_EN_REFERENCIA = 16;        // `.app-aside .card { --card-p: 16px }`

// Cuántos `card-body` tiene que medir la corrida entera. Mismo motivo que el
// piso de `[RITMO]`: una guarda que no encuentra qué medir pasa igual.
//
// **Medido el 2026-09-29: 273 en 71 pantallas**, de los cuales 3 son los
// `empty-state` que la medición de abajo exceptúa, o sea **270**. El piso son
// 250: veinte de margen, que es una pantalla de módulo entera y media —las más
// cargadas dibujan entre ocho y diez—, y sigue muy por encima del cero al que
// lo lleva un renombre de `card-body` o de `.card`.
const PISO_DE_CARD_BODY = 250;
let cardBodiesMedidos = 0;

async function revisarRellenoDeTarjeta(page, name) {
  const { total, rotos, muestra } = await page.evaluate(({ centro, referencia }) => {
    const malos = [];
    let total = 0;
    // `.card > .card-body` y no `.card-body` a secas: es el mismo contrato que
    // ya exige `[PANEL]` (ninguna `card` sin su `card-body` directo adentro).
    // El contenido de un `<template>` queda afuera, como en todas las demás.
    //
    // `.empty-state` es la ÚNICA excepción, y va por selector —angosta, como
    // las superficies de código de `[MONO]`— porque la hoja le declara el
    // relleno a propósito: `.empty-state { padding: 44px 20px }`, vocabulario
    // propio de esta app igual que `.step-card` y `.flow-strip`. Ahí 44/20 es
    // la regla y no la desviación, y midió 44/20/44/20 en las tres pantallas
    // vacías del recorrido en la primera corrida de esta guarda.
    //
    // Exceptuarla no le saca nada a lo que la guarda contesta —«DaisyUI no
    // recuperó sus 24px»—: su propia regla le gana a `var(--card-p)`, así que
    // un `empty-state` mediría 44/20 con el token roto o sano. Lo que NO se
    // puede hacer es ensanchar la excepción a «si tiene alguna clase propia,
    // no mido»: eso la dejaría ciega, que es lo que esta tanda vino a
    // arreglar. Son seis lugares —cinco vistas y el estado vacío del builder
    // en `pipeline_builder.vue`—, y el recorrido fotografía tres.
    for (const body of document.querySelectorAll('.card > .card-body:not(.empty-state)')) {
      total++;
      // La referencia es más angosta y la hoja le baja el relleno; el resto de
      // la app —incluido lo que arman las islas y los popups— va con el del
      // centro.
      const esperado = body.closest('.app-aside') ? referencia : centro;
      const cs = getComputedStyle(body);
      const lados = ['paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft']
        .map((lado) => Math.round(parseFloat(cs[lado])));
      if (lados.some((px) => px !== esperado)) {
        malos.push({ clase: body.parentElement.className, esperado, lados });
      }
    }
    // El conteo va sin truncar y sólo el DETALLE lleva tope. Contar sobre la
    // lista ya cortada declaraba «4 `card-body`» en una pantalla con treinta
    // rotos, o sea un número inventado justo en el único lugar donde el
    // mensaje afirma uno (`[CLASES]` no tiene el problema porque no declara
    // ninguno).
    return { total, rotos: malos.length, muestra: malos.slice(0, 4) };
  }, { centro: RELLENO_DE_CARD, referencia: RELLENO_EN_REFERENCIA });

  cardBodiesMedidos += total;

  if (rotos) {
    failures++;
    const detalle = muestra.map((m) => `«${m.clase}» ${m.lados.join('/')}px en vez de ${m.esperado}px`).join(' · ');
    console.error(`[RELLENO] ${name}: ${rotos} \`card-body\` con otro relleno que el de la hoja · ${detalle}`);
  }
}

// Un estado vacío son tres cosas centradas: el título, la explicación y la
// salida. La explicación NO lo estaba, y no se ve leyendo el CSS porque las
// tres reglas son correctas por separado: `.empty-state` es
// `text-align: center`, y `.app-main > .card .muted` le pone la medida de
// prosa (72ch) al párrafo. Juntas dejaban la CAJA de 72ch contra el borde
// izquierdo con el texto centrado adentro de ella, o sea el párrafo corrido
// media tarjeta mientras el título y el botón sí estaban centrados. Se ve
// midiendo.
// Un prompt es prosa adentro de un JSON, y la pantalla de auditoría existe
// para LEERLO. Con `white-space: pre` las líneas medían más que la tarjeta y
// la única salida era scrollear de costado, que para leer prosa no es una
// salida. Se mide que no sobre nada a lo ancho.
async function revisarBloqueDeCodigo(page, name) {
  const desbordados = await page.evaluate(() =>
    [...document.querySelectorAll('.code-block')]
      .map((n, i) => ({ i, sobra: n.scrollWidth - n.clientWidth }))
      .filter((n) => n.sobra > 1));

  if (desbordados.length) {
    failures++;
    const detalle = desbordados.map((d) => `#${d.i} sobra ${d.sobra}px`).join(' · ');
    console.error(`[CODIGO] ${name}: el bloque se sale de la tarjeta a lo ancho — ${detalle}`);
  }
}

async function revisarEstadoVacio(page, name) {
  const desviados = await page.evaluate(() => {
    const caja = document.querySelector('.empty-state');
    if (!caja) return null;
    const suyo = caja.getBoundingClientRect();
    const centro = suyo.left + suyo.width / 2;
    return [...caja.children]
      .map((n) => {
        const r = n.getBoundingClientRect();
        return { texto: n.textContent.trim().slice(0, 30), desvio: Math.round(r.left + r.width / 2 - centro) };
      })
      .filter((n) => Math.abs(n.desvio) > 4);
  });

  if (desviados === null) {
    failures++;
    console.error(`[VACIO] ${name}: no hay ningún .empty-state que medir`);
  } else if (desviados.length) {
    failures++;
    const detalle = desviados.map((d) => `«${d.texto}» ${d.desvio}px`).join(' · ');
    console.error(`[VACIO] ${name}: fuera del centro de la tarjeta — ${detalle}`);
  }
}

// La referencia es lo que se consulta, y tiene que poder consultarse sin
// buscarla. Dos formas de romperlo, medidas en evaluación cuando se completó:
// a 1440×1000 la columna —pegada y con `max-height: 100vh`— medía 1.395px, y
// lo último quedaba tapado detrás de su propio scroll; y debajo de 1280px,
// donde sube arriba del trabajo, formaba una banda de 727px que empujaba el
// título del módulo afuera de la primera pantalla.
async function revisarReferencia(page, name) {
  const columna = await page.evaluate(() => {
    const aside = document.querySelector('.app-aside');
    return aside ? { alto: aside.scrollHeight, visible: aside.clientHeight } : null;
  });
  if (!columna) return;
  if (columna.alto > columna.visible + 1) {
    failures++;
    console.error(`[REFERENCIA] ${name}: la columna mide ${columna.alto}px y se ven ${columna.visible}: lo último queda tapado`);
  }

  const tamano = page.viewportSize();
  await page.setViewportSize({ width: 1100, height: 900 });
  const titulo = await page.evaluate(() => {
    window.scrollTo(0, 0);
    return document.querySelector('.page-banner')?.getBoundingClientRect().top ?? null;
  });
  await page.setViewportSize(tamano);
  // La mitad de la pantalla: el título y el arranque del trabajo tienen que
  // verse sin scrollear.
  if (titulo !== null && titulo > 450) {
    failures++;
    console.error(`[REFERENCIA] ${name}: a 1100px la referencia empuja el título del módulo a ${Math.round(titulo)}px`);
  }
}

// Una clase que Tailwind no vio al escanear existe en el HTML y no tiene
// ninguna regla detrás: en el DOM se ve perfecta y en pantalla no se ve nada.
// Ninguna otra prueba lo atrapa — ni un request spec, que solo mira el body.
//
// Se detecta por el estilo COMPUTADO: un badge sin fondo, un botón sin
// padding, son clases que no llegaron a la hoja.
async function revisarClasesDescartadas(page, name) {
  const huerfanas = await page.evaluate(() => {
    const sospechosas = [];
    // `.panel` está en la lista aunque ya no tenga ninguna regla: es la
    // guarda contra que alguien la reintroduzca — sin CSS detrás queda sin
    // fondo, sin relleno y sin borde, que es exactamente lo que esto atrapa.
    // `.flow-drawer__punto` está por otro motivo, con CSS propio y escrito a
    // mano: lo que esto atrapa no es sólo una clase que Tailwind no vio, es
    // cualquier elemento que se quedó sin la regla que lo pintaba.
    //
    // LO QUE NO PUEDE VER, y conviene saberlo antes de confiarle un chip: un
    // `badge-soft` NUNCA cae acá. La hoja le deriva relleno y borde de
    // `currentColor` con alfa, y `currentColor` siempre resuelve a algún color
    // —al heredado, si hace falta—, así que `sinFondo` no es cierto jamás para
    // un chip suave por roto que esté el token que debería pintarlo. El chequeo
    // es de tres condiciones Y, y la primera no se cumple nunca.
    //
    // No se puede arreglar midiendo: del estilo computado no se saca de dónde
    // salió un color. A los chips suaves los cubre `[PASTILLA]`, que no pregunta
    // si hay fondo sino si ese fondo SE DISTINGUE de la superficie de atrás, y
    // ahí un currentColor de más no ayuda a pasar. Que nadie dé por cubierto un
    // chip suave porque `[CLASES]` está verde. El punto
    // del drawer entró acá cuando dejó de ser un `badge` vaciado —antes lo
    // cubría `[class*="badge"]`— y su fondo es un `color-mix()` sobre
    // `--punto`: si ese token se rompe o se renombra, el `color-mix()` queda
    // inválido, el fondo cae a transparente y el punto se vuelve invisible
    // sin dejar rastro en el DOM.
    //
    // Las tres familias que suma el rediseño INNK: `.page-banner`,
    // `.app-rail__item` y —ya cubierta— `.theme-switch__btn`. La banda importa
    // concretamente: si la regla `.page-banner` entera desapareciera, el `h1`
    // heredaría `--text` sobre `--surface`, o sea ~17:1, así que `[BANDA]`
    // seguiría verde, el conteo seguiría en 71 y nadie más se enteraría. El
    // botón del control de tema NO se agrega porque ya entra por
    // `[class*="btn"]`, que matchea la subcadena «btn» de `theme-switch__btn`:
    // sumarlo sería un selector redundante.
    for (const el of document.querySelectorAll('[class*="badge"],[class*="btn"],[class*="alert"],[class*="flow-drawer__punto"],.steps,.panel,.card,.page-banner,.app-rail__item,.table :is(th,td)')) {
      // Única excepción: la celda de `tr.cut-line` (línea de corte del
      // ranking, `steps/selection.html.haml`) anula padding y borde a
      // propósito con `!important` (`.cut-line td` en application.css) — no
      // es una clase que no llegó a la hoja, es la regla haciendo su trabajo.
      // Cualquier otra celda sin clase SÍ tiene que pasar el chequeo: si
      // `.table th`/`.table td` de DaisyUI dejara de compilar, una tabla con
      // todas sus celdas sin clase (como la de «Matriz por módulo» en
      // `steps/reporting.html.haml`) es exactamente el caso que esto tiene
      // que atrapar.
      if (el.closest('tr.cut-line')) continue;
      const cs = getComputedStyle(el);
      const sinFondo = cs.backgroundColor === 'rgba(0, 0, 0, 0)' || cs.backgroundColor === 'transparent';
      const sinRelleno = parseFloat(cs.paddingLeft) === 0 && parseFloat(cs.paddingTop) === 0;
      if (sinFondo && sinRelleno && parseFloat(cs.borderTopWidth) === 0) {
        sospechosas.push(el.className);
      }
    }
    return [...new Set(sospechosas)].slice(0, 6);
  });

  if (huerfanas.length) {
    failures++;
    console.error(`[CLASES] ${name} tiene clases sin ninguna regla detrás: ${JSON.stringify(huerfanas)}`);
  }
}

// Ningún `.card` puede quedar sin su `.card-body` adentro: `card` declara
// `display: flex` en columna, así que un `.card` sin `.card-body` mete a sus
// hijos directos en ese layout flex en vez del bloque que esperan — es un
// error de maquetado, no una tarjeta que quedó sin migrar (`.panel` ya no
// existe: no queda contra qué migrar). Se mira en el DOM y no en el fuente
// porque una clase la puede armar un `.js` o una isla en tiempo de ejecución,
// donde un `grep` no llega.
async function revisarCardSinBody(page, name) {
  const sinBody = await page.evaluate(
    () => document.querySelectorAll('.card:not(:has(> .card-body))').length
  );
  if (sinBody > 0) {
    failures++;
    console.error(`[PANEL] ${name}: ${sinBody} elementos \`card\` sin \`card-body\`: es un error de maquetado, no una tarjeta sin migrar`);
  }
}

// Contraste WCAG del texto contra su fondo EFECTIVO: el fondo del elemento
// compuesto sobre el de cada ancestro hasta el primero opaco, y el texto
// compuesto sobre ese resultado. Un color con alfa medido sin componer da un
// número que en pantalla no existe.
//
// Los colores se leen pintándolos en un canvas: `getComputedStyle` devuelve
// `oklab(…)` o `color(srgb …)` según cómo se declaró el color, y el canvas
// los resuelve todos a sRGB de 8 bits.
async function medirContraste(page, selector) {
  return page.evaluate((sel) => {
    const ctx = document.createElement('canvas').getContext('2d', { willReadFrequently: true });
    const rgba = (css) => {
      ctx.clearRect(0, 0, 1, 1);
      ctx.fillStyle = '#000';
      ctx.fillStyle = css;
      ctx.fillRect(0, 0, 1, 1);
      const [r, g, b, a] = ctx.getImageData(0, 0, 1, 1).data;
      return [r, g, b, a / 255];
    };
    const sobre = (arriba, abajo) => [0, 1, 2].map((i) => arriba[i] * arriba[3] + abajo[i] * (1 - arriba[3])).concat(1);
    const fondoDe = (el) => {
      const capas = [];
      for (let n = el; n && n.nodeType === 1; n = n.parentElement) {
        const c = rgba(getComputedStyle(n).backgroundColor);
        if (c[3] > 0) capas.push(c);
        if (c[3] >= 1) break;
      }
      let color = [255, 255, 255, 1];
      for (let i = capas.length - 1; i >= 0; i--) color = sobre(capas[i], color);
      return color;
    };
    // La opacidad de un ancestro atenúa el grupo entero —texto y fondo— sobre
    // lo que hay DETRÁS de ese ancestro. Un chip adentro de un comentario ya
    // atendido (`.feedback-item.is-addressed`, `opacity: .72`) se ve con menos
    // contraste del que da medirlo a opacidad plena.
    const atenuacion = (el) => {
      let o = 1;
      let exterior = null;
      for (let n = el; n && n.nodeType === 1; n = n.parentElement) {
        const op = parseFloat(getComputedStyle(n).opacity);
        if (op < 1) { o *= op; exterior = n; }
      }
      return { o, detras: exterior && exterior.parentElement ? fondoDe(exterior.parentElement) : null };
    };
    const luminancia = ([r, g, b]) => {
      const f = (v) => { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
      return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
    };

    return [...document.querySelectorAll(sel)]
      .filter((el) => el.getClientRects().length > 0 && el.textContent.trim())
      .map((el) => {
        const cs = getComputedStyle(el);
        let fondo = fondoDe(el);
        let texto = sobre(rgba(cs.color), fondo);
        // La superficie de atrás y el borde del chip, para `[PASTILLA]`.
        //
        // El borde sólo cuenta si TIENE ancho: con `border-width: 0` el color
        // computado sigue siendo un color —`currentColor` por default— y
        // contarlo daría por definida una pastilla que no se dibuja. Se lee
        // `borderTopColor` y no `borderColor`, que con los cuatro lados
        // distintos devuelve un shorthand que el canvas no sabe pintar.
        let superficie = fondoDe(el.parentElement);
        let borde = parseFloat(cs.borderTopWidth) > 0
          ? sobre(rgba(cs.borderTopColor), superficie)
          : superficie;
        const { o, detras } = atenuacion(el);
        if (o < 1 && detras) {
          // La superficie y el borde se atenúan con el chip: están adentro del
          // mismo grupo. Atenuar sólo el chip infla la diferencia.
          fondo = sobre([...fondo.slice(0, 3), o], detras);
          texto = sobre([...texto.slice(0, 3), o], detras);
          superficie = sobre([...superficie.slice(0, 3), o], detras);
          borde = sobre([...borde.slice(0, 3), o], detras);
        }
        const contraste = (a, b) => {
          const [claro, oscuro] = [luminancia(a), luminancia(b)].sort((x, y) => y - x);
          return (claro + 0.05) / (oscuro + 0.05);
        };
        return {
          clase: el.className,
          texto: el.textContent.trim().slice(0, 40),
          ratio: contraste(texto, fondo),
          estiloDeBorde: parseFloat(cs.borderTopWidth) > 0 ? cs.borderTopStyle : 'none',
          // Las dos mitades por separado: `[PASTILLA]` se queda con la más
          // fuerte, pero saber CUÁL de las dos define la pastilla es lo que
          // permite descontar un borde que no cubre todo el perímetro.
          pastillaDeFondo: contraste(fondo, superficie),
          pastillaDeBorde: contraste(borde, superficie),
          // Lo más FUERTE de los dos: cualquiera que llegue al piso deja la
          // pastilla definida.
          pastilla: Math.max(contraste(fondo, superficie), contraste(borde, superficie))
        };
      });
  }, selector);
}

// El medidor se prueba contra valores conocidos ANTES de creerle a lo que dice
// de las pantallas. Los dos con alfa valen 3,98 exactos; el canvas guarda el
// alfa en 8 bits (128/255 y no 0,5) y da entre 3,95 y 4,00, así que se espera
// 3,97 con 0,05 de tolerancia. Un medidor de contraste que compone mal el alfa infla los
// números —pasó en la fase 1: un 1.49:1 se leyó como 13.56:1— y una guarda que
// siempre pasa es peor que ninguna.
// Los casos de arriba son todos acromáticos (R=G=B): con pesos por canal que
// suman 1, cualquier combinación de pesos —aunque estén cambiados de canal—
// da el mismo resultado ahí. `rojo puro` y `azul puro` son los que detectan
// un peso de canal invertido: con los pesos cambiados darían 8,59 y 4,00 en
// vez de 4,00 y 8,59. Y `atenuado a la mitad` prueba que la opacidad de un
// ancestro atenúa el contraste: negro sobre blanco a través de un grupo con
// `opacity:.5` se ve como un gris de 127,5, no como negro puro.
async function probarMedidorDeContraste(page) {
  await page.setContent(`
    <body style="margin:0;background:#fff">
      <span data-esperado="21" style="color:#000;background:#fff">negro sobre blanco</span>
      <span data-esperado="4.54" style="color:#767676;background:#fff">el gris justo de WCAG</span>
      <span data-esperado="3.97" style="color:rgba(0,0,0,.5);background:#fff">texto con alfa</span>
      <div style="background:#000">
        <span data-esperado="3.97" style="color:#fff;background:rgba(255,255,255,.5)">fondo con alfa sobre negro</span>
      </div>
      <span data-esperado="21" style="color:oklch(0% 0 0);background:oklch(100% 0 0)">oklch</span>
      <span data-esperado="4.00" style="color:#f00;background:#fff">rojo puro</span>
      <span data-esperado="8.59" style="color:#00f;background:#fff">azul puro</span>
      <div style="background:#fff"><div style="opacity:.5">
        <span data-esperado="3.98" style="color:#000;background:#fff">atenuado a la mitad</span>
      </div></div>
    </body>`);
  const medidos = await medirContraste(page, '[data-esperado]');
  const esperados = await page.$$eval('[data-esperado]', (els) => els.map((e) => Number(e.dataset.esperado)));
  if (medidos.length !== esperados.length) {
    failures++;
    console.error(`[CONTRASTE] el medidor midió ${medidos.length} de ${esperados.length} valores conocidos`);
  }
  medidos.forEach((m, i) => {
    if (Math.abs(m.ratio - esperados[i]) > 0.05) {
      failures++;
      console.error(`[CONTRASTE] el medidor está mal: «${m.texto}» dio ${m.ratio.toFixed(2)} y es ${esperados[i]}`);
    }
  });
}

// El medidor de pastilla se prueba contra valores conocidos ANTES de creerle.
// Los seis casos están elegidos para que cada uno falle si el medidor está mal
// de una forma distinta:
//
//   - «relleno visible»      el relleno se mide, y el borde de ancho 0 no suma
//   - «sin relleno ni borde» el caso que la guarda existe para cazar: 1,00
//   - «solo borde»           el borde define la pastilla sin relleno
//   - «borde sin ancho»      un `border-color` con `border-width: 0` NO cuenta.
//                            Sin este caso, el medidor lo daría por bueno y la
//                            guarda pasaría en verde sobre un chip sin pastilla
//   - «relleno sobre gris»   se compone contra la SUPERFICIE y no contra
//                            blanco, que es el bug entero
//   - «atenuado sobre gris»  la opacidad de un ancestro atenúa el chip Y su
//                            superficie, así que la diferencia no se infla.
//                            La superficie de adentro del grupo tiene que ser
//                            OPACA y distinta del fondo de afuera: con un
//                            grupo atenuado sobre blanco y superficie
//                            transparente, atenuar blanco sobre blanco da
//                            blanco y el caso mide lo mismo con y sin las dos
//                            líneas que protege —medido: 1,1447 en los dos—.
//                            Así mide 1,251 bien y 1,895 mutado
async function probarMedidorDePastilla(page) {
  await page.setContent(`
    <body style="margin:0;background:#fff">
      <div style="background:#fff">
        <span data-pastilla="1.320" style="background:#e0e0e0;border:0">relleno visible</span>
        <span data-pastilla="1.000" style="background:transparent;border:0">sin relleno ni borde</span>
        <span data-pastilla="1.819" style="background:transparent;border:1px solid #c0c0c0">solo borde</span>
        <span data-pastilla="1.000" style="background:transparent;border:0 solid #808080">borde sin ancho</span>
      </div>
      <div style="background:#f5f5f5">
        <span data-pastilla="1.211" style="background:#e0e0e0;border:0">relleno sobre gris</span>
      </div>
      <div style="background:#fff"><div style="opacity:.5"><div style="background:#b0b0b0">
        <span data-pastilla="1.251" style="background:#e0e0e0;border:0">atenuado sobre gris</span>
      </div></div></div>
    </body>`);
  const medidos = await medirContraste(page, '[data-pastilla]');
  const esperados = await page.$$eval('[data-pastilla]', (els) => els.map((e) => Number(e.dataset.pastilla)));
  if (medidos.length !== esperados.length) {
    failures++;
    console.error(`[PASTILLA] el medidor midió ${medidos.length} de ${esperados.length} valores conocidos`);
  }
  medidos.forEach((m, i) => {
    if (Math.abs(m.pastilla - esperados[i]) > 0.01) {
      failures++;
      console.error(`[PASTILLA] el medidor está mal: «${m.texto}» dio ${m.pastilla.toFixed(3)} y es ${esperados[i]}`);
    }
  });
}

// Los componentes suaves de DaisyUI (`badge-soft`, `alert-soft`) pintan el
// texto con el color PURO del tema, y los colores que la hoja usaba para el
// texto de un chip (`--ok`, `--warn`, `--danger`) están oscurecidos justamente
// porque puros no llegaban. Esto dice cuál hay que ajustar, en cada pantalla.
async function revisarContraste(name, medidos) {
  const bajos = medidos.filter((m) => m.ratio < 4.5);
  const unicos = [...new Map(bajos.map((m) => [m.clase, m])).values()].slice(0, 6);
  if (unicos.length) {
    failures++;
    console.error(`[CONTRASTE] ${name}: ${unicos.map((m) => `«${m.texto}» (${m.clase}) ${m.ratio.toFixed(2)}:1`).join(' · ')}`);
  }
}

// La pastilla de un chip o de un aviso: que se lea COMO pastilla y no como
// texto de color suelto.
//
// POR QUÉ EXISTE: `badge-soft` de DaisyUI mezcla su fondo contra
// `--color-base-100` —o sea contra BLANCO— y no contra la superficie que tiene
// detrás. Sobre una tarjeta base-200 (`.step-card--locked`, un comentario
// atendido, una fila fuera del corte) el tinte cae justo en la luminosidad del
// fondo y la pastilla desaparece: medido, 1,02:1 en el builder con el flujo
// arrancado, donde se veía como si el chip nunca hubiera existido.
//
// `.alert` mide igual y con el mismo piso. `alert-soft` arrastraba
// EXACTAMENTE el mismo defecto —8% de relleno y 10% de borde, los dos
// mezclados contra `--color-base-100`— y estuvo fuera de esta guarda mientras
// el chip ya estaba adentro, así que nada miraba la única familia que todavía
// lo tenía. La hoja lo arregla igual que el chip (`.alert-soft`, con alfa
// sobre `currentColor`).
//
// Extenderlo son DOS selectores, no uno, y el segundo es fácil de no ver: acá
// abajo, y el filtro propio del muestrario (`revisarMuestrario`), que se
// quedaba con las clases que empiezan en `badge `. Lo que el segundo agrega es
// COBERTURA POR VARIANTE en cada tema: de las tres de aviso, la pasada oscura
// muestra `alert-warning` —`99-oscuro-idear` lo tiene, el de «Ya hay ideas
// postuladas…» de `steps/_campos_editor`— y no muestra ninguna de
// `alert-success` ni de `alert-error`. El muestrario YA inyecta las tres para
// `[CONTRASTE]`; sin sumarlo, esas dos no medirían pastilla en oscuro jamás.
// Lo que no hace falta tocar es el medidor: lo que `medirContraste` compone
// —el fondo real de atrás, el borde sólo si tiene ancho, la atenuación de los
// ancestros— no sabe ni le importa qué componente está midiendo.
//
// El piso es 1,25:1 y no 3:1: el TEXTO del chip ya pasa 4,5:1 —eso lo mide
// `[CONTRASTE]`— así que la pastilla no carga información y WCAG 1.4.11 no
// aplica. 1,25 sale de lo que hoy funciona: el chip neutro mide 1,201 y se lee
// perfecto.
//
// LO QUE NO VE, y son tres:
//
//   - Un `.badge` sin texto. El filtro es el de `medirContraste`, y hoy no
//     existe ninguno —el punto de estado del drawer es `flow-drawer__punto`,
//     con guarda propia y piso de 3:1, porque ahí el color SÍ es la
//     información—. Si algún día hay un chip vacío, este piso le queda corto.
//   - Una pantalla sin ningún `.badge` ni `.alert`: mide cero y pasa. Si los
//     chips dejaran de llamarse `badge` —que es lo que pasó cuando
//     `.status-chip` pasó a `badge`— esto quedaría verde sin medir nada. Lo
//     tapan el spec de Ruby «todos los chips son badge» y el conteo del
//     muestrario, que sí exige haber medido tantas muestras como declara.
//   - Un borde punteado se acredita entero. `border-dashed` cubre bastante
//     menos superficie que uno sólido y acá se cuentan igual; el nodo salteado
//     del mapa del flujo es el caso vivo.
const PISO_DE_PASTILLA = 1.25;

// Un borde PUNTEADO dibuja más o menos la mitad del perímetro, y hasta acá se
// acreditaba igual que uno sólido: el chip llegaba al piso por un borde que en
// pantalla está la mitad del tiempo ausente. El caso vivo es el nodo salteado
// del mapa del flujo, que comparte `badge-soft` con el pendiente —mismo fondo,
// mismo texto— y se distingue SÓLO por el punteado.
//
// Medido: su fondo da 1,081 en claro y 1,092 en oscuro, o sea POR DEBAJO del
// piso normal; lo que lo hacía pasar era el borde, con 1,957 y 2,422. Así que
// no es una hipótesis: hoy hay exactamente un chip cuya pastilla la sostiene un
// borde a medio dibujar.
//
// El piso más alto sale de la misma cuenta que el otro, no de elegir un número:
// 1,25 está a 0,25 de 1,0 —el punto donde no hay pastilla— y un borde que cubre
// la mitad tiene que llegar al doble de esa distancia. De ahí 1,50. Los 1,957 y
// 2,422 de hoy lo pasan con margen, y se cae si el punteado se afloja.
//
// Se aplica SÓLO cuando el borde es lo que sostiene la pastilla: si el fondo ya
// llega solo, el punteado es decoración y el piso normal alcanza.
const PISO_DE_PASTILLA_PUNTEADA = 1.5;

function pisoDePastillaDe(m) {
  const punteado = m.estiloDeBorde === 'dashed' || m.estiloDeBorde === 'dotted';
  return punteado && m.pastillaDeBorde > m.pastillaDeFondo
    ? PISO_DE_PASTILLA_PUNTEADA
    : PISO_DE_PASTILLA;
}

// Cuántos chips y avisos midió la corrida entera. Una pantalla sin ningún
// `.badge` ni `.alert` mide cero y pasa, y con 71 pantallas ese silencio se lee
// como cobertura: si los chips dejaran de llamarse `badge` —que es lo que pasó
// cuando `.status-chip` pasó a `badge`— esta guarda quedaría verde sin medir
// NADA. Es el mismo motivo por el que `[RITMO]` y `[RELLENO]` cuentan.
//
// El piso es FLOJO a propósito, y la primera versión de esto no lo era: se puso
// en 700 contra un día que medía 758-810, y unas horas después la misma corrida
// sobre el mismo commit daba 634 y fallaba. Lo que cambió fue la BASE de
// desarrollo —el recorrido camina datos sembrados, y los chips de estado salen
// de las ideas y los módulos que haya—, no el código: se comprobó corriendo
// `master` limpio, sin los cambios en curso, y midió 634 igual.
//
// O sea que un piso ajustado al número de ayer es un falso rojo esperando a la
// próxima resembrada. Y no hace falta: lo que esto tiene que distinguir es
// «midió algo» de «midió NADA», que es el caso real —si los chips dejaran de
// llamarse `badge`, como pasó cuando `.status-chip` pasó a `badge`, la guarda
// quedaría verde sin medir nada—. Para eso alcanza un orden de magnitud.
//
// A diferencia de `[RELLENO]`, que puede ir pegado (270 medidos, piso 250)
// porque los `card-body` son ESTRUCTURA y no dependen de los datos.
const PISO_DE_PASTILLAS = 300;
let pastillasMedidas = 0;

async function revisarPastilla(name, medidos) {
  pastillasMedidas += medidos.length;
  const bajos = medidos.filter((m) => m.pastilla < pisoDePastillaDe(m));
  const unicos = [...new Map(bajos.map((m) => [m.clase, m])).values()].slice(0, 6);
  if (unicos.length) {
    failures++;
    console.error(`[PASTILLA] ${name}: ${unicos.map((m) => `«${m.texto}» (${m.clase}) ${m.pastilla.toFixed(2)}:1`).join(' · ')}`);
  }
}

// Los puntos de estado del drawer no tienen texto, así que `revisarContraste`
// —que mide texto contra su fondo— no los ve. Son información no textual: el
// piso es el 3:1 de WCAG 1.4.11, contra el panel oscuro donde viven. El
// neutro estuvo en 2,57:1 hasta el plan 2b sin que nada lo dijera.
//
// `esperados` es CUÁNTOS puntos tiene que mostrar ese drawer, y falla si no
// están. Sin eso la guarda se cumple sola: `querySelectorAll` que no matchea
// devuelve una lista vacía, y filtrar una lista vacía no reporta nada, así que
// un renombre de la clase dejaría `[PUNTOS]` en verde midiendo CERO. `[CLASES]`
// tampoco lo vería —la clase nueva sí tendría regla detrás, que es lo único que
// ese chequeo mira—. Es el modo de falla que la pasada oscura del muestrario ya
// sufrió, y se ataja igual que ahí: fallando cuando mide menos de lo declarado.
// El número va fijo, como `PASOS_DE_SIN_FORMULARIO`: sacarlo de la propia
// página es volver a la guarda que se cumple sola.
async function revisarPuntos(page, name, tema, esperados) {
  const medidos = await page.evaluate(() => {
    const ctx = document.createElement('canvas').getContext('2d', { willReadFrequently: true });
    const rgba = (css) => {
      ctx.clearRect(0, 0, 1, 1);
      ctx.fillStyle = '#000';
      ctx.fillStyle = css;
      const [r, g, b, a] = (ctx.fillRect(0, 0, 1, 1), ctx.getImageData(0, 0, 1, 1).data);
      return [r, g, b, a / 255];
    };
    const luminancia = ([r, g, b]) => {
      const f = (v) => { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
      return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
    };
    const fondo = (el) => {
      for (let n = el.parentElement; n; n = n.parentElement) {
        const c = rgba(getComputedStyle(n).backgroundColor);
        if (c[3] >= 1) return c;
      }
      return [255, 255, 255, 1];
    };
    return [...document.querySelectorAll('.flow-drawer__punto')].map((el) => {
      const [claro, oscuro] = [luminancia(rgba(getComputedStyle(el).backgroundColor)), luminancia(fondo(el))].sort((a, b) => b - a);
      return { clase: el.className, ratio: (claro + 0.05) / (oscuro + 0.05) };
    });
  });
  if (medidos.length !== esperados) {
    failures++;
    console.error(`[PUNTOS] ${name} (${tema}): midió ${medidos.length} puntos y el drawer tiene que mostrar ${esperados}`);
  }
  const bajos = medidos.filter((m) => m.ratio < 3);
  if (bajos.length) {
    failures++;
    const unicos = [...new Map(bajos.map((m) => [m.clase, m])).values()];
    console.error(`[PUNTOS] ${name} (${tema}): ${unicos.map((m) => `${m.clase} ${m.ratio.toFixed(2)}:1`).join(' · ')}`);
  }
}

// Las DOS variantes del chip de estado del drawer, sobre el panel oscuro.
//
// POR QUÉ EXISTE: `[CONTRASTE]` y `[PASTILLA]` ya miden el chip donde aparece,
// pero el recorrido no muestra las dos variantes en los dos temas. Medido:
// TODAS las pantallas oscuras que tienen drawer son de desafíos EN CURSO
// —`91-oscuro-desafio` y las de módulo son de `merma-bodega`,
// `98-oscuro-salteado` es `con-salteado`, y las otras tres no tienen drawer—,
// así que el chip NEUTRO no se medía nunca en oscuro. Es la mitad de la regla.
//
// No sirve el muestrario, que es el mecanismo para esto en el resto del
// script: inyecta en una `.card-body`, y acá toda la validez de la medición
// está en la SUPERFICIE. Así que se le pone cada variante al chip que ya está
// en el panel, se mide ahí, y se lo deja como estaba.
//
// El piso es 4,5:1, que es el de un texto: a diferencia de los puntos, acá el
// color no carga la información —la palabra está escrita— pero hay que poder
// leerla. En tema claro el neutro sin tratar mide 1:1, porque `base-content`
// es casi el mismo casi-negro que el panel.
const VARIANTES_DEL_CHIP_DE_ESTADO = ['badge-soft', 'badge-soft badge-primary'];

async function revisarChipDelDrawer(page, name, tema) {
  const chip = page.locator('.flow-drawer__estado');
  if (!(await chip.count())) {
    failures++;
    console.error(`[ESTADO-DRAWER] ${name} (${tema}): no hay chip de estado en el drawer`);
    return;
  }

  // La base sale de lo que la app ACABA de renderizar, sin las variantes de
  // color: escribirla a mano ataba la guarda a una copia del helper. Si
  // `CHIP_DE_ESTADO` dejara de ser `badge-soft`, una base escrita a mano
  // seguiría midiendo un chip suave mientras la pantalla pinta uno sólido, y
  // reportaría verde sobre algo que nadie ve.
  const original = await chip.first().getAttribute('class');
  const base = original.replace(/\bbadge-(soft|primary|secondary|success|warning|error)\b/g, '').replace(/\s+/g, ' ').trim();

  const medidos = [];
  for (const variante of VARIANTES_DEL_CHIP_DE_ESTADO) {
    await page.evaluate(([clase]) => {
      document.querySelector('.flow-drawer__estado').className = clase;
    }, [`${base} ${variante}`]);
    const [m] = await medirContraste(page, '.flow-drawer__estado');
    // `medirContraste` saltea lo que no se ve y lo que no tiene texto, así que
    // devuelve una lista VACÍA sin fallar. Sin esta rama, `{ variante,
    // ...undefined }` no trae `ratio`, `undefined < 4.5` es false y los dos
    // filtros de abajo pasan: un chip oculto dejaba la guarda en verde.
    if (!m) {
      failures++;
      console.error(`[ESTADO-DRAWER] ${name} (${tema}): «${variante}» no se pudo medir`);
      continue;
    }
    medidos.push({ variante, ...m });
  }
  await page.evaluate((clase) => { document.querySelector('.flow-drawer__estado').className = clase; }, original);

  // Contra un literal y no contra `VARIANTES.length`, que es el mismo número
  // del que sale el bucle: así el chequeo se cumplía solo, y con el arreglo
  // vacío la guarda entera pasaba sin haber medido nada. Es el mismo error
  // que `esperados` evita en `revisarPuntos`, treinta líneas más arriba.
  if (medidos.length !== 2) {
    failures++;
    console.error(`[ESTADO-DRAWER] ${name} (${tema}): midió ${medidos.length} variantes y son 2`);
  }
  const bajos = medidos.filter((m) => m.ratio < 4.5);
  if (bajos.length) {
    failures++;
    console.error(`[ESTADO-DRAWER] ${name} (${tema}): ${bajos.map((m) => `«${m.variante}» ${m.ratio.toFixed(2)}:1`).join(' · ')}`);
  }
  const sinPastilla = medidos.filter((m) => m.pastilla < PISO_DE_PASTILLA);
  if (sinPastilla.length) {
    failures++;
    console.error(`[ESTADO-DRAWER] ${name} (${tema}): sin pastilla · ${sinPastilla.map((m) => `«${m.variante}» ${m.pastilla.toFixed(3)}`).join(' · ')}`);
  }
}

// Las variantes que la app usa, medidas en el tema activo aunque ninguna
// pantalla del recorrido las muestre en ese tema. Se inyectan en una tarjeta
// (`.card-body`) de una pantalla real —con la hoja y el tema de verdad—, se
// miden y se sacan. Sin esto la pasada oscura midió CERO avisos y dio verde:
// las cuatro pantallas que recorre no tienen ninguno.
//
// Falla también si mide menos muestras de las que declara, para que no
// vuelva a pasar en verde sin haber medido nada.
const MUESTRARIO = [
  'alert alert-soft alert-success',
  'alert alert-soft alert-warning',
  'alert alert-soft alert-error',
  // Cada chip distinto que devuelve `EstilosHelper`. Un spec de Ruby
  // (`estilos_helper_spec.rb`) falla si el helper devuelve uno que no está
  // acá: si no, esa variante nunca se mide en el tema en que ninguna pantalla
  // la muestre.
  'badge badge-soft badge-sm font-semibold whitespace-nowrap',
  'badge badge-soft badge-primary badge-sm font-semibold whitespace-nowrap',
  'badge badge-soft badge-success badge-sm font-semibold whitespace-nowrap',
  'badge badge-soft badge-warning badge-sm font-semibold whitespace-nowrap',
  // El veredicto de un testing (`CHIP_DE_VEREDICTO`). «Factible» y «con
  // reservas» comparten cadena con `CHIP_DE_ESTADO` (arriba); «no factible»
  // es la primera variante `badge-error` en tamaño `badge-sm`.
  'badge badge-soft badge-error badge-sm font-semibold whitespace-nowrap',
  'badge badge-soft badge-primary badge-xs font-semibold whitespace-nowrap ml-1.5',
  'badge badge-soft badge-success badge-xs font-semibold whitespace-nowrap ml-1.5',
  'badge badge-soft badge-secondary badge-xs font-semibold whitespace-nowrap ml-1.5',
  'badge badge-soft badge-warning badge-xs font-semibold whitespace-nowrap ml-1.5',
  'badge badge-soft badge-primary badge-xs font-bold uppercase',
  'badge badge-soft badge-warning badge-xs font-bold uppercase',
  'badge badge-soft badge-error badge-xs font-bold uppercase',
  'badge badge-soft badge-secondary badge-xs font-bold tracking-wide',
  // Los nodos del mapa del flujo (`CLASE_DE_NODO_DE_FLUJO`). El salteado
  // comparte `badge-soft` con el pendiente —mismo fondo, mismo texto— y se
  // distingue solo por `border-dashed`.
  'badge badge-soft badge-sm',
  'badge badge-soft badge-primary badge-sm font-semibold',
  'badge badge-soft badge-success badge-sm',
  'badge badge-soft badge-sm border-dashed',
  // Las marcas sueltas (`EstilosHelper::CHIPS`).
  'badge badge-soft badge-xs font-mono font-semibold ml-1.5',
  'badge badge-soft badge-warning badge-xs font-semibold ml-1',
  'badge badge-primary badge-xs font-semibold whitespace-nowrap ml-2',
  'badge badge-soft badge-error badge-xs font-semibold whitespace-nowrap ml-2',
  'badge badge-soft badge-warning badge-xs font-semibold whitespace-nowrap ml-2',
  'badge badge-soft badge-primary badge-xs font-bold ml-1.5',
  'badge badge-soft badge-xs font-semibold',
  'badge badge-soft badge-secondary badge-xs font-semibold'
];

// Los chips de un comentario ya atendido —el tipo, la resolución y la marca
// de IA— dentro de la peor ronda real: una ronda CERRADA (`.feedback-round
// .feedback-round--cerrada`, abierta con `open` para que se renderice) con
// un item `.is-addressed` adentro. Ya no se atenúan (ver el comentario en
// `.feedback-item.is-addressed` de `application.css`), pero la guarda arma
// la misma estructura que `ideas/show` y `shared/_feedback_item` así que si
// alguien vuelve a poner una opacidad sobre cualquiera de los dos
// contenedores, estas muestras bajan y la guarda lo marca.
const MUESTRARIO_ATENUADO = [
  'badge badge-soft badge-primary badge-xs font-bold uppercase',
  'badge badge-soft badge-warning badge-xs font-bold uppercase',
  'badge badge-soft badge-error badge-xs font-bold uppercase',
  'badge badge-soft badge-success badge-sm font-semibold whitespace-nowrap',
  'badge badge-soft badge-secondary badge-xs font-bold tracking-wide'
];

async function revisarMuestrario(page, tema) {
  await page.evaluate(({ plenas, atenuadas }) => {
    const destino = document.querySelector('.card-body') || document.querySelector('.app-main') || document.body;
    const caja = document.createElement('div');
    caja.dataset.muestrario = '';
    const muestra = (clase, padre) => {
      const el = document.createElement('div');
      el.className = clase;
      el.dataset.muestra = '';
      el.textContent = 'Muestra de contraste';
      padre.appendChild(el);
    };
    for (const clase of plenas) muestra(clase, caja);
    // El peor caso real: un comentario atendido adentro de una ronda cerrada.
    // Con los mismos elementos y clases que `ideas/show` y
    // `shared/_feedback_item`, así cualquier atenuación que se les vuelva a
    // poner baja estas muestras y la guarda lo marca.
    const ronda = document.createElement('details');
    ronda.className = 'feedback-round feedback-round--cerrada';
    ronda.open = true;
    const lista = document.createElement('ul');
    lista.className = 'feedback-list';
    const item = document.createElement('li');
    item.className = 'feedback-item is-addressed';
    for (const clase of atenuadas) muestra(clase, item);
    lista.appendChild(item);
    ronda.appendChild(lista);
    caja.appendChild(ronda);
    destino.appendChild(caja);
  }, { plenas: MUESTRARIO, atenuadas: MUESTRARIO_ATENUADO });
  const medidos = await medirContraste(page, '[data-muestrario] [data-muestra]');
  await page.evaluate(() => document.querySelector('[data-muestrario]')?.remove());

  const esperadas = MUESTRARIO.length + MUESTRARIO_ATENUADO.length;
  if (medidos.length !== esperadas) {
    failures++;
    console.error(`[CONTRASTE] muestrario ${tema}: se midieron ${medidos.length} de ${esperadas} muestras`);
  }
  const bajos = medidos.filter((m) => m.ratio < 4.5);
  if (bajos.length) {
    failures++;
    console.error(`[CONTRASTE] muestrario ${tema}: ${bajos.map((m) => `${m.clase} ${m.ratio.toFixed(2)}:1`).join(' · ')}`);
  }

  // Y la pastilla, por la MISMA razón por la que el muestrario existe para el
  // contraste: el recorrido no garantiza mostrar cada variante en cada tema
  // —la pasada oscura son diez pantallas— así que sin esto la pastilla de
  // `no_factible`, del chip de versión o de `evaluador_ia` puede no medirse
  // nunca en oscuro.
  //
  // Encima es el mejor banco que tiene el script: las muestras atenuadas se
  // inyectan dentro de `.feedback-round--cerrada .feedback-item`, que es
  // `background: var(--bg)` — la superficie base-200 donde vivía el bug.
  //
  // Los chips y los avisos, que arrastraban el mismo defecto de DaisyUI (ver
  // `PISO_DE_PASTILLA`). Se filtra por el prefijo y no se mide todo lo que hay
  // adentro: toda clase de chip empieza con `badge ` —hay un spec de Ruby que
  // lo exige— y las tres variantes de aviso, con `alert `.
  const sinPastilla = medidos.filter(
    (m) => /^(badge|alert) /.test(m.clase) && m.pastilla < pisoDePastillaDe(m)
  );
  if (sinPastilla.length) {
    failures++;
    console.error(`[PASTILLA] muestrario ${tema}: ${sinPastilla.map((m) => `${m.clase} ${m.pastilla.toFixed(2)}:1`).join(' · ')}`);
  }
}

// Abre todos los `<details>` de la pantalla, para la FOTO.
//
// NO es cobertura de medición: un `<details>` cerrado NO le saca la caja a sus
// descendientes, así que `medirContraste` y `revisarClasesDescartadas` —que
// filtran por `getClientRects().length > 0`— ya miden lo de adentro con el
// plegable cerrado. Medido de dos formas: contando elementos con caja adentro
// del desglose y de los ajustes (138 y 37, idénticos abierto y cerrado, en los
// dos temas), y metiendo un `.badge` de 1,20:1 adentro del desglose, que
// `[CONTRASTE]` reportó en seis pantallas incluidas las que lo tienen cerrado.
//
// Lo que el plegable sí se lleva es la imagen: las cinco capturas oscuras de
// módulo mostraban el `summary` y nada más, y mirar las capturas es la única
// revisión del rediseño que no hace una máquina.
async function abrirPlegables(page) {
  await page.evaluate(() => document.querySelectorAll('details').forEach((d) => { d.open = true; }));
}

// Monoespaciada es para CÓDIGO y para IDENTIFICADORES, y nada más.
//
// La regla: el texto propio de un elemento mono tiene que ser un identificador
// pelado —letras, dígitos, `_`, `.`, `-`—. «reduccion_merma» y «v3» lo son;
// «veredicto por idea» y «40%» no. La primera versión de esta guarda pedía un
// espacio, y así no veía los números, que es la mitad del requerimiento: `40%`
// no tiene ninguno.
//
// Las superficies de CÓDIGO se exceptúan por selector, porque una fórmula de
// dentaku o un JSON sí llevan espacios y signos. Las que existen de verdad son
// `%pre.code-block` (`ai_runs/show`) y `%code= …to_json`
// (`shared/_ai_suggestion`, servido en diez pantallas); `.code-input` va de
// seguro —hoy es un `<input>`, así que no tiene nodos de texto y no puede
// cambiar el resultado, pero empezaría a importar si pasara a `<textarea>`—.
//
// Mira el texto PROPIO de cada elemento —sus nodos de texto directos— y no el
// heredado: así un contenedor mono con texto suelto se reporta por su cuenta y
// el mismo texto no sale dos veces por estar adentro de un padre mono.
//
// POR QUÉ EXISTE: `.field-list__type` se llama por su primer uso pero es la
// columna de VALOR de una lista de etiqueta/valor, y nueve vistas le mandaban
// prosa, rótulos traducidos y números. Antes del arreglo esto marcaba 13 de las
// 66 pantallas y las 13 eran esa misma clase.
//
// LO QUE NO VE: un identificador de UNA palabra puesto donde va un nombre. Por
// construcción pasa el filtro. El desglose mostraba `criterion_key` y esto lo
// dejaba pasar; lo cuida un spec de Ruby («muestra el nombre del snapshot, y en
// el orden del snapshot»).
//
// La prosa partida por un hijo inline SÍ se ve, desde que los nodos de texto
// propios se unen con espacio. Ojo con cómo se prueba eso, porque el ejemplo
// con el que esto estuvo anotado falla de DOS formas a la vez:
//
//   - con un separador que lleva texto —`<span>Impacto<b>·</b>Numerico</span>`—
//     el `<b>` se reporta por su cuenta, porque «·» no es identificador, y la
//     falta del PADRE queda tapada;
//   - y con tilde —«Numérico»— el token fusionado no pasa el filtro ASCII de
//     `IDENTIFICADOR`, así que el padre se reportaba igual y no hay nada que
//     demostrar.
//
// El caso del autotest va sin tilde y con un separador sin texto propio, que es
// la única combinación que de verdad se escapaba.
const SUPERFICIES_DE_CODIGO = 'code, kbd, samp, pre, .code-input';
const IDENTIFICADOR = /^[A-Za-z0-9_.-]+$/;

async function medirMonoEnProsa(page) {
  return page.evaluate(({ selCodigo, reIdent }) => {
    const esIdentificador = new RegExp(reIdent);
    const esMono = (f) => /\bmonospace\b|ui-monospace|menlo|consolas|courier/i.test(f);
    const encontrados = [];
    for (const el of document.querySelectorAll('body *')) {
      if (el.closest(selCodigo)) continue;
      // Con espacio y no pegado: dos fragmentos separados por un hijo inline se
      // FUSIONABAN en un token —«Impacto» + «Numerico» = «ImpactoNumerico»— que
      // pasaba por identificador. SIN TILDE, y no es un detalle del ejemplo:
      // `IDENTIFICADOR` es ASCII puro, así que «ImpactoNumérico» nunca pasó el
      // filtro y esa forma se reportaba igual. La fusión sólo se escapa cuando
      // los dos fragmentos son ASCII.
      //
      // Con un solo nodo no cambia nada, y lo que ya fallaba el test sigue
      // fallándolo: el cambio sólo puede reportar de más, nunca de menos. Lo
      // que habilita es un falso positivo posible —dos identificadores
      // separados por un hijo sin texto, «v3» + ícono + «v4», leen como prosa—.
      // Hoy da cero en todo el recorrido; cuando aparezca, la respuesta es darle
      // a cada identificador su propio elemento mono, no aflojar el join.
      //
      // SIN el número de pantallas a propósito: decía «las 66» y hoy son 71, que
      // es el mismo desfasaje que `capturar()` explica para su propio
      // comentario, el README y CLAUDE.md. Lo que el recorrido midió lo imprime
      // la corrida.
      const propio = [...el.childNodes]
        .filter((n) => n.nodeType === 3)
        .map((n) => n.textContent)
        .join(' ')
        .trim();
      if (!propio || esIdentificador.test(propio)) continue;
      if (!esMono(getComputedStyle(el).fontFamily)) continue;
      if (!el.getClientRects().length) continue;
      const clase = typeof el.className === 'string' && el.className
        ? el.className
        : el.tagName.toLowerCase();
      encontrados.push({ clase, texto: propio.slice(0, 60) });
    }
    return encontrados;
  }, { selCodigo: SUPERFICIES_DE_CODIGO, reIdent: IDENTIFICADOR.source });
}

// El detector, contra casos conocidos. Sin esto la guarda pasa en verde en las
// 66 pantallas tanto si funciona como si un cambio la dejó midiendo cero, que
// es indistinguible desde afuera.
//
// Cada caso existe por UNA línea del detector: sacarla hace que este autotest
// falle. `prosa-normal` por `esMono`, `clave-mono` y `numero-mono` por el
// filtro de identificador, `formula-en-pre` y `json-en-code` por el `closest`
// —los dos, porque el selector tiene varias entradas y exceptuar sólo `pre`
// dejaría fuera la que más pesa en pantalla—, `oculta-mono` por
// `getClientRects`, `envoltorio-mono` por mirar el texto PROPIO —con
// `textContent` el envoltorio se reportaría además de su hija, o sea el mismo
// texto dos veces— y `prosa-partida` por el `join(' ')`: pegados, sus dos
// fragmentos dan «ImpactoNumerico» y pasan por identificador.
async function probarDetectorDeMono(page) {
  await page.setContent(`
    <body style="margin:0;font-family:Inter,sans-serif">
      <span class="prosa-mono" data-mono="1" style="font-family:ui-monospace,monospace">veredicto por idea</span>
      <span class="numero-mono" data-mono="1" style="font-family:ui-monospace,monospace">40%</span>
      <span class="clave-mono" data-mono="0" style="font-family:ui-monospace,monospace">reduccion_merma</span>
      <span class="version-mono" data-mono="0" style="font-family:ui-monospace,monospace">v3</span>
      <span class="prosa-normal" data-mono="0">veredicto por idea</span>
      <pre><span class="formula-en-pre" data-mono="0" style="font-family:ui-monospace,monospace">(impacto + esfuerzo) / 2</span></pre>
      <code><span class="json-en-code" data-mono="0" style="font-family:ui-monospace,monospace">{ "a": 1 }</span></code>
      <span class="oculta-mono" data-mono="0" style="font-family:ui-monospace,monospace;display:none">no se ve</span>
      <div class="envoltorio-mono" data-mono="0" style="font-family:ui-monospace,monospace"><span class="hija-heredada" data-mono="1">texto de la hija</span></div>
      <span class="prosa-partida" data-mono="1" style="font-family:ui-monospace,monospace">Impacto<b class="separador-sin-texto" data-mono="0"></b>Numerico</span>
      <div class="padre-con-texto" data-mono="1" style="font-family:ui-monospace,monospace">texto del padre
        <span class="otra-hija" data-mono="1">texto de la otra hija</span>
      </div>
    </body>`);
  const marcados = await page.$$eval('[data-mono="1"]', (els) => els.map((e) => e.className));
  const encontrados = (await medirMonoEnProsa(page)).map((c) => c.clase);

  const faltan = marcados.filter((c) => !encontrados.includes(c));
  const sobran = encontrados.filter((c) => !marcados.includes(c));
  if (faltan.length || sobran.length) {
    failures++;
    console.error(`[MONO] el detector está mal: no vio ${JSON.stringify(faltan)} y marcó de más ${JSON.stringify(sobran)}`);
  }
}

async function revisarMonoEnProsa(page, name) {
  const casos = await medirMonoEnProsa(page);
  const unicos = [...new Map(casos.map((c) => [c.clase, c])).values()].slice(0, 6);
  if (unicos.length) {
    failures++;
    console.error(`[MONO] ${name}: monoespaciada donde no hay código ni identificador · ${unicos.map((c) => `«${c.texto}» (${c.clase})`).join(' · ')}`);
  }
}

// La captura y las revisiones que solo piden la pantalla ya pintada.
//
// La mayoría de las pantallas no se abren por URL —se llega a ellas con un
// clic, esperando que monte una isla— y por eso no pasan por `shot()`. La
// revisión de clases descartadas corría en tres pantallas sueltas y el spec
// dice «en cada pantalla del recorrido»: acá adentro corre en todas,
// incluidas las que solo existen después de navegar.
//
// `[TEXTO]`, `[FORMS]` y `[RITMO]` estaban declaradas en `shot()` por la
// misma razón por la que la de clases estaba suelta, y con el mismo
// resultado: `[TEXTO]` afirmaba «se revisa en CADA pantalla» y no era cierto,
// y las otras dos se repetían a mano en cinco lugares, que es como una guarda
// se convierte en una lista de excepciones. Una guarda declarada acá no se
// puede olvidar en una pantalla; una declarada en `shot()` se olvida en todas
// las demás.
//
// Sin números a propósito: este comentario, `README.md` y `CLAUDE.md` los
// tenían, y los tres se desactualizaron cada vez que se sumó una captura. El
// número real lo imprime la corrida al terminar.
// El nombre del criterio en el desglose de una evaluación alinea la columna de
// puntajes con un `min-width: 110px`. Es `min-width` y no `width`, así que un
// nombre que no entre ESTIRA el span y corre el puntaje a la derecha: la columna
// deja de estar alineada y no se nota mirando, porque sigue habiendo un puntaje
// por fila y cada uno se ve bien por su cuenta.
//
// Con las claves de criterio no podía pasar —eran más cortas—; el riesgo nació
// cuando la fila pasó a mostrar el NOMBRE. Estaba anotado al lado de la regla en
// la hoja y medido a mano una sola vez, que es la forma de anotación que este
// repo ya vio envejecer varias veces.
//
// El arreglo, el día que falle, está escrito en la hoja: `flex: 0 0 110px` o una
// grilla de dos columnas en el `li`. NO subir el `min-width`, que sólo corre el
// problema al nombre siguiente.
const ANCHO_DEL_CRITERIO = 110;
// Flojo por el mismo motivo que `PISO_DE_PASTILLAS`, y con la misma historia
// detrás: el número sale de los criterios SEMBRADOS, así que se mueve con la base
// de desarrollo y no con el código. Se miden ~195; el piso sólo tiene que
// distinguir «midió algo» de «midió nada».
const PISO_DE_CRITERIOS = 100;
let criteriosMedidos = 0;

async function revisarAnchoDeCriterio(page, name) {
  const pasados = await page.evaluate((tope) => {
    const medidos = [...document.querySelectorAll('.assessment-detail__criterion')];
    return {
      total: medidos.length,
      largos: medidos
        .filter((el) => el.getBoundingClientRect().width > tope + 0.5)
        .map((el) => `«${el.textContent.trim()}» ${el.getBoundingClientRect().width.toFixed(0)}px`)
        .slice(0, 4)
    };
  }, ANCHO_DEL_CRITERIO);

  criteriosMedidos += pasados.total;
  if (pasados.largos.length) {
    failures++;
    console.error(`[CRITERIO] ${name}: nombres que no entran en ${ANCHO_DEL_CRITERIO}px y desalinean la columna de puntajes: ${pasados.largos.join(' · ')}`);
  }
}

// `[RIEL]` — que el riel exista, marque dónde estás, y SOBREVIVA al angosto.
//
// Lo que esta guarda cuida de verdad es el tercer punto. Abajo de 1024px la hoja
// cambia la grilla, y un riel que se esconda en vez de volverse fila deja la
// app sin navegación global en ese ancho —y ninguna otra captura mira ahí
// (`[REFERENCIA]` mide a 1100, que todavía es escritorio, y sólo ve las
// pantallas de módulo)—. Se mide la posición real, no la clase: un riel con su clase puesta y `display: none`
// tiene la clase igual.
// Medido: 71 pantallas con riel de 76, SIEMPRE las mismas: el riel depende de
// sesión y empresa, no de datos, así que el contador es determinista. Por eso
// el piso va ajustado (66, 93%, como `[RELLENO]`) y no flojo como `[PASTILLA]`
// o `[CRITERIO]`, que varían entre corridas. Cinco de margen son las pantallas
// sin riel que podrían sumarse; un renombre de `.app-rail` lo lleva a cero.
const PISO_DE_RIEL = 66;

let rielesMedidos = 0;

// Las pantallas que legítimamente no marcan ninguna entrada, declaradas una por
// una y a propósito: el riel tiene cinco secciones y una pantalla global que no
// es ninguna de ellas no tiene qué marcar. Hoy es sólo `/notifications`, que no
// cuelga de ningún desafío ni de ningún taller. La lista va angosta —por nombre
// de captura, no por patrón— porque es lo que sostiene la regla: perdonar «cero
// activas» a secas deja la guarda ciega justo para lo que existe. Sumar una
// pantalla acá es una decisión, no un arreglo.
const SIN_ENTRADA_ACTIVA = new Set(['09-13-avisos']);

async function revisarRiel(page, name) {
  const medir = () => page.evaluate(() => {
    const riel = document.querySelector('.app-rail');
    if (!riel) return null;
    const caja = riel.getBoundingClientRect();
    return {
      visible: caja.width > 0 && caja.height > 0,
      entradas: riel.querySelectorAll('.app-rail__item').length,
      activas: riel.querySelectorAll('.app-rail__item--on').length,
      // Vertical si es más alto que ancho; horizontal al revés.
      vertical: caja.height > caja.width
    };
  });
  const r = await medir();

  // Sin riel no es falla: el selector de empresa y el login no lo tienen.
  if (!r) return;
  rielesMedidos++;

  if (!r.visible) {
    failures++;
    console.error(`[RIEL] ${name}: el riel está en el DOM pero no se ve`);
  }
  if (r.vertical === false) {
    failures++;
    console.error(`[RIEL] ${name}: a escritorio el riel salió horizontal; arriba de 1024 tiene que ser una columna`);
  }
  if (r.entradas < 2) {
    failures++;
    console.error(`[RIEL] ${name}: ${r.entradas} entrada(s); todo rol ve al menos Desafíos y Talleres`);
  }
  if (r.activas > 1) {
    failures++;
    console.error(`[RIEL] ${name}: ${r.activas} entradas marcadas como activas a la vez`);
  }
  // Y que marque ALGUNA. La spec le pide a `[RIEL]` tres cosas —que exista, que
  // MARQUE EL ACTIVO y que abajo de 1024 se vuelva fila— y la del medio no
  // estaba cubierta: la guarda sólo fallaba con más de una activa, así que cero
  // activas daba verde. No era hipotético: `step_tests` y `previews` faltaban en
  // la lista de Desafíos y esas pantallas salían con los cinco iconos grises.
  if (r.activas === 0 && !SIN_ENTRADA_ACTIVA.has(name)) {
    failures++;
    console.error(`[RIEL] ${name}: ninguna entrada marcada como activa; el riel no dice dónde estás`);
  }

  // En el angosto: sigue visible y cambió de orientación. A 1000px y no a
  // 1100: el corte de la hoja es `max-width: 1023px`, así que a 1100 el riel
  // TODAVÍA es vertical por diseño y la guarda fallaría en todas las pantallas.
  //
  // Sí, son DOS `setViewportSize` por pantalla, y se quedan. Medido en esta
  // misma imagen de Playwright contra la app corriendo: 71 pares de resize
  // cuestan 2,4 s en total (33,5 ms por pantalla) sobre una corrida de varios
  // minutos que además le pide cosas a la IA de verdad. Hacerlo una sola vez por
  // corrida ahorraría esos 2,4 s y bajaría la cobertura del cambio a fila de 71
  // pantallas a UNA, que es exactamente la clase de recorte que este repo paga
  // caro. No es prolijidad pendiente: está medido y decidido.
  const tamano = page.viewportSize();
  await page.setViewportSize({ width: 1000, height: 900 });
  const angosto = await medir();
  await page.setViewportSize(tamano);
  if (angosto && (!angosto.visible || angosto.vertical)) {
    failures++;
    console.error(`[RIEL] ${name} a 1000px: el riel ${angosto.visible ? 'siguió vertical' : 'desapareció'} — abajo de 1024 tiene que ser una fila`);
  }
}

// `[BANDA]` — que la banda se dibuje y su texto se lea sobre ella.
//
// Dos cosas distintas. Que se dibuje caza la vista que se olvidó el
// `content_for :banda` en la mudanza de las veinte —es edición repetida, que
// es donde más fácil se cuela una—. Y el contraste la mantiene honesta si
// alguna vez se vuelve a tocar el primario: hoy mide 6,06:1, pero nada más lo
// vigila (`[CONTRASTE]` sólo mira `.badge` y `.alert`).
//
let bandasMedidas = 0;
// Medido: 71 pantallas con banda de 76, SIEMPRE las mismas. El piso va EXACTO
// (71) y no al 92% como `[RIEL]` y `[RELLENO]`: esos cuentan ELEMENTOS, que
// varían con los datos, y necesitan holgura. Éste cuenta VISTAS que publican
// `content_for :banda`, un número fijo, y lo único que esta guarda existe para
// cazar es la vista olvidada: con un piso flojo, borrar el `content_for` de una
// sola bajaba el conteo (63 -> 60 medido) y la guarda seguía en verde. Si se
// suma una pantalla con banda, el piso sube con ella.
const PISO_DE_BANDAS = 71;

// Lo único que un spec de Ruby no puede ver: el bundle, el temporizador y el
// endpoint pueden estar los tres en verde y el texto no volver.
//
// Tipea, espera el debounce, RECARGA, y mira que el texto esté. La recarga es el
// punto: sin ella se estaría probando que el navegador conserva lo que acabás de
// escribir, que es cierto sin autoguardado.
//
// Un MISMO selector para tipear y para leer, y acotado a lo que se puede tipear
// Y a lo que `cuerpo()` manda: un `fill` sobre un checkbox o un file revienta, y
// un campo que no empieza con `payload[` (una nota de cambio, por ejemplo) no
// viaja, así que acusaría a un autoguardado sano.
const SELECTOR_DE_CAMPO = 'form[data-draft-url] input[type="text"][name^="payload["], form[data-draft-url] textarea[name^="payload["]';

// Se escribe una marca distinta en CADA campo y se verifica cada uno después de
// recargar. Medir uno solo no cazaría que `cuerpo()` mande sólo el campo sucio:
// el endpoint reemplaza el hash entero, los demás volverían en blanco, y el
// campo medido estaría ahí con su marca. Por eso hace falta más de uno.
const MINIMO_DE_CAMPOS_POR_CARA = 2;

// El PATCH del autoguardado, para interceptarlo en la fase de fallo. La ruta es
// `resource :draft` anidado en la sala, o sea `/workshops/:id/salas/:id/draft`.
const RUTA_DEL_AUTOGUARDADO = /\/salas\/[^/]+\/draft(\?.*)?$/;

async function revisarBorrador(page, nombre) {
  const campos = page.locator(SELECTOR_DE_CAMPO);
  const total = await campos.count();
  if (!total) {
    failures++;
    console.error(`[DRAFT] ${nombre}: el formulario de la sala no tiene campo con autoguardado`);
    return;
  }
  if (total < MINIMO_DE_CAMPOS_POR_CARA) {
    failures++;
    console.error(`[DRAFT] ${nombre}: el formulario tiene ${total} campo(s) y hacen falta ${MINIMO_DE_CAMPOS_POR_CARA}: con uno solo la guarda no puede cazar que se mande sólo el campo sucio`);
    return;
  }
  const marca = `borrador-${Date.now()}`;
  const previos = [];
  for (let i = 0; i < total; i++) {
    previos.push(await campos.nth(i).inputValue());
    await campos.nth(i).fill(`${marca}-${i}`);
  }
  const espera = Number(await page.locator('form[data-draft-url]').first().getAttribute('data-debounce')) || 2000;
  await page.waitForTimeout(espera + 1500);

  // El sello tiene que decir lo que el JS escribe al guardar, y NO «algo».
  // Pedir que no esté vacío no discrimina: esta guarda deja un borrador en la
  // base, así que en la corrida siguiente el servidor ya renderiza «Guardado por
  // … hace …» antes de que el JS toque nada.
  const elSello = page.locator('#draft-stamp').first();
  const esperado = (await elSello.getAttribute('data-saved-text')) || '';
  const dice = (await elSello.innerText()).trim();
  if (dice !== esperado.trim()) {
    failures++;
    console.error(`[DRAFT] ${nombre}: el sello dice «${dice}» y el autoguardado tendría que haber escrito «${esperado}»`);
  }

  await page.reload({ waitUntil: 'domcontentloaded' });
  const despues = page.locator(SELECTOR_DE_CAMPO);
  const totalDespues = await despues.count();
  let fallo = false;
  for (let i = 0; i < total; i++) {
    const vuelto = i < totalDespues ? await despues.nth(i).inputValue() : '(el campo no está)';
    if (vuelto !== `${marca}-${i}`) {
      fallo = true;
      failures++;
      console.error(`[DRAFT] ${nombre}: después de recargar el campo ${i + 1} de ${total} dice «${vuelto}» y la mesa había escrito «${marca}-${i}» (antes decía «${previos[i]}»)`);
    }
  }
  if (fallo) return;

  // 3 · El camino de FALLO, que es lo único de esta guarda que mira el arreglo
  // del bloqueante, y lo único que lo mira en todo el repo. El endpoint contesta
  // 204 y nada más; el JS exige EXACTAMENTE eso y no `res.ok`, porque un
  // `before_action` que redirige —sesión caída, membresía revocada— le llega al
  // `fetch` como 200: el `fetch` sigue el 302 y convierte el PATCH en GET, así
  // que la pantalla de login satisface `res.ok`. Con `!res.ok` el sello diría
  // «Guardado ahora.» cada dos segundos sobre un guardado que nunca ocurrió, y
  // la mesa pierde todo al mandar sin que nada avise. Es silencioso por
  // construcción: por eso no alcanza con que el servidor conteste bien, y hace
  // falta un navegador que lea la respuesta.
  //
  // Se intercepta el PATCH y se contesta un 200 PELADO: es el 2xx que distingue
  // las dos implementaciones. Con `res.status !== 204` el sello tiene que decir
  // el texto de fallo; con `!res.ok` diría el de guardado, y esta guarda es la
  // única que se enteraría.
  //
  // Va al FINAL y no antes, por dos razones: la fase de éxito ya dejó el
  // borrador escrito y un guardado que falla no escribe nada, así que no
  // contamina nada de lo medido arriba; y `guardar()` no restaura `sucio` tras
  // fallar, de modo que el texto de esta fase no se va después en el `keepalive`
  // de `descargar()` al navegar.
  await page.route(RUTA_DEL_AUTOGUARDADO, (route) => route.fulfill({ status: 200 }));
  await despues.nth(0).fill(`${marca}-falla`);
  await page.waitForTimeout(espera + 1500);
  const selloTrasFallo = page.locator('#draft-stamp').first();
  const falloEsperado = ((await selloTrasFallo.getAttribute('data-failed-text')) || '').trim();
  const diceTrasFallo = (await selloTrasFallo.innerText()).trim();
  await page.unroute(RUTA_DEL_AUTOGUARDADO);
  if (diceTrasFallo !== falloEsperado) {
    failures++;
    console.error(`[DRAFT] ${nombre}: con el endpoint contestando 200 el sello dice «${diceTrasFallo}» y tendría que decir «${falloEsperado}»: el autoguardado está leyendo cualquier 2xx como éxito`);
    return;
  }

  draftMeasurements++;
}

// El viaje completo de la grabación: apretar, grabar unos segundos, parar,
// subir, y que la transcripción del fixture aparezca en pantalla.
//
// Es lo único que ve el camino entero. El POST, el job y el partial pueden
// estar los tres en verde y el botón no grabar: `getUserMedia` fuera de
// contexto seguro, el bundle sin compilar, el estado guardado en el DOM y
// borrado por un morph. Nada de eso lo ve un spec de Ruby.
async function revisarGrabacion(page, nombre) {
  const caja = page.locator('[data-recording-url]').first();
  if (!(await caja.count())) {
    failures++;
    console.error(`[GRABAR] ${nombre}: la sala no tiene bloque de grabación`);
    return;
  }

  const boton = caja.locator('[data-recording-role="toggle"]');
  // Un botón escondido significa que el JS encontró un impedimento. En el
  // recorrido corre sobre `localhost`, que es contexto seguro, así que esto
  // sólo pasa si el bundle no se compiló o si el micrófono falso no llegó.
  if (await boton.isHidden()) {
    failures++;
    const motivo = await caja.locator('[data-recording-role="status"]').innerText();
    console.error(`[GRABAR] ${nombre}: el control está bloqueado y dice «${motivo}». Si dice que falta HTTPS, el micrófono falso no llegó; si está vacío, falta \`make yarn-build\``);
    return;
  }

  const onda = caja.locator('[data-recording-role="wave"]');
  // Antes de grabar la onda está escondida: una onda plana sin micrófono abierto
  // se lee como un micrófono que no toma nada.
  if (!(await onda.isHidden())) {
    failures++;
    console.error(`[GRABAR] ${nombre}: la onda se ve antes de grabar y tendría que estar escondida`);
    return;
  }
  const barras = await onda.locator('.waveform__bar').count();
  if (barras !== 40) {
    failures++;
    console.error(`[GRABAR] ${nombre}: la onda tiene ${barras} barras y el markup declara 40`);
    return;
  }

  const antes = await page.locator('details summary').count();
  // Cuántas tarjetas con la transcripción del fixture hay ANTES: corridas
  // anteriores dejan `ready` con el mismo texto, así que contar «alguna» no
  // discrimina; hay que ver que sume UNA.
  const esperado = 'barricas';
  const conTextoAntes = await page.locator('details', { hasText: esperado }).count();
  // El POST se intercepta sólo para MEDIR el cuerpo y se deja seguir. El fixture
  // ignora el audio, así que un blob vacío pasaría todo lo demás: la onda prueba
  // que el analizador recibió sonido, no que `MediaRecorder` lo grabó.
  let bytesSubidos = null;
  const RUTA_DE_GRABACIONES = /\/recordings(\?.*)?$/;
  await page.route(RUTA_DE_GRABACIONES, async (route) => {
    const req = route.request();
    if (req.method() === 'POST') bytesSubidos = (req.postDataBuffer() || Buffer.alloc(0)).length;
    await route.continue();
  });
  await boton.click();
  // Que el cronómetro corra es la prueba de que `getUserMedia` resolvió: el
  // texto cambia recién cuando hay stream.
  await page.waitForFunction(
    () => /\d\d:\d\d/.test(document.querySelector('[data-recording-role="status"]')?.textContent || ''),
    null, { timeout: 10000 },
  ).catch(() => {});
  const sello = await caja.locator('[data-recording-role="status"]').innerText();
  if (!/\d\d:\d\d/.test(sello)) {
    failures++;
    console.error(`[GRABAR] ${nombre}: después de apretar grabar el sello dice «${sello}» y tendría que traer un cronómetro: el micrófono no se abrió`);
    return;
  }

  // ── El morph en medio de la grabación ──────────────────────────────────
  //
  // Es el ÚNICO testigo de un bug que ya ocurrió: el servidor renderiza el
  // botón diciendo «Grabar» y el sello vacío, así que un morph le devolvía esos
  // valores mientras el micrófono seguía abierto —y la onda SÍ se recuperaba,
  // porque el bucle de dibujo reescribe las barras en el frame siguiente—.
  // Quien veía onda moviéndose al lado de un botón que decía «Grabar» lo
  // apretaba creyendo que arrancaba, y PARABA la reunión.
  //
  // Se fuerza con `Turbo.visit` a la misma URL en vez de apretando un botón de
  // la pantalla: un POST real —«Crear borrador»— dejaría datos sembrados de más
  // en el recorrido, y lo que se quiere probar es el morph, no el POST.
  const textoAntes = await boton.innerText();
  // Se espera el EVENTO `turbo:morph` y no un tiempo fijo: con un tiempo, una
  // máquina lenta pasaría la fase sin que ningún morph hubiera ocurrido. El
  // oyente se registra ANTES de visitar.
  await page.evaluate(() => {
    window.__morphsGrabar = 0;
    addEventListener('turbo:morph', () => { window.__morphsGrabar += 1; });
    window.Turbo.visit(window.location.href, { action: 'replace' });
  });
  const huboMorph = await page.waitForFunction(() => window.__morphsGrabar > 0, null, { timeout: 15000 })
    .then(() => true).catch(() => false);
  if (!huboMorph) {
    failures++;
    console.error(`[GRABAR] ${nombre}: la visita a la misma URL no disparó \`turbo:morph\` en 15 s: la fase del morph no midió nada`);
    return;
  }
  const textoDespues = await boton.innerText();
  const selloDespues = await caja.locator('[data-recording-role="status"]').innerText();
  if (textoDespues !== textoAntes || !/\d\d:\d\d/.test(selloDespues)) {
    failures++;
    console.error(`[GRABAR] ${nombre}: después de morfear en medio de la grabación el botón dice «${textoDespues}» (antes «${textoAntes}») y el sello «${selloDespues}»: el morph le devolvió el HTML del servidor y \`start()\` no repintó desde el estado del módulo`);
    return;
  }

  // ── La onda ────────────────────────────────────────────────────────────
  //
  // Se muestrea `data-level` —el RMS CRUDO, no el alto de la barra— mientras
  // graba. Es el único puente medible: las barras dicen cómo quedó el dibujo y
  // esto dice qué midió el micrófono.
  // Visible MIENTRAS graba. Sin esto el chequeo de «escondida» de más abajo es
  // vacío: borrar el `hidden = false` del arranque dejaría la onda invisible,
  // `data-level` publicando y todo en verde. La onda es lo que se pidió.
  if (await onda.isHidden()) {
    failures++;
    console.error(`[GRABAR] ${nombre}: la onda está escondida mientras graba: la mesa no ve la señal del micrófono`);
    return;
  }
  const niveles = [];
  for (let i = 0; i < 60; i++) {
    niveles.push(Number(await caja.getAttribute('data-level')));
    await page.waitForTimeout(100);
  }

  await boton.click();

  // Dos aserciones sobre la serie, y la SEGUNDA es la que discrimina.
  //
  // Que el máximo esté arriba de cero sólo prueba que algo se mueve: una onda
  // decorativa con números al azar también lo logra. Lo que una onda falsa NO
  // puede producir es la corrida de muestras cerca de cero del silencio que el
  // wav tiene a propósito entre las dos voces. Por eso el archivo se arma
  // voz → silencio → voz. La corrida sale del hueco del medio: en la medición
  // vigente la ventana de 6 s termina dentro de la segunda voz (ver la serie
  // junto a las constantes). Si algún día la ventana pasara del final del wav,
  // con `%noloop` la cola es silencio y también serviría: una onda decorativa
  // no produce ni hueco ni cola silenciosa.
  const pico = Math.max(...niveles);
  let corrida = 0;
  let mayorCorrida = 0;
  for (const n of niveles) {
    corrida = n <= SILENCIO_MAXIMO ? corrida + 1 : 0;
    if (corrida > mayorCorrida) mayorCorrida = corrida;
  }
  const serie = niveles.map((n) => n.toFixed(3)).join(' ');
  if (pico < VOZ_MINIMA) {
    failures++;
    console.error(`[GRABAR] ${nombre}: el pico de la onda fue ${pico.toFixed(3)} y el mínimo esperado es ${VOZ_MINIMA}: el AnalyserNode no está leyendo el micrófono. Serie: ${serie}`);
    return;
  }
  if (mayorCorrida < MUESTRAS_DE_SILENCIO) {
    failures++;
    console.error(`[GRABAR] ${nombre}: la corrida de silencio más larga fue de ${mayorCorrida} muestras y hacen falta ${MUESTRAS_DE_SILENCIO}: la onda da nivel incluso en el silencio del wav, o sea que no está midiendo audio real. Serie: ${serie}`);
    return;
  }
  // `rec.stop()` es asíncrono: la onda se esconde en `onstop`, no en el clic.
  // Leerla en el mismo tick midió el instante anterior al evento (falso rojo
  // medido en las dos caras con el JS sano), así que se espera con tope.
  await onda.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
  if (!(await onda.isHidden())) {
    failures++;
    console.error(`[GRABAR] ${nombre}: después de parar la onda sigue visible: el bucle de dibujo o el AudioContext no se cerraron`);
    return;
  }

  // El POST y después la visita que morfea la pantalla. Se espera un `details`
  // MÁS que antes —la tarjeta nueva de la grabación—, que es una señal que sólo
  // puede existir con la pantalla nueva pintada.
  //
  // La tarjeta con `details` sólo existe cuando la transcripción está `ready`,
  // y eso lo hace Sidekiq DESPUÉS de la visita que dispara la subida: esa
  // primera visita pinta la tarjeta «en cola» sin plegable. Esperar sin volver a
  // visitar medía para siempre la pantalla vieja (falso rojo medido, con el
  // código sano), así que se vuelve a pedir la pantalla hasta que aparezca.
  //
  // OJO, esto NO es evidencia de que la tarjeta se actualice sola: la app no
  // refresca la tarjeta de la grabación —no hay `turbo-frame` ni poller—, así
  // que la guarda re-visita A PROPÓSITO para llegar al estado `ready`. Un
  // `[GRABAR]` verde no dice nada sobre que la tarjeta cambie sin recargar; ese
  // hueco está declarado en la spec, bajo «Los estados».
  for (let i = 0; i < 20; i++) {
    if ((await page.locator('details summary').count()) > antes) break;
    await page.waitForTimeout(1500);
    await page.evaluate(() => window.Turbo.visit(window.location.href, { action: 'replace' }));
    await page.waitForTimeout(500);
  }

  const tarjetas = await page.locator('details summary').count();
  if (tarjetas <= antes) {
    failures++;
    console.error(`[GRABAR] ${nombre}: después de parar hay ${tarjetas} plegables y antes había ${antes}: la grabación no llegó al servidor o el job no la transcribió`);
    return;
  }

  // Y que lo que apareció sea la transcripción del fixture y no «algo»: pedir
  // que no esté vacío no discrimina, porque esta guarda deja grabaciones en la
  // base y en la corrida siguiente ya hay tarjetas antes de tocar nada.
  const texto = await page.locator('.card-body').first().innerText();
  await page.unroute(RUTA_DE_GRABACIONES);
  if (bytesSubidos === null || bytesSubidos < 2000) {
    failures++;
    console.error(`[GRABAR] ${nombre}: el POST de la grabación llevó ${bytesSubidos === null ? 'ningún cuerpo medido' : bytesSubidos + ' bytes'} y se esperaban al menos 2000: se subió un blob vacío`);
    return;
  }
  if ((await page.locator('details', { hasText: esperado }).count()) <= conTextoAntes) {
    failures++;
    console.error(`[GRABAR] ${nombre}: la tarjeta nueva no trae la transcripción del fixture (buscaba «${esperado}»); lo que hay dice «${texto.slice(0, 120)}»`);
    return;
  }

  recordingMeasurements++;
}

// El contraste se mide con `medirContraste`, que es el ÚNICO medidor del
// script y el que tiene autotest (`probarMedidorDeContraste`). No hay un
// `contraste(a, b)` llamable desde acá: esa función vive adentro del
// `page.evaluate` de `medirContraste`. Y además `medirContraste` compone la
// cadena de fondos hasta el primer opaco, que es lo que hay que hacer si
// alguna vez la banda lleva alfa.
async function revisarBanda(page, name) {
  const medidos = await medirContraste(page, '.page-banner');
  if (!medidos.length) return;
  bandasMedidas += medidos.length;

  // `medirContraste` ya devuelve `texto` trimeado y cortado a 40.
  //
  // Acá había una rama para «la banda se dibuja vacía» y era código muerto:
  // `medirContraste` filtra con `.filter(el => … && el.textContent.trim())`,
  // así que una `.page-banner` sin texto NUNCA llega a este bucle y el mensaje
  // no se podía imprimir jamás. La banda vacía la caza el piso exacto de 71 —no
  // publicar el `content_for` baja el conteo—, que es la misma regresión por
  // otro lado. Una rama que aparenta cubrir lo que cubre otro chequeo es
  // exactamente la forma de ceguera que esta rama viene arrastrando.
  for (const m of medidos) {
    if (m.ratio < 4.5) {
      failures++;
      console.error(`[BANDA] ${name}: «${m.texto}» mide ${m.ratio.toFixed(2)}:1 sobre la banda, y el piso es 4,5:1`);
    }
  }
}

// `[SOMBRA]` — la sombra pasó a ser portante y nadie la medía.
//
// Antes la tarjeta se definía por su BORDE y la sombra era decorativa: perderla
// era cosmético. Ahora, en tema claro, el borde de la tarjeta es transparente y
// la sombra es lo ÚNICO que la define, así que perderla la deja sin contorno.
// Y está escrito que nadie la mira: `[CLASES]` mira fondo, relleno y borde;
// `[RELLENO]`, relleno; `[CONTRASTE]`, color.
//
// Mide DOS superficies: la `card` y el campo (`input`, `textarea`, `select`).
// El campo es el caso grave: pinta el mismo `--surface` que la tarjeta que lo
// contiene, así que perder la sombra no deja un borde tonal, lo deja sin borde.
//
// La sombra es portante SÓLO en claro: en oscuro `--borde-superficie` le
// devuelve un borde real a la tarjeta y perderla vuelve a ser cosmético. Aun
// así `capturar()` corre también en las pantallas oscuras (94 a 99 y las demás
// `oscuro-*`), así que el chequeo de sombra las mide en los dos esquemas; el de
// contorno `[CAMPO]` es SÓLO de claro, porque en oscuro el campo conserva su
// `--borde` de siempre: 1,13:1 medido con ESTE mismo medidor sobre el textarea de
// `/challenges/new` con `prefers-color-scheme: dark`. Es deuda anterior a esta
// rama y fuera de su alcance. El 1,05:1 que decía acá antes no lo reprodujo
// nadie; el valor exacto en flotante es 1,142 y el navegador, que cuantiza a 8
// bits, mide 1,134 — la diferencia es la cuantización, no dos mediciones
// distintas.
//
// Cuenta cuántas midió y falla si midió de menos, por el mismo motivo que
// `[RELLENO]` y `[PASTILLA]`: una guarda que mide cero da verde y es
// indistinguible de una que funciona.
let sombrasMedidas = 0;
// Medido en la primera corrida limpia: 299 tarjetas en 76 pantallas. El piso deja
// ~24 de holgura (una pantalla cargada) y está muy por encima del cero al que
// lo lleva un renombre de `.card`.
const PISO_DE_SOMBRAS = 275;
let camposMedidos = 0;
// Medido en la primera corrida limpia: 291 campos visibles y sin foco, en los dos
// esquemas. Piso en 270: holgura de una pantalla cargada.
const PISO_DE_CAMPOS = 270;

// `[CAMPO]` mide el contorno del campo EN REPOSO contra lo que tiene detrás: el
// primer fondo opaco de sus ancestros. 3:1, el 1.4.11 de WCAG —el mismo piso de
// `[PUNTOS]`—. Medido a mano: con borde transparente y sólo la sombra, 1,09:1.
// Los colores se resuelven con un canvas, que entiende cualquier sintaxis que
// el navegador computa (oklch, color-mix) y compone el alfa sobre el fondo.
async function revisarSombra(page, name) {
  const r = await page.evaluate(() => {
    const ctx = document.createElement('canvas').getContext('2d', { willReadFrequently: true });
    const rgba = (c) => {
      ctx.clearRect(0, 0, 1, 1);
      ctx.fillStyle = '#000';
      ctx.fillStyle = c;
      ctx.fillRect(0, 0, 1, 1);
      return Array.from(ctx.getImageData(0, 0, 1, 1).data);
    };
    const lum = ([r, g, b]) => {
      const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
      return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
    };
    const ratio = (a, b) => {
      const x = lum(a), y = lum(b);
      return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
    };
    // El borde, compuesto sobre el fondo de atrás: se pinta el fondo y encima el borde.
    const compuesto = (fondo, borde) => {
      ctx.clearRect(0, 0, 1, 1);
      ctx.fillStyle = fondo;
      ctx.fillRect(0, 0, 1, 1);
      ctx.fillStyle = borde;
      ctx.fillRect(0, 0, 1, 1);
      return Array.from(ctx.getImageData(0, 0, 1, 1).data);
    };
    const fondoDetras = (el) => {
      for (let p = el.parentElement; p; p = p.parentElement) {
        const bg = getComputedStyle(p).backgroundColor;
        if (rgba(bg)[3] === 255) return bg;
      }
      return 'rgb(255, 255, 255)';
    };
    const visible = (el) => {
      const b = el.getBoundingClientRect();
      return b.width > 0 && b.height > 0 && getComputedStyle(el).visibility !== 'hidden';
    };
    const sombra = (el) => {
      const s = getComputedStyle(el).boxShadow;
      return !!s && s !== 'none';
    };

    let tarjetas = 0;
    const sinTarjeta = [];
    for (const card of document.querySelectorAll('.card')) {
      tarjetas++;
      if (!sombra(card)) sinTarjeta.push(card.className);
    }

    const oscuro = getComputedStyle(document.documentElement).colorScheme === 'dark';
    let campos = 0;
    const sinCampo = [];
    const flojos = [];
    const sel = 'input[type="text"], input[type="email"], input[type="password"], ' +
      'input[type="number"], input[type="date"], input[type="file"], textarea, select';
    for (const el of document.querySelectorAll(sel)) {
      if (!visible(el)) continue;
      if (el === document.activeElement) continue; // enfocado: el borde es el acento
      campos++;
      const label = `${el.tagName.toLowerCase()}${el.name ? `[${el.name}]` : ''}`;
      if (!sombra(el)) sinCampo.push(label);
      const cs = getComputedStyle(el);
      const fondo = fondoDetras(el);
      // El borde SÓLO cuenta si tiene ancho, y es el mismo patrón que
      // `medirContraste`. Sin esta pregunta la guarda no cazaba la regresión
      // para la que existe: con `border-style: none` —lo que queda si alguien
      // borra la línea `border: 1px solid var(--borde-campo)` del bloque de
      // campos, o escribe `border: none` para volver al campo SIN contorno del
      // Figma— el ancho computa 0, pero `borderTopColor` sigue devolviendo un
      // color (`currentColor`, o sea `--text`), que sobre blanco mide ~17:1 y
      // dejaba la guarda VERDE con el campo sin ningún contorno. Las dos
      // mutaciones que sí se cazaban —borrar la sombra, `--borde-campo:
      // transparent`— dejan el ancho en 1px; la tercera, que es la más natural,
      // pasaba. Sin ancho el borde ES el fondo y mide 1.00:1, o sea rojo.
      const borde = parseFloat(cs.borderTopWidth) > 0
        ? compuesto(fondo, cs.borderTopColor)
        : rgba(fondo);
      const m = ratio(borde, rgba(fondo));
      if (!oscuro && m < 3) flojos.push(`${label} ${m.toFixed(2)}:1`);
    }
    return { tarjetas, sinTarjeta, campos, sinCampo, flojos };
  });
  sombrasMedidas += r.tarjetas;
  camposMedidos += r.campos;
  if (r.sinTarjeta.length) {
    failures++;
    console.error(`[SOMBRA] ${name}: ${r.sinTarjeta.length} \`card\` sin sombra · ${r.sinTarjeta.slice(0, 4).join(' · ')}`);
  }
  if (r.sinCampo.length) {
    failures++;
    console.error(`[SOMBRA] ${name}: ${r.sinCampo.length} campo(s) sin sombra · ${r.sinCampo.slice(0, 4).join(' · ')}`);
  }
  if (r.flojos.length) {
    failures++;
    console.error(`[CAMPO] ${name}: ${r.flojos.length} campo(s) con el contorno en reposo bajo 3:1 contra lo de atrás · ${r.flojos.slice(0, 4).join(' · ')}`);
  }
}

async function capturar(page, name) {
  await page.screenshot({ path: `${OUT}/${name}.png`, fullPage: true });
  await revisarTexto(page, name);
  await revisarFormsAnidados(page, name);
  await revisarRitmo(page, name);
  await revisarClasesDescartadas(page, name);
  await revisarCardSinBody(page, name);
  await revisarRellenoDeTarjeta(page, name);
  await revisarRiel(page, name);
  await revisarBanda(page, name);
  await revisarSombra(page, name);
  // UNA sola medición para las dos guardas: `medirContraste` recorre el DOM y
  // compone la cadena de fondos de cada elemento, y se estaba haciendo dos veces
  // por pantalla sobre el mismo selector.
  const pastillas = await medirContraste(page, '.badge, .alert');
  await revisarContraste(name, pastillas);
  await revisarPastilla(name, pastillas);
  await revisarMonoEnProsa(page, name);
  await revisarAnchoDeCriterio(page, name);
  shots.push(name);
}

async function shot(page, name, url, prepare) {
  await page.goto(BASE + url, { waitUntil: 'networkidle' });
  if (prepare) await prepare(page);
  await capturar(page, name);
}

// Una pantalla de error es la ÚNICA que se fotografía con un estado >= 400, y
// hay que poder hacerlo sin aflojar la regla: un `>= 400 se ignora` a secas
// volvería ciega la corrida entera, que es lo que esta guarda evita.
//
// `estadoEsperado` vale para la navegación siguiente y sólo para el documento
// principal. Si llega OTRO estado, sigue fallando: lo que se declara es cuál,
// no que no importe.
//
// Lo leen dos: el listener de respuestas de abajo, y `revisarFormsAnidados`,
// que NO es una navegación —es un re-GET del mismo documento— y aun así
// necesita saber con qué estado tiene que responder esta pantalla.
let estadoEsperado = null;

// Como `shot()`, pero la pantalla responde con el estado declarado. Falla si
// responde con otro —incluido un 200—: una pantalla de error que dejó de
// serlo es exactamente lo que esto tiene que decir.
async function shotConEstado(page, name, url, status) {
  estadoEsperado = status;
  const respuesta = await page.goto(BASE + url, { waitUntil: 'networkidle' });
  if (respuesta.status() !== status) {
    failures++;
    console.error(`[ESTADO] ${name}: se esperaba ${status} y respondió ${respuesta.status()}`);
  }
  await capturar(page, name);
  // DESPUÉS de `capturar()`, y no antes: adentro corre `[FORMS]`, que relee
  // el documento y espera el estado declarado. Subir esta línea deja las dos
  // pantallas de error fallando con un mensaje que no apunta a la causa.
  estadoEsperado = null;
}

// Los módulos cuya cara de ejecución está en tres zonas (plan 2b): todos menos
// las selecciones. Por nombre del seed de `merma-bodega`, igual que el resto
// del recorrido — y por eso el loop exige que cada módulo caiga en exactamente
// una de las dos listas: si no, renombrarlo en el seed lo deja sin chequear.
// `/Prueba de factibilidad/i` y no `/factibilidad/i`: el nombre completo del
// módulo de testing (que SÍ va en zonas) comparte la palabra «factibilidad»
// con «Corte por factibilidad» (una selección, que NO va en zonas). Hoy es
// inerte —el loop que consulta esta lista sólo recorre `merma-bodega`—, pero
// una regex ancha haría fallar `[ZONAS]` por un falso positivo el día que
// alguien la extienda a otro desafío, no por un defecto real.
const MODULOS_EN_ZONAS = [/Evaluaci/i, /Ronda de feedback/i, /Postulaci/i, /Reporte/i, /Prueba de factibilidad/i];
// Las selecciones van sin referencia —con la columna puesta el ranking no
// entraba en el centro—, pero los ajustes plegados sí los tienen.
const MODULOS_SOLO_AJUSTES = [/Corte a top|Finalistas/i];

// Cuántos puntos de estado tiene que mostrar el drawer de cada desafío: uno por
// módulo (`_flow_drawer.html.haml`, la cara de «arrancado»). Fijos y no sacados
// de la página, por lo mismo que `PASOS_DE_SIN_FORMULARIO`. Si el seed le
// cambia los módulos a uno de los dos, este número cambia con él.
const PUNTOS_DE_SALTEADO = 3; // `con-salteado`: idear, evolución, evaluación
const PUNTOS_DE_MERMA = 7;    // `merma-bodega`, el desafío del recorrido

// `[TEMA]` — que la elección a mano funcione SIN matar el modo automático.
//
// Un request spec prueba que `data-theme` se escribe; no prueba que el
// navegador pinte otro tema. Y el caso que importa no es «elegir oscuro
// funciona»: es que elegir CLARO con el sistema en oscuro gane, y que volver a
// Auto devuelva el automático. Si «Auto» escribiera "flow" en vez de borrar la
// cookie, los dos primeros casos pasarían igual y el tercero no.
//
// Se mide el fondo computado del <body>, que es lo que el token mueve, y no el
// atributo: el atributo es la causa, no el efecto.
//
// Se mide en DOS pantallas, y la que importa es la CON sesión: el login no
// carga Turbo, así que su POST es una recarga completa y el atributo siempre
// se aplica. En la app Turbo morfea el body y NO toca el `data-theme` del
// <html> (sólo sincroniza `lang` y `dir`): por eso los botones del control
// llevan `turbo: false`, y sólo acá se ve si lo pierden.
//
// La espera NO es `networkidle` —Turbo se calma antes de pintar el body
// nuevo—: es que el botón elegido tenga la clase de activo, que sólo existe
// con el estado nuevo pintado.
//
// Una guarda que no corrió es indistinguible de una que pasó.
let temaMedido = 0;
async function revisarTema(page, pantalla, url) {
  const fondo = () => page.evaluate(() => getComputedStyle(document.body).backgroundColor);
  const elegir = async (n) => {
    await page.click(`.theme-switch form:nth-child(${n}) button`);
    // Si no se ilumina no es un cuelgue: es un hallazgo, y la medición de
    // abajo tiene que seguir para decir QUÉ quedó mal.
    try {
      await page.waitForSelector(`.theme-switch form:nth-child(${n}) .theme-switch__btn--on`, { timeout: 5000 });
    } catch (e) {
      failures++;
      console.error(`[TEMA] (${pantalla}) el botón ${n} del control no quedó activo tras apretarlo`);
    }
  };

  await page.emulateMedia({ colorScheme: 'dark' });
  // Sólo la cookie del tema: con sesión, `clearCookies()` a secas la cerraría.
  await page.context().clearCookies({ name: 'theme' });
  await page.goto(BASE + url, { waitUntil: 'networkidle' });
  const automatico = await fondo();

  await elegir(2);  // Claro
  const forzadoClaro = await fondo();

  await elegir(1);  // Auto
  const devuelto = await fondo();

  await page.context().clearCookies({ name: 'theme' });
  await page.emulateMedia({ colorScheme: 'light' });

  temaMedido++;
  if (forzadoClaro === automatico) {
    failures++;
    console.error(`[TEMA] (${pantalla}) elegir «Claro» con el sistema en oscuro no cambió nada (${automatico})`);
  }
  if (devuelto !== automatico) {
    failures++;
    console.error(`[TEMA] (${pantalla}) volver a «Auto» no devolvió el tema del sistema: ${devuelto} en vez de ${automatico} — ¿«Auto» escribe la cookie en vez de borrarla?`);
  }
}

(async () => {
  // Se limpia antes de empezar: una captura que dejó de tomarse queda en disco
  // como si siguiera siendo el estado actual, y eso es peor que no tenerla.
  for (const file of fs.readdirSync(OUT)) {
    if (file.endsWith('.png')) fs.unlinkSync(`${OUT}/${file}`);
  }

  // El micrófono falso, para `[GRABAR]`. Son flags de LANZAMIENTO, así que
  // aplican a la corrida entera; inofensivo, ninguna otra pantalla pide
  // micrófono. Medido: la pista aparece como `Fake Default Audio Input` en
  // estado `live`, el permiso se auto-concede, y el `mimeType` que elige
  // Chromium es `audio/webm;codecs=opus` — el mismo que Deepgram acepta.
  //
  // `%noloop` está MEDIDO y se honra: grabando 12 segundos de un wav de 5, la
  // frase aparece UNA vez en la transcripción y el resto es silencio. Importa
  // porque sin él Chromium repite el archivo, y una grabación larga
  // transcribiría la misma frase tres veces — lo que haría imposible distinguir
  // «grabó bien» de «grabó el loop».
  //
  // Ojo si se verifica de nuevo: comparar el TAMAÑO del blob no discrimina
  // nada. A bitrate fijo los bytes siguen a la duración y no al contenido, así
  // que con y sin el sufijo dan el mismo número exacto (15.989 bytes los dos,
  // medido). Hay que transcribir, y grabar MÁS que el largo del archivo.
  const browser = await chromium.launch({
    args: [
      '--use-fake-ui-for-media-stream',
      '--use-fake-device-for-media-stream',
      '--use-file-for-fake-audio-capture=/script/fake_audio.wav%noloop',
    ],
  });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  // El link del check-in, que `29` lee de la pantalla y `30` usa sin sesión.
  // Queda en `null` si `29` no pudo leerlo, y `30` lo sabe.
  let checkinUrl = null;

  await probarMedidorDeContraste(page);
  await probarMedidorDePastilla(page);
  await probarDetectorDeMono(page);

  page.on('pageerror', (e) => { failures++; console.error(`[JS ERROR] ${e.message}`); });
  page.on('response', (r) => {
    if (r.status() < 400) return;
    // Sólo el documento principal de la navegación declarada. Un asset o un
    // fetch que devuelva 403 sigue siendo una falla.
    if (estadoEsperado && r.status() === estadoEsperado && r.request().isNavigationRequest()) return;
    failures++;
    console.error(`[HTTP ${r.status()}] ${r.url()}`);
  });

  await shot(page, '01-login', '/login');

  await page.fill('input[name="email"]', 'admin@demo.test');
  await page.fill('input[name="password"]', 'Test1234');
  await page.click('input[type="submit"]');
  await page.waitForLoadState('networkidle');

  await shot(page, '02-challenges', '/challenges');

  // Un módulo salteado en el mapa del flujo y en el drawer. Sin un seed que lo
  // tenga, el nodo salteado quedó negro en el plan 2a sin que nada lo viera.
  await shot(page, '02b-salteado', '/challenges/con-salteado');
  if (!(await page.locator('.flow-drawer [title="Salteado"], .flow-strip .border-dashed').count())) {
    failures++;
    console.error('[SALTEADO] ni el drawer ni el mapa del flujo muestran el módulo salteado');
  }
  // Tres de los cuatro puntos: pendiente, en curso y salteado. El completado
  // está en el drawer de `merma-bodega`, más abajo.
  await revisarPuntos(page, '02b-salteado', 'claro', PUNTOS_DE_SALTEADO);

  await shot(page, '03-new-challenge', '/challenges/new');

  // Un desafío sin módulos ofrece las plantillas desde el builder.
  //
  // Se usa el que siembra el seed en vez de crear uno: crear uno por corrida
  // dejaba un «desafio-de-prueba-N» en la base de desarrollo cada vez.
  await shot(page, '03b-builder-plantillas', '/challenges/sin-armar/builder', async (p) => {
    await p.waitForSelector('[data-island-mounted="true"]', { timeout: 15000 });
  });


  // Los tres verbos del builder: agregar, quitar y que la pantalla lo muestre.
  //
  // Estuvo roto y nadie se enteró porque las capturas solo abrían el panel de
  // un módulo. El componente mutaba las props —que Vue no hace reactivas—, así
  // que los datos cambiaban y la pantalla seguía mostrando lo viejo. No se
  // guarda: esto verifica la isla, no el server.
  const cuentaTarjetas = () => page.locator('.step-card').count();
  const antes = await cuentaTarjetas();

  await page.locator('.palette-item:not(.palette-item--disabled)').first().click();
  await page.waitForTimeout(200);
  if (await cuentaTarjetas() !== antes + 1) {
    failures++;
    console.error('[BUILDER] agregar un módulo no se ve en pantalla');
  }

  await page.locator('.step-card__remove').last().click();
  await page.waitForTimeout(200);
  if (await cuentaTarjetas() !== antes) {
    failures++;
    console.error('[BUILDER] quitar un módulo no se ve en pantalla');
  }

  // El camino tiene que estar en TODAS las pantallas de configuración: si falta
  // en una, ahí es donde se pierde quien está configurando. Vive en el flujo de
  // la izquierda —la tarjeta de arriba se fue: mostraba lo mismo, y con siete
  // módulos se partía en dos filas y se comía la pantalla—.
  //
  // Son NUEVE entradas y no un número cualquiera: el desafío, el flujo, un
  // paso por cada uno de los seis módulos que `sin-formulario` siembra
  // (el de testing se sumó en el fix round 1 de la Task 7), y el cierre. El
  // número va fijo a propósito —calcularlo desde la propia página haría que
  // la guarda se cumpla sola—, así que si el seed cambia cuántos módulos
  // tiene ese desafío, este número cambia con él.
  const PASOS_DE_SIN_FORMULARIO = 2 + 6 + 1;
  for (const url of ['/challenges/sin-formulario',
                     '/challenges/sin-formulario/builder',
                     '/challenges/sin-formulario/form',
                     '/challenges/sin-formulario/preview']) {
    await page.goto(BASE + url, { waitUntil: 'networkidle' });
    if (await page.locator('.flow-drawer__link').count() !== PASOS_DE_SIN_FORMULARIO) {
      failures++;
      console.error(`[SETUP] falta el paso a paso en ${url}`);
    }
  }
  await shot(page, '03c-paso-a-paso', '/challenges/sin-formulario/form');
  await shot(page, '04-challenge', `/challenges/${CHALLENGE}`);
  // El cuarto punto: acá hay módulos completados, que `con-salteado` no tiene.
  await revisarPuntos(page, '04-challenge', 'claro', PUNTOS_DE_MERMA);
  await revisarChipDelDrawer(page, '04-challenge', 'claro');

  // El índice de criterios (`/criteria`) se borró: duplicaba lo que ya hace
  // el flujo, que lista los módulos y ahora lleva a cada uno. El paso «Los
  // criterios» del paso a paso manda directo al módulo que puntúa, que es la
  // pantalla donde se configuran de verdad. Se llega por LINK desde el
  // builder —no con un `goto` directo a `/steps/:id`, que ni siquiera se
  // podría armar sin conocer el id— porque es la cara de configuración del
  // módulo, con su propia isla de ajustes.
  //
  // Esta captura verifica el DESTINO del paso a paso, no el editor de
  // criterios: «sin-formulario» siembra el módulo de evaluación sin ningún
  // set propio (`db/seeds.rb`), así que el bloque de criterios queda en su
  // estado vacío («Usar los tres genéricos…») y la isla que monta acá es la
  // de `step-settings` —la que trae TODO módulo pendiente—, no la de
  // `criteria-editor` (esa ya se cubre en `09-12-criterios-del-modulo`, sobre
  // un módulo que sí tiene un set). El selector lo pide explícito para no
  // confundir una cosa con la otra.
  await page.goto(`${BASE}/challenges/sin-formulario/builder`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-island-mounted="true"] .step-card', { timeout: 15000 });
  const evaluacionCard = porTipo(page, 'Evaluación').locator('.step-card__name');
  if (await evaluacionCard.count()) {
    await Promise.all([
      page.waitForURL(/\/steps\/[^/]+$/, { timeout: 15000 }),
      evaluacionCard.click()
    ]);
    await page.waitForSelector('[data-island="step-settings"][data-island-mounted="true"]', { timeout: 15000 });

    if (await page.locator('.flow-drawer__link').count() !== PASOS_DE_SIN_FORMULARIO) {
      failures++;
      console.error('[SETUP] falta el paso a paso en el módulo de evaluación');
    }
    // El índice era la única pantalla que cerraba con el pie del paso a
    // paso («siguiente →») para el paso de los criterios. Sin este render en
    // `steps/config/evaluation`/`.../selection`, el paso a paso queda sin
    // «siguiente» justo ahí — un indicador, no un recorrido.
    if (!(await page.locator('.setup-nav').count())) {
      failures++;
      console.error('[SETUP] el módulo de evaluación perdió el pie del paso a paso (setup_nav)');
    }

    await capturar(page, '03d-paso-a-paso-criterios');
  } else {
    failures++;
    console.error('[LINK] «sin-formulario» no tiene módulo de evaluación');
  }

  // El builder es una isla Vue, y se llega NAVEGANDO POR EL LINK, no con un
  // goto directo.
  //
  // La diferencia importa: Turbo intercepta los links y reemplaza el body sin
  // disparar DOMContentLoaded. Un goto directo monta la isla igual y esconde
  // el bug; el link es el camino que usa una persona de verdad.
  await page.goto(`${BASE}/challenges/${CHALLENGE}`, { waitUntil: 'networkidle' });
  await page.click('a:has-text("Editar flujo")');
  await page.waitForSelector('[data-island-mounted="true"] .step-card', { timeout: 15000 });
  // Ya no se abre ningún panel —el builder lo perdió, se configura desde la
  // pantalla del módulo— así que alcanza con la lista tal cual monta,
  // incluida la tarjeta de «Idear» bloqueada (ya ejecutada en el demo).
  await page.waitForTimeout(300);
  await capturar(page, '05-builder');

  // El paso a paso es para CONFIGURAR: sobre un desafío que ya arrancó marca
  // como pendiente un paso que ya no se puede tocar. La guarda vive en el
  // partial, pero cuatro de seis pantallas se la habían olvidado antes.
  if (await page.locator('.setup').count()) {
    failures++;
    console.error('[SETUP] el paso a paso aparece en el builder de un desafío en curso');
  }

  // Una isla que no montó deja el placeholder: es un fallo, no una captura.
  if (await page.locator('.island-placeholder').count()) {
    failures++;
    console.error('[ISLA] el builder no montó: quedó "Cargando el editor de flujo…"');
  }

  // El formulario de postulación: ya no vive en una pantalla propia
  // (`form_fields/show`, que redirige a ésta) — la tarea «los campos del
  // formulario, embebidos» lo sumó a la pantalla del módulo «Idear», la
  // misma cara de ejecución que ya se estaba mirando. Ni un link ni un clic
  // de más: se llega por la tarjeta ENTERA, que es el link a su pantalla
  // (`.step-card__link`).
  //
  // El click va sobre `.step-card__name`, adentro del link: es donde clickea
  // una persona —sobre contenido pintado— y no sobre la caja que lo envuelve.
  //
  // Se filtra por TIPO y no por nombre: el nombre de un módulo lo cambia
  // cualquiera —una propuesta de la IA lo renombra— y la captura se caía.
  //
  // Tiene que ser un módulo TOCADO con campos de verdad, no uno vacío: el
  // «Idear» de este desafío ya arrancó y tiene ideas postuladas, así que la
  // isla monta con campos reales, no con el estado vacío.
  const ideationCardName = porTipo(page, 'Idear').locator('.step-card__name');
  if (await ideationCardName.count()) {
    await Promise.all([
      page.waitForURL(/\/steps\/[^/]+$/, { timeout: 15000 }),
      ideationCardName.click()
    ]);
    // El editor vive ahora en los ajustes plegados: sin abrirlos, sus campos
    // no están visibles y `waitForSelector` (que espera visibilidad) cuelga.
    await page.locator('details.ajustes__plegable').evaluate((el) => { el.open = true; });
    await page.waitForSelector('[data-island-mounted="true"] .field-edit', { timeout: 15000 });
    await capturar(page, '05b-form');

    if (await page.locator('.setup').count()) {
      failures++;
      console.error('[SETUP] el paso a paso aparece en el formulario de un desafío en curso');
    }

    // Todo campo tiene que decir qué es: sin etiqueta hay dos cajas de texto
    // seguidas y hay que deducir cuál es la pregunta y cuál la ayuda.
    const campos = await page.locator('.field-edit').count();
    const etiquetas = await page.locator('.field-edit .captioned__text').count();
    if (etiquetas < campos * 3) {
      failures++;
      console.error(`[ETIQUETAS] el editor del formulario tiene campos sin etiqueta (${etiquetas} para ${campos} campos)`);
    }

    if (await page.locator('.island-placeholder').count()) {
      failures++;
      console.error('[ISLA] el editor del formulario no montó');
    }
  } else {
    failures++;
    console.error('[LINK] la tarjeta de «Idear» no ofrece ir a su pantalla');
  }

  // La previsualización: se llega por link desde el builder.
  await page.goto(`${BASE}/challenges/sin-formulario/builder`, { waitUntil: 'networkidle' });
  const previewLink = page.locator('a:has-text("Previsualizar")');
  if (await previewLink.count()) {
    await Promise.all([
      page.waitForURL('**/preview', { timeout: 15000 }),
      previewLink.first().click()
    ]);
    await page.waitForSelector('.preview-surface, .empty-state', { timeout: 10000 });
    await capturar(page, '05c-preview-borrador');
  } else {
    failures++;
    console.error('[LINK] el builder no ofrece previsualizar');
  }

  // El mismo preview sobre el desafío en curso, con su formulario y su set de
  // criterios de verdad.
  await shot(page, '05d-preview-configurado', `/challenges/${CHALLENGE}/preview`);

  // Las dos caras de un módulo (`StepsController#show` despacha por
  // `step.touched?`). La de EJECUCIÓN (`steps/<kind>`) ya la recorre el loop
  // de más abajo sobre cada módulo tocado de `${CHALLENGE}`; la de
  // CONFIGURACIÓN (`steps/config/<kind>`) no tenía ningún módulo de
  // EVOLUCIÓN fotografiado en ningún desafío sembrado — deuda que dejó la
  // Task 8. (La de evaluación pendiente ya se rozaba de rebote en
  // `03d-paso-a-paso-criterios`, sobre su estado vacío; este bloque la cubre
  // también, con datos, para las cinco por igual.)
  //
  // Se llega por LINK, no con un goto directo a `/steps/:id`: un goto monta
  // la isla `step-settings` igual y esconde el mismo bug que ya escondió una
  // vez. El click va sobre `.step-card__name`, adentro del link que es LA
  // TARJETA ENTERA (`.step-card__link`, Task 5) — es donde clickea una
  // persona, sobre contenido pintado, no sobre la caja que lo envuelve.
  //
  // `locked: step.touched?` (`PipelinePresenter#step_json`) es la única forma
  // honesta de saber, desde el builder, cuál tarjeta todavía se configura: se
  // verifica ANTES de clickear para no confundir una cara con la otra si los
  // datos sembrados cambiaran.
  //
  // «sin-formulario» y no un desafío hecho a mano: existe SOLO para las
  // capturas (ver `db/seeds.rb`) y tiene los seis `kind` pendientes. Un
  // desafío que además se usa para probar la app rompió esto mismo dos veces
  // (`3e437d6`) — cualquier `goto` a un slug que no siembra `db/seeds.rb`
  // revienta en un entorno recién sembrado, no solo acá.
  //
  // El nombre de cada captura va por TIPO, no por posición: la posición es
  // mutable por diseño (`decimal(20,10)`, insertar entre A y B es `(a+b)/2`)
  // y un índice numérico pasaría a significar un módulo distinto en cuanto
  // alguien reordene el flujo.
  //
  // «Testing» se sumó en el fix round 1 de la Task 7: su cara de
  // configuración —la isla `step-settings` con el schema nuevo de
  // `Flow::StepSettings`— no tenía NINGUNA cobertura de navegador. El único
  // desafío sembrado que usaba ese `kind` (`testeo-abierto`) arranca el
  // módulo casi enseguida (`pipeline.start!` + `advance!`), así que nunca
  // queda pendiente en un momento capturable — y un spec de request
  // (`testing_config_spec.rb`) no ejecuta JS, así que una isla que no monta
  // se ve perfecta en el HTML servido. Este bloque es EXACTAMENTE el lugar
  // que ya prueba eso para los otros cinco `kind`: sumar la entrada alcanza.
  const CARAS_DE_CONFIGURACION = [
    ['Idear', 'idear'],
    ['Testing', 'testing'],
    ['Evolución', 'evolucion'],
    ['Evaluación', 'evaluacion'],
    ['Selección', 'seleccion'],
    ['Reportería', 'reporteria']
  ];

  for (const [label, slug] of CARAS_DE_CONFIGURACION) {
    await page.goto(`${BASE}/challenges/sin-formulario/builder`, { waitUntil: 'networkidle' });
    await page.waitForSelector('[data-island-mounted="true"] .step-card', { timeout: 15000 });

    const tarjeta = porTipo(page, label);
    if (!(await tarjeta.count())) {
      failures++;
      console.error(`[LINK] no hay módulo de tipo «${label}» para fotografiar su cara de configuración`);
      continue;
    }
    const clases = await tarjeta.evaluate((el) => el.className);
    if (clases.includes('step-card--locked')) {
      failures++;
      console.error(`[LINK] el módulo de tipo «${label}» ya está tocado: no tiene cara de configuración que fotografiar`);
      continue;
    }

    await Promise.all([
      page.waitForURL(/\/steps\/[^/]+$/, { timeout: 15000 }),
      tarjeta.locator('.step-card__name').click()
    ]);
    // Señal determinista de la cara de configuración: `data-island=
    // "step-settings"` sólo lo renderiza `steps/config/_modulo`, nunca la
    // cara de ejecución — si el click hubiera caído en la otra cara, esto
    // se cuelga hasta el timeout en vez de fotografiar la pantalla que no es.
    await page.waitForSelector('[data-island="step-settings"][data-island-mounted="true"]', { timeout: 15000 });
    await capturar(page, `05e-config-${slug}`);

    if (await page.locator('.island-placeholder').count()) {
      failures++;
      console.error(`[ISLA] la cara de configuración de «${label}» no montó`);
    }
  }

  await shot(page, '06-ideas', `/challenges/${CHALLENGE}/ideas`);

  // Una idea que EVOLUCIONÓ, para que el diff tenga dos versiones que comparar.
  // Tomar la primera de la lista dejaba de capturar el diff en silencio cuando
  // esa idea tenía una sola versión.
  await page.goto(`${BASE}/challenges/${CHALLENGE}/ideas`, { waitUntil: 'networkidle' });
  // «Sensores» es la idea completa del seed: dos versiones, colaboradores y un
  // adjunto. Tomar cualquiera con v2 capturaba una sin esos datos.
  const versioned = page.locator('.idea-list__item', { hasText: 'Sensores' });
  if (!(await versioned.count())) {
    failures++;
    console.error('[DATOS] ninguna idea tiene v2: el diff no se puede capturar');
  }
  // Se espera la URL, no `networkidle`: con Turbo el estado de red se calma
  // antes de que el body nuevo esté puesto, y la captura salía de la lista.
  await Promise.all([
    page.waitForURL(/\/ideas\/[^/]+$/, { timeout: 15000 }),
    versioned.first().locator('.idea-list__link').click()
  ]);
  await page.waitForSelector('.version-timeline', { timeout: 10000 });
  await capturar(page, '07-idea');

  // Las rondas de feedback cerradas de la ficha de la idea ya se pliegan con
  // <details>: es el plegable que existe desde antes de este plan.
  await revisarPlegableTrasMorph(page, '07-idea', 'details.feedback-round--cerrada');

  const diffLink = page.locator('a:has-text("Ver cambios entre versiones")');
  if (await diffLink.count()) {
    await diffLink.click();
    await page.waitForURL('**/diff**', { timeout: 10000 });
    await capturar(page, '08-diff');
  } else {
    failures++;
    console.error('[LINK] la idea con v2 no ofrece ver el diff');
  }

  // Una pantalla por tipo de módulo, tomando el primero de cada kind.
  await page.goto(`${BASE}/challenges/${CHALLENGE}`, { waitUntil: 'networkidle' });
  const stepLinks = await page.locator('.table-link').evaluateAll(
    (nodes) => nodes.map((n) => ({ href: n.getAttribute('href'), text: n.textContent.trim() }))
  );

  // Generar ideas deja elegir cuántas, con un tope. Sin el tope, un clic
  // distraído pide veinte ideas y eso es una factura sorpresa.
  //
  // Va sobre `recorrido-ia` y NO sobre el desafío del recorrido: en
  // `merma-bodega` el flujo corrió entero, así que su módulo de idear está
  // cerrado, y la IA ya no trabaja sobre un módulo cerrado. Mirándolo ahí,
  // este chequeo estaba fijando justamente el bug: pedía que el selector
  // siguiera ofrecido en un módulo donde apretar el botón creaba ideas sin
  // fila en ninguna `step_entries`.
  await page.goto(`${BASE}/challenges/recorrido-ia`, { waitUntil: 'networkidle' });
  const ideacion = (await page.locator('.table-link').evaluateAll(
    (nodes) => nodes.map((n) => ({ href: n.getAttribute('href'), text: n.textContent.trim() }))
  )).find((l) => l.text.match(/Postulaci/i));
  if (!ideacion) {
    failures++;
    console.error('[IA] recorrido-ia no tiene módulo de idear donde mirar el selector de cantidad');
  } else {
    await page.goto(BASE + ideacion.href, { waitUntil: 'networkidle' });
    const opciones = await page.locator('select[name="count"] option').allTextContents();
    if (opciones.join(',') !== '1,2,3,4,5') {
      failures++;
      console.error(`[IA] el selector de cantidad no ofrece 1..5 (${opciones.join(',')})`);
    }
  }

  for (const [index, link] of stepLinks.entries()) {
    const nombre = `09-${index + 1}-step-${link.text.toLowerCase().replace(/[^a-z0-9]+/g, '-')}`;
    await shot(page, nombre, link.href);

    // El modo de IA se ajusta desde el módulo, sin volver al builder. La
    // selección era el único de los cinco que no lo ofrecía, y es donde más
    // importa: con «Solo personas» los veredictos los responde alguien uno
    // por uno.
    if (!(await page.locator('.ai-mode-card').count())) {
      failures++;
      console.error(`[MODO IA] «${link.text}» no ofrece cambiar el modo de IA del módulo`);
    }

    // Las tres zonas: la referencia existe, y quien recorre —admin— tiene
    // los ajustes plegados al final. Sin esto, un módulo reordenado podía
    // perder su columna sin que ninguna captura lo dijera.
    const enZonas = MODULOS_EN_ZONAS.some((re) => re.test(link.text));
    const soloAjustes = MODULOS_SOLO_AJUSTES.some((re) => re.test(link.text));

    // Las dos listas van por NOMBRE del seed, así que renombrar un módulo lo
    // saca de las dos y sus zonas dejan de chequearse sin que nada lo diga: es
    // el mismo «se cumple sola» que `[PUNTOS]` ya pagó, y acá no hay ni una
    // lista vacía que mirar, porque el `if` simplemente no entra. Cada módulo
    // del recorrido tiene que caer en EXACTAMENTE una de las dos, así que el
    // caso malo es que las dos digan lo mismo: ninguna (renombrado, o un kind
    // nuevo sin lista) o las dos (listas que se solapan y se pisan).
    if (enZonas === soloAjustes) {
      failures++;
      console.error(enZonas
        ? `[ZONAS] «${link.text}» cae en las dos listas de MODULOS_*, que se contradicen: con referencia y sin referencia`
        : `[ZONAS] «${link.text}» no cae en ninguna de las dos listas de MODULOS_*: nadie chequea sus zonas`);
    }

    if (enZonas) {
      if (!(await page.locator('.app-aside').count())) {
        failures++;
        console.error(`[ZONAS] «${link.text}» no tiene columna de referencia`);
      }
      if (!(await page.locator('details.ajustes__plegable').count())) {
        failures++;
        console.error(`[ZONAS] «${link.text}» no tiene los ajustes plegados`);
      }
      await revisarReferencia(page, nombre);
    }
    if (soloAjustes && !(await page.locator('details.ajustes__plegable').count())) {
      failures++;
      console.error(`[ZONAS] «${link.text}» no tiene los ajustes plegados`);
    }
  }

  // Quién evalúa y cuánto pesa su voto. La tabla y la columna existían desde
  // el principio sin ninguna pantalla que las tocara.
  const comite = stepLinks.find((l) => l.text.match(/comit/i));
  if (comite) {
    await page.goto(BASE + comite.href, { waitUntil: 'networkidle' });
    const filas = await page.locator('.assignment-row').count();
    const conPesos = await page.locator('.badge-primary', { hasText: 'con pesos' }).count();

    if (filas === 0) {
      failures++;
      console.error('[EVALUADORES] el módulo de evaluación no lista quién evalúa');
    }
    if (conPesos === 0) {
      failures++;
      console.error('[EVALUADORES] no se avisa que el módulo tiene pesos distintos');
    }
  } else {
    failures++;
    console.error('[LINK] el desafío no tiene el módulo de evaluación de comité');
  }

  // Los ajustes abiertos. Es por la FOTO: plegados no salen en ninguna captura.
  // No por la medición —las guardas ya miden adentro de un plegable cerrado,
  // ver `abrirPlegables`—, que es lo que este comentario decía y no era cierto.
  if (comite) {
    await page.goto(BASE + comite.href, { waitUntil: 'networkidle' });

    // Una fila de idea desplegada: plegada no se ve ni se mide.
    const fila = page.locator('details.fila-de-idea__plegable').first();
    if (!(await fila.count())) {
      failures++;
      console.error('[DESGLOSE] ninguna idea del comité tiene fila desplegable');
    } else {
      await fila.evaluate((el) => { el.open = true; });
      await capturar(page, '09-17-desglose');
      await revisarPlegableTrasMorph(page, '09-17-desglose', 'details.fila-de-idea__plegable');
    }

    await page.locator('details.ajustes__plegable').evaluate((el) => { el.open = true; });
    await capturar(page, '09-16-ajustes-abiertos');
    await revisarPlegableTrasMorph(page, '09-16-ajustes-abiertos', 'details.ajustes__plegable');
  }

  // Los ajustes de idear abiertos: adentro está el editor del formulario, una
  // isla que monta plegada. Cerrado no tiene caja, y las guardas de contraste y
  // de clases no medirían nada de lo que pinta.
  if (ideacion) {
    await page.goto(BASE + ideacion.href, { waitUntil: 'networkidle' });
    await page.locator('details.ajustes__plegable').evaluate((el) => { el.open = true; });
    await page.waitForSelector('[data-island="form-editor"][data-island-mounted="true"]', { timeout: 15000 });
    await capturar(page, '09-18-ajustes-de-idear');
  }

  // La selección con filtros: cada idea pasa o no pasa cada condición, y se
  // ve quién lo respondió. Un filtro sin responder traba el cierre del módulo,
  // así que la columna tiene que estar poblada.
  const corte = stepLinks.find((l) => l.text.match(/Corte a top/i));
  if (corte) {
    await page.goto(BASE + corte.href, { waitUntil: 'networkidle' });
    // Acotado a la tabla: la leyenda de abajo usa los mismos símbolos y
    // contarla daría un pendiente que no existe.
    const pasan = await page.locator('.ranking-table .gate--pass, .ranking-table .gate--fail').count();
    const porIA = await page.locator('.ranking-table .gate--by-ai').count();
    const pendientes = await page.locator('.ranking-table .gate--pending').count();

    if (pasan === 0 || pendientes > 0) {
      failures++;
      console.error(`[FILTROS] la tabla de la selección no muestra veredictos resueltos (${pasan} resueltos, ${pendientes} pendientes)`);
    }
    if (porIA === 0) {
      failures++;
      console.error('[FILTROS] ningún veredicto aparece atribuido a la IA');
    }
  } else {
    failures++;
    console.error('[LINK] el desafío no tiene el módulo de corte con filtros');
  }

  // El desafío en borrador: «Idear» todavía no tiene formulario. El builder
  // lo marca como error arriba de la lista (Flow::Pipeline#validate) sin que
  // haga falta abrir ninguna tarjeta.
  await page.goto(`${BASE}/challenges/sin-formulario/builder`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-island-mounted="true"] .step-card', { timeout: 15000 });
  await page.waitForTimeout(200);
  await capturar(page, '09-9-builder-sin-formulario');

  await shot(page, '09-10-form-vacio', '/challenges/sin-formulario/form');

  // Pedirle algo a la IA no debe recargar la pantalla: el botón apunta al
  // marco de las propuestas. No se dispara el pedido —cuesta plata con el
  // proveedor real—, se verifica el contrato que lo hace posible.
  if (!(await page.locator('turbo-frame#ai-suggestions').count())) {
    failures++;
    console.error('[IA] falta el turbo-frame de propuestas: el pedido recargaría la pantalla');
  }
  const destino = await page
    .locator('form:has(button:has-text("Proponer campos con IA"))')
    .getAttribute('data-turbo-frame');
  if (destino !== 'ai-suggestions') {
    failures++;
    console.error(`[IA] el botón no apunta al marco de propuestas (data-turbo-frame=${destino})`);
  }

  // Sobre la pantalla del formulario a propósito: tiene isla de Vue, así que
  // si el morph la dejara sin montar la revisión del placeholder lo canta.
  await revisarMorphing(page, '09-10-form-vacio');

  // Los criterios del módulo de evaluación: ya no se muestran en un panel del
  // builder, sino en la referencia de SU PROPIA pantalla
  // (`steps/_referencia_evaluacion.html.haml`), que ya los ofrece. Se llega
  // por link desde la ficha del desafío, no con un goto directo a la pantalla
  // del módulo.
  //
  // Sobre un módulo YA ARRANCADO a propósito, y no sobre uno de
  // «sin-formulario» (que está pendiente): la tarea «configurar vs ejecutar»
  // le dio dos caras a la pantalla del módulo, y esta referencia es de la cara
  // de EJECUCIÓN — sólo un panel de sólo lectura, sin link a ninguna pantalla
  // de criterios propia. La de configuración se captura aparte, más abajo.
  await page.goto(`${BASE}/challenges/${CHALLENGE}`, { waitUntil: 'networkidle' });
  const evaluacionLink = page
    .locator('.table tr', { hasText: 'Evaluación de comité' })
    .locator('.table-link');
  if (await evaluacionLink.count()) {
    await Promise.all([
      page.waitForURL(/\/steps\/[^/]+$/, { timeout: 15000 }),
      evaluacionLink.first().click()
    ]);
    await capturar(page, '09-11-panel-evaluacion');
  } else {
    failures++;
    console.error('[LINK] el desafío no tiene módulo de evaluación');
  }

  // El editor de criterios de un módulo TODAVÍA PENDIENTE: ya no vive en una
  // pantalla propia (`step_criteria/show`, que redirige a ésta) — la tarea
  // «los criterios, embebidos» lo sumó a la cara de configuración del
  // módulo. Se llega por link desde la ficha de un desafío en borrador.
  //
  // Tiene que ser un módulo con un set INLINE de verdad, no uno vacío: la
  // isla sólo monta cuando hay `set` (ver `steps/_criterios_editor.html.haml`)
  // — sobre un módulo sin criterios propios la captura sólo prueba el estado
  // vacío, que es justo lo que NO justificaba reemplazar el click roto.
  //
  // «sin-formulario»: su módulo de SELECCIÓN («Selección para pilotear»)
  // siembra un set inline (`db/seeds.rb`) sólo para esto. No es el de
  // evaluación («Primera revisión») porque ESE lo usa
  // `03d-paso-a-paso-criterios` para probar justo el estado vacío — ponerle
  // criterios propios ahí taparía lo que esa otra captura verifica.
  await page.goto(`${BASE}/challenges/sin-formulario`, { waitUntil: 'networkidle' });
  const seleccionLink = page
    .locator('.table tr', { hasText: 'Selección para pilotear' })
    .locator('.table-link');
  if (await seleccionLink.count()) {
    await Promise.all([
      page.waitForURL(/\/steps\/[^/]+$/, { timeout: 15000 }),
      seleccionLink.first().click()
    ]);
    await page.waitForSelector('[data-island-mounted="true"] .criterion-edit', { timeout: 15000 });
    await capturar(page, '09-12-criterios-del-modulo');

    if (await page.locator('.island-placeholder').count()) {
      failures++;
      console.error('[ISLA] el editor de criterios embebido no montó');
    }

    // La sugerencia de IA pendiente de revisión no se pierde al borrar la
    // pantalla suelta: el marco de propuestas sigue presente, embebido en
    // el bloque de criterios.
    if (!(await page.locator('turbo-frame#ai-suggestions').count())) {
      failures++;
      console.error('[IA] el módulo pendiente perdió el marco de sugerencias de criterios');
    }
  } else {
    failures++;
    console.error('[LINK] no se encontró el módulo de selección pendiente con criterios propios');
  }

  await shot(page, '09-13-avisos', '/notifications');

  await shot(page, '12-miembros', '/members');

  await shot(page, '10-criteria', '/criteria_sets');

  // El editor de criterios: la config que antes se escribía como JSON a mano.
  await page.goto(`${BASE}/criteria_sets`, { waitUntil: 'networkidle' });
  const setLink = page.locator('a:has-text("Editar")').first();
  if (await setLink.count()) {
    await setLink.click();
    await page.waitForSelector('[data-island-mounted="true"] .criterion-edit', { timeout: 15000 });
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await page.waitForTimeout(150);
    await capturar(page, '10b-criteria-editor');

    if (await page.locator('.island-placeholder').count()) {
      failures++;
      console.error('[ISLA] el editor de criterios no montó');
    }

    // Un set de biblioteca EN USO no se pisa: guardar crea la versión
    // siguiente. El aviso tiene que decirlo ANTES, porque si no la edición
    // parece no haber llegado a los desafíos que ya lo usaban.
    //
    // Acá no se aprieta guardar a propósito: cada corrida dejaría una versión
    // nueva en la demo. El guardado en sí lo cubren los request specs.
    const aviso = await page.locator('.alert-warning').first().textContent().catch(() => '');
    if (!/Al guardar se crea la v\d/.test(aviso || '')) {
      failures++;
      console.error('[VERSIONADO] el editor no avisa que guardar crea una versión nueva:', aviso);
    }
  } else {
    failures++;
    console.error('[LINK] la biblioteca de criterios no ofrece editar un set');
  }
  // ── Los dos popups de la IA ────────────────────────────────────────────────
  //
  // Desarrollo usa el proveedor REAL (FLOW_AI_PROVIDER=anthropic): ninguna
  // captura puede disparar un pedido que llame a la IA. Los dos caminos de acá
  // pasan por el servidor de verdad y no cuestan un peso: un propósito que no
  // existe se rechaza antes de llamar a nadie, y «Detectar duplicados» compara
  // local porque el proveedor de VECTORES es el fixture.
  //
  // Sobre `recorrido-ia`, que existe sólo para esto: las capturas que
  // dependieron de un desafío que también se usa a mano fallaron por datos dos
  // veces.
  await page.goto(BASE + '/challenges/recorrido-ia', { waitUntil: 'networkidle' });

  // El pedido a la IA vive en la pantalla del módulo (Postulación), no en el
  // resumen del desafío: se entra por link, como pide CLAUDE.md, para no
  // esconder detrás de un `goto` un bug de Turbo al montar esa pantalla.
  await Promise.all([
    page.waitForURL(/\/steps\/[^/]+$/, { timeout: 15000 }),
    page.click('.table-link:has-text("Postulación")')
  ]);
  await page.waitForSelector('form[action*="/ai_requests"]', { timeout: 15000 });

  // 1 · La espera. El pedido se RETIENE para fotografiar el popup girando y
  // comprobar que Escape no lo cierra; después se suelta y tiene que irse solo.
  let soltar = null;
  await page.route('**/ai_requests*', async (route) => {
    await new Promise((resolve) => { soltar = resolve; });
    await route.continue();
  });

  // Se reescribe la acción de un formulario de IA que ya está en la pantalla:
  // así el pedido va con su token CSRF y por el mismo camino que un clic real.
  const hayForm = await page.evaluate(() => {
    const form = document.querySelector('form[action*="/ai_requests"]');
    if (!form) return false;
    const url = new URL(form.action);
    url.searchParams.set('purpose', 'proposito-inexistente');
    form.action = url.toString();
    form.requestSubmit();
    return true;
  });
  if (!hayForm) {
    failures++;
    console.error('[IA] recorrido-ia no ofrece ningún pedido a la IA');
  }

  await page.waitForSelector('dialog[data-ia="espera"][open]', { timeout: 5000 });
  await capturar(page, '09-13-ia-espera');

  // No se puede cerrar: es la razón de ser del popup.
  await page.keyboard.press('Escape');
  if (!(await page.locator('dialog[data-ia="espera"][open]').count())) {
    failures++;
    console.error('[IA] la espera se cerró con Escape');
  }

  if (soltar) soltar();
  await page.waitForSelector('dialog[data-ia="respuesta"][open]', { timeout: 15000 });
  if (await page.locator('dialog[data-ia="espera"]').count()) {
    failures++;
    console.error('[IA] la espera quedó puesta después de la respuesta');
  }
  const rojo = await page.locator('dialog[data-ia="respuesta"] .ia-respuesta--error').count();
  if (!rojo) {
    failures++;
    console.error('[IA] un pedido rechazado no muestra el popup de error');
  }
  await page.click('dialog[data-ia="respuesta"] .ia-respuesta__cerrar');
  await page.unroute('**/ai_requests*');

  // 2 · El éxito, con la propuesta adentro del popup. «Detectar duplicados»
  // vive en la ficha de una idea, y se llega por link: un `goto` monta la
  // pantalla igual y esconde los bugs de Turbo.
  //
  // `.idea-list__link` y no `a[href*="/ideas/"]` a secas: esta misma pantalla
  // ofrece «Postular una idea» (`/ideas/new`), que matchea el mismo patrón y
  // aparece ANTES que la lista en el DOM — un selector más flojo hacía clic en
  // el formulario nuevo y nunca llegaba a la ficha de una idea existente.
  const aIdea = page.locator('a.idea-list__link').first();
  if (!(await aIdea.count())) {
    failures++;
    console.error('[IA] recorrido-ia no ofrece ningún link a una idea');
  }
  await aIdea.click();
  await page.waitForURL(/\/ideas\//);
  await page.click('form[action*="detect_duplicates"] button');
  await page.waitForSelector('dialog[data-ia="respuesta"][open]', { timeout: 30000 });

  // Detectar duplicados es INFORMATIVA: lo que devuelve es para leer y su
  // `apply!` no toca nada, así que la tarjeta ofrece un solo «Listo» —no
  // «Aplicar», que prometía algo que no pasaba, ni «Descartar», que decía que
  // la IA se equivocó—.
  if (!(await page.locator('dialog[data-ia="respuesta"] button:has-text("Listo")').count())) {
    failures++;
    console.error('[IA] el popup de una propuesta informativa no ofrece «Listo»');
  }
  for (const texto of ['Aplicar', 'Descartar']) {
    if (await page.locator(`dialog[data-ia="respuesta"] button:has-text("${texto}")`).count()) {
      failures++;
      console.error(`[IA] una propuesta informativa sigue ofreciendo «${texto}»`);
    }
  }
  // Se captura CON el popup abierto, pero `revisarClasesDescartadas` (la
  // guarda de clases sin regla detrás que corre en `capturar()`) sólo mira
  // `[class*="badge"],[class*="btn"],[class*="alert"],.steps,.panel`: de lo
  // que arma este JS eso alcanza al ✕ y a «Listo» —es `btn`—, no a `modal`,
  // `modal-box`, `modal-backdrop`, `loading` ni a ninguna `ia-*`.
  await capturar(page, '09-14-ia-respuesta');

  // «Listo», para no dejar una propuesta pendiente: la corrida siguiente la
  // encontraría como «ya había una» y el camino de éxito dejaría de probarse.
  //
  // Se anota ANTES el `action` del form de «Listo» para poder esperar a que se
  // vaya ESA propuesta. Esperar a que no quede ninguna `.ai-suggestion` daría
  // lo mismo hoy, pero el panel lista todo lo pendiente de la idea: una
  // propuesta de otro propósito colgaría la corrida diez segundos y la
  // abortaría sin resumen.
  const formDeListo = await page.getAttribute('dialog[data-ia="respuesta"] form', 'action');
  await page.click('dialog[data-ia="respuesta"] button:has-text("Listo")');
  await page.waitForSelector('dialog[data-ia="respuesta"]', { state: 'detached', timeout: 10000 });
  // «Listo» también sale a `_top`, y el diálogo se saca en
  // `turbo:submit-start` —ANTES del morph—, así que el `detached` de arriba se
  // cumple con la navegación todavía en vuelo. Se espera a que la propuesta
  // aceptada se vaya del panel, que es lo que sólo puede pasar una vez
  // pintada la pantalla nueva: sin esto el contador de morphs de acá abajo
  // registra ÉSTE y la guarda pasa aunque el pedido no vaya a `_top`.
  await page.waitForSelector(`form[action="${formDeListo}"]`, { state: 'detached', timeout: 10000 });

  // 3 · El camino `_top`: el pedido que refresca la PANTALLA ENTERA.
  //
  // Es el riesgo central del diseño y los dos caminos de arriba no lo tocan:
  // los dos responden al marco de propuestas. Acá el popup convive con el
  // morph —el layout declara `turbo-refresh-method: morph`— y un `<dialog
  // open>` que el cliente agregó es, para idiomorph, un nodo de más: se lo
  // lleva puesto, o le saca el `open` y lo deja en el DOM sin verse. Por eso
  // se comprueba que hubo morph de verdad y no sólo que el popup aparece.
  //
  // Va por el camino de ÉXITO y no por uno rechazado: así la respuesta trae la
  // TARJETA de la propuesta, o sea un `<form>` adentro del `<dialog>`, y de
  // paso se ejercitan `shared/_ia_respuesta` en el camino de pantalla entera
  // y el filtro de permiso por propuesta. Es el mismo «Detectar duplicados»
  // de recién —la anterior ya se aceptó, así que el runner arranca una
  // corrida nueva— y sigue sin costar un peso: compara local porque el
  // proveedor de VECTORES es el fixture.
  //
  // Ojo con lo que NO prueba: el popup de respuesta no sobrevive a nada. Se
  // cierra en `turbo:before-render` y se arma de nuevo en `turbo:render`, o
  // sea DESPUÉS del morph y a propósito —un `<dialog open>` que el cliente
  // agregó es un nodo de más para idiomorph—. Lo que tiene que no sobrevivir
  // es la ESPERA, y eso lo mira la guarda de abajo.
  await page.evaluate(() => {
    window.__morphs = 0;
    addEventListener('turbo:morph', () => { window.__morphs += 1; });
  });
  const hayFormTop = await page.evaluate(() => {
    const form = document.querySelector('form[action*="detect_duplicates"]');
    if (!form) return false;
    form.dataset.turboFrame = '_top';
    form.requestSubmit();
    return true;
  });
  if (!hayFormTop) {
    failures++;
    console.error('[IA] la ficha de la idea no ofrece «Detectar duplicados»');
  }

  await page.waitForSelector('dialog[data-ia="respuesta"][open]', { timeout: 30000 });
  if (!(await page.evaluate(() => window.__morphs > 0))) {
    failures++;
    console.error('[IA] el pedido a `_top` no pasó por un morph: este camino no se probó');
  }
  if (await page.locator('dialog[data-ia="espera"]').count()) {
    failures++;
    console.error('[IA] la espera sobrevivió al morph de la pantalla entera');
  }
  // El popup rearmado después del morph tiene que estar VISIBLE, no sólo en el
  // DOM —idiomorph puede dejar un `<dialog>` puesto y sacarle el `open`— y
  // tiene que traer su tarjeta: el `<form>` de «Listo» es lo que este camino
  // suma sobre los dos de arriba.
  const listoTrasMorph = page.locator('dialog[data-ia="respuesta"] button:has-text("Listo")');
  if (!(await listoTrasMorph.isVisible())) {
    failures++;
    console.error('[IA] el popup de la pantalla entera no trae la tarjeta de la propuesta');
  }
  await capturar(page, '09-15-ia-respuesta-pantalla-entera');

  // Se acepta de nuevo, por lo mismo que la vez anterior: dejarla pendiente
  // haría que la corrida siguiente la reúse y este camino dejaría de probarse.
  //
  // Y se ESPERA a que se vaya, igual que arriba. `shot()` arranca con un
  // `goto`, que cancela el pedido que este clic acaba de largar: la propuesta
  // quedaría pendiente y el camino dejaría de probarse en silencio, que es lo
  // que este bloque existe para evitar.
  if (await listoTrasMorph.count()) {
    const formDeListoTrasMorph = await page.getAttribute('dialog[data-ia="respuesta"] form', 'action');
    await listoTrasMorph.click();
    await page.waitForSelector(`form[action="${formDeListoTrasMorph}"]`, { state: 'detached', timeout: 10000 });
  } else {
    await page.click('dialog[data-ia="respuesta"] .ia-respuesta__cerrar');
  }

  await shot(page, '11-ai-runs', '/admin/ai_runs');

  // El muestrario en claro: ninguna pantalla del recorrido garantiza mostrar
  // las tres variantes, así que se miden a mano acá, con la hoja y el tema de
  // verdad, antes de pasar a oscuro.
  await revisarMuestrario(page, 'claro');

  // ── Las pantallas que nadie fotografiaba ────────────────────────────────
  //
  // Estas vistas no tenían ninguna captura y ninguna guarda las miraba:
  // `[PANEL]`, `[RITMO]`, `[CONTRASTE]` y `[CLASES]` sólo ven lo que el
  // recorrido abre.
  //
  // El plan original contaba OCHO, con `pages/home.html.haml` como
  // `13-home`. Esa captura no existe y no puede existir: `config/routes.rb`
  // declara `root "challenges#index"` y no hay ninguna ruta a
  // `PagesController#home` — el propio controller trae el comentario
  // «Placeholder. En Fase 2 la raíz pasa a ser el índice de desafíos», fase
  // que ya ocurrió. `/` sirve el mismo índice que ya fotografía
  // `02-challenges` (comprobado: mismo md5 byte a byte que `13-home` daba).
  // `pages/home.html.haml` ya se borró por muerta, en otra tarea del plan;
  // acá no queda nada de esa vista que fotografiar.

  // La ficha de una corrida de IA, que no es el índice.
  await page.goto(`${BASE}/admin/ai_runs`, { waitUntil: 'networkidle' });
  const aRun = page.locator('.table-link').first();
  if (!(await aRun.count())) {
    failures++;
    console.error('[LINK] el índice de corridas de IA no ofrece ninguna ficha');
  } else {
    await aRun.click();
    await page.waitForURL(/\/ai_runs\//);
    await revisarBloqueDeCodigo(page, '14-ai-run');
    await capturar(page, '14-ai-run');
  }

  // La ficha de un set de criterios: el NOMBRE, no «Editar» —eso ya es
  // `10b-criteria-editor`, que es la pantalla de edición—.
  //
  // `criteria_sets/index.html.haml` es una grilla de tarjetas, no una tabla:
  // no hay ningún `.table-link` ahí, y el NOMBRE del set no es un link —sólo
  // «Editar» lo es—. La ficha (`criteria_sets#show`) existe y está ruteada,
  // pero HOY ninguna vista de la app linkea a ella (`grep criteria_set_path`
  // sólo encuentra `edit_criteria_set_path` y `promote_criteria_set_path`):
  // se llega derivando el id del link a «Editar», que sí existe.
  await page.goto(`${BASE}/criteria_sets`, { waitUntil: 'networkidle' });
  const editarSet = page.locator('a:has-text("Editar")').first();
  if (!(await editarSet.count())) {
    failures++;
    console.error('[LINK] la biblioteca de criterios no ofrece ningún set');
  } else {
    const hrefEditar = await editarSet.getAttribute('href');
    const idSet = hrefEditar?.match(/\/criteria_sets\/([^/]+)\/edit/)?.[1];
    if (!idSet) {
      failures++;
      console.error(`[LINK] no se pudo extraer el id del set de «${hrefEditar}»`);
    } else {
      await page.goto(`${BASE}/criteria_sets/${idSet}`, { waitUntil: 'networkidle' });
      await capturar(page, '15-criteria-set');
    }
  }

  // Postular una idea. `IdeaPolicy#create?` no mira el estado del módulo
  // —sólo que haya membresía y no sea gestor—, así que quien administra
  // siempre puede abrir el formulario. Lo que SÍ depende del estado es el
  // LINK: `ideas/index.html.haml` sólo ofrece «Postular una idea» mientras
  // `ideacion&.active?`, y en `merma-bodega` ese módulo ya está `completed`
  // —arrancó y cerró, como el resto del flujo que este recorrido recorre—.
  // No hay otro desafío sembrado con la postulación todavía abierta que no
  // esté reservado para otra captura (`con-salteado`, `recorrido-ia`) o que
  // no sea dato armado a mano fuera de `db/seeds.rb`. No se aprieta
  // «Guardar»: la captura no deja un borrador sembrado en la base.
  await page.goto(`${BASE}/challenges/${CHALLENGE}/ideas/new`, { waitUntil: 'networkidle' });
  if (!(await page.locator('h1:has-text("Postular una idea")').count())) {
    failures++;
    console.error('[LINK] /ideas/new no renderizó el formulario de postulación');
  }
  await capturar(page, '16-idea-new');

  await page.goto(`${BASE}/challenges/${CHALLENGE}/ideas`, { waitUntil: 'networkidle' });
  const aIdeaExistente = page.locator('a.idea-list__link').first();
  if (!(await aIdeaExistente.count())) {
    failures++;
    console.error('[LINK] la lista de ideas no tiene ninguna idea');
  } else {
    await aIdeaExistente.click();
    await page.waitForURL(/\/ideas\//);
    const aEditar = page.locator('a:has-text("Editar")').first();
    if (!(await aEditar.count())) {
      failures++;
      console.error('[LINK] la ficha de la idea no ofrece editarla');
    } else {
      await aEditar.click();
      await page.waitForURL(/\/edit/);
      await capturar(page, '17-idea-edit');
    }
  }

  // La ficha de evaluación: el formulario que se llena para puntuar una idea.
  // No la cubría ninguna captura —`09-11-panel-evaluacion` es la pantalla del
  // MÓDULO, no ésta— y por eso la tarea 6 tuvo que verificarla a mano.
  //
  // No sale de `merma-bodega`: ahí el flujo corrió entero y sus dos módulos
  // de evaluación quedan `completed`, así que ninguna fila ofrece «Evaluar»
  // —la vista exige `step.active?` además de la policy
  // (`steps/_fila_de_evaluacion.html.haml`)—. `comite-abierto` existe sólo
  // para esto: un módulo de evaluación TODAVÍA activo, con una idea real de
  // otra persona.
  await page.goto(`${BASE}/challenges/comite-abierto`, { waitUntil: 'networkidle' });
  const aComite = page.locator('.table-link', { hasText: /comit/i }).first();
  if (!(await aComite.count())) {
    failures++;
    console.error('[LINK] «comite-abierto» no tiene el módulo de evaluación de comité');
  } else {
    await aComite.click();
    await page.waitForURL(/\/steps\/[^/]+$/);
    const aEvaluar = page.locator('a:has-text("Evaluar")').first();
    if (!(await aEvaluar.count())) {
      failures++;
      console.error('[LINK] el módulo de comité no ofrece evaluar ninguna idea');
    } else {
      await aEvaluar.click();
      await page.waitForURL(/\/assessments\/new/);
      await capturar(page, '21-evaluar-idea');
    }
  }

  // El módulo de TESTING: la cara de ejecución y el envío REAL de un testeo.
  //
  // `testeo-abierto` siembra una idea ya testeada y otra sin testear: es la
  // única forma de que la tabla muestre las dos filas y los dos textos del
  // botón («Testear» y «Re-testear»). Ningún otro desafío sembrado deja un
  // testing en ese estado. Propio y no compartido, como manda CLAUDE.md —
  // existe sólo para estas capturas.
  await page.goto(`${BASE}/challenges/testeo-abierto`, { waitUntil: 'networkidle' });
  const testingLink = page
    .locator('.table tr', { hasText: 'Prueba de factibilidad' })
    .locator('.table-link');
  if (!(await testingLink.count())) {
    failures++;
    console.error('[LINK] «testeo-abierto» no tiene el módulo de testing');
  } else {
    await Promise.all([
      page.waitForURL(/\/steps\/[^/]+$/, { timeout: 15000 }),
      testingLink.first().click()
    ]);
    await page.waitForSelector('table.table', { timeout: 15000 });

    const idaTesteada = 'Bicis eléctricas con caja térmica';
    const ideaSinTestear = 'Tercerizar el último kilómetro a un courier local';
    const reTestearOk = await page.locator('tr', { hasText: idaTesteada })
      .locator('a', { hasText: /^Re-testear$/ }).count();
    const testearOk = await page.locator('tr', { hasText: ideaSinTestear })
      .locator('a', { hasText: /^Testear$/ }).count();
    if (!reTestearOk || !testearOk) {
      failures++;
      console.error('[TESTING] el módulo no muestra las dos filas (una testeada, otra sin testear) con sus dos botones');
    }

    // `testeo-abierto` corre en `ai_assisted` justamente para que este botón
    // se pinte: en `human` (como quedó hasta acá) nunca se renderiza, y
    // `[CLASES]`/`[CONTRASTE]`/`[PANEL]` de `capturar()` sólo miran lo que el
    // DOM tiene puesto. Sin esta guarda, volver el módulo a modo humano
    // reabriría en silencio el mismo punto ciego que dejó pasar
    // `flow.ai_purposes` sin `test_idea`.
    const iaEnFilas = await page.locator('tr', { hasText: idaTesteada }).locator('button', { hasText: 'IA' }).count()
      && await page.locator('tr', { hasText: ideaSinTestear }).locator('button', { hasText: 'IA' }).count();
    if (!iaEnFilas) {
      failures++;
      console.error('[TESTING] el módulo no ofrece el botón «IA» en las filas (¿volvió a modo humano?)');
    }
    await capturar(page, '22-testing');

    // Las tres zonas de la cara de ejecución: la misma guarda que corre sobre
    // los módulos de `merma-bodega` (más abajo, con `stepLinks`), repetida
    // acá porque «Prueba de factibilidad» vive en OTRO desafío y ese loop no
    // lo recorre. Sin esto el módulo nuevo caería en la lista sin que nada lo
    // chequeara de verdad, aunque el nombre esté en `MODULOS_EN_ZONAS`.
    const enZonasTesting = MODULOS_EN_ZONAS.some((re) => re.test('Prueba de factibilidad'));
    const soloAjustesTesting = MODULOS_SOLO_AJUSTES.some((re) => re.test('Prueba de factibilidad'));
    if (enZonasTesting === soloAjustesTesting) {
      failures++;
      console.error(enZonasTesting
        ? '[ZONAS] «Prueba de factibilidad» cae en las dos listas de MODULOS_*, que se contradicen: con referencia y sin referencia'
        : '[ZONAS] «Prueba de factibilidad» no cae en ninguna de las dos listas de MODULOS_*: nadie chequea sus zonas');
    }
    if (enZonasTesting) {
      if (!(await page.locator('.app-aside').count())) {
        failures++;
        console.error('[ZONAS] «Prueba de factibilidad» no tiene columna de referencia');
      }
      if (!(await page.locator('details.ajustes__plegable').count())) {
        failures++;
        console.error('[ZONAS] «Prueba de factibilidad» no tiene los ajustes plegados');
      }
      await revisarReferencia(page, '22-testing');
    }
    if (soloAjustesTesting && !(await page.locator('details.ajustes__plegable').count())) {
      failures++;
      console.error('[ZONAS] «Prueba de factibilidad» no tiene los ajustes plegados');
    }

    // El envío REAL del formulario de testeo, completo: las situaciones, el
    // veredicto, las reservas y el resumen. `params[:situations]` llega como
    // hash indexado (`situations[0][dimension]`, …) desde ESTE formulario, y
    // no como arreglo —la forma que arma un request spec—: es el único camino
    // que ejercita esa rama de `StepTestsController#situaciones`, que hasta
    // ahora ningún test automatizado tocaba (hallazgo de la revisión de la
    // Task 6).
    //
    // RE-testea la idea que YA tenía un testeo (`idaTesteada`) y no la que
    // está sin testear: así la corrida queda idempotente. Testear la idea sin
    // testear dejaría a las DOS testeadas, y una segunda `make screens` sin
    // volver a sembrar encontraría la tabla sin ninguna fila «sin testear» ni
    // botón «Testear» — justo lo que este seed existe para mostrar. Re-testear
    // sólo reemplaza el veredicto vigente de la misma idea: la mezcla
    // testeada/sin-testear no cambia sin importar cuántas veces corra esto.
    const filaTesteada = page.locator('tr', { hasText: idaTesteada });
    const aReTestear = filaTesteada.locator('a', { hasText: /^Re-testear$/ });
    if (!(await aReTestear.count())) {
      failures++;
      console.error('[LINK] el módulo de testing no ofrece re-testear la idea ya testeada');
    } else {
      // El seed deja esta idea en «Factible con reservas», con «Viernes de
      // lluvia…» como escenario roto. Elegir siempre el mismo veredicto sólo
      // probaba algo en la corrida 1: para la 2 el badge YA decía «Factible» y
      // «Se rompió en» ya estaba en «—» antes de tocar nada, así que la
      // aserción de abajo pasaba igual con un POST que no hiciera nada. Leer
      // el estado ANTES de enviar y alternar contra él prueba lo mismo en
      // cualquier corrida, resembrada o no.
      const veredictoAntes = (await filaTesteada.locator('.badge').first().innerText()).trim();
      const rompioAntes = (await filaTesteada.locator('td').nth(2).innerText()).trim();
      const introduceFalla = rompioAntes === '—';
      const veredictoNuevo = introduceFalla ? 'con_reservas' : 'factible';
      const ETIQUETA_VEREDICTO = { factible: 'Factible', con_reservas: 'Factible con reservas', no_factible: 'No factible' };

      await Promise.all([
        page.waitForURL(/\/step_tests\/new/, { timeout: 15000 }),
        aReTestear.click()
      ]);
      await page.waitForSelector('select[name="situations[0][dimension]"]', { timeout: 15000 });

      // El aviso de que ya tiene un testeo vigente sólo aparece al RE-testear.
      if (!(await page.locator('.alert').count())) {
        failures++;
        console.error('[TESTING] re-testear no avisa que ya había un testeo vigente');
      }

      await page.selectOption('select[name="situations[0][dimension]"]', 'tecnica');
      await page.fill('input[name="situations[0][escenario]"]', 'Reparto con lluvia sostenida toda la tarde');
      await page.selectOption('select[name="situations[0][resultado]"]', introduceFalla ? 'se_rompe' : 'aguanta');
      await page.fill('input[name="situations[0][detalle]"]', introduceFalla
        ? 'La caja térmica no alcanza a mantener la temperatura pasada la hora de reparto'
        : 'La caja térmica no se moja ni pierde temperatura');

      await page.selectOption('select[name="situations[1][dimension]"]', 'operativa');
      await page.fill('input[name="situations[1][escenario]"]', 'Pico de pedidos al mediodía');
      await page.selectOption('select[name="situations[1][resultado]"]', 'aguanta');
      await page.fill('input[name="situations[1][detalle]"]', 'La flota alcanza con dos personas más');

      await page.selectOption('select[name="situations[2][dimension]"]', 'economica');
      await page.fill('input[name="situations[2][escenario]"]', 'Comparado con moto propia por entrega');
      await page.selectOption('select[name="situations[2][resultado]"]', 'aguanta');
      await page.fill('input[name="situations[2][detalle]"]', 'El costo por entrega ya no sube con la lluvia resuelta');

      await page.selectOption('select[name="verdict"]', veredictoNuevo);
      await page.fill('textarea[name="reservations"]', 'Confirmar el protocolo con el equipo de logística antes de escalar');
      await page.fill('input[name="summary"]', 'El protocolo de lluvia resolvió la única reserva pendiente.');

      // La tarjeta «¿Querés que la IA la ponga a prueba?»: como el botón «IA»
      // de la fila, sólo se sirve con el módulo activo y en un modo que no
      // sea «Solo personas» — otra vez `testeo-abierto` en `ai_assisted`, y
      // no `step_tests/new` de un desafío en modo humano, que la deja afuera.
      if (!(await page.locator('.card', { hasText: '¿Querés que la IA la ponga a prueba?' }).count())) {
        failures++;
        console.error('[TESTING] step_tests/new no ofrece la tarjeta de pedirle el testeo a la IA');
      }

      await capturar(page, '22b-testeo-nuevo');

      // Sólo `input[type="submit"]`: el header global tiene un
      // `button_to "Salir"` que también es `button[type="submit"]`, y un
      // selector que lo incluyera podía apretar «Salir» en vez de «Guardar el
      // testeo» y mandar el recorrido a `/login` en vez de al módulo.
      await Promise.all([
        page.waitForURL(/\/steps\/[^/]+$/, { timeout: 15000 }),
        page.click('input[type="submit"]')
      ]);
      await page.waitForSelector('table.table', { timeout: 15000 });

      // Lo que ninguna guarda automática ve: que el re-testeo mandado con la
      // forma REAL del formulario (el hash indexado, no el arreglo de un
      // spec) quedó guardado de verdad, y no sólo que el POST respondió 200.
      // Comparado contra el estado ANTES del envío (no contra un valor fijo):
      // si el POST no hiciera nada, esto fallaría en cualquier corrida.
      const filaActualizada = page.locator('tr', { hasText: idaTesteada });
      const veredictoActualizado = (await filaActualizada.locator('.badge').first().innerText()).trim();
      if (veredictoActualizado === veredictoAntes || veredictoActualizado !== ETIQUETA_VEREDICTO[veredictoNuevo]) {
        failures++;
        console.error(`[TESTING] el veredicto del re-testeo enviado por el formulario no quedó guardado (era «${veredictoAntes}», se ve «${veredictoActualizado}», se esperaba «${ETIQUETA_VEREDICTO[veredictoNuevo]}»)`);
      }
      const rompioDespues = (await filaActualizada.locator('td').nth(2).innerText()).trim();
      const rompioEsperado = introduceFalla ? 'Reparto con lluvia sostenida toda la tarde' : '—';
      if (rompioDespues === rompioAntes || rompioDespues !== rompioEsperado) {
        failures++;
        console.error(`[TESTING] «Se rompió en» del re-testeo no quedó guardado (era «${rompioAntes}», se ve «${rompioDespues}», se esperaba «${rompioEsperado}»)`);
      }
      // Y que re-testear una idea no le toque el estado a la otra: la mezcla
      // testeada/sin-testear tiene que sobrevivir para la próxima corrida.
      if (!(await page.locator('tr', { hasText: ideaSinTestear })
        .locator('a', { hasText: /^Testear$/ }).count())) {
        failures++;
        console.error('[TESTING] re-testear una idea le movió el estado a la otra, que tenía que seguir sin testear');
      }
    }
  }

  // El filtro por testeo: una selección que corta usando el veredicto de
  // testing (`testing_passed`), sin ninguna evaluación antes. Sale de
  // `filtro-por-testeo`, propio y no compartido —el testing ya cerró con dos
  // veredictos distintos, así que la celda del filtro muestra sus DOS
  // estados: la idea factible pasa y la no factible no.
  //
  // No hace falta clasificar «Corte por factibilidad» en `MODULOS_EN_ZONAS` ni
  // en `MODULOS_SOLO_AJUSTES`: el módulo es un `selection` más, y la forma de
  // su pantalla (sin referencia, con los ajustes plegados) ya la prueba el
  // loop de arriba sobre «Corte a top 3» y «Finalistas» —el mismo template,
  // otro desafío—. Sumarlo ahí sería sólo documentación, y encima al revés:
  // el nombre comparte «factibilidad» con la entrada que ya está en
  // `MODULOS_EN_ZONAS` (puesta para «Prueba de factibilidad», el módulo de
  // testing), así que agregarlo haría que las dos listas se contradigan sobre
  // el mismo texto.
  //
  // Read-only a propósito: no se tilda ni se confirma el corte, así que
  // `make screens` corrido dos veces sin volver a sembrar encuentra el mismo
  // estado las dos veces.
  await page.goto(BASE + '/challenges/filtro-por-testeo', { waitUntil: 'networkidle' });
  const filtroLink = page
    .locator('.table tr', { hasText: 'Corte por factibilidad' })
    .locator('.table-link');
  if (!(await filtroLink.count())) {
    failures++;
    console.error('[LINK] «filtro-por-testeo» no tiene el módulo de corte por factibilidad');
  } else {
    await Promise.all([
      page.waitForURL(/\/steps\/[^/]+$/, { timeout: 15000 }),
      filtroLink.first().click()
    ]);
    await page.waitForSelector('table.ranking-table', { timeout: 15000 });

    const filaPasa = page.locator('tr', { hasText: 'Tablet para pedir desde la mesa' });
    const filaFalla = page.locator('tr', { hasText: 'Cocina satélite en el subsuelo' });
    const gatePasa = filaPasa.locator('.gate-cell .gate--pass');
    const gateFalla = filaFalla.locator('.gate-cell .gate--fail');

    if (!(await gatePasa.count()) || !(await gateFalla.count())) {
      failures++;
      console.error('[FILTROS] la celda del filtro no muestra los dos estados (una idea pasa la prueba, la otra no)');
    } else {
      // El texto sale de `TestingPassed#detalle_de` y viaja en el `title` del
      // span (la celda sólo dibuja ✓/✗; el detalle es la explicación). La
      // idea factible no tiene reservas cargadas, así que el texto es el
      // veredicto liso —y si volviera a ser un genérico «cumple»/«no cumple»
      // en vez del veredicto, esto lo detecta—. La no factible SÍ trae una
      // reserva cargada en el seed: fotografía el camino «con condiciones a
      // resolver», que si no ninguna captura ve.
      const detallePasa = (await gatePasa.getAttribute('title')) || '';
      const detalleFalla = (await gateFalla.getAttribute('title')) || '';
      if (detallePasa !== 'Factible') {
        failures++;
        console.error(`[FILTROS] el detalle de la idea factible dice «${detallePasa}», se esperaba «Factible»`);
      }
      if (detalleFalla !== 'No factible · 1 condición a resolver') {
        failures++;
        console.error(`[FILTROS] el detalle de la idea no factible dice «${detalleFalla}», se esperaba «No factible · 1 condición a resolver»`);
      }
    }

    await capturar(page, '23-filtro-por-testeo');
  }

  // ── El taller ────────────────────────────────────────────────────────────
  //
  // Los tres desafíos son PROPIOS del recorrido (`taller-idear`,
  // `taller-evolucion`, `taller-avanzado`) y los tres talleres también —el
  // borrador, el de idear y el de evolución—: ninguno se usa a mano, como
  // manda CLAUDE.md. Un taller trabaja sobre una sola fase, así que idear y
  // evolución viven en talleres distintos. Se entra por el link «Talleres» del
  // nav y de ahí todo va por link.
  //
  // No se abre, no se propone ni se acepta nada, pero `[DRAFT]` SÍ escribe: deja
  // dos filas de `workshop_drafts` por corrida (una por cara de la sala), y la
  // captura `25` de la corrida siguiente sale con ese texto en el campo. El seed
  // borra los borradores al resembrar (el `destroy_all` del taller se los lleva
  // por cascada); resembrar no es parte de `make screens`, así que dos corridas
  // seguidas SIN resembrar no encuentran el mismo estado: `25` y `26b` salen con
  // el texto de la anterior.
  const goToWorkshop = async (workshopName) => {
    // Desde donde esté la pantalla: el nav está en todas. El listado se
    // espera por su título, no por la red.
    await Promise.all([
      page.waitForURL(/\/workshops$/, { timeout: 15000 }),
      page.click('.app-rail__item:has-text("Talleres")')
    ]);
    await page.waitForSelector('h1.page-banner:has-text("Talleres")', { timeout: 10000 });
    const workshopLink = page.locator('table.table a', { hasText: workshopName });
    if (!(await workshopLink.count())) {
      failures++;
      console.error(`[LINK] el listado de talleres no tiene «${workshopName}»`);
      return false;
    }
    await Promise.all([
      page.waitForURL(/\/workshops\/[^/]+$/, { timeout: 15000 }),
      workshopLink.first().click()
    ]);
    await page.waitForSelector('h1.page-banner', { timeout: 10000 });
    return true;
  };

  // Entrar a la sala de un desafío POR LINK, desde el selector del taller.
  // Nunca `goto`: Turbo no dispara `DOMContentLoaded` al navegar por link, y un
  // `goto` monta la pantalla igual y esconde el bug.
  //
  // El `li` se busca por el NOMBRE del desafío y el link adentro, ANCLADO al
  // selector de salas (la `card` cuyo título es «Salas»): el bloque de armado
  // lista los mismos nombres en sus propios `li.field-list__item` y desde que
  // cada mesa ofrece su propio «Entrar» tiene links con ese texto, así que
  // «tener un Entrar» ya no desempata. Hoy no colisiona por casualidad —los
  // talleres abiertos del seed tienen UN vínculo trabajable, así que el rótulo
  // de la mesa es «Entrar» pelado y el nombre del desafío no aparece en su
  // `li`—, pero con dos salas `first()` tomaría el de la mesa, porque el bloque
  // de armado se renderiza ANTES que el selector, y la corrida seguiría verde
  // midiendo otra navegación.
  const goToRoom = async (challengeName) => {
    const selector = page.locator('.card')
      .filter({ has: page.locator('h2.section-title', { hasText: 'Salas' }) });
    const entrar = selector.locator('li.field-list__item', { hasText: challengeName })
      .locator('a:has-text("Entrar")');
    if (!(await entrar.count())) {
      failures++;
      console.error(`[TALLER] el selector del taller no ofrece entrar a «${challengeName}»`);
      return false;
    }
    await Promise.all([
      page.waitForURL(/\/workshops\/[^/]+\/salas\/[^/?]+/, { timeout: 15000 }),
      entrar.first().click()
    ]);
    // Señal determinista de que la sala pintó: su propio título.
    await page.waitForSelector(`h1.page-banner:has-text("${challengeName}")`, { timeout: 10000 });
    return true;
  };

  // 24: el taller en borrador, con el bloque de armado. «Abrir taller» sólo
  // existe en este estado.
  if (await goToWorkshop('Taller de planificación (borrador)')) {
    if (!(await page.locator('button:has-text("Abrir taller"), input[value="Abrir taller"]').count())) {
      failures++;
      console.error('[TALLER] el taller en borrador no ofrece «Abrir taller»');
    }
    if (!(await page.locator('h2.section-title', { hasText: 'Mesas' }).count())) {
      failures++;
      console.error('[TALLER] el bloque de armado no muestra las mesas');
    }
    // Un taller en BORRADOR no tiene salas: nadie lo abrió todavía, y sus
    // vínculos tienen `challenge_step_id` nulo a propósito. La pantalla llegó
    // a dibujar una sala por desafío anunciando «el desafío avanzó de fase»
    // —falso sobre un borrador recién armado— y esta captura pasó igual,
    // porque las guardas de arriba sólo buscan «Abrir taller» y «Mesas» y las
    // de `capturar()` son genéricas y no leen ese texto.
    //
    // Se mide por el TÍTULO de la sala —el nombre del desafío como
    // `h2.section-title`—, que sobrevive a un cambio de redacción; en el
    // armado los desafíos son links dentro de `.field-list`, no encabezados.
    const draftRooms = await page.locator('h2.section-title', {
      hasText: /^Ideas para (la sala de descanso|la inducción de nuevos ingresos)$/
    }).count();
    if (draftRooms) {
      failures++;
      console.error(`[TALLER] el taller en borrador dibuja ${draftRooms} sala(s): todavía no se abrió`);
    }
    await capturar(page, '24-taller-armado');
  }

  // 25a, 25 y 28 salen del taller de idear, y cada captura exige lo suyo: si
  // una sala dejara de renderizar, las otras seguirían pasando. 26 y 27 salen
  // del taller de evolución, más abajo.
  if (await goToWorkshop('Taller de mejora continua')) {
    // El bloque de armado lista los MISMOS nombres de desafío en sus propios
    // `li.field-list__item`, y el motivo del vínculo cerrado también, así que
    // las dos guardas de abajo se acotan a la tarjeta del selector. Sin eso, el
    // día que el selector pierda el brief o el motivo, el armado los tendría
    // igual y las dos darían verde midiendo la tarjeta de al lado.
    const selector = page.locator('.card', {
      has: page.locator('h2.section-title', { hasText: 'Salas' })
    });

    // El selector: cada desafío con su brief y su «Entrar». Es la pantalla que
    // antes apilaba un formulario por desafío sin decir de qué trataba ninguno.
    const conBrief = await selector.locator('li.field-list__item p.muted').count();
    if (!conBrief) {
      failures++;
      console.error('[TALLER] el selector del taller no muestra el brief de ningún desafío');
    }
    await capturar(page, '25a-taller-salas');

    // 25: la sala de idear ofrece el formulario del módulo de ideación y dice
    // con quién se comparte el borrador.
    if (await goToRoom('Ideas para la sala de descanso')) {
      if (!(await page.locator('form[action*="/ideas?"] input[value="Crear borrador"]').count())) {
        failures++;
        console.error('[TALLER] la sala de idear no ofrece «Crear borrador»');
      }
      if (!(await page.locator('p.muted', { hasText: 'El borrador se comparte con Paula Participante' }).count())) {
        failures++;
        console.error('[TALLER] la sala de idear no dice con quién se comparte el borrador');
      }
      // La referencia: el brief y la mesa. Sin esto, la sala podría perder la
      // columna entera y las capturas seguirían en verde.
      if (!(await page.locator('.app-aside h2.section-title:has-text("Tu mesa")').count())) {
        failures++;
        console.error('[TALLER] la sala no dibuja «Tu mesa» en la referencia');
      }
      // Y lo que la mesa ya creó, con la participación de cada uno. El seed
      // siembra un borrador de Mesa Bodega justo para esto: sin ninguna idea el
      // bloque NO se renderiza, y durante seis corridas verdes esta captura
      // fotografió su ausencia mientras la lista de participación estaba mal
      // maquetada. `[CLASES]` no lo cazaba: las cuatro clases tienen regla en
      // la hoja. Se mide dentro de la tarjeta, no en la pantalla, porque la
      // referencia dibuja sus propios `.field-list__item`.
      const mesaIdeas = page.locator('.card', {
        has: page.locator('h2.section-title', { hasText: 'Las ideas de tu mesa' })
      });
      if (!(await mesaIdeas.count())) {
        failures++;
        console.error('[TALLER] la sala de idear no dibuja «Las ideas de tu mesa»');
      } else {
        const participacion = await mesaIdeas.locator('li.people-list__item').count();
        if (!participacion) {
          failures++;
          console.error('[TALLER] «Las ideas de tu mesa» no lista la participación de ninguna idea');
        }
        // Y va DENTRO del bloque del título, no al lado. Como hijo directo del
        // `li` queda como segundo hijo flex de `.field-list__item`
        // (`space-between`, sin `flex-wrap` afuera de `.app-aside`): las
        // cajitas de los nombres se pegan al borde derecho y aprietan el
        // título. Es el defecto que esta captura no veía porque el bloque no
        // se dibujaba; el conteo de arriba no lo distingue.
        const alCostado = await mesaIdeas.locator('li.field-list__item > ul.people-list').count();
        if (alCostado) {
          failures++;
          console.error(`[TALLER] la participación de ${alCostado} idea(s) cuelga del li y no del bloque del título`);
        }
      }
      await capturar(page, '25-taller-sala-idear');
      await revisarBorrador(page, 'sala de idear');
      await revisarGrabacion(page, 'sala de idear');
      await goToWorkshop('Taller de mejora continua');
    }

    // 28: el desafío que avanzó de fase se ve cerrado, y DICE POR QUÉ. Vive en
    // el selector, que lista los vínculos no trabajables con su motivo.
    const closedRoom = selector.locator('li.field-list__item', {
      hasText: 'Ideas para el manual de seguridad'
    }).locator('p.field-hint');
    const closedReason = (await closedRoom.count()) ? await closedRoom.first().innerText() : '';
    if (!/El desafío está en Evaluación, y un taller sólo trabaja sobre idear o evolución/.test(closedReason)) {
      failures++;
      console.error(`[TALLER] el vínculo cerrado no dice su motivo: «${closedReason}»`);
    }
    await capturar(page, '28-taller-vinculo-cerrado');
  }

  // El taller de evolución: 26 y 27 salen de acá, no del de idear. La mesa es
  // la suya —se llama igual y lleva a la misma gente a propósito—.
  if (await goToWorkshop('Taller de evolución')) {
    if (await goToRoom('Ideas para la inducción de nuevos ingresos')) {
      // 26: el selector de ideas de la mesa. Las dos de Paula; la de Pedro no,
      // porque su autor no está en esta mesa.
      const filas = await page.locator('li.field-list__item a[href*="?idea="]').count();
      const elegidas = await page.locator('li.field-list__item strong').count();
      if (filas + elegidas !== 2) {
        failures++;
        console.error(`[TALLER] el selector de la sala de evolución lista ${filas + elegidas} ideas y se esperaban 2`);
      }
      // Y la participación de cada uno, que es lo que explica por qué una idea
      // ajena entra: alguien de la mesa colabora en ella.
      if (!(await page.locator('.people-list__role:has-text("creó la idea")').count())) {
        failures++;
        console.error('[TALLER] el selector no dice quién creó cada idea');
      }
      await capturar(page, '26-taller-sala-evolucion');

      // 26b: con una idea elegida, su contenido y UN formulario. Por link.
      const primera = page.locator('li.field-list__item a[href*="?idea="]').first();
      if (await primera.count()) {
        await Promise.all([
          page.waitForURL(/\?idea=/, { timeout: 15000 }),
          primera.click()
        ]);
        await page.waitForSelector('h2.section-title:has-text("Contenido")', { timeout: 10000 });
        const forms = await page.locator('form[action*="/proposals?"] input[value="Proponer"]').count();
        if (forms !== 1) {
          failures++;
          console.error(`[TALLER] con una idea elegida hay ${forms} formularios de propuesta y se esperaba 1`);
        }
        await capturar(page, '26b-taller-idea-elegida');
        await revisarBorrador(page, 'sala de evolución');
        await revisarGrabacion(page, 'sala de evolución');
      } else {
        failures++;
        console.error('[TALLER] ninguna idea del selector se puede elegir');
      }
      await goToWorkshop('Taller de evolución');
    }

    // 27: la propuesta de la mesa, en la ficha de la idea. Por link: taller →
    // desafío → «Ideas» → la idea. La ficha la ve quien administra, que no es
    // autor: la propuesta se muestra, sin botones.
    await Promise.all([
      page.waitForURL(/\/challenges\/taller-evolucion$/, { timeout: 15000 }),
      page.locator('.field-list a', { hasText: 'Ideas para la inducción de nuevos ingresos' }).first().click()
    ]);
    await Promise.all([
      page.waitForURL(/\/challenges\/taller-evolucion\/ideas$/, { timeout: 15000 }),
      page.locator('a.btn:has-text("Ideas")').first().click()
    ]);
    await Promise.all([
      page.waitForURL(/\/ideas\/[^/]+$/, { timeout: 15000 }),
      page.locator('.idea-list__item', { hasText: 'Un buddy para la primera semana' })
        .locator('.idea-list__link').first().click()
    ]);
    // Se espera la tarjeta de la propuesta, que sólo existe con la ficha
    // nueva pintada.
    await page.waitForSelector('[id^="workshop_proposal_"]', { timeout: 10000 });
    const proposalCard = page.locator('[id^="workshop_proposal_"]');
    if (!/Propuesta de la mesa «Mesa Bodega»/.test(await proposalCard.first().innerText())) {
      failures++;
      console.error('[TALLER] la ficha no muestra la propuesta de la mesa');
    }
    if (await proposalCard.locator('button:has-text("Aceptar"), input[value="Aceptar"]').count()) {
      failures++;
      console.error('[TALLER] quien no es autor ve «Aceptar» en la propuesta');
    }
    await capturar(page, '27-taller-propuesta-en-la-idea');
  }

  // El QR del check-in. El token es aleatorio por siembra, así que el link se
  // LEE de la pantalla —es para eso que el diseño lo pone en texto debajo del
  // código— y se usa más abajo, en la pasada sin sesión.
  //
  // Con la guarda de las otras: `goToWorkshop` cuenta la falla y devuelve false
  // SIN moverse del listado, y seguir de largo leería un locator que no matchea
  // nada, que lanza y aborta la corrida entera. Una corrida abortada y una con
  // fallas no se leen igual.
  if (await goToWorkshop('Taller con check-in')) {
    const svg = page.locator('.card:has-text("Check-in por link") svg');
    if (!(await svg.count())) {
      failures++;
      console.error('[CHECKIN] la pantalla del taller no dibuja el QR');
    } else {
      // Contarlo no alcanza: `qr_svg` lo emite con `viewBox` y SIN width ni
      // height —el tamaño lo decide el contenedor, a propósito—, así que el
      // tamaño del código no está en el SVG. Si `.w-60` pasa a ser otro ancho
      // —un renombre, un token roto— el QR se achica y el contador sigue
      // diciendo 1. Un QR que no se escanea es la
      // única falla que esta función no sobrevive, y no la ve nadie más:
      // `[CLASES]` no, porque el `.bg-white` le da fondo al contenedor;
      // `[RELLENO]` mira `card-body` y `[CONTRASTE]`, color. Así que se MIDE.
      //
      // 150px de piso. Hoy mide 208 —los 240 de `w-60` menos los dos `p-4`,
      // con `box-sizing: border-box`— y el link ronda los 55 caracteres, o sea
      // unos 37 módulos por lado con nivel M: 150/37 ≈ 4px por módulo, que es
      // el piso con el que un lector de teléfono lo saca de una pantalla. Los
      // 58px de margen que deja no los gasta el layout, porque `w-60` es un
      // ancho fijo y no un porcentaje.
      //
      // Y se pide CUADRADO, pero ESA rama hoy no la puede disparar `qr_svg` y
      // está medido: sacarle `viewbox: true` no deja al SVG en los 300×150 que
      // el navegador usa por default, porque rqrcode entonces emite `width` y
      // `height` fijos y el código sale cuadrado y grande igual —lo que se
      // rompe ahí es el escalado por contenedor, que no es ilegibilidad—. La
      // comparación se queda porque cuesta una resta y porque el día que el
      // helper emita un `viewBox` no cuadrado, o un `width` sin su `height`,
      // pasa a ser alcanzable. Es protección por adelantado, no una falla
      // observada: la rama del piso de 150px sí está probada por mutación.
      const caja = await svg.first().boundingBox();
      if (!caja) {
        failures++;
        console.error('[CHECKIN] el QR está en el DOM pero no ocupa lugar en la pantalla');
      } else {
        const medida = `${Math.round(caja.width)}×${Math.round(caja.height)}`;
        if (Math.min(caja.width, caja.height) < 150) {
          failures++;
          console.error(`[CHECKIN] el QR mide ${medida}: así no se escanea`);
        } else if (Math.abs(caja.width - caja.height) > caja.width * 0.1) {
          failures++;
          console.error(`[CHECKIN] el QR no salió cuadrado (${medida}): el viewBox no manda el tamaño`);
        }
      }
    }
    const hint = page.locator('.card:has-text("Check-in por link") .field-hint');
    if (await hint.count()) {
      const leido = (await hint.first().innerText()).trim();
      if (/\/checkin\/[A-Za-z0-9]+$/.test(leido)) {
        checkinUrl = leido;
      } else {
        failures++;
        console.error(`[CHECKIN] el link del QR no se pudo leer: «${leido}»`);
      }
    } else {
      failures++;
      console.error('[CHECKIN] la pantalla del taller no muestra el link del QR en texto');
    }
    await capturar(page, '29-taller-checkin');

    // La lista de la llegada tiene que refrescarse SOLA. No hace falta una
    // segunda persona entrando: alcanza con contar los `turbo:frame-render` de
    // ese frame y exigir que el contador crezca sin que nadie toque nada.
    //
    // Probar «entró alguien nuevo mientras yo miraba» pediría dos sesiones
    // simultáneas, y un `browser.newContext()` trae una `page` SIN los listeners
    // de `pageerror` y de `response`, que se registran una sola vez: la captura
    // quedaría ciega justo a lo que esto existe para cazar. Qué devuelve el
    // endpoint lo prueba `spec/requests/workshop_arrival_live_spec.rb`: cada
    // herramienta prueba lo que puede probar.
    const refreshes = await page.evaluate(async () => {
      const frame = document.getElementById('arrival');
      if (!frame) return { error: 'sin frame' };
      if (frame.dataset.live !== 'true') return { error: 'el frame no está vivo' };
      let n = 0;
      const count = (e) => { if (e.target.id === 'arrival') n++; };
      addEventListener('turbo:frame-render', count);
      // Algo más que el intervalo declarado, para no depender del reloj.
      const wait = (Number(frame.dataset.interval) || 5000) + 1500;
      await new Promise((r) => setTimeout(r, wait));
      removeEventListener('turbo:frame-render', count);
      return { n };
    });
    if (refreshes.error || !refreshes.n) {
      failures++;
      console.error(`[LIVE] la mesa de llegada no se refrescó sola: ${JSON.stringify(refreshes)}`);
    } else {
      liveMeasurements++;
    }
  } else {
    console.error('[CHECKIN] sin el taller no hay link, y la pasada pública (30, 30b) no corre');
  }

  // ── Las que piden otra sesión ───────────────────────────────────────────
  //
  // Van últimas de la pasada clara: el recorrido como admin ya terminó, así
  // que cambiar de usuario acá no le saca la sesión a ninguna captura.
  const salir = async () => {
    // Sin empresa elegida `/challenges` rebota a `/select_company` —es el
    // estado que deja `18-select-company` con `multi@demo.test`— y desde ahí
    // se sale igual: `SessionsController#destroy` está en las excepciones de
    // `require_company`. Antes no lo estaba y el propio `DELETE /logout`
    // rebotaba al selector, así que había que elegir una empresa cualquiera
    // para poder salir: el único botón de esa pantalla era el que encerraba.
    await page.goto(`${BASE}/challenges`, { waitUntil: 'networkidle' });
    await page.click('form[action="/logout"] button, form[action="/logout"] input[type="submit"]');
    await page.waitForURL(/\/login/, { timeout: 10000 });
  };
  const entrar = async (email) => {
    await page.goto(`${BASE}/login`, { waitUntil: 'networkidle' });
    await page.fill('input[name="email"]', email);
    await page.fill('input[name="password"]', 'Test1234');
    await page.click('input[type="submit"]');
    await page.waitForLoadState('networkidle');
  };

  // Elegir empresa: `multi@demo.test` es la cuenta que el seed deja con dos
  // membresías, así que el login la manda acá en vez de a los desafíos.
  await salir();
  await entrar('multi@demo.test');
  await capturar(page, '18-select-company');

  // Las cinco `.card-body.empty-state` de las VISTAS (A1) no las abre ningún
  // otro paso del recorrido —la sexta de la app es el estado vacío del
  // builder, que vive en `pipeline_builder.vue` y sale en
  // `03b-builder-plantillas`—. «Otra Empresa» —la segunda del seed— no tiene
  // ningún desafío ni ningún set, y es la única puerta alcanzable acá: se
  // elige por NOMBRE y no por posición, porque el orden de `@memberships` no
  // está declarado en ningún lado.
  // `choose_company_path` redirige a `root_path`, que sirve `challenges#index`
  // pero deja la URL en `/` —`root "challenges#index"`—: `waitForURL` a
  // `/challenges` nunca dispara. Se espera el título de la pantalla.
  await page.click('.company-list button:has-text("Otra Empresa")');
  await page.waitForSelector('h1.page-banner:has-text("Desafíos")');
  await capturar(page, '18b-desafios-vacio');
  await revisarEstadoVacio(page, '18b-desafios-vacio');

  // Por link —el nav de arriba—, no `goto`: es el mismo camino que recorrería
  // cualquiera, y `manages_challenges?` lo ofrece porque acá `multi@demo.test`
  // es admin.
  await page.click('.app-rail__item:has-text("Criterios")');
  await page.waitForURL(/\/criteria_sets$/);
  await capturar(page, '18c-criterios-vacio');
  await revisarEstadoVacio(page, '18c-criterios-vacio');

  // El 403. Quien participa SÍ ve el desafío —`ChallengeStepPolicy#show?` es
  // cualquiera de la empresa— pero no lo arma: `ChallengePolicy#builder?` es
  // `manager?`. Es el 403 legítimo que CLAUDE.md describe, no un oráculo de
  // existencia: fotografiar un 403 sobre algo que no se debería ver sería
  // fotografiar un bug.
  await salir();
  await entrar('part1@demo.test');
  await shotConEstado(page, '19-forbidden', `/challenges/${CHALLENGE}/builder`, 403);

  // El 404, sobre un slug que no existe.
  await shotConEstado(page, '20-not-found', '/challenges/no-existe', 404);

  // El check-in sin sesión. `salir()` y NO un `browser.newContext()`: un
  // contexto nuevo trae una `page` nueva SIN los listeners de `pageerror` y de
  // `response`, que se registran una sola vez sobre la del recorrido. La
  // captura quedaría ciega justo a lo que esto existe para cazar, y daría verde.
  //
  // Acá el `goto` es correcto: no hay link que seguir —el QR es una imagen— y
  // la pantalla pública no monta ninguna isla ni carga el bundle de JS, que es
  // lo que la regla de «navegá por link» protege.
  //
  // Sin link leído no hay nada que abrir: `29` ya contó la falla, y un `goto`
  // a `null` abortaría la corrida.
  if (checkinUrl) {
    await salir();
    await page.goto(checkinUrl, { waitUntil: 'networkidle' });
    if (!(await page.locator('input[name="email"]').count())) {
      failures++;
      console.error('[CHECKIN] la pantalla pública no ofrece el formulario');
    }
    await capturar(page, '30-checkin-publico');

    // El registro, con un email FIJO: la primera corrida crea la cuenta, las
    // siguientes autentican con la misma clave y el check-in sólo re-marca
    // presente. Es idempotente por el mismo mecanismo que hace que el formulario
    // único no sea un oráculo de cuentas.
    //
    // `.example` y no `.test`: `Flow::Demo` identifica lo sembrado por el sufijo
    // `.test`, así que una cuenta `@demo.test` creada acá aparecería en la lista
    // de la pantalla de login y cambiaría esa captura.
    await page.fill('input[name="email"]', 'llegada@taller.example');
    await page.fill('input[name="name"]', 'Lucía Llegada');
    await page.fill('input[name="password"]', 'Test1234');
    // Si el registro falla, el listener de `response` ya contó el 4xx, pero el
    // `waitForURL` vencería y lanzaría: abortaría la corrida en vez de sumarle
    // una falla contada, que es lo que `29` también evita.
    //
    // El taller tiene UN solo desafío y ella no lo administra, así que el
    // taller redirige derecho a la sala: el `Location` del check-in apunta a
    // `workshops#show` y ésa es otra redirección más, así que la URL del
    // taller no llega a quedar nunca en la barra —se espera la de la sala, no
    // la intermedia—.
    let entro = true;
    try {
      await Promise.all([
        page.waitForURL(/\/workshops\/[^/]+\/salas\/[^/?]+/, { timeout: 15000 }),
        page.click('input[type="submit"]')
      ]);
    } catch (e) {
      entro = false;
      failures++;
      console.error(`[CHECKIN] el registro no llevó a la sala: ${e.message.split('\n')[0]}`);
    }
    if (entro) {
      // La sala tiene que decir que la mesa todavía no se armó: es la mesa de
      // llegada, y de ella no se trabaja. Si dijera otra cosa, el borrador que
      // alguien cree ahí nacería con toda la sala como contribuyentes. El
      // mensaje vive en la sala: es la única cara que puede decirlo.
      if (!(await page.locator('p.muted', { hasText: 'Tu mesa todavía no se armó' }).count())) {
        failures++;
        console.error('[CHECKIN] entró, pero la sala no anuncia la espera de la mesa de llegada');
      }
      // Y el acuse del escaneo, que es lo único que le confirma que funcionó.
      // Es la ÚNICA cadena de dos redirects de la app —check-in → taller →
      // sala— y el flash tiene que sobrevivir los dos: la pantalla del medio
      // lo conserva a mano (`flash.keep` en `workshops#show`). Acá es donde se
      // mide de verdad: lo que ve quien escanea el QR.
      if (!(await page.locator('.alert', { hasText: 'Listo: estás en el taller' }).count())) {
        failures++;
        console.error('[CHECKIN] entró a la sala sin el aviso del escaneo: se perdió en la cadena de redirects');
      }
      await capturar(page, '30b-taller-llegada');
    }
  }

  // Vuelve el admin: la pasada oscura sigue después y recorre pantallas que
  // sólo quien administra ve.
  await salir();
  await entrar('admin@demo.test');

  // ── Tema oscuro ──────────────────────────────────────────────────────────
  //
  // El contraste se mide en los dos temas: una variante que pasa en claro
  // puede no pasar en oscuro. Se emula `prefers-color-scheme` y se vuelve a
  // las pantallas donde viven los chips y los avisos. Por URL y no por link:
  // esto no prueba navegación, prueba colores, y el recorrido por link ya
  // corrió en claro.
  await page.emulateMedia({ colorScheme: 'dark' });
  // Las pantallas de módulo también, que son las que el plan 2b reordena. Por
  // URL, como el resto de esta pasada: esto prueba colores, no navegación.
  const oscuroDeModulos = [
    ['94-oscuro-evaluacion', stepLinks.find((l) => l.text.match(/comit/i))],
    ['95-oscuro-seleccion', stepLinks.find((l) => l.text.match(/Corte a top/i))],
    ['96-oscuro-evolucion', stepLinks.find((l) => l.text.match(/Ronda de feedback/i))],
    ['97-oscuro-reporteria', stepLinks.find((l) => l.text.match(/Reporte/i))],
    // Idear se quedó afuera de esta pasada cuando la Tarea 4 la armó, así que
    // la única pantalla de módulo que el plan 2b reordenó y nadie miraba en
    // oscuro era justo la primera del flujo.
    ['99-oscuro-idear', stepLinks.find((l) => l.text.match(/Postulaci/i))]
  ];
  for (const [nombre, link] of oscuroDeModulos) {
    if (!link) {
      failures++;
      console.error(`[LINK] la pasada oscura no encontró el módulo de ${nombre}`);
    }
  }
  for (const [nombre, url] of [
    ['90-oscuro-desafios', '/challenges'],
    ['91-oscuro-desafio', `/challenges/${CHALLENGE}`],
    ['92-oscuro-criterios', '/criteria_sets'],
    ['93-oscuro-ia', '/admin/ai_runs'],
    ...oscuroDeModulos.filter(([, link]) => link).map(([nombre, link]) => [nombre, link.href]),
    ['98-oscuro-salteado', '/challenges/con-salteado']
  ]) {
    await page.goto(BASE + url, { waitUntil: 'networkidle' });
    if (nombre === '90-oscuro-desafios') {
      await revisarMuestrario(page, 'oscuro');
    }
    // Los mismos dos drawers que la pasada clara, por la misma razón:
    // `con-salteado` tiene pendiente, en curso y salteado, y el completado
    // solo está en `merma-bodega`. Con uno solo, el punto verde no se mide en
    // oscuro.
    if (nombre === '98-oscuro-salteado') await revisarPuntos(page, nombre, 'oscuro', PUNTOS_DE_SALTEADO);
    if (nombre === '91-oscuro-desafio') await revisarPuntos(page, nombre, 'oscuro', PUNTOS_DE_MERMA);
    // Después de `revisarPuntos` —que cuenta los puntos del drawer y no
    // depende de lo plegado— y antes de la captura, que es lo que esto mejora.
    await abrirPlegables(page);
    await capturar(page, nombre);
    // DESPUÉS de capturar, igual que la pasada clara: esta guarda le cambia la
    // clase al chip para medir las dos variantes y después la repone, y
    // mientras está cambiada el chip no es el que la app renderiza. Antes de
    // la captura, la reposición pasaba a sostener la foto y las guardas que
    // viven en `capturar()`.
    if (nombre === '91-oscuro-desafio') await revisarChipDelDrawer(page, nombre, 'oscuro');
  }
  await page.emulateMedia({ colorScheme: 'light' });

  // Con sesión primero —es donde el mecanismo puede fallar— y después sin ella
  // (el login). La segunda cierra la sesión del recorrido, así que va al final.
  await revisarTema(page, 'con sesión', '/challenges');
  await page.context().clearCookies();
  await revisarTema(page, 'login', '/');

  await browser.close();

  // Los dos pisos van acá porque son de la CORRIDA, no de una pantalla: lo que
  // vigilan es que la guarda haya tenido algo que medir. Una que mide cero da
  // verde y es indistinguible de una que funciona, que es el modo de falla que
  // este script ya pagó dos veces (la pasada oscura del muestrario, y `[MONO]`
  // después del arreglo).
  console.log(`[RITMO] ${pantallasConRitmo} de ${shots.length} pantallas tuvieron dos tarjetas que comparar · [RELLENO] ${cardBodiesMedidos} \`card-body\` medidos · [PASTILLA] ${pastillasMedidas} chips y avisos medidos · [CRITERIO] ${criteriosMedidos} nombres medidos · [LIVE] ${liveMeasurements} pantalla(s) medida(s) · [RIEL] ${rielesMedidos} pantallas con riel · [BANDA] ${bandasMedidas} pantallas con banda · [SOMBRA] ${sombrasMedidas} tarjetas medidas · [CAMPO] ${camposMedidos} campos medidos · [DRAFT] ${draftMeasurements} caras medidas · [GRABAR] ${recordingMeasurements} caras medidas`);
  if (pantallasConRitmo < PISO_DE_RITMO) {
    failures++;
    console.error(`[RITMO] sólo ${pantallasConRitmo} de ${shots.length} pantallas tuvieron un par de tarjetas que comparar, y el piso es ${PISO_DE_RITMO}: la guarda dejó de ver las tarjetas`);
  }
  if (criteriosMedidos < PISO_DE_CRITERIOS) {
    failures++;
    console.error(`[CRITERIO] sólo se midieron ${criteriosMedidos} nombres de criterio en ${shots.length} pantallas, y el piso es ${PISO_DE_CRITERIOS}: la guarda dejó de ver el desglose`);
  }
  if (pastillasMedidas < PISO_DE_PASTILLAS) {
    failures++;
    console.error(`[PASTILLA] sólo se midieron ${pastillasMedidas} chips y avisos en ${shots.length} pantallas, y el piso es ${PISO_DE_PASTILLAS}: la guarda dejó de ver los chips`);
  }
  if (draftMeasurements < PISO_DE_BORRADORES) {
    failures++;
    console.error(`[DRAFT] sólo ${draftMeasurements} de ${PISO_DE_BORRADORES} caras de la sala midieron el autoguardado: la guarda dejó de ver una`);
  }
  if (recordingMeasurements < PISO_DE_GRABACIONES) {
    failures++;
    console.error(`[GRABAR] sólo ${recordingMeasurements} de ${PISO_DE_GRABACIONES} caras de la sala midieron el viaje de la grabación: la guarda dejó de ver una`);
  }
  if (!liveMeasurements) {
    failures++;
    console.error('[LIVE] no se midió ninguna pantalla con la llegada en vivo');
  }
  if (temaMedido < 2) {
    failures++;
    console.error(`[TEMA] la guarda midió ${temaMedido} pantalla(s) y son 2: con sesión y el login`);
  }
  if (rielesMedidos < PISO_DE_RIEL) {
    failures++;
    console.error(`[RIEL] sólo ${rielesMedidos} pantallas tuvieron riel y el piso es ${PISO_DE_RIEL}: la guarda dejó de verlo`);
  }
  if (bandasMedidas < PISO_DE_BANDAS) {
    failures++;
    console.error(`[BANDA] sólo ${bandasMedidas} pantallas dibujaron banda y el piso es ${PISO_DE_BANDAS}`);
  }
  if (sombrasMedidas < PISO_DE_SOMBRAS) {
    failures++;
    console.error(`[SOMBRA] sólo ${sombrasMedidas} tarjetas medidas y el piso es ${PISO_DE_SOMBRAS}: la guarda dejó de verlas`);
  }
  if (camposMedidos < PISO_DE_CAMPOS) {
    failures++;
    console.error(`[CAMPO] sólo ${camposMedidos} campos medidos y el piso es ${PISO_DE_CAMPOS}: la guarda dejó de verlos`);
  }
  if (cardBodiesMedidos < PISO_DE_CARD_BODY) {
    failures++;
    console.error(`[RELLENO] sólo se midieron ${cardBodiesMedidos} \`card-body\` en ${shots.length} pantallas, y el piso es ${PISO_DE_CARD_BODY}: la guarda dejó de ver las tarjetas`);
  }

  console.log(`\n${shots.length} capturas en ${OUT}`);
  if (failures) {
    console.error(`\n${failures} errores de página. La maqueta tiene pantallas rotas.`);
    process.exit(1);
  }
  console.log('Sin errores de JS ni respuestas >= 400.');
})().catch((e) => { console.error('FALLO:', e.message); process.exit(1); });
