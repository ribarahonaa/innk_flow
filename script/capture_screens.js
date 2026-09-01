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
  await page.waitForSelector('.builder .step-card', { timeout: 10000 });
  const cards = page.locator('.step-card:not(.step-card--locked)');
  if (await cards.count()) await cards.first().click();
  await page.waitForTimeout(300);
  await page.screenshot({ path: `${OUT}/05-builder.png`, fullPage: true });
  shots.push('05-builder');

  // Una isla que no montó deja el placeholder: es un fallo, no una captura.
  if (await page.locator('.island-placeholder').count()) {
    failures++;
    console.error('[ISLA] el builder no montó: quedó "Cargando el editor de flujo…"');
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

  await shot(page, '10-criteria', '/criteria_sets');
  await shot(page, '11-ai-runs', '/admin/ai_runs');

  await browser.close();

  console.log(`\n${shots.length} capturas en ${OUT}`);
  if (failures) {
    console.error(`\n${failures} errores de página. La maqueta tiene pantallas rotas.`);
    process.exit(1);
  }
  console.log('Sin errores de JS ni respuestas >= 400.');
})().catch((e) => { console.error('FALLO:', e.message); process.exit(1); });
