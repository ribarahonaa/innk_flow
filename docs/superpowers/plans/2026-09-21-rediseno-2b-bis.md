# Rediseño 2b-bis — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrar las 41 apariciones de `.panel` en 23 vistas HAML y las 4 de las dos islas Vue a `card` + `card-body`, borrar la vista muerta que quedaba, y borrar `.panel` y la guarda `[CARD]`.

**Corrección sobre el spec:** el spec contaba 42 usos en 24 vistas e incluía `app/views/pages/home.html.haml`, suponiéndola alcanzable en `/`. No lo es: `config/routes.rb:113` es `root "challenges#index"` y **nada rutea a `PagesController#home`**. Se borra en la Tarea 2b en vez de migrarse. Lo destapó la captura `13-home` de la Tarea 1, que resultó ser un duplicado byte a byte de `02-challenges`.

**Architecture:** La plomería ya existe: el 2b dejó en `application.css` una regla `.card` con el aspecto exacto de `.panel` (`--card-p: 20px`, `--card-fs: 14px`). Cada vista pasa a escribir `.card` > `.card-body` y nada más. Lo único que se ajusta es el espaciado que el `gap` de `card-body` mueve, porque en flex los márgenes no colapsan. Las ocho pantallas que hoy no tiene ninguna captura se fotografían PRIMERO, con `.panel` todavía puesto.

**Tech Stack:** Rails 8 · HAML · Tailwind 4 + DaisyUI 5 (config por CSS) · Vue 3 en islas · Playwright (`make screens`) · RSpec (`make spec`). Todo corre en Docker; nunca `bundle exec` en el host.

**Spec:** `docs/superpowers/specs/2026-09-21-rediseno-2b-bis-resto-de-la-app-design.md`

## Global Constraints

- **El código, los comentarios y los mensajes de commit van en español.**
- Todo corre en Docker: `make spec`, `make spec-file FILE=…`, `make screens`, `make yarn-build`. Nunca `bundle exec` en el host.
- **`make yarn-build` antes de `make screens`** siempre que se toque CSS o JS: el contenedor `app` no recompila solo.
- Cada tarea termina con `make spec` y `make screens` en verde y **un commit**.
- **Ningún cambio de permiso, dominio, motor ni IA.** Si algo parece necesitarlo, es un hallazgo: se anota, se consulta, y va en commit propio fuera de este plan.
- **Ninguna clase interpolada.** `spec/lint/clases_interpoladas_spec.rb` mira HAML, `.vue` y `.js`.
- **Nunca `goto` a un desafío que también se usa a mano.** Para el recorrido existen `sin-formulario` y `con-salteado`; `merma-bodega` es el del seed.
- Commits terminan con:
  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  ```

---

## La tabla de formas

**Esta tabla es el corazón del plan.** Las tareas 2 a 7 la aplican; no hay otra decisión que tomar por línea.

El criterio único: **lo que es de la caja externa —ancho, margen, borde, fondo— queda en `.card`; lo que es relleno o alineación del contenido va en `.card-body`.** El relleno de `.panel` vivía en el mismo elemento; en una `card` vive en el `card-body`, y un modificador que pone su propio relleno tiene que mudarse con él o los dos se suman.

| Forma hoy | Forma nueva | Por qué |
|---|---|---|
| `.panel` | `.card` > `.card-body` | El caso base |
| `.panel.empty-state` | `.card` > `.card-body.empty-state` | `.empty-state` pone `padding: 44px 20px`. En `.card` se sumaría a los 20px de `card-body`; en `card-body` lo pisa, que es lo que hacía con `.panel` |
| `.panel.island-placeholder` | `.card` > `.card-body.island-placeholder` | Ídem, con `padding: 40px` |
| `.panel.narrow` | `.card.narrow` > `.card-body` | `.narrow` es `max-width` y márgenes: caja externa |
| `.panel.ai-guide-banner` | `.card.ai-guide-banner` > `.card-body` | Borde y fondo: caja externa. Gana por orden en la hoja (línea 1762, después de `.card`) |
| `.panel.assessment-detail--ai` | `.card.assessment-detail--ai` > `.card-body` | Ídem (línea 1748) |
| `.panel.setup` | `.card.setup` > `.card-body` | Sólo `margin-bottom`: caja externa |

**Al mover contenido un nivel adentro, todo lo que estaba indentado bajo el `.panel` baja un nivel.** HAML es sensible a la indentación; un nivel de más o de menos cambia qué es hijo de qué.

---

## File Structure

**Se modifican:**

| Archivo | Qué cambia | Tarea |
|---|---|---|
| `script/capture_screens.js` | 8 capturas nuevas + escape de estado esperado | 1 |
| `script/capture_screens.js` | `[CARD]` borrada; `[RITMO]`, muestrario y mensaje de `[PANEL]` limpiados | 8 |
| Las 24 vistas HAML | `.panel` → `card` + `card-body` | 2-6 |
| `app/javascript/components/pipeline_builder/pipeline_builder.vue` | 2 usos | 7 |
| `app/javascript/components/criteria_editor/criteria_editor.vue` | 2 usos | 7 |
| `app/assets/stylesheets/application.css` | ajustes de espaciado (2-7); borrado de `.panel` y sus 3 selectores compuestos (8) | 2-8 |
| `CLAUDE.md` | tres pasajes sobre `.panel` y `[CARD]` | 8 |
| `docs/superpowers/specs/2026-09-17-rediseno-2b-pantallas-de-modulo-design.md` | la línea que deja las islas para el 2c | 8 |

**No se crea ningún archivo.** No hay request specs nuevos: esto no cambia qué se sirve ni quién lo ve, y un request spec no mira CSS.

---

## Task 1: Las ocho capturas que faltan

Ninguna guarda mira hoy `ai_runs/show`, `criteria_sets/show`, `errors/forbidden`, `errors/not_found`, `ideas/edit`, `ideas/new`, `pages/home` ni `sessions/select_company`. Sin esto, un tercio de la migración va a ciegas.

> **Resultado, anotado al ejecutar:** siete de las ocho se fotografiaron. La octava no se puede: `/` sirve `challenges#index` y **nada rutea a `pages/home`**. La captura `13-home` salió duplicada byte a byte de `02-challenges`, y se saca. Esa vista se borra en la Tarea 2b. El recorrido queda en **59** capturas, no 60.

