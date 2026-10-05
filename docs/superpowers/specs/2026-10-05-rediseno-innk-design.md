# El rediseño INNK: que la maqueta se reconozca como su producto

## El problema

`innk_flow` tiene un sistema visual propio y coherente —Tailwind 4 + DaisyUI,
dos temas, tokens derivados— pero no se parece al producto de INNK. El color
primario de la hoja lo dice con todas las letras desde que se escribió:

```css
/* #5b3df5 exacto. Provisorio hasta saber si innk tiene marca propia: es UNA
   línea, y nada más de la hoja lo escribe literal. */
```

Ahora se sabe. El Figma «General Rediseño»
(`3xc9srW7XlOlM9jzZ3lGjC`, página «Vistas aprobadas», 485 frames en 15
secciones) tiene la marca, el cromo y el lenguaje de superficie de INNK.

**El objetivo es que alguien de INNK abra `innk_flow` y lo reconozca como su
producto.** No es fidelidad píxel a píxel: el Figma describe un producto mucho
más grande —módulo de proyectos con Kanban y Gantt, portafolio, gestión de
horas, gamificación, «Mi espacio»— que acá no existe ni está en el backlog. Y
al revés: el taller y la sala de la mesa no están en el Figma.

## Alcance

**Entra:** la paleta en los dos temas, la tipografía, el riel de navegación, la
banda de título, un control de tema, el tratamiento de superficies y la
disposición de los formularios.

**No entra:** ninguna pantalla nueva, y ninguna reestructuración del interior de
las pantallas. El stepper con círculos, el riel de decisión de la evaluación y
el panel lateral de creación —que el Figma sí resolvió— quedan afuera a
propósito: son trabajo de producto, no de marca.

**Lo que NO se adopta del Figma, explícito:** su gris de texto apagado
`#808080` (3,95:1 sobre blanco) y su base tipográfica de 13px. Los dos están
abajo del piso que `[CONTRASTE]` exige. `--muted` se sigue derivando de
`base-content`, que es lo que lo mantiene en regla.

## Lo que hace barato el cambio

Dos hallazgos de la exploración, y el diseño entero se apoya en ellos.

**Todos los tokens propios de la hoja se derivan de los 20 de DaisyUI por
`color-mix`.** `--borde` es `base-300`, `--muted` es 70% de `base-content`,
`--dato` sale de `base-content` sobre `base-100`, `--ok`/`--warn`/`--danger`
son mezclas de sus familias. No hay colores literales repartidos: cambiando los
20, el resto sigue solo.

**La navegación global ya existe.** `.app-nav`, dentro de `.app-header`, con
exactamente las cinco entradas que el riel necesita y las mismas condiciones de
permiso (`manages_challenges?` para Criterios, IA y Miembros), más su lógica de
`is-active`. El riel no es navegación nueva: es mudar la que hay.

## La paleta

El cambio de marca es un corrimiento de **6,7° de tono** a la misma luminosidad
y croma, así que todo lo que cuelga del primario conserva su contraste.

| | hoy | INNK |
|---|---|---|
| `--color-primary` | `oklch(52.249% 0.2549 280.33)` | `oklch(52.015% 0.2475 273.64)` = `#4747F3` |
| blanco encima | 6,12:1 | 6,06:1 |

Los valores son la conversión exacta del hex y el croma máximo que entra al
gamut sRGB, como manda la hoja: lo declarado tiene que ser lo que pinta.

### Tema claro

```
base-100      oklch(100%     0      247.88)   #FFFFFF
base-200      oklch(97.470%  0.0051 247.88)   #F4F7FA   INNK exacto
base-300      oklch(92.400%  0.0080 247.88)   #E2E6EB
base-content  oklch(21.500%  0.0280 247.88)   #0F1B26   17,49:1 sobre la superficie
primary       oklch(52.015%  0.2475 273.64)   #4747F3   INNK exacto,  6,06:1
accent        oklch(48.894%  0.2246 309.04)   #8520BD   INNK exacto,  7,15:1
error         oklch(67.909%  0.1741  30.12)   #F06653   INNK exacto
```

`base-content` conserva su luminosidad y croma de hoy y sólo corre el tono a
247.88, para que el negro del texto pertenezca a la misma familia que el resto.
A ese croma la diferencia es sutil; lo que importa es que de él se derivan
`--muted`, `--tenue` y los dos `--dato`, que es lo que mantiene el gris de la
app en regla sin adoptar el `#808080` de INNK.

### Tema oscuro

Misma estructura de luminosidad que hoy, tonos de INNK. Queda azul marino en
vez del violeta actual, y **no es una invención**: es el fondo que INNK usa en
su propia pantalla de login.

