# Rediseño 2a: el vocabulario de componentes — plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pasar el vocabulario visual que se repite —tarjetas, tablas, avisos, chips y nodos del flujo— a componentes de DaisyUI, sin tocar el dominio.

**Architecture:** Casi todo el cambio vive en `EstilosHelper`, que ya es el único lugar que traduce estado a clase: cambiar lo que devuelve cambia todas las vistas que lo usan. Lo que está escrito a mano en vistas e islas pasa a usar el helper, o se reescribe literal cuando no hay helper. `.card` se renombra a `.panel` antes de habilitar el `card` de DaisyUI, porque habilitarlo es global. Una guarda nueva de contraste en `make screens` decide qué variantes suaves necesitan ajuste.

**Tech Stack:** Rails 7 · HAML · Vue 3 (islas) · Tailwind 4 + DaisyUI 5 (config en CSS, compilado con el CLI de Tailwind) · RSpec · Playwright (`script/capture_screens.js`).

**Spec:** `docs/superpowers/specs/2026-09-16-rediseno-2a-vocabulario-design.md` (continúa `2026-09-08-rediseno-tailwind-daisyui-design.md`). Leé los dos antes de la primera tarea.

## Global Constraints

- Código, comentarios y mensajes de commit **en español**. Los commits terminan con las líneas de atribución de la sesión.
- **Todo corre en Docker.** `make spec`, `make spec-file FILE=…`, `make screens`, `make yarn-build`. Nunca `bundle exec` en el host, y nunca `docker compose exec app bundle exec rspec` (usa el contenedor de desarrollo y todos los request specs dan 403).
- **El contenedor `app` no recompila CSS ni JS solo.** Después de tocar `app/assets/stylesheets/application.css`, un `.vue` o un `.js` de `app/javascript`, corré `make yarn-build` **antes** de `make screens`. Sin eso, las capturas prueban la hoja vieja.
- **Nombres de clase completos y literales.** Nunca `"badge-#{x}"`: Tailwind escanea texto y una clase interpolada no llega a la hoja. Lo cuida `spec/lint/clases_interpoladas_spec.rb` (HAML, `.vue`, `.js`). En `EstilosHelper` también: cada valor es la cadena entera.
- **Mezclas de color `in oklab`, nunca `in oklch`.**
- **Contraste del texto: mínimo 4,5:1**, compuesto sobre su fondo efectivo, **en los dos temas**.
- **Una regla CSS propia va sin capa** y le gana entera a DaisyUI (que vive en `@layer`). No re-ancles a `.table` o `.badge` reglas que pisen lo que el componente ya pinta: sólo lo que es vocabulario de la app.
- **Rama `rediseno-2a`**, salida de `master`, que ya tiene el commit del spec. Si `doc-404-403` se mergea a `master` antes que ésta, rebaseá antes de mergear (los dos tocan `CLAUDE.md` en secciones distintas).
- **Cada tarea termina con `make spec` y `make screens` en verde, y un commit.**
- **`CLAUDE.md` se actualiza en el commit que vuelve falsa cada frase.**

---

## Mapa de archivos

| Archivo | Qué hace en este plan |
|---|---|
| `app/helpers/estilos_helper.rb` | Tareas 4, 5, 6: los mapas devuelven `alert`/`badge`; nace `CHIP_DE_IA` |
| `spec/helpers/estilos_helper_spec.rb` | Tareas 4, 5, 6: las guardas contra el enum pasan de sufijo a claves |
| `app/assets/stylesheets/application.css` | Tareas 1, 2, 4, 5, 7: renombres, re-anclajes, ajustes de contraste, borrado |
| `script/capture_screens.js` | Tareas 1, 2, 3: guardas de `.card`, `.table`, contraste y pasada oscura |
| 38 vistas HAML + 2 islas | Tarea 1: `.card` → `.panel` |
| 8 vistas HAML | Tarea 2: `step-table` → `table` |
| 10 vistas HAML + 3 islas | Tarea 4: avisos a `alert` |
| 9 vistas HAML + `pipeline_builder.vue` | Tarea 5: chips a mano pasan por el helper |
| `app/views/challenges/_template_outline.html.haml` | Tarea 6: el nodo a mano pasa por el helper |
| `spec/system/builder_island_spec.rb` | Tarea 2: `.step-table` → `.table` |
| `spec/requests/popups_de_ia_spec.rb` | Tarea 4: la aserción de «no se pinta como franja» |
| `CLAUDE.md` | Tareas 1, 5, 7 |

---

### Task 1: `.card` pasa a `.panel`, y se habilita el `card` de DaisyUI

Mecánico y **sin cambio visible**. Es el punto de control del plan.

**Files:**
- Modify (HAML, 38): `app/views/ai_runs/index.html.haml` · `ai_runs/show` · `assessments/new` · `challenges/_gestores` · `challenges/builder` · `challenges/index` · `challenges/new` · `challenges/show` · `criteria_sets/_form` · `criteria_sets/index` · `criteria_sets/show` · `errors/forbidden` · `errors/not_found` · `ideas/_contributors` · `ideas/diff` · `ideas/edit` · `ideas/index` · `ideas/new` · `ideas/show` · `memberships/index` · `notifications/index` · `pages/home` · `previews/show` · `sessions/select_company` · `shared/_ai_suggestions` · `shared/_setup_outline` · `steps/_ai_mode` · `steps/_asignaciones_evaluadores` · `steps/_campos_editor` · `steps/_config_congelada` · `steps/_criterios_editor` · `steps/_referencia_evaluacion` · `steps/config/_modulo` · `steps/evaluation` · `steps/evolution` · `steps/ideation` · `steps/reporting` · `steps/selection` (todos `.html.haml` bajo `app/views/`)
- Modify (Vue, 2): `app/javascript/components/criteria_editor/criteria_editor.vue` · `app/javascript/components/pipeline_builder/pipeline_builder.vue`
- Modify: `app/assets/stylesheets/application.css` (bloque de comentario + `exclude: card` al principio; `.app-main > .card …` ~531-533; `.card {` ~753)
- Modify: `script/capture_screens.js` (`revisarRitmo` ~107; `revisarClasesDescartadas` ~132; comentario ~832; `capturar()`)
- Modify: `CLAUDE.md` (sección «El sistema visual»)

**Interfaces:**
- Produces: la clase `.panel` —mismo CSS que tenía `.card`— y la función `revisarTarjetasViejas(page, name)` en `script/capture_screens.js`, llamada desde `capturar()`. La Tarea 2b (plan futuro) migra `.panel` a `card` + `card-body`.

- [ ] **Step 1: Guardar las capturas de antes**

```bash
git checkout rediseno-2a
make yarn-build
make screens
rm -rf tmp/screenshots-antes-2a && cp -r tmp/screenshots tmp/screenshots-antes-2a
```

Expected: `Sin errores de JS ni respuestas >= 400.` Si no está en verde acá, pará: el punto de partida está roto y nada de lo que sigue se puede verificar.

- [ ] **Step 2: Escribir la guarda que falla**

En `script/capture_screens.js`, arriba de `async function capturar(page, name)`:

```js
// Ningún elemento puede tener la clase `card` de esta app: se renombró a
// `.panel` para poder habilitar el `card` de DaisyUI, que declara
// `display: flex` y convertiría en columna flex a cualquier tarjeta vieja que
// haya quedado. Se mira en el DOM y no en el fuente porque una clase la puede
// armar un `.js` o una isla en tiempo de ejecución, donde un `grep` no llega.
async function revisarTarjetasViejas(page, name) {
  const viejas = await page.evaluate(() => document.querySelectorAll('.card').length);
  if (viejas > 0) {
    failures++;
    console.error(`[PANEL] ${name}: ${viejas} elementos con la clase \`card\` vieja; tienen que ser \`panel\``);
  }
}
```

Y en `capturar()`, después de `await revisarClasesDescartadas(page, name);`:

```js
  await revisarTarjetasViejas(page, name);
```

- [ ] **Step 3: Verla fallar**

Run: `make screens`
Expected: FAIL, con líneas `[PANEL] … elementos con la clase \`card\` vieja` en casi todas las pantallas.

- [ ] **Step 4: Renombrar en HAML y Vue**

