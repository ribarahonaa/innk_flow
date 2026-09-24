# El estado se dibuja de UNA forma — Plan de implementación

> **Para quien ejecute esto:** SUB-SKILL REQUERIDA: usá
> `superpowers:subagent-driven-development` (recomendado) o
> `superpowers:executing-plans` para ejecutar tarea por tarea. Los pasos usan
> checkbox (`- [ ]`) para seguimiento.

**Objetivo:** Que el estado del dominio se dibuje de una sola forma —el chip—,
que el chip se vea como chip sobre cualquier superficie de la app, y que haya
una guarda que lo mida en las 66 pantallas y en los dos temas.

**Arquitectura:** Una regla de CSS sin capa que deriva el relleno y el borde
del chip de `currentColor` con alfa, así se componen contra la superficie real
en vez de contra blanco. Una guarda nueva (`[PASTILLA]`) que extiende el
medidor que ya existe. Y `CLASE_DE_RESULTADO` —el último mapa que pintaba un
estado con otra forma— pasa a ser una familia de chips más.

**Stack:** Tailwind 4 + DaisyUI 5 (config por CSS, sin `tailwind.config.js`),
HAML, RSpec, Playwright. Todo corre en Docker.

**Spec:** `docs/superpowers/specs/2026-09-24-el-estado-se-dibuja-de-una-forma-design.md`

## Restricciones globales

- **Código en inglés; comentarios y mensajes de commit en español.** Lo que ya
  está en español se queda (`chip_de_estado`, `clase_de_resultado`, los specs
  enteros): este plan renombra `CLASE_DE_RESULTADO` a `CHIP_DE_RESULTADO`
  porque cambia de familia, no para traducirlo.
- **Los specs corren en `app_test`**: siempre `make spec`, `make spec-file
  FILE=…`. Nunca `docker compose exec app bundle exec rspec` — devuelve 403
  «Blocked hosts» en todos los request specs y parece que la app está rota.
- **Tocar la hoja obliga a `make yarn-build`.** No hay watcher: el CSS lo
  compila el CLI de Tailwind a `app/assets/builds/`, y sin recompilar
  `make screens` mide la hoja vieja y da un verde mentiroso.
- **Nunca una clase interpolada.** Todo nombre de clase va completo y literal:
  Tailwind escanea texto. Hay guarda (`spec/lint/clases_interpoladas_spec.rb`).
- **Los porcentajes son los medidos: relleno 4%, borde 30%.** Subir el relleno
  baja el contraste del texto, que tiene 0,13 de margen sobre el piso de 4,5 en
  tema oscuro. No se cambian sin volver a medir.
- **Piso de pastilla: 1,25:1. Piso de texto: 4,5:1.** Los dos contra el fondo
  compuesto, en los dos temas.
- **Los commits no llevan línea `Co-Authored-By`.**
- **Sin worktree.** El stack de Docker está atado a `/home/ribarahonaa/innk_flow`;
  desde un worktree `make spec` correría contra otro compose.
- **Nadie pushea.** La rama `estado-una-forma` se queda local hasta que Raúl lo
  pida.

## Review Focus

Los cinco modos de falla que el spec implica y que, sin un test puesto a
propósito, pasan en verde. Cada uno tiene su test en la tarea que es dueña del
código.

1. **Un `.badge` con `border-width: 0` contado como si tuviera borde.** El
   `border-color` computado sigue siendo un color —`currentColor` por
   default— aunque no se dibuje nada, así que la guarda daría por definida una
   pastilla invisible. → Tarea 1, caso «borde sin ancho» del autotest.
2. **La atenuación aplicada a la pastilla y no a la superficie.** Un chip
   dentro de un contenedor con `opacity` se atenúa junto con lo que tiene
   detrás; atenuar sólo el chip infla el número. → Tarea 1, caso «atenuado a la
   mitad».
3. **La pastilla medida contra blanco y no contra la superficie real.** Es el
   bug original: sobre base-200 el chip mide 1,02:1 y el medidor tiene que
   verlo. → Tarea 1, caso «relleno sobre gris», y la corrida real.