```
base-100      oklch(21.5%  0.028  247.88)   #0F1B26
base-200      oklch(18.2%  0.026  247.88)   #08131D
base-300      oklch(26.4%  0.030  247.88)   #192633
base-content  oklch(92.8%  0.012  247.88)   #E1E8EF   14,17:1 sobre la superficie
primary       oklch(66.5%  0.1780 273.64)   #7387FF   texto oscuro encima, 6,22:1
accent        oklch(70.0%  0.2098 309.04)   #C471FF   6,74:1
error         oklch(66.0%  0.1900  30.12)   #F05845   5,82:1
```

El croma del primario oscuro está clampeado: a L=66,5% y H=273,64 el gamut
sRGB corta en 0,1780, por debajo del 0,2475 del tema claro. Declarar 0,2475
ahí sería declarar algo que el navegador recorta, que es lo que la hoja
prohíbe.

### El acento gana un color propio

Hoy `--color-accent` apunta al primario, con el comentario «no tiene un tercer
color de marca detrás». Ahora lo tiene: el morado `#8520BD` con que el Figma
pinta la pestaña activa. Queda a **35°** del primario, holgado contra los 8°
que en su momento obligaron a correr `--color-secondary` al azul acero para que
«acción» no se confundiera con «lo propuso la máquina». El azul de la IA no se
toca.

### El coral entra exacto, y cuesta dos ajustes

INNK usa `#F06653` con texto blanco a **3,12:1**, que no pasa. Oscurecerlo
hasta 4,5:1 lo convierte en otro color (`#CE1D0D`). La salida es la que la hoja
ya usa para `success` y `warning`: conservar el color y dar vuelta el texto.

- `--color-error-content` pasa a oscuro → **6,32:1**.
- `--danger` es `85% error + 15% base-content` y **se usa como color de
  texto**: con el coral da **4,06:1**. Baja a **75%** → 4,88:1. En el tema
  oscuro el 85% sigue sirviendo (6,12:1).

## La tipografía

Open Sans variable (ejes `wght` y `wdth`; el propio código del Figma trae
`fontVariationSettings: '"wdth" 100'`), auto-hospedada como las actuales: un
`.woff2` del subconjunto latin en `public/fonts` con su OFL. `--font-display` y
`--font-sans` apuntan los dos a ella; se jubilan Bricolage Grotesque e Inter.

El peso **baja**: hoy son 125 KB entre dos archivos; Open Sans variable latin
ronda los 35–40 KB.

Se mantienen **14px** de base y los **22px** de `.page-title`, que es el tamaño
del título en la banda del Figma.

## El shell

El riel de INNK arranca en el borde superior, con el logo a su derecha: ocupa
toda la altura, **incluida la barra**. Así que no es una columna más de
`.app-shell` —eso obligaría a tocar sus cuatro reglas de grilla— sino un
envoltorio nuevo:

```
body
└── .app-frame            grid: 80px | 1fr
    ├── nav.app-rail      el riel, de arriba abajo
    └── div
        ├── header.app-header   (sin .app-nav: se fue al riel)
        └── .app-shell          las cuatro reglas, intactas
```

**Abajo de 1024px el riel se vuelve fila horizontal dentro del header** — el
mismo mecanismo que `.flow-strip` ya usa para el drawer: un markup, un cambio
de dirección en CSS. Los frames de teléfono del Figma (414px) no tienen riel,
así que esto respeta el diseño.

Los cinco iconos se bajan del Figma como SVG.

**El costo en ancho, medido:** el cromo pasa de 552px (232 del drawer + 320 de
referencia) a **632px**. A 1440 el trabajo baja de 888px a **808px**.

### La banda de título

El Figma pinta una banda indigo de ancho completo con el título en blanco,
22px bold. `.page-head` se parte: el `%h1.page-title` sube a la banda, y
breadcrumb, chip de estado y `.page-head__actions` quedan en una fila debajo.
Es la lectura literal del Figma, donde el «← Volver a lista de ideas» va justo
debajo de la banda.

Son ~12 vistas con `.page-head`, y la edición es mecánica.

**Por qué no la alternativa barata:** meter `.page-head` entero adentro de la
banda es una regla de CSS y cero vistas tocadas, pero deja los
`btn btn-primary` de las acciones sobre un fondo indigo —donde desaparecen— y
obliga a inventar una variante clara de botón que el Figma no define.

### El control de tema

Una cookie que lee el servidor.

```haml
%html{ lang: I18n.locale, data: { theme: cookies[:theme].presence } }
```

HAML omite el atributo cuando el valor es `nil`, así que **sin cookie no hay
`data-theme`** y `prefersdark` sigue vivo; con cookie, manda la elección. Un
`PATCH /theme` la escribe y redirige de vuelta.

Esto resuelve de una las dos trampas que tendría un toggle del lado del
cliente: no hay parpadeo del tema equivocado en la primera pintura, y como el
atributo lo pinta el servidor **el morph no lo puede perder** —que es la misma
familia del `<details>` que se cerraba solo—.