```bash
# `.card` como clase en HAML: `.card`, `%tag.card`, `.otra.card`, `.card.otra`.
git grep -lP '(?<![-\w])\.card(?![-\w])' -- 'app/views/**/*.haml' \
  | xargs perl -pi -e 's/(?<![-\w])\.card(?![-\w])/.panel/g'

# `card` dentro de un atributo de clase: `class: "card challenge-card"`, `class="card"`.
git grep -lP '(?<=["\s])card(?=["\s])' -- 'app/views/**/*.haml' 'app/javascript/**/*.vue' \
  | xargs perl -pi -e 's/(?<=["\s])card(?=["\s])/panel/g'
```

- [ ] **Step 5: Verificar que no quedó ninguna**

```bash
git grep -nP '(?<![-\w])card(?![-\w])' -- app/views app/javascript app/helpers app/presenters
```

Expected: **sin salida.** Si aparece algo, es una forma de escribir la clase que los dos reemplazos no agarraron: corregilo a mano y volvé a correr la búsqueda. Revisá también que `git diff --stat` muestre exactamente 40 archivos bajo `app/views` y `app/javascript`, y que ninguno de los `-card` propios (`.stat-card`, `.auth-card`, `.theme-card`, `.challenge-card`, `.ai-mode-card`, `.narrative-card`) haya cambiado:

```bash
git diff -U0 -- app/views app/javascript | grep -E '^[-+].*(stat|auth|theme|challenge|ai-mode|narrative)-(card|panel)' | grep -v 'challenge-card'
```

Expected: sin salida. (`challenge-card` aparece en la línea de `class: "panel challenge-card"`, que es correcta.)

- [ ] **Step 6: Renombrar en la hoja y sacar el `exclude`**

En `app/assets/stylesheets/application.css`, las reglas (no los comentarios):

```css
.app-main > .panel p:not([class]),
.app-main > .panel .muted,
.app-main > .panel .field-hint,
```

```css
.panel {
  background: var(--surface);
  border: 1px solid var(--borde);
  border-radius: var(--radius);
  box-shadow: var(--shadow);
  padding: 20px;
}
```

Y el principio del archivo queda así (reemplazá el comentario de `card` y el `@plugin` enteros):

```css
@import "tailwindcss";

/* `card` de DaisyUI está HABILITADA, pero ninguna tarjeta la usa todavía.
   Estuvo excluida porque además de pintar declara `display: flex`,
   `flex-direction: column` y `position: relative`, y habilitarla convertía de
   golpe todas las tarjetas de la app en columnas flex. Para poder habilitarla
   sin tocar ninguna, las tarjetas de la app se renombraron a `.panel`. Cada
   pantalla pasa de `.panel` a `card` + `card-body` cuando le toca (plan 2b),
   y `.panel` se borra cuando no quede ninguna. */
@plugin "daisyui" {
  themes: false;
}
```

Dos comentarios más de la hoja hablan de `card` excluida. En el de «Buttons» (~línea 822), reemplazá:

```css
   `card` NO se migró, y no alcanzaba con dejarla después del @plugin: se
   excluye del plugin, arriba, con la medición que lo justifica.
```

por:

```css
   `card` tampoco colisiona ya: la tarjeta de esta app pasó a llamarse
   `.panel`, y el `card` de DaisyUI quedó habilitada sin que nada la use
   todavía. Ver el comentario del @plugin, arriba.
```

Y en el de «Los dos popups de la IA» (~línea 2268), reemplazá:

```css
/* El armazón es el `modal` de DaisyUI (que NO está excluido: sólo `card` lo */
/* está) sobre un `<dialog>` de verdad: `showModal()` deja el resto de la */
```

por:

```css
/* El armazón es el `modal` de DaisyUI sobre un `<dialog>` de verdad: */
/* `showModal()` deja el resto de la */
```

- [ ] **Step 7: Las guardas de capturas que miraban `.card`**

En `script/capture_screens.js`:
- En `revisarRitmo`: `document.querySelectorAll('.app-main > .card')` → `document.querySelectorAll('.app-main > .panel')`, y renombrá la variable `cards` a `paneles`.
- En `revisarClasesDescartadas`: en el selector, `.card` → `.panel`.
- En el comentario cerca de la línea 832 que cita ese selector: `.card` → `.panel`.

Sin esto las dos guardas se quedan mirando cero elementos y pasan en verde sin probar nada.

- [ ] **Step 8: Recompilar y correr todo**

```bash
make yarn-build
make spec
make screens
```

Expected: `make spec` sin fallas; `make screens` con `Sin errores de JS ni respuestas >= 400.` y **ninguna línea `[PANEL]`, `[RITMO]` ni `[CLASES]`**.

- [ ] **Step 9: Mirar que no cambió nada**

Abrí lado a lado, de `tmp/screenshots-antes-2a/` y `tmp/screenshots/`: `02-challenges.png`, `04-challenge.png`, `05-builder.png`, `07-idea.png`, `10-criteria.png`. Tienen que verse iguales: mismas tarjetas, mismo espaciado, mismos bordes. Si una tarjeta cambió de disposición interna (hijos apilados, enlaces que ocupan el ancho entero), quedó un `card` que la búsqueda no vio: volvé al Step 5.

- [ ] **Step 10: `CLAUDE.md`**

En la sección «El sistema visual», reemplazá el párrafo que empieza «`card` de DaisyUI está **excluida**» por:

```markdown
`card` de DaisyUI está **habilitada**, y ninguna tarjeta la usa todavía. Estuvo
excluida porque declara `display: flex`, y habilitarla convertía de golpe todas
las tarjetas de la app en columnas flex. Para poder habilitarla sin tocar
ninguna, las tarjetas de la app se llaman **`.panel`**: mismo CSS que tenía
`.card`. Cada pantalla pasa de `.panel` a `card` + `card-body` cuando le toca
(plan 2b). `make screens` falla si aparece un elemento con la clase `card`
vieja (`revisarTarjetasViejas`), porque sin el `exclude` esa tarjeta se vuelve
flex en silencio.
```

Y en el párrafo «Esta fase migró la plomería…», cambiá «`status-chip`, `.step-card` y compañía todavía son CSS escrito a mano y no `badge` ni `card` de DaisyUI» por «`status-chip`, `.step-card` y compañía todavía son CSS escrito a mano; el plan 2a (`docs/superpowers/plans/2026-09-16-rediseno-2a-vocabulario.md`) los pasa a componentes».

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -F - <<'MSG'
Las tarjetas se llaman `.panel`, y `card` de DaisyUI queda habilitada

`card` de DaisyUI estaba excluida porque declara `display: flex`, y sacar el
`exclude` convertía de golpe todas las tarjetas de la app en columnas flex. No
se podía migrar de a una pantalla. Ahora las tarjetas de la app se llaman
`.panel` —mismo CSS— y el `exclude` se fue sin tocar ninguna: cada pantalla
pasa a `card` + `card-body` cuando le toque.

El renombre alcanza dos islas Vue aunque las islas sean otro plan: si no, al
sacar el `exclude` esas tarjetas se volvían flex.

`make screens` suma una guarda: ningún elemento con la clase `card` vieja en
el DOM, que es donde una clase armada por una isla o un `.js` aparece y un
`grep` no. Y las dos guardas que miraban `.card` —ritmo y clases descartadas—
pasan a `.panel`, o se quedaban mirando cero elementos.

Verificado: la guarda nueva falló antes del renombre en casi todas las
pantallas, y las capturas de antes y después se ven iguales.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 2: `step-table` pasa a `table`

**Files:**
- Modify: `app/views/ai_runs/index.html.haml` (tabla ~25, link ~39) · `app/views/ai_runs/show.html.haml` (~24) · `app/views/challenges/show.html.haml` (tabla ~60, link ~74) · `app/views/criteria_sets/show.html.haml` (~8) · `app/views/steps/evaluation.html.haml` (tabla ~52, links ~71 y ~114) · `app/views/steps/reporting.html.haml` (tablas ~27, ~86, ~129, ~152) · `app/views/steps/selection.html.haml` (tabla ~110, link ~142)
- Modify: `app/assets/stylesheets/application.css` (reglas de `.step-table` ~464, ~1026-1039, ~1325-1326, ~2532-2533)
- Modify: `script/capture_screens.js` (`revisarClasesDescartadas`)
- Test: `spec/system/builder_island_spec.rb:82`

**Interfaces:**
- Produces: tablas `%table.table` y enlaces de fila `.table-link`. Las reglas de estado de fila (`tr.is-active`, `tr.is-touched`) quedan ancladas a `.table`.

