# El frontend

**Casi todo es server-rendered.** Rails + HAML + Turbo 8, con Vue sólo donde el
estado es del cliente. No hay SPA, no hay router, no hay store.

Y la consecuencia que hay que internalizar antes de tocar nada: **un bug de
Vue, de Turbo o de CSS no lo atrapa ningún spec de Ruby.** Un
`__VUE_OPTIONS_API__` mal puesto dejó el builder en blanco con la suite entera
en verde. La verificación de esta capa es `make screens`, y la última sección de
este documento dice exactamente qué ve y qué no.

## Lo primero: la hoja y el bundle viven SÓLO en el contenedor

`app/assets/builds/*` está **gitignoreado entero**. Ahí viven la hoja compilada
(`application-build.css`, que produce `yarn build:css`) y el bundle
(`application-build.js`, que arma esbuild con `yarn build`).

**Tocaste `app/javascript/` o agregaste utilidades de Tailwind →
`make yarn-build` ANTES de `make screens`.**

Si no, la app sirve lo anterior y **la verificación valida en verde una pantalla
distinta de la que escribiste**. Pasó dos veces en la misma sesión:

- Una tarjeta con cuatro clases de Tailwind nuevas sobrevivió **seis** corridas
  verdes sin que ninguna de las cuatro existiera en la hoja: el QR salía sin
  ancho, sin fondo blanco, sin relleno y sin bordes.
- Un `.js` nuevo importado desde `application.js` no existía para el navegador:
  la suite daba 1.558 ejemplos en verde, el bundle no tenía **una sola
  referencia** al archivo, y la lista en vivo no se refrescaba.

## Turbo 8: las pantallas se actualizan, no se recargan

El layout declara `turbo-refresh-method: morph`. Turbo 8 trata como *page
refresh* **cualquier POST que redirija a la misma URL** —que es lo que hace casi
todo acá, empezando por los pedidos a la IA— y con esa meta **morfea el DOM** en
vez de repintar la página.

No hace falta `data-turbo-action` en los formularios: Turbo ya elige `replace`
solo cuando el redirect vuelve a donde estabas.

### Las cinco cosas que el morph rompe

**1. `turbo-refresh-scroll: preserve` NO conserva el scroll.** Sólo le dice a
Turbo que no scrollee él. El scroll se pierde *durante* el morph: mientras
idiomorph tiene nodos afuera la página se acorta y el navegador recorta
`scrollY`. Lo devuelve el bloque de `app/javascript/application.js`, que lo
guarda en `turbo:before-render` y lo repone en `turbo:render` **sólo si hubo
`turbo:morph`**.

**2. Después de un POST, Turbo NO cachea la página**
(`shouldCacheSnapshot = formSubmission.isSafe`), así que `turbo:before-cache`
**no se dispara** y no sirve para desmontar nada en el camino que importa. Por
eso `islands.js` también escucha `turbo:before-render`.

**3. Un `<dialog>` abierto no puede existir durante un morph.** Idiomorph compara
contra el HTML del servidor, y un diálogo que agregó el cliente es un nodo de
más: se lo lleva puesto, o le saca el `open` y lo deja en el DOM sin verse.

Por eso **los dos popups de la IA los arma el JS y ninguno existe durante un
render** (`ia_popups.js`): la espera se cierra y se saca en
`turbo:before-frame-render`, `turbo:before-render` y `turbo:submit-end` (este
último sólo si no hubo éxito), y la de respuesta se arma recién **después** de
pintar, en `turbo:frame-render`, `turbo:render` y `turbo:load` —el primero es el
más frecuente, porque el modo asistido responde al marco—.

**4. Un `<details>` abierto se cerraría.** El `open` lo pone el cliente, y el
morph compara contra el HTML del servidor, que no lo trae: guardar algo adentro
de un plegable lo cerraba.

`application.js` cancela en `turbo:before-morph-attribute` la **REMOCIÓN** de
`open` en un `DETAILS` (un `open` que agrega el servidor sigue entrando). **Por
eso todo lo plegable de la app es un `<details>`: un mecanismo, un gancho.**

**5. El morph le devuelve al campo enfocado el valor del servidor.** Turbo 8
llama a `morphElements` **sin `ignoreActiveValue`**, así que `syncInputValue`
pisa lo que estás tecleando. De ahí dos consecuencias documentadas:

- Un envío rechazado del borrador de la mesa pierde lo tecleado desde la última
  pausa de dos segundos: cuando el cliente se entera, el valor del DOM ya se fue.
- **No se puede poner un poller de página completa** en la sala, porque le
  pisaría a la mesa lo que está escribiendo. Es la razón dura por la que la
  tarjeta de grabaciones no se refresca sola.

**Lo que el morph NO rompe son las islas:** reemplaza el contenedor entero y
`turbo:load` vuelve a montar con las props nuevas. Está medido en la cara de
configuración de Idear, sin gastar una llamada al proveedor
(`revisarMorphing` en `script/capture_screens.js`).

### Un caso aparte: los tres botones de tema llevan `turbo: false`

```haml
form: { data: { turbo: false } }
```

Parece prolijidad y **es lo único que hace andar el control adentro de la app, así
que no lo «limpies»**.

