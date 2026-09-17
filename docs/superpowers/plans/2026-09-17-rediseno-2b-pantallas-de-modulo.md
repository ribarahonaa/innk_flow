# Rediseño 2b: la pantalla del módulo — plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reordenar la cara de ejecución de los cinco módulos en tres zonas —trabajo al centro, consulta a la derecha, ajustes plegados al final—, juntar lo que está partido en la cara de configuración y pasar todo eso de `.panel` a `card` + `card-body`.

**Architecture:** Cada pantalla de módulo llena la columna de referencia con `content_for :referencia` (el mecanismo ya existe y lo usa evaluación). Dos partials de layout nuevos dan la forma: `steps/_ajustes` (el plegable) y `steps/_bloque` (tarjeta suelta o sección adentro de los ajustes). Todo lo plegable es un `<details>`, y un gancho en `application.js` evita que el morph de Turbo lo cierre. Ninguna policy cambia: cada bloque se muda con su guarda.

**Tech Stack:** Rails 7 · HAML · Turbo 8.0.23 (morph) · Tailwind 4 + DaisyUI 5.7.28 (config en CSS) · RSpec · Playwright (`script/capture_screens.js`).

**Spec:** `docs/superpowers/specs/2026-09-17-rediseno-2b-pantallas-de-modulo-design.md`. Leelo entero antes de la primera tarea: las decisiones y sus porqués están ahí, no acá.

**Desvío del spec:** su tarea 3 («Evaluación») se parte en dos (Tareas 3 y 4 de este plan): las tres zonas y el desglose por fila se pueden aprobar por separado, y las zonas son el patrón que copian las Tareas 5 a 8.

## Global Constraints

- Código, comentarios y mensajes de commit **en español**. Los commits terminan con estas dos líneas:
  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_014gkhXcuX5q5pNYj9oZdAZU
  ```
- **Todo corre en Docker.** `make spec`, `make spec-file FILE=…`, `make screens`, `make yarn-build`, `make seed`. Nunca `bundle exec` en el host, y nunca `docker compose exec app bundle exec rspec` (usa el contenedor de desarrollo y todos los request specs dan 403).
- **El contenedor `app` no recompila CSS ni JS solo.** Después de tocar `application.css`, un `.js` o una clase literal en un helper o una vista, `make yarn-build` **antes** de `make screens`.
- **Nombres de clase completos y literales.** Nunca `"badge-#{x}"`. Lo cuida `spec/lint/clases_interpoladas_spec.rb`.
- **No se toca ninguna policy.** Cada bloque que se muda conserva su guarda exacta: `advance?` (modo de IA), `manage_assignments?` (evaluadores), `ChallengePolicy#update_pipeline?` (gestores), `manage_form?` (formulario), `configure?` (criterios). Si algo parece pedir un cambio de permiso, pará y consultá.
- **Contraste del texto: mínimo 4,5:1** en los dos temas. Mezclas `in oklab`.
- **Una regla CSS propia va sin capa** y le gana entera a DaisyUI. La regla de `.card` va **pegada a la de `.panel`**, antes de `.ai-panel`, `.narrative-card` y compañía, para que esas sigan pisando el borde y el fondo.
- **Un `<details>` es el único plegable.** Nada de checkbox ni `hidden` con JS.
- **Una tarjeta es `.card` > `.card-body`.** Nunca `card` sin `card-body` adentro (`[PANEL]` lo rechaza), y nunca una tarjeta adentro de otra: adentro de los ajustes, un bloque es `%section.ajustes__seccion` (lo resuelve `steps/_bloque`).
- **Rama `rediseno-2b`**, que ya tiene el commit del spec.
- **Cada tarea termina con `make spec` y `make screens` en verde, y un commit.** Las tareas que cambian lo que se ve miran las capturas de antes y de después, **en los dos temas**, antes del commit.
- **`CLAUDE.md` se actualiza en el commit que vuelve falsa cada frase.**
- Al terminar cada tarea, **se para y se pregunta** si se sigue con la siguiente.

---

## Mapa de archivos

| Archivo | Qué hace en este plan |
|---|---|
| `app/assets/stylesheets/application.css` | T1: aspecto de `.card`, pares de prosa · T2: se borran los chips a mano · T3: ajustes, `.ai-mode-card` suelta, `.pedido-a-la-ia` · T4: filas de ideas · T10: punto del drawer, borde por `data-kind` · T11: CSS muerto |
| `app/javascript/application.js` | T1: el gancho del `<details>` |
| `script/capture_screens.js` | T1: guardas con `.card`, plegable tras morph, comparación card/panel, pasada oscura de módulos · T2: muestrario · T3–T8: `MODULOS_EN_ZONAS`, captura de ajustes abiertos · T4: captura del desglose · T10: captura del salteado |
| `app/helpers/estilos_helper.rb` | T2: `CHIPS` y `chip(nombre)` · T10: `PUNTO_DE_ESTADO` y `punto_de_estado` |
| `spec/helpers/estilos_helper_spec.rb` | T2, T10 |
| `app/views/steps/_bloque.html.haml` | T3: nuevo |
| `app/views/steps/_ajustes.html.haml` | T3: nuevo |
| `app/views/steps/_progreso.html.haml` | T3: nuevo |
| `app/views/steps/_quien_evalua.html.haml` | T3: nuevo |
| `app/views/steps/_fila_de_evaluacion.html.haml` | T4: nuevo |
| `app/views/steps/_celdas_de_evaluacion.html.haml` | T4: nuevo |
| `app/views/steps/_como_se_decide.html.haml` | T5: nuevo |
| `app/views/steps/_quienes_acompanan.html.haml` | T6: nuevo |
| `app/views/steps/_campos_lista.html.haml` | T7: nuevo |
| `app/views/steps/_campos_lectura.html.haml` | T7: nuevo |
| `app/views/steps/_descargas.html.haml` | T8: nuevo |
| `app/views/steps/{evaluation,selection,evolution,ideation,reporting}.html.haml` | T3–T8 |
| `app/views/steps/_referencia_evaluacion.html.haml` | T3 |
| `app/views/steps/_ai_mode.html.haml` · `_config_congelada` · `_asignaciones_evaluadores` · `_asignaciones_gestores` | T3, T6 |
| `app/views/shared/_ai_suggestions.html.haml` | T3 |
| `app/views/challenges/_gestores.html.haml` | T6 |
| `app/views/steps/_campos_editor.html.haml` | T7 (bloque y lista) · T9 (juntar) |
| `app/views/steps/_criterios_editor.html.haml` · `steps/config/_modulo` | T9 |
| 7 vistas con chips a mano | T2 |
| `app/views/shared/_feedback_item.html.haml` · `layouts/_flow_drawer` | T10 |
| `db/seeds.rb` | T10: desafío `con-salteado` |
| `spec/requests/pantalla_del_modulo_spec.rb` | T3: nuevo · T4–T9 lo extienden |
| `spec/requests/ai_spec.rb` · `participant_rules_spec.rb` | T4: aserciones sobre «Evaluaciones hechas» |
| `CLAUDE.md` | T1, T2, T3, T10, T11 |

---

### Task 1: Plomería — `.card` con el aspecto de `.panel`, guardas que la miran y el gancho del `<details>`

**Sin cambio visible.** Deja todo listo para que la primera `card` real (Tarea 3) nazca medida.

**Files:**
- Modify: `app/assets/stylesheets/application.css` (`.app-main > .panel …` ~523-525; `.panel {` ~746)
- Modify: `app/javascript/application.js`
- Modify: `script/capture_screens.js` (`revisarRitmo` ~107; `revisarClasesDescartadas` ~132; `revisarMuestrario` ~353; después de `capturar(page, '07-idea')` ~751; pasada oscura ~1199)
- Modify: `CLAUDE.md` (sección «Las pantallas se actualizan, no se recargan» y «El sistema visual»)

**Interfaces:**
- Produces: regla `.card` (superficie, borde, radio, sombra, `--card-p: 20px`, `--card-fs: 14px`); `revisarPlegableTrasMorph(page, name, selector)` y `revisarCardComoPanel(page, tema)` en `script/capture_screens.js`. Las Tareas 3 y 4 llaman a `revisarPlegableTrasMorph`.

- [ ] **Step 1: Partir de verde**

```bash
git switch rediseno-2b
make yarn-build
make spec
make screens
```

Expected: `make spec` sin fallas; `make screens` termina con `Sin errores de JS ni respuestas >= 400.` Si no, pará: el punto de partida está roto.

- [ ] **Step 2: Escribir la guarda del plegable y verla fallar**

En `script/capture_screens.js`, debajo de `revisarMorphing`:

```js
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
```

Y después de `await capturar(page, '07-idea');`:

```js
  // Las rondas de feedback cerradas de la ficha de la idea ya se pliegan con
  // <details>: es el plegable que existe desde antes de este plan.
  await revisarPlegableTrasMorph(page, '07-idea', 'details.feedback-round--cerrada');
```

Run: `make screens`
Expected: FAIL con `[PLEGABLE] 07-idea: details.feedback-round--cerrada se cerró al actualizarse la pantalla`. Si dice «no hay ningún…», la idea «Sensores» no tiene una ronda cerrada en el seed: corré `make seed` y repetí. Si pasa en verde, **pará**: la guarda no prueba lo que dice y el gancho del Step 3 no se puede verificar.

- [ ] **Step 3: El gancho**

Al final de `app/javascript/application.js`:

```js
// Un plegable abierto sigue abierto cuando la pantalla se actualiza.
//
// El `open` de un <details> lo pone quien lo abre, en el cliente. Un POST que
// redirige a la misma URL morfea contra el HTML del servidor, que no lo trae,
// e idiomorph lo saca: guardar un peso adentro de «Ajustes del módulo» cerraba
// los ajustes en la cara de quien acababa de guardar. Se cancela solo la
// REMOCIÓN: un `open` que agrega el servidor sigue entrando.
addEventListener('turbo:before-morph-attribute', (event) => {
  const { attributeName, mutationType } = event.detail;
  if (event.target instanceof HTMLDetailsElement && attributeName === 'open' && mutationType === 'remove') {
    event.preventDefault();
  }
});
```

Run: `make yarn-build && make screens`
Expected: sin `[PLEGABLE]`, y en verde.

- [ ] **Step 4: El aspecto de `.card`**

En `app/assets/stylesheets/application.css`, inmediatamente **después** del bloque `.panel { … }` (~746-752):

```css
/* La tarjeta de DaisyUI con el aspecto de `.panel`. El componente trae el
   radio y `display: flex` en columna, y nada más: ni fondo, ni borde, ni
   sombra. Escribir `card-border bg-base-100 shadow-sm` en cada vista sería la
   regla de los componentes al revés, así que el aspecto vive acá, una vez.

   `--card-p` y `--card-fs` son lo que mide `.panel`: 20px de relleno —DaisyUI
   pone 24— y la letra del `body`. Va PEGADA a `.panel` y antes de `.ai-panel`,
   `.narrative-card` y `.ai-mode-card`: con la misma especificidad y sin capa,
   gana la que viene después, y esas tienen que seguir pisando borde y fondo. */
.card {
  --card-p: 20px;
  --card-fs: 14px;
  background: var(--surface);
  border: 1px solid var(--borde);
  border-radius: var(--radius);
  box-shadow: var(--shadow);
}
```

Y los pares de la prosa, en el bloque de `.app-main` (~523):

```css
.app-main > .panel p:not([class]),
.app-main > .panel .muted,
.app-main > .panel .field-hint,
.app-main > .card p:not([class]),
.app-main > .card .muted,
.app-main > .card .field-hint,
.app-main > .page-head p,
.app-main > p { max-width: var(--prosa); }
```

Buscá cualquier otro selector que cuelgue de `.panel` desde afuera y sumale su par:

```bash
grep -nE '\.panel[^-_a-zA-Z]' app/assets/stylesheets/application.css | grep -v '^\s*[0-9]*:\s*/\*'
```

Expected: sólo las tres líneas de arriba y `.panel {`. Si aparece otra, sumale el par con `.card`.

- [ ] **Step 5: Las guardas miran `.card`**

En `revisarRitmo`:

```js
    const paneles = [...document.querySelectorAll('.app-main > .panel, .app-main > .card')];
```

En `revisarClasesDescartadas`, en el selector:

```js
    for (const el of document.querySelectorAll('[class*="badge"],[class*="btn"],[class*="alert"],.steps,.panel,.card,.table :is(th,td)')) {
```

En `revisarMuestrario`, el destino:

```js
    const destino = document.querySelector('.card-body') || document.querySelector('.panel') || document.querySelector('.app-main') || document.body;
```

Y actualizá el comentario de `revisarMuestrario` («Se inyectan en un `.panel`») a «en una tarjeta (`.card-body` o `.panel`)».

- [ ] **Step 6: La guarda que prueba que `.card` se ve como `.panel`**

Debajo de `revisarMuestrario`:

```js
// Mientras convivan `.panel` y `.card`, una tarjeta migrada tiene que verse
// igual que una sin migrar: si no, cada pantalla del plan 2b cambia de aspecto
// por la tarjeta y no por lo que se decidió cambiarle. Se inyectan las dos en
// la pantalla real —con la hoja y el tema de verdad— y se comparan los estilos
// computados. Se borra junto con `.panel`, al final del plan 2b-bis.
async function revisarCardComoPanel(page, tema) {
  const diferencias = await page.evaluate(() => {
    const destino = document.querySelector('.app-main') || document.body;
    const panel = document.createElement('div');
    panel.className = 'panel';
    panel.textContent = 'panel';
    const card = document.createElement('div');
    card.className = 'card';
    const body = document.createElement('div');
    body.className = 'card-body';
    body.textContent = 'card';
    card.appendChild(body);
    destino.append(panel, card);

    const p = getComputedStyle(panel);
    const c = getComputedStyle(card);
    const b = getComputedStyle(body);
    const pares = {
      'background-color': [p.backgroundColor, c.backgroundColor],
      'border-top': [`${p.borderTopWidth} ${p.borderTopStyle} ${p.borderTopColor}`, `${c.borderTopWidth} ${c.borderTopStyle} ${c.borderTopColor}`],
      'border-radius': [p.borderTopLeftRadius, c.borderTopLeftRadius],
      'box-shadow': [p.boxShadow, c.boxShadow],
      'padding': [`${p.paddingTop} ${p.paddingLeft}`, `${b.paddingTop} ${b.paddingLeft}`],
      'font-size': [p.fontSize, b.fontSize]
    };
    panel.remove();
    card.remove();
    return Object.entries(pares).filter(([, [a, z]]) => a !== z).map(([k, [a, z]]) => `${k}: panel ${a} · card ${z}`);
  });
  if (diferencias.length) {
    failures++;
    console.error(`[CARD] ${tema}: la card no se ve como el panel — ${diferencias.join(' | ')}`);
  }
}
```

Llamala junto al muestrario, en los dos temas:

```js
  await revisarMuestrario(page, 'claro');
  await revisarCardComoPanel(page, 'claro');
```

```js
    if (nombre === '90-oscuro-desafios') {
      await revisarMuestrario(page, 'oscuro');
      await revisarCardComoPanel(page, 'oscuro');
    }
```

- [ ] **Step 7: Verla fallar**

Comentá temporalmente `box-shadow: var(--shadow);` de la regla `.card` —la `card` de DaisyUI no trae sombra, así que la diferencia es segura; con el radio no, porque `--radius` y `--radius-box` pueden valer lo mismo—, `make yarn-build && make screens`.
Expected: `[CARD] claro: … box-shadow: panel … · card none`. Devolvé la línea, `make yarn-build`.

- [ ] **Step 8: La pasada oscura recorre las pantallas de módulo**

En la pasada oscura, antes del `for`, armá la lista con los módulos que ya se conocen por link (`stepLinks` está en alcance):

```js
  // Las pantallas de módulo también, que son las que el plan 2b reordena. Por
  // URL, como el resto de esta pasada: esto prueba colores, no navegación.
  const oscuroDeModulos = [
    ['94-oscuro-evaluacion', stepLinks.find((l) => l.text.match(/comit/i))],
    ['95-oscuro-seleccion', stepLinks.find((l) => l.text.match(/Corte a top/i))],
    ['96-oscuro-evolucion', stepLinks.find((l) => l.text.match(/Ronda de feedback/i))],
    ['97-oscuro-reporteria', stepLinks.find((l) => l.text.match(/Reporte/i))]
  ];
  for (const [nombre, link] of oscuroDeModulos) {
    if (!link) {
      failures++;
      console.error(`[LINK] la pasada oscura no encontró el módulo de ${nombre}`);
    }
  }
```

Y sumalos al arreglo del `for`:

```js
  for (const [nombre, url] of [
    ['90-oscuro-desafios', '/challenges'],
    ['91-oscuro-desafio', `/challenges/${CHALLENGE}`],
    ['92-oscuro-criterios', '/criteria_sets'],
    ['93-oscuro-ia', '/admin/ai_runs'],
    ...oscuroDeModulos.filter(([, link]) => link).map(([nombre, link]) => [nombre, link.href])
  ]) {
```

- [ ] **Step 9: Verde, y las capturas de antes**

```bash
make yarn-build
make spec
make screens
rm -rf tmp/screenshots-antes-2b && cp -r tmp/screenshots tmp/screenshots-antes-2b
```

Expected: verde, con `94-oscuro-evaluacion` a `97-oscuro-reporteria` en la lista. `tmp/screenshots-antes-2b/` es la referencia de «antes» de todo el plan.

- [ ] **Step 10: `CLAUDE.md`**

En «Las pantallas se actualizan, no se recargan», sumá un bullet:

```markdown
- **Un `<details>` abierto sobrevive al morph.** El `open` lo pone el
  cliente, y un POST que vuelve a la misma URL morfea contra el HTML del
  servidor, que no lo trae: guardar algo adentro de un plegable lo cerraba.
  `application.js` cancela en `turbo:before-morph-attribute` la REMOCIÓN de
  `open` en un `DETAILS` (un `open` que agrega el servidor sigue entrando).
  Por eso todo lo plegable de la app es un `<details>`: un mecanismo, un
  gancho. Lo prueba `revisarPlegableTrasMorph` en `make screens`.
```

En «Las tres capas, y de quién es cada regla», reemplazá el párrafo que empieza con «`card` de DaisyUI está **habilitada**, y ninguna tarjeta la usa todavía.» por:

```markdown
`card` de DaisyUI está **habilitada**, y el aspecto lo pone la hoja: una
regla `.card` pegada a `.panel` le da superficie, borde, radio y sombra, y
fija `--card-p` y `--card-fs` a lo que mide `.panel`. En las vistas se
escribe `.card` > `.card-body` y nada más. Estuvo excluida porque declara
`display: flex`, y habilitarla convertía de golpe todas las tarjetas en
columnas flex; por eso las tarjetas de la app se llaman **`.panel`** hasta
que cada pantalla pasa a `card` (planes 2b y 2b-bis). `make screens` falla si
aparece un `card` sin `card-body` (`[PANEL]`) y si una `card` no se ve igual
que un `.panel` (`[CARD]`, que se borra con `.panel`).
```

- [ ] **Step 11: Commit**

```bash
git add app/assets/stylesheets/application.css app/javascript/application.js script/capture_screens.js CLAUDE.md
git commit -F - <<'EOF'
Plomería del 2b: la card se ve como el panel, y un plegable no se cierra solo

La regla de `.card` le da el aspecto de `.panel` una sola vez, y una guarda
nueva lo compara en los dos temas. Las guardas de ritmo, de clases y el
muestrario miran también `.card`, para no pasar en verde sin ver la primera
tarjeta migrada. Un gancho en `turbo:before-morph-attribute` evita que el
morph le saque el `open` a un <details>, con su guarda vista fallar sobre las
rondas cerradas de la ficha de la idea. La pasada oscura suma las pantallas de
módulo. Nada de esto se ve.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014gkhXcuX5q5pNYj9oZdAZU
EOF
```

---

### Task 2: Los seis chips escritos a mano pasan a `badge`

**Files:**
- Modify: `app/helpers/estilos_helper.rb`
- Modify: `spec/helpers/estilos_helper_spec.rb`
- Modify: `script/capture_screens.js` (`MUESTRARIO`)
- Modify (vistas): `app/views/steps/evaluation.html.haml` · `steps/_referencia_evaluacion` · `steps/evolution` · `steps/reporting` · `steps/selection` · `ideas/_list` · `ideas/show` · `assessments/new` · `criteria_sets/index` · `challenges/show`
- Modify: `app/assets/stylesheets/application.css` (se borran `.version-chip` ×2, `.stale-chip`, `.here-chip`, `.out-chip`, `.out-chip--pending`, `.evaluator-chip`, `.evaluator-chip--ai`, `.derived-chip`)
- Modify: `CLAUDE.md`

**Interfaces:**
- Produces: `EstilosHelper::CHIPS` (hash) y `chip(nombre)` con las claves `"version"`, `"desactualizada"`, `"aca"`, `"no_pasa"`, `"sin_responder"`, `"derivado"`, `"evaluador"`, `"evaluador_ia"`. `chip` levanta `KeyError` con una clave desconocida: las claves son código, no datos del dominio. Las Tareas 3 y 4 usan `chip("version")`, `chip("desactualizada")`, `chip("derivado")`, `chip("evaluador")` y `chip("evaluador_ia")`.

| Hoy | Clave | `badge` |
|---|---|---|
| `version-chip` (neutro, borde, mono, 10-11px, `margin-left: 6px`) | `version` | `badge badge-soft badge-xs font-mono font-semibold ml-1.5` |
| `stale-chip` (warn suave, 10px, 600, `margin-left: 4px`) | `desactualizada` | `badge badge-soft badge-warning badge-xs font-semibold ml-1` |
| `here-chip` (acento sólido, 10px, 600, `margin-left: 8px`) | `aca` | `badge badge-primary badge-xs font-semibold whitespace-nowrap ml-2` |
| `out-chip` (danger suave) | `no_pasa` | `badge badge-soft badge-error badge-xs font-semibold whitespace-nowrap ml-2` |
| `out-chip out-chip--pending` (warn suave) | `sin_responder` | `badge badge-soft badge-warning badge-xs font-semibold whitespace-nowrap ml-2` |
| `derived-chip` (acento suave, 700, `margin-left: 6px`) | `derivado` | `badge badge-soft badge-primary badge-xs font-bold ml-1.5` |
| `evaluator-chip` (círculo de 20px, iniciales) | `evaluador` | `badge badge-soft badge-xs font-semibold` |
| `evaluator-chip evaluator-chip--ai` | `evaluador_ia` | `badge badge-soft badge-secondary badge-xs font-semibold` |