- [ ] **Step 1: El test que falla**

En `spec/system/builder_island_spec.rb`, línea ~82:

```ruby
    expect(page).to have_css("table.table", wait: 10)
```

- [ ] **Step 2: Verlo fallar**

Run: `make spec-file FILE=spec/system/builder_island_spec.rb`
Expected: FAIL, `expected to find css "table.table"`.

- [ ] **Step 3: Renombrar en las vistas**

```bash
git grep -l 'step-table' -- 'app/views/**/*.haml' | xargs perl -pi -e 's/\bstep-table__link\b/table-link/g; s/\.step-table\b/.table/g'
git grep -n 'step-table' -- app/views
```

Expected de la búsqueda: sin salida. `ranking-table` en `steps/selection.html.haml` queda al lado: `%table.table.ranking-table`.

- [ ] **Step 4: La hoja: lo que pinta el componente se va, lo que es de la app se re-ancla**

En `app/assets/stylesheets/application.css`:

1. La línea ~464 `.step-table td, .step-table th { font-variant-numeric: tabular-nums; }` → `.table td, .table th { font-variant-numeric: tabular-nums; }`.
2. El bloque ~1026-1039 se reemplaza entero por:

```css
/* La tabla la pinta `table` de DaisyUI: ancho, relleno de celdas y bordes de
   fila. Acá queda sólo lo que es vocabulario de esta app: la separación del
   título de la tarjeta, y los encabezados de columna en mayúsculas chicas —que
   es donde CLAUDE.md dice que van las mayúsculas chicas—. */
.table { margin-top: 18px; }
.table th {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: .05em;
  color: var(--muted);
}
/* Lo ya ejecutado se marca en gris: si compite con el acento, el módulo en */
/* curso deja de destacarse y la tabla queda con un riel azul de punta a punta. */
.table tr.is-touched td:first-child { border-left: 2px solid var(--borde); }
```

   Es decir: se van `width`, `border-collapse` y `font-size` de `.step-table`, el `text-align`/`padding`/`border-bottom` de `th`, y la regla entera de `td` —lo hace el componente—.
3. ~1325-1326: `.step-table__link` → `.table-link` (las dos reglas).
4. ~2532-2533: `.step-table tr.is-active td` → `.table tr.is-active td` (las dos reglas).

- [ ] **Step 5: La guarda de clases descartadas mira las celdas**

En `revisarClasesDescartadas`, sumá `.table :is(th,td)` al selector. No `.table` a secas: la `<table>` no tiene fondo ni relleno propios aunque el componente haya llegado a la hoja, así que marcaría todas. Las celdas sí tienen relleno cuando `table` compiló:

```js
    for (const el of document.querySelectorAll('[class*="badge"],[class*="btn"],[class*="alert"],.steps,.panel,.table :is(th,td)')) {
```

- [ ] **Step 6: Recompilar y verificar**

```bash
make yarn-build
make spec-file FILE=spec/system/builder_island_spec.rb
make spec
make screens
```

Expected: el system spec pasa; `make spec` sin fallas; `make screens` en verde y sin `[CLASES]`.

- [ ] **Step 7: Mirar**

Compará con `tmp/screenshots-antes-2a/`: `04-challenge.png` (flujo del desafío), `11-ai-runs.png`, y las capturas de evaluación, selección y reportería (`09-3-step-evaluaci-n-t-cnica.png`, `09-4-step-corte-a-top-3.png`, `09-7-step-reporte-de-cierre.png`). Cambia poco: la letra de las celdas pasa de 13 a 14px y el relleno lo pone el componente. **Tiene que seguir** estando la fila activa resaltada con el riel de acento, las ejecutadas con el borde gris, y los encabezados en mayúsculas chicas.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -F - <<'MSG'
Las tablas son `table` de DaisyUI

`step-table` era CSS escrito a mano para lo que `table` ya pinta: ancho,
relleno de celdas, bordes de fila. Eso se fue. Quedó lo que es vocabulario de
esta app —los encabezados en mayúsculas chicas, la separación del título, y
las filas activa y ejecutada—, re-anclado a `.table`. Re-anclar el resto habría
pisado el componente entero: una regla sin capa le gana a cualquier `@layer`.

`step-table__link` quedaba como elemento de un bloque que ya no existe; pasa a
`table-link`.

La guarda de clases descartadas mira las celdas y no la tabla: una `<table>`
no tiene fondo ni relleno propios aunque el componente haya compilado.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 3: La guarda de contraste en `make screens`

Antes de migrar avisos y chips, porque `alert-soft` y `badge-soft` pintan el texto con el color **puro** del tema, y la hoja de hoy tuvo que oscurecer `success`, `warning` y `error` para que los chips llegaran al contraste. Esta guarda es la que dice cuáles hay que ajustar.

**Files:**
- Modify: `script/capture_screens.js`

**Interfaces:**
- Produces: `medirContraste(page, selector)` → `Promise<Array<{ clase: string, texto: string, ratio: number }>>`; `revisarContraste(page, name)`, llamada desde `capturar()`; `probarMedidorDeContraste(page)`, que corre una vez al arrancar; y una pasada en tema oscuro al final del recorrido.

- [ ] **Step 1: La prueba del medidor, antes que el medidor**

En `script/capture_screens.js`, arriba de `capturar()`:

```js
// El medidor se prueba contra valores conocidos ANTES de creerle a lo que dice
// de las pantallas. Los dos con alfa valen 3,98 exactos; el canvas guarda el
// alfa en 8 bits (128/255 y no 0,5) y da entre 3,95 y 4,00, así que se espera
// 3,97 con 0,05 de tolerancia. Un medidor de contraste que compone mal el alfa infla los
// números —pasó en la fase 1: un 1.49:1 se leyó como 13.56:1— y una guarda que
// siempre pasa es peor que ninguna.
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
    </body>`);
  const medidos = await medirContraste(page, '[data-esperado]');
  const esperados = await page.$$eval('[data-esperado]', (els) => els.map((e) => Number(e.dataset.esperado)));
  medidos.forEach((m, i) => {
    if (Math.abs(m.ratio - esperados[i]) > 0.05) {
      failures++;
      console.error(`[CONTRASTE] el medidor está mal: «${m.texto}» dio ${m.ratio.toFixed(2)} y es ${esperados[i]}`);
    }
  });
}
```

Y en el cuerpo principal, justo después de `const page = await browser.newPage(...)` (~línea 179):

```js
  await probarMedidorDeContraste(page);
```

- [ ] **Step 2: Verla fallar**

Run: `make screens`
Expected: el script aborta con `FALLO: medirContraste is not defined`.

- [ ] **Step 3: El medidor**

Arriba de `probarMedidorDeContraste`:

```js
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
    const luminancia = ([r, g, b]) => {
      const f = (v) => { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
      return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
    };

    return [...document.querySelectorAll(sel)]
      .filter((el) => el.getClientRects().length > 0 && el.textContent.trim())
      .map((el) => {
        const fondo = fondoDe(el);
        const texto = sobre(rgba(getComputedStyle(el).color), fondo);
        const [claro, oscuro] = [luminancia(texto), luminancia(fondo)].sort((a, b) => b - a);
        return { clase: el.className, texto: el.textContent.trim().slice(0, 40), ratio: (claro + 0.05) / (oscuro + 0.05) };
      });
  }, selector);
}
```

- [ ] **Step 4: Ver pasar la prueba del medidor**

Run: `make screens`
Expected: sin líneas `[CONTRASTE] el medidor está mal`. Si aparece alguna, el medidor está mal: no sigas hasta que dé los cinco valores.

- [ ] **Step 5: La guarda sobre las pantallas**

Abajo de `medirContraste`:

```js
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
```

Y en `capturar()`, después de `await revisarTarjetasViejas(page, name);`:

```js
  await revisarContraste(page, name);