El login no carga Turbo, así que ahí el POST es una recarga entera y el atributo
se aplica solo. En la app, en cambio, Turbo morfea el `<body>` y del `<html>`
sólo sincroniza `lang` y `dir`, así que el `data-theme` **se quedaría con el
valor viejo**: el botón se ilumina, porque está en el body, y los colores no se
mueven hasta recargar.

Con `turbo: false` el PATCH es una recarga completa y **el servidor sigue siendo
quien escribe el atributo**, sin parpadeo.

Si se pierde, la guarda `[TEMA]` es lo único que se entera. Los specs de request
no pueden: piden el atributo en el HTML servido, o sea **la causa**, y lo que se
rompe es el **efecto** en el navegador.

## Las cuatro islas Vue

| Isla | Qué edita | Guarda |
|---|---|---|
| `pipeline_builder` | Kind, orden, alta y baja de módulos | `PUT` de la lista completa |
| `form_editor` | Los campos del formulario de postulación | `PUT` de la lista completa |
| `criteria_editor` | Los criterios de un set | `PUT` de la lista completa |
| `step_settings` | Los ajustes de un módulo | **Ninguna propia** |

Se montan con `app/javascript/islands.js`, que cubre `DOMContentLoaded`,
`turbo:load` y el script que llega tarde, y desmonta en `turbo:before-cache`.
Las islas exponen **`data-island-mounted="true"`** como señal determinista, que
es lo que la verificación mira.

### Las props las serializa el SERVER

`PipelinePresenter`, `CriteriaSetPresenter`, `StepSettingsPresenter`, y viajan
en un `data-props`. Una vuelta de red menos, y **la tenencia la garantiza el
scope de Ruby, no una ruta JSON que alguien podría olvidar scopear**.

### Las props son el estado INICIAL, no el estado

Vue **no hace reactivas las props de la raíz**: mutarlas cambia los datos y **no
redibuja nada**. Copiá a `data()` una vez y trabajá sobre la copia.

El builder mutaba sus props (`steps.push`, `steps.splice`) y por eso agregar,
quitar y reordenar módulos **no se veían** — y el segundo clic en una tarjeta
fantasma reventaba con «Cannot read properties of undefined».

### Un solo camino de escritura

Las tres primeras guardan la **lista completa** contra su API (`PUT`), y el
server reconcilia. **No agregues un segundo camino de escritura** (nested
attributes, endpoints por fila): la pantalla de criterios los tenía y se sacó.

`step-settings` es la excepción: **no tiene guardado propio**. Renderiza sus
campos DENTRO del `form_with` de Rails de `steps/config/_modulo` y viaja en el
mismo PATCH que el nombre y el modo de IA — un solo botón, un solo endpoint.

### El builder es dueño del ARMADO, no de la configuración

Manda `kind`, orden, alta y baja; **no** manda `settings`, `criteria_set_id` ni
`source_step_id`. Si los mandara, guardar el flujo con props cargadas antes
**revertiría lo configurado**, y `lock_version` no lo ataja: es del desafío, y un
PATCH al módulo no lo incrementa.

El payload del PUT es literalmente **`{ id, kind }` por módulo**, y
`create_added` lee sólo `kind`. `update_existing` **no existe** — de un módulo
que ya existe no se escribe ningún atributo.

**Y tampoco manda para el otro lado.** `PipelinePresenter` publica sólo lo que la
tarjeta dibuja. Cuando la configuración se mudó a la pantalla del módulo
quedaron **6,4 KB de 10,4 KB** de props que ningún `.vue` leía, y no era sólo
peso: el resumen de criterios corría una consulta por módulo que puntúa, y el
del formulario cargaba `form_fields.ordered` en **cada** render del builder.
Además `createApp(component, props)` convierte toda prop no declarada en atributo
del elemento raíz, así que **lo que sobra se serializa al DOM**.

**Antes de sumar una clave, buscá quién la lee.**

> **Trampa:** cuidado con `.compact` sobre el hash de un step en el presenter: se
> lleva puesto `aiMode: nil`, que significa «heredá el modo del desafío» y no es
> lo mismo que la clave ausente.

## Los cuatro módulos JS planos

| Archivo | Qué hace |
|---|---|
| `islands.js` | Monta y desmonta las islas |
| `ia_popups.js` | Los dos diálogos de la IA, armados por JS y nunca presentes durante un render |
| `arrival_live.js` | Refresca sola la mesa de llegada. **Para** en `turbo:before-render` |
| `workshop_draft.js` | El autoguardado del borrador. **Descarga** en `turbo:before-render` |
| `workshop_recording.js` | La grabación. **NO para ni descarga ahí**, y es a propósito |

**`workshop_recording.js` es la excepción deliberada**, al revés de sus dos
hermanos: `turbo:before-render` dispara también en un morph, y un morph ocurre
con cualquier POST a la misma URL — alguien apretando «Crear borrador»
**cortaría la reunión**. Lo que lo permite es que el `MediaRecorder` y los trozos
son variables de **módulo**. Si alguien «arregla» el archivo copiando a los
hermanos, se cortan grabaciones y **ninguna suite se entera**. Ver
[`taller.md`](taller.md).

