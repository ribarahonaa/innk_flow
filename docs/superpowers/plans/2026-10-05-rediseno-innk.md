# Rediseño INNK Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que `innk_flow` se reconozca como el producto de INNK —marca, cromo y
lenguaje de superficie— sobre las pantallas que ya existen, sin agregar
ninguna.

**Architecture:** Casi todo entra por la hoja. Los tokens propios se derivan de
los 20 de DaisyUI por `color-mix`, así que cambiar esos 20 arrastra el resto; y
la navegación global ya existe en `.app-nav`, así que el riel es una mudanza y
no una función nueva. Lo único estructural es un envoltorio `.app-frame` que
mete el riel a la izquierda sin tocar las cuatro reglas de grilla de
`.app-shell`, y un `PATCH /theme` que escribe una cookie que el servidor
traduce a `data-theme`.

**Tech Stack:** Rails 8 + HAML, Tailwind 4 + DaisyUI 5 (config por CSS),
Playwright para el recorrido, RSpec. Todo corre en Docker.

**Spec:** `docs/superpowers/specs/2026-10-05-rediseno-innk-design.md`

## Global Constraints

- **El código va en inglés; los comentarios y los mensajes de commit, en
  español.** Lo que ya está en español se queda.
- **Los commits NO llevan línea `Co-Authored-By`.** Van con
  `ribarahonaa@gmail.com`, que ya está en el `git config` local.
- **Nunca `bundle exec` en el host.** Los specs corren con `make spec*`, que
  usa el contenedor `app_test`. `docker compose exec app bundle exec rspec`
  devuelve 403 «Blocked hosts» en todos los request specs.
- **Tocaste `app/javascript/` o agregaste utilidades de Tailwind →
  `make yarn-build` ANTES de `make screens`.** Si no, el recorrido valida la
  hoja anterior y lo hace en verde.
- **Una clase de Tailwind nunca se interpola.** `estilos_helper.rb` devuelve el
  nombre completo literal; lo vigila `spec/lint/clases_interpoladas_spec.rb`
  sobre HAML, `.vue` y `.js`.
- **Los valores oklch son la conversión exacta del hex y el croma máximo que
  entra al gamut sRGB.** Lo declarado tiene que ser lo que pinta.
- **Las mezclas van `in oklab`, nunca `in oklch`.**
- **`--borde`, no `--border`:** DaisyUI usa `--border` para el ancho.
- **`data-theme` sólo se escribe si hay cookie.** Con el atributo presente,
  `:root:not([data-theme])` no matchea y `prefersdark` queda muerto.
- Migraciones: ninguna en este plan. No se toca la base.

## Review Focus

Cinco cosas que la spec implica y que ninguna tarea ejercitaría sola. Cada una
tiene su test asignado a la tarea que es dueña del código.

1. **El PDF de reportería no cuelga de los tokens.** `layouts/pdf.html.haml`
   lleva `#5b3df5` y otros cuatro colores como literales, porque lo arma
   wkhtmltopdf sin la hoja y sin nadie que resuelva `var()`. Cambiar la paleta
   sin tocarlo deja la marca vieja en lo único que el usuario se descarga.
   → Tarea 2.
2. **Hay un SEGUNDO layout.** `layouts/auth.html.haml` tiene su propio `%html`
   y no pasa por `application.html.haml`. Sin tocarlo, el control de tema no
   existe en el login —que es donde INNK tiene cuatro variantes de diseño— y
   la cookie elegida adentro no se respeta al salir. → Tarea 4.
3. **El riel no se dibuja sin sesión ni sin empresa.** `.app-nav` hoy vive
   dentro de `if signed_in? && current_company`. Un riel que se dibuje igual
   deja una columna de 80px vacía en el selector de empresa y en cualquier
   pantalla sin membresía. → Tarea 5.
4. **La cookie es entrada del usuario.** Se renderiza dentro de un atributo del
   `<html>`. HAML escapa, así que no hay inyección, pero un valor fuera de la
   lista blanca tiene que tratarse como ausente y no como tema. → Tarea 4.
5. **`/challenges/new` deja un `Challenge.new` sin slug y no hay drawer.** La
   grilla tiene que seguir funcionando con el riel puesto y sin columna de
   flujo; es la misma guarda por la que `desafio_del_shell` existe. → Tarea 5.

---

## Task 1: La red antes de mover nada — spec de la navegación global

`.app-nav` aparece ÚNICAMENTE en `app/views/layouts/application.html.haml`: ni
un spec la nombra. Hoy se puede romper qué ve cada rol en la navegación global
y `make spec` queda en verde. Este spec se escribe **contra la nav actual**,
antes de tocarla, para que la mudanza del riel tenga red en vez de estrenarla
ya movida.

**Files:**
- Create: `spec/requests/navegacion_global_spec.rb`

**Interfaces:**
- Consumes: nada.
- Produces: el spec que las tareas 5 y 6 tienen que seguir dejando en verde.
  Sus aserciones van por **texto del link y `href`**, no por clase CSS, para
  que sobrevivan a la mudanza sin editarse.

- [ ] **Step 1: Escribir el spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

