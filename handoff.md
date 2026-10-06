# Handoff — el rediseño INNK (2026-10-05)

## 1. Objetivo

Que `innk_flow` se reconozca como el producto de INNK —marca, cromo y lenguaje
de superficie— sobre las pantallas que ya existen, sin agregar ninguna. El
insumo es el Figma «General Rediseño» (`3xc9srW7XlOlM9jzZ3lGjC`, página «Vistas
aprobadas», 485 frames en 15 secciones).

La spec está en `docs/superpowers/specs/2026-10-05-rediseno-innk-design.md` y el
plan en `docs/superpowers/plans/2026-10-05-rediseno-innk.md`.

## 2. Estado actual

Rama `rediseno-innk`, **15 commits, árbol limpio, nada pusheado**. Suite en
**1628 ejemplos, 0 fallas** (eran 1612 al empezar). `make screens` verde: 76
capturas, sin errores de JS ni respuestas >= 400, con 71 pantallas con riel, 71
con banda, 299 tarjetas y 289 campos medidos.

**Las nueve tareas están cerradas**, cada una con revisión independiente y, donde
hubo hallazgos, ronda de arreglo y re-revisión. Encima de eso corrió una
**revisión final de toda la rama** (`163925a..51fa668`, 14 commits) en el modelo
más capaz: **ningún Critical**, tres Important y ocho Minor, veredicto «listo para
mergear con arreglos». Esos once hallazgos se cerraron en **una sola ronda de
arreglos**, el commit 15.

| | Tarea | Commits |
|---|---|---|
| ✓ | 1. La red: spec de navegación global | `e936cde` · `33bf85e` |
| ✓ | 2. La paleta INNK en los dos temas | `c742519` |
| ✓ | 3. Open Sans | `8e457c9` · `639ddd6` (corrección del plan) |
| ✓ | 4. El control de tema | `b7d5c29` · `4ed1ba2` |
| ✓ | 5. El riel de navegación | `252c60f` |
| ✓ | 6. La banda de título | `d2301e9` · `ed484dd` |
| ✓ | 7. Superficies y radios | `cbde0b0` |
| ✓ | 8. Los formularios | `172c543` |
| ✓ | 9. `CLAUDE.md` | `51fa668` |
| ✓ | + revisión final de toda la rama | ronda de arreglos (commit 15) |

`4f04cab` es la versión anterior de este archivo, de cuando iban seis tareas.

**Falta una sola cosa antes del merge: la re-revisión acotada de la ronda de
arreglos.** Está agendada y lee ese commit como su propio rango.

**El ledger de la ejecución vive en
`.superpowers/sdd/2026-10-05-rediseno-innk/progress.md`** (gitignoreado) con los
briefs, los reportes, los transcriptos de mutación, el reporte de la ronda de
arreglos (`fix-wave-report.md`) y su mutación (`fix-wave-mutacion.txt`). Si se
perdiera, el registro real es `git log`.

### La decisión de diseño que queda ABIERTA

**El morado de INNK (`#8520BD`) está declarado y no pinta un pixel.**
`--color-accent` existe en los dos temas porque un tema propio de DaisyUI emite
sólo lo que declara —borrarlo rompe el tema—, pero nada lo lee: no hay un
`btn-accent`, `badge-accent`, `alert-accent`, `text-accent` ni `bg-accent` en
toda la app. Lo que pinta es el `--accent` de la app, que sigue apuntando al
primario (el índigo) en 35 usos directos más 16 de su escalera, `a { color: … }`
incluido. **Adoptarlo es una decisión que nadie tomó**, no un pendiente:
repuntar `--accent` repinta el producto entero, y pintar sólo la entrada activa
del riel pide una escalera nueva para una familia que no usa nada más. El
comentario al lado del token lo dice; la spec, en cambio, afirma que el acento
«gana un color propio», que es cierto del token y falso de lo que se ve —no se
reescribió la spec, se anotó—.

### Las decisiones que se tomaron sin preguntar