Y un detalle que vale para cualquier JS nuevo: **`workshop_recording.js` no
tiene ningún manejo de `prefers-reduced-motion`, y no agregarlo es deliberado.**
La onda del micrófono quieta se lee como un micrófono tapado, que es justo el
estado que tiene que poder distinguir. No es una decisión implementada con una
guarda: es la **ausencia** de una, y quien la «arregle» agregándola la rompe.
(El spinner de la IA sigue girando por lo mismo, y eso sí está registrado en la
hoja.)

## El CSS: Tailwind 4 + DaisyUI 5

La configuración vive **en el CSS** —Tailwind 4 es config-por-CSS, no hay
`tailwind.config.js`—. `app/assets/stylesheets/application.css` abre con:

```css
@import "tailwindcss";
@plugin "daisyui";
@plugin "daisyui/theme" { name: "flow"; ... }
@plugin "daisyui/theme" { name: "flow-oscuro"; prefersdark: true; ... }
@source "../../views"; @source "../../helpers"; @source "../../javascript";
```

La compila el **CLI de Tailwind** (`yarn build:css`), no esbuild, que ya sólo ve
JavaScript. Sass se jubiló entero. El archivo de salida conserva el nombre, así
que el `stylesheet_link_tag` del layout nunca cambió.

### Las tres capas, y de quién es cada regla

1. **Componentes de DaisyUI** donde existan.
2. **Clases propias con nombre semántico** para el vocabulario que es de esta app
   y se repite: `.flow-strip`, `.step-card`, `.empty-state`.
3. **Utilidades sueltas** sólo para lo irrepetible.

**Si una clase aparece en más de dos vistas, es un componente, no doce
utilidades.**

### La capa decide quién gana, y no es la especificidad

Las clases propias de la app van **sin capa**, y una regla sin capa le gana a
cualquier `@layer` —o sea a **todo** Tailwind y **todo** DaisyUI—: es lo que
sostiene las 1.939 líneas heredadas sin tener que tocarlas.

El precio es que **un selector genérico sin capa pisa un componente**:
`a { color: … }` suelto le ganaba al `.btn` de DaisyUI y dejaba un
`<a class="btn btn-primary">` con el texto del color del fondo.

Los defaults del navegador que el Preflight borra —y ese color de enlace— van en
`@layer base`, desde donde le ganan al Preflight, pierden contra el componente y
pierden contra las utilidades. Si estuvieran sin capa, un `<p class="m-0">`
saldría con el default y **la utilidad parecería no haber compilado**.

### Tailwind escanea TEXTO: una clase interpolada no existe

`app/helpers/estilos_helper.rb` traduce estado del dominio → clase y devuelve
siempre el nombre **completo**, escrito literal.

**Nunca `"badge-#{x}"`:** esa clase no llega a la hoja, el elemento queda sin
ninguna regla detrás, y **en el DOM se ve perfecto mientras en pantalla no se ve
nada**. De rebote, la traducción estado → estilo queda en un solo lugar.

La guarda es `spec/lint/clases_interpoladas_spec.rb` y mira **HAML, `.vue` y
`.js`**: las islas son fuente de Tailwind igual que las vistas, y un `.js` plano
como `ia_popups.js` arma sus diálogos con el mismo template literal que una isla.

En una isla **el nombre lo manda el presenter** en las props, y el componente
sólo lo liga.

Cada mapeo se prueba **contra su enum**, preguntando si cada estado es clave del
hash (`spec/helpers/estilos_helper_spec.rb`). Antes se comparaba el sufijo de la
clase con `end_with`; con `badge` varios estados comparten la misma clase y el
sufijo dejó de decir qué estado la pidió.

**Un mapeo escrito como ternario en la vista queda afuera de ese spec.** El
estado de una propuesta de la mesa vivía así, de modo que un cuarto estado se
habría pintado con la rama de «descartada» —ámbar, o sea «mirá esta fila»— y con
el texto de traducción faltante al lado, **sin que nada se pusiera rojo**. Hoy es
`CHIP_DE_PROPUESTA` + `chip_de_propuesta`, con su caso en el spec.

### El tema: `data-theme` va en el `<html>`, pero SÓLO si hay cookie

El tema oscuro es `@plugin "daisyui/theme" { name: "flow-oscuro"; prefersdark:
true; }`, y `prefersdark` engancha
`@media (prefers-color-scheme: dark) { :root:not([data-theme]) }`.

**Con el atributo presente —aunque sea con el nombre del tema claro— ese
selector no matchea NUNCA y el modo oscuro automático queda muerto.**

Lo que sostiene la elección a mano es que el atributo **se omite** cuando no hay
elección: `tema_elegido` devuelve `nil` sin cookie y HAML omite un atributo
`nil`. De ahí las dos cosas que es fácil escribir al revés:

- **«Auto» BORRA la cookie** en vez de escribir `"flow"`. Escribirla dejaría
  pasar los dos casos obvios —«elegir oscuro funciona» y «elegir claro
  funciona»— y **mataría el automático en silencio**.
- **Lo escribe el servidor y no el cliente**, así no hay parpadeo en la primera
  pintura y el morph no se lo lleva.

