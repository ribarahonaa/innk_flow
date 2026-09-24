# El estado se dibuja de UNA forma

El estado del dominio se pinta hoy de tres maneras distintas, y la app se lee
como tres apps. Al terminar hay una sola: **el chip**. Y hay una guarda que
mide que el chip se vea como chip, en las 66 pantallas y en los dos temas.

Es la primera de las tres inconsistencias sistémicas que dejó el repaso de
capturas. Las otras dos —el monospace usado para prosa y para números, y el
«N de M · ahora: X» que se lee como posición— no entran acá.

Leé primero la sección «El sistema visual» de `CLAUDE.md`: las tres capas, de
quién es cada regla, y por qué las clases propias van sin capa. Acá se usa esa
plomería y no se toca.

---

## Qué cambió al medirlo

El handoff describía las tres formas así: badge en la ficha del desafío y en el
builder en borrador; **texto de color sin badge** en el builder con el flujo
arrancado; y una palabra gris con borde izquierdo de 3px en «Cómo le fue».

**La segunda no existe.** Medido contra la app corriendo, componiendo cada
fondo hasta el primer opaco y leyéndolo en sRGB —los tokens se computan en
`oklab()`, así que leerlos crudo da números que en pantalla no existen—:

| Pantalla | Chip | pastilla / fondo |
|---|---|---|
| Builder arrancado | «En curso» | **1,014:1** |
| Builder arrancado | «Completado» | 1,022:1 |
| Ficha del desafío | «Completado» sobre blanco | 1,084:1 |
| Ficha del desafío | «En curso» en la fila activa | 1,014:1 |
| Ficha de la idea | «Sugerencia» | 1,014:1 |
| Builder borrador | «Pendiente» (neutro) | 1,201:1 |

El builder arrancado **no dibuja texto de color: dibuja un `badge` cuya
pastilla mide 1,02:1 contra lo que tiene detrás.** La clase es la misma que en
la ficha —`PipelinePresenter` la manda hecha con el mismo `chip_de_estado` que
el HAML—; lo que cambia es la superficie.

La causa es una sola línea de DaisyUI:

```css
.badge-soft { background-color: color-mix(in oklab, var(--badge-color) 8%, var(--color-base-100)) }
```

La mezcla va contra `--color-base-100`, o sea contra **blanco**, no contra la
superficie real. `.step-card--locked` pinta `var(--bg)` (base-200, 96,5% de
luminosidad) y un 8% de verde sobre blanco cae justo ahí: la pastilla
desaparece. Y con 8% la pastilla es débil **en toda la app**: el único que se
lee es el neutro, y sólo porque `base-content` es oscuro.

El contraste del **texto** está bien en todos los casos (5,2:1 y más, medido).
Lo que falta es la pastilla.

**Y apareció una cuarta forma, que el handoff no tenía.** En la ficha de la
idea, una ronda de feedback cerrada se pinta con `chip_de_estado("skipped")`
—ámbar— mostrando la etiqueta de su estado real en minúscula
(`app/views/ideas/show.html.haml:131`). O sea un chip ámbar que dice
«completado»: el color dice una cosa y la palabra otra.

Así que las formas reales son: **el chip** (la nominal, con la pastilla casi
invisible en las variantes de color), **`.result`** (otro vocabulario, en
«Cómo le fue») y **el chip que miente** (la ronda cerrada).

---

## 1 · Alcance

**Entra:**

- El relleno y el borde de `badge-soft`, para las seis familias de chip
  (`CHIP_DE_ESTADO`, `CHIP_DE_ORIGEN`, `CLASE_DE_FEEDBACK`,
  `CLASE_DE_NODO_DE_FLUJO`, `CHIPS`, `CHIP_DE_VEREDICTO`, más `CHIP_DE_IA`).
- `CLASE_DE_RESULTADO` → `CHIP_DE_RESULTADO`, y la fila de «Cómo le fue».
- La ronda cerrada de la ficha de la idea.
- La guarda `[PASTILLA]` en `make screens`, con su autotest.
- Los specs del helper que se mueven con eso.

**No entra:**

- `.alert`. Las variantes suaves de aviso tienen el mismo 8% de fondo, pero son
  cajas grandes con borde propio y se leen. Meterlas amplía el cambio sin que
  nada lo pida. Si `[PASTILLA]` se extendiera a `.alert` mañana, es una línea.