```

- [ ] **Step 6: La pasada en tema oscuro**

El tema oscuro se activa con `prefers-color-scheme` (el `data-theme` NO va en el `<html>`: rompe el oscuro). Justo antes de `await browser.close();` (~línea 931):

```js
  // ── Tema oscuro ──────────────────────────────────────────────────────────
  //
  // El contraste se mide en los dos temas: una variante que pasa en claro
  // puede no pasar en oscuro. Se emula `prefers-color-scheme` y se vuelve a
  // las pantallas donde viven los chips y los avisos. Por URL y no por link:
  // esto no prueba navegación, prueba colores, y el recorrido por link ya
  // corrió en claro.
  await page.emulateMedia({ colorScheme: 'dark' });
  for (const [nombre, url] of [
    ['90-oscuro-desafios', '/challenges'],
    ['91-oscuro-desafio', `/challenges/${CHALLENGE}`],
    ['92-oscuro-criterios', '/criteria_sets'],
    ['93-oscuro-ia', '/admin/ai_runs']
  ]) {
    await page.goto(BASE + url, { waitUntil: 'networkidle' });
    await capturar(page, nombre);
  }
  await page.emulateMedia({ colorScheme: 'light' });
```

- [ ] **Step 7: Verificar**

Run: `make screens`
Expected: en verde. Todavía no hay ningún `.badge` ni `.alert` en la app, así que la guarda no mide nada real: lo que se prueba acá es que el medidor da bien y que la pasada oscura corre. Mirá `tmp/screenshots/90-oscuro-desafios.png`: tiene que verse en tema oscuro.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -F - <<'MSG'
`make screens` mide el contraste de avisos y chips, en los dos temas

Los componentes suaves de DaisyUI pintan el texto con el color puro del tema,
y la hoja tuvo que oscurecer `success`, `warning` y `error` para que los chips
de hoy llegaran al contraste. Antes de pasarlos a `badge-soft` y `alert-soft`
hace falta saber cuáles no llegan.

El medidor compone el alfa del fondo sobre cada ancestro hasta el primero
opaco, y el del texto sobre eso: medido sin componer da un número que en
pantalla no existe, que fue el error de la fase 1. Lee los colores pintándolos
en un canvas, porque `getComputedStyle` los devuelve en el espacio en que se
declararon. Y se prueba contra cinco valores conocidos antes de creerle a lo
que dice de las pantallas.

Todavía no hay badges ni alerts en la app: esta tarea prueba el medidor, las
dos siguientes lo usan.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 4: Los avisos pasan a `alert`

**Files:**
- Modify: `app/helpers/estilos_helper.rb` (`CLASE_DE_FLASH`)
- Test: `spec/helpers/estilos_helper_spec.rb`
- Modify (HAML, 10 avisos en 8 archivos): `app/views/ai_runs/show.html.haml:11` · `app/views/assessments/new.html.haml:28,44` · `app/views/challenges/new.html.haml:14` · `app/views/challenges/show.html.haml:46,52` · `app/views/ideas/edit.html.haml:5` · `app/views/previews/show.html.haml:16` · `app/views/steps/_campos_editor.html.haml:47` · `app/views/steps/_criterios_editor.html.haml:97`
- Modify (Vue, 7 avisos en 3 archivos): `app/javascript/components/criteria_editor/criteria_editor.vue:3,7,9` · `app/javascript/components/form_editor/form_editor.vue:3` · `app/javascript/components/pipeline_builder/pipeline_builder.vue:28,31,34`
- Modify: `app/assets/stylesheets/application.css` (`.flash ul` ~311 y ~1214; `.form-doble > .flash` ~951)
- Test: `spec/requests/popups_de_ia_spec.rb:166`

**Interfaces:**
- Produces: `EstilosHelper::CLASE_DE_FLASH` = `{ "notice" => "alert alert-soft alert-success", "alert" => "alert alert-soft alert-error" }`. Los avisos fijos usan `alert alert-soft alert-warning|success|error` literal.

- [ ] **Step 1: El test del helper que falla**

En `spec/helpers/estilos_helper_spec.rb`, antes del último `end`:

```ruby
  # El flash de un redirect. `alert-soft` y no la variante sólida: los avisos
  # de hoy son suaves, y la sólida los volvería bloques de color. El contraste
  # de la suave lo mide `make screens`.
  it "pinta el flash de un redirect como alert" do
    expect(helper.clase_de_flash("notice")).to eq("alert alert-soft alert-success")
    expect(helper.clase_de_flash("alert")).to eq("alert alert-soft alert-error")
  end
```

- [ ] **Step 2: Verlo fallar**

Run: `make spec-file FILE=spec/helpers/estilos_helper_spec.rb`
Expected: FAIL, `expected: "alert alert-soft alert-success" got: "flash flash--notice"`.

- [ ] **Step 3: El helper**

En `app/helpers/estilos_helper.rb`:

```ruby
  CLASE_DE_FLASH = {
    "notice" => "alert alert-soft alert-success",
    "alert" => "alert alert-soft alert-error"
  }.freeze
```

- [ ] **Step 4: Verlo pasar**

Run: `make spec-file FILE=spec/helpers/estilos_helper_spec.rb`
Expected: PASS.

- [ ] **Step 5: La aserción de los popups, que tiene que poder fallar**

En `spec/requests/popups_de_ia_spec.rb`, el ejemplo «no se pinta como franja de flash» (~línea 163) queda así:

```ruby
  # El flash de la IA ya no es una franja: es el popup. Pintarlo además arriba
  # de `.app-main` sería decir dos veces lo mismo, y encima escupiendo el hash.
  #
  # Se mira el hijo directo de `.app-main`, que es donde el layout pinta el
  # flash de un redirect. No el nombre de la clase en el body: con los avisos
  # en `alert`, `flash--notice` no aparece nunca y esa aserción pasaba sin
  # probar nada.
  it "no se pinta como franja de flash" do
    pedir!("propose_pipeline")
    follow_redirect!

    expect(Nokogiri::HTML(response.body).css(".app-main > .alert")).to be_empty
    expect(response.body).not_to include("tipo&quot;=&gt;")
  end
```

- [ ] **Step 6: Verla fallar a propósito**

En `app/views/layouts/application.html.haml`, comentá temporalmente la línea `- next if type.to_s == "ia"` (~línea 75) agregándole `-#` adelante.

Run: `make spec-file FILE=spec/requests/popups_de_ia_spec.rb`
Expected: FAIL en «no se pinta como franja de flash».

Sacá el `-#`: la línea vuelve como estaba. Corré de nuevo y tiene que pasar. `git diff app/views/layouts/application.html.haml` tiene que quedar vacío.

- [ ] **Step 7: Los avisos fijos de HAML**

`alert` de DaisyUI es `display: grid` con `grid-auto-flow: column`: **un aviso con varios hijos los reparte en columnas.** Los de un solo hijo cambian sólo de clase; los cuatro que tienen varios envuelven su contenido en un `%div`.

Un solo hijo — cambiá la clase:

| Archivo:línea | Antes | Después |
|---|---|---|
| `ai_runs/show.html.haml:11` | `.flash.flash--alert= @run.error` | `.alert.alert-soft.alert-error= @run.error` |
| `assessments/new.html.haml:28` | `.flash.flash--warn` | `.alert.alert-soft.alert-warning` |
| `challenges/new.html.haml:14` | `.flash.flash--alert= @challenge.errors…` | `.alert.alert-soft.alert-error= @challenge.errors…` |
| `challenges/show.html.haml:52` | `.flash.flash--warn` (con `%ul` adentro) | `.alert.alert-soft.alert-warning` |
| `previews/show.html.haml:16` | `.flash.flash--alert` (con `%ul`) | `.alert.alert-soft.alert-error` |
| `steps/_campos_editor.html.haml:47` | `.flash.flash--warn` | `.alert.alert-soft.alert-warning` |

Varios hijos — clase nueva y un `%div` que los envuelve:

`app/views/assessments/new.html.haml:44`:

```haml
          .alert.alert-soft.alert-warning
            %div
              %strong Criterios derivados:
              = derived.map { _1["name"] }.join(", ")
              se calculan solos al guardar, a partir de los anteriores.
```

`app/views/challenges/show.html.haml:46`:

```haml
    .alert.alert-soft.alert-error
      %div
        %strong Falta resolver:
        %ul
          - @report.errors.each do |error|
            %li= error
```

`app/views/ideas/edit.html.haml:5`:

```haml
  .alert.alert-soft.alert-warning
    %div
      Guardar no pisa el contenido: publica la versión
      %strong= "v#{(@idea.versions.maximum(:number) || 0) + 1}"
      y la anterior queda en el historial.
```

`app/views/steps/_criterios_editor.html.haml:97`:

```haml
    .alert.alert-soft.alert-success
      %div
        Estos criterios son de este módulo: no afectan a otros desafíos.
        = link_to "Guardarlos también en la biblioteca", promote_criteria_set_path(set),
                  data: { turbo_method: :post }, class: "field-hint__link"
```

Respetá la indentación que tiene cada uno en su archivo: los bloques de arriba muestran la relativa.

- [ ] **Step 8: Los avisos de las islas**

Los siete tienen un solo hijo (una `<ul>` o una interpolación). Cambiá sólo la clase:

| Antes | Después |
|---|---|
| `class="flash flash--alert"` | `class="alert alert-soft alert-error"` |
| `class="flash flash--warn"` | `class="alert alert-soft alert-warning"` |
| `class="flash flash--notice"` | `class="alert alert-soft alert-success"` |

```bash
git grep -l 'flash flash--' -- 'app/javascript/**/*.vue' | xargs perl -pi -e 's/class="flash flash--alert"/class="alert alert-soft alert-error"/g; s/class="flash flash--warn"/class="alert alert-soft alert-warning"/g; s/class="flash flash--notice"/class="alert alert-soft alert-success"/g'
```

- [ ] **Step 9: Verificar que no quedó ningún aviso viejo**

```bash
git grep -nE '\bflash--|\.flash\b|"flash ' -- app/views app/javascript app/helpers
```

Expected: sin salida.

- [ ] **Step 10: Los selectores de la hoja que dependían de `.flash`**

En `app/assets/stylesheets/application.css`:
- ~311 (dentro de `@layer base`): `.flash ul { list-style: disc; }` → `.alert ul { list-style: disc; }`, y el comentario de arriba sigue siendo cierto.
- ~951: `.form-doble > .flash,` → `.form-doble > .alert,`
- ~1214: `.flash ul { margin: 0; padding-left: 18px; }` → `.alert ul { margin: 0; padding-left: 18px; }`

Las reglas `.flash`, `.flash--alert`, `.flash--notice` y `.flash--warn` **no** se borran acá: las borra la Tarea 7.

- [ ] **Step 11: Recompilar y medir**

```bash
make yarn-build
make spec
make screens
```

Expected: `make spec` en verde. `make screens` probablemente **falla con `[CONTRASTE]`** en alguna variante (`alert-success`, `alert-warning` o `alert-error`), en claro, en oscuro o en los dos. Anotá cuáles.

- [ ] **Step 12: Ajustar sólo las que la guarda marcó**

Por cada variante que falló, agregá su línea en `app/assets/stylesheets/application.css`, al lado de las reglas de `.alert ul`. Son los mismos tokens que usaba la hoja para el texto de los avisos:

```css
/* `alert-soft` pinta el texto con el color puro del tema, y en estas
   variantes no llega a 4,5:1 (lo mide `make screens`). Se oscurece con el
   mismo token que usaba el aviso antes de ser `alert`. Dos clases: le gana a
   `.alert-soft` por especificidad sin pelear la capa. */
.alert-soft.alert-success { color: var(--ok); }
.alert-soft.alert-warning { color: var(--warn); }
.alert-soft.alert-error { color: var(--danger); }
```

Poné **sólo** las líneas de las variantes que fallaron, y ajustá el comentario para que nombre ésas. Si ninguna falló, no agregues nada.

```bash
make yarn-build
make screens
```

Expected: en verde, sin `[CONTRASTE]`. Si sigue fallando alguna con su token, **pará y reportalo**: el token de hoy tampoco alcanza sobre el fondo nuevo, y eso es una decisión de diseño, no un ajuste.

- [ ] **Step 13: Mirar, en los dos temas**

Compará con `tmp/screenshots-antes-2a/` las pantallas con avisos: `04-challenge.png` (el de «Falta resolver» sólo aparece si el desafío tiene errores de configuración), `05b-form.png` o la del editor de campos, `07-idea.png`/edición, `10b-criteria-editor.png`, y el flash de un redirect en cualquier captura posterior a una acción. Y `90-oscuro-*.png`. Revisá especialmente los cuatro que envolviste en `%div`: el texto tiene que leerse corrido, no en columnas.

- [ ] **Step 14: Commit**

```bash
git add -A
git commit -F - <<'MSG'
Los avisos son `alert` de DaisyUI

El flash de un redirect cambia en el helper; los diez avisos fijos de las
vistas y los siete de las islas, a mano. `alert-soft` y no la variante sólida:
los avisos de hoy son suaves, y la sólida los vuelve bloques de color.

`alert` es `display: grid` con `grid-auto-flow: column`, así que un aviso con
varios hijos los repartía en columnas —«Guardar no pisa… | v3 | y la
anterior…» en tres—. Los cuatro que tenían varios hijos los envuelven en un
`div`.

[Completá con el resultado del Step 11: qué variantes no llegaban a 4,5:1, en
qué tema, y con qué token se ajustaron. O «las tres llegaban sin ajuste».]

La aserción de los popups miraba que no apareciera `flash--notice` en el body,
que con los avisos en `alert` no aparece nunca: pasaba sin probar nada. Ahora
mira el hijo directo de `.app-main`, y se verificó que falla pintando el flash
de la IA a propósito.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

Antes de commitear, **reemplazá el párrafo entre corchetes** con lo que pasó de verdad.

---

### Task 5: Los chips pasan a `badge`

**Files:**
- Modify: `app/helpers/estilos_helper.rb` (`CHIP_DE_ESTADO`, `CHIP_DE_ORIGEN`, `CLASE_DE_FEEDBACK`, nace `CHIP_DE_IA` y `chip_de_ia`)
- Test: `spec/helpers/estilos_helper_spec.rb`
- Modify (`status-chip` escrito a mano, 10): `app/views/ideas/show.html.haml:21,117,126` · `app/views/shared/_feedback_item.html.haml:35` · `app/views/steps/_asignaciones_evaluadores.html.haml:26` · `app/views/steps/evolution.html.haml:44,46` · `app/views/steps/reporting.html.haml:41,43,45`
- Modify (`ai-chip` escrito a mano, 12 en 9 archivos): `app/views/assessments/_criterion_field.html.haml:51` · `app/views/assessments/new.html.haml:19,82` · `app/views/ideas/_list.html.haml:13` · `app/views/ideas/show.html.haml:147` · `app/views/shared/_ai_actions.html.haml:15` · `app/views/shared/_ai_suggestions.html.haml:30` · `app/views/shared/_feedback_item.html.haml:15` · `app/views/steps/evaluation.html.haml:35,120` · `app/views/steps/reporting.html.haml:56,102`
- Modify: `app/javascript/components/pipeline_builder/pipeline_builder.vue:224`
- Modify: `app/assets/stylesheets/application.css` (sólo si la guarda de contraste lo pide)
- Modify: `CLAUDE.md` («Tailwind escanea texto…»)

**Interfaces:**
- Consumes: `revisarContraste` (Tarea 3).
- Produces: `EstilosHelper::CHIP_DE_ESTADO`, `CHIP_DE_ORIGEN`, `CLASE_DE_FEEDBACK` con valores `badge …`; `EstilosHelper::CHIP_DE_IA` (String) y `chip_de_ia` → String.

- [ ] **Step 1: Reescribir el spec del helper**

Las guardas contra cada enum comparaban con `end_with("--#{estado}")`. Con `badge`, varios estados devuelven **la misma** clase (`draft`, `pending`, `closed` y `archived` son todos el neutro), así que el sufijo deja de existir. Lo que protegen —que un estado nuevo no caiga al fallback sin que nadie lo vea— se prueba mejor preguntando si el estado es **clave** del hash.

Reemplazá `spec/helpers/estilos_helper_spec.rb` entero por:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EstilosHelper, type: :helper do
  it "devuelve el nombre completo, no un fragmento" do
    expect(helper.chip_de_estado("completed")).to eq("badge badge-soft badge-success badge-sm font-semibold whitespace-nowrap")
  end

  # Sin esto, un estado nuevo dejaría el elemento sin ninguna clase y el
  # síntoma sería un chip invisible en vez de un error.
  it "cae al neutro con un estado que no conoce" do
    neutro = EstilosHelper::CHIP_DE_ESTADO.fetch("pending")
    expect(helper.chip_de_estado("inventado")).to eq(neutro)
    expect(helper.chip_de_estado(nil)).to eq(neutro)
  end

  it "acepta símbolos igual que strings" do
    expect(helper.chip_de_estado(:active)).to eq(helper.chip_de_estado("active"))
  end

  it "traduce una corrida de IA sin que la vista sepa el ternario" do
    ok = instance_double("AiRun", succeeded?: true, failed?: false)
    mal = instance_double("AiRun", succeeded?: false, failed?: true)
    curso = instance_double("AiRun", succeeded?: false, failed?: false)

    expect(helper.chip_de_corrida_de_ia(ok)).to eq(helper.chip_de_estado("completed"))
    expect(helper.chip_de_corrida_de_ia(mal)).to eq(helper.chip_de_estado("skipped"))
    expect(helper.chip_de_corrida_de_ia(curso)).to eq(helper.chip_de_estado("pending"))
  end

  it "pinta el flash de un redirect como alert" do
    expect(helper.clase_de_flash("notice")).to eq("alert alert-soft alert-success")
    expect(helper.clase_de_flash("alert")).to eq("alert alert-soft alert-error")
  end

  # Todas las familias de chip son `badge`. Un valor que quedó con el nombre
  # viejo (`status-chip`, `source-chip`…) se ve bien mientras la hoja todavía
  # tiene su regla, y se rompe en silencio el día que la Tarea 7 la borra.
  it "todos los chips son badge" do
    chips = [EstilosHelper::CHIP_DE_ESTADO, EstilosHelper::CHIP_DE_ORIGEN, EstilosHelper::CLASE_DE_FEEDBACK]
            .flat_map(&:values) << EstilosHelper::CHIP_DE_IA
    chips.each { |clase| expect(clase).to start_with("badge "), "«#{clase}» no es un badge" }
  end

  it "el chip de IA es uno solo" do
    expect(helper.chip_de_ia).to eq("badge badge-soft badge-secondary badge-xs font-bold tracking-wide")
  end

  # Escritos contra el ENUM y no contra una lista a mano: así un estado que
  # alguien agregue mañana al modelo rompe este spec en vez de pintarse con el
  # color del fallback.
  #
  # Contra las CLAVES del hash y no contra el sufijo de la clase: con `badge`
  # varios estados comparten la misma clase —el neutro—, así que la clase ya
  # no dice qué estado la pidió. Que el estado sea clave es exactamente «no cae
  # al fallback».
  def sin_mapear(enum, mapa) = enum.map(&:to_s) - mapa.keys

  it "cubre todos los estados de un desafío" do
    expect(sin_mapear(Challenge::STATUSES, EstilosHelper::CHIP_DE_ESTADO)).to be_empty
  end

  it "cubre todos los estados de un módulo" do
    expect(sin_mapear(ChallengeStep::STATUSES, EstilosHelper::CHIP_DE_ESTADO)).to be_empty
  end

  it "cubre todos los orígenes de un criterio" do
    expect(sin_mapear(Criterion::SOURCES, EstilosHelper::CHIP_DE_ORIGEN)).to be_empty
  end

  it "cubre todos los tipos de feedback" do
    expect(sin_mapear(FeedbackItem::KINDS, EstilosHelper::CLASE_DE_FEEDBACK)).to be_empty
  end

  it "cubre todos los estados de una entrada de módulo" do
    expect(sin_mapear(StepEntry::STATUSES, EstilosHelper::CLASE_DE_RESULTADO)).to be_empty
  end

  it "cubre todos los estados de un módulo en el mapa del flujo" do
    expect(sin_mapear(ChallengeStep::STATUSES, EstilosHelper::CLASE_DE_NODO_DE_FLUJO)).to be_empty
  end

  # `pipeline_builder.vue` pinta el chip de un módulo recién agregado —que
  # todavía no pasó por `PipelinePresenter`— con la cadena escrita a mano.
  # Tiene que ser la MISMA que devuelve el helper para "pending", o un módulo
  # nuevo se ve distinto de uno guardado.
  it "el builder usa el mismo chip de pendiente que el helper" do
    vue = File.read(Rails.root.join("app/javascript/components/pipeline_builder/pipeline_builder.vue"))
    expect(vue).to include("statusClass: '#{EstilosHelper::CHIP_DE_ESTADO.fetch("pending")}'")
  end
end
```