# Qué entradas de la navegación global ve cada rol.
#
# Existe porque `.app-nav` vivía sólo en el layout y NINGÚN spec la nombraba:
# se podía abrir «Criterios» o «Miembros» a quien participa y la suite quedaba
# en verde. Se escribió antes de mudar la nav al riel, a propósito: una red
# estrenada ya movida no distingue el refactor de la regresión.
#
# Las aserciones van por TEXTO y `href`, no por clase: así el riel la hereda
# sin editarla.
RSpec.describe "navegación global", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(role, email)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, role, company: company, user: u)
      u
    end
  end

  # Un link se busca por su `href` Y su texto: sólo por texto, «IA» matchea
  # cualquier mención; sólo por href, un link escondido en otra parte de la
  # pantalla lo daría por presente.
  def nav_link?(texto, path)
    response.body.include?(%(href="#{path}")) &&
      response.body.match?(/<a[^>]+href="#{Regexp.escape(path)}"[^>]*>\s*#{Regexp.escape(texto)}\s*</)
  end

  context "quien participa" do
    before { sign_in member(:participant, "part@test.dev"), company: company }

    it "ve Desafíos y Talleres" do
      get root_path
      expect(nav_link?("Desafíos", challenges_path)).to be true
      expect(nav_link?("Talleres", workshops_path)).to be true
    end

    # El control positivo de arriba es lo que hace que esta negativa valga:
    # sin él, las cuatro aserciones pasarían con la nav entera borrada.
    it "no ve lo que administra la empresa" do
      get root_path
      expect(nav_link?("Criterios", criteria_sets_path)).to be false
      expect(nav_link?("Miembros", members_path)).to be false
      expect(nav_link?("IA", ai_runs_path)).to be false
    end
  end

  context "quien administra" do
    before { sign_in member(:admin, "admin@test.dev"), company: company }

    it "ve las cinco entradas" do
      get root_path
      expect(nav_link?("Desafíos", challenges_path)).to be true
      expect(nav_link?("Talleres", workshops_path)).to be true
      expect(nav_link?("Criterios", criteria_sets_path)).to be true
      expect(nav_link?("Miembros", members_path)).to be true
      expect(nav_link?("IA", ai_runs_path)).to be true
    end
  end

  context "el gestor" do
    before { sign_in member(:gestor, "gestor@test.dev"), company: company }

    # `manages_challenges?` es lo que hoy condiciona las tres: si alguna vez se
    # confunde con `administers?`, esto lo dice.
    it "ve Criterios, Miembros e IA según manages_challenges?" do
      get root_path
      esperado = without_tenant { Membership.find_by(user: User.find_by(email: "gestor@test.dev")).manages_challenges? }
      expect(nav_link?("Criterios", criteria_sets_path)).to eq esperado
      expect(nav_link?("Miembros", members_path)).to eq esperado
      expect(nav_link?("IA", ai_runs_path)).to eq esperado
    end
  end

  # Review Focus #3, la mitad que se puede probar sin navegador: sin empresa en
  # contexto no hay nav. La tarea 5 agrega la del riel.
  it "no dibuja la nav sin empresa elegida" do
    u = without_tenant do
      user = create(:user, email: "multi@test.dev")
      create(:membership, :participant, company: company, user: user)
      create(:membership, :participant, company: create(:company, slug: "otra"), user: user)
      user
    end
    sign_in u
    get select_company_path
    expect(nav_link?("Desafíos", challenges_path)).to be false
  end
end
```

- [ ] **Step 2: Correrlo y verificar que pasa**

Run: `make spec-file FILE=spec/requests/navegacion_global_spec.rb`
Expected: todos los ejemplos PASAN. Es una red sobre código que ya anda.

- [ ] **Step 3: Probar que puede fallar**

Una red que no puede fallar no es una red. Mutar el layout a mano:

```bash
cp app/views/layouts/application.html.haml /tmp/layout.bak
# borrar a mano la línea del link "Criterios" en app/views/layouts/application.html.haml
make spec-file FILE=spec/requests/navegacion_global_spec.rb
```

Expected: FALLA en «quien administra ve las cinco entradas».

- [ ] **Step 4: Restaurar**

```bash
cp /tmp/layout.bak app/views/layouts/application.html.haml
make spec-file FILE=spec/requests/navegacion_global_spec.rb
```

Expected: vuelve a PASAR. Restaurar con `cp` y no con `git checkout`: el
checkout desharía cualquier otro cambio en curso, no la mutación.

- [ ] **Step 5: Commit**

```bash
git add spec/requests/navegacion_global_spec.rb
git commit -m "Spec: qué entradas de la navegación ve cada rol

.app-nav vivía sólo en el layout y ningún spec la nombraba: se podía abrir
Criterios o Miembros a quien participa y la suite quedaba en verde.

Va antes de mudarla al riel a propósito. Una red estrenada ya movida no
distingue el refactor de la regresión. Las aserciones van por texto y href y
no por clase, así el riel la hereda sin editarla."
```

---

## Task 2: La paleta en los dos temas

**Files:**
- Modify: `app/assets/stylesheets/application.css` (los dos bloques
  `@plugin "daisyui/theme"`, y el `--danger` del bloque `:root`)
- Modify: `app/views/layouts/pdf.html.haml` (Review Focus #1)

**Interfaces:**
- Consumes: nada.
- Produces: los 20 tokens con los valores de INNK. Todo lo demás de la hoja se
  deriva de ellos por `color-mix` y no se toca.

- [ ] **Step 1: Cambiar el tema claro**

En el bloque `@plugin "daisyui/theme" { name: "flow"; ... }`:

```css
  --color-base-100: oklch(100% 0 0);
  --color-base-200: oklch(97.470% 0.0051 247.88);
  --color-base-300: oklch(92.400% 0.0080 247.88);
  --color-base-content: oklch(21.500% 0.0280 247.88);

  /* #4747f3 exacto: la marca de INNK, del Figma «General Rediseño». Dejó de
     ser provisorio. Es un corrimiento de 6,7° de tono sobre el violeta que
     había (280.33), a la misma luminosidad y croma, así que todo lo que cuelga
     del primario conserva su contraste: 6.12:1 antes, 6.06:1 ahora. */
  --color-primary: oklch(52.015% 0.2475 273.64);
  --color-primary-content: oklch(100% 0 0);          /* 6.06:1 */

  --color-secondary: oklch(50% 0.0996 230);
  --color-secondary-content: oklch(100% 0 0);        /* 5.86:1 */

  --color-neutral: oklch(21.500% 0.0280 247.88);
  --color-neutral-content: oklch(78.5% 0.024 247.88);

  /* #8520bd exacto: el morado con que el Figma pinta la pestaña activa. El
     acento DEJA de apuntar al primario —ya tiene un color de marca propio
     detrás—. Queda a 35° del primario: holgado contra los 8° que en su momento
     obligaron a correr `--color-secondary` al azul acero. */
  --color-accent: oklch(48.894% 0.2246 309.04);
  --color-accent-content: oklch(100% 0 0);           /* 7.15:1 */
  --color-info: oklch(50% 0.0996 230);
  --color-info-content: oklch(100% 0 0);

  /* #f06653 exacto. INNK lo usa con texto BLANCO y eso mide 3.12:1, que no
     pasa. Oscurecerlo hasta 4,5:1 lo convierte en otro color (#ce1d0d), así
     que se conserva el color y se da vuelta el texto —el mismo patrón que la
     hoja ya usa para `success` y `warning`—. */
  --color-error: oklch(67.909% 0.1741 30.12);
  --color-error-content: oklch(15% 0.03 285.9);      /* 6.32:1 — blanco da 3.12 */
  --color-success: oklch(62.6% 0.1507 156.4);
  --color-success-content: oklch(15% 0.03 285.9);    /* 5.94:1 */
  --color-warning: oklch(72.9% 0.1501 82.4);
  --color-warning-content: oklch(15% 0.03 285.9);    /* 8.10:1 */
```

- [ ] **Step 2: Cambiar el tema oscuro**

En el bloque `name: "flow-oscuro"`:

```css
  --color-base-100: oklch(21.5% 0.028 247.88);
  --color-base-200: oklch(18.2% 0.026 247.88);
  --color-base-300: oklch(26.4% 0.030 247.88);
  --color-base-content: oklch(92.8% 0.012 247.88);

  /* El croma está CLAMPEADO: a L=66.5% y H=273.64 el gamut sRGB corta en
     0.1780, por debajo del 0.2475 del tema claro. Declarar el del claro acá
     sería declarar algo que el navegador recorta. */
  --color-primary: oklch(66.5% 0.1780 273.64);
  --color-primary-content: oklch(15% 0.03 285.9);    /* 6.22:1 */

  --color-neutral: oklch(15.5% 0.024 247.88);
  --color-neutral-content: oklch(78.5% 0.024 247.88);

  --color-accent: oklch(70% 0.2098 309.04);
  --color-accent-content: oklch(15% 0.03 285.9);     /* 6.74:1 */

  --color-error: oklch(66% 0.19 30.12);
  --color-error-content: oklch(15% 0.03 285.9);      /* 5.82:1 */
```

`secondary`, `info`, `success` y `warning` del tema oscuro no se tocan.

- [ ] **Step 3: Bajar el `--danger` de 85% a 75%**

En el bloque `:root`. Medido: con el coral de INNK, el 85% da **4,06:1** sobre
la superficie clara y no pasa; el 75% da **4,88:1**. En el tema oscuro el 85%
daría 6,12:1, pero el token es uno solo y el 75% ahí sigue holgado.

```css
  /* 75% y no 85%: con el coral de INNK (#f06653, más claro que el rojo que
     había) la mezcla al 85% medía 4.06:1 sobre la superficie clara. Al 75%
     mide 4.88:1. `--danger` se usa como color de TEXTO, así que el piso que
     corre es 4,5:1. */
  --danger: color-mix(in oklab, var(--color-error) 75%, var(--color-base-content));
```

- [ ] **Step 4: Actualizar el PDF (Review Focus #1)**

`app/views/layouts/pdf.html.haml` lo arma wkhtmltopdf **sin la hoja de la app y
sin nadie que resuelva `var()`**, así que lleva los cinco colores como
literales. Es el único lugar donde la paleta llega a un usuario en algo que se
descarga. Reemplazar `#5b3df5` por `#4747f3` en el comentario y en todas las
reglas, y actualizar la línea del comentario que lo describe:

```
-#   #4747f3  --color-primary, el indigo de la marca INNK (6.1:1)
```

Verificar con `grep -c '5b3df5' app/views/layouts/pdf.html.haml` → debe dar 0.

- [ ] **Step 5: Compilar y medir**

```bash
make yarn-build
make spec
make screens
```

Expected: `make spec` en verde. `make screens` **va a reportar fallas de
`[CONTRASTE]`** y posiblemente de `[PUNTOS]` y `[ESTADO-DRAWER]`: es lo que la
guarda existe para decir. `badge-soft` y `alert-soft` pintan el texto con el
color PURO del tema, y cambiaron `error`, `accent` y el tono del primario.

- [ ] **Step 6: Arreglar lo que la guarda marcó**

La hoja ya tiene una regla de dos clases que corrige las variantes suaves
(buscar `badge-soft` en `application.css`). Ajustar ahí los tonos que
`[CONTRASTE]` reportó, **midiendo**, no estimando: el mensaje de la guarda trae
el número medido y el elemento. Repetir `make yarn-build && make screens` hasta
que no quede ninguna.

No aflojar el piso de la guarda. Si un color no llega, se corrige el color.

- [ ] **Step 7: Verificar que el recorrido quedó limpio**

Run: `make yarn-build && make screens`
Expected: sin errores de JS, sin HTTP >= 400, y los cinco contadores impresos
(`[RITMO]`, `[RELLENO]`, `[PASTILLA]`, `[CRITERIO]`, `[LIVE]`) por encima de
sus pisos.

- [ ] **Step 8: Commit**

```bash
git add app/assets/stylesheets/application.css app/views/layouts/pdf.html.haml
git commit -m "La paleta de INNK en los dos temas

El primario deja de ser provisorio: #4747f3 del Figma. Es un corrimiento de
6,7° de tono a la misma luminosidad y croma, así que lo que cuelga de él
conserva su contraste (6.12 -> 6.06:1).

El acento gana un color propio en vez de apuntar al primario: el morado
#8520bd de la pestaña activa, a 35° del primario.

El coral #f06653 entra exacto. INNK lo usa con texto blanco y eso mide 3.12:1,
así que se da vuelta el texto —lo que la hoja ya hace con success y warning— y
--danger baja de 85% a 75%, porque al 85% medía 4.06:1 y se usa como texto.

El tema oscuro corre al azul marino, que es el fondo que INNK usa en su propia
pantalla de login. El croma del primario oscuro va clampeado a 0.1780: el
gamut sRGB corta ahí.

Y el PDF de reportería, que no cuelga de los tokens porque wkhtmltopdf no
resuelve var(): sus cinco colores son literales y había que cambiarlos a mano."
```

---

## Task 3: La tipografía

**Files:**
- Create: `public/fonts/open-sans-latin.woff2`
- Delete: `public/fonts/bricolage-grotesque-latin.woff2`,
  `public/fonts/inter-latin.woff2`
- Modify: `public/fonts/OFL.txt` (la licencia de Open Sans)
- Modify: `app/assets/stylesheets/application.css` (los `@font-face`, el bloque
  `@theme`, y la regla de `@layer base` que pone la display en los títulos)

**Interfaces:**
- Consumes: nada.
- Produces: `--font-display` y `--font-sans` apuntando los dos a `"Open Sans"`.

- [ ] **Step 1: Bajar Open Sans variable, subconjunto latin**

El archivo tiene que ser el **variable** (ejes `wght` y `wdth`) del subconjunto
**latin**, que es el mismo recorte que usan las dos familias actuales. El
`unicode-range` que ya está en la hoja se reusa tal cual.

```bash
curl -s "https://fonts.googleapis.com/css2?family=Open+Sans:wght@300..800&display=swap" \
  -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36" \
  | grep -A3 'unicode-range: U+0000-00FF'
```

De la salida, bajar la URL `.woff2` del bloque cuyo `unicode-range` empieza en
`U+0000-00FF` (ése es latin) a `public/fonts/open-sans-latin.woff2`.

Verificar que es variable antes de seguir —si no lo es, un solo archivo no
cubre los pesos—:

```bash
python3 - <<'PY'
d=open('public/fonts/open-sans-latin.woff2','rb').read()
print("fvar presente:", b'fvar' in d, "· tamaño:", len(d))
PY
```

Expected: `fvar presente: True`. Si da False, buscar el archivo variable en
https://github.com/googlefonts/opensans (`fonts/variable/`) y recortarlo al
subconjunto latin.

- [ ] **Step 2: Agregar la licencia**

Open Sans es OFL 1.1, igual que las dos que se van. Reemplazar el contenido de
`public/fonts/OFL.txt` por el `OFL.txt` de Open Sans (está en el repo de
googlefonts/opensans). La licencia tiene que acompañar a los archivos, que es
lo que pide.

- [ ] **Step 3: Reemplazar los dos `@font-face` por uno**

Borrar los bloques `@font-face` de Bricolage Grotesque y de Inter y poner:

```css
/* AUTO-HOSPEDADA, no de Google Fonts: una hoja de un tercero bloquea el
   render, y medido, con la petición colgada `DOMContentLoaded` no llega nunca
   y la pantalla queda EN BLANCO. El porqué completo está en el historial de
   este archivo.

   UNA familia donde había dos. Open Sans es la de INNK —el propio código que
   exporta su Figma trae `fontVariationSettings: '"wdth" 100'`—, y usarla para
   títulos y cuerpo es lo que hace el diseño. Pesa MENOS que las dos que
   reemplaza: 125 KB entre Bricolage e Inter contra ~37 KB de ésta.

   Es VARIABLE (tiene `fvar`), así que un archivo cubre todos los pesos y
   `font-weight: 300 800` es un rango y no una lista.

   El `unicode-range` es el mismo subconjunto latin de siempre: el español
   entra entero. Lo de afuera cae a la pila de respaldo. */
@font-face {
  font-family: "Open Sans";
  font-style: normal;
  font-weight: 300 800;
  font-stretch: 100%;
  font-display: swap;
  src: url("/fonts/open-sans-latin.woff2") format("woff2");
  unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD;
}
```

- [ ] **Step 4: Apuntar las dos variables a la misma familia**

```css
@theme {
  /* Las dos apuntan a Open Sans: INNK usa una sola familia. `--font-display`
     se conserva como token aunque hoy valga lo mismo que `--font-sans`, porque
     es el gancho por donde volvería a entrar una display si alguna vez se
     quiere. */
  --font-display: "Open Sans", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  --font-sans: "Open Sans", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
}
```

- [ ] **Step 5: Borrar los dos archivos viejos**

```bash
git rm public/fonts/bricolage-grotesque-latin.woff2 public/fonts/inter-latin.woff2
```

- [ ] **Step 6: Compilar y correr el lint de reglas sin elemento**

```bash
make yarn-build
make spec-file FILE=spec/lint/reglas_sin_elemento_spec.rb
```

Expected: PASA. Si marca alguna regla que nombraba a Bricolage o a Inter por
clase, borrar esa regla —no excepcionarla—.

- [ ] **Step 7: Verificar en el navegador que la fuente aplica**

```bash
make screens
```

Expected: sin errores. Después, confirmar que la familia servida es la nueva:

```bash
grep -c 'Bricolage\|Inter' app/assets/builds/application-build.css
```

Expected: `0`. Si da distinto de 0, quedó una referencia y la hoja está
sirviendo una familia que ya no existe en `public/fonts` — el navegador caería
a la pila de respaldo sin decir nada.

- [ ] **Step 8: Commit**

```bash
git add -A public/fonts app/assets/stylesheets/application.css
git commit -m "Open Sans: una familia donde había dos

Es la tipografía de INNK —el código que exporta su Figma trae
fontVariationSettings '\"wdth\" 100'— y la usa para títulos y cuerpo, así que
se jubilan Bricolage Grotesque e Inter.

Pesa menos: 125 KB entre las dos que se van contra ~37 KB de ésta. Sigue
auto-hospedada y sigue siendo variable, así que un archivo cubre los pesos.

--font-display se conserva como token aunque hoy valga lo mismo que
--font-sans: es el gancho por donde volvería a entrar una display."
```

---

## Task 4: El control de tema

**Files:**
- Create: `app/controllers/themes_controller.rb`
- Create: `app/lib/flow/themes.rb`
- Create: `app/views/shared/_theme_switch.html.haml`
- Create: `spec/requests/theme_spec.rb`
- Modify: `config/routes.rb`
- Modify: `app/views/layouts/application.html.haml`
- Modify: `app/views/layouts/auth.html.haml` (Review Focus #2)
- Modify: `app/assets/stylesheets/application.css` (estilo del control)

**Interfaces:**
- Consumes: nada.
- Produces:
  - `Flow::Themes::NAMES = %w[flow flow-oscuro].freeze` — la lista blanca.
  - `ApplicationHelper#tema_elegido` → `String | nil`. Devuelve el tema de la
    cookie **sólo si está en la lista blanca**; `nil` en cualquier otro caso.
    Los dos layouts lo consumen.
  - `PATCH /theme` con parámetro `theme` ∈ `{"flow", "flow-oscuro", "auto"}`.

- [ ] **Step 1: Escribir el spec que falla**

```ruby
# frozen_string_literal: true

require "rails_helper"

# El control de tema.
#
# El mecanismo entero existe para no matar `prefersdark`: el tema oscuro se
# engancha a `@media (prefers-color-scheme: dark) { :root:not([data-theme]) }`,
# así que escribir `data-theme` SIEMPRE —aunque sea con el nombre del tema
# claro— hace que ese selector no matchee nunca.
#
# Por eso son tres estados y no dos, y por eso «Auto» BORRA la cookie en vez de
# escribir "flow".
RSpec.describe "control de tema", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }
  let!(:user) do
    without_tenant do
      u = create(:user, email: "u@test.dev")
      create(:membership, :participant, company: company, user: u)
      u
    end
  end

  before { sign_in user, company: company }

  it "sin cookie no escribe data-theme" do
    get root_path
    expect(response.body).not_to include("data-theme")
  end

  it "elegir el claro escribe la cookie y el atributo" do
    patch theme_path, params: { theme: "flow" }
    expect(response).to have_http_status(:redirect)
    get root_path
    expect(response.body).to include(%(data-theme="flow"))
  end

  it "elegir el oscuro escribe la cookie y el atributo" do
    patch theme_path, params: { theme: "flow-oscuro" }
    get root_path
    expect(response.body).to include(%(data-theme="flow-oscuro"))
  end

  # El caso que justifica todo el diseño: «Auto» tiene que BORRAR. Si escribe
  # "flow", prefersdark queda muerto para siempre y nadie se entera.
  it "volver a Auto borra la cookie y el atributo" do
    patch theme_path, params: { theme: "flow" }
    get root_path
    expect(response.body).to include("data-theme")

    patch theme_path, params: { theme: "auto" }
    get root_path
    expect(response.body).not_to include("data-theme")
  end

  # Review Focus #4: la cookie es entrada del usuario y se renderiza dentro de
  # un atributo del <html>.
  it "ignora un valor que no está en la lista blanca" do
    patch theme_path, params: { theme: "flow-inventado" }
    get root_path
    expect(response.body).not_to include("data-theme")
  end

  it "ignora una cookie forjada a mano" do
    cookies[:theme] = %(" onload="alert(1))
    get root_path
    expect(response.body).not_to include("data-theme")
    expect(response.body).not_to include("onload")
  end

  it "vuelve a donde estabas" do
    patch theme_path, params: { theme: "flow" }, headers: { "HTTP_REFERER" => workshops_url }
    expect(response).to redirect_to(workshops_url)
  end

  # Review Focus #2: el login usa OTRO layout, con su propio <html>.
  it "el login respeta la cookie" do
    patch theme_path, params: { theme: "flow-oscuro" }
    delete logout_path
    get login_path
    expect(response.body).to include(%(data-theme="flow-oscuro"))
  end
end
```

- [ ] **Step 2: Correr el spec y verificar que falla**

Run: `make spec-file FILE=spec/requests/theme_spec.rb`
Expected: FALLA con `NameError: undefined local variable or method 'theme_path'`.

- [ ] **Step 3: La ruta**

En `config/routes.rb`, junto a las rutas de sesión (antes del bloque
`namespace :api`):

```ruby
  # El tema elegido a mano. Es una cookie y no una columna: el login es
  # público, así que una preferencia en `users` no serviría ahí; y es el
  # SERVIDOR el que la traduce a `data-theme`, con lo cual no hay parpadeo del
  # tema equivocado en la primera pintura y el morph no se lo puede llevar
  # —que es la misma familia del <details> que se cerraba solo—.
  resource :theme, only: :update
```

- [ ] **Step 4: La lista blanca y el helper**

**Ojo: `app/lib/flow.rb` NO existe** — `app/lib/flow/` es un namespace
implícito de Zeitwerk. Crear ese archivo convertiría el namespace en explícito,
que es un cambio más grande del que hace falta. Va en archivo propio, con una
constante por archivo como el resto (`Flow::Demo`, `Flow::StepSettings`).

Crear `app/lib/flow/themes.rb`:

```ruby
# frozen_string_literal: true

module Flow
  # Los dos nombres de tema que declara la hoja.
  #
  # Es una lista BLANCA, no una validación de formato: el valor sale de una
  # cookie —o sea de entrada del usuario— y se renderiza dentro de un atributo
  # del <html>. HAML escapa, así que no hay inyección; aceptar cualquier string
  # igual sería aceptar que el atributo diga cualquier cosa.
  module Themes
    NAMES = %w[flow flow-oscuro].freeze
  end
end
```

En `app/helpers/application_helper.rb`:

```ruby
  # El tema elegido a mano, o `nil` si no hay ninguno.
  #
  # `nil` es la respuesta importante: los dos layouts lo pasan como valor de
  # `data: { theme: ... }` y HAML OMITE el atributo cuando es nil. Sin atributo,
  # `:root:not([data-theme])` matchea y `prefersdark` sigue vivo. Cualquier
  # cosa fuera de la lista blanca se trata como ausente, no como error.
  def tema_elegido
    valor = cookies[:theme]
    valor if Flow::Themes::NAMES.include?(valor)
  end
```

- [ ] **Step 5: El controller**

```ruby
# frozen_string_literal: true

# Escribe —o borra— la cookie del tema.
#
# No hereda ninguna regla de tenencia: la preferencia es del navegador y no del
# dominio, así que no toca el tenant ni pide membresía. Sí pide sesión, como
# todo lo demás del layout.
class ThemesController < ApplicationController
  def update
    if params[:theme] == "auto"
      # BORRAR, no escribir "flow". Escribir el nombre del tema claro dejaría
      # `data-theme` puesto, y con el atributo presente
      # `:root:not([data-theme])` no matchea nunca: el modo oscuro automático
      # quedaría muerto para siempre, en silencio.
      cookies.delete(:theme)
    elsif Flow::Themes::NAMES.include?(params[:theme])
      cookies.permanent[:theme] = { value: params[:theme], same_site: :lax }
    end
    # Un valor fuera de la lista no hace nada: ni escribe ni borra.

    redirect_back fallback_location: root_path
  end
end
```

- [ ] **Step 6: Los dos layouts**

En `application.html.haml` **y** en `auth.html.haml`, reemplazar la línea
`%html{ lang: I18n.locale }` por:

```haml
%html{ lang: I18n.locale, data: { theme: tema_elegido } }
```

Y **reemplazar** el comentario que está arriba de esa línea en los dos
archivos, que hoy dice que nunca va `data-theme`:

```haml
-# `data-theme` SÓLO si hay una elección explícita. `tema_elegido` devuelve nil
-# cuando no hay cookie, y HAML omite el atributo con valor nil: sin atributo,
-# `:root:not([data-theme])` matchea y `prefersdark` resuelve el tema por el
-# sistema. Con el atributo presente ese selector no matchea NUNCA, así que
-# escribirlo siempre —aunque fuera con el nombre del tema claro— mataría el
-# modo oscuro automático. Lo escribe el SERVIDOR y no el cliente: así no hay
-# parpadeo en la primera pintura y el morph no se lo lleva.
```

- [ ] **Step 7: El control de tres estados**

`app/views/shared/_theme_switch.html.haml`:

```haml
-# Tres estados, no dos. El servidor no sabe qué prefiere el sistema de quien
-# mira, así que un control de dos posiciones obliga a elegir un default y mata
-# `prefersdark` para todo el que nunca lo toque. «Auto» borra la cookie.
-#
-# Las clases van literales: Tailwind escanea texto y una clase interpolada no
-# llega a la hoja (spec/lint/clases_interpoladas_spec.rb).
- actual = tema_elegido
%div.theme-switch{ role: "group", "aria-label": "Tema" }
  = button_to "Auto", theme_path, method: :patch, params: { theme: "auto" },
              class: actual.nil? ? "theme-switch__btn theme-switch__btn--on" : "theme-switch__btn"
  = button_to "Claro", theme_path, method: :patch, params: { theme: "flow" },
              class: actual == "flow" ? "theme-switch__btn theme-switch__btn--on" : "theme-switch__btn"
  = button_to "Oscuro", theme_path, method: :patch, params: { theme: "flow-oscuro" },
              class: actual == "flow-oscuro" ? "theme-switch__btn theme-switch__btn--on" : "theme-switch__btn"
```

Renderizarlo en `application.html.haml` dentro de `.app-header__session`,
**antes** del link de salir, y en `auth.html.haml` al pie.

Cuidado: `button_to` es un `<form>`, y un `<form>` dentro de otro es HTML
inválido —el navegador descarta el interno—. El header no está dentro de
ningún form, así que acá es seguro; lo vigila igual `revisarFormsAnidados` en
el recorrido.

- [ ] **Step 8: El estilo**

En `application.css`, junto a las reglas de `.app-header`:

```css
.theme-switch { display: inline-flex; gap: 2px; }
.theme-switch form { display: contents; }
.theme-switch__btn {
  padding: 4px 9px;
  border: 1px solid var(--borde);
  border-radius: var(--radius-selector);
  background: var(--surface);
  color: var(--muted);
  font: inherit;
  font-size: 12px;
  cursor: pointer;
}
.theme-switch__btn--on { background: var(--accent-soft); color: var(--accent); border-color: var(--accent); }
```

`form { display: contents }` porque `button_to` envuelve cada botón en su
propio `<form>`: sin eso, los tres forms serían los hijos flex y el `gap` no
separaría los botones.

- [ ] **Step 9: Correr el spec**

```bash
make yarn-build
make spec-file FILE=spec/requests/theme_spec.rb
```

Expected: todos PASAN.

- [ ] **Step 10: La guarda `[TEMA]` en el recorrido**

Un spec de request prueba que el atributo se escribe. **No prueba que el tema
realmente cambie en pantalla**: eso sólo lo ve un navegador. Agregar en
`script/capture_screens.js`:

```js
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
async function revisarTema(page) {
  const fondo = () => page.evaluate(() => getComputedStyle(document.body).backgroundColor);

  await page.emulateMedia({ colorScheme: 'dark' });
  await page.context().clearCookies();
  await page.goto(BASE + '/', { waitUntil: 'networkidle' });
  const automatico = await fondo();

  await page.click('.theme-switch form:nth-child(2) button');  // Claro
  await page.waitForLoadState('networkidle');
  const forzadoClaro = await fondo();

  await page.click('.theme-switch form:nth-child(1) button');  // Auto
  await page.waitForLoadState('networkidle');
  const devuelto = await fondo();

  await page.emulateMedia({ colorScheme: 'light' });
  await page.context().clearCookies();

  temaMedido = true;
  if (forzadoClaro === automatico) {
    failures++;
    console.error(`[TEMA] elegir «Claro» con el sistema en oscuro no cambió nada (${automatico})`);
  }
  if (devuelto !== automatico) {
    failures++;
    console.error(`[TEMA] volver a «Auto» no devolvió el tema del sistema: ${devuelto} en vez de ${automatico} — ¿«Auto» escribe la cookie en vez de borrarla?`);
  }
}

// Una guarda que no corrió es indistinguible de una que pasó.
let temaMedido = false;
```

Llamarla una vez desde el flujo principal (cerca de donde se hace la pasada
oscura, línea ~3172), y al final, junto a los otros contadores:

```js
  if (!temaMedido) {
    failures++;
    console.error('[TEMA] la guarda no llegó a correr');
  }
```

- [ ] **Step 11: Probar la guarda por mutación**

Primero la corrida limpia, porque **una mutación sólo discrimina si el baseline
pasa**:

```bash
make yarn-build && make screens    # tiene que estar en verde ANTES de mutar
cp app/controllers/themes_controller.rb /tmp/themes.bak
```

Mutar: en `themes_controller.rb`, cambiar la rama de `"auto"` por
`cookies.permanent[:theme] = { value: "flow", same_site: :lax }` — o sea el bug
exacto que el diseño evita.

```bash
make screens
```

Expected: **FALLA** con `[TEMA] volver a «Auto» no devolvió el tema del
sistema`.

```bash
cp /tmp/themes.bak app/controllers/themes_controller.rb
make screens
```

Expected: vuelve a pasar. Restaurar con `cp`, nunca con `git checkout`.

- [ ] **Step 12: Commit**

```bash
git add app/controllers/themes_controller.rb app/views/shared/_theme_switch.html.haml \
        spec/requests/theme_spec.rb config/routes.rb app/views/layouts/ \
        app/assets/stylesheets/application.css script/capture_screens.js
git commit -m "Elegir el tema a mano, sin matar el automático

Una cookie que lee el SERVIDOR y traduce a data-theme. Del lado del cliente
habría dos problemas: parpadeo del tema equivocado en la primera pintura, y un
atributo que el servidor no manda, que es la familia del <details> que se
cerraba solo en cada morph.

Son tres estados y no dos. El servidor no sabe qué prefiere el sistema de quien
mira, así que un control de dos posiciones obliga a elegir un default y mata
prefersdark para todo el que nunca lo toque. «Auto» BORRA la cookie; escribir
\"flow\" ahí dejaría el modo oscuro automático muerto en silencio.

El valor va contra lista blanca: sale de una cookie y se renderiza dentro de un
atributo del <html>.

Los DOS layouts, no uno: auth.html.haml tiene su propio <html> y sin tocarlo el
control no existiría en el login.

Y la guarda [TEMA], que mide el fondo computado en un navegador con el sistema
en oscuro: el request spec prueba que el atributo se escribe, no que el tema
cambie. Probada por mutación."
```

---

## Task 5: El riel de navegación

**Files:**
- Create: `app/views/layouts/_rail.html.haml`
- Create: `app/assets/images/rail/` (los cinco SVG del Figma)
- Modify: `app/views/layouts/application.html.haml`
- Modify: `app/assets/stylesheets/application.css`
- Modify: `script/capture_screens.js`

**Interfaces:**
- Consumes: `spec/requests/navegacion_global_spec.rb` de la Tarea 1 — **tiene
  que seguir pasando sin editarse**. Sus aserciones van por texto y `href`.
- Produces: `nav.app-rail` dentro de `.app-frame`.

- [ ] **Step 1: Bajar los cinco iconos del Figma**

Del frame `2253:11082` del archivo `3xc9srW7XlOlM9jzZ3lGjC`, los iconos del
riel son los nodos `3351:6555` (Home), `3351:6559` (Mi espacio), `3351:6551`
(Ideas), `3351:6563` (Portafolios) y `3351:6584` (Admin). Bajarlos como SVG y
guardarlos en `app/assets/images/rail/` con los nombres de ESTA app:
`challenges.svg`, `workshops.svg`, `criteria.svg`, `members.svg`, `ai.svg`.

**No redibujarlos ni extraerles los paths.** Conservar el `width` y el `height`
raíz de cada uno.

- [ ] **Step 2: El partial del riel**

```haml
-# El riel de navegación global.
-#
-# No es nav nueva: es la que estaba en `.app-nav`, dentro del header, con las
-# mismas cinco entradas y las mismas condiciones de permiso. Se mudó acá
-# porque es donde la pone el diseño de INNK, y de paso deja el header para lo
-# que es de la sesión.
-#
-# Las clases van literales y el estado activo también: Tailwind escanea texto
-# y una clase interpolada no llega a la hoja.
%nav.app-rail{ "aria-label": "Navegación principal" }
  = rail_link "Desafíos", challenges_path, "challenges",
              activo: controller_name.in?(%w[challenges steps ideas assessments])
  -# Sin condicionar a `manages_challenges?`: a un taller se entra por
  -# convocatoria, y quien participa en una mesa es quien más lo necesita.
  = rail_link "Talleres", workshops_path, "workshops",
              activo: controller_name.start_with?("workshop")
  - if current_membership&.manages_challenges?
    = rail_link "Criterios", criteria_sets_path, "criteria",
                activo: controller_name == "criteria_sets"
    = rail_link "Miembros", members_path, "members",
                activo: controller_name == "memberships"
    = rail_link "IA", ai_runs_path, "ai",
                activo: controller_name.start_with?("ai_")
```

Y el helper, en `app/helpers/shell_helper.rb`:

```ruby
  # Una entrada del riel: icono arriba, nombre abajo.
  #
  # La clase del estado activo se escribe COMPLETA en las dos ramas y no se
  # arma con interpolación: Tailwind escanea texto, y `"app-rail__item--#{x}"`
  # no llegaría a la hoja —el elemento quedaría sin ninguna regla detrás y en
  # el DOM se vería perfecto—.
  def rail_link(texto, path, icono, activo:)
    clase = activo ? "app-rail__item app-rail__item--on" : "app-rail__item"
    link_to path, class: clase, "aria-current": (activo ? "page" : nil) do
      safe_join([
        image_tag("rail/#{icono}.svg", class: "app-rail__icon", alt: "", aria: { hidden: true }),
        content_tag(:span, texto, class: "app-rail__label")
      ])
    end
  end
```

- [ ] **Step 3: Envolver el layout**

En `application.html.haml`, sacar el bloque `%nav.app-nav` entero del header y
envolver header + shell:

```haml
  %body
    -# El riel va AFUERA de `.app-shell` y no como una columna más: en el
    -# diseño arranca en el borde de arriba, o sea que abarca también la barra.
    -# Como envoltorio, las cuatro reglas de grilla de `.app-shell` quedan
    -# intactas.
    -#
    -# Sólo con sesión Y empresa elegida: sin eso no hay a dónde navegar, y una
    -# columna de 80px vacía en el selector de empresa se lee como un error.
    - con_riel = signed_in? && current_company
    %div{ class: con_riel ? "app-frame app-frame--con-riel" : "app-frame" }
      - if con_riel
        = render "layouts/rail"
      %div.app-frame__body
        %header.app-header
          ...
```

- [ ] **Step 4: La grilla y el estilo**

```css
/* El riel es la primera columna del marco, no de `.app-shell`: en el diseño
   arranca arriba de todo, así que abarca la barra. Así `.app-shell` no se
   entera de que existe. */
.app-frame { display: grid; grid-template-columns: 1fr; min-height: 100vh; }
.app-frame--con-riel { grid-template-columns: 80px minmax(0, 1fr); }
.app-frame__body { min-width: 0; }

.app-rail {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 10px;
  padding: 14px 6px;
  background: var(--surface);
  border-right: 1px solid var(--borde);
}
.app-rail__item {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  width: 100%;
  padding: 8px 2px;
  border-radius: var(--radius-field);
  color: var(--muted);
  text-decoration: none;
  font-size: 11px;
  text-align: center;
}
.app-rail__item:hover { background: var(--bg); color: var(--text); }
.app-rail__item--on { background: var(--accent-soft); color: var(--accent); }
.app-rail__icon { width: 22px; height: 22px; }

/* Abajo de 1024px el riel pasa a fila horizontal arriba del contenido, que es
   el mismo mecanismo que `.flow-strip` ya usa para el drawer: un markup y un
   cambio de dirección. Los frames de teléfono del diseño no tienen riel.
   NO se esconde: un riel que desaparece deja la app sin navegación global. */
@media (max-width: 1023px) {
  .app-frame--con-riel { grid-template-columns: 1fr; }
  .app-rail {
    flex-direction: row;
    justify-content: flex-start;
    overflow-x: auto;
    border-right: 0;
    border-bottom: 1px solid var(--borde);
    padding: 6px 10px;
  }
  .app-rail__item { width: auto; flex-direction: row; gap: 6px; padding: 6px 10px; font-size: 12px; }
}
```

- [ ] **Step 5: Borrar las reglas de `.app-nav`**

```bash
grep -n 'app-nav' app/assets/stylesheets/application.css
```

Borrar las tres reglas (`.app-nav`, `.app-nav__link`, `.app-nav__link:hover`,
`.app-nav__link.is-active`). No excepcionarlas en el lint: una regla sin
elemento se borra.

- [ ] **Step 6: La red de la Tarea 1 tiene que seguir en verde, SIN tocarla**

```bash
make spec-file FILE=spec/requests/navegacion_global_spec.rb
```

Expected: PASA sin haber editado el archivo. Si hay que editarlo para que pase,
la mudanza cambió qué ve algún rol — eso es una regresión, no un ajuste.

- [ ] **Step 7: El lint de reglas sin elemento**

Run: `make spec-file FILE=spec/lint/reglas_sin_elemento_spec.rb`
Expected: PASA. Si marca `.app-nav`, quedó una regla sin borrar.

- [ ] **Step 8: La guarda `[RIEL]`**

En `script/capture_screens.js`:

```js
// `[RIEL]` — que el riel exista, marque dónde estás, y SOBREVIVA al angosto.
//
// Lo que esta guarda cuida de verdad es el tercer punto. A 1100px la hoja
// cambia la grilla, y un riel que se esconda en vez de volverse fila deja la
// app sin navegación global en ese ancho —y ninguna otra captura mira ahí
// salvo `[REFERENCIA]`—. Se mide la posición real, no la clase: un riel con su
// clase puesta y `display: none` tiene la clase igual.
const PISO_DE_RIEL = 20;
let rielesMedidos = 0;

async function revisarRiel(page, name) {
  const r = await page.evaluate(() => {
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

  // Sin riel no es falla: el selector de empresa y el login no lo tienen.
  if (!r) return;
  rielesMedidos++;

  if (!r.visible) {
    failures++;
    console.error(`[RIEL] ${name}: el riel está en el DOM pero no se ve`);
  }
  if (r.entradas < 2) {
    failures++;
    console.error(`[RIEL] ${name}: ${r.entradas} entrada(s); todo rol ve al menos Desafíos y Talleres`);
  }
  if (r.activas > 1) {
    failures++;
    console.error(`[RIEL] ${name}: ${r.activas} entradas marcadas como activas a la vez`);
  }
}
```

Llamarla desde `capturar()`, junto a las demás. Y en el angosto, donde ya se
mide `[REFERENCIA]` a 1100×900, agregar la comprobación de que siguió visible y
**cambió de orientación**:

```js
  const angosto = await page.evaluate(() => {
    const riel = document.querySelector('.app-rail');
    if (!riel) return null;
    const c = riel.getBoundingClientRect();
    return { visible: c.width > 0 && c.height > 0, vertical: c.height > c.width };
  });
  if (angosto && (!angosto.visible || angosto.vertical)) {
    failures++;
    console.error(`[RIEL] ${name} a 1100px: el riel ${angosto.visible ? 'siguió vertical' : 'desapareció'} — abajo de 1024 tiene que ser una fila`);
  }
```

Y el piso, junto a los otros contadores del final:

```js
  if (rielesMedidos < PISO_DE_RIEL) {
    failures++;
    console.error(`[RIEL] sólo ${rielesMedidos} pantallas tuvieron riel y el piso es ${PISO_DE_RIEL}: la guarda dejó de verlo`);
  }
```

- [ ] **Step 9: Probar la guarda por mutación**

```bash
make yarn-build && make screens      # verde ANTES de mutar
cp app/assets/stylesheets/application.css /tmp/hoja.bak
```

Mutar: en la media query, cambiar la regla del riel por `display: none` — el
bug exacto que la guarda existe para cazar.

```bash
make yarn-build && make screens
```

Expected: **FALLA** con `[RIEL] ... a 1100px: el riel desapareció`.

```bash
cp /tmp/hoja.bak app/assets/stylesheets/application.css
make yarn-build && make screens
```

Expected: vuelve a pasar.

- [ ] **Step 10: Commit**

```bash
git add app/views/layouts/ app/helpers/shell_helper.rb app/assets/images/rail \
        app/assets/stylesheets/application.css script/capture_screens.js
git commit -m "El riel de navegación, afuera de .app-shell

No es navegación nueva: es la de .app-nav con las mismas cinco entradas y los
mismos permisos, mudada a donde la pone el diseño de INNK.

Va como envoltorio y no como una columna más de .app-shell, porque en el diseño
arranca en el borde de arriba y abarca la barra. Así las cuatro reglas de
grilla de .app-shell quedan intactas.

Sólo con sesión y empresa elegida: una columna de 80px vacía en el selector de
empresa se lee como un error.

Abajo de 1024px se vuelve fila, el mismo mecanismo que .flow-strip usa para el
drawer. NO se esconde: un riel que desaparece deja la app sin navegación
global, y la guarda [RIEL] mide la posición real y no la clase, porque un riel
con display:none tiene la clase igual."
```

---

## Task 6: La banda de título

**Files:**
- Modify: `app/views/layouts/application.html.haml`
- Modify: las **20** vistas con `.page-head` (lista abajo)
- Modify: `app/assets/stylesheets/application.css`
- Modify: `script/capture_screens.js`

**Interfaces:**
- Consumes: `--color-primary` de la Tarea 2.
- Produces: `content_for :banda` — cada pantalla publica el texto de su banda;
  el layout la dibuja antes del `yield`.

- [ ] **Step 1: La banda en el layout**

En `application.html.haml`, dentro de `%main.app-main`, **antes** de los flash:

```haml
        -# La banda de título: ancho completo, el color de la marca, el nombre
        -# de la pantalla en blanco. La publica cada vista con
        -# `content_for :banda`, así que una pantalla que se olvide no dibuja
        -# una banda vacía: no dibuja ninguna, y `[BANDA]` lo dice.
        - if content_for?(:banda)
          %h1.page-banner= yield :banda
```

- [ ] **Step 2: El estilo**

```css
/* La banda de título. El `%h1` vive ACÁ y no en `.page-head`: en el diseño el
   breadcrumb y las acciones van debajo de la banda, no adentro. Meterlas
   adentro dejaría los `btn btn-primary` sobre un fondo del mismo color, donde
   desaparecen, y obligaría a inventar una variante clara que el diseño no
   define. */
.page-banner {
  margin: 0;
  padding: 10px 24px;
  border-radius: var(--radius-field);
  background: var(--color-primary);
  color: var(--color-primary-content);
  font-size: 22px;
  font-weight: 700;
  letter-spacing: -.01em;
}
```

- [ ] **Step 3: Partir `.page-head` en las 20 vistas**

En cada una, el `%h1.page-title` sale de `.page-head` y pasa a ser
`content_for :banda`. El breadcrumb, el subtítulo y `.page-head__actions`
quedan donde están.

Ejemplo, `app/views/criteria_sets/index.html.haml`:

```haml
- content_for :title, "Criterios"
- content_for :banda, "Sets de criterios"
.page-head
  %div
    %p.muted Plantillas reusables. Al activar un módulo de evaluación, sus criterios quedan congelados ahí.
  = link_to "Nuevo set", new_criteria_set_path, class: "btn btn-primary"
```

Ejemplo con breadcrumb, `app/views/steps/_header.html.haml`: el
`content_for :banda` lleva `step.name`, y el `%p.breadcrumb` se queda en
`.page-head`.

Las 20: `criteria_sets/{new,index,edit,show}`, `steps/_header`,
`steps/config/_shell`, `workshops/index`, `ai_runs/{index,show}`,
`workshop_rooms/show`, `notifications/index`, `assessments/new`,
`ideas/{show,index,diff}`, `previews/show`, `challenges/{index,builder,show}`,
`memberships/index`.

Un `.page-head` que quede con un solo hijo y sin acciones se puede borrar.

- [ ] **Step 4: Borrar `.page-title` si quedó sin uso**

```bash
grep -rn 'page-title' app/views --include=*.haml
```

Si no queda ninguno, borrar la regla `.page-title` de la hoja —el lint de
reglas sin elemento lo va a exigir igual—.

- [ ] **Step 5: La guarda `[BANDA]`**

```js
// `[BANDA]` — que la banda se dibuje y su texto se lea sobre ella.
//
// Dos cosas distintas. Que se dibuje caza la vista que se olvidó el
// `content_for :banda` en la mudanza de las veinte —es edición repetida, que
// es donde más fácil se cuela una—. Y el contraste la mantiene honesta si
// alguna vez se vuelve a tocar el primario: hoy mide 6,06:1, pero nada más lo
// vigila (`[CONTRASTE]` sólo mira `.badge` y `.alert`).
let bandasMedidas = 0;
const PISO_DE_BANDAS = 30;

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
  for (const m of medidos) {
    if (!m.texto) {
      failures++;
      console.error(`[BANDA] ${name}: la banda se dibuja vacía`);
      continue;
    }
    if (m.ratio < 4.5) {
      failures++;
      console.error(`[BANDA] ${name}: «${m.texto}» mide ${m.ratio.toFixed(2)}:1 sobre la banda, y el piso es 4,5:1`);
    }
  }
}
```

Más el piso al final, con el mismo molde que `[RELLENO]`:

```js
  if (bandasMedidas < PISO_DE_BANDAS) {
    failures++;
    console.error(`[BANDA] sólo ${bandasMedidas} pantallas dibujaron banda y el piso es ${PISO_DE_BANDAS}`);
  }
```

- [ ] **Step 6: Mutación**

```bash
make yarn-build && make screens      # verde ANTES
cp app/views/criteria_sets/index.html.haml /tmp/cs.bak
```

Mutar: borrar la línea `content_for :banda` de esa vista.

```bash
make screens
```

Expected: **FALLA**, el conteo baja. Si el piso de 30 no lo detecta porque
sobra margen, bajar la mutación a borrar la línea de `application.html.haml`
que dibuja la banda: ahí el conteo cae a 0 y falla seguro.

```bash
cp /tmp/cs.bak app/views/criteria_sets/index.html.haml && make screens
```

- [ ] **Step 7: Commit**

```bash
git add app/views app/assets/stylesheets/application.css script/capture_screens.js
git commit -m "La banda de título, con el h1 adentro

El h1 sale de .page-head y pasa a content_for :banda; breadcrumb, subtítulo y
acciones quedan debajo, que es como lo dibuja el diseño.

Meter .page-head entero adentro de la banda habría sido una regla de CSS y cero
vistas tocadas, pero deja los btn-primary de las acciones sobre un fondo del
mismo color —donde desaparecen— y obliga a inventar una variante clara que el
diseño no define.

Son veinte vistas y la edición es repetida, que es donde más fácil se cuela una
olvidada: [BANDA] cuenta cuántas dibujaron banda y falla si contó de menos.
También mide el contraste del título sobre ella, que no lo vigilaba nadie —
[CONTRASTE] sólo mira badge y alert."
```

---

## Task 7: Superficies y radios

**Files:**
- Modify: `app/assets/stylesheets/application.css`
- Modify: `script/capture_screens.js`

**Interfaces:**
- Consumes: los tokens de la Tarea 2.
- Produces: `--shadow` redefinido con `light-dark()` y `--borde-superficie`
  nuevo, consumidos por `.card` y por el bloque de campos.

- [ ] **Step 1: Verificar `light-dark()` ANTES de escribir nada**

Todo el diseño de esta tarea depende de que la función exista en el Chromium
del recorrido.

```bash
node -e '
const { chromium } = require("playwright");
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  await p.setContent("<div id=x style=\"color-scheme:dark;background:light-dark(#fff,#000)\"></div>");
  console.log("resuelto:", await p.evaluate(() => getComputedStyle(document.getElementById("x")).backgroundColor));
  await b.close();
})();'
```

Expected: `rgb(0, 0, 0)`. Si devuelve `rgba(0, 0, 0, 0)` o vacío, la función no
está soportada: **no seguir con los pasos 2 y 3**, usar el plan B —declarar
`--shadow` y `--borde-superficie` dentro de cada bloque
`@plugin "daisyui/theme"`, con sus dos valores— y anotarlo en el commit.

- [ ] **Step 2: Redefinir `--shadow` y agregar `--borde-superficie`**

En el bloque `:root`:

```css
  /* INNK no usa bordes: la tarjeta y el campo se definen con una sombra. Pero
     una sombra negra al 10% SOBRE UNA SUPERFICIE OSCURA no existe, y el diseño
     no lo resuelve porque no tiene tema oscuro. Así que el tratamiento depende
     del esquema y no de la clase.

     `light-dark()` resuelve contra `color-scheme`, que los DOS temas ya
     declaran: una declaración por token, sin duplicar selectores y sin
     depender de si el tema entró por el atributo o por el media query.

     `--shadow` se REDEFINE en vez de agregar un token nuevo: sus cinco usos
     son todos superficies —`.card`, `.auth-card` y las tres barras de acciones
     pegadas— así que alcanza a todas y no quedan dos tokens de sombra
     conviviendo. */
  --shadow: light-dark(0 2px 20px rgba(0, 0, 0, .1), 0 1px 3px rgba(0, 0, 0, .4));

  /* Sólo para el borde de la tarjeta y del campo. `--borde` NO se toca: lo
     usan los divisores, las celdas de tabla y los `border-top` de
     `.config-advanced` y `.field-list__item`, que en tema claro siguen
     haciendo falta. */
  --borde-superficie: light-dark(transparent, var(--borde));
```

- [ ] **Step 3: Consumirlo en los dos lugares**

```css
.card {
  --card-p: 20px;
  --card-fs: 14px;
  background: var(--surface);
  border: 1px solid var(--borde-superficie);
  border-radius: var(--radius);
  box-shadow: var(--shadow);
}
```

Y en el bloque de campos (`input[type="text"], ... textarea, select`):

```css
  border: 1px solid var(--borde-superficie);
  box-shadow: var(--shadow);
```

- [ ] **Step 4: Los radios**

En los **dos** bloques `@plugin "daisyui/theme"`:

```css
  --radius-box: 1rem;        /* 16px: las tarjetas */
  --radius-field: 0.625rem;  /* 10px: campos y botones */
  --radius-selector: 0.5rem;
```

Los dos siguen saliendo del mismo token, así que el comentario que los ata —un
campo y un botón que no comparten radio se leen como un error de alineación—
se sostiene.

- [ ] **Step 5: La guarda `[SOMBRA]`**

```js
// `[SOMBRA]` — la sombra pasó a ser portante y nadie la medía.
//
// Antes la tarjeta se definía por su BORDE y la sombra era decorativa: perderla
// era cosmético. Ahora, en tema claro, el borde es transparente y la sombra es
// lo ÚNICO que define la tarjeta, así que perderla la deja sin contorno. Y está
// escrito que nadie la mira: `[CLASES]` mira fondo, relleno y borde;
// `[RELLENO]`, relleno; `[CONTRASTE]`, color.
//
// Cuenta cuántas midió y falla si midió de menos, por el mismo motivo que
// `[RELLENO]` y `[PASTILLA]`: una guarda que mide cero da verde y es
// indistinguible de una que funciona.
const PISO_DE_SOMBRAS = 150;
let sombrasMedidas = 0;

async function revisarSombra(page, name) {
  const r = await page.evaluate(() => {
    let total = 0;
    const sin = [];
    for (const card of document.querySelectorAll('.card')) {
      total++;
      const s = getComputedStyle(card).boxShadow;
      if (!s || s === 'none') sin.push(card.className);
    }
    return { total, sin: sin.slice(0, 4), cuantas: sin.length };
  });
  sombrasMedidas += r.total;
  if (r.cuantas) {
    failures++;
    console.error(`[SOMBRA] ${name}: ${r.cuantas} \`card\` sin sombra · ${r.sin.join(' · ')}`);
  }
}
```

Llamarla desde `capturar()`. Y el piso al final:

```js
  if (sombrasMedidas < PISO_DE_SOMBRAS) {
    failures++;
    console.error(`[SOMBRA] sólo ${sombrasMedidas} tarjetas medidas y el piso es ${PISO_DE_SOMBRAS}: la guarda dejó de verlas`);
  }