**Files:**
- Modify: `script/capture_screens.js`

**Interfaces:**
- Consumes: nada.
- Produces: ocho nombres de captura nuevos (`13-home`, `14-ai-run`, `15-criteria-set`, `16-idea-new`, `17-idea-edit`, `18-select-company`, `19-forbidden`, `20-not-found`) y el helper `shotConEstado(page, name, url, status)`, que las tareas siguientes no usan pero el cierre sí menciona.

- [ ] **Step 1: Leer cómo arranca y termina la pasada clara**

Leer `script/capture_screens.js` entero antes de tocarlo. Importa especialmente:
- el `page.on('response')` que hace fallar cualquier estado `>= 400`;
- el login (`admin@demo.test` / `Test1234`, con `input[type="submit"]`);
- dónde termina la pasada clara: justo antes del comentario `── Tema oscuro ──`.

- [ ] **Step 2: Sumar el escape de estado esperado**

El recorrido tiene que poder fotografiar un 403 y un 404 **sin** aflojar la regla para todo lo demás: una variable que declara el estado esperado, y un helper que la usa.

**Ojo con los ámbitos.** El `page.on('response')` vive DENTRO del IIFE async, pero `shot()` y las demás guardas están en ámbito de módulo. La variable y el helper van **en ámbito de módulo, junto a `failures` y a `shot`**; sólo el reemplazo del handler va adentro del IIFE. Puestos los tres juntos adentro, `shotConEstado` no lo ve nadie.

En ámbito de módulo, junto a `shot`:

```js
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
```

Y adentro del IIFE, reemplazando el handler que ya está ahí:

```js
  page.on('response', (r) => {
    if (r.status() < 400) return;
    // Sólo el documento principal de la navegación declarada. Un asset o un
    // fetch que devuelva 403 sigue siendo una falla.
    if (estadoEsperado && r.status() === estadoEsperado && r.request().isNavigationRequest()) return;
    failures++;
    console.error(`[HTTP ${r.status()}] ${r.url()}`);
  });
```

Nota: `shotConEstado` no llama a `revisarFormsAnidados`, que pide el HTML por `page.request.get` — eso no es una navegación, así que volvería a disparar el handler con el estado de error.

- [ ] **Step 3: Sumar las cinco capturas que van como admin**

Al final de la pasada clara, antes de `── Tema oscuro ──`. Por link donde haya link: Turbo no dispara `DOMContentLoaded` al navegar por link, y un `goto` esconde ese bug.

```js
  // ── Las pantallas que nadie fotografiaba ────────────────────────────────
  //
  // Ocho vistas usan `.panel` y ninguna guarda las miraba: `[CARD]`,
  // `[PANEL]`, `[RITMO]`, `[CONTRASTE]` y `[CLASES]` sólo ven lo que el
  // recorrido abre. Van ANTES de migrarlas, en verde con `.panel` puesto:
  // así se prueba que la captura funciona, no que la migración funcionó.
  await shot(page, '13-home', '/');

  // La ficha de una corrida de IA, que no es el índice.
  await page.goto(`${BASE}/admin/ai_runs`, { waitUntil: 'networkidle' });
  const aRun = page.locator('.table-link').first();
  if (!(await aRun.count())) {
    failures++;
    console.error('[LINK] el índice de corridas de IA no ofrece ninguna ficha');
  } else {
    await aRun.click();
    await page.waitForURL(/\/ai_runs\//);
    await capturar(page, '14-ai-run');
  }

  // La ficha de un set de criterios: el NOMBRE, no «Editar» —eso ya es
  // `10b-criteria-editor`, que es la pantalla de edición—.
  await page.goto(`${BASE}/criteria_sets`, { waitUntil: 'networkidle' });
  const aSet = page.locator('.table-link').first();
  if (!(await aSet.count())) {
    failures++;
    console.error('[LINK] el índice de criterios no ofrece ninguna ficha');
  } else {
    await aSet.click();
    await page.waitForURL(/\/criteria_sets\//);
    await capturar(page, '15-criteria-set');
  }

  // Postular y editar una idea. `sin-formulario` es del recorrido y nadie lo
  // toca a mano, que es la regla para cualquier captura nueva.
  await page.goto(`${BASE}/challenges/${CHALLENGE}/ideas`, { waitUntil: 'networkidle' });
  const aNueva = page.locator('a:has-text("Postular una idea")').first();
  if (!(await aNueva.count())) {
    failures++;
    console.error('[LINK] la lista de ideas no ofrece postular una');
  } else {
    await aNueva.click();
    await page.waitForURL(/\/ideas\/new/);
    await capturar(page, '16-idea-new');
  }

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
```

