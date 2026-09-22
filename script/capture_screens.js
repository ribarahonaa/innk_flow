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
async function revisarFormsAnidados(page, name, url) {
  const html = await (await page.request.get(BASE + url)).text().catch(() => '');
  let profundidad = 0;
  let maxima = 0;
  for (const etiqueta of html.match(/<form\b|<\/form>/g) || []) {
    profundidad += etiqueta === '</form>' ? -1 : 1;
    maxima = Math.max(maxima, profundidad);
  }
  if (maxima > 1) {
    failures++;
    console.error(`[FORMS] ${name} sirve un formulario dentro de otro: el navegador se come el interno`);
  }
}

// Las tarjetas tenían `margin: 0` y se tocaban: la página era una sola columna
// blanca continua partida por hairlines, sin agrupar nada. Se ve midiendo, no
// mirando —a simple vista el borde doble parece una separación—.
async function revisarRitmo(page, name) {
  const pegadas = await page.evaluate(() => {
    const paneles = [...document.querySelectorAll('.app-main > .card')];
    let juntas = 0;
    for (let i = 1; i < paneles.length; i++) {
      const anterior = paneles[i - 1].getBoundingClientRect();
      const actual = paneles[i].getBoundingClientRect();
      if (actual.top - anterior.bottom < 8) juntas++;
    }
    return juntas;
  });

  if (pegadas > 0) {
    failures++;
    console.error(`[RITMO] ${name}: ${pegadas} tarjetas pegadas a la anterior, sin separación`);
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
    return document.querySelector('.page-title')?.getBoundingClientRect().top ?? null;
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
    // cualquier elemento que se quedó sin la regla que lo pintaba. El punto
    // del drawer entró acá cuando dejó de ser un `badge` vaciado —antes lo
    // cubría `[class*="badge"]`— y su fondo es un `color-mix()` sobre
    // `--punto`: si ese token se rompe o se renombra, el `color-mix()` queda
    // inválido, el fondo cae a transparente y el punto se vuelve invisible
    // sin dejar rastro en el DOM.
    for (const el of document.querySelectorAll('[class*="badge"],[class*="btn"],[class*="alert"],[class*="flow-drawer__punto"],.steps,.panel,.card,.table :is(th,td)')) {
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
        let fondo = fondoDe(el);
        let texto = sobre(rgba(getComputedStyle(el).color), fondo);
        const { o, detras } = atenuacion(el);
        if (o < 1 && detras) {
          fondo = sobre([...fondo.slice(0, 3), o], detras);
          texto = sobre([...texto.slice(0, 3), o], detras);
        }
        const [claro, oscuro] = [luminancia(texto), luminancia(fondo)].sort((a, b) => b - a);
        return { clase: el.className, texto: el.textContent.trim().slice(0, 40), ratio: (claro + 0.05) / (oscuro + 0.05) };
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

// Los componentes suaves de DaisyUI (`badge-soft`, `alert-soft`) pintan el
// texto con el color PURO del tema, y los colores que la hoja usaba para el
// texto de un chip (`--ok`, `--warn`, `--danger`) están oscurecidos justamente
// porque puros no llegaban. Esto dice cuál hay que ajustar, en cada pantalla.
async function revisarContraste(page, name) {
  const bajos = (await medirContraste(page, '.badge, .alert')).filter((m) => m.ratio < 4.5);
  const unicos = [...new Map(bajos.map((m) => [m.clase, m])).values()].slice(0, 6);
  if (unicos.length) {
    failures++;
    console.error(`[CONTRASTE] ${name}: ${unicos.map((m) => `«${m.texto}» (${m.clase}) ${m.ratio.toFixed(2)}:1`).join(' · ')}`);
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
}

// La captura y las revisiones que solo piden la pantalla ya pintada.
//
// La mayoría de las pantallas no se abren por URL —se llega a ellas con un
// clic, esperando que monte una isla— y por eso no pasan por `shot()`. La
// revisión de clases descartadas corría en tres pantallas sueltas y el spec
// dice «en cada pantalla del recorrido»: acá adentro corre en todas,
// incluidas las que solo existen después de navegar.
//
// Sin números a propósito: este comentario, `README.md` y `CLAUDE.md` los
// tenían, y los tres se desactualizaron cada vez que se sumó una captura. El
// número real lo imprime la corrida al terminar.
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

async function capturar(page, name) {
  await page.screenshot({ path: `${OUT}/${name}.png`, fullPage: true });
  await revisarClasesDescartadas(page, name);
  await revisarCardSinBody(page, name);
  await revisarContraste(page, name);
  shots.push(name);
}

async function shot(page, name, url, prepare) {
  await page.goto(BASE + url, { waitUntil: 'networkidle' });
  if (prepare) await prepare(page);
  await revisarTexto(page, name);
  await revisarFormsAnidados(page, name, url);
  await revisarRitmo(page, name);
  await capturar(page, name);
}

// Una pantalla de error es la ÚNICA que se fotografía con un estado >= 400, y
// hay que poder hacerlo sin aflojar la regla: un `>= 400 se ignora` a secas
// volvería ciega la corrida entera, que es lo que esta guarda evita.
//
// `estadoEsperado` vale para la navegación siguiente y sólo para el documento
// principal. Si llega OTRO estado, sigue fallando: lo que se declara es cuál,
// no que no importe.
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
  await revisarTexto(page, name);
  await revisarRitmo(page, name);
  await capturar(page, name);
  estadoEsperado = null;
}

// Los módulos cuya cara de ejecución está en tres zonas (plan 2b): todos menos
// las selecciones. Por nombre del seed de `merma-bodega`, igual que el resto
// del recorrido — y por eso el loop exige que cada módulo caiga en exactamente
// una de las dos listas: si no, renombrarlo en el seed lo deja sin chequear.
const MODULOS_EN_ZONAS = [/Evaluaci/i, /Ronda de feedback/i, /Postulaci/i, /Reporte/i, /factibilidad/i];
// Las selecciones van sin referencia —con la columna puesta el ranking no
// entraba en el centro—, pero los ajustes plegados sí los tienen.
const MODULOS_SOLO_AJUSTES = [/Corte a top|Finalistas/i];

// Cuántos puntos de estado tiene que mostrar el drawer de cada desafío: uno por
// módulo (`_flow_drawer.html.haml`, la cara de «arrancado»). Fijos y no sacados
// de la página, por lo mismo que `PASOS_DE_SIN_FORMULARIO`. Si el seed le
// cambia los módulos a uno de los dos, este número cambia con él.
const PUNTOS_DE_SALTEADO = 3; // `con-salteado`: idear, evolución, evaluación
const PUNTOS_DE_MERMA = 7;    // `merma-bodega`, el desafío del recorrido

(async () => {
  // Se limpia antes de empezar: una captura que dejó de tomarse queda en disco
  // como si siguiera siendo el estado actual, y eso es peor que no tenerla.
  for (const file of fs.readdirSync(OUT)) {
    if (file.endsWith('.png')) fs.unlinkSync(`${OUT}/${file}`);
  }

  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });

  await probarMedidorDeContraste(page);

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

    // El editor de campos quedó FUERA del form del módulo (los dos conviven
    // en la misma pantalla, uno detrás del otro): si quedara adentro, el
    // navegador se comería el form interno y sus botones pasarían a
    // pertenecer al externo.
    await revisarFormsAnidados(page, '05b-form', new URL(page.url()).pathname);
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

    // Esta cara combina tres forms en la misma pantalla (el módulo, los
    // criterios o el formulario, y las asignaciones): el mismo riesgo de
    // form-dentro-de-form que ya se pagó una vez en la pantalla del corte.
    await revisarFormsAnidados(page, `05e-config-${slug}`, new URL(page.url()).pathname);
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
  await page.goto(`${BASE}/challenges/${CHALLENGE}`, { waitUntil: 'networkidle' });
  const ideacion = stepLinks.find((l) => l.text.match(/Postulaci/i));
  if (ideacion) {
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

    // El bloque de criterios quedó FUERA del form del módulo (los dos
    // conviven en la misma pantalla, uno detrás del otro): si quedara
    // adentro, el navegador se comería el form interno y sus botones
    // pasarían a pertenecer al externo.
    await revisarFormsAnidados(page, '09-12-criterios-del-modulo', new URL(page.url()).pathname);
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
    // `capturar()` no corre `[RITMO]` —lo corre `shot()`, y acá se navega por
    // link y no por `shot()`— y ésta es de las pocas capturas nuevas donde
    // importa: `ai_runs/show` pone hasta tres `.card` hermanas directas de
    // `.app-main` (prompt, respuesta, sugerencias derivadas).
    await revisarRitmo(page, '14-ai-run');
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
      // Misma razón que en `14-ai-run`: se llega por `goto`, no por `shot()`.
      // `criteria_sets/show` es hija directa de `.app-main`, así que
      // `.app-main > .card` matchea.
      await revisarRitmo(page, '15-criteria-set');
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
      await page.selectOption('select[name="situations[0][resultado]"]', 'aguanta');
      await page.fill('input[name="situations[0][detalle]"]', 'La caja térmica no se moja ni pierde temperatura');

      await page.selectOption('select[name="situations[1][dimension]"]', 'operativa');
      await page.fill('input[name="situations[1][escenario]"]', 'Pico de pedidos al mediodía');
      await page.selectOption('select[name="situations[1][resultado]"]', 'aguanta');
      await page.fill('input[name="situations[1][detalle]"]', 'La flota alcanza con dos personas más');

      await page.selectOption('select[name="situations[2][dimension]"]', 'economica');
      await page.fill('input[name="situations[2][escenario]"]', 'Comparado con moto propia por entrega');
      await page.selectOption('select[name="situations[2][resultado]"]', 'aguanta');
      await page.fill('input[name="situations[2][detalle]"]', 'El costo por entrega ya no sube con la lluvia resuelta');

      await page.selectOption('select[name="verdict"]', 'factible');
      await page.fill('textarea[name="reservations"]', 'Confirmar el protocolo con el equipo de logística antes de escalar');
      await page.fill('input[name="summary"]', 'El protocolo de lluvia resolvió la única reserva pendiente.');

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
      // Si el envío falla o el veredicto no aparece, esto tiene que fallar la
      // corrida.
      const veredictoActualizado = (await page.locator('tr', { hasText: idaTesteada })
        .locator('.badge').first().innerText()).trim();
      if (veredictoActualizado !== 'Factible') {
        failures++;
        console.error(`[TESTING] el veredicto del re-testeo enviado por el formulario no quedó guardado (se ve «${veredictoActualizado}»)`);
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

  // ── Las tres que piden otra sesión ──────────────────────────────────────
  //
  // Van últimas de la pasada clara: el recorrido como admin ya terminó, así
  // que cambiar de usuario acá no le saca la sesión a ninguna captura.
  const salir = async () => {
    await page.goto(`${BASE}/challenges`, { waitUntil: 'networkidle' });
    // `require_company` es un before_action GLOBAL (`ApplicationController`) y
    // `SessionsController#destroy` no está en la lista de excepciones: sin
    // empresa elegida, el propio `DELETE /logout` rebota a `/select_company`
    // en vez de cerrar la sesión. Pasa con `multi@demo.test` recién entrado
    // —es el estado que deja `18-select-company`—, así que hay que elegir
    // cualquiera antes de poder salir.
    if (new URL(page.url()).pathname === '/select_company') {
      await page.click('.company-list button, .company-list input[type="submit"]');
      await page.waitForLoadState('networkidle');
    }
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

  // Las cinco `.card-body.empty-state` de la app (A1) no las abre ningún otro
  // paso del recorrido. «Otra Empresa» —la segunda del seed— no tiene ningún
  // desafío ni ningún set, y es la única puerta alcanzable acá: se elige por
  // NOMBRE y no por posición, porque el orden de `@memberships` no está
  // declarado en ningún lado.
  // `choose_company_path` redirige a `root_path`, que sirve `challenges#index`
  // pero deja la URL en `/` —`root "challenges#index"`—: `waitForURL` a
  // `/challenges` nunca dispara. Se espera el título de la pantalla.
  await page.click('.company-list button:has-text("Otra Empresa")');
  await page.waitForSelector('h1.page-title:has-text("Desafíos")');
  await capturar(page, '18b-desafios-vacio');

  // Por link —el nav de arriba—, no `goto`: es el mismo camino que recorrería
  // cualquiera, y `manages_challenges?` lo ofrece porque acá `multi@demo.test`
  // es admin.
  await page.click('.app-nav__link:has-text("Criterios")');
  await page.waitForURL(/\/criteria_sets$/);
  await capturar(page, '18c-criterios-vacio');

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
  }
  await page.emulateMedia({ colorScheme: 'light' });

  await browser.close();

  console.log(`\n${shots.length} capturas en ${OUT}`);
  if (failures) {
    console.error(`\n${failures} errores de página. La maqueta tiene pantallas rotas.`);
    process.exit(1);
  }
  console.log('Sin errores de JS ni respuestas >= 400.');
})().catch((e) => { console.error('FALLO:', e.message); process.exit(1); });