4. **Un estado nuevo de `StepEntry` cayendo al neutro sin que nadie se
   entere.** → Tarea 2, el spec contra el enum.
5. **Las dos celdas de `CHIP_DE_RESULTADO` que dicen algo distinto, pegadas y
   cambiadas.** Como chips, `pending` y `done` comparten clase, así que el spec
   de «cada uno pinta su propio modificador» deja de aplicar y hay que pinchar
   las celdas que importan. → Tarea 2, spec «avanzó y no avanzó no se
   confunden».

---

## Estado de partida

Rama `estado-una-forma`, con los dos commits del diseño (`81915f8`, `6989e1e`).
`make spec` en 1115 ejemplos / 0 fallas y `make screens` en 66 capturas / 0
errores.

## Estructura de archivos

| Archivo | Responsabilidad | Tarea |
|---|---|---|
| `script/capture_screens.js` | El medidor devuelve también la pastilla · guarda `[PASTILLA]` · su autotest. `MUESTRARIO` no se toca: ver Tarea 2, paso 4 | 1 |
| `app/assets/stylesheets/application.css` | La regla de la pastilla (1) · la limpieza de `.result` (2) | 1, 2 |
| `app/helpers/estilos_helper.rb` | `CLASE_DE_RESULTADO` → `CHIP_DE_RESULTADO` | 2 |
| `app/views/ideas/show.html.haml` | La fila de «Cómo le fue» (2) · la ronda cerrada (3) | 2, 3 |
| `spec/helpers/estilos_helper_spec.rb` | Los tres movimientos del spec del helper | 2 |
| `spec/requests/feedback_spec.rb` | El chip de la ronda cerrada | 3 |

---

## Tarea 1: La pastilla se ve

La guarda primero y la regla después: lo que prueba que la regla hace algo es
ver a `[PASTILLA]` fallar sobre la app de hoy.

**Archivos:**
- Modificar: `script/capture_screens.js` (`medirContraste` en `:308-363`,
  `probarMedidorDeContraste` en `:378-406`, su llamada en `:686`, `capturar`
  en `:612-618`)
- Modificar: `app/assets/stylesheets/application.css` (después de `:1265`)

**Interfaces:**
- Produce: `medirContraste(page, selector)` devuelve, además de `ratio`, un
  campo **`pastilla`** (número). `revisarPastilla(page, name)` y la constante
  `PISO_DE_PASTILLA = 1.25`.
- Consume: `fondoDe`, `sobre`, `rgba`, `atenuacion` y `luminancia`, que ya
  viven dentro del `page.evaluate` de `medirContraste`.

---

- [ ] **Paso 1: Que el medidor devuelva también la pastilla**

En `script/capture_screens.js`, reemplazá el `.map(...)` final de
`medirContraste` (hoy en `:351-362`) por esto:

```js
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
          // Lo más FUERTE de los dos: cualquiera que llegue al piso deja la
          // pastilla definida.
          pastilla: Math.max(contraste(fondo, superficie), contraste(borde, superficie))
        };
      });
```

- [ ] **Paso 2: Comprobar que no se rompió el medidor viejo**

```bash
make screens
```

Esperado: **verde**, 66 capturas. `probarMedidorDeContraste` sigue pasando sus
ocho valores conocidos: el campo `ratio` no cambió de fórmula, sólo se le sumó
un hermano.

Si falla acá, es que `contraste(texto, fondo)` no quedó equivalente al cálculo
anterior. Arreglalo antes de seguir.

- [ ] **Paso 3: Escribir el autotest de la pastilla**

Justo después de `probarMedidorDeContraste` (termina en `:406`), agregá:

```js
// El medidor de pastilla se prueba contra valores conocidos ANTES de creerle.
// Los cinco casos están elegidos para que cada uno falle si el medidor está
// mal de una forma distinta:
//
//   - «relleno visible»     el relleno se mide, y el borde de ancho 0 no suma
//   - «sin relleno ni borde» el caso que la guarda existe para cazar: 1,00
//   - «solo borde»          el borde define la pastilla sin relleno
//   - «borde sin ancho»     un `border-color` con `border-width: 0` NO cuenta.
//                           Sin este caso, el medidor lo daría por bueno y la
//                           guarda pasaría en verde sobre un chip sin pastilla
//   - «relleno sobre gris»  se compone contra la SUPERFICIE y no contra
//                           blanco, que es el bug entero
//   - «atenuado a la mitad» la opacidad de un ancestro atenúa el chip Y su
//                           superficie, así que la diferencia no se infla
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
      <div style="background:#fff"><div style="opacity:.5">
        <span data-pastilla="1.145" style="background:#e0e0e0;border:0">atenuado a la mitad</span>
      </div></div>
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
```

- [ ] **Paso 4: Escribir la guarda**

Justo después de `revisarContraste` (termina en `:419`), agregá:

```js
// La pastilla de un chip: que se lea COMO pastilla y no como texto de color
// suelto.
//
// POR QUÉ EXISTE: `badge-soft` de DaisyUI mezcla su fondo contra
// `--color-base-100` —o sea contra BLANCO— y no contra la superficie que tiene
// detrás. Sobre una tarjeta base-200 (`.step-card--locked`, un comentario
// atendido, una fila fuera del corte) el tinte cae justo en la luminosidad del
// fondo y la pastilla desaparece: medido, 1,02:1 en el builder con el flujo
// arrancado, donde se veía como si el chip nunca hubiera existido.
//
// El piso es 1,25:1 y no 3:1: el TEXTO del chip ya pasa 4,5:1 —eso lo mide
// `[CONTRASTE]`— así que la pastilla no carga información y WCAG 1.4.11 no
// aplica. 1,25 sale de lo que hoy funciona: el chip neutro mide 1,201 y se lee
// perfecto.
//
// LO QUE NO VE: un `.badge` sin texto. El filtro es el de `medirContraste`, y
// hoy no existe ninguno —el punto de estado del drawer es
// `flow-drawer__punto`, con guarda propia y piso de 3:1, porque ahí el color
// SÍ es la información—. Si algún día hay un chip vacío, este piso le queda
// corto.
const PISO_DE_PASTILLA = 1.25;

async function revisarPastilla(page, name) {
  const bajos = (await medirContraste(page, '.badge')).filter((m) => m.pastilla < PISO_DE_PASTILLA);
  const unicos = [...new Map(bajos.map((m) => [m.clase, m])).values()].slice(0, 6);
  if (unicos.length) {
    failures++;
    console.error(`[PASTILLA] ${name}: ${unicos.map((m) => `«${m.texto}» (${m.clase}) ${m.pastilla.toFixed(2)}:1`).join(' · ')}`);
  }
}
```

- [ ] **Paso 5: Engancharla donde corre en TODAS las pantallas**

En `capturar` (hoy `:612-618`), después de `revisarContraste`:

```js
async function capturar(page, name) {
  await page.screenshot({ path: `${OUT}/${name}.png`, fullPage: true });
  await revisarClasesDescartadas(page, name);
  await revisarCardSinBody(page, name);
  await revisarContraste(page, name);
  await revisarPastilla(page, name);
  shots.push(name);
}
```

Y el autotest junto al otro, en `:686`:

```js
  await probarMedidorDeContraste(page);
  await probarMedidorDePastilla(page);
```

`capturar()` es lo que corre en las 66 pantallas —incluidas las que se abren
por clic y nunca pasan por `shot()`— y también en la pasada oscura, que la
llama igual (`:2061`). Enganchar la guarda en otro lado la deja ciega en más de
la mitad del recorrido.

- [ ] **Paso 6: Correr y VER FALLAR**

```bash
make screens
```

Esperado: **rojo**, con líneas `[PASTILLA]` en las pantallas que tienen chips
sobre base-200 o sobre una superficie teñida. El builder con el flujo arrancado
(`05-builder`) tiene que aparecer con «Completado» y «En curso» alrededor de
1,02:1.

El autotest tiene que pasar: si aparece `[PASTILLA] el medidor está mal`, el
problema es el medidor y no la app. Arreglalo antes de escribir la regla.

Anotá qué pantallas y qué clases salieron, para comparar en el paso 9.

- [ ] **Paso 7: La regla**

