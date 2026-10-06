# Handoff — el rediseño INNK (2026-10-05)

## 1. Objetivo

Que `innk_flow` se reconozca como el producto de INNK —marca, cromo y lenguaje
de superficie— sobre las pantallas que ya existen, sin agregar ninguna. El
insumo es el Figma «General Rediseño» (`3xc9srW7XlOlM9jzZ3lGjC`, página «Vistas
aprobadas», 485 frames en 15 secciones).

La spec está en `docs/superpowers/specs/2026-10-05-rediseno-innk-design.md` y el
plan en `docs/superpowers/plans/2026-10-05-rediseno-innk.md`.

## 2. Estado actual

Rama `rediseno-innk`, **15 commits, árbol limpio**. **Ojo, el handoff anterior
decía «nada pusheado» y era falso: `origin/rediseno-innk` apunta a `4f04cab`,
así que 11 de los 15 YA están en el remoto y los últimos 4 son locales**
(`cbde0b0`, `172c543`, `51fa668` y la ronda de arreglos). Lo cazó la
re-revisión de la ronda de arreglos; nadie lo había vuelto a verificar en dos
sesiones. Suite en
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

**La re-revisión de esa ronda cerró: los once hallazgos ADDRESSED, sin roturas
nuevas, veredicto «listo para mergear».** Verificó por su cuenta —sin navegador
y sin la app— los diez contrastes de la hoja recalculando oklab → sRGB lineal →
WCAG, y dio con el valor embarcado a cuatro decimales en ocho de diez. El único
defecto que introdujo la propia ronda era el «nada pusheado» de acá arriba.

**No queda ningún hallazgo abierto.** Lo que falta es decidir cómo se integra,
y eso es de Raúl.

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

### Las 36 decisiones, por número de ruling

La lista de arriba son las que cambian el código. Ésta es **completa**, en el
orden en que se tomaron, y existe porque el ledger que las tenía enteras se
borra con el workspace. Una por línea, con qué cuesta si está mal.

1. El ejemplo del gestor en T1 asevera `false` literal y no consulta
   `manages_challenges?` — *si algún día el gestor sí ve Criterios, el ejemplo
   falla y se actualiza a mano.*
2. Los iconos del riel van inline y no por `image_tag` — *el partial queda más
   largo; se extrae a un helper si molesta.*
3. Los tres pisos nuevos se calibran con la primera corrida limpia — *un piso
   mal calibrado da falso rojo o deja pasar una regresión.*
4. `make screens` sigue corriendo con el proveedor real — *unos dólares de API.*
5. `--danger` va a 65% y `--danger-soft-text` se borra — *el rojo del texto
   queda un escalón más oscuro que el del Figma; el color de marca no cambia.*
6. El PDF se actualiza entero y no sólo el primario — *estético y reversible.*
7. El chequeo de «fuente variable» del plan se reemplaza por el CSS de Google —
   *si Google cambia el formato, el chequeo deja de discriminar.*
8. El Critical de T4 se verifica en navegador antes de arreglarlo — *dos
   minutos de verificación.*
9. Dos Minor de T4 entran en la ronda — *dos líneas de más en un commit.*
10. El «desvío» del mapeo de iconos era falso positivo mío — *descartar un
    hallazgo real; se re-revisó.*
11. Siete Minor de T5 entran en la ronda — *un commit más grande.*
12. Faltaban seis vistas en T6 (grepeé `.page-head` y el alcance era
    `.page-title`) — *seis ediciones mecánicas de más.*
13. El piso de `[BANDA]` va EXACTO y no al 92% — *sumar una pantalla obliga a
    subir el piso a mano, que es deliberado y no un falso rojo.*
14. El flake `[JS ERROR] «The user aborted a request.»` se anota y no bloquea —
    *corridas intermitentes que obligan a repetir, que es lo que ya pasa.*
15. **El Step 1 de T7 verificaba la variante equivocada de `light-dark()`** (el
    caso color, no el box-shadow que gobernaba) — *una verificación de más, de
    un minuto.* Resultó portante: el gate original habría dado verde con la
    sombra borrada en los dos temas.
16. El plan B de T7 tampoco estaba verificado, y se le dio un plan C — *dos
    selectores en vez de una declaración.*
17. **«Las islas Vue no usan `.field`» era falso** y estaba en el mensaje de
    commit — *un selector de exclusión de más.*
18. Dos formas más de `.field` que el brief no contemplaba, verificadas en
    navegador — *dos capturas más que mirar.*
19. El Step 3 de T9 no tenía nada que hacer: su premisa era falsa — *nada; el
    paso queda verificado en vez de ejecutado.*