```

El piso se calibra con el número que imprima la primera corrida limpia, con el
mismo criterio que `PISO_DE_CARD_BODY`: holgura de una pantalla cargada, y muy
por encima del cero al que lo lleva un renombre.

- [ ] **Step 6: Mutación**

```bash
make yarn-build && make screens      # verde ANTES
cp app/assets/stylesheets/application.css /tmp/hoja.bak
```

Mutar: borrar `box-shadow: var(--shadow);` de la regla `.card`.

```bash
make yarn-build && make screens
```

Expected: **FALLA** con `[SOMBRA] ...: N card sin sombra`.

```bash
cp /tmp/hoja.bak app/assets/stylesheets/application.css && make yarn-build && make screens
```

- [ ] **Step 7: Verificar el recorrido completo en los dos temas**

Run: `make yarn-build && make screens`
Expected: sin fallas. Mirar en particular que `[CLASES]` no marque tarjetas: la
tarjeta conserva su fondo, así que no debería, pero es justo el cambio que
podría dispararlo.

- [ ] **Step 8: Commit**

```bash
git add app/assets/stylesheets/application.css script/capture_screens.js
git commit -m "Superficies con sombra, y los radios de INNK

INNK no usa bordes: la tarjeta y el campo se definen con una sombra. Pero una
sombra negra al 10% sobre una superficie oscura no existe, y el diseño no lo
resuelve porque no tiene tema oscuro. El tratamiento depende entonces del
esquema y no de la clase, con light-dark(), que resuelve contra color-scheme
—que los dos temas ya declaran— sin duplicar selectores.