Antes de correr: confirmar con `make psql` que `CHALLENGE` (el slug que usa el recorrido) tiene ideas y que al menos una es editable por admin. Si la lista sale vacía, las dos guardas `[LINK]` lo van a decir.

- [ ] **Step 4: Sumar las tres que piden otra sesión**

Van después de las cinco de arriba, todavía en la pasada clara. Cambian de usuario, así que cierran sesión primero.

```js
  // ── Las tres que piden otra sesión ──────────────────────────────────────
  //
  // Van últimas de la pasada clara: el recorrido como admin ya terminó, así
  // que cambiar de usuario acá no le saca la sesión a ninguna captura.
  const salir = async () => {
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
```

- [ ] **Step 5: Verificar la sintaxis**

Run: `node --check script/capture_screens.js`
Expected: sin salida.

- [ ] **Step 6: Correr el recorrido y verlo verde con `.panel` todavía puesto**

Run: `make yarn-build && make screens`
Expected: `60 capturas en /shots` y `Sin errores de JS ni respuestas >= 400.`

Si alguna `[LINK]` falla, el seed no tiene el dato que esa captura necesita: arreglar el localizador o el seed, **no** sacar la guarda.

- [ ] **Step 7: Ver fallar el escape de estado**

Una guarda de estado que acepta cualquier cosa no sirve. Cambiar a mano `403` por `404` en la llamada de `19-forbidden`, correr, y confirmar:

Run: `make screens`
Expected: `[ESTADO] 19-forbidden: se esperaba 404 y respondió 403` **y** un `[HTTP 403]`.

Devolver el `403` y volver a correr hasta verde.

- [ ] **Step 8: Mirar las ocho capturas nuevas**

Están en `tmp/screenshots/`. Confirmar que cada una muestra la pantalla que dice y no un login ni un error inesperado. Es la única verificación que no hace una máquina.

- [ ] **Step 9: Commit**

```bash
git add script/capture_screens.js
git commit -m "Las ocho pantallas que ninguna guarda miraba ya tienen captura

Ocho de las 24 vistas que usan \`.panel\` no estaban en ninguna captura, así
que \`[CARD]\`, \`[PANEL]\`, \`[RITMO]\`, \`[CONTRASTE]\` y \`[CLASES]\` no las
miraban. Van antes de migrarlas y en verde con \`.panel\` todavía puesto: lo
que esto prueba es que la captura funciona, no que la migración funcionó.

Las dos pantallas de error necesitan declarar el estado que esperan. El
recorrido falla con cualquier respuesta >= 400, y aflojarlo a \`>= 400 se
ignora\` lo volvería ciego entero: \`shotConEstado\` acepta UN estado, para UNA
navegación, y falla si llega otro —incluido un 200—. Visto fallar.

El 403 es el legítimo: quien participa ve el desafío pero no lo arma.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Sistema

Seis pantallas chicas, de una tarjeta cada una. Van primero porque es donde el ajuste de espaciado se calibra barato, antes de aplicarlo a una familia entera.

**Files:**
- Modify: `app/views/errors/forbidden.html.haml:1`
- Modify: `app/views/errors/not_found.html.haml:1`
- Modify: `app/views/sessions/select_company.html.haml:1`
- Modify: `app/views/notifications/index.html.haml:10` (`.panel.empty-state`)
- Modify: `app/views/shared/_setup_outline.html.haml:4` (`.panel.setup`)
- Modify: `app/assets/stylesheets/application.css` (sólo si hace falta ajustar espaciado)

**Interfaces:**
- Consumes: la tabla de formas.
- Produces: los ajustes `.card-body > X` que las tareas 3-7 reusan, si aparece alguno.

- [ ] **Step 1: Leer las seis vistas enteras**

No sólo la línea del `.panel`: hay que ver qué queda adentro, porque todo eso baja un nivel de indentación.

- [ ] **Step 2: Aplicar la tabla de formas**

Tres son el caso base. Ejemplo, `app/views/errors/not_found.html.haml`:

```haml
-# Antes
.panel
  %h1.page-title Hola

-# Después
.card
  .card-body
    %h1.page-title Hola
```

`notifications/index.html.haml:10` es `.panel.empty-state` → `.card` > `.card-body.empty-state`.
`shared/_setup_outline.html.haml:4` es `.panel.setup` → `.card.setup` > `.card-body`.

- [ ] **Step 3: Confirmar que no quedó ningún `.panel` en las seis**

Run:
```bash
grep -n "\.panel" app/views/errors/*.haml \
  app/views/sessions/select_company.html.haml \
  app/views/notifications/index.html.haml app/views/shared/_setup_outline.html.haml
```
Expected: sin salida.

- [ ] **Step 4: Correr el recorrido**

Run: `make screens`
Expected: 59 capturas, sin errores. En particular sin `[PANEL]` (una `card` sin `card-body`) ni `[RITMO]`.

- [ ] **Step 5: Comparar las seis capturas contra las de antes**

`18-select-company`, `19-forbidden`, `20-not-found`, `09-13-avisos`, `03c-paso-a-paso`. Lo que hay que mirar es el ESPACIADO: el `gap` de 8px de `card-body` se suma a los márgenes de títulos y párrafos, que en `.panel` colapsaban. Si algo quedó más suelto, descontarle al margen lo que el gap ya pone, con una regla en la hoja:

```css
/* `card-body` es flex en columna con `gap: 8px`, y en flex los márgenes NO
   colapsan. A cada margen se le descuenta el gap; `card-body` no se toca. */