Están completas en el ledger con qué cuesta si cada una está mal. Las que
cambian el código:

1. **El ejemplo del gestor en T1 no podía fallar** — derivaba su expectativa de
   `manages_challenges?`, el mismo método que la vista consulta. Pasa a aseverar
   `false` literal.
2. **Los iconos del riel van inline, no por `image_tag`** — un `<img>` no hereda
   `currentColor` y el icono habría quedado gris con la entrada activa.
3. **Los pisos de las guardas nuevas se calibran con la primera corrida limpia**,
   no con los números que inventé en el plan.
4. **`make screens` corre con el proveedor real** y se deja así: el gasto es de
   centavos y ninguna guarda nueva depende de lo que conteste la IA.
5. **`--danger` va a 65%, no 75%** — mi cálculo era contra la superficie plana;
   el fondo que manda es la pastilla teñida.
6. **El PDF se actualiza entero**, no sólo el primario.
7. **El chequeo de «fuente variable» del plan no servía** (`fvar` no aparece como
   bytes literales en woff2); la señal confiable es el CSS de Google.
8. **El Critical de T4 se verificó en navegador antes de arreglarlo.**
9. **Dos Minor de T4 y siete de T5 entraron en la ronda** porque eran de una
   línea o defectos visibles, y la ronda ya iba a ocurrir.
10. **El «desvío» del mapeo de iconos era falso positivo mío** — el revisor sólo
    recibe el brief, no mis correcciones del despacho.
11. **Faltaban seis vistas en T6** — grepeé `.page-head` cuando el alcance era
    `.page-title`.
12. **El piso de `[BANDA]` va exacto**, no al 92%.
13. **El flake de JS queda anotado y no bloquea.**
14. **El campo NO es «sin borde»** (T7): es el único desvío deliberado del Figma,
    y está declarado en la hoja. Ver «Intentos fallidos».
15. **`[RIEL]` exige exactamente una entrada activa, con UNA excepción declarada
    por nombre de captura** (`/notifications`, que no es ninguna de las cinco
    secciones del riel). Se verificó que esa excepción no es código muerto:
    medido en navegador, `/notifications` tiene cero activas y `/challenges`,
    `/workshops` y `/criteria_sets` tienen una.
16. **El doble `setViewportSize` de `[RIEL]` se queda**, medido: 71 pares cuestan
    2,4 s (33,5 ms por pantalla) en una corrida de varios minutos, y hacerlo una
    vez por corrida bajaría la cobertura del cambio a fila de 71 pantallas a una.

## 3. Archivos y cambios

**Tokens y hoja** (`app/assets/stylesheets/application.css`): los 20 colores de
DaisyUI en los dos temas con la paleta INNK; `--danger` al 65%; una familia
tipográfica donde había dos; las reglas del riel, de la banda y del control de
tema; `.app-nav` borrada; `--shadow` y `--borde-superficie` dentro de cada bloque
`@plugin "daisyui/theme"`; `--borde-campo` nuevo; la etiqueta del campo a la
izquierda con cuatro excepciones (`.app-aside`, `<1024px`, `label.field-check`,
`.auth-card`).

**Fuentes** (`public/fonts/`): `open-sans-latin.woff2` (48.320 B) reemplaza a
Bricolage Grotesque e Inter (125.144 B entre las dos). `OFL.txt` es el de Open
Sans.

**Layouts**: `application.html.haml` gana el envoltorio `.app-frame`, el riel y
la banda; `auth.html.haml` y `application.html.haml` escriben `data-theme` sólo
si hay cookie. `pdf.html.haml` lleva los cinco colores nuevos a mano.

**Nuevo**: `app/controllers/themes_controller.rb`, `app/lib/flow/themes.rb`,
`app/views/shared/_theme_switch.html.haml`, `app/views/layouts/_rail.html.haml`
y los cinco `app/views/layouts/rail/_*.html.erb` con los SVG del Figma inline.

**26 vistas** publican `content_for :banda`. `workshop_checkins/show` NO, y lleva
el comentario que dice por qué.

