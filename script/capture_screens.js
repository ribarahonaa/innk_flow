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

const BASE = process.env.BASE_URL || 'http://localhost:3001';
const OUT = process.env.OUT_DIR || '/shots';
const CHALLENGE = 'merma-bodega';

const shots = [];
let failures = 0;

async function shot(page, name, url, prepare) {
  await page.goto(BASE + url, { waitUntil: 'networkidle' });
  if (prepare) await prepare(page);
  await page.screenshot({ path: `${OUT}/${name}.png`, fullPage: true });
  shots.push(name);
}

(async () => {
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
  const ideationCard = page.locator('.step-card', { hasText: 'Postulación' }).first();
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

  await shot(page, '06-ideas', `/challenges/${CHALLENGE}/ideas`);

  // La idea con más versiones, y su diff.
  await page.goto(`${BASE}/challenges/${CHALLENGE}/ideas`, { waitUntil: 'networkidle' });
  const idea = page.locator('.idea-list__link').first();
  await idea.click();
  await page.waitForLoadState('networkidle');
  await page.screenshot({ path: `${OUT}/07-idea.png`, fullPage: true });
  shots.push('07-idea');

  const diffLink = page.locator('a:has-text("Ver cambios entre versiones")');
  if (await diffLink.count()) {
    await diffLink.click();
    await page.waitForURL('**/diff**', { timeout: 10000 });
    await page.screenshot({ path: `${OUT}/08-diff.png`, fullPage: true });
    shots.push('08-diff');
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
  await page.locator('.step-card', { hasText: 'Postulación' }).first().click();
  await page.waitForTimeout(200);
  await page.screenshot({ path: `${OUT}/09-9-builder-sin-formulario.png`, fullPage: true });
  shots.push('09-9-builder-sin-formulario');

  await shot(page, '09-10-form-vacio', '/challenges/onboarding-remoto/form');

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