En `app/assets/stylesheets/application.css`, justo después del bloque que
corrige el color del texto (termina en `:1265`):

```css
/* La pastilla de un chip se compone contra SU superficie.

   `badge-soft` de DaisyUI mezcla fondo y borde contra `--color-base-100`, o
   sea contra BLANCO, y no contra lo que el chip tenga detrás. Sobre una
   tarjeta `--bg` (base-200) el tinte cae justo en la luminosidad del fondo y
   la pastilla desaparece: 1,02:1 medido en el builder con el flujo arrancado,
   donde el chip se veía como texto de color suelto. Con alfa se compone sobre
   el fondo real por construcción, así que no hay lista de superficies que
   mantener a mano.

   El que define la pastilla es el BORDE, no el relleno: el texto se apoya en
   el relleno, y subirlo hasta que se viera lo dejaba en 3,92:1 sobre base-200
   en tema claro. Con 4% y 30% la peor pastilla mide 1,53 (claro) y 1,59
   (oscuro) y el peor texto 4,85 y 4,63, los dos arriba de su piso. Los
   números salen de medir; subir el relleno los baja.

   Una sola regla y no seis: `currentColor` resuelve al color con el que el
   chip TERMINA pintando —incluidos `--ok`, `--warn` y `--danger`, que la
   regla de arriba le pone al texto de las tres variantes de aviso— así que
   cada variante tiñe con lo suyo y una variante nueva no se puede olvidar.
   Sin capa, como el resto de las clases propias: así le gana a DaisyUI. */
.badge-soft {
  background-color: color-mix(in oklab, currentColor 4%, transparent);
  border-color: color-mix(in oklab, currentColor 30%, transparent);
}
```

- [ ] **Paso 8: Recompilar la hoja**

```bash
make yarn-build
```

Sin esto `make screens` mide el CSS viejo y da verde o rojo por la razón
equivocada.

- [ ] **Paso 9: Correr y ver verde**

```bash
make screens
```

Esperado: **verde**, 66 capturas, sin `[PASTILLA]` ni `[CONTRASTE]`. Las
pantallas que anotaste en el paso 6 ya no aparecen.

Si sale una `[CONTRASTE]` nueva —texto por debajo de 4,5— **la salida es bajar
el relleno a 3%**, no retocar `--ok`/`--warn`/`--danger`: a 3% el peor texto
sube a 4,68/4,91 y la pastilla no se mueve, porque la sostiene el borde.
Después de cambiarlo, `make yarn-build` otra vez.

- [ ] **Paso 10: Ver fallar la guarda a mano**

Una guarda que nunca se vio fallar sobre la app real no está probada. Agregá
temporalmente al final de la hoja:

```css
.step-card--locked .badge-soft { border-color: transparent; }
```

```bash
make yarn-build && make screens
```

Esperado: **rojo**, con `[PASTILLA] 05-builder` alrededor de 1,05:1 — el
relleno solo, sin el borde que lo sostiene. Sacá las dos líneas, `make
yarn-build` y confirmá que vuelve a verde.

- [ ] **Paso 11: Mirar las capturas**

Abrí `tmp/screenshots/05-builder.png`, `04-challenge.png` y
`94-oscuro-evaluacion.png`. En el builder, «Completado» y «En curso» tienen que
leerse como pastillas con contorno, no como texto de color. Mirar las capturas
es la única revisión que no hace una máquina.

- [ ] **Paso 12: `make spec`**

```bash
make spec
```

Esperado: 1115 ejemplos, 0 fallas. Esta tarea no toca Ruby; si algo se rompió,
es un spec que miraba el CSS.

- [ ] **Paso 13: Commit**