**Specs nuevos**: `spec/requests/navegacion_global_spec.rb`,
`spec/requests/theme_spec.rb`.

**Guardas nuevas en `script/capture_screens.js`**: `[TEMA]`, `[RIEL]`, `[BANDA]`,
`[SOMBRA]` y `[CAMPO]` —las cinco probadas por mutación, con transcripto—. Los
dos lint de `spec/lint/` se ensancharon a `.erb`.

## 4. Intentos fallidos

Lo que más vale de esta sesión. **Seis defectos del plan se encontraron antes de
costar una vuelta, y OCHO guardas o tests resultaron incapaces de fallar**
—cuatro durante las nueve tareas, cuatro más que encontró la revisión final—.

### Guardas y tests que no podían fallar

- **El control de tema pasaba todos los tests y estaba roto.** Nueve ejemplos de
  request en verde, la guarda `[TEMA]` en verde, el recorrido en verde — y
  apretar «Oscuro» no cambiaba nada hasta recargar a mano. Tres cosas fallaron a
  la vez: mi spec razonó contra el peligro equivocado (defendí que el morph
  *borrara* el atributo; el problema es que nunca lo *aplica*, porque Turbo
  morfea el `<body>` y del `<html>` sólo sincroniza `lang` y `dir`); un request
  spec no puede verlo porque pide la página de nuevo; y **la guarda medía la
  única pantalla donde el bug no ocurre** —corre tras limpiar cookies, cae en
  `/login`, y ése resulta ser el único layout sin bundle—. Arreglado con
  `turbo: false` en los tres `button_to`.
- **`[CAMPO]` no cazaba la regresión para la que existe.** Medía el borde del
  campo sin preguntar por su ANCHO, y con `border-style: none` —lo que queda si
  alguien borra la línea `border:` del bloque de campos, o escribe `border: none`
  para volver al campo sin contorno del Figma— el ancho computa 0 pero
  `borderTopColor` sigue devolviendo `currentColor`, o sea `--text`, que sobre
  blanco mide **17,43:1**: verde con el campo sin ningún contorno. Las dos
  mutaciones que se habían corrido (borrar el `box-shadow`, `--borde-campo:
  transparent`) dejan el ancho en 1px, así que ninguna tocaba el agujero. La
  tercera, que es la más natural de las tres, pasaba. Probado de los dos lados en
  `fix-wave-mutacion.txt`: con la hoja mutada, fórmula vieja 17,43:1 y 6,06:1
  (verde), fórmula nueva 1,00:1 en 47 pantallas (rojo).
- **`[RIEL]` aceptaba CERO entradas activas, y había pantallas reales con cero.**
  Sólo fallaba con más de una, así que la segunda de las tres cosas que la spec
  le pide —«marca el activo»— no estaba cubierta. Y no era hipotético:
  `step_tests` y `previews` faltaban en la lista de `controller_name` de
  Desafíos, dos pantallas que están claramente adentro de Desafíos, y salían con
  los cinco iconos grises (se ve en `22b-testeo-nuevo.png`). Venía de `master`
  —`.app-nav` tenía la misma condición—, pero una columna de 80px lo muestra
  mucho más que una pastilla en la barra.
- **La rama de «la banda se dibuja vacía» de `[BANDA]` era código muerto.**
  `medirContraste` filtra con `.filter(el => … && el.textContent.trim())`, así
  que una `.page-banner` sin texto nunca llegaba a ese bucle y el mensaje no se
  podía imprimir jamás. El caso lo cubre el piso exacto de 71 por otro lado. Una
  rama que aparenta cubrir lo que cubre otro chequeo es peor que no tenerla:
  invita a creer que está cubierto dos veces.
- **El piso de `[BANDA]` al 92% no cazaba lo único que la guarda existe para
  cazar.** Borrar el `content_for :banda` de una vista bajaba el conteo de 63 a
  60 sin cruzar el piso de 58. Va exacto.