.card-body > .page-title { margin-bottom: 0; }
```

Si se toca la hoja: `make yarn-build` antes de volver a correr.

- [ ] **Step 6: Correr la suite**

Run: `make spec`
Expected: 919 examples, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add app/views app/assets/stylesheets/application.css
git commit -m "Las seis pantallas de sistema pasan a card

Errores, elegir empresa, avisos y el paso a paso. Cinco pantallas de una
tarjeta: es donde el ajuste de espaciado se calibra barato, antes de aplicarlo
a una familia entera.

home quedó afuera: no es alcanzable y se borra en su propio commit.

card-body es flex en columna con gap, y en flex los márgenes NO colapsan, así
que el cambio de clase mueve el espaciado por su cuenta.
[Describir acá qué se ajustó y por qué, o decir que no hizo falta.]

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 2b: Borrar `pages/home`, que nadie puede abrir

`app/views/pages/home.html.haml` tiene un `.panel`, así que mientras exista
`.panel` no se puede borrar. Pero **no es alcanzable**: `config/routes.rb:113`
es `root "challenges#index"` y no hay ninguna ruta a `PagesController#home`.
El comentario del propio controller lo dice: «Placeholder. En Fase 2 la raíz
pasa a ser el índice de desafíos» — fase que ya ocurrió. La vista todavía
anuncia «Fase 1 — tenencia, sesión y semillas».

Decisión de Raúl: se borra. Migrar a ciegas una pantalla que nadie puede ver
es lo contrario de lo que la Tarea 1 vino a garantizar.

**Files:**
- Delete: `app/views/pages/home.html.haml`
- Delete: `app/controllers/pages_controller.rb`
- Modify: `app/controllers/application_controller.rb:29`

**Interfaces:**
- Consumes: nada.
- Produces: una vista menos en el alcance (41 usos, no 42).

- [ ] **Step 1: Confirmar que sigue sin ser alcanzable**

Run: `grep -rn "pages#\|PagesController\|pages/home" config/ app/ spec/`
Expected: **sólo** `app/controllers/pages_controller.rb` y la línea 29 de
`application_controller.rb`. Ninguna ruta, ningún render, ningún spec.

Si aparece cualquier otra cosa, **pará**: la vista no está muerta y esta tarea
no corresponde.

- [ ] **Step 2: Sacar `PagesController` de `skip_pundit?`**

`application_controller.rb:29` dice hoy:

```ruby
  # Sesión y páginas sin recurso no tienen qué autorizar.
  def skip_pundit?
    is_a?(SessionsController) || is_a?(PagesController)
  end
```

Borrar el controller sin tocar esto revienta la app con `NameError` en el
primer request. Queda:

```ruby
  # La sesión no tiene qué autorizar: todavía no hay membresía con la cual.
  def skip_pundit?
    is_a?(SessionsController)
  end
```

El comentario cambia con la línea: ya no hay «páginas sin recurso».

- [ ] **Step 3: Borrar los dos archivos**

```bash
git rm app/views/pages/home.html.haml app/controllers/pages_controller.rb
```

- [ ] **Step 4: Correr la suite**

Run: `make spec`
Expected: 919 examples, 0 failures.

`spec/requests/authentication_spec.rb` usa `root_path`, que es
`challenges#index` y no cambia. Si algún ejemplo se cae, es que algo sí
llegaba a `PagesController` y el Step 1 no lo vio: **pará y reportalo**.

- [ ] **Step 5: Correr el recorrido**

Run: `make screens`
Expected: 59 capturas, sin errores. **Son 59 y no 60**: la Tarea 1 saca su
captura `13-home` en el mismo ciclo de arreglos, porque fotografiaba
`challenges#index` y era un duplicado byte a byte de `02-challenges`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Se borra la pantalla que nadie podía abrir

app/views/pages/home.html.haml tenía un .panel, y mientras existiera .panel no
se podía borrar. Pero no es alcanzable: routes.rb:113 es root
challenges#index y nada rutea a PagesController#home. El comentario del propio
controller dice que es un placeholder para cuando la raíz pase a ser el índice
de desafíos — ya pasó. La vista seguía anunciando «Fase 1».

Lo destapó la captura que la tarea 1 le sumó: 13-home.png y 02-challenges.png
tenían el MISMO md5. La guarda nueva estaba fotografiando otra pantalla.

PagesController sale también de skip_pundit?, que lo nombraba: borrarlo sin
eso revienta con NameError en el primer request.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Ideas

Once usos en seis vistas. `ideas/show` es la más cargada de la familia (4).

**Files:**
- Modify: `app/views/ideas/index.html.haml:17,22`
- Modify: `app/views/ideas/show.html.haml:38,66,81,133`
- Modify: `app/views/ideas/new.html.haml:2` (`.panel.narrow`)
- Modify: `app/views/ideas/edit.html.haml:2` (`.panel.narrow`)
- Modify: `app/views/ideas/diff.html.haml:8,18`
- Modify: `app/views/ideas/_contributors.html.haml:2`
- Modify: `app/assets/stylesheets/application.css` (espaciado, si hace falta)

**Interfaces:**
- Consumes: la tabla de formas y los ajustes `.card-body > X` de la tarea 2.
- Produces: nada que las siguientes necesiten.

- [ ] **Step 1: Leer las seis vistas enteras**

- [ ] **Step 2: Aplicar la tabla de formas**

Nueve son el caso base. Las dos `.panel.narrow` (`new` y `edit`) van a `.card.narrow` > `.card-body`: `.narrow` es `max-width: 560px` y márgenes automáticos, o sea caja externa.