```bash
git add script/capture_screens.js app/assets/stylesheets/application.css app/assets/builds/
git commit -F - <<'EOF'
La pastilla de un chip se ve sobre cualquier superficie

`badge-soft` de DaisyUI mezcla fondo y borde contra `--color-base-100`, o
sea contra blanco, y no contra lo que el chip tenga detrás. Sobre una
tarjeta base-200 el tinte cae justo en la luminosidad del fondo y la
pastilla desaparece: 1,02:1 medido en el builder con el flujo arrancado,
donde el chip se veía como texto de color suelto.

Con alfa se compone sobre el fondo real por construcción, así que no hay
lista de superficies que mantener a mano. El que define la pastilla es el
borde y no el relleno, porque el texto se apoya en el relleno: con 4% y
30% la peor pastilla mide 1,53 y 1,59 y el peor texto 4,85 y 4,63, los dos
arriba de su piso, y no hace falta tocar ningún token de texto.

Una sola regla y no seis por variante: derivada de `currentColor`, cada
chip tiñe con el color con el que termina pintando, así que una variante
nueva no se puede olvidar.

La guarda `[PASTILLA]` mide lo más fuerte del relleno y el borde contra el
fondo compuesto, en las 66 pantallas y en los dos temas. Con autotest de
seis casos, incluido un `border-width: 0` que no tiene que contar como
borde y un chip sin pastilla que tiene que marcar.
EOF
```

---

## Tarea 2: «Cómo le fue» pasa a chip

**Archivos:**
- Modificar: `app/helpers/estilos_helper.rb` (`CLASE_DE_RESULTADO` con su
  comentario en `:146-157`, `clase_de_resultado` en `:167`)
- Modificar: `app/views/ideas/show.html.haml:70-77`
- Modificar: `app/assets/stylesheets/application.css:2486-2505`
- Modificar: `spec/helpers/estilos_helper_spec.rb` (`:8-12`, `:82-84`,
  `:144-152`)

**Interfaces:**
- Produce: `EstilosHelper::CHIP_DE_RESULTADO` (hash congelado, claves
  `StepEntry::STATUSES`) y `chip_de_resultado(status)`.
- Deja de existir: `CLASE_DE_RESULTADO` y `clase_de_resultado`. Único llamador:
  `app/views/ideas/show.html.haml:73`.

---

- [ ] **Paso 1: Escribir los specs que fallan**

En `spec/helpers/estilos_helper_spec.rb`, cambiá `todos_los_chips` (`:8-12`)
para que incluya la familia nueva:

```ruby
  def todos_los_chips
    [EstilosHelper::CHIP_DE_ESTADO, EstilosHelper::CHIP_DE_ORIGEN, EstilosHelper::CLASE_DE_FEEDBACK,
     EstilosHelper::CLASE_DE_NODO_DE_FLUJO, EstilosHelper::CHIPS, EstilosHelper::CHIP_DE_VEREDICTO,
     EstilosHelper::CHIP_DE_RESULTADO]
      .flat_map(&:values) << EstilosHelper::CHIP_DE_IA
  end
```

Cambiá el spec del enum (`:82-84`) a la constante nueva:

```ruby
  it "cubre todos los estados de una entrada de módulo" do
    expect(sin_mapear(StepEntry::STATUSES, EstilosHelper::CHIP_DE_RESULTADO)).to be_empty
  end
```

Y reemplazá el spec de los modificadores (`:144-152`) por estos tres:

```ruby
  # `CLASE_DE_DIFF` sigue teniendo un modificador por clave, así que se prueba
  # además por el valor: con las claves solas, un
  # `"added" => "diff-kind diff-kind--removed"` pegado de la línea de abajo
  # pasaba.
  it "cada tipo de diff pinta su propio modificador" do
    EstilosHelper::CLASE_DE_DIFF.each do |clave, clase|
      expect(clase).to end_with("diff-kind--#{clave}"), "«#{clave}» pinta «#{clase}»"
    end
  end

  # `CHIP_DE_RESULTADO` ya no tiene modificador por estado: como chips,
  # `pending` y `done` comparten el neutro y la clase no dice qué clave la
  # pidió. El error que la prueba de arriba atajaba —dos celdas pegadas y
  # cambiadas— se ataja acá, sobre las tres que dicen algo distinto entre sí.
  it "avanzó, no avanzó y en curso no se confunden" do
    expect(helper.chip_de_resultado("advanced")).to include("badge-success")
    expect(helper.chip_de_resultado("eliminated")).to include("badge-warning")
    expect(helper.chip_de_resultado("in_progress")).to include("badge-primary")
  end

  # Que `done` vaya al neutro es una decisión, no un olvido: es lo que decía el
  # borde de 3px que esto reemplaza —sólo `advanced` y `eliminated` llevaban
  # color— y deja el verde significando «avanzó», que es la única buena noticia
  # de la lista.
  it "listo y pendiente van los dos al neutro" do
    neutro = EstilosHelper::CHIP_DE_ESTADO.fetch("pending")
    expect(helper.chip_de_resultado("done")).to eq(neutro)
    expect(helper.chip_de_resultado("pending")).to eq(neutro)
  end
```