**Son tres estados, no dos: Auto · Claro · Oscuro.** El servidor no sabe qué
prefiere el sistema de quien mira, así que un control de dos posiciones obliga
a elegir un default y mata `prefersdark` para todo el que nunca lo toque.
«Auto» **borra** la cookie; no escribe `"flow"`.

De rebote: `make screens` hoy fuerza el tema oscuro emulando el media query;
con la cookie puede pedirlo explícito, que es más determinista.

## Superficies, radios y formularios

### Superficies

INNK no usa bordes: cada tarjeta y cada campo llevan `0 2px 20px
rgba(0,0,0,.1)`. Una sombra negra al 10% **sobre una superficie oscura no
existe**, y el Figma no lo resuelve porque no tiene tema oscuro. El
tratamiento depende entonces del esquema, no de la clase:

```css
--shadow:           light-dark(0 2px 20px rgba(0,0,0,.1), 0 1px 3px rgba(0,0,0,.4));
--borde-superficie: light-dark(transparent, var(--borde));
```

`--shadow` **ya existe y se redefine**, no se agrega un token nuevo: sus cinco
usos son todos superficies —`.card`, `.auth-card` y las tres barras de
acciones pegadas (`.builder__actions`, `.editor-actions`, `.setup-nav`)— así
que la redefinición las alcanza a todas de una y no quedan dos tokens de
sombra conviviendo.

`--borde-superficie` sí es nuevo, y lo consumen **dos** reglas: el `border` de
`.card` (hoy `1px solid var(--borde)`) y el de los campos —el bloque de
`input[type=...], textarea, select`—. Ningún otro borde cambia.

`light-dark()` resuelve contra `color-scheme`, y **los dos temas ya lo
declaran**. Una declaración por token, sin duplicar selectores ni depender de
en qué modo entró el tema.

**A verificar en implementación:** soporte de `light-dark()` en el Chromium que
usa `make screens`. Plan B si falta: declarar los dos tokens dentro de cada
bloque `@plugin "daisyui/theme"`.

`--borde` **no se toca**: lo usan los divisores, las celdas de tabla y los
`border-top` de `.config-advanced` y `.field-list__item`. Lo que cambia es sólo
el borde de la tarjeta y del campo.

### Radios

```
--radius-box:    0.8125rem (13px)  →  1rem      (16px)   tarjetas
--radius-field:  0.5625rem  (9px)  →  0.625rem  (10px)   campos y botones
```

Los dos siguen saliendo del mismo token, así que el comentario que los ata
—«un campo de 8px al lado de un botón de 9px se ve como un error de
alineación»— se sostiene.

### Formularios

Hoy `label` es global: `display: block; margin-bottom: 5px; font-size: 12px;
font-weight: 600; color: var(--muted)`. INNK la usa a la derecha de su columna,
13px, bold, en el color del texto.

La forma robusta no es una grilla de dos columnas a secas —un `.field` con tres
hijos se desarmaría— sino fijar la columna por hijo:

```css
.field {
  display: grid;
  grid-template-columns: minmax(120px, 190px) minmax(0, 1fr);
  column-gap: 16px;
  align-items: start;
}
.field > label        { grid-column: 1; text-align: right; margin: 0;
                        font-size: 13px; color: var(--text); }
.field > :not(label)  { grid-column: 2; }
```

Un `.field` con label + input + hint + lo que sea apila todo en la columna 2.
Cubre las **154 ocurrencias en 43 vistas** sin tocar un HAML.

Tres excepciones:

1. **Dentro de `.app-aside`** (320px) no entran dos columnas: ahí `.field`
   sigue apilado. Se scopea igual que el `.app-aside .card { --card-p: 16px }`
   que ya existe.
2. **Abajo de 1024px** vuelve a apilarse, como en los frames de 414px del
   Figma.
3. **Las islas Vue** no usan `.field`; sus formularios quedan como están, que
   es coherente con lo que midió el plan 2c.

`.field-check` no se ve afectado: es un `label` con `display: flex` propio y
vive suelto, no dentro de un `.field`.

## Verificación

### Guardas que van a fallar, y está bien

- **`[CONTRASTE]` y el muestrario.** `badge-soft`/`alert-soft` pintan con el
  color puro del tema, y cambian `error` y el tono del primario. Uno ya está
  medido: `--danger` baja de 85% a 75%. El resto se mide al implementar.
- **`reglas_sin_elemento_spec.rb`.** Al mudar la nav, `.app-nav` y
  `.app-nav__link` quedan sin elemento; igual los dos `@font-face` que se
  jubilan. La respuesta es borrar las reglas, no excepcionarlas.