- [ ] **Step 3: Confirmar que no quedó ninguno**

Run: `grep -rn "\.panel" app/views/ideas/`
Expected: sin salida.

- [ ] **Step 4: Correr el recorrido**

Run: `make screens`
Expected: 59 capturas, sin errores.

- [ ] **Step 5: Comparar las capturas**

`06-ideas`, `07-idea`, `08-diff`, `16-idea-new`, `17-idea-edit`. Ojo especialmente con **`07-idea`**: la ficha de la idea pliega las rondas cerradas con `<details>`, y `revisarPlegableTrasMorph` ya la vigila. Y con **`06-ideas`**, que lista tarjetas hermanas: el `p { flex-grow: 1 }` de DaisyUI estira párrafos dentro de tarjetas de alto fijo, y en una grilla de filas parejas se nota. Si aparece, se resuelve con una regla en la hoja, no con utilidades por vista.

- [ ] **Step 6: Correr la suite**

Run: `make spec`
Expected: 919 examples, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add app/views/ideas app/assets/stylesheets/application.css
git commit -m "La familia de ideas pasa a \`card\`

Lista, ficha, alta, edición, diff y colaboradores: once tarjetas. Las dos
\`.panel.narrow\` quedan como \`.card.narrow\`, porque \`.narrow\` es ancho y
márgenes, o sea caja externa.

[Describir el ajuste de espaciado, o decir que no hizo falta.]

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Desafíos

Nueve usos en cinco vistas. Dos son `.panel.island-placeholder` y `.panel.empty-state`, que cambian de nivel.

**Files:**
- Modify: `app/views/challenges/index.html.haml:10` (`.panel.empty-state`)
- Modify: `app/views/challenges/show.html.haml:26,32`
- Modify: `app/views/challenges/new.html.haml:8`
- Modify: `app/views/challenges/builder.html.haml:16,32,47` (la 47 es `.panel.island-placeholder`)
- Modify: `app/views/previews/show.html.haml:22` (`.panel.empty-state`), `:27`
- Modify: `app/assets/stylesheets/application.css` (espaciado, si hace falta)

**Interfaces:**
- Consumes: la tabla de formas.
- Produces: nada.

- [ ] **Step 1: Leer las cinco vistas enteras**

- [ ] **Step 2: Aplicar la tabla de formas**

Seis son el caso base. Las dos `.panel.empty-state` van a `.card` > `.card-body.empty-state`; la `.panel.island-placeholder` de `builder` va a `.card` > `.card-body.island-placeholder`.

**El placeholder de la isla tiene una trampa propia:** lo reemplaza Vue al montar, y `make screens` falla si queda un `.island-placeholder` sin montar. Después de este cambio, confirmar en `05-builder` que la isla montó (`data-island-mounted="true"`).

- [ ] **Step 3: Confirmar que no quedó ninguno**

Run: `grep -rn "\.panel" app/views/challenges/ app/views/previews/`
Expected: sin salida.

- [ ] **Step 4: Correr el recorrido**

Run: `make screens`
Expected: 59 capturas, sin errores, sin `[ISLA]`.

- [ ] **Step 5: Comparar las capturas**

`02-challenges`, `04-challenge`, `03-new-challenge`, `05-builder`, `03b-builder-plantillas`, `09-9-builder-sin-formulario`, `05c-preview-borrador`, `05d-preview-configurado`, `02b-salteado`, y las oscuras `90-oscuro-desafios` y `91-oscuro-desafio`.

**`02-challenges` es la de mayor riesgo:** `.challenge-grid` es una grilla de tarjetas hermanas con `minmax(330px, 1fr)`, o sea filas de alto parejo. Es donde el `p { flex-grow: 1 }` se ve.

- [ ] **Step 6: Correr la suite**

Run: `make spec`
Expected: 919 examples, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add app/views/challenges app/views/previews app/assets/stylesheets/application.css
git commit -m "La familia de desafíos pasa a \`card\`

Índice, ficha, alta, builder y vista previa. Las dos \`.panel.empty-state\` y
el \`.panel.island-placeholder\` bajan su modificador al \`card-body\`: los dos
ponen su propio relleno, que en la \`card\` vive ahí.

[Describir el ajuste de espaciado, o decir que no hizo falta.]

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Criterios, IA y miembros

Once usos en seis vistas.

**Files:**
- Modify: `app/views/criteria_sets/index.html.haml:9` (`.panel.empty-state`), `:16`
- Modify: `app/views/criteria_sets/show.html.haml:7` (el `.panel`) **y `:20`** (un bug preexistente, ver Step 2b)
- Modify: `app/views/criteria_sets/_form.html.haml:5` (`.panel.island-placeholder`)
- Modify: `app/views/ai_runs/index.html.haml:21`
- Modify: `app/views/ai_runs/show.html.haml:13,17,22`
- Modify: `app/views/memberships/index.html.haml:7,18,37`
- Modify: `app/assets/stylesheets/application.css` (espaciado, si hace falta)

**Interfaces:**
- Consumes: la tabla de formas.
- Produces: nada.

- [ ] **Step 1: Leer las seis vistas enteras**

- [ ] **Step 2: Aplicar la tabla de formas**

Nueve son el caso base. `criteria_sets/index.html.haml:9` es `.panel.empty-state` → `.card` > `.card-body.empty-state`. `criteria_sets/_form.html.haml:5` es `.panel.island-placeholder` → `.card` > `.card-body.island-placeholder`.

- [ ] **Step 2b: Arreglar el `%td:` de `criteria_sets/show.html.haml:20`**

Bug preexistente, destapado al fotografiar esa pantalla en la tarea 1.
Decisión de Raúl: se arregla acá, que es cuando le toca a esta vista.

La línea 20 dice:

```haml
          %td: %code= criterion.key