- `CLASE_DE_PASO_DE_SETUP` y `PUNTO_DE_ESTADO`. Son el mismo estado con otra
  forma **a propósito**: el paso a paso del drawer y el punto de color no son
  chips y no tienen lugar para una palabra. `CLAUDE.md` ya lo dice y
  `PUNTO_DE_ESTADO` tiene su propia guarda con piso de 3:1 (`[PUNTOS]`), que es
  el de WCAG 1.4.11 porque ahí el color SÍ carga la información.
- `CLASE_DE_NODO_DE_FLUJO` cambia de aspecto —hereda el relleno nuevo— pero no
  de vocabulario: sigue siendo el mapa compacto, con su `border-dashed` para el
  salteado.
- Rediseñar ninguna pantalla. Lo único que se mueve es el chip.

---

## 2 · La pastilla se compone contra su superficie

### El mecanismo

En vez de mezclar contra `--color-base-100`, **el relleno lleva alfa**:

```css
/* DaisyUI:  color-mix(in oklab, <color> 8%, var(--color-base-100))  ← contra blanco */
/* Acá:      color-mix(in oklab, <color> N%, transparent)            ← contra lo que haya */
```

Un relleno con alfa se compone sobre el fondo real por construcción. El
navegador hace lo que si no habría que declarar superficie por superficie, y
**no hay lista que enumerar ni superficie nueva que pueda reintroducir el
bug**. Importa: en la hoja hay dieciséis reglas que pintan `var(--bg)` y al menos
seis de ellas alojan chips (`.step-card--locked`, `.feedback-item.is-addressed`,
`.feedback-round--cerrada .feedback-item`, `.ranking-table tr.is-below td`,
`.criterion-row`, `.criterion-edit`), más las superficies teñidas
(`.table tr.is-active td` con `--accent-soft`, el panel de IA con
`--ia-panel`). Una lista de ocho que hay que mantener a mano es exactamente el mecanismo que este repo ya vio fallar
tres veces: la guarda de IA escrita a mano en ocho llamadores, los renders de
`setup_nav`, la regla de estado repetida en cada vista.

### Dónde va

En `app/assets/stylesheets/application.css`, junto a las reglas que ya
corrigen el **color del texto** de las variantes suaves (hoy en `:1252-1265`),
con el mismo patrón: **reglas de dos clases, sin capa**. Sin capa le ganan a
DaisyUI —que vive en un `@layer`— y las dos clases le ganan a la regla neutra
de al lado sin pelear especificidad con nada más.

Hacen falta seis: la neutra (`.badge-soft` a secas, que cubre `badge`,
`badge-sm` y `badge-xs` sin variante de color) y una por cada
`badge-primary`, `badge-secondary`, `badge-success`, `badge-warning`,
`badge-error`.

El `border-color` de `badge-soft` también se mezcla contra base-100, así que va
por el mismo camino. Si no, sobre base-200 el borde queda **más claro** que la
superficie y dibuja un halo.

### El piso

**1,2:1 de la pastilla contra su fondo compuesto, en los dos temas.**

Sale de lo que hoy funciona: el chip neutro mide 1,201:1 y se lee perfecto como
pastilla (mirá «Pendiente» en `09-9-builder-sin-formulario.png`). No es WCAG
1.4.11: el texto del chip ya pasa 4,5:1 y la pastilla no carga información, así
que exigir 3:1 sería inventar un requisito y forzaría un tinte que no se parece
a lo que la app quiere.

**Los porcentajes salen de medir, uno por variante.** Es lo mismo que ya se
hizo con `--ok`, `--warn` y `--danger`, cuyos 70/60/85% salieron de medir y no
de elegir. Los valores concretos los fija la implementación; lo que el spec
fija es el piso y que el **mínimo medido quede en ~1,25** — con el piso al ras,
un redondeo pone la corrida en rojo sin que nadie haya tocado nada.

### El riesgo, dicho

Oscurecer la pastilla **baja el contraste del texto que va encima**. Hoy las
variantes andan en 5,2:1 con piso de 4,5. Si alguna se acerca, hay que
reajustar `--ok` / `--warn` / `--danger`, que es justamente para lo que
existen. No hay que construir nada para verlo: `[CONTRASTE]` ya corre en cada
pantalla y en el muestrario, en los dos temas.