- **`[PUNTOS]` y `[ESTADO-DRAWER]`** piden re-medición: `--punto--acento` es el
  primario y el panel del drawer es `--color-neutral`, que también cambia de
  tono.

`[CLASES]`, `[RELLENO]`, `[RITMO]` y `[PANEL]` no se tocan: la tarjeta conserva
fondo y relleno. `clases_interpoladas_spec.rb` obliga a que el estado activo
del riel se escriba literal.

### Dos agujeros encontrados mirando

**La nav no tiene un solo test.** `.app-nav` aparece únicamente en el layout:
ni un spec la nombra. Hoy se puede romper qué ve cada rol en la navegación
global y `make spec` queda en verde.

**La sombra pasa a ser portante y nadie la mide.** `CLAUDE.md` ya lo dice: «una
`card` puede perder la letra de 14px o la sombra y las 74 capturas seguir en
verde». Hoy eso es cosmético porque el borde define la tarjeta; después de este
cambio, en tema claro la sombra es lo único que la define.

### Las cuatro guardas nuevas

**`[SOMBRA]`** — toda `.card` tiene `box-shadow` distinto de `none` en tema
claro. Cuenta cuántas midió y falla si midió de menos, como `[RELLENO]` y
`[PASTILLA]`.

**`[TEMA]`** — prueba la trampa documentada en tres casos:

| cookie | sistema | tema que tiene que quedar |
|---|---|---|
| ausente | oscuro | `flow-oscuro` |
| `flow` | oscuro | claro |
| borrada de nuevo | oscuro | `flow-oscuro` |

El tercer caso existe porque «Auto» tiene que borrar la cookie. Si en vez de
borrarla escribe `"flow"`, `prefersdark` queda muerto para siempre y nadie se
entera.

**`[RIEL]`** — el riel existe, marca el activo, y abajo de 1024px se vuelve
horizontal **sin desaparecer**. Un riel que se esfuma a 1100px deja la app sin
navegación global, y ninguna captura mira hoy ese ancho salvo `[REFERENCIA]`.

**`[BANDA]`** — la banda se dibuja y su texto pasa 4,5:1 sobre el primario.
Hoy da 6,06:1; la guarda es lo que lo mantiene si el primario se vuelve a
tocar.

### Specs de Ruby

- **`spec/requests/navegacion_global_spec.rb`** — qué entradas ve cada rol. Se
  escribe **antes** de mover nada, contra la nav actual, para que el refactor
  tenga red en vez de estrenarla ya movido.
- **`spec/requests/theme_spec.rb`** — el `PATCH /theme` escribe la cookie,
  «Auto» la borra, y vuelve a donde estabas.

**Seguridad:** el valor de la cookie se renderiza dentro de un atributo del
`<html>`. HAML escapa, así que no hay inyección, pero igual se valida contra
una lista blanca (`%w[flow flow-oscuro]`) y cualquier otro valor se trata como
ausente. Una cookie es entrada del usuario; que hoy no se pueda explotar no es
razón para aceptar un valor arbitrario.

### Lo que queda sin vigilancia

Para que nadie lo dé por cubierto:

- **`--card-fs`** (la letra de 14px de la tarjeta) sigue sin medirse.
  `[SOMBRA]` cubre un tercio de lo que medía el viejo `[CARD]` y `[RELLENO]`
  otro; este tercio queda afuera.
- **`[REFERENCIA]` sigue sin medir la sala de la mesa**, igual que antes. Este
  trabajo no lo arregla.
- **El riel a 414px** no lo mira ninguna captura: el recorrido no fotografía
  anchos de teléfono.

### La regla de mutación

Cada guarda nueva se prueba rompiéndola a propósito, con la corrida limpia en
verde primero —una mutación sólo discrimina si el baseline pasa— y restaurando
con `cp` desde un backup, nunca con `git checkout`, que desharía el arreglo en
vez de la mutación.

Y el orden obligatorio: tocar `app/javascript/` o agregar utilidades de
Tailwind → **`make yarn-build` ANTES de `make screens`**. Un cambio de tokens
sin compilar deja a `make screens` validando la hoja anterior, en verde.

## Riesgos

- **`light-dark()`** puede no estar en el Chromium del recorrido. Plan B
  declarado arriba.
- **El ancho del trabajo baja a 808px** a 1440. Las pantallas más apretadas
  —la tabla de ranking de selección, que ya no entra en el centro angosto— hay
  que mirarlas con el riel puesto.
- **`.page-head` en ~12 vistas** es edición mecánica pero repetida: es donde
  más fácil se cuela una vista olvidada. `[BANDA]` la caza si la banda no se
  dibuja.
- **`[CONTRASTE]` va a fallar de entrada** y hay que distinguir el rojo
  esperado del nuevo. Conviene cambiar la paleta en un commit propio y medir
  ahí, antes de tocar el shell.