- [ ] **Paso 2: Correr y ver fallar**

```bash
make spec-file FILE=spec/helpers/estilos_helper_spec.rb
```

Esperado: FALLA con `NameError: uninitialized constant
EstilosHelper::CHIP_DE_RESULTADO` y `NoMethodError: chip_de_resultado`.

- [ ] **Paso 3: El helper**

En `app/helpers/estilos_helper.rb`, reemplazá el bloque `CLASE_DE_RESULTADO`
con su comentario (`:146-157`) por:

```ruby
  # Las claves son StepEntry::STATUSES: la participación de UNA idea en un
  # módulo, que es otro enum que el estado del módulo. Por eso tiene mapa
  # propio, aunque comparta las cadenas con `CHIP_DE_ESTADO` — es el mismo
  # vocabulario visual, no el mismo dominio.
  #
  # Antes esto era `.result--*`: una palabra gris a la derecha y un borde
  # izquierdo de 3px que sólo coloreaba dos de los cinco estados. «Pendiente» y
  # «Listo» se veían idénticos.
  #
  # `done` va al NEUTRO y no al verde: es lo que decía ese borde —sólo
  # `advanced` y `eliminated` llevaban color— y así el verde queda
  # significando «avanzó», que es la única buena noticia de la lista. Que
  # `pending` y `done` compartan clase los distingue la palabra, igual que los
  # cuatro estados que comparten el neutro en `CHIP_DE_ESTADO`.
  #
  # `eliminated` va ÁMBAR y no rojo. Se pintaba de los dos colores según dónde
  # se mirara: ámbar en la ficha de la idea y en la lista
  # (`chip_de_estado("skipped")`), rojo en `.result--eliminated`. Que una idea
  # no avance es el resultado normal de un filtro, no un error: el rojo queda
  # para lo que falló, y `CHIP_DE_ESTADO` sigue sin variante de error.
  CHIP_DE_RESULTADO = {
    "pending" => "badge badge-soft badge-sm font-semibold whitespace-nowrap",
    "in_progress" => "badge badge-soft badge-primary badge-sm font-semibold whitespace-nowrap",
    "done" => "badge badge-soft badge-sm font-semibold whitespace-nowrap",
    "advanced" => "badge badge-soft badge-success badge-sm font-semibold whitespace-nowrap",
    "eliminated" => "badge badge-soft badge-warning badge-sm font-semibold whitespace-nowrap"
  }.freeze
```

Y en la lista de accesores (`:167`), cambiá:

```ruby
  def chip_de_resultado(status) = CHIP_DE_RESULTADO.fetch(status.to_s, CHIP_DE_RESULTADO.fetch("pending"))
```

- [ ] **Paso 4: Correr y ver pasar**

```bash
make spec-file FILE=spec/helpers/estilos_helper_spec.rb
```

Esperado: PASA.

**Corrección al spec de diseño:** su sección 6 dice que `MUESTRARIO` de
`capture_screens.js` suma las clases de `CHIP_DE_RESULTADO`. **No hace falta
tocarlo**: las cinco cadenas coinciden exactamente con las de `CHIP_DE_ESTADO`,
que ya están en el arreglo (es el mismo vocabulario visual, y el spec del
muestrario compara con `.uniq`). El mecanismo que el spec describe sigue en
pie: si mañana alguna celda se escribiera distinta, ese spec obliga a sumarla.

Por eso, si falla «El muestrario no mide: …», el problema es que alguna cadena
de `CHIP_DE_RESULTADO` se escribió distinta de la de `CHIP_DE_ESTADO`, no que
falte una entrada en el arreglo.

