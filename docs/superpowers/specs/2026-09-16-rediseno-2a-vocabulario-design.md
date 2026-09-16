# Rediseño, plan 2a: el vocabulario de componentes

Continúa `2026-09-08-rediseno-tailwind-daisyui-design.md`. Ese spec define el
rediseño entero en siete pasos; la fase 1 hizo del 1 al 4 (plomería, clases
dinámicas, tema, shell). Esto es el **paso 5**, y es el primero de tres planes:

| Plan | Paso del spec | Qué |
|---|---|---|
| **2a** | 5 | El vocabulario compartido: tarjetas, chips, avisos, tablas |
| 2b | 6 | Pantalla por pantalla, la peor primero |
| 2c | 7 | Las islas Vue |

Un plan por paso, y cada uno se escribe cuando el anterior está mergeado,
porque la forma del siguiente depende de cómo quedó éste. Es lo mismo que hizo
la fase 1 al dejar el plan 2 para después del shell.

---

## Qué cambió desde el spec original

**Los números.** Una semana entró configurar/ejecutar, los popups de la IA y el
paso a paso por módulos:

| | Spec | Hoy |
|---|---|---|
| Partials renderizados desde más de una vista | 18 | 22 |
| Vistas HAML | 54 | 66 |
| Componentes Vue | 7 | 8 |
| CSS escrito a mano (`application.css`) | — | 2.694 líneas |

**El paso 5 no es «los partials».** El spec lo llamaba «los 18 partials
compartidos», pero lo que se repite no vive sólo en partials: vive en
`EstilosHelper` —que la fase 1 dejó como el único lugar que traduce estado a
clase— y en unas pocas clases que aparecen en decenas de vistas. Cambiar el
helper cambia todas las vistas que lo usan sin tocarlas. Por eso el paso se
define por **vocabulario**, no por archivo.

**Tres filas de la tabla de mapeo del §4.** Salieron de medir, y cada una está
explicada abajo:

| Hoy | El spec decía | Queda |
|---|---|---|
| `.card` | `card` | `.panel` en 2a; `card` + `card-body` en 2b |
| `.flash--*` | `alert`, y `toast` como ganancia | `alert`; `toast` no entra |
| `.flow-strip` | `steps` | Contenedor propio; nodos `badge` |

---

## 1 · Las tarjetas: `.card` pasa a `.panel`

`card` de DaisyUI está excluida (`exclude: card` en el `@plugin`) porque además
de pintar declara `display: flex`. Sacar el `exclude` es **global**: unas 86
tarjetas en 40 archivos —12 partials, 26 vistas y 2 islas Vue— pasarían a ser
columnas flex a la vez. No se puede migrar de a una pantalla.

El número es el de una búsqueda al escribir esto, y no hay que creerle: una
clase se puede escribir de varias formas en HAML (`.card`, `class: "card"`,
`class: %w[card]`). El plan busca exhaustivo, y el `exclude` se saca recién
cuando la búsqueda da cero.

Por eso en dos tiempos:

1. **En 2a, `.card` se renombra a `.panel`** en todos lados: vistas, partials,
   las dos islas (`pipeline_builder`, `criteria_editor`), el selector de la hoja
   y las dos guardas de `make screens` que lo miran. Con ninguna tarjeta usando
   `.card`, se saca el `exclude`. **No cambia nada visible.**
2. **En 2b, cada pantalla pasa de `.panel` a `card` + `card-body`** cuando le
   toca. `.panel` se borra cuando no quede ninguna.

El renombre alcanza las islas aunque Vue sea el plan 2c: si no, al sacar el
`exclude` esas tarjetas se vuelven flex.

---

## 2 · Los chips pasan a `badge`

Cuatro familias con la misma forma —fondo suave, texto de color, píldora— y
cuatro nombres:

| Familia | Usos | Dónde se decide |
|---|---|---|
| `status-chip` | 42 | `CHIP_DE_ESTADO` y los tres `chip_de_*` que lo usan |
| `source-chip` | 8 | `CHIP_DE_ORIGEN` |
| `feedback-kind` | 7 | `CLASE_DE_FEEDBACK` |
| `ai-chip` | 12 en 9 vistas | escrita a mano en cada vista |

El spec mapeaba sólo `status-chip`. Las otras tres son lo mismo con otro
nombre, así que entran.

`ai-chip` es la única sin helper. Pasa a tener uno (`CHIP_DE_IA` en
`EstilosHelper`): escrito a mano en nueve vistas, `badge badge-soft
badge-secondary badge-xs uppercase font-bold` serían seis clases repetidas
nueve veces, que es justo lo que la regla del spec —si aparece en más de dos
vistas es un componente— existe para evitar.

### Por color, no por familia

El color de hoy ya agrupa los estados. El mapeo sigue esos grupos:

| Color de hoy | Qué lo usa | `badge` |
|---|---|---|
| neutro (`--neutro-soft`) | draft · pending · closed · archived | `badge badge-soft` |
| acento (`--accent`) | running · active · activating · sugerencia · manual | `badge badge-soft badge-primary` |
| ok (`--ok`) | completed · automático | `badge badge-soft badge-success` |
| warn (`--warn`) | skipped · pregunta · fórmula | `badge badge-soft badge-warning` |
| danger (`--danger`) | problema (`issue`) | `badge badge-soft badge-error` |
| ia (`--ia`) | origen IA · `ai-chip` | `badge badge-soft badge-secondary` |

`badge-soft` sin variante mezcla el color del texto al 8% sobre el fondo, que
es exactamente la receta de `--neutro-soft`. No hace falta `badge-ghost`.

### El contraste manda, y `badge-soft` no lo trae resuelto

**Verificado en el fuente de DaisyUI:** `badge-soft` pinta el texto con
`var(--badge-color)`, y `badge-warning` fija `--badge-color` en
`--color-warning` a secas. Pero la hoja de hoy no usa el color puro para el
texto de un chip: `--ok` es `success` mezclado al 70% con el texto, `--warn`
es `warning` al 60% y `--danger` es `error` al 85%. Alguien los oscureció
porque puros no llegaban al contraste —el `warning` del tema claro es un
amarillo de 72,9% de luminosidad—.

Así que **no se asume que `badge-soft` alcanza**. Antes de fijar el mapeo se
mide el contraste del texto de cada variante, **compuesto sobre su fondo** (la
regla de siempre: un color con alfa se compone antes de medirse), en los dos
temas. Donde no llegue a 4,5:1, el color del texto de esa variante se ajusta
con el mismo token que usa la hoja hoy:

```css
.badge-soft.badge-warning { color: var(--warn); }
```

Dos clases: le gana a `.badge-soft` por especificidad sin pelear la capa. No se
pasa a la variante sólida, que tiene el contraste resuelto por el tema pero
cambia chips suaves por bloques de color.

`primary` y `secondary` no se mezclaron nunca (`--accent` y `--ia` son el color
del tema tal cual) y hoy pasan; se miden igual.

### Lo que cambia a la vista, y es a propósito

Este paso **no es invisible**, y la verificación lo trata como tal:

- **El radio.** Los chips de hoy son píldoras (`border-radius: 99px`); el
  `badge` usa `--radius-selector`, que en los dos temas vale `0.5rem`. Se
  acepta el del tema: que el componente mande sobre la forma es lo que el
  rediseño compra.
- **El alto.** Lo fija el tamaño del `badge`. Los chips de hoy tienen 10 u 11px
  de letra: `badge-sm` (12px) para `status-chip` y los nodos del flujo,
  `badge-xs` (10px) para `source-chip`, `feedback-kind` y `ai-chip`. El helper
  devuelve el tamaño junto con la variante, así que sigue siendo un solo
  lugar.
- **Lo que el chip tiene y el `badge` no.** `feedback-kind` y `ai-chip` van en
  mayúsculas y en negrita. Se conservan con utilidades (`uppercase
  font-bold`) **en el helper**, que es el único lugar que las escribe; no en
  las vistas.

---

## 3 · El mapa del flujo: contenedor propio, nodos `badge`

`flow-strip` es el mapa compacto del pipeline en el índice de desafíos, la
ficha y la vista previa de una plantilla. El spec lo mandaba a `steps`, y a la
vez lo ponía en su §4 como ejemplo de clase propia de la app. La captura del
índice desempata: cada tarjeta mide unos 300px, y con siete módulos los nodos
**se reparten en dos o tres filas**. `steps` de DaisyUI no hace eso: pone
columnas iguales en una sola, con un círculo y la etiqueta debajo, y siete en
300px no dejan lugar para «Evaluación».

Así que `.flow-strip` sigue siendo el contenedor, con su reparto en filas, y
**sus nodos pasan a `badge`**. No con el mapeo de los chips: los nodos pintan
distinto los mismos estados —el chip `skipped` es amarillo, el nodo `skipped`
es neutro con el borde punteado—, y se respeta lo que pinta cada uno hoy:

| Estado | Hoy | `badge` |
|---|---|---|
| pending · activating | neutro, con borde | `badge badge-soft badge-sm` |
| active | acento, en negrita | `badge badge-soft badge-primary badge-sm font-semibold` |
| completed | ok | `badge badge-soft badge-success badge-sm` |
| skipped | neutro, borde punteado | `badge badge-dash badge-sm` |

Se ve casi igual que hoy.

La fila `flow-strip → steps` sale de la tabla de mapeo.

---

## 4 · Los avisos pasan a `alert`