- [ ] **Step 2: Verlo fallar**

Run: `make spec-file FILE=spec/helpers/estilos_helper_spec.rb`
Expected: FAIL en «devuelve el nombre completo», «todos los chips son badge» y «el chip de IA es uno solo» (`uninitialized constant EstilosHelper::CHIP_DE_IA`). Las de «cubre todos…» y «el builder usa el mismo chip» **pasan**: prueban invariantes que hoy se cumplen y que el cambio no puede romper.

- [ ] **Step 3: El helper**

En `app/helpers/estilos_helper.rb`, reemplazá `CHIP_DE_ESTADO`, `CHIP_DE_ORIGEN` y `CLASE_DE_FEEDBACK` (con sus comentarios) por:

```ruby
  # Los chips son `badge` de DaisyUI, en su variante suave, y el color lo
  # decide el grupo al que pertenece el estado —el mismo agrupamiento que
  # tenía la hoja—:
  #
  #   neutro   draft · pending · closed · archived
  #   acento   running · active · activating         → badge-primary
  #   ok       completed                             → badge-success
  #   warn     skipped                               → badge-warning
  #
  # Cubre dos enums a la vez: ChallengeStep::STATUSES y Challenge::STATUSES.
  # Cada valor va ENTERO y literal: Tailwind escanea texto, y una clase armada
  # con interpolación no llega a la hoja.
  #
  # `badge-sm` porque los chips tenían 11px de letra; `font-semibold` y
  # `whitespace-nowrap` porque los tenían, y el `badge` no.
  CHIP_DE_ESTADO = {
    "pending" => "badge badge-soft badge-sm font-semibold whitespace-nowrap",
    "draft" => "badge badge-soft badge-sm font-semibold whitespace-nowrap",
    "closed" => "badge badge-soft badge-sm font-semibold whitespace-nowrap",
    "archived" => "badge badge-soft badge-sm font-semibold whitespace-nowrap",
    "active" => "badge badge-soft badge-primary badge-sm font-semibold whitespace-nowrap",
    "activating" => "badge badge-soft badge-primary badge-sm font-semibold whitespace-nowrap",
    "running" => "badge badge-soft badge-primary badge-sm font-semibold whitespace-nowrap",
    "completed" => "badge badge-soft badge-success badge-sm font-semibold whitespace-nowrap",
    "skipped" => "badge badge-soft badge-warning badge-sm font-semibold whitespace-nowrap"
  }.freeze

  # `badge-xs` porque tenían 10px de letra; `ml-1.5` es el `margin-left: 6px`
  # que los separaba del nombre del criterio.
  CHIP_DE_ORIGEN = {
    "manual" => "badge badge-soft badge-primary badge-xs font-semibold whitespace-nowrap ml-1.5",
    "automatic" => "badge badge-soft badge-success badge-xs font-semibold whitespace-nowrap ml-1.5",
    "ai" => "badge badge-soft badge-secondary badge-xs font-semibold whitespace-nowrap ml-1.5",
    "formula" => "badge badge-soft badge-warning badge-xs font-semibold whitespace-nowrap ml-1.5"
  }.freeze

  # Las claves son FeedbackItem::KINDS tal cual las declara el modelo. Van en
  # mayúsculas y en negrita, como iban.
  CLASE_DE_FEEDBACK = {
    "suggestion" => "badge badge-soft badge-primary badge-xs font-bold uppercase",
    "question" => "badge badge-soft badge-warning badge-xs font-bold uppercase",
    "issue" => "badge badge-soft badge-error badge-xs font-bold uppercase"
  }.freeze

  # La marca de IA. Estaba escrita a mano en nueve vistas; como `badge` serían
  # cinco clases repetidas nueve veces, que es justo lo que «si aparece en más
  # de dos vistas es un componente» existe para evitar.
  CHIP_DE_IA = "badge badge-soft badge-secondary badge-xs font-bold tracking-wide"
```

Y junto a los otros métodos de una línea (después de `def clase_de_feedback…`):

```ruby
  def chip_de_ia = CHIP_DE_IA
```

- [ ] **Step 4: Ver pasar el helper, y fallar el builder**

Run: `make spec-file FILE=spec/helpers/estilos_helper_spec.rb`
Expected: todo en verde **salvo** «el builder usa el mismo chip de pendiente que el helper», que ahora falla: el `.vue` todavía tiene la cadena vieja. Ésa es la prueba de que la guarda funciona.