--shadow se redefine en vez de agregar un token: sus cinco usos son todos
superficies. --borde-superficie es nuevo y lo consumen sólo dos reglas;
--borde no se toca, porque lo usan los divisores y las celdas de tabla.

Y la guarda [SOMBRA]. Antes la tarjeta se definía por su borde y perder la
sombra era cosmético; ahora, en claro, la sombra es lo único que la define.
Estaba escrito que nadie la miraba."
```

---

## Task 8: Los formularios

**Files:**
- Modify: `app/assets/stylesheets/application.css`

**Interfaces:**
- Consumes: nada de las tareas anteriores.
- Produces: `.field` en dos columnas. No se toca ningún HAML.

- [ ] **Step 1: La regla**

Reemplazar `.field { margin-bottom: 16px; }` por:

```css
/* Etiqueta a la izquierda, campo a la derecha: es como lo dibuja INNK.
   Son 154 ocurrencias en 43 vistas y no se edita ninguna.

   La columna se fija POR HIJO y no con una grilla de dos columnas a secas: un
   `.field` con tres hijos —label, campo y `.field-hint`— se desarmaría, porque
   el tercero caería en la columna de la etiqueta. Así, todo lo que no sea
   `label` apila en la columna 2, sean dos hijos o cinco. */
.field {
  margin-bottom: 16px;
  display: grid;
  grid-template-columns: minmax(120px, 190px) minmax(0, 1fr);
  column-gap: 16px;
  align-items: start;
}
.field > label {
  grid-column: 1;
  margin: 0;
  text-align: right;
  font-size: 13px;
  /* El color sube de `--muted` a `--text`: en el diseño la etiqueta es parte
     del contenido y no una anotación. */
  color: var(--text);
}
.field > :not(label) { grid-column: 2; }