El tema oscuro se mide igual y no se da por hecho. Sobre una superficie oscura
el alfa **aclara** en vez de oscurecer, así que la dirección se da vuelta sola
—igual que `--ok`/`--warn`/`--danger`, que mezclan hacia `base-content`— pero
el porcentaje que alcanza el piso puede no ser el mismo.

---

## 3 · «Cómo le fue» pasa a chip

Hoy la fila es `nombre del módulo` + una palabra gris a la derecha, y toda la
distinción la carga un borde izquierdo de 3px que **sólo colorea dos de los
cinco estados**: `advanced` en verde y `eliminated` en rojo. `pending`,
`in_progress` y `done` comparten el mismo borde neutro, así que «Pendiente» y
«Listo» se ven idénticos.

`EstilosHelper::CLASE_DE_RESULTADO` → **`CHIP_DE_RESULTADO`**, con los cinco
`StepEntry::STATUSES`:

| Estado | Etiqueta (`flow.entry_statuses`) | Color |
|---|---|---|
| `pending` | Pendiente | neutro |
| `in_progress` | En curso | acento |
| `done` | Listo | neutro |
| `advanced` | Avanzó | ok |
| `eliminated` | No avanzó | warn |

Dos decisiones que no se leen solas:

**`done` va neutro.** Es exactamente lo que dice el borde de hoy —sólo
`advanced` y `eliminated` llevan color— y deja el verde significando «avanzó»,
que es la única buena noticia de la lista. La alternativa era `done` en ok,
espejando `completed` → success de `CHIP_DE_ESTADO`; el precio era que «Listo»
y «Avanzó» quedaran del mismo verde y la columna perdiera su señal. Que
`pending` y `done` compartan clase no es un descuido: la palabra los distingue,
igual que en `CHIP_DE_ESTADO`, donde cuatro estados comparten el neutro.

**`eliminated` va ámbar y no rojo.** Hoy «quedó afuera» se pinta de dos colores
según dónde se mire: `chip_de_estado("skipped")` —ámbar— en la ficha de la idea
y en la lista, y `var(--danger)` —rojo— en `.result--eliminated`. Gana el
ámbar: que una idea no avance es el resultado normal de un filtro, no un error,
y el rojo de la app queda para lo que falló. De paso `CHIP_DE_ESTADO` sigue sin
variante de error, que es una decisión tomada —lo dice el comentario de
`CHIP_DE_VEREDICTO`— y no un olvido.

En la hoja se van `.result--pending`, `.result--in_progress`, `.result--done`,
`.result--advanced`, `.result--eliminated` y el `border-left-width: 3px` de
`.result`. La regla y el markup se borran **en el mismo cambio**: dejar la
clase en el HAML sin regla detrás es justo lo que caza `[CLASES]`, y dejar la
regla sin quien la use es CSS muerto.

`.result` se queda con su caja (flex, padding, borde de 1px, radio) y
`.result__step` / `.result__score` intactos. `.result__outcome` —la palabra
gris— lo reemplaza el chip.

---

## 4 · La ronda cerrada deja de mentir

`app/views/ideas/show.html.haml:131` pinta `chip_de_estado("skipped")` y le
pone al lado `t("flow.statuses.#{paso.status}").downcase`. Con una ronda
`completed` sale un chip **ámbar que dice «completado»**.

Pasa a `chip_de_estado(paso.status)`. Una ronda completada sale verde; una
salteada sigue ámbar, que es lo que `skipped` siempre quiso decir.

**La minúscula se queda.** Ahí el chip se lee como parte de la frase, igual que
el «en curso» de la ronda abierta tres líneas más arriba. No es el caso de la
ficha del desafío, donde el chip es la etiqueta de un campo.

---

## 5 · La guarda `[PASTILLA]`

Función nueva en `script/capture_screens.js`, llamada desde `capturar()`. Eso
la pone **en las 66 pantallas y en los dos temas**, no en algunas: es el mismo
lugar desde donde corren `[CLASES]`, `[PANEL]` y `[CONTRASTE]`, y es lo que
hace que cubra también las pantallas a las que se llega por clic y nunca pasan
por `shot()`.

Mide, para cada `.badge` con caja: su fondo compuesto contra el fondo compuesto
de **su padre**. Reusa `fondoDe` y el manejo de `opacity` que ya tiene
`medirContraste` —un chip dentro de un contenedor atenuado se ve con menos
contraste del que da medirlo a opacidad plena, y eso ya está resuelto ahí—.
Falla por debajo del piso, listando clase y texto como hace `[CONTRASTE]`.