`evaluator-chip` deja de ser un círculo y pasa al radio del tema, igual que los chips del 2a: que el componente mande sobre la forma es lo que el rediseño compra. Si en la captura las iniciales quedan ilegibles o se parten, **pará y consultá** antes de dejarlo propio.

- [ ] **Step 1: Los specs que fallan**

En `spec/helpers/estilos_helper_spec.rb`, arriba del primer `it`, un método para no repetir la lista de chips (hoy está copiada en dos `it`):

```ruby
  # Toda clase de chip que devuelve el helper. Una sola lista: estaba copiada
  # en dos specs, y un chip nuevo sumado a una y no a la otra quedaba sin medir.
  def todos_los_chips
    [EstilosHelper::CHIP_DE_ESTADO, EstilosHelper::CHIP_DE_ORIGEN, EstilosHelper::CLASE_DE_FEEDBACK,
     EstilosHelper::CLASE_DE_NODO_DE_FLUJO, EstilosHelper::CHIPS].flat_map(&:values) << EstilosHelper::CHIP_DE_IA
  end
```

Reemplazá el cuerpo de `it "todos los chips son badge"` por:

```ruby
    todos_los_chips.each { |clase| expect(clase).to start_with("badge "), "«#{clase}» no es un badge" }
```

En `it "el muestrario de las capturas tiene cada chip del helper"`, reemplazá las dos líneas que arman `chips` por:

```ruby
    faltan = todos_los_chips.uniq - muestrario
```

Y sumá:

```ruby
  # Las marcas sueltas se piden por nombre, no por estado: un nombre mal
  # escrito es un error de código y tiene que reventar, no pintar un neutro.
  it "una marca que no existe revienta en vez de caer a un default" do
    expect { helper.chip("versión") }.to raise_error(KeyError)
  end

  it "la marca de fuera del corte y la de sin responder no se confunden" do
    expect(helper.chip("no_pasa")).to include("badge-error")
    expect(helper.chip("sin_responder")).to include("badge-warning")
  end
```

Run: `make spec-file FILE=spec/helpers/estilos_helper_spec.rb`
Expected: FAIL con `uninitialized constant EstilosHelper::CHIPS`.

- [ ] **Step 2: El helper**

En `app/helpers/estilos_helper.rb`, debajo de `CHIP_DE_IA`:

```ruby
  # Las marcas que no traducen un estado sino que dicen algo suelto de un
  # elemento: su versión, que quedó vieja, que no pasa un filtro, quién evaluó.
  # Estaban escritas a mano, cada una con su CSS, y la guarda de contraste no
  # las medía. Se piden por NOMBRE y un nombre que no existe revienta: es un
  # error de código, no un dato del dominio que pueda venir nuevo.
  #
  # Los `ml-*` son los `margin-left` que tenían. `evaluador` deja de ser un
  # círculo: toma el radio del tema, como el resto de los chips.
  CHIPS = {
    "version" => "badge badge-soft badge-xs font-mono font-semibold ml-1.5",
    "desactualizada" => "badge badge-soft badge-warning badge-xs font-semibold ml-1",
    "aca" => "badge badge-primary badge-xs font-semibold whitespace-nowrap ml-2",
    "no_pasa" => "badge badge-soft badge-error badge-xs font-semibold whitespace-nowrap ml-2",
    "sin_responder" => "badge badge-soft badge-warning badge-xs font-semibold whitespace-nowrap ml-2",
    "derivado" => "badge badge-soft badge-primary badge-xs font-bold ml-1.5",
    "evaluador" => "badge badge-soft badge-xs font-semibold",
    "evaluador_ia" => "badge badge-soft badge-secondary badge-xs font-semibold"
  }.freeze
```

Y con los demás métodos:

```ruby
  def chip(nombre) = CHIPS.fetch(nombre.to_s)
```

- [ ] **Step 3: El muestrario**

En `script/capture_screens.js`, al final del arreglo `MUESTRARIO` (antes de `];`):

```js
  // Las marcas sueltas (`EstilosHelper::CHIPS`).
  'badge badge-soft badge-xs font-mono font-semibold ml-1.5',
  'badge badge-soft badge-warning badge-xs font-semibold ml-1',
  'badge badge-primary badge-xs font-semibold whitespace-nowrap ml-2',
  'badge badge-soft badge-error badge-xs font-semibold whitespace-nowrap ml-2',
  'badge badge-soft badge-warning badge-xs font-semibold whitespace-nowrap ml-2',
  'badge badge-soft badge-primary badge-xs font-bold ml-1.5',
  'badge badge-soft badge-xs font-semibold',
  'badge badge-soft badge-secondary badge-xs font-semibold'
```

Run: `make spec-file FILE=spec/helpers/estilos_helper_spec.rb`
Expected: PASS.

- [ ] **Step 4: Las vistas**

Reemplazos exactos (buscá cada uno con `grep -rn` antes de tocar):

| Archivo | Antes | Después |
|---|---|---|
| `steps/evaluation.html.haml` | `%span.evaluator-chip{ class: ("evaluator-chip--ai" if assessment.by_ai?),` | `%span{ class: chip(assessment.by_ai? ? "evaluador_ia" : "evaluador"),` |
| `steps/evaluation.html.haml` | `%span.version-chip= assessment.idea_version.label` | `%span{ class: chip("version") }= assessment.idea_version.label` |
| `steps/evaluation.html.haml` | `%span.stale-chip= "la idea ya va por …"` | `%span{ class: chip("desactualizada") }= "la idea ya va por …"` |
| `steps/evaluation.html.haml` | `%span.stale-chip= score.error` | `%span{ class: chip("desactualizada") }= score.error` |
| `steps/_referencia_evaluacion.html.haml` | `%span.derived-chip derivado` | `%span{ class: chip("derivado") } derivado` |
| `steps/evolution.html.haml` | `%span.version-chip= entry.idea.current_version&.label` | `%span{ class: chip("version") }= entry.idea.current_version&.label` |
| `steps/reporting.html.haml` | `%span.version-chip= row["version"]` | `%span{ class: chip("version") }= row["version"]` |
| `steps/reporting.html.haml` | `%span.stale-chip{ title: … }` | `%span{ class: chip("desactualizada"), title: … }` |
| `steps/reporting.html.haml` | `%span.version-chip= cell["version"]` | `%span{ class: chip("version") }= cell["version"]` |
| `steps/selection.html.haml` | `%span.out-chip{ title: … }` | `%span{ class: chip("no_pasa"), title: … }` |
| `steps/selection.html.haml` | `%span.out-chip.out-chip--pending= …` | `%span{ class: chip("sin_responder") }= …` |
| `ideas/_list.html.haml` | `%span.version-chip= idea.current_version&.label` | `%span{ class: chip("version") }= idea.current_version&.label` |
| `ideas/show.html.haml` (2) | `%span.version-chip= …` | `%span{ class: chip("version") }= …` |
| `assessments/new.html.haml` | `%span.version-chip= @idea.current_version&.label` | `%span{ class: chip("version") }= @idea.current_version&.label` |
| `criteria_sets/index.html.haml` | `%span.version-chip{ title: … }= "v#{set.version}"` | `%span{ class: chip("version"), title: … }= "v#{set.version}"` |
| `challenges/show.html.haml` | `%span.here-chip acá está el flujo` | `%span{ class: chip("aca") } acá está el flujo` |

Verificá que no quedó ninguno, en vistas, islas y el script de capturas:

```bash
grep -rnE 'version-chip|stale-chip|here-chip|out-chip|evaluator-chip|derived-chip' app script spec
```

Expected: sin salida fuera de `application.css`.

- [ ] **Step 5: Borrar el CSS**

En `app/assets/stylesheets/application.css`, borrá las reglas enteras (con su comentario si es sólo de ellas): `.version-chip` (las dos, ~1227 y ~2432), `.stale-chip` (~1516), `.here-chip` (~2483), `.out-chip` y `.out-chip--pending` (~2502-2513), `.evaluator-chip` y `.evaluator-chip--ai` (~1636-1650), `.derived-chip` (~1354). **No** borres `.evaluators` (el contenedor de las iniciales).

```bash
grep -nE 'version-chip|stale-chip|here-chip|out-chip|evaluator-chip|derived-chip' app/assets/stylesheets/application.css
```

Expected: sin salida.

- [ ] **Step 6: Verde, y mirar**

```bash
make yarn-build
make spec
make screens
```

Expected: verde, sin `[CONTRASTE]` (el muestrario mide los ocho en los dos temas). Si alguno no llega a 4,5:1, ajustalo como en el 2a, con una regla de dos clases y el token oscurecido que ya existe (`.badge-soft.badge-warning { color: var(--warn); }` ya está; buscá antes de sumar).

Mirá lado a lado, contra `tmp/screenshots-antes-2b/`: `09-3-step-evaluaci-n-t-cnica` (iniciales, versión, desactualizada), `09-4-step-corte-a-top-3` (no pasa), `09-7-step-reporte-de-cierre` (versión, →), `04-challenge` (acá está el flujo), `06-ideas`, `10-criteria` y `97-oscuro-reporteria`.

- [ ] **Step 7: `CLAUDE.md`**

En «El sistema visual», reemplazá:

```markdown
Otros chips
(`version-chip`, `stale-chip`, `here-chip`, `out-chip`, `evaluator-chip`,
`derived-chip`) siguen escritos a mano: la guarda de contraste no los mide, y
son candidatos del plan 2b.
```

por:

```markdown
Las marcas sueltas —versión, desactualizada, «acá está el flujo», no pasa un
filtro, filtros sin responder, derivado, las iniciales de quien evaluó— son
`badge` vía `EstilosHelper::CHIPS`, y se piden por nombre con `chip("version")`:
un nombre que no existe revienta, porque es un error de código y no un estado
nuevo del dominio.
```

- [ ] **Step 8: Commit**

```bash
git add app/helpers/estilos_helper.rb spec/helpers/estilos_helper_spec.rb script/capture_screens.js app/views app/assets/stylesheets/application.css CLAUDE.md
git commit -F - <<'EOF'
Los seis chips escritos a mano pasan a badge

Versión, desactualizada, «acá está el flujo», no pasa un filtro, sin
responder, derivado y las iniciales de quien evaluó eran CSS a mano que la
guarda de contraste no medía. Pasan a `EstilosHelper::CHIPS`, se piden por
nombre y entran al muestrario, que los mide en claro y en oscuro. Las
iniciales dejan de ser un círculo y toman el radio del tema, como el resto.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014gkhXcuX5q5pNYj9oZdAZU
EOF
```

---

### Task 3: Evaluación — las tres zonas

La pantalla de evaluación pasa a tener la forma que copian las demás: la referencia completa, el trabajo en una `card` y los ajustes plegados al final. **El desglose por fila es la Tarea 4**: acá «Evaluaciones hechas» sigue como está, sólo pasa a `card`.

**Files:**
- Create: `app/views/steps/_bloque.html.haml`
- Create: `app/views/steps/_ajustes.html.haml`
- Create: `app/views/steps/_progreso.html.haml`
- Create: `app/views/steps/_quien_evalua.html.haml`
- Create: `spec/requests/pantalla_del_modulo_spec.rb`
- Modify: `app/views/steps/evaluation.html.haml` (entero)
- Modify: `app/views/steps/_referencia_evaluacion.html.haml` (entero)
- Modify: `app/views/steps/_ai_mode.html.haml`
- Modify: `app/views/steps/_config_congelada.html.haml`
- Modify: `app/views/steps/_asignaciones_evaluadores.html.haml`
- Modify: `app/views/shared/_ai_suggestions.html.haml`
- Modify: `app/assets/stylesheets/application.css`
- Modify: `script/capture_screens.js`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: `revisarPlegableTrasMorph` (Tarea 1); `chip("derivado")` (Tarea 2).
- Produces, para las Tareas 4 a 9:
  - `render layout: "steps/ajustes", locals: { resumen: String } do … end` — la tarjeta plegable; su contenido va adentro del `<details>`.
  - `render layout: "steps/bloque", locals: { tarjeta: Boolean } do … end` — `.card > .card-body` con `tarjeta: true` (default), `%section.ajustes__seccion` con `false`.
  - `render "steps/progreso", progress: Progress, detalle: String (opcional)`.
  - `render "steps/config_congelada", step:` — ahora `.card`.
  - `render "steps/ai_mode", step:` — ahora `.ai-mode-card` suelta, sin `.panel`.
  - `render "steps/asignaciones_evaluadores", step:, assignable:, tarjeta: Boolean`.
  - `const MODULOS_EN_ZONAS` en `script/capture_screens.js`: arreglo de regex sobre el nombre del módulo; cada tarea suma el suyo.
  - `spec/requests/pantalla_del_modulo_spec.rb` con `member(email, role)`, `paso(kind)` y `zonas` (hash con `:referencia` y `:ajustes`, texto de cada zona).

- [ ] **Step 1: El spec que falla**

Create `spec/requests/pantalla_del_modulo_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# La cara de ejecución de un módulo en tres zonas: el trabajo al centro, lo
# que se consulta a la derecha (`.app-aside`) y los ajustes plegados al final
# (`.ajustes`). Es markup, no permisos: mudar un bloque de lugar no puede
# sacarlo de atrás de su guarda, y un spec que solo mira a quien administra no
# lo ve. Por eso cada zona se prueba por rol.
RSpec.describe "la pantalla del módulo en tres zonas", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email, role)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, role.to_sym, company: company, user: u)
      u
    end
  end

  let!(:admin) { member("admin@test.dev", :admin) }
  let!(:elena) { member("elena@test.dev", :evaluator) }
  let!(:paula) { member("paula@test.dev", :participant) }

  def paso(kind) = as_company(company) { challenge.steps.reload.find { |s| s.kind == kind } }

  def documento = Nokogiri::HTML(response.body)

  # El texto de cada zona, leído del HTML servido.
  def zonas
    { referencia: documento.at_css(".app-aside")&.text.to_s,
      ajustes: documento.at_css(".ajustes")&.text.to_s }
  end

  def postular!(challenge, author:, titulo:)
    as_company(company) do
      i = create(:idea, challenge: challenge, author: author)
      Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => titulo }, author: author).call
      i.update!(submitted_at: Time.current)
      i
    end
  end

  describe "evaluación" do
    let!(:challenge) do
      as_company(company) do
        c = create(:challenge, name: "Merma", ai_default_mode: "human")
        seed_form!(c.steps.create!(kind: "ideation", position: 1))
        c.steps.create!(kind: "evaluation", position: 2, name: "Técnica", config: { "min_assessments" => 1 })
        c
      end
    end

    before do
      postular!(challenge, author: paula, titulo: "Sensores")
      as_company(company) do
        challenge.pipeline.start!
        challenge.pipeline.advance!
      end
    end

    it "quien administra: consulta a la derecha y los ajustes plegados" do
      sign_in(admin, company: company)
      get challenge_step_path(challenge, paso("evaluation"))

      expect(zonas[:referencia]).to include("Progreso", "Criterios", "Quién evalúa", elena.name, "Cómo quedó configurado")
      expect(zonas[:ajustes]).to include("Ajustes del módulo", "Modo de IA", "Peso")
      expect(documento.at_css(".ajustes details.ajustes__plegable")).not_to be_nil
    end

    it "quien evalúa: la referencia sin la lista de asignaciones, y sin ajustes" do
      sign_in(elena, company: company)
      get challenge_step_path(challenge, paso("evaluation"))

      expect(zonas[:referencia]).to include("Progreso", "Criterios", "Cómo quedó configurado")
      expect(zonas[:referencia]).not_to include("Quién evalúa")
      expect(documento.at_css(".ajustes")).to be_nil
    end

    it "quien participa: tampoco ve asignaciones ni ajustes" do
      sign_in(paula, company: company)
      get challenge_step_path(challenge, paso("evaluation"))

      expect(zonas[:referencia]).to include("Progreso", "Cómo quedó configurado")
      expect(zonas[:referencia]).not_to include("Quién evalúa")
      expect(documento.at_css(".ajustes")).to be_nil
    end

    # La pantalla del módulo terminó de migrar: ningún `.panel` servido. Las
    # tarjetas de adentro de una isla no están en el HTML del servidor.
    it "no sirve ningún panel viejo" do
      sign_in(admin, company: company)
      get challenge_step_path(challenge, paso("evaluation"))

      expect(documento.css(".panel").map { |n| n["class"] }).to eq([])
    end
  end
end
```

Run: `make spec-file FILE=spec/requests/pantalla_del_modulo_spec.rb`
Expected: FAIL — la referencia no trae «Quién evalúa» ni «Cómo quedó configurado», no hay `.ajustes`, y hay `.panel`.

- [ ] **Step 2: Los partials de forma**

Create `app/views/steps/_bloque.html.haml`:

```haml
-# Un bloque de la pantalla del módulo, con la forma que le toca según dónde
-# va: tarjeta propia suelto en una columna, sección adentro de los ajustes
-# plegados. Una tarjeta adentro de otra se lee como un error de maquetado.
-#
-#   = render layout: "steps/bloque", locals: { tarjeta: false } do
-#     %h2.section-title …
- if local_assigns.fetch(:tarjeta, true)
  .card
    .card-body= yield
- else
  %section.ajustes__seccion= yield
```

Create `app/views/steps/_ajustes.html.haml`:

```haml
-# «Ajustes del módulo»: lo que se edita en la cara de ejecución, pero casi
-# nunca —nombre, modo de IA, quién participa—. Va al final y plegado para no
-# interponerse con el trabajo, que es lo que la pantalla existe para hacer.
-#
-# La vista decide si se dibuja: si a quien mira no le toca ningún bloque de
-# adentro, un plegable que se abre vacío es un control que no responde.
-#
-# Queda abierto después de guardar algo adentro por el gancho de
-# `application.js` (`turbo:before-morph-attribute`).
.card.ajustes
  .card-body
    %details.ajustes__plegable
      %summary.ajustes__titulo
        %span.section-title Ajustes del módulo
        %span.muted= resumen
      .ajustes__contenido= yield
```

Create `app/views/steps/_progreso.html.haml`:

```haml
-# El progreso del módulo, en la referencia: es lo que más se mira, así que
-# va primero. `detalle` suma lo que el kind quiera decir junto al conteo.
- detalle = local_assigns[:detalle]
.card
  .card-body
    %h3.section-title Progreso
    .step-progress
      %div
        %strong= progress.done
        %span.muted= " de #{progress.total} #{progress.label}#{" · #{detalle}" if detalle}"
      .progress-bar
        .progress-bar__fill{ style: "width: #{[progress.pct, 100].min}%" }
```

Create `app/views/steps/_quien_evalua.html.haml`:

```haml
-# Quién evalúa, para LEER: cuántas evaluaciones hizo cada persona y su peso,
-# si tiene uno. Editar vive en los ajustes (`_asignaciones_evaluadores`).
-#
-# Aparece dos veces a propósito —leída acá, editable allá—: leer y editar
-# son dos usos distintos de la misma lista. Con la MISMA guarda que la
-# edición: mudarla a la referencia no la vuelve pública.
- if policy(step).manage_assignments?
  - asignaciones = step.step_assignments.includes(:user).sort_by { |a| a.user.name }
  - evaluaron = step.assessments.current.group(:evaluator_id).count
  .card
    .card-body
      .section-head
        %h3.section-title Quién evalúa
        - if asignaciones.any?(&:weighted?)
          %span{ class: chip_de_estado("active") } con pesos
      - if asignaciones.empty?
        %p.muted Todavía no hay nadie asignado.
      - else
        %ul.field-list
          - asignaciones.each do |asignacion|
            - notas = evaluaron[asignacion.user_id].to_i
            %li.field-list__item
              %span
                = asignacion.user.name
                %br
                %span.muted= notas.positive? ? Flow::Texto.contar(notas, "evaluación") : "sin evaluar"
              - if asignacion.weighted?
                %span.field-list__type= "peso #{asignacion.weight.to_f}"
```

- [ ] **Step 3: Los partials que cambian de forma**

`app/views/steps/_config_congelada.html.haml`: reemplazá la primera línea `.panel` por dos líneas y re-indentá todo lo que colgaba de ella un nivel más:

```haml
.card
  .card-body
    .section-head
      %h2.section-title
        - if step.touched?
          Cómo quedó configurado
        - else
          Cómo está configurado
    %p.field-hint
      - if step.touched?
        🔒 Quedó fijado cuando arrancó el módulo.
        - if step.evaluation? || step.evolution?
          Se pueden cambiar el nombre, el modo de IA y quién participa; la regla no.
        - else
          Se pueden cambiar el nombre y el modo de IA; la regla no.
      - else
        🔒 Todavía no arrancó. Sólo quien administra el desafío puede cambiar esta configuración.
    - filas = resumen_de_configuracion(step)
    - if filas.any?
      %ul.field-list
        - filas.each do |etiqueta, valor|
          %li.field-list__item
            %span= etiqueta
            %span.field-list__type= valor
    - else
      %p.muted Este módulo no tiene nada configurable.
```

(Conservá los comentarios `-#` que tenga el archivo arriba de `.panel`.)

`app/views/steps/_ai_mode.html.haml`: la línea `.panel.ai-mode-card` pasa a `.ai-mode-card`. Nada más. Ahora vive adentro de los ajustes y no es una tarjeta.

`app/views/steps/_asignaciones_evaluadores.html.haml`: la línea `  .panel` (debajo de las variables) pasa a:

```haml
  = render layout: "steps/bloque", locals: { tarjeta: local_assigns.fetch(:tarjeta, true) } do
```

Lo que colgaba de `.panel` queda con la misma indentación. Sumá arriba del archivo:

```haml
-# Editar quién evalúa y cuánto pesa. En la cara de configuración es una
-# tarjeta; en la de ejecución vive adentro de los ajustes (`tarjeta: false`)
-# y la lista para leer está en la referencia (`_quien_evalua`).
```

`app/views/shared/_ai_suggestions.html.haml`:

```haml
  - if suggestions.any?
    .card.ai-panel
      .card-body
        %h2.section-title
          Propuestas de la IA
          %span{ class: chip_de_ia }= suggestions.size
        - suggestions.each do |suggestion|
          = render "shared/ai_suggestion", suggestion: suggestion
```

- [ ] **Step 4: La referencia de evaluación**

Reemplazá `app/views/steps/_referencia_evaluacion.html.haml` entero:

```haml
-# Lo que se consulta mientras se evalúa y no se edita acá, en el orden de la
-# regla de la referencia: el progreso primero, después lo propio del módulo
-# (los criterios), después quién participa y al final la configuración, que
-# no cambia.
-#
-# La tabla de criterios es lista porque una tabla de tres columnas no entra
-# en la columna. Los formularios no están acá: son trabajo, o ajustes.
- desafio = step.challenge
= render "steps/progreso", progress: handler.progress, detalle: "mínimo #{handler.min_assessments} por idea"

.card
  .card-body
    %h3.section-title
      Criterios
      - if step.criteria_set
        %span.muted= " · #{step.criteria_set.name}"

    - if handler.criteria_snapshot.empty?
      %p.muted Este módulo se activó sin criterios propios.
    - else
      %ul.field-list
        - handler.criteria_snapshot.each do |criterion|
          %li.field-list__item
            %span
              = criterion["name"]
              -# Contra `source` y no contra `scale_type`: `align_scale_with_source`
              -# fuerza `numeric` para las fórmulas, así que `scale_type ==
              -# "formula"` no es nunca cierto.
              - if criterion["source"] == "formula"
                %span{ class: chip("derivado") } derivado
              %br
              %span.muted= t("flow.scale_types.#{criterion['scale_type']}")
            %strong= "#{(criterion['weight'].to_f * 100).round}%"
      %p.muted.field-hint
        Congelados al activar el módulo: editar el set ahora no altera lo ya evaluado.

    -# Uno de la biblioteca sigue editable en el mantenedor —afecta a otros
    -# desafíos, por eso vive ahí y no acá—; un set inline no va a ningún lado.
    - if policy(desafio).update_pipeline? && step.criteria_set&.library?
      = link_to "Ver el set", edit_criteria_set_path(step.criteria_set), class: "btn btn-ghost btn-sm"

= render "steps/quien_evalua", step: step
= render "steps/config_congelada", step: step
```

- [ ] **Step 5: La pantalla**

Reemplazá `app/views/steps/evaluation.html.haml` entero:

```haml
- content_for :title, @step.name

-# Las tres zonas de la cara de ejecución: el trabajo al centro, lo que se
-# consulta a la derecha y los ajustes plegados al final. La referencia se
-# declara arriba de todo porque el layout la lee después del `yield`.
- content_for :referencia do
  = render "steps/referencia_evaluacion", step: @step, handler: @handler

= render "steps/header", step: @step, handler: @handler
= render "shared/ai_suggestions", suggestions: @pending_suggestions

- manda = policy(@challenge).update_pipeline?
- pendientes = @step.step_entries.reject { |e| @handler.complete?(e) }
-# Quién ve esto no es quién administra: evaluar depende de la ASIGNACIÓN, así
-# que un evaluador asignado también le pide una mano a la IA. Va sin idea a
-# propósito —pedirle a la IA que evalúe no es evaluar—; el porqué largo está
-# en AiSuggestionPolicy#evaluacion.
- puede_pedir = policy(Assessment.new(challenge_step: @step)).create?

.card
  .card-body
    %h2.section-title Ideas a evaluar

    -# El pedido a la IA es parte del trabajo sobre esta lista, así que va
    -# arriba de ella y no en una tarjeta aparte del mismo peso.
    - if @step.active? && @step.effective_ai_mode != "human" && pendientes.any? && puede_pedir
      %section.pedido-a-la-ia
        %h3.section-title Pedirle una evaluación a la IA
        %p.muted
          La IA evalúa con los mismos criterios y su nota entra al promedio como una más, con su
          justificación por criterio.
        -# Con más de una pendiente el lote va primero: es lo que casi siempre se
        -# quiere, y pedirlas de a una es el camino largo al mismo lugar.
        - if pendientes.size > 1
          .ai-actions
            %span{ class: chip_de_ia } IA
            = button_to "Evaluar #{Flow::Texto.contar(pendientes.size, "idea")} con IA",
                        evaluate_all_challenge_step_path(@challenge, @step),
                        class: "btn btn-primary btn-sm"
            %span.muted Todas las que faltan, de una.
        = render "shared/ai_actions", challenge: @challenge, mode: @step.effective_ai_mode,
                 actions: pendientes.first(1).map { |e| { label: "Evaluar solo «#{e.idea.title.truncate(28)}»", purpose: "evaluate_idea", step_id: @step.id, idea_id: e.idea_id } }

    - unless manda
      %p.muted.field-hint
        Los puntajes se muestran cuando envíes tu evaluación: verlos antes ancla el juicio. De las
        ideas que no evalúes vas a ver el resultado, no quién puso qué.
    - if @step.step_entries.empty?
      %p.muted Todavía no hay ideas en este módulo.
    - else
      .table-scroll
        %table.table
          %thead
            %tr
              %th Idea
              %th Evaluaciones
              %th Puntaje
              %th Dispersión
              %th
          %tbody
            - entries = @step.step_entries.includes(idea: %i[current_version author idea_contributors])
            - entries.select { |e| @ideas_visibles.include?(e.idea_id) }.each do |entry|
              - result = entry.result
              - propia = entry.idea.participates?(current_user)
              -# El puntaje agregado y el desglose por evaluador son dos cosas
              -# distintas: el autor ve el suyo, pero no quién puso qué.
              - visible = @handler.score_visible_for?(entry.idea, user: current_user, manager: manda)
              - desglose = @handler.breakdown_visible_for?(entry.idea_id, user: current_user, manager: manda)
              %tr
                %td
                  = link_to entry.idea.title, challenge_idea_path(@challenge, entry.idea), class: "table-link"
                  %span.muted= " · #{entry.idea.author.name}"
                %td.muted
                  = "#{result['assessments_count'] || 0} / #{@handler.min_assessments_for(entry.idea)}"
                  - evaluadores = desglose ? @handler.assessments_for(entry.idea_id) : []
                  - if evaluadores.any?
                    %span.evaluators
                      - evaluadores.each do |assessment|
                        %span{ class: chip(assessment.by_ai? ? "evaluador_ia" : "evaluador"),
                               title: "#{assessment.evaluator_name}: #{assessment.overall_comment}" }
                          = assessment.by_ai? ? "IA" : assessment.evaluator_name.split.map(&:first).join
                %td
                  - if !visible
                    %span.muted{ title: "Se muestra cuando envíes la tuya" } oculto
                  - elsif result["score"]
                    %strong= "#{(result['score'].to_f * 100).round}%"
                  - else
                    %span.muted —
                %td.muted= visible && result["dispersion"] ? result["dispersion"].to_f.round(3) : "—"
                %td.nowrap
                  - if @step.active? && propia
                    %span.field-hint Es tu idea
                  - elsif @step.active?
                    = link_to "Evaluar", new_challenge_step_assessment_path(@challenge, @step, idea_id: entry.idea_id), class: "btn btn-ghost btn-sm"
                    - if @step.effective_ai_mode != "human" && manda
                      = button_to "IA", challenge_ai_requests_path(@challenge, purpose: "evaluate_idea", step_id: @step.id, idea_id: entry.idea_id),
                                  class: "btn btn-ghost btn-sm", title: "Que la IA evalúe esta idea"

- hechas = @step.assessments.current.submitted_ones.includes(:idea, :evaluator, :assessment_scores).to_a
-# Solo se ven las de las ideas que ya evaluaste.
- hechas = hechas.select { |a| @handler.breakdown_visible_for?(a.idea_id, user: current_user, manager: manda) }
- if hechas.any?
  .card
    .card-body
      %h2.section-title
        Evaluaciones hechas
        %span.muted= " (#{hechas.size})"
      %p.muted.field-hint
        Las de la IA cuentan igual que las de una persona: mismo peso en el promedio.
        - unless manda
          Solo ves las de las ideas que ya evaluaste.
      - hechas.group_by(&:idea).each do |idea, lista|
        .assessment-group
          %h3.assessment-group__title
            = link_to idea.title, challenge_idea_path(@challenge, idea), class: "table-link"
          - lista.each do |assessment|
            .assessment-detail{ class: ("assessment-detail--ai" if assessment.by_ai?) }
              .assessment-detail__head
                %strong= assessment.evaluator_name
                - if assessment.by_ai?
                  %span{ class: chip_de_ia } IA
                %span{ class: chip("version") }= assessment.idea_version.label
                - if assessment.stale?
                  %span{ class: chip("desactualizada") }= "la idea ya va por #{idea.current_version&.label}"
                - if assessment.normalized_score
                  %span.assessment-detail__score= "#{(assessment.normalized_score.to_f * 100).round(1)}%"
              - if assessment.overall_comment.present?
                %p.assessment-detail__comment= assessment.overall_comment
              %ul.assessment-detail__scores
                - assessment.assessment_scores.sort_by { |s| s.criterion_key }.each do |score|
                  %li
                    %span.assessment-detail__criterion= score.criterion_key
                    %strong= score.display_value
                    - if score.comment.present?
                      %span.muted= score.comment
                    - if score.error.present?
                      %span{ class: chip("desactualizada") }= score.error

-# Nombre, modo de IA y quién evalúa: se editan acá, pero casi nunca. Cada
-# bloque trae su guarda; los ajustes se dibujan si a quien mira le toca uno.
- if policy(@step).advance? || policy(@step).manage_assignments?
  = render layout: "steps/ajustes", locals: { resumen: "nombre, modo de IA y quién evalúa" } do
    = render "steps/ai_mode", step: @step
    = render "steps/asignaciones_evaluadores", step: @step, assignable: @assignable, tarjeta: false
```

- [ ] **Step 6: El CSS**

En `application.css`, reemplazá la regla `.ai-mode-card { border-style: dashed; … }` (~1722) por:

```css
/* Ya no es una tarjeta: vive adentro de los ajustes plegados. Conserva el
   recuadro punteado de la IA, que es lo que la distingue. */
.ai-mode-card {
  padding: 16px;
  border: 1px dashed var(--ia-borde);
  border-radius: var(--radius);
  background: var(--ia-panel);
}
```

Y al final de la sección de la pantalla de módulo (junto a `.step-progress`, ~1195):

```css
/* ── Ajustes del módulo ─────────────────────────────────────────────────── */
/* Lo que se edita en la cara de ejecución pero casi nunca, plegado al final. */
.ajustes__titulo {
  display: flex;
  align-items: baseline;
  gap: 10px;
  cursor: pointer;
  list-style: none;
}
.ajustes__titulo::-webkit-details-marker { display: none; }
.ajustes__titulo::before {
  content: "▸";
  display: inline-block;
  color: var(--muted);
  transition: transform .15s;
}
.ajustes__plegable[open] > .ajustes__titulo::before { transform: rotate(90deg); }
.ajustes__titulo .section-title { margin: 0; }
.ajustes__contenido { display: grid; gap: 20px; margin-top: 16px; }