### Son DOS layouts, no uno

`auth.html.haml` tiene su propio `%html` y **no pasa** por
`application.html.haml`: lo usan el login y el check-in público.

**Todo lo que se agregue al `<html>` o al `<head>` va en los dos** —el
`data-theme` está escrito dos veces por eso, y el control de tema se renderiza en
los dos—. Y el login es donde más se nota, porque es lo único que ve quien
todavía no entró.

### Lo que más fácil se rompe en la hoja

**`light-dark()` es una función de COLOR, y cuando se la usa mal falla hacia
`none`.** Una custom property acepta cualquier flujo de tokens, así que
`--shadow: light-dark(0 2px 20px …, 0 1px 3px …)` declara sin un solo error; lo
que revienta es la **sustitución**: `box-shadow: var(--shadow)` queda inválida al
computar y cae en **`none` en los DOS temas**. El token de color de al lado
—`light-dark(transparent, var(--borde))`— **sí** anda, porque ése es un color, y
es justo lo que hace al error difícil de ver.

> **La moraleja vale más que el bug:** el paso de verificación del plan probaba
> `background: light-dark(#fff, #000)`, o sea el caso de color. **Una guarda que
> mide una forma distinta de la que gobierna no es que no ayude — da permiso.**

**El token del color de borde es `--borde`, no `--border`.** DaisyUI usa
`--border` para el **ancho** (`border-width: var(--border)`): con el nombre en
inglés el color se colaba ahí, el ancho quedaba inválido y **todos los botones
salían con los 3px del `medium` por default**. No se ve leyendo el CSS; se ve
midiendo.

**Las mezclas van `in oklab`, nunca `in oklch`.** En oklch el tono interpola por
el arco corto: mezclar el ámbar (82°) con el texto (286°) da la vuelta por el
rojo y el «amarillo oscuro» sale marrón anaranjado.

**Un color con alfa se compone sobre su fondo antes de medir su contraste.** Si
el fondo también es translúcido, se compone la cadena hasta el primer opaco.

**Un tema propio emite SÓLO lo que declara**: no hereda nada de los que trae la
librería. Los 20 colores y los tres escalares van completos **en los dos** temas
— sin `--depth`, el `color-mix()` del borde de `.btn` queda inválido y
`border-color` cae en `currentColor`.

**`badge-soft` y `alert-soft` pintan el texto con el color PURO del tema.** La
hoja tuvo que oscurecer `success`, `warning` y `error` para el texto de un chip
(`--ok`, `--warn`, `--danger`), y las variantes suaves no usan esos tokens: en
tema claro las tres variantes de aviso y de chip quedaban entre 2,3 y 4,2:1.

**Atenuar un contenedor con `opacity` baja el contraste de todo lo de adentro**,
chips incluidos: un comentario atendido a `.72` los dejaba en 3:1. Que pese menos
—sin superficie, contorno punteado, texto en gris—, **no que se lea peor**.

**`alert` es `display: grid` con `grid-auto-flow: column`.** Un aviso con varios
hijos —un `%strong` y un texto— los reparte en columnas. **Envolvé el contenido
en un solo `%div`.**

**Renombrar una clase deja muertas en silencio las reglas que la usaban desde
AFUERA de su bloque.** Al pasar los chips a `badge`, `.flow-drawer .status-chip`
y `.feedback-item:has(.feedback-kind--issue)` dejaron de aplicar, y **ni
`make spec` ni `make screens` lo notaron**: el elemento seguía teniendo reglas,
sólo que otras. Antes de renombrar, buscá la clase en selectores compuestos,
descendientes y `:has()`, **y en los localizadores de
`script/capture_screens.js`**.

### La superficie se define con una SOMBRA, no con un borde

`--shadow` tiene **seis** consumidores: `.card`, `.auth-card`,
`.builder__actions`, `.editor-actions`, `.setup-nav` y el bloque de campos
(`input`, `textarea`, `select`). Ese censo es lo que justifica redefinir el token
compartido en vez de agregar uno nuevo: **quien lo retoque mueve cada campo de la
app junto con las cinco superficies.**

`--borde-superficie` alimenta **sólo** a `.card`: `transparent` en claro,
`--borde` en oscuro. Por eso en tema claro **la sombra es lo único que define la
tarjeta**, y por eso dejó de ser decorativa.

**`--borde-campo` es nuevo, y es el único lugar donde la app se aparta del diseño
de INNK a propósito.** El Figma no le dibuja borde al campo: sólo sombra. Medido,
el contorno en reposo de un campo sin borde contra su tarjeta daba
**1,09–1,12:1** —su fondo es el MISMO token que el de la tarjeta, los dos blanco
puro—. El 1.4.11 de WCAG pide 3:1 para el límite de un control. Así que el campo
conserva un hilo: `--borde-campo` es `--tenue` (**3,36:1** medido) en claro y
`--borde` en oscuro. De paso arregló algo que ya estaba mal: ese borde medía
**1,25:1 ANTES**.