```

`%td: %code=` es sintaxis de **Slim**, no de HAML. HAML no la lee como
anidamiento: toma `td:` como nombre de etiqueta y el resto como texto. Medido
compilando el fragmento, no deducido:

```
%td: %code= 1+1   →   <td:>%code= 1+1</td:>
```

Etiqueta inválida, el Ruby nunca se evalúa, y la columna «Clave» muestra el
texto literal `%code= criterion.key` en vez del valor. Va anidado de verdad:

```haml
          %td
            %code= criterion.key
```

Verificar en el HTML servido que la columna «Clave» trae ahora la clave de cada
criterio, y mirarlo en la captura `15-criteria-set`.

**Nada más de esa vista.** Que `criteria_sets#show` sea una pantalla huérfana
—nada en la app la linkea— es un hallazgo aparte y sin decidir: no se linkea ni
se borra en esta tarea.

- [ ] **Step 3: Confirmar que no quedó ninguno**

Run: `grep -rn "\.panel" app/views/criteria_sets/ app/views/ai_runs/ app/views/memberships/`
Expected: sin salida.

- [ ] **Step 4: Correr el recorrido**

Run: `make screens`
Expected: 59 capturas, sin errores, sin `[ISLA]` (el editor de criterios monta sobre el placeholder de `_form`).

- [ ] **Step 5: Comparar las capturas**

`10-criteria`, `10b-criteria-editor`, `15-criteria-set`, `11-ai-runs`, `14-ai-run`, `12-miembros`, y las oscuras `92-oscuro-criterios` y `93-oscuro-ia`.

`ai_runs/show` y `memberships/index` tienen tres tarjetas cada una: es donde el ritmo entre tarjetas hermanas se nota. `[RITMO]` lo mide, pero sólo sobre hijas directas de `.app-main`.

- [ ] **Step 6: Correr la suite**

Run: `make spec`
Expected: 919 examples, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add app/views/criteria_sets app/views/ai_runs app/views/memberships app/assets/stylesheets/application.css
git commit -m "Criterios, corridas de IA y miembros pasan a \`card\`

Once tarjetas en seis pantallas. \`ai_runs/show\` y \`memberships/index\` tienen
tres cada una: es donde el ritmo entre tarjetas hermanas se nota.

Y de paso el \`%td: %code=\` de criteria_sets/show, que es sintaxis de Slim y
no de HAML: HAML tomaba \`td:\` como nombre de etiqueta y el resto como texto,
así que la columna Clave mostraba el literal. Lo destapó la captura que la
tarea 1 le sumó a esa pantalla, que hasta ahora no tenía ninguna.

[Describir el ajuste de espaciado, o decir que no hizo falta.]

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: La ficha de evaluación

Cinco usos en una sola vista, la más densa de la app. Va sola por eso.

**Files:**
- Modify: `app/views/assessments/new.html.haml:16` (`.panel.ai-guide-banner`), `:25`, `:72`, `:80` (`.panel.assessment-detail--ai`), `:86`
- Modify: `app/assets/stylesheets/application.css` (espaciado, si hace falta)

**Interfaces:**
- Consumes: la tabla de formas.
- Produces: nada.

- [ ] **Step 1: Leer la vista entera**

Cinco tarjetas anidadas en una pantalla de formulario: importa más que en ninguna otra ver qué queda adentro de cada una antes de bajar todo un nivel.

- [ ] **Step 2: Aplicar la tabla de formas**

Tres son el caso base. `:16` es `.panel.ai-guide-banner` → `.card.ai-guide-banner` > `.card-body`; `:80` es `.panel.assessment-detail--ai` → `.card.assessment-detail--ai` > `.card-body`. Las dos ponen borde y fondo, que son de la caja externa.

- [ ] **Step 3: Confirmar el orden en la hoja**

Las dos reglas tienen que seguir **después** de `.card` en `application.css`, porque pisan `background` y `border-color` con la misma especificidad y sin capa: gana la que viene después. Hoy están en 1748 y 1762, y `.card` alrededor de 800.

Run: `grep -n "^\.card {\|^\.assessment-detail--ai\|^\.ai-guide-banner" app/assets/stylesheets/application.css`
Expected: el número de `.card` es **menor** que los otros dos.

- [ ] **Step 4: Confirmar que no quedó ninguno**

Run: `grep -n "\.panel" app/views/assessments/new.html.haml`
Expected: sin salida.

- [ ] **Step 5: Correr el recorrido**

Run: `make screens`
Expected: 59 capturas, sin errores. Sin `[CONTRASTE]`: las dos tarjetas de IA tienen fondo propio (`--ia-panel`), y un chip adentro se mide contra ese fondo.

- [ ] **Step 6: Comparar la captura**

`09-11-panel-evaluacion`. Mirar que las dos tarjetas de IA sigan teniéndose su fondo y su borde, que es lo que el paso 3 protege en teoría y la captura confirma en la práctica.

- [ ] **Step 7: Correr la suite**

Run: `make spec`
Expected: 919 examples, 0 failures.

- [ ] **Step 8: Commit**

```bash
git add app/views/assessments app/assets/stylesheets/application.css
git commit -m "La ficha de evaluación pasa a \`card\`