/* Dos columnas no entran en la referencia, que mide 320px. Se scopea igual que
   el `.app-aside .card { --card-p: 16px }` que ya está. */
.app-aside .field { display: block; }
.app-aside .field > label { text-align: left; margin-bottom: 5px; }

/* Y abajo de 1024px vuelve a apilarse, como en los frames de teléfono del
   diseño. */
@media (max-width: 1023px) {
  .field { display: block; }
  .field > label { text-align: left; margin-bottom: 5px; }
}
```

- [ ] **Step 2: Compilar y recorrer**

```bash
make yarn-build
make screens
```

Expected: sin fallas. `[ZONAS]`, `[REFERENCIA]` y `[DESGLOSE]` son las que más
podrían moverse: miran la forma de las pantallas de módulo, que es donde hay
más formularios.

- [ ] **Step 3: Mirar las capturas a ojo**

Las guardas miden reglas, no composición. Abrir al menos cuatro capturas con
formulario —una pantalla de configuración de módulo, el editor de criterios, la
creación de desafío y la sala de la mesa— y confirmar que ninguna etiqueta se
corta ni se superpone con su campo.

Es el paso que ninguna guarda reemplaza: un `.field` con un hijo inesperado
compila sin error y se ve mal.

- [ ] **Step 4: Commit**

```bash
git add app/assets/stylesheets/application.css
git commit -m "La etiqueta a la izquierda del campo