**`--color-accent` está declarado y NO pinta un pixel.** Es el morado `#8520BD`
de INNK y es lo que el Figma usa para la pestaña activa, pero **nada lo lee**: no
hay un `btn-accent`, `badge-accent`, `alert-accent`, `text-accent` ni
`bg-accent` en toda la app. Lo que pinta es el `--accent` de la app, que sigue
siendo el índigo en 35 usos directos más 16 de su escalera. Está declarado
porque un tema propio emite sólo lo que declara; **borrarlo rompe el tema**.
**Adoptar el morado es una decisión abierta que nadie tomó**, no un pendiente:
repuntar `--accent` repinta el producto entero.

**Deuda medida y deliberadamente no arreglada:** en tema OSCURO el campo mide
**1,13:1** contra su ancestro. Ese borde es `--borde`, el mismo que tenía antes
del rediseño, y **no es una regresión** —la paleta nueva le corrió el tono a la
misma luminosidad y croma: +0,0025 a favor—.

### `card` + `card-body`, y `.panel` ya no existe

`card` de DaisyUI está **habilitada**, y el aspecto lo pone la hoja: una regla
`.card` le da superficie, borde, radio y sombra, y fija `--card-p` y `--card-fs`.
**En las vistas se escribe `.card` > `.card-body` y nada más.**

Estuvo excluida porque declara `display: flex`, y habilitarla convertía de golpe
todas las tarjetas en columnas flex; por eso las tarjetas se llamaron `.panel`
hasta que cada pantalla pasó a `card`. **Ya no queda ninguna: la regla se borró
de la hoja.**

**Dos grillas con el mismo aspecto y mecánica distinta.** En `challenges/index`
las tarjetas son `.challenge-card`, que declara `display: block` **sin capa** —y
una regla sin capa le gana al `display: flex` de DaisyUI, que vive en un
`@layer`—: el `<a>` nunca es contenedor flex. En `criteria_sets/index` son
`.card` a secas: ahí sí es flex, el sobrante se reparte ADENTRO y el botón queda
pegado abajo. Se ven igual; el motivo no es el mismo.

### El ritmo lo pone `.app-main`

Es `flex` en columna con `gap`. **Las tarjetas tienen `margin: 0` a propósito**:
un margen por tarjeta rompería las grillas, donde son hermanas con su propio
`gap`. Antes no había ninguno de los dos y las tarjetas **se tocaban** — la
página era una columna blanca continua partida por hairlines. No se ve mirando
(el borde doble parece una separación): se ve midiendo.

Tres cosas más de jerarquía:

- **`.section-title` es un encabezado, no una etiqueta.** Era 13px en mayúsculas
  y gris, o sea estilo de etiqueta usado en 54 lugares como título de sección:
  **nada anunciaba nada.**
- **`--muted` se usa 178 veces**, así que casi todo el texto de la app es gris.
  Subir el contraste del token una vez lo levanta en todos lados; es más barato y
  más parejo que discutir usos.
- **El acento es de las ACCIONES.** Los gráficos van con `--dato` /
  `--dato-fuerte`, una rampa sacada del propio texto: pintar una barra con el
  violeta del botón de al lado la hace **leer como un control**.

Y un detalle con nombre propio: un `turbo-frame` que siempre se renderiza pero
casi siempre está vacío —el de sugerencias de IA— necesita `display: contents`,
o como hijo flex se lleva dos gaps y **abre un hueco de la nada**.

## El layout: dos grillas anidadas

```
.app-frame                              la de afuera, dos columnas
├── riel de navegación global (80px)    arranca arriba de todo, abarca la barra
└── todo lo demás
    ├── barra oscura (bg-neutral)       oscura en los DOS temas: es el shell
    └── .app-shell                      la de adentro, tres regiones
        ├── flujo del desafío (232px)   el drawer
        ├── trabajo                     el centro
        └── referencia (320px)          la columna derecha
```

**Las dos laterales de `.app-shell` son opcionales y la grilla se acomoda sola
con `:has()`**, así que ninguna pantalla declara su layout.

El riel sólo se dibuja con sesión **Y** empresa elegida
(`.app-frame--con-riel`): sin eso no hay a dónde navegar y una columna de 80px
vacía se lee como un error. **Abajo de 1024px vuelve a una sola columna y el riel
pasa a ser una fila horizontal arriba del contenido — no se esconde**, que es lo
que la guarda `[RIEL]` existe para cuidar.

### La regla de qué va dónde

**El centro es lo que se hace; la derecha es lo que se consulta y no se edita**
en el curso normal del trabajo.

En la cara de ejecución de un módulo hay una **tercera** zona: «Ajustes del
módulo», una tarjeta plegada al final del centro (`steps/_ajustes`) con lo que se
edita pero casi nunca —nombre, modo de IA, quién participa—.

**La referencia va en orden FIJO:** progreso, lo propio del módulo, quién
participa, configuración congelada. Reportería lo tuvo al revés hasta que hubo
guarda.

**Lo que se lee a la derecha y se edita abajo aparece dos veces a propósito, con
la MISMA guarda en los dos lugares.** Las dos cosas las prueba
`spec/requests/pantalla_del_modulo_spec.rb`: los bloques por rol, y el orden con
la secuencia de títulos de cada pantalla. **Un título que esa lista no conoce
vuelve marcado con `¿?` en vez de desaparecer**, así que sumar una tarjeta a la
columna obliga a decir dónde va.