- [ ] **Paso 5: La vista**

En `app/views/ideas/show.html.haml`, las líneas `:73-75`:

```haml
              %li.result
                %span.result__step= resultado[:step].name
                %span{ class: chip_de_resultado(entry.status) }= t("flow.entry_statuses.#{entry.status}", default: entry.status.humanize)
```

(`%span.result__outcome` desaparece: lo reemplaza el chip.)

- [ ] **Paso 6: La hoja**

En `app/assets/stylesheets/application.css`, reemplazá el bloque de `.result`
(`:2486-2505`) por:

```css
/* ── Cómo le fue a una idea, módulo por módulo ─────────────────────────────── */
.result-list { list-style: none; margin: 0; padding: 0; display: grid; gap: 6px; }

/* Sin `border-left-width: 3px` ni `.result--*`: el estado lo dice el chip,
   como en el resto de la app. El borde coloreaba dos de los cinco estados y
   dejaba «Pendiente» y «Listo» idénticos. */
.result {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 9px 12px;
  border: 1px solid var(--borde);
  border-radius: 8px;
  font-size: 13px;
}

.result__step { flex: 1; font-weight: 600; }
.result__score { font-weight: 650; font-variant-numeric: tabular-nums; }
```

La regla y el markup se borran en el mismo paso: una clase en el HAML sin regla
detrás es lo que caza `[CLASES]`, y una regla sin quien la use es CSS muerto.

- [ ] **Paso 7: Confirmar que no quedó nada colgando**

```bash
grep -rn "result--\|result__outcome\|clase_de_resultado\|CLASE_DE_RESULTADO" app/ spec/ script/ --include=*.rb --include=*.haml --include=*.css --include=*.js --include=*.vue
```

Esperado: **sin resultados**. Cualquier línea que aparezca es algo que quedó
apuntando a lo que ya no existe.

- [ ] **Paso 8: Recompilar y correr todo**

```bash
make yarn-build && make spec && make screens
```

Esperado: 1115 ejemplos / 0 fallas y 66 capturas / 0 errores. `[PASTILLA]` mide
ahora también los chips nuevos de «Cómo le fue».

- [ ] **Paso 9: Mirar la captura**

Abrí `tmp/screenshots/07-idea.png`. La lista «Cómo le fue» tiene que mostrar
cinco chips —«Avanzó» verde, «Listo» neutro, «Pendiente» neutro— y ningún borde
izquierdo grueso.

- [ ] **Paso 10: Commit**

```bash
git add app/helpers/estilos_helper.rb app/views/ideas/show.html.haml \
        app/assets/stylesheets/application.css app/assets/builds/ \
        spec/helpers/estilos_helper_spec.rb
git commit -F - <<'EOF'
«Cómo le fue» dice el estado con un chip, como el resto de la app

Era la última forma distinta de dibujar un estado: una palabra gris a la
derecha y un borde izquierdo de 3px que sólo coloreaba dos de los cinco
estados, así que «Pendiente» y «Listo» se veían idénticos.

`CLASE_DE_RESULTADO` pasa a ser `CHIP_DE_RESULTADO` y la fila queda nombre
del módulo + chip + puntaje. `done` va al neutro y no al verde: es lo que
decía el borde, y así el verde queda significando «avanzó». `eliminated`
va ámbar y no rojo, que es lo que ya hacían la ficha de la idea y la
lista; que una idea no avance es el resultado normal de un filtro, no un
error.

De rebote la familia entra en `todos_los_chips`, así que el muestrario de
`make screens` la mide en los dos temas. El spec de «cada uno pinta su
propio modificador» deja de aplicarle —como chips, pending y done
comparten clase— y se reemplaza por aserciones sobre las celdas que dicen
algo distinto entre sí, que es el error que aquél atajaba.
EOF
```

---

## Tarea 3: La ronda cerrada deja de mentir

**Archivos:**
- Modificar: `app/views/ideas/show.html.haml:131`
- Modificar: `spec/requests/feedback_spec.rb` (dentro de `describe "con más de
  una ronda de evolución"`, después del spec de `:334-339`)