Como lo dibuja INNK. Son 154 ocurrencias en 43 vistas y no se edita ninguna:
la columna se fija por hijo y no con una grilla de dos columnas a secas, así un
.field con label, campo y hint apila los dos últimos en la columna 2 en vez de
mandar el hint a la columna de la etiqueta.

Tres excepciones: la referencia —320px, no entran dos columnas—, abajo de
1024px, y las islas Vue, que no usan .field.

La etiqueta sube de --muted a --text: en el diseño es parte del contenido y no
una anotación."
```

---

## Task 9: Documentar en CLAUDE.md

Lo que una sesión futura va a romper si no está escrito.

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Corregir la trampa de `data-theme`, que ahora es distinta**

La sección «Lo que más fácil se rompe» dice hoy «**`data-theme` NO va en el
`<html>`**». Eso dejó de ser cierto: va, pero **sólo si hay cookie**.
Reemplazar ese bloque por la regla nueva, conservando el porqué —que es lo que
no cambió—: con el atributo presente `:root:not([data-theme])` no matchea, así
que escribirlo siempre mata el modo oscuro automático; por eso «Auto» BORRA la
cookie en vez de escribir `"flow"`, y por eso lo escribe el servidor y no el
cliente.

- [ ] **Step 2: Anotar que son DOS layouts**

En la misma sección: `auth.html.haml` tiene su propio `%html` y no pasa por
`application.html.haml`. Todo lo que se agregue al `<html>` o al `<head>` va en
los dos, y el login es donde más se nota porque es público.

- [ ] **Step 3: Anotar el PDF**

La nota del PDF ya existe —«si el tema cambia, ese archivo se actualiza a
mano»— pero menciona `#5b3df5`. Actualizarla a `#4747f3`.