**Selección es la única cara de ejecución sin referencia**: su tabla de ranking
no entra en el centro angosto. Los ajustes plegados sí los tiene, y
`make screens` lo espera así (`MODULOS_SOLO_AJUSTES`).

### La referencia tiene que entrar en una pantalla

Pegada y con `max-height: 100vh`, lo que no entra queda tapado detrás de su
propio scroll. **Por eso la densidad la decide la zona**: adentro de `.app-aside`
una `.field-list` va sin recuadro por ítem, con una línea por fila.

Debajo de 1280px, donde sube arriba del trabajo, las tarjetas van en **UNA fila
que se desliza de costado** (tope de 320px por tarjeta): en varias filas
empujaban el título del módulo afuera de la primera pantalla.

### El drawer

**No es el componente `drawer` de DaisyUI**: es un `menu` dentro de una región
de la grilla. El `drawer` pide un checkbox, dos labels y envolver el contenido
entero. Abajo de 1024px el flujo pasa a ser una tira horizontal arriba del
contenido, **sin una línea de JS** y sin que haya que abrir nada.

Aparece sólo si hay un desafío **guardado** en contexto
(`ShellHelper#desafio_del_shell`). Dos guardas que parecen de más y no lo son:

- `/challenges/new` deja un `Challenge.new` sin slug, y el `challenge_path` del
  drawer **reventaba la pantalla entera**.
- Sin tenant devuelve `nil`, porque un 404 se renderiza **después** del
  `Current.reset` y la consulta de los módulos moriría con `MissingTenant`.

**El drawer tiene dos caras:** en borrador es el camino de configurar (con el ✓ y
la pista de cada paso, y el «N de M» al lado del estado) y arrancado vuelve a ser
el mapa de lo que corre, con el chip de estado de ejecución.

### El paso a paso: sus pasos son los MÓDULOS del flujo

No una lista fija: el desafío, el flujo, **un paso por cada módulo** —con su
nombre, en el orden del flujo, identificado por el id del módulo— y «Revisar y
arrancar». Es la misma lista que dibuja el drawer, que es de dónde salió el
cambio: eran dos listas de cosas distintas y había que traducir de una a la otra.

**Dónde estoy lo decide `ShellHelper#paso_actual_del_setup`, y sólo él.** Antes
cada pantalla escribía su clave a mano, y con cuatro claves fijas para las cinco
pantallas de módulo era imposible de acertar.

**Y una advertencia operativa:** `setup_nav` es lo **ÚNICO** que avanza el paso a
paso. Sin su render en una pantalla, ahí se corta el recorrido — y el paso sigue
apareciendo en el drawer igual, **así que no se nota mirando**. Pasó de verdad, y
`make spec` y `make screens` **quedaron en verde igual**. Quien borre o mude una
pantalla de configuración tiene que revisar `Flow::Setup` y los renders de
`setup_nav` **a mano**.

## El formulario: la etiqueta a la izquierda

`.field` es una grilla de dos columnas —`minmax(120px, 190px)` para la etiqueta,
el resto para el control—, que es como lo dibuja INNK.

La columna se fija **por hijo** (`.field > label` a la 1,
`.field > :not(label)` a la 2) y **no** con una grilla de dos columnas a secas:
un `.field` con etiqueta, control y `.field-hint` mandaría el hint a la columna
de la etiqueta.

El alcance medido son **29 `.field` en 12 vistas HAML**, más 3 en las islas.

**Cinco excepciones:**

| Excepción | Por qué |
|---|---|
| `label.field-check` | `config_field.vue` la pone como **hermana** de la etiqueta del campo, no como su rótulo: sin la excepción las dos se apilan en la columna de 190px y la 2 queda vacía. **No aparece en ningún HAML — es sólo de Vue** |
| `fieldset.field { display: block }` | `step_tests/new.html.haml` es el único `fieldset.field` del repo, y en grilla los `.field` de adentro caían en la columna 2 del agrupador |
| `.app-aside` | Dos columnas no entran en los 320px de la referencia |
| Abajo de 1024px | Apilado, como lo dibujan los frames de teléfono del diseño |
| `.auth-card` | Mide 380px; entre la columna de la etiqueta y el gap al control le sobraban ~110px, y el hint de la clave caía en seis líneas al lado de un canal vacío. Va por `.auth-card` y **no** por `.auth-form`, porque el formulario del check-in no tiene esa clase |

## Las fuentes se auto-hospedan

**Open Sans, UNA familia donde había dos.** Vive en `public/fonts` y la declara
la hoja con `@font-face`.

**No entra por Google Fonts**: una hoja de un tercero bloquea el render y,
medido, **con la petición colgada `DOMContentLoaded` no llega nunca y la pantalla
queda en blanco** —abortada rendía bien; colgada, no, y `preconnect` no ayuda
contra un agujero negro—.

Es un archivo **variable** del subconjunto latin: un solo `@font-face` con
`font-weight: 300 800` cubre todos los pesos. Pesa **48.320 B** contra los
125.144 B de lo que reemplaza —un 61% menos—, con `font-display: swap` y la pila
de respaldo intacta. La licencia OFL acompaña al archivo.