20. El grep de la verificación final de T9 **no puede volver vacío** y se
    reescribe contra la lista real — *hay que actualizar la lista si alguien
    toca esos comentarios.*
21. `[SOMBRA]` se ensancha a los campos aunque la spec la escriba sólo sobre
    `.card` — *un selector más largo y un contador más.*
22. El censo de `--shadow` se corrige a seis — *nada; es exactitud de un
    comentario que sostiene una decisión de diseño.*
23. **El canto del campo se mide, y si no llega a 3:1 se arregla** — *el campo
    queda con un canto que el Figma no dibuja, visible en todos los
    formularios, y se revierte cambiando un token.* Medido 1,09–1,12:1, así que
    se arregló. Es el único desvío deliberado del diseño.
24. Los campos en tema oscuro quedan parkeados para la revisión final — *el
    tema oscuro queda con campos sin canto discernible.* Resuelto en el 33.
25. El Important de T8 entra: la tarjeta de auth se arregla — *dos pantallas
    conservan la etiqueta arriba, que es como estaban.*
26. El Minor del band 1024–1280px se mide antes de descartarlo — *una medición
    de un minuto.* Dio 239px: no había nada que arreglar.
27. Que nada vigile la regla de los formularios NO se contesta con una guarda
    nueva: se escribe en «sin vigilancia» — *la regla queda sin red y se rompe
    en silencio alguna vez.*
28. La corrección del ruling 20 va al PLAN y no sólo al brief generado — *dos
    párrafos editados en un plan ya ejecutado.*
29. **`CLAUDE.md` describía el morph como si todavía rompiera el control de tema
    y nunca nombraba `turbo: false`** — *una cláusula de más en un párrafo.* Sin
    esto, la próxima sesión limpia los tres formularios y rompe el tema.
30. `[CAMPO]` tenía puesta la razón de `[SOMBRA]` para ser sólo-claro — *quien
    lo extienda a oscuro se come un rojo en todas las pantallas.*
31. Cinco Minor de T9 entran en la misma ronda, incluido documentar el riel en
    la sección del shell — *unas líneas en una sección que nadie pidió tocar.*
32. El PDF entra a «sin vigilancia» — *ninguno; la cobertura no existe igual.*
33. **El ruling 24 queda resuelto: deuda vieja, la rama no la empeoró** (1,1395
    antes, 1,1420 después) — *y aparece que el 1,05:1 que decían los archivos no
    lo reprodujo nadie; se midió y da 1,13:1.*
34. **Sobre `--color-accent`: NO se repunta `--accent`, se arregla el
    comentario** — *el morado de INNK sigue sin pintar nada hasta que Raúl
    decida, y queda escrito donde se mira.* Es la decisión abierta de arriba.
35. El Important de `[CAMPO]` entra entero con su mutación — *ninguno; cierra
    una guarda que daba permiso.*
36. Ocho Minor entran en la ola única y uno se difiere (el `font-weight: 600`
    del label contra el «bold» de la spec) — *un peso de letra cosmético.*

**Y una que tomó el implementador, no yo, y la acepté:** `[RIEL]` exige
exactamente una entrada activa con **una excepción declarada por nombre de
captura** (`/notifications`, que no es ninguna de las cinco secciones del riel).
Era una tercera salida que yo no había ofrecido, sigue el precedente de
`shotConEstado`, y la re-revisión la verificó mejor que las dos que sí ofrecí:
«exigir al menos una» habría fallado en esa pantalla y «dejarla como estaba» la
dejaba ciega en las 71.

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

**No queda trabajo de implementación.** Las nueve tareas, la revisión final y la
re-revisión de su ronda de arreglos están cerradas, sin hallazgos abiertos.

1. **Cómo se integra es decisión de Raúl**, y hay un dato que cambia las
   opciones: **la rama ya está parcialmente pusheada**. `origin/rediseno-innk`
   apunta a `4f04cab`, o sea los primeros 11 commits; los últimos 4 son locales.
   Así que no es «pushear una rama nueva», es un `push` que adelanta una rama que
   ya existe en el remoto.
2. **El push y el merge los hace Raúl a mano.** Desde la sesión los frena el
   clasificador de auto mode, y además son efectos fuera del repo.
3. **La decisión del morado queda para Raúl** (sección 2). No hay nada que
   implementar hasta que la tome: si la respuesta es «no», el estado de hoy es el
   correcto y el comentario de la hoja ya lo explica.

**Lo que queda sin vigilancia**, y está anotado en `CLAUDE.md` con los otros
huecos: `--card-fs` y la sombra de `card`, `[REFERENCIA]` en la sala de la mesa,
el riel a 414px, la regla de la etiqueta a la izquierda (ninguna guarda la ve) y
el PDF de reportería, que no lo ejercita ningún test.