Son dos cosas con la misma clase:

- **El flash de un redirect** («Feedback registrado.»): lo pinta el layout
  arriba del contenido, vía `clase_de_flash`. Pasa a `alert alert-success` o
  `alert alert-error` cambiando el helper.
- **Los avisos fijos de una pantalla** («Criterios derivados: …»): diez
  `.flash.flash--*` escritos a mano. Pasan a `alert alert-warning`,
  `alert-success` o `alert-error`, a mano.

**`toast` no entra.** El spec lo listaba como ganancia —que el flash deje de
empujar el contenido—, pero `toast` es CSS puro y no se cierra solo: quedaría
tapando una esquina hasta la próxima navegación. Cerrarlo pide JavaScript, y
cambiar cómo se comporta la pantalla merece su propio paso.

---

## 5 · Las tablas: `step-table` pasa a `table`

Quince usos, a mano. Es el más chico y el menos ambiguo.

---

## Fuera de alcance

- Pasar `.panel` a `card` + `card-body`: plan 2b.
- `toast`.
- Las islas Vue, salvo el renombre de `.card` que las alcanza: plan 2c.
- El tema, el layout y el shell: fase 1.
- El dominio, las policies, el motor y la IA, igual que en el spec original.

---

## Orden

Cada familia en su propio commit, con `make spec` y `make screens` en verde:

| # | Qué | ¿Cambia lo que se ve? |
|---|---|---|
| 1 | `.card` → `.panel`, y se saca el `exclude` | No |
| 2 | `step-table` → `table` | Poco |
| 3 | Avisos → `alert` | Sí |
| 4 | Chips → `badge`, con el contraste medido primero | Sí |
| 5 | Nodos del flujo → `badge` | Sí |
| 6 | Borrar el CSS a mano que quedó sin nadie que lo use | No |

El renombre va primero porque es el único que se verifica por «no cambió
nada», y así queda de punto de control, igual que el paso 1 de la fase 1.
Después, de lo más chico a lo más grande: las tablas y los avisos son pocos y
sin ambigüedad; los chips tocan cuatro familias y piden medir contraste antes
de elegir.

---

## Verificación

**Lo que ya existe sigue sirviendo:** nada compara píxeles.

**Se ajusta, en el mismo commit que lo necesita:**

- Las dos guardas de `script/capture_screens.js` que miran `.card` —la de
  clases descartadas (`[class*="badge"],…,.card`) y la de ritmo
  (`.app-main > .card`, la que atrapó las tarjetas que se tocaban)— pasan a
  `.panel`. Sin eso, las dos se quedarían mirando cero elementos y pasarían en
  verde sin probar nada.
- Las aserciones de `EstilosHelper` contra cada enum, que comparan con
  `end_with` para no confundir `--issued` con `--issue`: se reescriben contra
  el nombre nuevo.
- `spec/lint/clases_interpoladas_spec.rb` no cambia: los nombres nuevos
  también se escriben enteros.

**Cómo se verifica cada paso:**

- **El renombre (1):** las capturas antes y después tienen que dar iguales. Si
  una tarjeta se ve distinta, hay un `.card` que el renombre no agarró. Y
  después de sacar el `exclude` no puede quedar ningún `.card` en `app/`: se
  busca.
- **Los que cambian lo que se ve (2 a 5):** las capturas de antes y de después
  se miran a ojo, familia por familia, **en los dos temas**. El contraste de
  cada variante de `badge` se mide con el estilo computado y compuesto sobre
  su fondo, no leyendo el CSS.
- **El borrado (6):** por cada regla que se saca, se busca que su clase no
  aparezca en `app/views`, `app/helpers` ni `app/javascript`.

**Y `CLAUDE.md`**, que hoy dice que `card` está excluida, que la regla
alcanza a «las 101 tarjetas de la app» y que `status-chip` y compañía siguen
siendo CSS a mano, se actualiza en el commit que vuelve falsa cada frase.

---

## Riesgos

- **Un `.card` que el renombre no agarra**, armado en un `.js` o en un
  template literal de una isla. El `exclude` se saca recién cuando la búsqueda
  da cero en todo `app/`, y la guarda de clases descartadas ya mira `.js` y
  `.vue`.
- **El contraste de `badge-soft`** en `success`, `warning` y `error`, que es
  probable que no alcance. Está resuelto de antemano con los tokens que ya
  existen; lo que no está es el número, y se mide antes de elegir.
- **Un chip que hoy se ve bien por algo que no está en su clase**: un
  `margin-left` de `.source-chip`, el `font-weight: 600` del nodo activo. Las
  capturas familia por familia son las que lo muestran.

---

## Decisiones abiertas

1. **La marca de innk**, que sigue abierta desde el spec original y sigue sin
   bloquear: todo esto cuelga de los colores del tema.