Cinco tarjetas en la pantalla más densa de la app. Las dos de IA
—\`.ai-guide-banner\` y \`.assessment-detail--ai\`— conservan su clase en la
\`card\` y no en el \`card-body\`: ponen borde y fondo, que son de la caja
externa, y siguen pisando a \`.card\` porque vienen después en la hoja.

[Describir el ajuste de espaciado, o decir que no hizo falta.]

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Las dos islas

Cuatro usos. Es el único punto del plan donde se toca un `.vue`, y entra sólo para que `.panel` pueda morir acá como el spec del 2b prometió.

**Files:**
- Modify: `app/javascript/components/pipeline_builder/pipeline_builder.vue:4,38`
- Modify: `app/javascript/components/criteria_editor/criteria_editor.vue:11,22`

**Interfaces:**
- Consumes: la tabla de formas.
- Produces: cero usos de `.panel` en todo el repo, que es lo que la tarea 8 exige.

- [ ] **Step 1: Buscar la clase en selectores compuestos antes de tocarla**

Es la trampa que el 2a pagó dos veces: renombrar una clase deja muertas en silencio las reglas que la usaban desde AFUERA de su bloque, y ni `make spec` ni `make screens` lo notan porque el elemento sigue teniendo reglas, sólo que otras.

Run:
```bash
grep -n "builder__palette\|criterion-edit\|\.panel" app/assets/stylesheets/application.css | grep -v "^7[0-9][0-9]:\|^8[0-2][0-9]:"
grep -rn "panel" app/javascript/
```
Expected: anotar toda regla que combine `.panel` con otra clase o la use como descendiente/`:has()`. Si aparece alguna, se migra con el markup en el mismo commit.

- [ ] **Step 2: Aplicar la tabla de formas en `pipeline_builder.vue`**

```html
<!-- Antes -->
<aside class="builder__palette panel">
<!-- Después -->
<aside class="builder__palette card"><div class="card-body">
```

y cerrar el `</div>` que corresponda. Lo mismo con `:38`, que es `class="panel empty-state"` → `class="card"` con un hijo `class="card-body empty-state"`.

**Cuidado con el cierre de etiquetas:** agregar un nivel en un `.vue` es agregar un `<div>` que hay que cerrar. Un desbalance rompe el build de esbuild, no la pantalla.

- [ ] **Step 3: Aplicar la tabla de formas en `criteria_editor.vue`**

`:11` y `:22` son `<div class="panel">` → `<div class="card"><div class="card-body">` con su cierre.

- [ ] **Step 4: Recompilar y confirmar que no quedó ninguno**

Run: `make yarn-build && grep -rn "\"panel\"\|'panel'\| panel\b" app/javascript/components/`
Expected: el build sin errores, y el grep sin salida fuera de comentarios.

- [ ] **Step 5: Correr el recorrido**

Run: `make screens`
Expected: 59 capturas, sin errores, sin `[ISLA]`, sin `[JS ERROR]`.

**Un bug de Vue no lo atrapa ningún spec de Ruby.** Si la isla no monta, `make spec` sigue en verde y la pantalla queda en blanco; la guarda que lo dice es `[ISLA]` y el `.island-placeholder` sin montar.

- [ ] **Step 6: Comparar las capturas de las dos islas**

`05-builder`, `03b-builder-plantillas`, `09-9-builder-sin-formulario` y `10b-criteria-editor`.

- [ ] **Step 7: Correr la suite**

Run: `make spec`
Expected: 919 examples, 0 failures.

- [ ] **Step 8: Commit**

```bash
git add app/javascript/components
git commit -m "Las dos islas entregan sus cuatro tarjetas