- [ ] **Step 4: Las guardas nuevas**

En la sección de `make screens`, sumar `[TEMA]`, `[RIEL]`, `[BANDA]` y
`[SOMBRA]` a la lista, con una línea cada una de qué cazan y por qué existen.
Y actualizar la frase «Cinco de las guardas cuentan cuánto midieron»: ahora son
ocho.

- [ ] **Step 5: Lo que sigue sin vigilancia**

Dejar escrito, con el mismo tono que la nota que ya está sobre `[CARD]`:

- `--card-fs` (la letra de 14px) sigue sin medirse. `[SOMBRA]` cubre un tercio
  de lo que medía el viejo `[CARD]` y `[RELLENO]` otro; éste queda afuera.
- `[REFERENCIA]` sigue sin medir la sala de la mesa.
- El riel a 414px no lo mira ninguna captura: el recorrido no fotografía anchos
  de teléfono.

- [ ] **Step 6: La fuente**

Actualizar la sección de fuentes: una familia y no dos, Open Sans, y el peso
nuevo. La razón de auto-hospedarlas no cambió y se conserva tal cual.

- [ ] **Step 7: Commit**

```bash
git add CLAUDE.md
git commit -m "CLAUDE.md: el rediseño INNK y sus trampas nuevas

La regla de data-theme cambió y es la que más fácil se rompe: ahora el atributo
VA, pero sólo si hay cookie. El porqué no cambió —con el atributo presente
:root:not([data-theme]) no matchea— y es lo que obliga a que «Auto» borre la
cookie en vez de escribir \"flow\".

Queda anotado que son dos layouts y no uno, las cuatro guardas nuevas, y los
tres lugares que siguen sin vigilancia para que nadie los dé por cubiertos."
```

---

## Verificación final

- [ ] `make spec` — suite completa en verde. Baseline antes de empezar: 1612
      ejemplos. Después tiene que haber **más**, no los mismos: las tareas 1 y
      4 agregan specs.
- [ ] `make yarn-build && make screens` — sin errores de JS, sin HTTP >= 400, y
      los contadores por encima de sus pisos. Ahora son ocho: `[RITMO]`,
      `[RELLENO]`, `[PASTILLA]`, `[CRITERIO]`, `[LIVE]`, `[RIEL]`, `[BANDA]`,
      `[SOMBRA]`, más `[TEMA]` que no cuenta sino que corre una vez.
- [ ] `grep -rn '5b3df5\|Bricolage\|Inter\b' app/ public/ --include='*.css' --include='*.haml'`
      → sin resultados. Cualquiera de los tres es un resto de la paleta o la
      tipografía anterior.
- [ ] Las capturas, a ojo, en los dos temas. Las guardas miden reglas; que la
      pantalla se vea bien no lo contesta ninguna.