/* El pedido a la IA arriba de la lista sobre la que actúa, separado de ella. */
.pedido-a-la-ia { padding-bottom: 16px; border-bottom: 1px solid var(--tenue); }
.pedido-a-la-ia .ai-actions { margin-bottom: 8px; }
```

- [ ] **Step 7: El spec en verde**

Run: `make spec-file FILE=spec/requests/pantalla_del_modulo_spec.rb`
Expected: PASS. Si «no sirve ningún panel viejo» lista clases, son partials que la pantalla de evaluación todavía renderiza con `.panel`: migralos igual que `_config_congelada` (y sumalos al commit).

Run: `make spec`
Expected: verde. `step_assignments_spec` («lista a quienes evalúan», «quien evalúa no la ve») y `dos_caras_spec` («deja asignar evaluadores antes de que el módulo arranque», que usa `_asignaciones_evaluadores` con `tarjeta` por default) tienen que seguir pasando sin tocarlos.

- [ ] **Step 8: Las capturas**

En `script/capture_screens.js`, arriba de `(async () => {`:

```js
// Los módulos cuya cara de ejecución ya está en tres zonas (plan 2b). Por
// nombre del seed de `merma-bodega`, igual que el resto del recorrido. Cada
// tarea del plan suma el suyo; al final están los siete.
const MODULOS_EN_ZONAS = [/Evaluaci/i];
```

Adentro del `for (const [index, link] of stepLinks.entries())`, después del chequeo `[MODO IA]`:

```js
    // Las tres zonas: la referencia existe, y quien recorre —admin— tiene
    // los ajustes plegados al final. Sin esto, un módulo reordenado podía
    // perder su columna sin que ninguna captura lo dijera.
    if (MODULOS_EN_ZONAS.some((re) => re.test(link.text))) {
      if (!(await page.locator('.app-aside').count())) {
        failures++;
        console.error(`[ZONAS] «${link.text}» no tiene columna de referencia`);
      }
      if (!(await page.locator('details.ajustes__plegable').count())) {
        failures++;
        console.error(`[ZONAS] «${link.text}» no tiene los ajustes plegados`);
      }
    }
```

Después del bloque `if (comite) { … }` de `[EVALUADORES]`:

```js
  // Los ajustes abiertos. Plegados no salen en ninguna captura, y las guardas
  // de contraste y de clases sólo miden lo que tiene caja: sin esto, lo de
  // adentro quedaba sin medir.
  if (comite) {
    await page.goto(BASE + comite.href, { waitUntil: 'networkidle' });
    await page.locator('details.ajustes__plegable').evaluate((el) => { el.open = true; });
    await capturar(page, '09-16-ajustes-abiertos');
    await revisarPlegableTrasMorph(page, '09-16-ajustes-abiertos', 'details.ajustes__plegable');
  }
```

- [ ] **Step 9: Verde y mirar**

```bash
make yarn-build
make screens
```

Expected: verde, sin `[ZONAS]`, `[PLEGABLE]`, `[RITMO]`, `[PANEL]` ni `[CONTRASTE]`.

Mirá contra `tmp/screenshots-antes-2b/`: `09-3-step-evaluaci-n-t-cnica`, `09-5-step-evaluaci-n-de-comit-`, `09-16-ajustes-abiertos`, `94-oscuro-evaluacion`, `05e-config-evaluacion` (la tarjeta de asignaciones de la cara de configuración). Qué buscar:
- el `gap` de 8px de `card-body` sumado a los márgenes de `.section-title` (14px) y de los párrafos: si una tarjeta quedó visiblemente más suelta que en la captura de antes, ajustalo con una regla sobre la clase propia de adentro, no sobre `.card-body`;
- la referencia: cuatro tarjetas en 320px, que ninguna fila de «Quién evalúa» se parta feo;
- a 1100px de ancho la referencia sube arriba del trabajo en fila (`@media (max-width: 1279px)`): con cuatro tarjetas la banda crece. Mirala a mano con el navegador a ese ancho; si empuja el trabajo afuera de la primera pantalla, anotalo en el reporte de la tarea y no lo arregles acá.

- [ ] **Step 10: `CLAUDE.md`**

En «El shell de tres regiones», reemplazá el bullet «La regla de qué va dónde: …» por:

```markdown
- La regla de qué va dónde: **el centro es lo que se hace; la derecha es lo que
  se consulta y no se edita** en el curso normal del trabajo. En la cara de
  ejecución de un módulo hay una tercera zona: **«Ajustes del módulo»**, una
  tarjeta plegada al final del centro (`steps/_ajustes`) con lo que se edita
  pero casi nunca —nombre, modo de IA, quién participa—. La referencia va en
  orden fijo: progreso, lo propio del módulo, quién participa, configuración
  congelada. Lo que se lee a la derecha y se edita abajo aparece dos veces a
  propósito, **con la misma guarda en los dos lugares**
  (`spec/requests/pantalla_del_modulo_spec.rb` lo prueba por rol). Un bloque
  que va suelto o adentro de los ajustes toma su forma de `steps/_bloque`.
```

- [ ] **Step 11: Commit**

```bash
git add app/views app/assets/stylesheets/application.css script/capture_screens.js spec/requests/pantalla_del_modulo_spec.rb CLAUDE.md
git commit -F - <<'EOF'
Evaluación en tres zonas: consulta a la derecha, ajustes plegados

La referencia se completa con quién evalúa y la configuración congelada, el
pedido a la IA pasa a ser parte de la lista de ideas, y el nombre, el modo de
IA y las asignaciones van a un «Ajustes del módulo» plegado al final. Nacen
los partials que copian los otros cuatro módulos (`_ajustes`, `_bloque`,
`_progreso`) y un spec que prueba por rol que nada salió de atrás de su
guarda. La pantalla ya no sirve ningún `.panel`.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014gkhXcuX5q5pNYj9oZdAZU
EOF
```

---

### Task 3b: La referencia entra en una pantalla

**Agregada después de la Tarea 3**, por decisión de Raúl sobre un hallazgo de su revisión. Con la referencia completa, evaluación medía **1.395px** de columna a 1440×1000 —«Cómo quedó configurado» quedaba tapado detrás del scroll propio de la columna, que es `sticky` con `max-height: 100vh`— y **a 1100px de ancho** la referencia, que sube arriba del trabajo, formaba una banda de **727px** que empujaba el título del módulo a y=807, afuera de la primera pantalla. Las Tareas 5 a 8 copian la forma, así que se arregla antes.

Decisiones: **se compactan las listas de la referencia** (una línea por fila, sin recuadro por ítem) y **debajo de 1280px las tarjetas van en UNA fila que se desliza de costado**.

**Files:**
- Modify: `app/assets/stylesheets/application.css` (bloque `.app-aside` del `@media (max-width: 1279px)` ~702-703; comentario de `.card` ~756-764; sección nueva «La referencia, densa»)
- Modify: `app/views/steps/_quien_evalua.html.haml`
- Modify: `app/views/steps/_referencia_evaluacion.html.haml` (la lista de criterios)
- Modify: `script/capture_screens.js`
- Modify: `CLAUDE.md` («El shell de tres regiones»)

**Interfaces:**
- Consumes: `.app-aside` (layout), `MODULOS_EN_ZONAS` y el loop de módulos (Tarea 3).
- Produces: `revisarReferencia(page, name)` en `script/capture_screens.js`, llamada en el loop para cada módulo de `MODULOS_EN_ZONAS`; la densidad de `.field-list` adentro de `.app-aside`, que las listas de lectura de las Tareas 5 a 8 (`_como_se_decide`, `_quienes_acompanan`, `_campos_lectura`, `_descargas`) toman solas, sin tocar su markup.

- [ ] **Step 1: La guarda, y verla fallar**

En `script/capture_screens.js`, debajo de `revisarRitmo`:

```js
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
```

En el loop de módulos, adentro del `if (MODULOS_EN_ZONAS.some(...))` de la Tarea 3, después de los dos chequeos de `[ZONAS]`:

```js
      await revisarReferencia(page, nombre);
```

Run: `make screens`
Expected: FAIL con `[REFERENCIA] 09-3-step-evaluaci-n-t-cnica: la columna mide …px y se ven 1000` y `[REFERENCIA] …: a 1100px la referencia empuja el título del módulo a …px`, para evaluación técnica y para comité. Si alguna de las dos no falla, **pará**: la guarda no mide lo que dice.

- [ ] **Step 2: La referencia, densa**

En `application.css`, después de la regla `.app-shell:has(.app-aside) .app-main { border-right: … }` (~555):

```css
/* La referencia, densa. Lo que se consulta tiene que entrar en una pantalla:
   con un recuadro por ítem, la de evaluación medía 1.395px y lo último quedaba
   tapado. La ZONA decide la densidad y no la lista: la misma `.field-list` en
   el centro o en la cara de configuración conserva sus recuadros, y cualquier
   lista de lectura que se mude a la referencia la toma sola. */
.app-aside .card { --card-p: 16px; }
.app-aside .field-list { gap: 0; }
.app-aside .field-list__item {
  gap: 8px;
  padding: 5px 0;
  border: 0;
  border-radius: 0;
}
.app-aside .field-list__item + .field-list__item { border-top: 1px solid var(--tenue); }
```

- [ ] **Step 3: Una línea por fila**

`app/views/steps/_quien_evalua.html.haml`, el `%li` entero pasa a:

```haml
            %li.field-list__item
              %span= asignacion.user.name
              %span.muted
                = notas.positive? ? Flow::Texto.contar(notas, "evaluación") : "sin evaluar"
                - if asignacion.weighted?
                  = "· peso #{asignacion.weight.to_f}"
```

`app/views/steps/_referencia_evaluacion.html.haml`, el `%li` de los criterios pasa a:

```haml
          %li.field-list__item
            %span
              = criterion["name"]
              -# Contra `source` y no contra `scale_type`: `align_scale_with_source`
              -# fuerza `numeric` para las fórmulas, así que `scale_type ==
              -# "formula"` no es nunca cierto.
              - if criterion["source"] == "formula"
                %span{ class: chip("derivado") } derivado
              %span.muted= " · #{t("flow.scale_types.#{criterion['scale_type']}")}"
            %strong= "#{(criterion['weight'].to_f * 100).round}%"
```

- [ ] **Step 4: Debajo de 1280px, una fila**

En el `@media (max-width: 1279px)`, reemplazá las dos líneas

```css
  .app-aside { flex-direction: row; flex-wrap: wrap; align-items: flex-start; }
  .app-aside > * { flex: 1 1 260px; }
```

y su comentario («Y en fila: …») por:

```css
  /* En UNA fila que se desliza de costado. En varias filas, las cuatro
     tarjetas de evaluación formaban una banda de 727px que empujaba el título
     del módulo afuera de la primera pantalla; en una, la banda mide lo que la
     tarjeta más alta, y ninguna pasa de 320px: una lista larga scrollea
     adentro de su tarjeta. */
  .app-aside { flex-direction: row; flex-wrap: nowrap; overflow-x: auto; align-items: flex-start; }
  .app-aside > * { flex: 0 0 280px; max-height: 320px; overflow-y: auto; }
```

Verificá que ninguna regla posterior del mismo `@media` (ni del de 1023px) vuelva a poner `flex-wrap: wrap` o `overflow: visible` sobre `.app-aside`; si la hay, que no pise estas.

- [ ] **Step 5: El comentario de `.card`**

En el comentario de la regla `.card` (~756-764), `.ai-mode-card` ya no es tarjeta desde la Tarea 3. Reemplazá «Va PEGADA a `.panel` y antes de `.ai-panel`, `.narrative-card` y `.ai-mode-card`» por «Va PEGADA a `.panel` y antes de `.ai-panel` y `.narrative-card`».

- [ ] **Step 6: Verde y mirar**

```bash
make yarn-build
make spec
make screens
```

Expected: verde, sin `[REFERENCIA]`. Si a 1100px el título queda apenas arriba de 450 por una tarjeta puntual, reportalo con el número: no subas el umbral.

Mirá contra `tmp/screenshots-antes-2b/` y contra las de la Tarea 3: `09-3-step-evaluaci-n-t-cnica`, `09-5-step-evaluaci-n-de-comit-` (la columna entera, con «Cómo quedó configurado» al final) y `94-oscuro-evaluacion`. Y con Playwright o el navegador a 1100×900, una captura de evaluación de comité para el reporte.

- [ ] **Step 7: `CLAUDE.md`**

En «El shell de tres regiones», después del bullet de la regla de qué va dónde (Tarea 3), sumá:

```markdown
- **La referencia tiene que entrar en una pantalla.** Pegada y con
  `max-height: 100vh`, lo que no entra queda tapado detrás de su propio
  scroll. Por eso la densidad la decide la zona: adentro de `.app-aside` una
  `.field-list` va sin recuadro por ítem, con una línea por fila. Debajo de
  1280px, donde sube arriba del trabajo, las tarjetas van en UNA fila que se
  desliza de costado (tope de 320px por tarjeta): en varias filas empujaban el
  título del módulo afuera de la primera pantalla. Lo mide `[REFERENCIA]` en
  `make screens`, a 1440×1000 y a 1100×900.
```

- [ ] **Step 8: Commit**

```bash
git add app/assets/stylesheets/application.css app/views/steps/_quien_evalua.html.haml app/views/steps/_referencia_evaluacion.html.haml script/capture_screens.js CLAUDE.md docs/superpowers/plans/2026-09-17-rediseno-2b-pantallas-de-modulo.md
git commit -F - <<'MSG'
La referencia entra en una pantalla

Con la referencia completa, la columna de evaluación medía 1.395px a
1440×1000 y lo último quedaba tapado detrás de su propio scroll; a 1100px
formaba una banda de 727px que empujaba el título del módulo afuera de la
primera pantalla. Las listas de la referencia pasan a una línea por fila sin
recuadro —la zona decide la densidad—, y debajo de 1280px las tarjetas van en
una fila que se desliza de costado. `[REFERENCIA]` mide las dos cosas.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014gkhXcuX5q5pNYj9oZdAZU
MSG
```

---

### Task 4: Evaluación — el desglose adentro de la fila de cada idea

«Evaluaciones hechas» desaparece como sección: cada idea es una fila que se despliega y muestra sus evaluaciones.

**Files:**
- Create: `app/views/steps/_fila_de_evaluacion.html.haml`
- Create: `app/views/steps/_celdas_de_evaluacion.html.haml`
- Modify: `app/views/steps/evaluation.html.haml` (la tarjeta «Ideas a evaluar» y la de «Evaluaciones hechas»)
- Modify: `app/assets/stylesheets/application.css`
- Modify: `spec/requests/pantalla_del_modulo_spec.rb`
- Modify: `spec/requests/ai_spec.rb:488`
- Modify: `spec/requests/participant_rules_spec.rb:112`
- Modify: `script/capture_screens.js`

**Interfaces:**
- Consumes: `chip(...)` (T2); `revisarPlegableTrasMorph` (T1); `pantalla_del_modulo_spec.rb` con `postular!`, `zonas`, `documento` (T3).
- Produces: las clases `.filas-de-ideas`, `.fila-de-idea`, `.fila-de-idea__plegable`, `.fila-de-idea__resumen`, `.fila-de-idea__desglose`, `.fila-de-idea__acciones`, que ningún otro módulo usa.

- [ ] **Step 1: Los specs que fallan**

En `spec/requests/pantalla_del_modulo_spec.rb`, adentro de `describe "evaluación"`, sumá:

```ruby
    describe "el desglose por fila" do
      before do
        as_company(company) do
          evaluacion = challenge.steps.reload.find(&:evaluation?)
          idea = challenge.ideas.first
          evaluacion.assessments.create!(idea: idea, idea_version_id: idea.current_version_id,
                                         evaluator: elena, actor_type: "human", status: "submitted",
                                         submitted_at: Time.current, normalized_score: 0.58,
                                         overall_comment: "Falta el costo del piloto")
          evaluacion.handler.recompute_entry!(StepEntry.find_by(challenge_step_id: evaluacion.id, idea_id: idea.id))
        end
      end

      it "quien administra despliega la fila y ve quién puso qué" do
        sign_in(admin, company: company)
        get challenge_step_path(challenge, paso("evaluation"))

        desglose = documento.at_css("details.fila-de-idea__plegable .fila-de-idea__desglose")
        expect(desglose&.text.to_s).to include(elena.name, "Falta el costo del piloto")
        expect(response.body).not_to include("Evaluaciones hechas")
      end

      it "«Evaluar» queda afuera del summary: un clic ahí no despliega la fila" do
        sign_in(admin, company: company)
        get challenge_step_path(challenge, paso("evaluation"))

        # El link del título sí va adentro del summary: navega, no despliega.
        # Lo que no puede ir es un formulario ni las acciones de la fila.
        expect(documento.css("summary form, summary .fila-de-idea__acciones")).to be_empty
      end

      it "quien participa no tiene fila desplegable ni ve quién evaluó" do
        sign_in(paula, company: company)
        get challenge_step_path(challenge, paso("evaluation"))

        expect(documento.at_css(".fila-de-idea__plegable")).to be_nil
        expect(response.body).not_to include(elena.name)
      end
    end
```

Run: `make spec-file FILE=spec/requests/pantalla_del_modulo_spec.rb`
Expected: FAIL — no existe `.fila-de-idea__plegable` y «Evaluaciones hechas» sigue.

- [ ] **Step 2: Las celdas**

Create `app/views/steps/_celdas_de_evaluacion.html.haml`:

```haml
-# Las cuatro celdas de la fila de una idea. Se renderizan adentro del
-# `summary` cuando la fila se despliega y sueltas cuando no: la misma fila en
-# los dos casos, sin copiar el markup.
%span.fila-de-idea__flecha{ "aria-hidden": "true" }= desplegable ? "▸" : ""
%span.fila-de-idea__idea
  = link_to entry.idea.title, challenge_idea_path(challenge, entry.idea), class: "table-link"
  %span.muted= " · #{entry.idea.author.name}"
%span.muted
  = "#{result['assessments_count'] || 0} / #{handler.min_assessments_for(entry.idea)}"
  - if evaluaciones.any?
    %span.evaluators
      - evaluaciones.each do |assessment|
        %span{ class: chip(assessment.by_ai? ? "evaluador_ia" : "evaluador"),
               title: "#{assessment.evaluator_name}: #{assessment.overall_comment}" }
          = assessment.by_ai? ? "IA" : assessment.evaluator_name.split.map(&:first).join
%span
  - if !visible
    %span.muted{ title: "Se muestra cuando envíes la tuya" } oculto
  - elsif result["score"]
    %strong= "#{(result['score'].to_f * 100).round}%"
  - else
    %span.muted —
%span.muted= visible && result["dispersion"] ? result["dispersion"].to_f.round(3) : "—"
```

El título de la idea es un link y queda adentro del `summary`: un link ahí navega, no despliega. Lo que no puede ir adentro es un formulario (`button_to`) ni «Evaluar», que están en `_fila_de_evaluacion`.

- [ ] **Step 3: La fila**

Create `app/views/steps/_fila_de_evaluacion.html.haml`:

```haml
-# Una idea a evaluar. Si quien mira puede ver quién puso qué
-# (`breakdown_visible_for?`) y hay evaluaciones, la fila es un <details> que
-# se despliega con el detalle de cada una. Si no, es una fila común: una
-# flechita que abre algo vacío sería un control que no responde.
-#
-# «Evaluar» e «IA» van AFUERA del `summary`, a la derecha: un clic en un botón
-# adentro de un `summary` también despliega la fila, y un `button_to` es un
-# formulario, que ahí adentro el HTML no admite.
- result = entry.result
- propia = entry.idea.participates?(current_user)
-# El puntaje agregado y el desglose por evaluador son dos cosas distintas: el
-# autor ve el suyo, pero no quién puso qué.
- visible = handler.score_visible_for?(entry.idea, user: current_user, manager: manda)
- desglose = handler.breakdown_visible_for?(entry.idea_id, user: current_user, manager: manda)
- evaluaciones = desglose ? hechas.fetch(entry.idea_id, []) : []
- celdas = { entry: entry, handler: handler, challenge: challenge, result: result, visible: visible, evaluaciones: evaluaciones }

.fila-de-idea
  - if evaluaciones.any?
    %details.fila-de-idea__plegable
      %summary.fila-de-idea__resumen
        = render "steps/celdas_de_evaluacion", **celdas, desplegable: true
      .fila-de-idea__desglose
        - evaluaciones.each do |assessment|
          .assessment-detail{ class: ("assessment-detail--ai" if assessment.by_ai?) }
            .assessment-detail__head
              %strong= assessment.evaluator_name
              - if assessment.by_ai?
                %span{ class: chip_de_ia } IA
              %span{ class: chip("version") }= assessment.idea_version.label
              - if assessment.stale?
                %span{ class: chip("desactualizada") }= "la idea ya va por #{entry.idea.current_version&.label}"
              - if assessment.normalized_score
                %span.assessment-detail__score= "#{(assessment.normalized_score.to_f * 100).round(1)}%"
            - if assessment.overall_comment.present?
              %p.assessment-detail__comment= assessment.overall_comment
            %ul.assessment-detail__scores
              - assessment.assessment_scores.sort_by(&:criterion_key).each do |score|
                %li
                  %span.assessment-detail__criterion= score.criterion_key
                  %strong= score.display_value
                  - if score.comment.present?
                    %span.muted= score.comment
                  - if score.error.present?
                    %span{ class: chip("desactualizada") }= score.error
  - else
    .fila-de-idea__resumen
      = render "steps/celdas_de_evaluacion", **celdas, desplegable: false

  .fila-de-idea__acciones
    - if step.active? && propia
      %span.field-hint Es tu idea
    - elsif step.active?
      = link_to "Evaluar", new_challenge_step_assessment_path(challenge, step, idea_id: entry.idea_id), class: "btn btn-ghost btn-sm"
      - if step.effective_ai_mode != "human" && manda
        = button_to "IA", challenge_ai_requests_path(challenge, purpose: "evaluate_idea", step_id: step.id, idea_id: entry.idea_id),
                    class: "btn btn-ghost btn-sm", title: "Que la IA evalúe esta idea"
```

- [ ] **Step 4: La tarjeta**

En `app/views/steps/evaluation.html.haml`, reemplazá desde `- if @step.step_entries.empty?` (adentro de la tarjeta «Ideas a evaluar») **hasta el final del bloque `- if hechas.any?`** (inclusive) por:

```haml
    %p.muted.field-hint
      Las de la IA cuentan igual que las de una persona: mismo peso en el promedio.
    - if @step.step_entries.empty?
      %p.muted Todavía no hay ideas en este módulo.
    - else
      -# El detalle de cada evaluación vive en la fila de su idea. Era una
      -# sección aparte —quince bloques abiertos debajo de la tabla— y la idea
      -# aparecía dos veces en la pantalla.
      - hechas = @step.assessments.current.submitted_ones.includes(:evaluator, :assessment_scores, :idea_version).group_by(&:idea_id)
      - entries = @step.step_entries.includes(idea: %i[current_version author idea_contributors])
      .filas-de-ideas
        .filas-de-ideas__encabezado
          .filas-de-ideas__columnas
            %span
            %span Idea
            %span Evaluaciones
            %span Puntaje
            %span Dispersión
          %span
        - entries.select { |e| @ideas_visibles.include?(e.idea_id) }.each do |entry|
          = render "steps/fila_de_evaluacion", entry: entry, handler: @handler, challenge: @challenge,
                   step: @step, manda: manda, hechas: hechas
```

La tarjeta «Evaluaciones hechas» ya no existe. Los ajustes quedan como estaban, después de la tarjeta.

- [ ] **Step 5: El CSS**

En `application.css`, junto a `.assessment-detail` (~1652), reemplazá las tres reglas `.assessment-group*` por:

```css
/* ── Ideas a evaluar: una fila por idea, que se despliega ───────────────── */
/* Grilla y no <table>: un <details> no puede abarcar una fila de tabla. El
   encabezado y cada fila comparten las columnas, así que se alinean sin
   tabla. Afuera, dos columnas —lo que se lee y las acciones— porque las
   acciones no pueden ir adentro del `summary`. */
.filas-de-ideas { display: grid; }
.filas-de-ideas__encabezado,
.fila-de-idea {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 8.5rem;
  column-gap: 12px;
  align-items: start;
}
.filas-de-ideas__encabezado {
  padding-bottom: 8px;
  font-size: 11px;
  font-weight: 600;
  letter-spacing: .04em;
  text-transform: uppercase;
  color: var(--muted);
}
.fila-de-idea { padding: 10px 0; border-top: 1px solid var(--tenue); }
.filas-de-ideas__columnas,
.fila-de-idea__resumen {
  display: grid;
  grid-template-columns: 1rem minmax(0, 1fr) 8rem 4.5rem 5rem;
  column-gap: 12px;
  align-items: center;
}
.fila-de-idea__resumen { list-style: none; }
.fila-de-idea__resumen::-webkit-details-marker { display: none; }
.fila-de-idea__plegable > .fila-de-idea__resumen { cursor: pointer; }
.fila-de-idea__flecha { display: inline-block; color: var(--muted); transition: transform .15s; }
.fila-de-idea__plegable[open] > .fila-de-idea__resumen .fila-de-idea__flecha { transform: rotate(90deg); }
.fila-de-idea__desglose { display: grid; gap: 8px; margin: 10px 0 0 calc(1rem + 12px); }
.fila-de-idea__acciones { display: flex; justify-content: flex-end; align-items: center; gap: 6px; flex-wrap: wrap; }
```

Y en `.assessment-detail` (~1656), borrá el `margin-bottom: 8px`: el espacio entre evaluaciones lo pone el `gap` del desglose.

- [ ] **Step 6: Los specs que miraban la sección vieja**

`spec/requests/ai_spec.rb:488`, en «la pantalla del módulo muestra la evaluación con su justificación»: reemplazá

```ruby
    expect(response.body).to include("Evaluaciones hechas")
    expect(response.body).to include("diferencia de inventario")
```

por

```ruby
    desglose = Nokogiri::HTML(response.body).css(".fila-de-idea__desglose").text
    expect(desglose).to include("diferencia de inventario")
```

`spec/requests/participant_rules_spec.rb:112`: `expect(response.body).not_to include("Evaluaciones hechas")` ya no probaría nada —el texto no existe para nadie—. Reemplazalo por:

```ruby
      expect(response.body).not_to include("fila-de-idea__desglose")
```

Run: `make spec`
Expected: verde. **Verificá que la línea nueva de `participant_rules_spec` falla** si en `_fila_de_evaluacion` cambiás `desglose ? hechas.fetch(...) : []` por `hechas.fetch(entry.idea_id, [])`; después devolvelo.

- [ ] **Step 7: Las capturas**

En `script/capture_screens.js`, adentro del `if (comite) { … }` de los ajustes abiertos (Tarea 3), antes de abrir los ajustes:

```js
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
```

- [ ] **Step 8: Verde y mirar**

```bash
make yarn-build
make screens
```

Expected: verde. Mirá `09-3-…`, `09-5-…`, `09-17-desglose` y `94-oscuro-evaluacion` contra `tmp/screenshots-antes-2b/`. La pantalla de evaluación tiene que medir mucho menos que los 4.239px de antes. Revisá que los encabezados queden alineados con las celdas y que «Evaluar» e «IA» no se partan en 8.5rem; si se parten, ajustá el ancho de la columna en **las dos** reglas (`.filas-de-ideas__encabezado, .fila-de-idea`).

- [ ] **Step 9: Commit**

```bash
git add app/views app/assets/stylesheets/application.css spec script/capture_screens.js
git commit -F - <<'EOF'
El desglose de cada evaluación, adentro de la fila de su idea

«Evaluaciones hechas» eran quince bloques abiertos debajo de la tabla, con
cada idea escrita dos veces en la pantalla. Cada idea pasa a ser una fila que
se despliega —un <details>, con «Evaluar» e «IA» afuera del summary— y sólo
cuando quien mira puede ver quién puso qué. La lista deja de ser tabla porque
un <details> no puede abarcar una fila.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014gkhXcuX5q5pNYj9oZdAZU
EOF
```

---

### Task 5: Selección

**Files:**
- Create: `app/views/steps/_como_se_decide.html.haml`
- Modify: `app/views/steps/selection.html.haml` (entero)
- Modify: `spec/requests/pantalla_del_modulo_spec.rb`
- Modify: `script/capture_screens.js` (`MODULOS_EN_ZONAS`)

**Interfaces:**
- Consumes: `steps/_ajustes`, `steps/_ai_mode`, `.pedido-a-la-ia`, `postular!`, `zonas`, `documento`, `MODULOS_EN_ZONAS`.
- Produces: `render "steps/como_se_decide", step:, handler:, completo:`.

- [ ] **Step 1: El spec que falla**

En `spec/requests/pantalla_del_modulo_spec.rb`:

```ruby
  describe "selección" do
    let!(:challenge) do
      as_company(company) do
        c = create(:challenge, name: "Merma", ai_default_mode: "human")
        seed_form!(c.steps.create!(kind: "ideation", position: 1))
        c.steps.create!(kind: "selection", position: 2, name: "Corte")
        c
      end
    end

    before do
      postular!(challenge, author: paula, titulo: "Sensores")
      as_company(company) do
        challenge.pipeline.start!
        challenge.pipeline.advance!
      end
    end

    it "quien administra: cómo se decide a la derecha, los ajustes plegados" do
      sign_in(admin, company: company)
      get challenge_step_path(challenge, paso("selection"))

      expect(zonas[:referencia]).to include("Cómo se decide")
      expect(zonas[:ajustes]).to include("Ajustes del módulo", "Modo de IA")
      expect(documento.css(".panel").map { |n| n["class"] }).to eq([])
    end

    it "quien participa: cómo se decide, sin ajustes" do
      sign_in(paula, company: company)
      get challenge_step_path(challenge, paso("selection"))

      expect(zonas[:referencia]).to include("Cómo se decide")
      expect(documento.at_css(".ajustes")).to be_nil
    end
  end
```

Run: `make spec-file FILE=spec/requests/pantalla_del_modulo_spec.rb`
Expected: FAIL en los dos nuevos.

- [ ] **Step 2: Cómo se decide, como partial**

Create `app/views/steps/_como_se_decide.html.haml` con el bloque «Cómo se decide» de `steps/selection.html.haml` (líneas 14-74 de hoy), en `.card > .card-body` y con `@step`/`@handler`/`@challenge` pasados como locals:

```haml
-# Los filtros y el corte, para leer: se congelaron al arrancar el módulo. Va
-# en la referencia —se consulta mientras se decide el corte, no se edita—.
- challenge = step.challenge
- gates = handler.gate_criteria
.card
  .card-body
    .section-head
      %h3.section-title Cómo se decide
      - if step.criteria_set && policy(challenge).update_pipeline?
        = link_to "Editar el set", edit_criteria_set_path(step.criteria_set), class: "btn btn-ghost btn-sm"

    - if gates.any?
      %p.field-hint
        = "#{Flow::Texto.contar(gates.size, "condición")} para poder avanzar."
        Una idea avanza solo si las cumple todas.
      %ul.field-list
        - gates.each do |gate|
          - criterion = Criterion.find_by(id: gate["id"])
          %li.field-list__item
            %span
              = gate["name"]
              %span{ class: chip_de_origen(gate["source"]) }= t("flow.criterion_sources.#{gate['source']}")
            %span.field-list__type
              - if gate["source"] == "automatic" && criterion&.check
                = criterion.check.description
              - else
                veredicto por idea

    %p.rule-line
      - if gates.any?
        %strong Después, el corte:
      - else
        %strong El corte:
      = t("flow.cut_modes.#{handler.cut_mode}")
      - unless handler.manual_cut?
        = "· #{handler.cut_value.to_i}"
        - if handler.cut_min.positive?
          = "· mínimo #{Flow::Texto.contar(handler.cut_min, "idea")}"
      - fuentes = handler.expected_source_steps
      - if fuentes.any?
        %span.muted
          = " · por puntaje de #{fuentes.map(&:name).join(" + ")}"
          - if fuentes.size > 1
            - weights = step.settings.dig("score_source", "weights") || {}
            - if weights.present?
              = "(#{fuentes.map { |s| "#{s.name} #{(weights[s.slug].to_f * 100).round}%" }.join(', ')})"
      - else
        %span.muted · sin fuente de puntaje: el orden es manual

    - if handler.piso_aplicado?(completo)
      %p.rule-line
        %strong Pasan por el mínimo:
        = "el corte dejaba pasar menos de #{Flow::Texto.contar(handler.cut_min, "idea")}, así que avanzan las mejores aunque no lo alcancen."

    - combine_campo = Flow::StepSettings.fields("selection").find { |c| c[:key] == "score_source.combine" }
    - combine_valor = step.settings.dig("score_source", "combine")
    - if fuentes.size > 1 && combine_valor.present?
      %p.muted.field-hint= "#{combine_campo[:label]}: #{Flow::StepSettings.display_value(combine_campo, combine_valor)}"

    -# La cara de ejecución sólo se renderiza con el módulo tocado.
    %p.field-hint El corte quedó fijado cuando arrancó el módulo. Se puede cambiar el modo de IA, no la regla.
```

Antes de dar por buena la copia, compará con el original:

```bash
git show HEAD:app/views/steps/selection.html.haml | sed -n 14,74p
```

Las únicas diferencias permitidas: `.panel` → `.card > .card-body` (un nivel más de indentación), `%h2` → `%h3`, `@step`/`@handler`/`@challenge` → `step`/`handler`/`challenge`, y el comentario de arriba.

- [ ] **Step 3: La pantalla**

En `app/views/steps/selection.html.haml`:

1. Borrá el bloque `.panel` de «Cómo se decide» (hoy líneas 15-74) y el `- gates = @handler.gate_criteria` suelto queda (lo usa la tabla).
2. Borrá `= render "steps/ai_mode", step: @step` (línea 79) y su comentario.
3. Arriba de `= render "steps/header"`, declarale la referencia. Como necesita `completo`, las variables del ranking suben arriba del `content_for`:

```haml
- content_for :title, @step.name

- completo = @handler.ranking
- above = completo.select(&:above_cut?)
-# Quien participa ve solo las filas de sus ideas. La línea de corte y el
-# contador siguen siendo del pool entero —son agregados, no dicen de quién es
-# cada idea— pero la línea solo se dibuja si se ve la tabla completa: entre
-# filas salteadas no marca nada.
- ranking = completo.select { |row| @ideas_visibles.include?(row.idea.id) }
- ve_todo = ranking.size == completo.size
- gates = @handler.gate_criteria

-# Lo que se consulta mientras se decide el corte: los filtros y la regla, que
-# quedaron fijos al arrancar.
- content_for :referencia do
  = render "steps/como_se_decide", step: @step, handler: @handler, completo: completo

= render "steps/header", step: @step, handler: @handler
= render "shared/ai_suggestions", suggestions: @pending_suggestions
```

4. El pedido de veredictos a la IA entra a la tarjeta del ranking. Borrá su `.panel` suelto (hoy 84-94) y dejá la tarjeta del ranking así (la tabla y la leyenda, sin cambios adentro, pasan a `.table-scroll` e indentan un nivel):

```haml
- sin_veredicto = ranking.select { |r| r.pending_gates.any? }
- decidible = @step.active? && policy(@step).advance?
- corte_id = "corte-#{@step.id}"
- fuera_aca = @handler.eliminated_ideas.index_by(&:id)

.card
  .card-body
    %h2.section-title
      Ranking
      %span.muted= " · #{above.size} de #{completo.size} avanzan"

    -# Un filtro sin responder deja a la idea en el limbo y traba el cierre del
    -# módulo. El pedido va arriba de la tabla sobre la que actúa.
    - if @step.active? && @handler.verdict_gates.any? && sin_veredicto.any? && policy(@step).advance?
      %section.pedido-a-la-ia
        %h3.section-title Pedirle los veredictos a la IA
        %p.muted
          La IA lee la idea y responde cada filtro con su justificación. A diferencia de una
          evaluación, un veredicto decide quién queda afuera: lo que proponga pasa por tu revisión
          antes de aplicarse.
        = render "shared/ai_actions", challenge: @challenge, mode: @step.effective_ai_mode,
                 actions: sin_veredicto.first(1).map { |r| { label: "Responder los filtros de «#{r.idea.title.truncate(28)}»", purpose: "decide_verdicts", step_id: @step.id, idea_id: r.idea.id } }
        - if sin_veredicto.size > 1
          %p.field-hint= "Quedan #{sin_veredicto.size} ideas con filtros sin responder."

    -# La tabla va FUERA del formulario del corte: los ✓/✗ de veredicto son
    -# `button_to` y quedaban anidados. Los checkboxes se atan por `form=`.
    .table-scroll
```

Debajo de `.table-scroll` va la tabla de hoy **sin cambiar una letra**: desde `%table.table.ranking-table` hasta la última celda de su `%tbody` (hoy líneas 110-193), con cuatro espacios más de indentación. Después, a la altura de `.table-scroll`, la leyenda de hoy (`- if gates.any?` con su `%p.table-legend`, líneas 197-208) con dos espacios más. Para confirmar que la tabla y la leyenda no cambiaron más que de sangría, `git diff -w` ignora los espacios:

```bash
git diff -w HEAD -- app/views/steps/selection.html.haml
```

Expected: en el diff no aparece ninguna línea de `%thead`, `%tbody`, `%tr`, `%td`, `gate` ni de la leyenda.

5. «Confirmar el corte» y «Registro de decisiones»: sus `.panel` pasan a `.card` + `.card-body`, con el contenido un nivel más adentro.

6. Al final del archivo:

```haml
-# El modo de IA importa acá más que en ninguno: con «Solo personas» los
-# veredictos los tiene que responder alguien uno por uno. Se ajusta, pero
-# casi nunca: va plegado.
- if policy(@step).advance?
  = render layout: "steps/ajustes", locals: { resumen: "nombre y modo de IA" } do
    = render "steps/ai_mode", step: @step
```

- [ ] **Step 4: Verde**

Run: `make spec`
Expected: verde, incluido `spec/requests/selection_screen_spec.rb` (formularios anidados) y `dos_caras_spec` («no muestra el trabajo del módulo»: «Cómo se decide» sigue sin aparecer en la cara de configuración).

- [ ] **Step 5: Capturas, y la decisión del ancho**

En `script/capture_screens.js`: `const MODULOS_EN_ZONAS = [/Evaluaci/i, /Corte a top|Finalistas/i];`

```bash
make yarn-build
make screens
```

Expected: verde, sin `[ZONAS]`, `[FORMS]` ni `[FILTROS]`.

Mirá `09-4-step-corte-a-top-3`, `09-6-step-finalistas` y `95-oscuro-seleccion` contra `tmp/screenshots-antes-2b/`. **La decisión abierta del spec (§3, «Selección y el ancho»):** si en el centro el ranking no se lee —el título de la idea partido en tres renglones o más, los encabezados de los filtros encimados, o la tabla con scroll horizontal a 1440px—, selección se queda sin referencia:

- el `content_for :referencia` se borra, y `= render "steps/como_se_decide", step: @step, handler: @handler, completo: completo` va entre `shared/ai_suggestions` y la tarjeta del ranking;
- en los dos specs de selección, `expect(zonas[:referencia]).to include("Cómo se decide")` pasa a `expect(response.body).to include("Cómo se decide")` y se suma `expect(documento.at_css(".app-aside")).to be_nil`;
- `/Corte a top|Finalistas/i` sale de `MODULOS_EN_ZONAS`, y arriba de él se declara `const MODULOS_SOLO_AJUSTES = [/Corte a top|Finalistas/i];`. En el loop, al lado del chequeo de `MODULOS_EN_ZONAS`:

```js
    if (MODULOS_SOLO_AJUSTES.some((re) => re.test(link.text)) &&
        !(await page.locator('details.ajustes__plegable').count())) {
      failures++;
      console.error(`[ZONAS] «${link.text}» no tiene los ajustes plegados`);
    }
```

Sea cual sea, **la decisión y lo que se vio van en el mensaje del commit**, y se reporta al terminar la tarea.

- [ ] **Step 6: Commit**

Si el ranking se lee con la referencia puesta:

```bash
git add app/views spec/requests/pantalla_del_modulo_spec.rb script/capture_screens.js
git commit -F - <<'EOF'
Selección en tres zonas

«Cómo se decide» va a la referencia: se consulta mientras se decide el corte
y quedó fijo al arrancar. El pedido de veredictos a la IA entra a la tarjeta
del ranking, arriba de la tabla sobre la que actúa, y el modo de IA va a los
ajustes plegados. El ranking se lee en el centro angosto: en la captura a
1440px no se parte ningún título ni aparece desplazamiento horizontal.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014gkhXcuX5q5pNYj9oZdAZU
EOF
```

Si no se lee y selección quedó sin referencia:

```bash
git add app/views spec/requests/pantalla_del_modulo_spec.rb script/capture_screens.js
git commit -F - <<'EOF'
Selección sin referencia, y el resto en su lugar

La decisión abierta del spec: con la columna de referencia puesta el ranking
no se leía en el centro —lleva una columna por filtro y por módulo fuente—,
así que «Cómo se decide» vuelve arriba del ranking y selección no tiene
columna derecha. El pedido de veredictos a la IA entra a la tarjeta del
ranking y el modo de IA va a los ajustes plegados.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014gkhXcuX5q5pNYj9oZdAZU
EOF
```

En el segundo caso, sumá al mensaje qué fue lo que no se leía (qué se partía, a qué ancho).

---

### Task 6: Evolución

**Files:**
- Create: `app/views/steps/_quienes_acompanan.html.haml`
- Modify: `app/views/steps/evolution.html.haml` (entero)
- Modify: `app/views/steps/_asignaciones_gestores.html.haml`
- Modify: `app/views/challenges/_gestores.html.haml`
- Modify: `app/assets/stylesheets/application.css`
- Modify: `spec/requests/pantalla_del_modulo_spec.rb`
- Modify: `script/capture_screens.js` (`MODULOS_EN_ZONAS`)

**Interfaces:**
- Consumes: `steps/_ajustes`, `steps/_bloque`, `steps/_progreso`, `steps/_config_congelada`, `steps/_ai_mode`.
- Produces: `render "steps/quienes_acompanan", step:`; `render "steps/asignaciones_gestores", step:, candidates:, tarjeta: Boolean`; `render "challenges/gestores", challenge:, candidatos:, desde_modulo:, tarjeta: Boolean`.

- [ ] **Step 1: El spec que falla**

```ruby
  describe "evolución" do
    let!(:gina) { member("gina@test.dev", :gestor) }

    let!(:challenge) do
      as_company(company) do
        c = create(:challenge, name: "Merma", ai_default_mode: "human")
        seed_form!(c.steps.create!(kind: "ideation", position: 1))
        c.steps.create!(kind: "evolution", position: 2, name: "Ronda")
        c
      end
    end

    before do
      postular!(challenge, author: paula, titulo: "Sensores")
      as_company(company) do
        challenge.pipeline.start!
        challenge.pipeline.advance!
      end
    end

    it "quien administra: progreso y quiénes acompañan a la derecha, gestores en los ajustes" do
      sign_in(admin, company: company)
      get challenge_step_path(challenge, paso("evolution"))

      expect(zonas[:referencia]).to include("Progreso", "Quiénes acompañan", "Cómo quedó configurado")
      expect(zonas[:ajustes]).to include("Ajustes del módulo", "Modo de IA", "Elegí a quién sumar")
      expect(documento.css(".panel").map { |n| n["class"] }).to eq([])
    end

    it "quien participa: sin quiénes acompañan y sin ajustes" do
      sign_in(paula, company: company)
      get challenge_step_path(challenge, paso("evolution"))

      expect(zonas[:referencia]).to include("Progreso", "Cómo quedó configurado")
      expect(zonas[:referencia]).not_to include("Quiénes acompañan")
      expect(documento.at_css(".ajustes")).to be_nil
    end
  end
```

Si la factory no acepta `:gestor` como rasgo de `membership`, usá `create(:membership, company: company, user: u, role: "gestor")` como en `dos_caras_spec`.

Run: `make spec-file FILE=spec/requests/pantalla_del_modulo_spec.rb`
Expected: FAIL en los dos nuevos.

- [ ] **Step 2: Quiénes acompañan, para leer**

Create `app/views/steps/_quienes_acompanan.html.haml`:

```haml
-# Quiénes acompañan este desafío, para LEER. Sumar y sacar gente vive en los
-# ajustes (`_asignaciones_gestores`). Con la MISMA guarda que la edición.
- if policy(step.challenge).update_pipeline?
  - asignados = step.challenge.challenge_gestores.includes(:user)
  .card
    .card-body
      %h3.section-title Quiénes acompañan
      - if asignados.any?
        %ul.field-list
          - asignados.each do |asignacion|
            %li.field-list__item
              %span= asignacion.user.name
              %span.field-list__type gestor
      - else
        %p.muted Nadie acompaña este desafío todavía.
```

- [ ] **Step 3: Gestores como bloque**

`app/views/challenges/_gestores.html.haml`: la línea `.panel` pasa a

```haml
= render layout: "steps/bloque", locals: { tarjeta: local_assigns.fetch(:tarjeta, true) } do
```

con el contenido a la misma indentación. Sumá al comentario de arriba: «En la ficha del desafío y en la cara de configuración es una tarjeta; en los ajustes del módulo, una sección (`tarjeta: false`).» La ficha del desafío (`challenges/show`) pasa así a `card` antes del 2b-bis: es un partial compartido y no se mantiene en dos formas.

`app/views/steps/_asignaciones_gestores.html.haml`:

```haml
- if policy(step.challenge).update_pipeline?
  = render "challenges/gestores", challenge: step.challenge, candidatos: candidates,
           desde_modulo: true, tarjeta: local_assigns.fetch(:tarjeta, true)
```

(Conservá sus comentarios.)

- [ ] **Step 4: La pantalla**

Reemplazá `app/views/steps/evolution.html.haml` entero:

```haml
- content_for :title, @step.name

-# Lo que se consulta mientras se acompaña la evolución.
- content_for :referencia do
  = render "steps/progreso", progress: @handler.progress
  = render "steps/quienes_acompanan", step: @step
  = render "steps/config_congelada", step: @step

= render "steps/header", step: @step, handler: @handler
= render "shared/ai_suggestions", suggestions: @pending_suggestions

-# Pedirle feedback a la IA es lo mismo que escribirlo: lo puede hacer quien
-# podría comentar esa idea. Para quien acompaña la evolución, es su trabajo.
- primera = @step.step_entries.first
- if primera && policy(FeedbackItem.new(idea: primera.idea, challenge_step: @step)).create?
  = render "shared/ai_actions", challenge: @challenge, mode: @step.effective_ai_mode,
           actions: [{ label: "Sugerir feedback con IA", purpose: "suggest_feedback", step_id: @step.id, idea_id: primera.idea_id }]

.feedback-board
  -# Quien participa ve solo las ideas en las que participa: el tablero de la
  -# evolución es la vista de quien acompaña, no la del resto del desafío.
  - visibles = @step.step_entries.includes(idea: %i[current_version author]).select { |e| @ideas_visibles.include?(e.idea_id) }
  - if visibles.empty?
    .card
      .card-body
        %p.muted Todavía no hay ideas tuyas en este módulo.
  - visibles.each do |entry|
    - items = @handler.feedback_for(entry.idea_id)
    - open_items = items.reject(&:addressed)
    .card.feedback-card
      .card-body
        .feedback-card__head
          %div
            = link_to entry.idea.title, challenge_idea_path(@challenge, entry.idea), class: "feedback-card__title"
            %p.muted
              = entry.idea.author.name
              %span{ class: chip("version") }= entry.idea.current_version&.label
          .feedback-card__state
            - if @handler.responded?(entry)
              %span{ class: chip_de_estado("completed") } actualizada
            - elsif open_items.any?
              %span{ class: chip_de_estado("pending") }= "#{open_items.size} sin atender"
            - if @step.active? && policy(entry.idea).update?
              = link_to "Responder editando la idea",
                        edit_challenge_idea_path(@challenge, entry.idea),
                        class: "btn btn-primary btn-sm"

        - if items.any?
          %ul.feedback-list
            - items.each do |item|
              = render "shared/feedback_item", item: item, challenge: @challenge
        - else
          %p.muted Todavía nadie dio feedback a esta idea.

        -# Comentar la idea ajena es de quien acompaña o juzga; quien participa,
        -# solo la suya. El botón no se ofrece si va a rebotar.
        - puede_comentar = policy(FeedbackItem.new(idea: entry.idea, challenge_step: @step)).create?
        - if @step.active? && puede_comentar
          = form_with url: challenge_step_feedback_items_path(@challenge, @step, idea_id: entry.idea_id), method: :post, class: "feedback-form" do
            = select_tag :kind, options_for_select(FeedbackItem::KINDS.map { |k| [t("flow.feedback_kinds.#{k}"), k] }), class: "feedback-form__kind"
            = text_field_tag :body, nil, placeholder: "Qué le falta o qué mejorarías", required: true
            = submit_tag "Comentar", class: "btn btn-ghost btn-sm"

-# Nombre, modo de IA y quiénes acompañan: se editan acá, pero casi nunca.
- if policy(@step).advance? || policy(@challenge).update_pipeline?
  = render layout: "steps/ajustes", locals: { resumen: "nombre, modo de IA y quiénes acompañan" } do
    = render "steps/ai_mode", step: @step
    = render "steps/asignaciones_gestores", step: @step, candidates: @gestor_candidates, tarjeta: false
```

- [ ] **Step 5: El CSS**

Las acciones de IA quedan sueltas en la columna del trabajo, donde el `gap` de `.app-main` ya separa. Junto a `.ai-actions` (~1289):

```css
/* Suelta en la columna del trabajo, el `gap` de `.app-main` ya la separa: el
   margen de abajo se sumaría y abriría un hueco. */
.app-main > .ai-actions { margin-bottom: 0; }
```

- [ ] **Step 6: Verde y mirar**

En `script/capture_screens.js`: `const MODULOS_EN_ZONAS = [/Evaluaci/i, /Corte a top|Finalistas/i, /Ronda de feedback/i];` (con lo que haya quedado de selección).

```bash
make yarn-build
make spec
make screens
```

Expected: verde, incluidos `gestor_spec` («Quiénes acompañan» por rol) y `dos_caras_spec` («deja asignar gestores antes de que el módulo arranque»). Mirá `09-2-step-ronda-de-feedback`, `96-oscuro-evolucion` y `04-challenge` (la tarjeta de gestores de la ficha, ahora `card`) contra `tmp/screenshots-antes-2b/`. Revisá el borde de color por tipo en los comentarios: sigue colgando de `.badge-*` hasta la Tarea 10.

- [ ] **Step 7: Commit**

```bash
git add app/views app/assets/stylesheets/application.css spec/requests/pantalla_del_modulo_spec.rb script/capture_screens.js
git commit -F - <<'EOF'
Evolución en tres zonas

El progreso, quiénes acompañan y la configuración van a la referencia; el
tablero de ideas con su feedback queda solo en el centro, y el modo de IA y
la asignación de gestores, plegados al final. `challenges/_gestores` toma su
forma de `steps/_bloque`, así que la ficha del desafío también pasa a `card`.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014gkhXcuX5q5pNYj9oZdAZU
EOF
```

---

### Task 7: Idear

**Files:**
- Create: `app/views/steps/_campos_lista.html.haml`
- Create: `app/views/steps/_campos_lectura.html.haml`
- Modify: `app/views/steps/ideation.html.haml` (entero)
- Modify: `app/views/steps/_campos_editor.html.haml`
- Modify: `spec/requests/pantalla_del_modulo_spec.rb`
- Modify: `script/capture_screens.js` (`MODULOS_EN_ZONAS`)

**Interfaces:**
- Consumes: `steps/_ajustes`, `steps/_bloque`, `steps/_progreso`, `steps/_config_congelada`, `steps/_ai_mode`.
- Produces: `render "steps/campos_lista", campos:` (la lista sola); `render "steps/campos_lectura", step:` (tarjeta con título); `render "steps/campos_editor", step:, suggestions: (opcional), tarjeta: Boolean`. La Tarea 9 consume `_campos_editor`.

- [ ] **Step 1: El spec que falla**

```ruby
  describe "idear" do
    let!(:challenge) do
      as_company(company) do
        c = create(:challenge, name: "Merma", ai_default_mode: "human")
        seed_form!(c.steps.create!(kind: "ideation", position: 1))
        c.steps.create!(kind: "evaluation", position: 2, name: "Técnica")
        c
      end
    end

    before { as_company(company) { challenge.pipeline.start! } }

    it "quien administra: el formulario leído a la derecha y el editor en los ajustes" do
      sign_in(admin, company: company)
      get challenge_step_path(challenge, paso("ideation"))

      expect(zonas[:referencia]).to include("Progreso", "Formulario de postulación", "Cómo quedó configurado")
      expect(documento.at_css('.ajustes [data-island="form-editor"]')).not_to be_nil
      expect(documento.css(".panel").map { |n| n["class"] }).to eq([])
    end

    it "quien participa: lee el formulario, sin editor ni ajustes" do
      sign_in(paula, company: company)
      get challenge_step_path(challenge, paso("ideation"))

      expect(zonas[:referencia]).to include("Formulario de postulación")
      expect(documento.at_css(".ajustes")).to be_nil
      expect(response.body).not_to include('data-island="form-editor"')
    end
  end
```

Run: `make spec-file FILE=spec/requests/pantalla_del_modulo_spec.rb`
Expected: FAIL en los dos nuevos.

- [ ] **Step 2: La lista y su lectura**

Create `app/views/steps/_campos_lista.html.haml`:

```haml
-# Los campos del formulario tal cual los ve quien postula, sin ningún control.
- if campos.any?
  %ul.field-list
    - campos.each do |field|
      %li.field-list__item
        %span.field-list__label
          = field.label
          - if field.required
            %span.field-list__req *
        %span.field-list__type= field.type_label
- else
  %p.muted Todavía no hay campos.
```

Create `app/views/steps/_campos_lectura.html.haml`:

```haml
-# El formulario de postulación, para leer, en la referencia de idear. Para
-# todos: quien postula ve lo mismo al postular. El editor vive en los ajustes.
.card
  .card-body
    %h3.section-title Formulario de postulación
    = render "steps/campos_lista", campos: step.form_fields.ordered
```

- [ ] **Step 3: El editor como bloque**

En `app/views/steps/_campos_editor.html.haml`, desde `.panel` (hoy línea 31) hasta el final, reemplazá por:

```haml
= render layout: "steps/bloque", locals: { tarjeta: local_assigns.fetch(:tarjeta, true) } do
  .section-head
    %h2.section-title Formulario de postulación
  %p.muted Estos son los campos que responde quien postula.

  - if puede_configurar
    - if local_assigns[:suggestions]
      = render "shared/ai_suggestions", suggestions: suggestions

    - if bloqueado
      .alert.alert-soft.alert-warning
        Ya hay ideas postuladas. Podés cambiar etiquetas, ayudas, obligatoriedad y orden, pero no el tipo ni la clave de un campo, ni quitarlo: las respuestas ya guardadas quedarían huérfanas.

    - if campos.empty?
      .panel
        %h2.section-title Todavía no hay campos
        %p.muted Sin formulario nadie puede postular. Empezá con los básicos, pedile una propuesta a la IA, o armalo a mano.
        .report-actions
          = button_to "Usar los tres básicos", seed_defaults_challenge_form_path(step.challenge), class: "btn btn-primary btn-sm"
          = render "shared/ai_actions", challenge: step.challenge, mode: step.effective_ai_mode, always: true,
                   actions: [{ label: "Proponer campos con IA", purpose: "suggest_form_fields", step_id: step.id }]
    - else
      = render "shared/ai_actions", challenge: step.challenge, mode: step.effective_ai_mode, always: true,
               actions: [{ label: "Rehacer el formulario con IA", purpose: "suggest_form_fields", step_id: step.id }]

    %div{ "data-island": "form-editor", data: { props: props.to_json } }
      .island-placeholder
        %p.muted Cargando el editor…

    = javascript_include_tag "packs/form_editor", defer: true, nonce: content_security_policy_nonce
  - else
    = render "steps/campos_lista", campos: campos
    %p.field-hint.field-hint--warn 🔒 Sólo quien administra el desafío puede cambiar esto.
```

Además de envolver en el bloque cambian tres cosas: la barra «Rehacer el formulario con IA» pierde su `.panel` (`.ai-actions` ya es un recuadro propio), el placeholder de la isla pierde el suyo (se reemplaza al montar) y la lista de lectura sale a `_campos_lista`. Las dos primeras son necesarias acá: el spec «no sirve ningún panel viejo» mira la cara de ejecución, donde el editor vive adentro de los ajustes. El `.panel` de «Todavía no hay campos» **se queda**: sólo aparece en la cara de configuración —idear no arranca sin formulario— y lo junta la Tarea 9.

- [ ] **Step 4: La pantalla**

Reemplazá `app/views/steps/ideation.html.haml` entero:

```haml
- content_for :title, "#{@step.name} · #{@challenge_name = @step.challenge.name}"

-# Lo que se consulta mientras se postula: cuántas van, qué pregunta el
-# formulario y cómo quedó configurado.
- content_for :referencia do
  = render "steps/progreso", progress: @handler.progress
  = render "steps/campos_lectura", step: @step
  = render "steps/config_congelada", step: @step

= render "steps/header", step: @step, handler: @handler
= render "shared/ai_suggestions", suggestions: @pending_suggestions

.card
  .card-body
    .section-head
      %h2.section-title
        Ideas postuladas
        %span.muted= " (#{@handler.submitted_ideas.count})"
      - if @step.active? && policy(Idea.new(challenge: @step.challenge)).create?
        = link_to "Postular una idea", new_challenge_idea_path(@step.challenge), class: "btn btn-primary btn-sm"
    = render "shared/ai_actions", challenge: @step.challenge, mode: @step.effective_ai_mode,
             actions: [{ label: "Generar ideas candidatas", purpose: "generate_ideas", step_id: @step.id,
                         count: 3, count_options: (1..Flow::AI::Tasks::GenerateIdeas::MAX_COUNT).to_a }]
    = render "ideas/list", ideas: @handler.submitted_ideas.includes(:current_version, :author).recent, challenge: @step.challenge

-# El formulario se sigue pudiendo corregir con el módulo abierto —su candado
-# es `ideas.submitted.exists?`, más fino que `touched?`—, pero casi nunca: va
-# plegado con el nombre y el modo de IA. Cada bloque trae su guarda.
- if policy(@step).advance? || policy(@step).manage_form?
  = render layout: "steps/ajustes", locals: { resumen: "nombre, modo de IA y el formulario" } do
    = render "steps/ai_mode", step: @step
    - if policy(@step).manage_form?
      = render "steps/campos_editor", step: @step, tarjeta: false
```

- [ ] **Step 5: Verde y mirar**

En `script/capture_screens.js`, sumá `/Postulaci/i` a `MODULOS_EN_ZONAS`, y después del bloque de los ajustes abiertos del comité:

```js
  // Los ajustes de idear abiertos: adentro está el editor del formulario, una
  // isla que monta plegada. Cerrado no tiene caja, y las guardas de contraste y
  // de clases no medirían nada de lo que pinta.
  if (ideacion) {
    await page.goto(BASE + ideacion.href, { waitUntil: 'networkidle' });
    await page.locator('details.ajustes__plegable').evaluate((el) => { el.open = true; });
    await page.waitForSelector('[data-island="form-editor"][data-island-mounted="true"]', { timeout: 15000 });
    await capturar(page, '09-18-ajustes-de-idear');
  }
```

(`ideacion` ya existe en el script: es el link del módulo de postulación que usa el chequeo del selector de cantidad.)

```bash
make yarn-build
make spec
make screens
```

Expected: verde, incluidos `ideas_spec` («muestra el formulario declarado, el progreso y las ideas»; «Postular una idea» no se ofrece donde no corresponde) y el chequeo `[IA]` del selector de cantidad («Generar ideas candidatas» sigue en el centro). La isla `form-editor` monta aunque esté plegada: `make screens` falla con `.island-placeholder` sin montar.

Mirá `09-1-step-postulaci-n-de-ideas` contra `tmp/screenshots-antes-2b/`, y abrí los ajustes a mano en el navegador para ver el editor adentro.

- [ ] **Step 6: Commit**

```bash
git add app/views spec/requests/pantalla_del_modulo_spec.rb script/capture_screens.js
git commit -F - <<'EOF'
Idear en tres zonas

El editor entero del formulario estaba entre el progreso y las ideas
postuladas. Pasa a los ajustes plegados, y a la referencia va el formulario
para leer —para todos, que es lo que ve quien postula—, junto con el
progreso y la configuración. «Postular una idea» sube al encabezado de la
lista sobre la que actúa.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014gkhXcuX5q5pNYj9oZdAZU
EOF
```

---

### Task 7b: Quien participa ve en idear sólo las ideas en las que participa

**Agregada después de la Tarea 7**, por decisión de Raúl sobre un hallazgo de su revisión. **No es del rediseño: es una fuga de lectura que ya estaba.** La pantalla de idear lista `@handler.submitted_ideas` sin filtrar, así que quien participa ve título y autor de TODAS las ideas postuladas. `CLAUDE.md` dice que ve sólo las que creó o en las que colabora, y `e3787a3` aplicó esa regla en evaluación, evolución y selección con `@ideas_visibles` —que publica `StepsController#show`— y advirtió: «la quinta que liste ideas se olvidaría». Idear es la quinta. Va en su propio commit para que se lea como lo que es.

El **progreso** de la referencia («5 de 5 ideas postuladas») se queda como está: es un agregado, no dice de quién es cada idea —la misma decisión que tomó `e3787a3` con el contador del corte—. El **contador del encabezado** de la lista sí pasa a contar lo que la lista muestra: «Ideas postuladas (5)» arriba de una sola fila se lee como un error.

**Files:**
- Modify: `app/views/steps/ideation.html.haml` (la tarjeta «Ideas postuladas»)
- Modify: `spec/requests/pantalla_del_modulo_spec.rb` (`describe "idear"`)

**Interfaces:**
- Consumes: `@ideas_visibles` (un `Set` de ids, `StepsController#show:33`, de `policy_scope(Idea)`); `postular!`, `member`, `documento`, `paso` del spec.

- [ ] **Step 1: El spec que falla**

En `spec/requests/pantalla_del_modulo_spec.rb`, adentro de `describe "idear"`:

1. El `before` pasa a confirmar que el módulo arrancó (la trampa de la Tarea 5: `start!` devuelve un resultado fallido sin levantar, y la pantalla sería la de configuración):

```ruby
    before do
      as_company(company) { challenge.pipeline.start! }
      expect(paso("ideation")).to be_active
    end
```

2. Los ejemplos nuevos:

```ruby
    describe "la lista de ideas postuladas" do
      let!(:pedro) { member("pedro@test.dev", :participant) }

      before do
        postular!(challenge, author: paula, titulo: "Sensores de peso")
        postular!(challenge, author: pedro, titulo: "Cámaras en la merma")
      end

      # Quien participa compite por el mismo corte que las demás: ve sólo las
      # ideas en las que participa (`IdeaPolicy::Scope`). Las otras pantallas
      # de módulo ya filtraban con `@ideas_visibles`; idear no.
      it "quien participa ve sólo la suya, y el contador cuenta lo que ve" do
        sign_in(paula, company: company)
        get challenge_step_path(challenge, paso("ideation"))

        lista = documento.css(".app-main .card").find { |c| c.text.include?("Ideas postuladas") }
        expect(lista.text).to include("Sensores de peso")
        expect(lista.text).not_to include("Cámaras en la merma")
        expect(lista.text).not_to include(pedro.name)
        expect(lista.at_css(".section-title").text).to include("(1)")
      end

      it "quien administra las ve todas" do
        sign_in(admin, company: company)
        get challenge_step_path(challenge, paso("ideation"))

        lista = documento.css(".app-main .card").find { |c| c.text.include?("Ideas postuladas") }
        expect(lista.text).to include("Sensores de peso", "Cámaras en la merma")
        expect(lista.at_css(".section-title").text).to include("(2)")
      end
    end
```

Run: `make spec-file FILE=spec/requests/pantalla_del_modulo_spec.rb`
Expected: FAIL en «quien participa ve sólo la suya» (ve «Cámaras en la merma» y el contador dice «(2)»). «Quien administra las ve todas» pasa: es la regla que ya se cumplía. Si la de quien participa **no** falla, pará: el fixture no reproduce la fuga (revisá que las dos ideas estén `submitted` y que `pedro.name` no sea igual al de `paula`).

- [ ] **Step 2: El filtro**

En `app/views/steps/ideation.html.haml`, arriba de la tarjeta:

```haml
-# Quien participa ve sólo las ideas en las que participa: compite por el mismo
-# corte que las demás. La regla vive en `IdeaPolicy::Scope` y llega como
-# `@ideas_visibles` (`StepsController#show`), igual que en los otros módulos.
-# El progreso de la referencia sigue contando todas: es un agregado, no dice
-# de quién es cada idea. El contador de acá cuenta lo que la lista muestra.
- postuladas = @handler.submitted_ideas.where(id: @ideas_visibles.to_a)
```

Y en la tarjeta, las dos líneas que usan `@handler.submitted_ideas`:

```haml
        %span.muted= " (#{postuladas.count})"
```

```haml
    = render "ideas/list", ideas: postuladas.includes(:current_version, :author).recent, challenge: @step.challenge
```

- [ ] **Step 3: Verde**

Run: `make spec-file FILE=spec/requests/pantalla_del_modulo_spec.rb`
Expected: PASS.

Run: `make spec`
Expected: verde. `ideas_spec` («muestra el formulario declarado, el progreso y las ideas», como admin) tiene que seguir pasando sin tocarlo.

Run: `make screens`
Expected: verde. `make screens` recorre como admin: `09-1-step-postulaci-n-de-ideas` no cambia.

- [ ] **Step 4: `CLAUDE.md`**

En «Los cuatro roles», en el bullet «**Quien participa ve solo las ideas en las que participa**», después de «los módulos filtran con eso lo que listan.», sumá: «Idear se lo olvidó hasta el plan 2b —listaba todas las postuladas—, que es exactamente lo que advertía `e3787a3`.»

- [ ] **Step 5: Commit**

```bash
git add app/views/steps/ideation.html.haml spec/requests/pantalla_del_modulo_spec.rb CLAUDE.md docs/superpowers/plans/2026-09-17-rediseno-2b-pantallas-de-modulo.md
git commit -F - <<'MSG'
Quien participa ve en idear sólo las ideas en las que participa

La pantalla de idear listaba todas las ideas postuladas, con título y autor,
a quien participa. La regla —ve sólo las que creó o en las que colabora—
vive en `IdeaPolicy::Scope` y llega como `@ideas_visibles`; evaluación,
evolución y selección ya filtraban con eso desde `e3787a3`, que advertía que
la quinta pantalla que listara ideas se iba a olvidar. Era idear.

El contador de la lista cuenta lo que la lista muestra. El progreso de la
referencia sigue contando todas: es un agregado y no dice de quién es cada
idea. No es del rediseño: la fuga estaba antes y la encontró la revisión de
la Tarea 7 del plan 2b.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014gkhXcuX5q5pNYj9oZdAZU
MSG
```

---

### Task 8: Reportería

**Files:**
- Create: `app/views/steps/_descargas.html.haml`
- Modify: `app/views/steps/reporting.html.haml` (entero)
- Modify: `spec/requests/pantalla_del_modulo_spec.rb`
- Modify: `script/capture_screens.js` (`MODULOS_EN_ZONAS`)
- Modify: `app/assets/stylesheets/application.css`

**Interfaces:**
- Consumes: `steps/_ajustes`, `steps/_config_congelada`, `steps/_ai_mode`, `chip(...)`.
- Produces: `render "steps/descargas", step:, handler:, data:`.

- [ ] **Step 1: El spec que falla**

```ruby
  describe "reportería" do
    let!(:challenge) do
      as_company(company) do
        c = create(:challenge, name: "Merma", ai_default_mode: "human")
        seed_form!(c.steps.create!(kind: "ideation", position: 1))
        c.steps.create!(kind: "reporting", position: 2, name: "Informe")
        c
      end
    end

    before do
      postular!(challenge, author: paula, titulo: "Sensores")
      as_company(company) do
        challenge.pipeline.start!
        challenge.pipeline.advance!
      end
    end

    it "quien administra: configuración y descargas a la derecha, el reporte al centro" do
      sign_in(admin, company: company)
      get challenge_step_path(challenge, paso("reporting"))

      expect(zonas[:referencia]).to include("Cómo quedó configurado", "Descargas", "Excel", "PDF")
      expect(zonas[:referencia]).not_to include("Embudo")
      expect(zonas[:ajustes]).to include("Ajustes del módulo", "Modo de IA")
      expect(documento.css(".panel").map { |n| n["class"] }).to eq([])
    end
  end
```

Run: `make spec-file FILE=spec/requests/pantalla_del_modulo_spec.rb`
Expected: FAIL.

- [ ] **Step 2: Las descargas**

Create `app/views/steps/_descargas.html.haml`:

```haml
-# Generar Excel y PDF, y los archivos ya generados. Son herramientas que se
-# usan al costado del reporte, no el reporte: van en la referencia. La tabla
-# de cinco columnas que había no entra en la columna, así que es lista.
- downloadable = handler.reports.select { |r| r.format != "dashboard" }
.card
  .card-body
    %h3.section-title Descargas
    %p.muted
      Modo
      %strong= t("flow.report_modes.#{data['mode']}")
      = data["mode"] == "by_version" ? "· cada puntaje dice sobre qué versión se evaluó." : "· solo la versión vigente."
    .report-actions
      = button_to "Excel", challenge_step_reports_path(step.challenge, step, format_kind: "xlsx"),
                  params: { format: "xlsx", kind: "snapshot" }, class: "btn btn-ghost btn-sm"
      = button_to "PDF", challenge_step_reports_path(step.challenge, step),
                  params: { format: "pdf", kind: "snapshot" }, class: "btn btn-ghost btn-sm"

    - if downloadable.any?
      %ul.field-list
        - downloadable.each do |report|
          %li.field-list__item{ id: "report-#{report.id}" }
            %span
              %strong= report.format.upcase
              - if report.ready?
                %span{ class: chip_de_estado("completed") } listo
              - elsif report.stalled? || report.failed?
                %span{ class: chip_de_estado("skipped") } falló
              - else
                %span{ class: chip_de_estado("active") } generando…
              %br
              %span.muted
                = report.generated_at ? l(report.generated_at, format: :short) : "—"
                = "· #{report.row_count} filas" if report.row_count
            - if report.ready? && report.file.attached?
              = link_to "Descargar", rails_blob_path(report.file, disposition: "attachment"), class: "btn btn-ghost btn-sm"
```

- [ ] **Step 3: La pantalla**

Reemplazá `app/views/steps/reporting.html.haml` entero:

```haml
- content_for :title, @step.name

- data = @handler.dashboard
- narrative = @handler.reports.detect { |r| r.kind == "narrative" && r.ready? }

-# Reportería no tiene progreso: la referencia se lleva la configuración y las
-# descargas, y el centro es el reporte.
- content_for :referencia do
  = render "steps/config_congelada", step: @step
  = render "steps/descargas", step: @step, handler: @handler, data: data

= render "steps/header", step: @step, handler: @handler
= render "shared/ai_suggestions", suggestions: @pending_suggestions

-# El pedido del resumen a la IA va donde aparece lo que produce.
- resumen_con_ia = { label: narrative ? "Rehacer el resumen narrativo" : "Resumen narrativo", purpose: "summarize_challenge", step_id: @step.id }
- if narrative
  .card.narrative-card
    .card-body
      %h2.section-title
        Resumen narrativo
        %span{ class: chip_de_ia } IA
      = render "shared/ai_actions", challenge: @challenge, mode: @step.effective_ai_mode, actions: [resumen_con_ia]
      %p.narrative-card__summary= narrative.data["summary"]
      - if narrative.data["themes"].present?
        .theme-grid
          - narrative.data["themes"].each do |theme|
            .theme-card
              %span.theme-card__count= theme["count"]
              %strong= theme["name"]
              %span.muted= theme["note"]
      - if narrative.data["left_behind"].present?
        %p.narrative-card__left
          %strong Lo que quedó afuera:
          = narrative.data["left_behind"]
- else
  = render "shared/ai_actions", challenge: @challenge, mode: @step.effective_ai_mode, actions: [resumen_con_ia]

.card
  .card-body
    %h2.section-title Embudo
    .funnel
      - data["funnel"].each do |stage|
        - max = data["funnel"].map { _1["entered"] }.max.to_f
        .funnel__stage
          .funnel__bar{ style: "width: #{max.positive? ? (stage['entered'] / max * 100).round : 0}%" }
          .funnel__meta
            %strong= stage["name"]
            %span.muted= "#{stage['entered']} entraron"
            - if stage["eliminated"].positive?
              %span.funnel__lost= "−#{stage['eliminated']}"

- if data["ranking"].any?
  .card
    .card-body
      %h2.section-title Ranking
      .table-scroll
        %table.table
          %thead
            %tr
              %th #
              %th Idea
              %th Autor
              %th Puntaje
              %th Evaluada sobre
              %th Estado
          %tbody
            - data["ranking"].each do |row|
              %tr
                %td.muted= row["rank"]
                %td
                  = row["title"]
                  - if row["origin"] == "ai"
                    %span{ class: chip_de_ia } IA
                %td.muted= row["author"]
                %td
                  %strong= "#{(row['score'] * 100).round(1)}%"
                %td.muted
                  %span{ class: chip("version") }= row["version"]
                  - if row["stale"]
                    %span{ class: chip("desactualizada"), title: "La idea cambió después de evaluarse" }= "→ #{row['current_version']}"
                %td
                  %span{ class: chip_de_estado(row["status"] == "active" ? "active" : "skipped") }
                    = t("flow.idea_statuses.#{row['status']}")

- if data["distribution"].any?
  .card
    .card-body
      %h2.section-title Distribución de puntajes
      .histogram
        - max = data["distribution"].map { _1["count"] }.max.to_f
        - data["distribution"].each do |bucket|
          .histogram__col
            .histogram__bar{ style: "height: #{max.positive? ? (bucket['count'] / max * 100).round : 0}%",
                             title: "#{bucket['count']} ideas" }
            %span.histogram__label= bucket["label"].split("–").first
            %span.histogram__count= bucket["count"]

- if data["evaluators"].any?
  .card
    .card-body
      %h2.section-title Participación de evaluadores
      .table-scroll
        %table.table
          %thead
            %tr
              %th Módulo
              %th Asignados
              %th Evaluaron
              %th Evaluaciones
          %tbody
            - data["evaluators"].each do |row|
              %tr
                %td= row["step"]
                %td.muted= row["expected"]
                %td= "#{row['submitted']} / #{row['expected']}"
                %td.muted= row["assessments"]

- matrix = data["matrix"]
- if matrix["columns"].any?
  .card
    .card-body
      %h2.section-title
        Matriz por módulo
        - if data["mode"] == "by_version"
          %span.muted · cada celda con la versión que se evaluó
      .table-scroll
        %table.table
          %thead
            %tr
              %th Idea
              - matrix["columns"].each do |column|
                %th= column["name"]
          %tbody
            - matrix["rows"].each do |row|
              %tr
                %td= row["title"]
                - row["cells"].each do |cell|
                  %td
                    - if cell["score"]
                      %strong= "#{(cell['score'] * 100).round}%"
                      - if cell["version"]
                        %span{ class: chip("version") }= cell["version"]
                    - else
                      %span.muted —

- if policy(@step).advance?
  = render layout: "steps/ajustes", locals: { resumen: "nombre y modo de IA" } do
    = render "steps/ai_mode", step: @step

= render "shared/reports_auto_refresh", challenge: @challenge, step: @step
```

Antes de seguir, compará el contenido del embudo, ranking, distribución, participación y matriz con `git show HEAD:app/views/steps/reporting.html.haml`: las únicas diferencias permitidas son `.panel` → `.card > .card-body`, las tablas adentro de `.table-scroll` y la indentación.

- [ ] **Step 4: El CSS**

Adentro de la tarjeta del resumen, el recuadro de IA va antes del texto: junto a `.narrative-card` (~1555):

```css
.narrative-card .ai-actions { margin-bottom: 4px; }
```

- [ ] **Step 5: Verde y mirar**

En `script/capture_screens.js`, sumá `/Reporte/i` a `MODULOS_EN_ZONAS`.

```bash
make yarn-build
make spec
make screens
```

Expected: verde. Mirá `09-7-step-reporte-de-cierre` y `97-oscuro-reporteria` contra `tmp/screenshots-antes-2b/`: la matriz y el ranking en el centro más angosto, y las descargas en 320px.

- [ ] **Step 6: Commit**

```bash
git add app/views app/assets/stylesheets/application.css spec/requests/pantalla_del_modulo_spec.rb script/capture_screens.js
git commit -F - <<'EOF'
Reportería en tres zonas

Sin progreso que mostrar, la referencia se lleva la configuración y las
descargas —Excel, PDF y los archivos generados, ahora en lista porque la
tabla no entra—. El centro es el reporte, con el pedido del resumen a la IA
junto al resumen. Las tablas anchas se desplazan adentro de su tarjeta.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014gkhXcuX5q5pNYj9oZdAZU
EOF
```

---

### Task 8b: Quien participa ve en reportería lo agregado y sus propias ideas

**Agregada después de la Tarea 8**, por decisión de Raúl. **No es del rediseño: es una sospecha de fuga de lectura que ya estaba**, del mismo tipo que la de idear (Tarea 7b). La cara de ejecución de reportería no tiene ninguna guarda de vista, así que el tablero —ranking con autor y puntaje de TODAS las ideas, matriz por módulo, resumen narrativo que nombra ideas— se dibuja para cualquiera que llegue al desafío, incluido quien participa. `participant_rules_spec` dice «El reporte trae el ranking entero: es justo lo que no ve en pantalla», pero sólo prueba que no puede GENERAR el archivo. **Lo primero es confirmarla con un spec**; si no se confirma, se para.

Qué ve cada quien (decisión de Raúl, la misma forma que selección):

| Bloque | Quien participa | Quien administra, acompaña o evalúa |
|---|---|---|
| Embudo, distribución, participación de evaluadores | Sí: son conteos, no dicen de quién es cada idea | Sí |
| Ranking y matriz | Sólo las filas de sus ideas (`@ideas_visibles`) | Todas |
| Resumen narrativo | No: nombra ideas ajenas | Sí |
| Pedido del resumen a la IA | No | Sólo quien puede pedirlo (`ChallengePolicy#update_pipeline?`, el alcance `:challenge` de `summarize_challenge`) |
| Descargas (Excel, PDF y archivos generados) | No | Sólo `ChallengeStepPolicy#report?` |

Las dos últimas filas también le sacan controles a quien acompaña o evalúa: hoy los ve y le rebotan con 403 —generar pide `report?`, pedir el resumen pide `update_pipeline?`—, que es el control que no responde. Y los archivos generados traen el ranking entero por un link de Active Storage que no pasa por Pundit: no se le muestran a quien no puede generarlos. Todas las ideas que ve quien no participa siguen siendo todas: para esos roles `@ideas_visibles` es el pool entero.

**Files:**
- Modify: `app/views/steps/reporting.html.haml`
- Modify: `app/views/steps/_descargas.html.haml`
- Modify: `spec/requests/pantalla_del_modulo_spec.rb` (`describe "reportería"`)
- Modify: `spec/requests/participant_rules_spec.rb` (el comentario de ~130)
- Modify: `CLAUDE.md` («Los cuatro roles»)

**Interfaces:**
- Consumes: `@ideas_visibles` (`Set` de ids, `StepsController#show`); las filas de `data["ranking"]` y `data["matrix"]["rows"]` traen `"idea_id"` (`Flow::Reports::Builder`, ~77 y ~141); `current_membership` (disponible en las vistas); `postular!`, `member`, `documento`, `zonas`, `paso` del spec.

- [ ] **Step 1: Confirmar la fuga con un spec que falla**

En `spec/requests/pantalla_del_modulo_spec.rb`, adentro de `describe "reportería"`, un `describe` nuevo con su propio desafío —el del `describe` padre no tiene evaluación, así que su ranking y su matriz están vacíos y no pueden mostrar ninguna fuga—:

```ruby
    describe "lo que ve cada quien" do
      let!(:pedro) { member("pedro@test.dev", :participant) }

      let!(:challenge) do
        as_company(company) do
          c = create(:challenge, name: "Merma", ai_default_mode: "human")
          seed_form!(c.steps.create!(kind: "ideation", position: 1))
          c.steps.create!(kind: "evaluation", position: 2, name: "Técnica", config: { "min_assessments" => 1 })
          c.steps.create!(kind: "reporting", position: 3, name: "Informe")
          c
        end
      end

      before do
        postular!(challenge, author: paula, titulo: "Sensores de peso")
        postular!(challenge, author: pedro, titulo: "Cámaras en la merma")
        as_company(company) do
          challenge.pipeline.start!
          challenge.pipeline.advance!
          evaluacion = challenge.steps.reload.find(&:evaluation?)
          challenge.ideas.each do |idea|
            evaluacion.assessments.create!(idea: idea, idea_version_id: idea.current_version_id,
                                           evaluator: elena, actor_type: "human", status: "submitted",
                                           submitted_at: Time.current, normalized_score: 0.6)
            evaluacion.handler.recompute_entry!(StepEntry.find_by(challenge_step_id: evaluacion.id, idea_id: idea.id))
          end
          challenge.pipeline.advance!
          informe = challenge.steps.reload.find(&:reporting?)
          # Un resumen narrativo listo, que nombra una idea ajena a quien participa.
          Report.create!(challenge_step: informe, kind: "narrative", format: "dashboard", status: "ready",
                         data: { "summary" => "«Cámaras en la merma» quedó última por esfuerzo." })
        end
        expect(paso("reporting")).to be_active
      end

      def tarjeta(titulo) = documento.css(".app-main .card").find { |c| c.at_css(".section-title")&.text.to_s.include?(titulo) }

      it "quien participa: lo agregado y sus ideas, sin resumen ni descargas" do
        sign_in(paula, company: company)
        get challenge_step_path(challenge, paso("reporting"))

        expect(tarjeta("Embudo")).not_to be_nil
        expect(tarjeta("Ranking").text).to include("Sensores de peso")
        expect(tarjeta("Ranking").text).not_to include("Cámaras en la merma")
        expect(tarjeta("Matriz por módulo").text).not_to include("Cámaras en la merma")
        expect(response.body).not_to include("quedó última por esfuerzo")
        expect(zonas[:referencia]).not_to include("Descargas")
      end

      it "quien evalúa: el pool entero, sin descargas ni pedido a la IA" do
        sign_in(elena, company: company)
        get challenge_step_path(challenge, paso("reporting"))

        expect(tarjeta("Ranking").text).to include("Sensores de peso", "Cámaras en la merma")
        expect(response.body).to include("quedó última por esfuerzo")
        expect(zonas[:referencia]).not_to include("Descargas")
      end

      it "quien administra: todo" do
        sign_in(admin, company: company)
        get challenge_step_path(challenge, paso("reporting"))

        expect(tarjeta("Ranking").text).to include("Sensores de peso", "Cámaras en la merma")
        expect(response.body).to include("quedó última por esfuerzo")
        expect(zonas[:referencia]).to include("Descargas", "Excel", "PDF")
      end
    end
```

El fixture es una guía: si `advance!` no llega a reportería (el `be_active` lo dice), leé `Flow::Pipeline#advance!` y `Flow::Handlers::Evaluation#can_complete?` y ajustá lo mínimo; si `Report.create!` pide otro campo, mirá `app/models/report.rb`. Reportá cada ajuste.

Run: `make spec-file FILE=spec/requests/pantalla_del_modulo_spec.rb`
Expected: FAIL en «quien participa» (ve «Cámaras en la merma», el resumen y las descargas) y en «quien evalúa» (ve las descargas). «Quien administra: todo» pasa. **Si «quien participa» no falla por la fuga** —por ejemplo, porque la pantalla ya no le muestra el ranking—, pará y reportá BLOCKED con la salida: la sospecha no se confirmó y no hay nada que arreglar.

- [ ] **Step 2: El filtro en la pantalla**

En `app/views/steps/reporting.html.haml`, debajo de `- narrative = …`:

```haml
-# Quien participa ve lo agregado y sus propias ideas, igual que en selección:
-# el embudo, la distribución y la participación son conteos y no dicen de
-# quién es cada idea; el ranking y la matriz se filtran con `@ideas_visibles`
-# (`IdeaPolicy::Scope`, que para quien administra, acompaña o evalúa es el
-# pool entero). El resumen narrativo nombra ideas ajenas: no se le muestra.
- ve_el_pool = !current_membership.participant?
- ranking = data["ranking"].select { |row| @ideas_visibles.include?(row["idea_id"]) }
- matrix = data["matrix"]
- filas_de_matriz = matrix["rows"].select { |row| @ideas_visibles.include?(row["idea_id"]) }
-# Pedir el resumen es `summarize_challenge`, de alcance `:challenge`: lo
-# autoriza `update_pipeline?`. Sin esto quien acompaña o evalúa veía un botón
-# que le rebotaba con 403.
- pide_resumen = policy(@challenge).update_pipeline?
```

Y en el cuerpo:

1. El resumen: `- if narrative` pasa a `- if narrative && ve_el_pool`; adentro, el `= render "shared/ai_actions" …` pasa a estar detrás de `- if pide_resumen`. El `- else` (pedido suelto, sin resumen) pasa a `- elsif pide_resumen`.
2. El ranking: `- if data["ranking"].any?` pasa a `- if ranking.any?`, y `- data["ranking"].each do |row|` pasa a `- ranking.each do |row|`.
3. La matriz: borrá la línea `- matrix = data["matrix"]` que está más abajo (ya está arriba); `- if matrix["columns"].any?` pasa a `- if matrix["columns"].any? && filas_de_matriz.any?`, y `- matrix["rows"].each do |row|` pasa a `- filas_de_matriz.each do |row|`.

Embudo, distribución y participación no cambian.

- [ ] **Step 3: Las descargas, sólo para quien puede generarlas**

En `app/views/steps/_descargas.html.haml`, todo lo que no es el comentario de arriba pasa a colgar de un único `if`:

```haml
-# Sólo quien puede generarlos (`report?`): los archivos traen el ranking
-# entero, y el link de Active Storage no pasa por Pundit. Sin esto quien
-# acompaña o evalúa veía dos botones que le rebotaban con 403.
- if policy(step).report?
  - downloadable = handler.reports.select { |r| r.format != "dashboard" }
  .card
    -# (el resto del partial, un nivel más adentro, sin cambios)
```

(Pegá el contenido actual de la tarjeta un nivel más adentro; no dejes el comentario de paréntesis.)

- [ ] **Step 4: Verde**

Run: `make spec-file FILE=spec/requests/pantalla_del_modulo_spec.rb`
Expected: PASS.

Run: `make spec`
Expected: verde, incluido `participant_rules_spec` («no puede generar el reporte»).

Run: `make yarn-build && make screens`
Expected: verde. El recorrido es como admin: `09-7-step-reporte-de-cierre` y `97-oscuro-reporteria` no cambian.

- [ ] **Step 5: El comentario viejo y `CLAUDE.md`**

En `spec/requests/participant_rules_spec.rb` (~130), el comentario «El reporte trae el ranking entero: es justo lo que no ve en pantalla.» pasa a: «El reporte trae el ranking entero: en pantalla ve lo agregado y sus propias ideas (`pantalla_del_modulo_spec`, reportería), y el archivo no lo puede generar.»

En `CLAUDE.md`, «Los cuatro roles», al final del bullet de «Quien participa ve solo las ideas en las que participa» (después de lo que sumó la Tarea 7b), agregá: «En reportería ve lo agregado —embudo, distribución, participación— y el ranking y la matriz filtrados a sus ideas; el resumen narrativo no, porque nombra ideas ajenas. Hasta el plan 2b veía el tablero entero.»

- [ ] **Step 6: Commit**

```bash
git add app/views/steps/reporting.html.haml app/views/steps/_descargas.html.haml spec/requests/pantalla_del_modulo_spec.rb spec/requests/participant_rules_spec.rb CLAUDE.md docs/superpowers/plans/2026-09-17-rediseno-2b-pantallas-de-modulo.md
git commit -F - <<'MSG'
Quien participa ve en reportería lo agregado y sus propias ideas

La pantalla de reportería no tenía guarda de vista: quien participa veía el
ranking con autor y puntaje de todas las ideas, la matriz por módulo y el
resumen narrativo, que nombra ideas ajenas. El spec de reglas decía que eso
no lo veía en pantalla y sólo probaba que no podía generar el archivo.

Ahora ve lo agregado —embudo, distribución, participación— y el ranking y la
matriz filtrados con `@ideas_visibles`, igual que selección; el resumen no.
Las descargas y el pedido del resumen a la IA quedan para quien puede usarlos
(`report?`, `update_pipeline?`): a quien acompaña o evalúa le rebotaban con
403, y los archivos traen el ranking entero por un link que no pasa por
Pundit. No es del rediseño: lo encontró el plan 2b al mudar la pantalla.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014gkhXcuX5q5pNYj9oZdAZU
MSG
```

---

### Task 9: Las cinco caras de configuración

Una sola columna, en el orden de hoy. Lo que cambia es juntar lo que está partido y pasar a `card`.

**Files:**
- Modify: `app/views/steps/config/_modulo.html.haml`
- Modify: `app/views/steps/_criterios_editor.html.haml`
- Modify: `app/views/steps/_campos_editor.html.haml`
- Modify: `spec/requests/pantalla_del_modulo_spec.rb`

**Interfaces:**
- Consumes: `steps/_bloque`; `_campos_editor` con `tarjeta` (T7); `_asignaciones_evaluadores` (T3) y `challenges/_gestores` (T6), que ya son `card` por default.

- [ ] **Step 1: El spec que falla**

```ruby
  describe "la cara de configuración" do
    let!(:challenge) do
      as_company(company) do
        c = create(:challenge, name: "Merma", ai_default_mode: "human")
        c.steps.create!(kind: "ideation", position: 1)
        c.steps.create!(kind: "evolution", position: 2, name: "Ronda")
        c.steps.create!(kind: "evaluation", position: 3, name: "Técnica")
        c.steps.create!(kind: "selection", position: 4, name: "Corte")
        c.steps.create!(kind: "reporting", position: 5, name: "Informe")
        c
      end
    end

    it "no sirve ningún panel viejo en los cinco kinds" do
      sign_in(admin, company: company)

      %w[ideation evolution evaluation selection reporting].each do |kind|
        get challenge_step_path(challenge, paso(kind))
        expect(documento.css(".panel").map { |n| n["class"] }).to eq([]), "quedó un .panel en #{kind}"
      end
    end

    # Lo que estaba partido en tarjetas sueltas con una sola cosa adentro: el
    # título, la descripción y la acción de IA de un bloque van juntos.
    it "el título de los criterios y su acción de IA están en la misma tarjeta" do
      sign_in(admin, company: company)
      get challenge_step_path(challenge, paso("evaluation"))

      tarjeta = documento.css(".card").find { |c| c.at_css(".section-title")&.text.to_s.include?("Los criterios") }
      expect(tarjeta).not_to be_nil
      expect(tarjeta.text).to include("Proponer criterios con IA")
    end

    it "el título del formulario y su acción de IA están en la misma tarjeta" do
      sign_in(admin, company: company)
      get challenge_step_path(challenge, paso("ideation"))

      tarjeta = documento.css(".card").find { |c| c.at_css(".section-title")&.text.to_s.include?("Formulario de postulación") }
      expect(tarjeta).not_to be_nil
      expect(tarjeta.text).to include("Proponer campos con IA")
    end
  end
```

Run: `make spec-file FILE=spec/requests/pantalla_del_modulo_spec.rb`
Expected: FAIL en los tres.

- [ ] **Step 2: El módulo**

`app/views/steps/config/_modulo.html.haml`, la línea `    .panel` adentro del `form_with` pasa a:

```haml
    .card
      .card-body
```

y todo lo que colgaba de ella baja un nivel.

- [ ] **Step 3: Los criterios, juntos**

En `app/views/steps/_criterios_editor.html.haml`, reemplazá desde el primer `.panel` (el encabezado) hasta el final del archivo por:

```haml
-# Una tarjeta por bloque: el título, qué es, el aviso y la acción de IA van
-# juntos. Eran cuatro bloques sueltos, dos de ellos tarjetas con una sola cosa
-# adentro. Las propuestas de la IA van DESPUÉS de la tarjeta —donde aparece lo
-# que se le pidió— y la isla, al final. Sus tarjetas internas son del plan 2c.
.card
  .card-body
    .section-head
      %h2.section-title= step.selection? ? "Los filtros" : "Los criterios"
    %p.muted= step.selection? ? "Condiciones que la idea tiene que cumplir para avanzar. Se aplican antes del corte." : "Con qué se puntúa cada idea en este módulo."

    - if puede_configurar
      - if set.nil?
        - nueva_version = step.criteria_set&.newer_version
        - asignables = CriteriaSet.asignables_para(step)
        %h3.section-title Este módulo todavía no tiene criterios propios
        - if step.criteria_set
          %p.muted
            Hoy usa
            %strong= step.criteria_set.label
            de la biblioteca, que comparten otros desafíos. Editarlo desde acá los tocaría a todos.
          - if nueva_version
            %p.field-hint.field-hint--warn
              = "Hay una versión más nueva (#{nueva_version.label}). Este módulo sigue con la que tiene hasta que alguien lo pase."
        - else
          %p.muted Sin criterios propios se van a usar los genéricos: impacto, factibilidad y esfuerzo.

        .report-actions
          - if nueva_version
            = button_to "Pasarlo a #{nueva_version.label}", challenge_step_path(step.challenge, step),
                        method: :patch, params: { challenge_step: { criteria_set_id: nueva_version.id } },
                        class: "btn btn-ghost btn-sm"
          - if step.criteria_set
            = button_to "Copiar ese set y hacerlo propio", challenge_step_criteria_path(step.challenge, step, from: "library"),
                        class: "btn btn-primary btn-sm"
          - else
            = button_to "Usar los tres genéricos y editarlos", challenge_step_criteria_path(step.challenge, step, from: "defaults"),
                        class: "btn btn-primary btn-sm"
          = button_to "Empezar en blanco", challenge_step_criteria_path(step.challenge, step, from: "blank"),
                      class: "btn btn-ghost btn-sm"
          = render "shared/ai_actions", challenge: step.challenge, mode: step.effective_ai_mode, always: true,
                   actions: [{ label: "Proponer criterios con IA", purpose: "suggest_criteria", step_id: step.id }]

        - if asignables.any?
          = form_with model: step, url: challenge_step_path(step.challenge, step), method: :patch do |f|
            .field
              = f.label :criteria_set_id, step.selection? ? "O usá un set de filtros de la biblioteca" : "O usá un set de criterios de la biblioteca"
              = f.select :criteria_set_id,
                         asignables.map { |candidato| ["#{candidato.label} — #{Flow::Texto.contar(candidato.active_criteria.size, "criterio")}", candidato.id] },
                         { include_blank: step.selection? ? "Sin filtros" : "Criterios genéricos (impacto, factibilidad y esfuerzo)" }
              %p.field-hint Se comparte entre desafíos: acá se elige cuál usa este módulo, no se edita. Queda fijo en cuanto el módulo arranca.
            .form-actions
              = f.submit "Usar ese set", class: "btn btn-ghost btn-sm"
      - else
        .alert.alert-soft.alert-success
          %div
            Estos criterios son de este módulo: no afectan a otros desafíos.
            = link_to "Guardarlos también en la biblioteca", promote_criteria_set_path(set),
                      data: { turbo_method: :post }, class: "field-hint__link"
        = render "shared/ai_actions", challenge: step.challenge, mode: step.effective_ai_mode, always: true,
                 actions: [{ label: "Rehacer los criterios con IA", purpose: "suggest_criteria", step_id: step.id }]
    - else
      - efectivo = step.criteria_set
      - if efectivo
        %p.muted
          = efectivo.inline? ? "Criterios propios de este módulo" : "De la biblioteca: #{efectivo.name}"
          = " · #{Flow::Texto.contar(efectivo.active_criteria.size, 'criterio')}"
        %ul.field-list
          - efectivo.active_criteria.each do |criterion|
            %li.field-list__item
              %span.field-list__label
                = criterion.name
                %span.criterion-field__weight= "#{(criterion.weight.to_f * 100).round}%"
              %span.field-list__type= criterion.summary
      - else
        %p.muted Sin criterios propios: usa los genéricos (impacto, factibilidad y esfuerzo).
      %p.field-hint.field-hint--warn 🔒 Sólo quien administra el desafío puede cambiar esto.

- if puede_configurar
  = render "shared/ai_suggestions", suggestions: suggestions
  - unless set.nil?
    %div{ "data-island": "criteria-editor", data: { props: props.to_json } }
      .card
        .card-body.island-placeholder
          %p.muted Cargando el editor de criterios…

    = javascript_include_tag "packs/criteria_editor", defer: true, nonce: content_security_policy_nonce
```

**Mantené los comentarios `-#` del archivo original** que explican las guardas (el «un solo `if puede_configurar`» y por qué): movelos arriba del `.card`. Ojo: ahora hay **dos** `if puede_configurar` —uno adentro de la tarjeta y otro para las propuestas y la isla—. Actualizá ese comentario para decir por qué son dos y que las dos preguntan lo mismo.

Compará con el original antes de seguir:

```bash
git diff HEAD -- app/views/steps/_criterios_editor.html.haml
```

Las únicas diferencias permitidas: el reagrupamiento en una tarjeta, `.panel` de «todavía no tiene criterios propios» → `%h3` adentro de la misma tarjeta, las propuestas de la IA después de la tarjeta, la barra «Rehacer» sin su `.panel`, y el placeholder en `card`.

- [ ] **Step 4: El formulario, junto**

En `app/views/steps/_campos_editor.html.haml` (de la Tarea 7), sacá las propuestas y la isla de adentro del bloque, y juntá «Todavía no hay campos» con el encabezado:

```haml
= render layout: "steps/bloque", locals: { tarjeta: local_assigns.fetch(:tarjeta, true) } do
  .section-head
    %h2.section-title Formulario de postulación
  %p.muted Estos son los campos que responde quien postula.

  - if puede_configurar
    - if bloqueado
      .alert.alert-soft.alert-warning
        Ya hay ideas postuladas. Podés cambiar etiquetas, ayudas, obligatoriedad y orden, pero no el tipo ni la clave de un campo, ni quitarlo: las respuestas ya guardadas quedarían huérfanas.

    - if campos.empty?
      %h3.section-title Todavía no hay campos
      %p.muted Sin formulario nadie puede postular. Empezá con los básicos, pedile una propuesta a la IA, o armalo a mano.
      .report-actions
        = button_to "Usar los tres básicos", seed_defaults_challenge_form_path(step.challenge), class: "btn btn-primary btn-sm"
        = render "shared/ai_actions", challenge: step.challenge, mode: step.effective_ai_mode, always: true,
                 actions: [{ label: "Proponer campos con IA", purpose: "suggest_form_fields", step_id: step.id }]
    - else
      = render "shared/ai_actions", challenge: step.challenge, mode: step.effective_ai_mode, always: true,
               actions: [{ label: "Rehacer el formulario con IA", purpose: "suggest_form_fields", step_id: step.id }]
  - else
    = render "steps/campos_lista", campos: campos
    %p.field-hint.field-hint--warn 🔒 Sólo quien administra el desafío puede cambiar esto.

-# Las propuestas van después del bloque —donde aparece lo que se le pidió a
-# la IA— y la isla al final. Mismo `puede_configurar` que adentro del bloque.
- if puede_configurar
  - if local_assigns[:suggestions]
    = render "shared/ai_suggestions", suggestions: suggestions

  %div{ "data-island": "form-editor", data: { props: props.to_json } }
    .island-placeholder
      %p.muted Cargando el editor…

  = javascript_include_tag "packs/form_editor", defer: true, nonce: content_security_policy_nonce
```

**En la cara de ejecución** (`tarjeta: false`, adentro de los ajustes) la isla queda ahora afuera de la `%section`, pero sigue adentro de `.ajustes__contenido`, que es un `yield`: lo que el partial renderiza entero va adentro de los ajustes. Verificalo con el spec de idear de la Tarea 7 (`.ajustes [data-island="form-editor"]`).

- [ ] **Step 5: Verde, y `Flow::Setup` a mano**

Run: `make spec`
Expected: verde, incluidos `dos_caras_spec` (la isla de ajustes en los cinco kinds; `setup-nav` en cada kind), `paso_a_paso_spec`, `step_criteria_spec` y `form_fields_spec`.

**A mano** (la suite ya no lo vio dos veces, `2029528` y `df0681d`): confirmá que las cinco caras siguen dibujando el pie del paso a paso:

```bash
grep -n 'setup_nav' app/views/steps/config/*.html.haml
```

Expected: una línea por cada uno de `evaluation`, `evolution`, `ideation`, `reporting`, `selection`.

- [ ] **Step 6: Mirar**

```bash
make yarn-build
make screens
```

Expected: verde, sin `[ISLA]`, `[FORMS]`, `[PANEL]` ni `[IA]` (el botón «Proponer campos con IA» sigue apuntando al marco de propuestas: lo mira `09-10-form-vacio`). Mirá `05e-config-*`, `03c-paso-a-paso`, `03d-paso-a-paso-criterios`, `09-10-form-vacio` y `09-12-criterios-del-modulo` contra `tmp/screenshots-antes-2b/`.

- [ ] **Step 7: Commit**

```bash
git add app/views spec/requests/pantalla_del_modulo_spec.rb
git commit -F - <<'EOF'
Las caras de configuración juntan lo que estaba partido

El bloque de criterios y el del formulario eran hasta cinco tarjetas sueltas
—título, aviso, la acción de IA sola, el placeholder—. Pasan a una tarjeta
con el título, qué es, el aviso y la acción de IA juntos; las propuestas
van después, donde aparece lo que se pidió, y la isla al final. Ninguna cara
de configuración sirve ya un `.panel`. Revisado a mano que las cinco siguen
dibujando el pie del paso a paso.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014gkhXcuX5q5pNYj9oZdAZU
EOF
```

---

### Task 10: La captura del salteado y los dos desacoples

**Files:**
- Modify: `db/seeds.rb`
- Modify: `script/capture_screens.js`
- Modify: `app/views/shared/_feedback_item.html.haml`
- Modify: `app/views/layouts/_flow_drawer.html.haml`
- Modify: `app/helpers/estilos_helper.rb`
- Modify: `spec/helpers/estilos_helper_spec.rb`
- Modify: `app/assets/stylesheets/application.css` (~662 `.flow-drawer .badge`; ~1504-1506 bordes por tipo)
- Modify: `CLAUDE.md`

**Interfaces:**
- Produces: `EstilosHelper::PUNTO_DE_ESTADO` y `punto_de_estado(estado)`; el desafío sembrado `con-salteado`.

- [ ] **Step 1: Medir los puntos del drawer antes de tocarlos**

Con el stack arriba y sesión de admin en el navegador, en `/challenges/merma-bodega` y con la consola:

```js
[...document.querySelectorAll('.flow-drawer .badge')].map((e) => [e.title, getComputedStyle(e).backgroundColor])
```

Anotá el resultado en claro y con `prefers-color-scheme: dark` (DevTools → Rendering → Emulate). Es la referencia del Step 5.

- [ ] **Step 2: El seed**

En `db/seeds.rb`, después del bloque de `recorrido-ia` y antes de `sin-armar`:

```ruby
    # Un desafío EN CURSO con un módulo SALTEADO, que existe sólo para
    # `make screens`. Ningún otro seed tiene uno, y el nodo salteado del mapa
    # del flujo quedó negro en el plan 2a sin que ninguna captura lo viera.
    #
    # Propio y no compartido, como manda CLAUDE.md. `sin-formulario` no sirve:
    # está en borrador, y un borrador no tiene módulos salteados.
    Challenge.where(slug: "con-salteado").destroy_all
    salteado = Challenge.create!(
      slug: "con-salteado",
      name: "Turnos que no se pisen",
      brief: "Los turnos de bodega se superponen y nadie sabe quién recibe qué camión.",
      ai_default_mode: "human"
    )
    salteado.pipeline.insert(kind: "ideation", after: :end, name: "Postulación")
    salteado.pipeline.insert(kind: "evolution", after: :end, name: "Ronda de feedback")
    salteado.pipeline.insert(kind: "evaluation", after: :end, name: "Evaluación")
    salteado_ideacion = salteado.pipeline.ideation_step
    salteado_ideacion.form_fields.create!(key: "titulo", label: "Título", field_type: "text", required: true,
                                          position: 0, config: { "is_title" => true })
    salteado.pipeline.start!
    salteado.steps.reload.find(&:evolution?).handler.skip!(reason: "Sin gestores disponibles este mes")
```

Run: `make seed`
Expected: termina sin error. Si `start!` falla por validación, leé el mensaje: el flujo pide algo que el seed no le dio (compará con cómo arma `recorrido-ia` el suyo). **No** marques el módulo con `update_column`: el seed usa el dominio.

- [ ] **Step 3: La captura**

En `script/capture_screens.js`, después de `await shot(page, '02-challenges', '/challenges');`:

```js
  // Un módulo salteado en el mapa del flujo y en el drawer. Sin un seed que lo
  // tenga, el nodo salteado quedó negro en el plan 2a sin que nada lo viera.
  await shot(page, '02b-salteado', '/challenges/con-salteado');
  if (!(await page.locator('.flow-drawer [title="Salteado"], .flow-strip .border-dashed').count())) {
    failures++;
    console.error('[SALTEADO] ni el drawer ni el mapa del flujo muestran el módulo salteado');
  }
```

Antes de correrla, confirmá el `title` real del estado salteado: `grep -n 'skipped' config/locales/*.yml`, y usá ese texto en el localizador.

Y a la pasada oscura: `['98-oscuro-salteado', '/challenges/con-salteado'],`.

Run: `make screens`
Expected: verde, con `02b-salteado` y `98-oscuro-salteado`. Miralas: el nodo salteado tiene que ser neutro con borde punteado, no el más pesado del mapa.

- [ ] **Step 4: El borde por tipo de feedback**

`app/views/shared/_feedback_item.html.haml`:

```haml
%li.feedback-item{ class: ("is-addressed" unless item.open?), data: { kind: item.kind } }
```

En `application.css` (~1504-1506), reemplazá las tres reglas `:has(… .badge-*)` por:

```css
/* El borde por tipo cuelga del TIPO del comentario, no del color de su chip:
   con `:has(.badge-error)` cambiar la variante del chip le cambiaba el borde
   a la tarjeta sin que nadie lo buscara ahí. */
.feedback-item[data-kind="issue"] { border-left-color: var(--danger-borde); }
.feedback-item[data-kind="question"] { border-left-color: var(--warn-borde); }
.feedback-item[data-kind="suggestion"] { border-left-color: var(--accent-borde); }
```

- [ ] **Step 5: Los puntos del drawer**

En `app/helpers/estilos_helper.rb`:

```ruby
  # El punto de estado de cada módulo en el drawer. Era un chip vaciado
  # (`.flow-drawer .badge`), así que cambiar la variante de un chip cambiaba
  # el color del punto sin que nadie lo buscara ahí. Mismos grupos que los
  # chips; el color lo resuelve la hoja.
  PUNTO_DE_ESTADO = {
    "pending" => "flow-drawer__punto flow-drawer__punto--neutro",
    "activating" => "flow-drawer__punto flow-drawer__punto--acento",
    "active" => "flow-drawer__punto flow-drawer__punto--acento",
    "completed" => "flow-drawer__punto flow-drawer__punto--ok",
    "skipped" => "flow-drawer__punto flow-drawer__punto--warn"
  }.freeze

  def punto_de_estado(estado) = PUNTO_DE_ESTADO.fetch(estado.to_s, PUNTO_DE_ESTADO.fetch("pending"))
```

En `spec/helpers/estilos_helper_spec.rb`:

```ruby
  it "cubre todos los estados de un módulo en el drawer" do
    expect(sin_mapear(ChallengeStep::STATUSES, EstilosHelper::PUNTO_DE_ESTADO)).to be_empty
  end
```

En `app/views/layouts/_flow_drawer.html.haml`, la línea del chip vacío:

```haml
              %span{ class: punto_de_estado(paso.status), title: estado }
```

(y actualizá el comentario de arriba: ya no es un chip vacío, es un punto).

En `application.css`, reemplazá la regla `.flow-drawer .badge { … }` (~662) —conservando su comentario largo, que explica la mezcla— por:

```css
.flow-drawer__punto {
  flex: none;
  width: 8px;
  height: 8px;
  border-radius: 99px;
  background-color: color-mix(in oklab, var(--punto) 55%, var(--color-neutral-content));
}
.flow-drawer__punto--neutro { --punto: var(--color-base-content); }
.flow-drawer__punto--acento { --punto: var(--color-primary); }
.flow-drawer__punto--ok { --punto: var(--ok); }
.flow-drawer__punto--warn { --punto: var(--warn); }
```

`make yarn-build`, y repetí la medición del Step 1 con `.flow-drawer__punto`. **Los colores tienen que coincidir** en los dos temas. Si alguno no coincide, el `--punto` de ese grupo no es el `color` que tenía el `badge-soft` de su variante: leelo con `getComputedStyle(document.querySelector('.badge-soft.badge-success')).color` en una pantalla con chips y ajustá el token.

- [ ] **Step 6: Verde**

```bash
make yarn-build
make spec
make screens
```

Expected: verde. Mirá `02b-salteado`, `98-oscuro-salteado` (puntos del drawer) y `07-idea` (bordes de los comentarios por tipo) contra `tmp/screenshots-antes-2b/`.

- [ ] **Step 7: `CLAUDE.md`**

En «Renombrar una clase deja muertas en silencio las reglas que la usaban desde AFUERA de su bloque», agregá al final del bullet:

```markdown
  Esas dos ya no cuelgan del chip: el borde va por `data-kind` y los puntos
  del drawer son `flow-drawer__punto` (`EstilosHelper::PUNTO_DE_ESTADO`).
```

Y en «Nunca apuntes una captura a un desafío que también se usa a mano», sumá: «`con-salteado` existe sólo para la captura del módulo salteado (`02b-salteado`).»

- [ ] **Step 8: Commit**

```bash
git add db/seeds.rb script/capture_screens.js app/views app/helpers/estilos_helper.rb spec/helpers/estilos_helper_spec.rb app/assets/stylesheets/application.css CLAUDE.md
git commit -F - <<'EOF'
Una captura del módulo salteado, y dos reglas que dejan de colgar del chip

Nace `con-salteado`, un desafío sembrado sólo para el recorrido con un
módulo salteado: ningún seed tenía uno y el nodo salió negro en el 2a sin que
nada lo viera. El borde de un comentario pasa a colgar de su tipo
(`data-kind`) y los puntos del drawer de una clase propia: con el color del
chip, cambiar una variante los cambiaba en silencio. Los puntos se midieron
antes y después, en los dos temas.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014gkhXcuX5q5pNYj9oZdAZU
EOF
```

---

### Task 11: Cierre — CSS muerto, `CLAUDE.md` y la revisión de la rama

**Ampliada al ejecutar el plan** con lo que dejaron las revisiones de las Tareas 4, 8b y 10 y una decisión de Raúl. Los Steps 0a a 0d son eso; el resto es el cierre como estaba.

**Files:**
- Modify: `app/assets/stylesheets/application.css`
- Modify: `script/capture_screens.js`
- Modify: `app/views/steps/reporting.html.haml`
- Modify: `spec/requests/pantalla_del_modulo_spec.rb`
- Modify: `CLAUDE.md`
- Modify: `docs/superpowers/specs/2026-09-17-rediseno-2b-pantallas-de-modulo-design.md` (estado y §3)

- [ ] **Step 0a: El punto neutro pasa 3:1, y una guarda mide los cuatro**

Decisión de Raúl. El punto de un módulo pendiente mide **2,57:1 en tema claro** sobre el panel oscuro del drawer, abajo del piso de 3:1 de WCAG 1.4.11 para lo que no es texto; los otros tres pasan (5,00 / 5,13 / 5,19) y en oscuro pasan los cuatro (7,69 a 12,92). Lo dice el comentario de `.flow-drawer__punto` desde la Tarea 10, y nada lo mide: `revisarContraste` saltea lo que no tiene texto.

1. Subí la mezcla del neutro hasta pasar 3:1 **en los dos temas**, tocando sólo ese modificador (hoy `--punto: var(--color-base-content)`). El punto se pinta con `color-mix(in oklab, var(--punto) 55%, var(--color-neutral-content))`: la palanca es el porcentaje o el token. Medí, no estimes.
2. Guarda nueva en `script/capture_screens.js`, al lado de `revisarContraste`:

```js
// Los puntos de estado del drawer no tienen texto, así que `revisarContraste`
// —que mide texto contra su fondo— no los ve. Son información no textual: el
// piso es el 3:1 de WCAG 1.4.11, contra el panel oscuro donde viven. El
// neutro estuvo en 2,57:1 hasta el plan 2b sin que nada lo dijera.
async function revisarPuntos(page, tema) {
  const bajos = await page.evaluate(() => {
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
    }).filter((m) => m.ratio < 3);
  });
  if (bajos.length) {
    failures++;
    const unicos = [...new Map(bajos.map((m) => [m.clase, m])).values()];
    console.error(`[PUNTOS] ${tema}: ${unicos.map((m) => `${m.clase} ${m.ratio.toFixed(2)}:1`).join(' · ')}`);
  }
}
```

Llamala donde haya drawer con los cuatro estados a la vista: en la pasada clara sobre `02b-salteado` (tiene pendiente, en curso y salteado) y sobre una pantalla de `merma-bodega` (tiene completado), y en la pasada oscura sobre `98-oscuro-salteado`. Si el fondo del punto no se puede leer con `backgroundColor` —porque el `color-mix` no resuelve en `getComputedStyle`—, reportalo con lo que devolvió en vez de inventar otra medición.

3. **Vela fallar**: con el valor viejo del neutro la guarda tiene que marcar `[PUNTOS] claro: flow-drawer__punto flow-drawer__punto--neutro 2.57:1`. Pegá esa salida y la de después.
4. Actualizá el párrafo del comentario que la Tarea 10 escribió: ahora los cuatro pasan, con los números nuevos, y lo mide `[PUNTOS]`.

- [ ] **Step 0b: Tres pendientes de la revisión de la Tarea 8b**

1. **La guarda `pide_resumen` no tiene test.** En `spec/requests/pantalla_del_modulo_spec.rb`, el ejemplo «quien evalúa: el pool entero, sin descargas ni pedido a la IA» promete algo que no afirma: el desafío corre en modo `human`, donde `shared/ai_actions` no dibuja nada para nadie. Sumá una variante en modo asistido —`ai_default_mode: "ai_assisted"` en ese `describe`, o un `as_company { challenge.update!(ai_default_mode: "ai_assisted") }` dentro del ejemplo— que afirme que `purpose=summarize_challenge` **está** para quien administra y **no está** para quien evalúa ni para quien participa. Verificalo borrando `pide_resumen` de `reporting.html.haml` (tiene que fallar) y devolviéndolo.
2. **La frase nueva de `CLAUDE.md` tiene sujeto ambiguo.** Viene después de «Quien administra, acompaña o evalúa las ve todas», así que «En reportería ve lo agregado…» se lee al revés. Pasa a «En reportería, quien participa ve lo agregado…».
3. **El sondeo de reportes corre para todos.** `shared/_reports_auto_refresh` (último render de `reporting.html.haml`) consulta cada 4s hasta 120 veces mientras hay un reporte pendiente; quien no tiene `report?` recibe 403 JSON, `data.pending` queda `undefined` y el script sigue. Envolvé ese render en `- if policy(@step).report?`, con un comentario de una línea que diga por qué.

- [ ] **Step 0c: Dos pendientes de las Tareas 4 y 7**

1. **Idear no se mira en oscuro.** `oscuroDeModulos` en `script/capture_screens.js` recorre evaluación, selección, evolución y reportería. Sumá idear (`stepLinks.find((l) => l.text.match(/Postulaci/i))`) como `99-oscuro-idear`, con su chequeo de link faltante como los otros cuatro.
2. **El `before` de «idear» no afirma que el módulo arrancó.** Los describes de selección, evolución y reportería tienen `expect(paso(...)).to be_active`; el de idear lo perdió. Sumalo (la Tarea 7b ya lo puso en su describe hijo; acá va en el padre, `spec/requests/pantalla_del_modulo_spec.rb`).

- [ ] **Step 0d: La descripción de `[CLASES]` en `CLAUDE.md`**

La sección «Verificación» dice que `make screens` falla «si una clase quedó **sin ninguna regla detrás** porque Tailwind no la vio al escanear». Es más angosto que lo que la guarda hace desde hace rato: también mira `.panel`, `.card` y ahora el punto del drawer, o sea cualquier elemento que se quedó sin la regla que lo pintaba —por un renombre, por un token roto o por lo que sea—. Corregí esa frase.

- [ ] **Step 1: CSS sin nadie que lo use**

Para cada una de estas clases, buscá si queda algún uso; si no queda ninguno, borrá su regla:

```bash
for c in assessment-group assessment-group__title ranking-table__check step-table evaluators feedback-board ai-mode-form ai-mode-form__name ai-mode-form__select; do
  printf '%s: ' "$c"; grep -rlw -- "$c" app/views app/helpers app/javascript app/presenters script | tr '\n' ' '; echo
done
```

Expected: las que salen sin archivos se borran de `application.css`. Las que tienen usos, se quedan. Repetí la búsqueda con cualquier clase propia que las Tareas 3 a 10 hayan dejado de escribir en una vista (revisá `git diff master -- app/views | grep '^-' | grep -oE '\.[a-z][a-z0-9_-]+' | sort -u`).

- [ ] **Step 2: `CLAUDE.md`**

Además de lo de los Steps 0b.2 y 0d: leé las secciones «El sistema visual», «El shell de tres regiones», «Lo que carga la jerarquía» y «Configurar y ejecutar son dos caras de la misma pantalla», y corregí toda frase que el plan volvió falsa. Como mínimo:
- «Lo que carga la jerarquía» dice que las tarjetas tienen `margin: 0` y el ritmo lo pone `.app-main`: sigue siendo cierto para `.card`, sumalo.
- Cualquier mención a que evaluación es la única pantalla con referencia.
- `make screens`: las guardas nuevas (`[PLEGABLE]`, `[CARD]`, `[ZONAS]`, `[DESGLOSE]`, `[SALTEADO]`) en el párrafo de «Verificación» que lista qué hace fallar el recorrido.

- [ ] **Step 3: El estado del spec**

En `docs/superpowers/specs/2026-09-17-rediseno-2b-pantallas-de-modulo-design.md`, la fila de **Selección** de la tabla del §3 todavía le da «Cómo se decide» a la referencia: pasa a decir que selección no tiene columna de referencia, con la medición del commit de la Tarea 5 en una frase. Y arriba de todo, debajo del título:

```markdown
> **Estado:** implementado en la rama `rediseno-2b`. Selección quedó con
> referencia (ver el commit de la Tarea 5).
```

Si en la Tarea 5 selección quedó sin referencia, la segunda oración es: «Selección quedó sin referencia: el ranking no se leía en el centro angosto (ver el commit de la Tarea 5).»

- [ ] **Step 4: Verde completo, en limpio**

```bash
make seed
make yarn-build
make spec
make screens
```

Expected: verde. Anotá el número de ejemplos y de capturas para el reporte.

- [ ] **Step 5: Commit**

```bash
git add app/assets/stylesheets/application.css CLAUDE.md docs/superpowers/specs/2026-09-17-rediseno-2b-pantallas-de-modulo-design.md
git commit -F - <<'EOF'
Cierre del 2b: CSS sin uso y CLAUDE.md al día

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014gkhXcuX5q5pNYj9oZdAZU
EOF
```

- [ ] **Step 6: Revisión final de la rama**

Con `superpowers:requesting-code-review`, contra `master`: la rama entera, con el spec al lado. Pedile que mire en especial que ningún bloque haya salido de atrás de su guarda, las capturas en los dos temas y que ningún `.panel` quede en la pantalla del módulo.