- **Tres mutaciones de T6 no probaban nada**: una no cruzaba el piso, otra moría
  antes en un `waitForSelector`, y **otra mutaba la guarda misma** (subir el
  piso) en vez del código — eso demuestra que el mensaje se imprime, no que
  detecte una regresión.
- **Una mutación de T7 no se aplicó, y la cazó su propio transcripto**: el assert
  falló y el log dice que esa corrida en realidad estaba sana. Se rehízo bien.
- **`[CLASES]` no conocía el vocabulario nuevo de la rama.** Su lista fija de
  familias no tenía `.page-banner` ni `.app-rail__item`, y eso tiene una
  consecuencia concreta: si la regla `.page-banner` entera desapareciera, el `h1`
  heredaría `--text` sobre `--surface` —unos 17:1—, así que `[BANDA]` seguiría
  verde, el conteo seguiría en 71 y nadie más se enteraría. (`.theme-switch__btn`
  ya entraba por la subcadena de `[class*="btn"]`.)
- **El `--color-accent` declarado y sin un solo consumidor**, con el comentario al
  lado afirmando lo contrario: «el acento DEJA de apuntar al primario». Nada lo
  leía. No es una guarda, pero es la misma familia de defecto: un texto que da
  permiso a creer que algo está hecho.

### Defectos del plan y mediciones que no se sostenían

- **`light-dark()` NO sirve para un valor que no es color, y la verificación del
  propio plan lo habría aprobado.** Es una función de COLOR: una `box-shadow`
  entera envuelta en ella deja la propiedad inválida en tiempo de valor computado
  y cae a `none` **en los dos temas**, en silencio. El paso de verificación del
  plan probaba `background: light-dark(#fff,#000)` —el caso de color, que SÍ
  funciona—. Una compuerta que mide una forma distinta de la que gobierna no es
  que no ayude: da permiso. Se embarcó el plan B: los dos tokens adentro de cada
  bloque `@plugin "daisyui/theme"`.
- **Hubo que BORRAR el `--shadow` viejo del `:root` sin capa de la app**, porque
  DaisyUI emite el tema por default en `:where(:root)` —especificidad cero—, así
  que una declaración sobreviviente de (0,1,0) le habría ganado en silencio y
  todo habría quedado verde sobre la sombra anterior.
- **Un campo sin borde medía 1,09–1,12:1** contra la tarjeta de atrás (el mismo
  `var(--surface)` de fondo, borde transparente) contra el 3:1 que pide el 1.4.11
  de WCAG, que este repo ya hace valer para los puntos del drawer. De ahí
  `--borde-campo`, el único desvío deliberado del Figma en toda la rama. Y la
  revisión final midió después que el borde del campo claro daba **1,25:1 ANTES**
  de esta rama y da **3,36:1** ahora: ese fallo no sólo evitó una regresión,
  arregló algo que ya estaba mal.
- **El plan afirmaba que las islas Vue no usan `.field`. Las usan**
  (`config_field.vue`, `criteria_editor.vue`), y `config_field.vue` pone un
  `label.field-check` como HERMANA directa de la label del nombre, que la regla
  nueva habría apilado en la columna de 190px dejando la columna 2 vacía.
- **Las «154 ocurrencias en 43 vistas» del plan eran el grep ingenuo**: incluían
  `.field-hint` y `.field-list*`. El alcance real son 29 envoltorios `.field` en
  12 vistas más 3 en las islas.
- **La columna de etiquetas apretó el login y el check-in público** de ~314px a
  ~108px, visible en las capturas entregadas, hasta que `.auth-card` se llevó su
  propia excepción.
- **`CLAUDE.md` describía la trampa del control de tema como el estado presente y
  nunca nombraba `turbo: false`**, que es lo que la resuelve — así que el
  documento habría llevado a la próxima sesión a «limpiar» tres formularios que
  optan por salir de Turbo «sin motivo» y a romper el control de tema en
  silencio, re-sembrando el bug que la tarea 4 acababa de pagar.