**Interfaces:** ninguna nueva. Usa `chip_de_estado`, que ya existe.

---

- [ ] **Paso 1: Escribir el spec que falla**

En `spec/requests/feedback_spec.rb`, dentro de `describe "con más de una ronda
de evolución"`, después del spec «la cerrada va plegada y la que está en curso,
abierta»:

```ruby
    # El chip de la ronda cerrada decía «completado» pintado de ÁMBAR: el color
    # de `skipped`, escrito a mano. El color decía una cosa y la palabra otra.
    # La ronda abierta es un `<p>`, así que el único `<summary>` de la pantalla
    # es el de la cerrada.
    it "la ronda cerrada se pinta con su propio estado" do
      get challenge_idea_path(challenge, idea)

      resumen = response.body[%r{<summary[^>]*>.*?</summary>}m]
      expect(resumen).to include("Ronda de feedback")
      expect(resumen).to include(EstilosHelper::CHIP_DE_ESTADO.fetch("completed"))
      expect(resumen).not_to include("badge-warning")
    end
```

- [ ] **Paso 2: Correr y ver fallar**

```bash
make spec-file FILE=spec/requests/feedback_spec.rb
```

Esperado: FALLA. El `<summary>` trae `badge badge-soft badge-warning badge-sm
font-semibold whitespace-nowrap` y no la cadena de `completed`.

- [ ] **Paso 3: La vista**

En `app/views/ideas/show.html.haml:131`:

```haml
                  %span{ class: chip_de_estado(paso.status) }= t("flow.statuses.#{paso.status}").downcase
```

La minúscula se queda: ahí el chip se lee como parte de la frase, igual que el
«en curso» de la ronda abierta tres líneas más arriba.

- [ ] **Paso 4: Correr y ver pasar**

```bash
make spec-file FILE=spec/requests/feedback_spec.rb
```

Esperado: PASA.

- [ ] **Paso 5: La suite y el recorrido**

```bash
make spec && make screens
```

Esperado: 1116 ejemplos / 0 fallas (uno más que antes de la tarea) y 66
capturas / 0 errores.

- [ ] **Paso 6: Commit**

```bash
git add app/views/ideas/show.html.haml spec/requests/feedback_spec.rb
git commit -F - <<'EOF'
La ronda de feedback cerrada se pinta con su propio estado

El chip estaba escrito a mano con el color de `skipped` y la etiqueta del
estado real, así que una ronda completada salía ámbar diciendo
«completado»: el color decía una cosa y la palabra otra.

Pasa a `chip_de_estado(paso.status)`. Una ronda completada sale verde y
una salteada sigue ámbar, que es lo que `skipped` siempre quiso decir. La
minúscula se queda: ahí el chip se lee como parte de la frase, igual que
el «en curso» de la ronda abierta.
EOF
```

---

## Cierre

- [ ] **`make spec` y `make screens` sobre el resultado final**, no sólo sobre
  la última tarea. Esperado: 1116 ejemplos / 0 fallas y 66 capturas / 0
  errores.
- [ ] **Las cuatro capturas miradas a ojo:** `05-builder`, `04-challenge`,
  `07-idea` y `94-oscuro-evaluacion`.
- [ ] **Merge a `master` local, sin PR** (es lo que Raúl viene haciendo), con
  `--no-ff` y sin línea de coautoría. **No se pushea** hasta que lo pida.
- [ ] **Handoff** en `handoff.md`, con sus cinco secciones e incluidos los
  intentos fallidos.

## Lo que este plan NO arregla

- `.alert` sigue con el 8% de relleno de DaisyUI. Se lee porque es una caja
  grande con borde propio, pero es la misma línea. `[PASTILLA]` mide `.badge`
  solamente; extenderla es cambiar un selector.
- Un `.badge` sin texto no lo mide nadie. Hoy no existe ninguno.
- Las otras dos inconsistencias sistémicas del repaso de capturas: el monospace
  usado para prosa y para números, y el «N de M · ahora: X» que se lee como
  posición.
- Nada vigila el relleno por default de `card` desde que se retiró `[CARD]`.