`--font-display` y `--font-sans` apuntan **las dos** a Open Sans; la primera se
conserva como token nada más que por si alguna vez vuelve a entrar una display.

**El PDF de reportería es la excepción y NO cuelga de los tokens:** lo arma
wkhtmltopdf sin la hoja de la app y sin nadie que resuelva `var()`, así que
`layouts/pdf.html.haml` lleva los cinco colores como **literales** y la fuente
del sistema. Si el tema cambia, **ese archivo se actualiza a mano**.

## `make screens`: qué ve y qué NO

```bash
make yarn-build   # si tocaste JS o clases de Tailwind
make screens      # 76 capturas → tmp/screenshots/, 42 guardas
```

Recorre la app con Playwright. Falla si hay error de JS, si una respuesta da
>= 400, si queda un `.island-placeholder` sin montar, o si cualquiera de las 42
guardas no pasa.

### Cómo escribir una captura nueva

- **Navegá por LINK, no con `goto`.** Turbo no dispara `DOMContentLoaded` al
  navegar por link; un `goto` monta la isla igual y **esconde el bug**.
- **Después de un clic, esperá `waitForURL` o un selector.** `networkidle` se
  calma **antes** de que Turbo ponga el body nuevo, y la captura sale de la
  pantalla anterior.
- Las islas exponen `data-island-mounted="true"` como señal determinista.
- **Nunca apuntes una captura a un desafío que también se usa a mano.** Hay
  desafíos sembrados que existen **sólo** para el recorrido
  (`sin-formulario`, `con-salteado`, `comite-abierto`). Compartir uno con
  pruebas manuales rompió la corrida dos veces.
- **Una guarda que cuenta eventos tiene que arrancar con el paso anterior ya
  pintado, y hay que verla fallar.** La del camino `_top` cuenta `turbo:morph`;
  el clic anterior también sale a `_top` y su diálogo se saca **antes** del
  morph, así que esperar a que el diálogo se detache deja esa navegación en
  vuelo y el contador registra **ESE** morph. Se espera una señal que sólo puede
  existir con la pantalla nueva pintada.

### «Falla si hay HTTP >= 400» tiene una excepción, angosta a propósito

Dos pantallas se fotografían con un error encima **aposta** —un 403 y un 404—, y
sin una excepción declarada eso reventaría la corrida.

`shotConEstado` fija `estadoEsperado` antes de navegar; mientras está puesto,
**sólo se perdona el DOCUMENTO PRINCIPAL de ESA navegación, y sólo si responde
exactamente con el estado declarado**. Un asset o un `fetch` que devuelva >= 400
en el medio **no se perdona nunca**, y si el documento principal responde con
otra cosa —un 200 donde se esperaba un 403— sigue fallando, con su propia guarda
(`[ESTADO]`).

**Lo angosto es lo que sostiene la regla:** perdonar «>= 400» a secas la dejaría
ciega para siempre.

### Las guardas, agrupadas

| Grupo | Guardas |
|---|---|
| **Que exista y monte** | `[ISLA]`, `[MORPH]`, `[PLEGABLE]`, `[ESTADO]` |
| **Que tenga reglas detrás** | `[CLASES]`, `[PANEL]`, `[RELLENO]`, `[SOMBRA]`, `[RITMO]` |
| **Contraste y accesibilidad** | `[CONTRASTE]`, `[PUNTOS]`, `[ESTADO-DRAWER]`, `[PASTILLA]`, `[BANDA]`, `[CAMPO]`, `[MONO]` |
| **Forma de la pantalla** | `[ZONAS]`, `[REFERENCIA]`, `[RIEL]`, `[TEMA]`, `[DESGLOSE]`, `[SALTEADO]` |
| **Comportamiento en vivo** | `[LIVE]`, `[DRAFT]`, `[GRABAR]`, `[CHECKIN]` |
| **Contenido de dominio** | `[CRITERIO]`, `[EVALUADORES]`, `[FILTROS]`, `[TESTING]`, `[VERSIONADO]`, `[SETUP]`, `[TALLER]`, `[BUILDER]`, `[FORMS]`, `[IA]`, `[DATOS]`, `[CODIGO]`, `[TEXTO]`, `[LINK]`, `[ETIQUETAS]`, `[VACIO]` |

`[CARD]` **se retiró** —ya no está entre las 42; sobrevive sólo en un
comentario—: medía el aspecto de una `card` contra `.panel`, y sin
`.panel` no quedaba contra qué comparar. `[RELLENO]` y `[SOMBRA]` ocupan dos
tercios de su lugar; el tercio que **queda sin cubrir es `--card-fs`**, la letra
de 14px, que no la mira nadie: **una `card` puede perder su tamaño de letra y las
76 capturas seguir en verde.**

### Once guardas cuentan cuánto midieron

Porque **una guarda que mide cero da verde y es indistinguible de una que
funciona**. La corrida imprime los once números en una sola línea al terminar.

