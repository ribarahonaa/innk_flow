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

async function shot(page, name, url, prepare) {
  await page.goto(BASE + url, { waitUntil: 'networkidle' });
  if (prepare) await prepare(page);
  await page.screenshot({ path: `${OUT}/${name}.png`, fullPage: true });
  await revisarTexto(page, name);
  await revisarFormsAnidados(page, name, url);
  shots.push(name);
}

(async () => {
  // Se limpia antes de empezar: una captura que dejó de tomarse queda en disco
  // como si siguiera siendo el estado actual, y eso es peor que no tenerla.
  for (const file of fs.readdirSync(OUT)) {
    if (file.endsWith('.png')) fs.unlinkSync(`${OUT}/${file}`);
  }

  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });

  page.on('pageerror', (e) => { failures++; console.error(`[JS ERROR] ${e.message}`); });
  page.on('response', (r) => {
    if (r.status() >= 400) { failures++; console.error(`[HTTP ${r.status()}] ${r.url()}`); }
  });

  await shot(page, '01-login', '/login');

  await page.fill('input[name="email"]', 'admin@demo.test');
  await page.fill('input[name="password"]', 'Test1234');
  await page.click('input[type="submit"]');
  await page.waitForLoadState('networkidle');

  await shot(page, '02-challenges', '/challenges');
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

  // El paso a paso tiene que estar en TODAS las pantallas de configuración: si
  // falta en una, ahí es donde se pierde quien está configurando.
  for (const url of ['/challenges/onboarding-remoto',
                     '/challenges/onboarding-remoto/builder',
                     '/challenges/onboarding-remoto/form',
                     '/challenges/onboarding-remoto/criteria',
                     '/challenges/onboarding-remoto/preview']) {
    await page.goto(BASE + url, { waitUntil: 'networkidle' });
    if (await page.locator('.setup__step').count() !== 6) {
      failures++;
      console.error(`[SETUP] falta el paso a paso en ${url}`);
    }
  }
  await shot(page, '03c-paso-a-paso', '/challenges/onboarding-remoto/form');
  await shot(page, '03d-criterios-indice', '/challenges/onboarding-remoto/criteria');
  await shot(page, '04-challenge', `/challenges/${CHALLENGE}`);

  // El builder es una isla Vue, y se llega NAVEGANDO POR EL LINK, no con un
  // goto directo.
  //
  // La diferencia importa: Turbo intercepta los links y reemplaza el body sin
  // disparar DOMContentLoaded. Un goto directo monta la isla igual y esconde
  // el bug; el link es el camino que usa una persona de verdad.
  await page.goto(`${BASE}/challenges/${CHALLENGE}`, { waitUntil: 'networkidle' });
  await page.click('a:has-text("Editar flujo")');
  await page.waitForSelector('[data-island-mounted="true"] .step-card', { timeout: 15000 });
  // Se abre el panel de «Idear»: es el que muestra el formulario, y en el demo
  // ya está ejecutado (bloqueado), que es justo el caso que interesa ver.
  //
  // Se filtra por TIPO y no por nombre: el nombre de un módulo lo cambia
  // cualquiera —una propuesta de la IA lo renombra— y la captura se caía.
  const ideationCard = porTipo(page, 'Idear');
  if (await ideationCard.count()) await ideationCard.click();
  await page.waitForTimeout(200);
  await page.waitForTimeout(300);
  await page.screenshot({ path: `${OUT}/05-builder.png`, fullPage: true });
  shots.push('05-builder');

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

  // El formulario de postulación: se llega desde el panel del módulo «Idear»,
  // que es donde el dueño se entera de que existe.
  const formLink = page.locator('a:has-text("Editar el formulario")');
  if (await formLink.count()) {
    await formLink.first().click();
    await page.waitForSelector('[data-island-mounted="true"] .field-edit', { timeout: 15000 });
    await page.screenshot({ path: `${OUT}/05b-form.png`, fullPage: true });
    shots.push('05b-form');

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
    console.error('[LINK] el panel de «Idear» no ofrece editar el formulario');
  }

  // La previsualización: se llega por link desde el builder.
  await page.goto(`${BASE}/challenges/onboarding-remoto/builder`, { waitUntil: 'networkidle' });
  const previewLink = page.locator('a:has-text("Previsualizar")');
  if (await previewLink.count()) {
    await Promise.all([
      page.waitForURL('**/preview', { timeout: 15000 }),
      previewLink.first().click()
    ]);
    await page.waitForSelector('.preview-surface, .empty-state', { timeout: 10000 });
    await page.screenshot({ path: `${OUT}/05c-preview-borrador.png`, fullPage: true });
    shots.push('05c-preview-borrador');
  } else {
    failures++;
    console.error('[LINK] el builder no ofrece previsualizar');
  }

  // El mismo preview sobre el desafío en curso, con su formulario y su set de
  // criterios de verdad.
  await shot(page, '05d-preview-configurado', `/challenges/${CHALLENGE}/preview`);

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
  await page.screenshot({ path: `${OUT}/07-idea.png`, fullPage: true });
  shots.push('07-idea');

  const diffLink = page.locator('a:has-text("Ver cambios entre versiones")');
  if (await diffLink.count()) {
    await diffLink.click();
    await page.waitForURL('**/diff**', { timeout: 10000 });
    await page.screenshot({ path: `${OUT}/08-diff.png`, fullPage: true });
    shots.push('08-diff');
  } else {
    failures++;
    console.error('[LINK] la idea con v2 no ofrece ver el diff');
  }

  // Una pantalla por tipo de módulo, tomando el primero de cada kind.
  await page.goto(`${BASE}/challenges/${CHALLENGE}`, { waitUntil: 'networkidle' });
  const stepLinks = await page.locator('.step-table__link').evaluateAll(
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
    await shot(page, `09-${index + 1}-step-${link.text.toLowerCase().replace(/[^a-z0-9]+/g, '-')}`, link.href);
  }

  // Quién evalúa y cuánto pesa su voto. La tabla y la columna existían desde
  // el principio sin ninguna pantalla que las tocara.
  const comite = stepLinks.find((l) => l.text.match(/comit/i));
  if (comite) {
    await page.goto(BASE + comite.href, { waitUntil: 'networkidle' });
    const filas = await page.locator('.assignment-row').count();
    const conPesos = await page.locator('.status-chip--active', { hasText: 'con pesos' }).count();

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

  // El desafío en borrador: «Idear» todavía no tiene formulario. El builder lo
  // marca como error y la pantalla ofrece las dos salidas.
  await page.goto(`${BASE}/challenges/onboarding-remoto/builder`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-island-mounted="true"] .step-card', { timeout: 15000 });
  await porTipo(page, 'Idear').click();
  await page.waitForTimeout(200);
  await page.screenshot({ path: `${OUT}/09-9-builder-sin-formulario.png`, fullPage: true });
  shots.push('09-9-builder-sin-formulario');

  await shot(page, '09-10-form-vacio', '/challenges/onboarding-remoto/form');

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

  // Los criterios del módulo de evaluación, desde su panel en el builder.
  await page.goto(`${BASE}/challenges/onboarding-remoto/builder`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-island-mounted="true"] .step-card', { timeout: 15000 });
  await porTipo(page, 'Evaluación').click();
  await page.waitForTimeout(200);
  await page.screenshot({ path: `${OUT}/09-11-panel-evaluacion.png`, fullPage: true });
  shots.push('09-11-panel-evaluacion');

  // Por DESTINO y no por texto: la etiqueta cambia según el módulo ya tenga
  // criterios propios o no, y la captura se caía cuando alguien los definía.
  const criteriaLink = page.locator('.config-form a[href*="/criteria"]');
  if (await criteriaLink.count()) {
    await criteriaLink.first().click();
    await page.waitForLoadState('networkidle');
    await page.screenshot({ path: `${OUT}/09-12-criterios-del-modulo.png`, fullPage: true });
    shots.push('09-12-criterios-del-modulo');
  } else {
    failures++;
    console.error('[LINK] el panel de evaluación no ofrece definir criterios propios');
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
    await page.screenshot({ path: `${OUT}/10b-criteria-editor.png`, fullPage: true });
    shots.push('10b-criteria-editor');

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
    const aviso = await page.locator('.flash--warn').first().textContent().catch(() => '');
    if (!/Al guardar se crea la v\d/.test(aviso || '')) {
      failures++;
      console.error('[VERSIONADO] el editor no avisa que guardar crea una versión nueva:', aviso);
    }
  } else {
    failures++;
    console.error('[LINK] la biblioteca de criterios no ofrece editar un set');
  }
  await shot(page, '11-ai-runs', '/admin/ai_runs');

  await browser.close();

  console.log(`\n${shots.length} capturas en ${OUT}`);
  if (failures) {
    console.error(`\n${failures} errores de página. La maqueta tiene pantallas rotas.`);
    process.exit(1);
  }
  console.log('Sin errores de JS ni respuestas >= 400.');
})().catch((e) => { console.error('FALLO:', e.message); process.exit(1); });