- [ ] **Step 5: El builder**

En `app/javascript/components/pipeline_builder/pipeline_builder.vue:224`:

```js
        statusClass: 'badge badge-soft badge-sm font-semibold whitespace-nowrap',
```

Run: `make spec-file FILE=spec/helpers/estilos_helper_spec.rb`
Expected: PASS entero.

- [ ] **Step 6: Los `status-chip` escritos a mano pasan por el helper**

Cada uno pasa a `%span{ class: chip_de_estado("…") }`, con el estado que tenía de modificador y el mismo texto:

| Archivo:línea | Después |
|---|---|
| `ideas/show.html.haml:21` | `%span{ class: chip_de_estado("pending") } Borrador` |
| `ideas/show.html.haml:117` | `%span{ class: chip_de_estado("active") } en curso` |
| `ideas/show.html.haml:126` | `%span{ class: chip_de_estado("skipped") }= t("flow.statuses.#{paso.status}").downcase` |
| `shared/_feedback_item.html.haml:35` | `%span{ class: chip_de_estado("completed") }= item.resolution_label` |
| `steps/_asignaciones_evaluadores.html.haml:26` | `%span{ class: chip_de_estado("active") } con pesos` |
| `steps/evolution.html.haml:44` | `%span{ class: chip_de_estado("completed") } actualizada` |
| `steps/evolution.html.haml:46` | `%span{ class: chip_de_estado("pending") }= "#{open_items.size} sin atender"` |
| `steps/reporting.html.haml:41` | `%span{ class: chip_de_estado("completed") } listo` |
| `steps/reporting.html.haml:43` | `%span{ class: chip_de_estado("skipped") } falló` |
| `steps/reporting.html.haml:45` | `%span{ class: chip_de_estado("active") } generando…` |

Mantené la indentación de cada línea.

- [ ] **Step 7: Los `ai-chip` escritos a mano pasan por el helper**

```bash
git grep -l '%span\.ai-chip' -- 'app/views/**/*.haml' | xargs perl -pi -e 's/%span\.ai-chip(?=[ =])/%span{ class: chip_de_ia }/g'
git grep -nE 'ai-chip|status-chip|source-chip|feedback-kind' -- app/views app/javascript app/helpers app/presenters
```

Expected de la búsqueda: sin salida. (`%span.ai-chip IA` queda `%span{ class: chip_de_ia } IA`, y `%span.ai-chip= suggestions.size` queda `%span{ class: chip_de_ia }= suggestions.size`.)

`app/presenters/pipeline_presenter.rb:12` tiene un **comentario** que menciona `status-chip--${step.status}` como ejemplo de lo que no hay que hacer: si la búsqueda lo muestra, es ése, y cambiá el ejemplo a `badge-${color}`.

- [ ] **Step 8: Recompilar y medir**

```bash
make yarn-build
make spec
make screens
```

Expected: `make spec` en verde. `make screens` probablemente **falla con `[CONTRASTE]`** en `badge-success`, `badge-warning` o `badge-error`. Anotá cuáles y en qué tema.

- [ ] **Step 9: Ajustar sólo las que la guarda marcó**

Igual que en la Tarea 4, al lado de las reglas de `.alert-soft`:

```css
/* `badge-soft` pinta el texto con el color puro del tema, y en estas
   variantes no llega a 4,5:1 (lo mide `make screens`). Se oscurece con el
   mismo token que usaba el chip antes de ser `badge`. */
.badge-soft.badge-success { color: var(--ok); }
.badge-soft.badge-warning { color: var(--warn); }
.badge-soft.badge-error { color: var(--danger); }
```

Sólo las líneas que fallaron. `primary` y `secondary` nunca se mezclaron para el texto de un chip (`--accent` e `--ia` son el color del tema tal cual) y deberían pasar; si alguna no pasa, **pará y reportalo**.

```bash
make yarn-build
make screens
```

Expected: en verde, sin `[CONTRASTE]`.

- [ ] **Step 10: Mirar, en los dos temas**

Compará con `tmp/screenshots-antes-2a/`: `02-challenges.png` (estado de cada desafío), `04-challenge.png` (estado de cada módulo), `07-idea.png` (borrador, en curso, feedback con su tipo y la marca de IA), `10-criteria.png` (origen de cada criterio), `11-ai-runs.png`, `09-7-step-reporte-de-cierre.png`. Y `90`-`93-oscuro`.

Lo que **cambia a propósito** (spec §2): el radio pasa de píldora a `0.5rem`, y el alto lo fija el tamaño del `badge`. Lo que **no** puede cambiar: el color de cada grupo, que los tipos de feedback sigan en mayúsculas, y que el chip de origen siga separado del nombre del criterio.

- [ ] **Step 11: `CLAUDE.md`**

En «Tailwind escanea texto: una clase interpolada no existe»:
- «Nunca `"status-chip--#{x}"`» → «Nunca `"badge-#{x}"`».
- Reemplazá el párrafo «Cada mapeo se prueba **contra su enum**, y con `end_with` y no `include`…» por:

```markdown
Cada mapeo se prueba **contra su enum**, preguntando si cada estado es clave
del hash (`spec/helpers/estilos_helper_spec.rb`). Antes se comparaba el sufijo
de la clase con `end_with`; con `badge` varios estados comparten la misma clase
—`draft`, `pending`, `closed` y `archived` son el neutro— y el sufijo dejó de
decir qué estado la pidió. Y todo chip empieza con `badge `: un valor que quedó
con el nombre viejo se ve bien hasta que se borra su regla.
```

- [ ] **Step 12: Commit**

```bash
git add -A
git commit -F - <<'MSG'
Los chips son `badge` de DaisyUI

Cuatro familias con la misma forma y cuatro nombres —`status-chip`,
`source-chip`, `feedback-kind`, `ai-chip`— pasan a `badge-soft`, con el color
del grupo que ya tenía cada estado en la hoja. Casi todo cambia en
`EstilosHelper`. Lo que no: diez `status-chip` escritos a mano en las vistas,
que pasan por `chip_de_estado`; doce `ai-chip`, que ganan `chip_de_ia`; y la
cadena del chip de un módulo recién agregado en el builder, que ahora tiene
un spec que la ata a la del helper.

Las guardas del helper contra cada enum comparaban el sufijo de la clase. Con
`badge` varios estados comparten la misma, y el sufijo dejó de existir: ahora
preguntan si el estado es clave del hash, que es lo que querían probar.

[Completá con el resultado del Step 8: qué variantes no llegaban a 4,5:1, en
qué tema, y con qué token se ajustaron.]

Cambia a propósito el radio —de píldora al del tema— y el alto, que lo fija el
tamaño del `badge`. Se conservan con utilidades en el helper lo que el chip
tenía y el `badge` no: el peso, las mayúsculas del feedback, el margen del
origen.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

Antes de commitear, **reemplazá el párrafo entre corchetes** con lo que pasó de verdad.

---

### Task 6: Los nodos del mapa del flujo pasan a `badge`

`.flow-strip` sigue siendo el contenedor, con su reparto en filas (spec §3). Sólo cambian los nodos, y **no** con el mapeo de los chips: cada nodo conserva lo que pinta hoy.

**Files:**
- Modify: `app/helpers/estilos_helper.rb` (`CLASE_DE_NODO_DE_FLUJO`)
- Test: `spec/helpers/estilos_helper_spec.rb`
- Modify: `app/views/challenges/_template_outline.html.haml:10`

**Interfaces:**
- Consumes: `revisarContraste` (Tarea 3).
- Produces: `EstilosHelper::CLASE_DE_NODO_DE_FLUJO` con valores `badge …`.

- [ ] **Step 1: El test que falla**

En `spec/helpers/estilos_helper_spec.rb`, en el ejemplo «todos los chips son badge», sumá `EstilosHelper::CLASE_DE_NODO_DE_FLUJO` a la lista:

```ruby
    chips = [EstilosHelper::CHIP_DE_ESTADO, EstilosHelper::CHIP_DE_ORIGEN, EstilosHelper::CLASE_DE_FEEDBACK,
             EstilosHelper::CLASE_DE_NODO_DE_FLUJO].flat_map(&:values) << EstilosHelper::CHIP_DE_IA