**`PISO_DE_BANDAS` es EXACTO y los demás van con holgura** —con dos excepciones
más, `[DRAFT]` y `[GRABAR]`, también exactas—. La diferencia tiene motivo: los
demás cuentan cosas que se mueven —tarjetas, chips y campos con los datos—, y
`[BANDA]` cuenta **VISTAS** que publican `content_for :banda`, que es un número
fijo, y lo único que esa guarda existe para cazar es **la vista olvidada**. Con
un piso flojo no la caza: borrar el `content_for` de una sola bajaba el conteo de
63 a 60 y un piso al 92% no se enteraba. El precio es que sumar una pantalla con
banda obliga a subir el piso con ella.

`[DRAFT]` y `[GRABAR]` son exactos en **2** por un motivo del mismo tipo pero no
el mismo: cuentan **las dos caras de la sala** y no hay una tercera, así que un
piso flojo no cazaría que una dejó de medirse.

### Y lo que NINGUNA guarda ve

Esto está acá para que nadie lo dé por cubierto.

**`[CLASES]` mira una lista FIJA de familias de componentes** —`badge`, `btn`,
`alert`, el punto del drawer, `.steps`, `.panel`, `.card`, `.page-banner`,
`.app-rail__item` y las celdas de `.table`—, **así que un elemento hecho sólo de
utilidades de Tailwind es invisible para ella**. La tarjeta del QR del check-in
(`.bg-white.p-4.rounded-box.w-60`) no matchea ninguna, y por eso sobrevivió a
**seis** corridas verdes sin que ninguna de sus cuatro clases existiera en la
hoja.

**Y tampoco alcanza que exista la captura: un bloque que sólo se dibuja con datos
se fotografía AUSENTE y da verde.** La sala de idear lista «Las ideas de tu mesa»
sólo si la mesa tiene alguna, y sin una idea sembrada la captura retrataba el
formulario y nada más — mientras la lista de participación salía al costado del
título en vez de debajo.

Lo demás, nombrado:

- **`[REFERENCIA]` no mide la sala de la mesa.** `revisarReferencia` se llama
  desde la rama de `[ZONAS]` y desde la de testing, o sea **sólo en las pantallas
  de módulo**, y la sala es la única otra pantalla que llena
  `content_for :referencia`. Su límite declarado es ése: **una mesa muy grande
  queda detrás de su propio scroll.**
- **El riel a 414px no lo mira ninguna captura.** `[RIEL]` prueba el cambio a
  1000px, pero el recorrido no fotografía anchos de teléfono.
- **La regla de la etiqueta a la izquierda tampoco.** Si `.field-check` quedara
  mal escrita en la hoja, `make screens` y los specs seguirían en verde y el
  único testigo sería **alguien abriendo la captura**.
- **El PDF de reportería no lo ejercita NINGÚN test.** Su layout tiene un solo
  consumidor, un job, y no hay spec que lo renderice. O sea que **el único lugar
  donde la paleta llega a un usuario en algo que se descarga es justo el que
  nadie mira.**
- **El camino concurrente del autoguardado.** `[DRAFT]` dispara **un solo**
  `guardar()` por cara, así que nada ejercita el `AbortController`, los dos
  `form !== enviadoDesde`, el `finally`, `descargar()`, el `keepalive` ni el
  `visibilitychange`. **Borrarlos deja la suite y `[DRAFT] 2` en verde.** No se
  le puso guarda a propósito: una que depende de ganarle a una carrera cuesta
  más en fallas intermitentes de lo que ahorra.
- **La detección de contexto inseguro de la grabación.** El recorrido corre en
  `localhost`, que es contexto seguro **siempre**: borrar la detección tampoco
  pone nada en rojo (medido: la mutación quedó verde).
- **El «Entrar» de cada mesa.** `[CLASES]` lo ve sólo por la familia `btn` y
  sólo si pierde **toda** regla, y su wrapper de utilidades sueltas es invisible.
  **Nada mide** que el link esté, que lleve el `mesa=` correcto, su rótulo ni su
  maquetación. La maquetación **sólo la vio una persona abriendo la captura**, y
  ahí apareció el defecto que la ronda de arreglo cerró.

### La causa de fondo, y cómo leer la salida

**La línea final dice «N errores de página» pero imprime el contador GLOBAL de
fallas**, así que una guarda que falla aparece ahí aunque no haya ningún error de
JS ni respuesta >= 400: **no busques un error de página que no existe.**

**Y una guarda nueva se prueba contra un baseline que funciona.** La primera
mutación de `[LIVE]` corrió sobre el bundle viejo, donde el estado sano y el
mutado daban el **MISMO** `{"n":0}`, así que **no probó nada**. Una mutación sólo
discrimina si la corrida limpia pasa.

### El otro lado: una regla sin elemento

`[CLASES]` caza un **elemento** que se quedó sin regla. Lo contrario —una
**REGLA** que se quedó sin elemento— no lo cazaba nada, y por eso se juntaron
siete en silencio: de 402 clases declaradas, 7 sin un solo uso.

Lo cuida `spec/lint/reglas_sin_elemento_spec.rb`, con dos excepciones declaradas
y **con autotest del detector**: el primero que se escribió reportó 267 de 402
«sin uso» porque **HAML escribe `.x` y no `class="x"`**, y un detector mal
acotado reporta cero y da verde.