**Con autotest, como `probarMedidorDeContraste`.** Pares conocidos inyectados
en una página propia, incluida **una pastilla deliberadamente invisible que el
detector tiene que marcar**. Una guarda que siempre pasa es peor que ninguna, y
en esta rama ya pasó dos veces: el chequeo del selector de cantidad que estaba
FIJANDO el bug que había que arreglar, y `[FORMS]`, que no ve las pantallas a
las que se llega por clic.

Y hay que **verla fallar**: bajar a mano el porcentaje de una variante y
confirmar que la corrida se pone en rojo por eso y no por otra cosa.

---

## 6 · Lo que se mueve en los specs

`spec/helpers/estilos_helper_spec.rb`, en tres lugares:

1. **`todos_los_chips` suma `CHIP_DE_RESULTADO`.** De rebote, el spec «el
   muestrario de las capturas tiene cada chip del helper» obliga a que sus
   clases entren en `MUESTRARIO` de `capture_screens.js`, y con eso se miden en
   los dos temas aunque ninguna pantalla oscura del recorrido muestre esa
   lista. Y el spec «todos los chips son badge» pasa a cubrirlas.
2. **El spec contra `StepEntry::STATUSES` cambia de constante.** Sigue
   preguntando por las CLAVES, que es «no cae al fallback».
3. **El spec «cada resultado y cada tipo de diff pintan su propio modificador»
   pierde la mitad de resultado**, porque como chips `pending` y `done`
   comparten clase y ya no hay un `result--<clave>` que comparar. `CLASE_DE_DIFF`
   se queda.

El punto 3 **deja un hueco y hay que taparlo.** Ese spec existía para que un
`"advanced" => "result result--eliminated"` copiado de la línea de abajo no
pasara: con las claves solas, ese error pasa en verde. Se reemplaza por una
aserción directa de las dos celdas que importan —`advanced` es `badge-success`,
`eliminated` es `badge-warning`—, que es el mismo remedio del spec «la marca de
fuera del corte y la de sin responder no se confunden».

---

## 7 · Archivos

| Archivo | Qué |
|---|---|
| `app/assets/stylesheets/application.css` | Relleno y borde de `badge-soft` con alfa · se van `.result--*` y el borde de 3px |
| `app/helpers/estilos_helper.rb` | `CLASE_DE_RESULTADO` → `CHIP_DE_RESULTADO` y `clase_de_resultado` → `chip_de_resultado` |
| `app/views/ideas/show.html.haml` | La fila de «Cómo le fue» (`:70-77`) · la ronda cerrada (`:131`) |
| `script/capture_screens.js` | `[PASTILLA]` y su autotest · `MUESTRARIO` suma `CHIP_DE_RESULTADO` |
| `spec/helpers/estilos_helper_spec.rb` | Los tres movimientos de la sección 6 |

---

## 8 · Verificación

- `make spec` en verde. Hoy: 1115 ejemplos, 0 fallas.
- `make screens` en verde, con `[PASTILLA]` corriendo en las 66 pantallas y en
  los dos temas. Hoy: 66 capturas, 0 errores.
- **`[PASTILLA]` vista fallar**, bajándole el porcentaje a una variante a mano.
- **Las cuatro pantallas miradas a ojo**, antes y después:
  `05-builder` (la pastilla que hoy no está), `04-challenge` (el chip sobre
  blanco y el de la fila activa), `07-idea` («Cómo le fue» y la ronda cerrada)
  y `94-oscuro-evaluacion` (el tema oscuro). Mirar las capturas es la única
  revisión del rediseño que no hace una máquina, y esta rama ya demostró que
  cinco ítems del backlog no sobrevivían a que alguien mirara la fuente.

---

## 9 · Lo que este plan NO arregla

- **`.alert` sigue con el 8% de relleno.** Se lee porque es una caja grande con
  borde, pero es la misma línea de DaisyUI. Queda anotado.
- **La segunda y la tercera inconsistencia sistémica** —el monospace para prosa
  y para números, el «N de M · ahora: X» que se lee como posición— siguen
  abiertas.
- **Nada vigila el relleno por default de `card`** desde que se retiró
  `[CARD]`. `[PASTILLA]` no cubre ese hueco: mide chips, no tarjetas.