- **`[RIEL]` medía a 1100px cuando el corte de la hoja es 1023px** — a 1100 el
  riel sigue vertical por diseño, así que la primera corrida falló en 71
  pantallas por nada.
- **El chequeo de fuente variable del plan daba falso negativo.** `b'fvar' in d`
  sobre el woff2 devuelve `False` aunque la fuente sea variable: woff2 codifica
  las tablas conocidas como índices de 5 bits. Un implementador siguiéndolo al
  pie habría salido a buscar otra fuente.
- **El token `--danger-soft-text` era el arreglo equivocado.** Tapaba sólo lo que
  `[CONTRASTE]` mira y dejaba el mismo defecto en `.diff-kind--removed` y
  `.setup__mark`, que ninguna guarda ve. La respuesta era corregir el 75%.
- **Mi advertencia sobre el `fill="white"` de `recursos.svg` estaba equivocada**:
  era el rect del `clipPath`, no un calado. El implementador lo verificó en vez
  de aplicarla a ciegas. (El `clipPath` en sí resultó basura de exportación —un
  `rect` de 34×32,1 contra un `viewBox` de 26,76, que no recorta nada— y era el
  único `id` global que el riel ponía en el DOM; se borró en la ronda final.)
- **Cinco números medidos quedaron viejos en la hoja, y uno nunca se reprodujo.**
  Ninguno cruzaba su piso, pero en este archivo un número declarado es un número
  que alguien midió: `--muted`, el acento y el hilo de IA, `--tenue` y
  `--color-neutral-content` se re-midieron en navegador en los dos esquemas. Y el
  peor: **la hoja, el script y `CLAUDE.md` decían que el campo en tema oscuro mide
  1,05:1 contra su ancestro, y nadie reprodujo ese número**. Medido con el propio
  medidor de `[CAMPO]` sobre el textarea de `/challenges/new`: **1,13:1**. La
  discrepancia con el 1,142 que da la cuenta en flotante es la cuantización a 8
  bits del canvas, no dos mediciones distintas — y de paso contesta la pregunta
  que quedaba abierta: con el tono viejo (285,9°) el par daba 1,1395 y con el
  nuevo (247,88°) da 1,1420, o sea que la paleta nueva lo mejoró en 0,0025 y no
  es una regresión.
- **Un falso positivo que es defecto de mi proceso**: el revisor marcó el mapeo
  de iconos como desvío porque **sólo recibe el brief extraído del plan, no mis
  correcciones del despacho**. Cuando corrijo un brief al despachar, la
  corrección tiene que viajar también al revisor.
- **Este archivo estaba viejo y es un archivo versionado de la rama.** Decía «10
  commits», «seis de nueve tareas cerradas» y marcaba la tarea 7 con «acá se
  sigue» cuando ya había 14 commits y las nueve tareas estaban cerradas,
  revisadas y pasadas por una revisión final. El documento de traspaso de la rama
  afirmaba con confianza que el trabajo iba por dos tercios.

## 5. Próximos pasos

1. **La re-revisión acotada de la ronda de arreglos** (el commit 15). Es lo único
   que falta y ya está agendada; lee ese commit como su propio rango, con este
   handoff, `fix-wave-report.md` y `fix-wave-mutacion.txt` como insumo.
2. **Después**, `superpowers:finishing-a-development-branch`. El push lo hace
   Raúl a mano: desde la sesión lo frena el clasificador de auto mode.
3. **La decisión del morado queda para Raúl** (sección 2). No hay nada que
   implementar hasta que la tome: si la respuesta es «no», el estado de hoy es el
   correcto y el comentario de la hoja ya lo explica.

**Lo que queda sin vigilancia**, y está anotado en `CLAUDE.md` con los otros
huecos: `--card-fs` y la sombra de `card`, `[REFERENCIA]` en la sala de la mesa,
el riel a 414px, la regla de la etiqueta a la izquierda (ninguna guarda la ve) y
el PDF de reportería, que no lo ejercita ningún test.
