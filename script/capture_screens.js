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

async function shot(page, name, url, prepare) {
  await page.goto(BASE + url, { waitUntil: 'networkidle' });
  if (prepare) await prepare(page);
  await page.screenshot({ path: `${OUT}/${name}.png`, fullPage: true });
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
                     '/challenges/onboarding-remoto/preview']) {
    await page.goto(BASE + url, { waitUntil: 'networkidle' });
    if (await page.locator('.setup__step').count() !== 6) {
      failures++;
      console.error(`[SETUP] falta el paso a paso en ${url}`);
    }
  }
  await shot(page, '03c-paso-a-paso', '/challenges/onboarding-remoto/form');
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

  for (const [index, link] of stepLinks.entries()) {
    await shot(page, `09-${index + 1}-step-${link.text.toLowerCase().replace(/[^a-z0-9]+/g, '-')}`, link.href);
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