```

Y sumá, antes del último `end`:

```ruby
  # Los nodos pintan los mismos estados que los chips, pero NO con los mismos
  # colores: el chip `skipped` es amarillo; el nodo `skipped` es neutro con el
  # borde punteado. Se respeta lo que pintaba cada uno.
  it "el nodo salteado es punteado, no amarillo" do
    expect(helper.clase_de_nodo_de_flujo("skipped")).to eq("badge badge-dash badge-sm")
  end
```

- [ ] **Step 2: Verlo fallar**

Run: `make spec-file FILE=spec/helpers/estilos_helper_spec.rb`
Expected: FAIL en «todos los chips son badge» (`flow-strip__node … no es un badge`) y en «el nodo salteado es punteado».

- [ ] **Step 3: El helper**

```ruby
  # El mapa compacto del flujo. Mismos estados que los chips, otros colores:
  # cada nodo conserva lo que pintaba antes de ser `badge`.
  #
  #   pending · activating   neutro, con borde
  #   active                 acento, en negrita
  #   completed              ok
  #   skipped                neutro, borde punteado → badge-dash
  CLASE_DE_NODO_DE_FLUJO = {
    "pending" => "badge badge-soft badge-sm",
    "activating" => "badge badge-soft badge-sm",
    "active" => "badge badge-soft badge-primary badge-sm font-semibold",
    "completed" => "badge badge-soft badge-success badge-sm",
    "skipped" => "badge badge-dash badge-sm"
  }.freeze
```

El comentario de arriba de `CLASE_DE_PASO_DE_SETUP` («pintan el MISMO conjunto de estados que los chips, con otra forma. Comparten la clave y no el nombre de clase») sigue siendo cierto: no lo toques.

- [ ] **Step 4: El nodo escrito a mano**

`app/views/challenges/_template_outline.html.haml:10`:

```haml
      %span{ class: clase_de_nodo_de_flujo("pending") }= label
```

```bash
git grep -n 'flow-strip__node' -- app/views app/javascript app/helpers
```

Expected: sin salida.

- [ ] **Step 5: Verificar**

```bash
make spec-file FILE=spec/helpers/estilos_helper_spec.rb
make yarn-build
make spec
make screens
```

Expected: todo en verde. Si `[CONTRASTE]` marca un nodo, el ajuste de `badge-success` de la Tarea 5 ya debería cubrirlo; si no, es `badge-primary` o el neutro, y **pará y reportalo**.

- [ ] **Step 6: Mirar**

Compará `02-challenges.png` y `04-challenge.png` con `tmp/screenshots-antes-2a/`, y `90-oscuro-desafios.png`. En el índice, con siete módulos, **los nodos tienen que seguir repartidos en dos o tres filas** dentro de cada tarjeta, con la flecha `›` entre ellos. El activo, en acento y negrita; los completados, en verde; un salteado, punteado.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -F - <<'MSG'
Los nodos del mapa del flujo son `badge`

`.flow-strip` sigue siendo el contenedor: `steps` de DaisyUI no reparte en
filas, y en el índice cada tarjeta mide unos 300px con hasta siete módulos.
Los nodos sí pasan a `badge`, y no con el mapeo de los chips: el chip
`skipped` es amarillo y el nodo `skipped` es neutro con el borde punteado, así
que cada nodo conserva lo que pintaba. El salteado es `badge-dash`.

La vista previa de una plantilla escribía su nodo a mano; pasa por el helper.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 7: Borrar el CSS que quedó sin nadie que lo use

**Files:**
- Modify: `app/assets/stylesheets/application.css`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Confirmar que ninguna clase vieja tiene usos**

```bash
for c in 'status-chip' 'source-chip' 'feedback-kind' 'ai-chip' 'flow-strip__node' 'flash--' 'step-table'; do
  printf '%-18s ' "$c"; git grep -c "$c" -- app/views app/javascript app/helpers app/presenters | awk -F: '{s+=$2} END {print s+0}'
done
git grep -nP '(?<![-\w])\.flash(?![-\w])' -- app/views app/javascript
```

Expected: todas en `0`, y la última búsqueda sin salida. Si alguna no da 0, **no borres su regla**: volvé a la tarea que la migraba.

- [ ] **Step 2: Borrar las reglas**

En `app/assets/stylesheets/application.css`, borrá **enteros** estos bloques (las líneas son de `master`; ubicalos por el selector):

- `.status-chip { … }` y las cinco reglas `.status-chip--*` (~964-981).
- `.flow-strip__node { … }` y `.flow-strip__node--active`, `--completed`, `--skipped` (~994-1004). **No** borres `.flow-strip` ni `.flow-strip__arrow`: el contenedor sigue.
- `.ai-chip { … }` (~1267-1275).
- `.feedback-kind { … }` y sus tres modificadores (~1538-1541).
- `.source-chip { … }` y sus cuatro modificadores (~1629-1640).
- `.flash { … }`, `.flash--alert`, `.flash--notice` (~761-768) y `.flash--warn` (~1213).
- Cualquier regla `.step-table…` que haya quedado.

Después:

```bash
grep -nE 'status-chip|source-chip|feedback-kind|ai-chip|flow-strip__node|\.flash|step-table' app/assets/stylesheets/application.css
```

Expected: sin salida, salvo comentarios que **expliquen** la migración. Si un comentario describe una regla que ya no existe como si existiera, corregilo.

- [ ] **Step 3: Verificar**

```bash
make yarn-build
make spec
make screens
```

Expected: todo en verde, y **ninguna** línea `[CLASES]`: si una clase vieja siguiera en uso en algún lugar que las búsquedas no vieron, acá se queda sin regla y la guarda la marca.

- [ ] **Step 4: Mirar**

Una pasada rápida por `tmp/screenshots/` contra el resultado de la Tarea 6: nada tendría que cambiar. Si algo cambió, una regla borrada todavía tenía un uso.

- [ ] **Step 5: `CLAUDE.md`**

En «El sistema visual», el párrafo «Esta fase migró la plomería…» queda:

```markdown
La fase 1 migró la plomería, las clases dinámicas, el tema y el shell. El plan
2a pasó el vocabulario que se repite a componentes: las tablas son `table`, los
avisos `alert alert-soft`, los chips y los nodos del mapa del flujo `badge`, y
las tarjetas se llaman `.panel` mientras esperan su `card` + `card-body`. Lo
que sigue —pantalla por pantalla (2b) y las islas Vue (2c)— tiene su plan
cuando le toque. `.step-card`, `.flow-strip` y `.empty-state` siguen siendo
clases propias a propósito: son vocabulario de esta app.
```

Y en «Lo que más fácil se rompe», sumá:

```markdown
- **`badge-soft` y `alert-soft` pintan el texto con el color PURO del tema.**
  La hoja tuvo que oscurecer `success`, `warning` y `error` para el texto de un
  chip (`--ok`, `--warn`, `--danger`), y las variantes suaves no usan esos
  tokens. `make screens` mide el contraste de todo `.badge` y `.alert`,
  compuesto sobre su fondo y en los dos temas (`revisarContraste`), y las
  variantes que no llegaban se ajustan con una regla de dos clases.
- **`alert` es `display: grid` con `grid-auto-flow: column`.** Un aviso con
  varios hijos —un `%strong` y un texto, una lista y un título— los reparte en
  columnas. Envolvé el contenido en un solo `%div`.
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -F - <<'MSG'
Se borra el CSS de los chips, avisos y tablas que ya no usa nadie

Cada regla se borró después de confirmar que su clase no aparece en vistas,
islas, helpers ni presenters. `make screens` es la red: una clase vieja que
siguiera en uso en algún lugar que las búsquedas no vieron se habría quedado
sin regla, y la guarda de clases descartadas la habría marcado.

`.flow-strip` y su flecha se quedan: el contenedor sigue siendo propio.

CLAUDE.md cuenta qué quedó en componentes y qué sigue siendo propio a
propósito, y suma las dos trampas del plan: el texto de las variantes suaves y
el grid de `alert`.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

## Al terminar

- [ ] `git log --oneline master..rediseno-2a` muestra el spec y siete commits.
- [ ] `make spec` y `make screens` en verde sobre la punta.
- [ ] Las capturas `tmp/screenshots-antes-2a/` se pueden borrar.
- [ ] Pedí revisión de la rama entera antes de mergear, y escribí el plan 2b recién con 2a mergeado.