\`pipeline_builder\` y \`criteria_editor\` eran los últimos \`.panel\` del repo, y
el spec del 2b los dejaba para el 2c — con lo cual su propia promesa de borrar
\`.panel\` al cerrar el 2b-bis no se podía cumplir. Entra sólo el markup de
tarjeta; el comportamiento y el CSS muerto siguen siendo 2c.

Un bug de Vue no lo atrapa ningún spec de Ruby: lo que lo dice es \`[ISLA]\` y
el \`.island-placeholder\` sin montar.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Cierre

Borrar `.panel`, limpiar las cinco menciones que quedan en el script y corregir los documentos.

**Files:**
- Modify: `app/assets/stylesheets/application.css` (borrar la regla `.panel` y los tres selectores compuestos)
- Modify: `script/capture_screens.js` (borrar `[CARD]`; limpiar `[RITMO]`, el muestrario y el mensaje de `[PANEL]`)
- Modify: `CLAUDE.md`
- Modify: `docs/superpowers/specs/2026-09-17-rediseno-2b-pantallas-de-modulo-design.md`

**Interfaces:**
- Consumes: cero usos de `.panel`, de la tarea 7.
- Produces: el estado final.

- [ ] **Step 1: Confirmar que no queda ningún uso en todo el repo**

Run: `grep -rn "\.panel\b" app/ spec/ script/ | grep -v "ai-panel\|ia-panel\|flow-drawer__panel"`
Expected: sólo las menciones de `application.css` y `capture_screens.js` que esta tarea borra, y los ocho asertos de `spec/requests/pantalla_del_modulo_spec.rb`, que esperan **cero** y siguen valiendo.

Si aparece un uso en una vista o en una isla, esta tarea no puede empezar.

- [ ] **Step 2: Borrar la regla `.panel` y sus selectores compuestos**

En `application.css`, borrar el bloque `.panel { … }` (superficie, borde, radio, sombra, relleno 20px) y las tres líneas de `.app-main > .panel …`. Los `.card` equivalentes ya están al lado, así que la prosa conserva su medida.

Actualizar de paso el comentario de la cabecera de la hoja, que dice que cada pantalla pasa de `.panel` a `card` «cuando le toca» y que `.panel` se borra cuando no quede ninguna: ya no queda ninguna.

- [ ] **Step 3: Borrar `[CARD]` y limpiar las otras cuatro menciones del script**

| Qué | Qué se hace |
|---|---|
| `revisarCardComoPanel` entera y sus dos llamadas (`claro` y `oscuro`) | **Borrar.** Sin `.panel` no hay contra qué comparar: era andamio |
| `[CLASES]`: `.panel` en la lista de selectores | **Dejar.** Es lo que caza un `.panel` reintroducido, que sin regla queda sin fondo, sin relleno y sin borde — exactamente lo que esa guarda marca. Actualizar el comentario, que hoy lo explica como una clase con CSS propio |
| `[RITMO]`: `'.app-main > .panel, .app-main > .card'` | Dejar sólo `'.app-main > .card'` |
| Destino del muestrario: `.card-body \|\| .panel \|\| .app-main` | Sacar el `.panel` del medio |
| Mensaje de `[PANEL]`: «tienen que ser `panel`» | Reescribir: una `card` sin `card-body` es un error de maquetado, no una tarjeta sin migrar |

- [ ] **Step 4: Ver que `[CLASES]` caza un `.panel` reintroducido**

Es el reemplazo de `[CARD]` y hay que verlo funcionar, no suponerlo. Poner a mano un `.panel` en una vista del recorrido —por ejemplo `app/views/errors/not_found.html.haml`, que se fotografía como `20-not-found`— y correr:

Run: `make yarn-build && make screens`
Expected: `[CLASES] 20-not-found: … panel …`

Sacarlo y volver a correr hasta verde.

- [ ] **Step 5: Correr todo**

Run: `make yarn-build && make spec && make screens`
Expected: 919 examples 0 failures; 59 capturas, sin errores.

- [ ] **Step 6: Corregir CLAUDE.md**

Tres pasajes hablan de `.panel` como vocabulario vivo:

1. En «El sistema visual», la frase «las tarjetas esperan su `card` + `card-body` bajo el nombre `.panel`» y «El resto de la app sigue en `.panel`: ésas son 2b-bis, y las islas Vue son 2c» — el resto de la app ya no sigue en `.panel`, y las islas entregaron sus cuatro tarjetas acá; lo que queda de ellas es 2c.
2. En «Las tres capas», el párrafo que explica por qué las tarjetas se llaman `.panel` «hasta que cada pantalla pasa a `card`» y que `make screens` falla «si una `card` no se ve igual que un `.panel` (`[CARD]`, que se borra con `.panel`)».
3. En «Verificación», la lista de guardas de `make screens`, que nombra `[CARD]`.

Decir en su lugar qué quedó: las tarjetas son `card` + `card-body`, `[PANEL]` sigue exigiendo el `card-body`, y `[CLASES]` es lo que caza una clase sin regla detrás.

- [ ] **Step 7: Corregir el spec del 2b**

Su sección de alcance dice que las islas Vue, incluidas sus tarjetas internas, son 2c. Anotar que el 2b-bis se llevó las cuatro tarjetas y por qué: sin ellas `.panel` no se podía borrar, que era lo que ese mismo spec prometía.

- [ ] **Step 8: Correr todo una vez más y commitear**

Run: `make yarn-build && make spec && make screens`
Expected: 919 examples 0 failures; 59 capturas, sin errores.

```bash
git add app/assets/stylesheets/application.css script/capture_screens.js CLAUDE.md docs/superpowers/specs
git commit -m "Se borra .panel: no queda ninguna

La regla, sus tres selectores compuestos (.app-main > .panel p:not([class]),
.muted y .field-hint) y la guarda [CARD]. Los .card equivalentes ya estaban al
lado, así que la prosa conserva su medida.

[CARD] era andamio: comparaba una card inyectada contra un .panel inyectado,
o sea que dependía de la REGLA y no de que alguna vista la usara. Existía para
que la card no se desviara del panel MIENTRAS convivían, y sin .panel no hay
de qué desviarse. No se reemplaza: [CLASES] ya lista .panel y marca cualquier
elemento sin fondo, sin relleno y sin borde, que es en lo que queda un .panel
reintroducido. Visto cazándolo antes de darlo por bueno.

Las otras tres menciones del script se limpian sin borrarse: [RITMO] y el
destino del muestrario pierden su mitad muerta, y el mensaje de [PANEL] deja
de decir que una card sin card-body es una tarjeta sin migrar — ahora es un
error de maquetado.

CLAUDE.md y el spec del 2b dicen lo que quedó.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 9: Mirar las 59 capturas**

Es el cierre del plan y lo único que no hace una máquina. Comparar contra `tmp/screenshots-antes-2b/` donde haya equivalente.

---

## Definición de terminado

- `grep -rn "\.panel\b" app/ script/` no devuelve nada fuera de los ocho asertos que esperan cero.
- `make spec`: 919 examples, 0 failures.
- `make screens`: 59 capturas, sin errores.
- `[CLASES]` visto cazando un `.panel` reintroducido.
- Las 59 capturas miradas.
- CLAUDE.md y el spec del 2b dicen lo que quedó.
