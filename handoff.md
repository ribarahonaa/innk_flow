# Handoff — el rediseño INNK (2026-10-05)

## 1. Objetivo

Que `innk_flow` se reconozca como el producto de INNK —marca, cromo y lenguaje
de superficie— sobre las pantallas que ya existen, sin agregar ninguna. El
insumo es el Figma «General Rediseño» (`3xc9srW7XlOlM9jzZ3lGjC`, página «Vistas
aprobadas», 485 frames en 15 secciones).

La spec está en `docs/superpowers/specs/2026-10-05-rediseno-innk-design.md` y el
plan en `docs/superpowers/plans/2026-10-05-rediseno-innk.md`.

## 2. Estado actual

Rama `rediseno-innk`, **10 commits, árbol limpio, nada pusheado**. Suite en
**1628 ejemplos, 0 fallas** (eran 1612 al empezar). `make screens` verde, con
71 pantallas con riel y 71 con banda.

**Seis de nueve tareas cerradas**, cada una con revisión independiente y, donde
hubo hallazgos, ronda de arreglo y re-revisión:

| | Tarea | Commits |
|---|---|---|
| ✓ | 1. La red: spec de navegación global | `e936cde` · `33bf85e` |
| ✓ | 2. La paleta INNK en los dos temas | `c742519` |
| ✓ | 3. Open Sans | `8e457c9` |
| ✓ | 4. El control de tema | `b7d5c29` · `4ed1ba2` |
| ✓ | 5. El riel de navegación | `252c60f` |
| ✓ | 6. La banda de título | `d2301e9` · `ed484dd` |
| | **7. Superficies y radios** | ← **acá se sigue** |
| | 8. Los formularios | |
| | 9. CLAUDE.md | |
| | + revisión final de toda la rama | |

**El ledger de la ejecución vive en
`.superpowers/sdd/2026-10-05-rediseno-innk/progress.md`** (gitignoreado) con los
briefs, los reportes y los transcriptos de mutación. Si se perdiera, el registro
real es `git log`.

### Las catorce decisiones que se tomaron sin preguntar

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

## 3. Archivos y cambios

**Tokens y hoja** (`app/assets/stylesheets/application.css`): los 20 colores de
DaisyUI en los dos temas con la paleta INNK; `--danger` al 65%; una familia
tipográfica donde había dos; las reglas del riel, de la banda y del control de
tema; `.app-nav` borrada.

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

**Guardas nuevas en `script/capture_screens.js`**: `[TEMA]`, `[RIEL]`, `[BANDA]`
—las tres probadas por mutación, con transcripto—. Los dos lint de
`spec/lint/` se ensancharon a `.erb`.

## 4. Intentos fallidos

Lo que más vale de esta sesión. **Cinco defectos del plan se encontraron antes de
costar una vuelta, y cuatro guardas o tests resultaron incapaces de fallar.**

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
- **El piso de `[BANDA]` al 92% no cazaba lo único que la guarda existe para
  cazar.** Borrar el `content_for :banda` de una vista bajaba el conteo de 63 a
  60 sin cruzar el piso de 58. Va exacto.
- **Tres mutaciones de T6 no probaban nada**: una no cruzaba el piso, otra moría
  antes en un `waitForSelector`, y **otra mutaba la guarda misma** (subir el
  piso) en vez del código — eso demuestra que el mensaje se imprime, no que
  detecte una regresión.
- **El chequeo de fuente variable del plan daba falso negativo.** `b'fvar' in d`
  sobre el woff2 devuelve `False` aunque la fuente sea variable: woff2 codifica
  las tablas conocidas como índices de 5 bits. Un implementador siguiéndolo al
  pie habría salido a buscar otra fuente.
- **El token `--danger-soft-text` era el arreglo equivocado.** Tapaba sólo lo que
  `[CONTRASTE]` mira y dejaba el mismo defecto en `.diff-kind--removed` y
  `.setup__mark`, que ninguna guarda ve. La respuesta era corregir el 75%.
- **`[RIEL]` medía a 1100px cuando el corte de la hoja es 1023px** — a 1100 el
  riel sigue vertical por diseño, así que la primera corrida falló en 71
  pantallas por nada.
- **Mi advertencia sobre el `fill="white"` de `recursos.svg` estaba equivocada**:
  era el rect del `clipPath`, no un calado. El implementador lo verificó en vez
  de aplicarla a ciegas.
- **Un falso positivo que es defecto de mi proceso**: el revisor marcó el mapeo
  de iconos como desvío porque **sólo recibe el brief extraído del plan, no mis
  correcciones del despacho**. Cuando corrijo un brief al despachar, la
  corrección tiene que viajar también al revisor.

## 5. Próximos pasos

En orden. El brief de cada tarea se genera con
`bash ~/.claude/plugins/cache/claude-plugins-official/superpowers/6.4.1/skills/subagent-driven-development/scripts/task-brief docs/superpowers/plans/2026-10-05-rediseno-innk.md N`

1. **Tarea 7 — superficies y radios.** Es la única con riesgo de cambiar de
   enfoque a mitad: su **primer paso verifica que `light-dark()` exista en el
   Chromium del recorrido**, y si no está hay que caer al plan B (declarar
   `--shadow` y `--borde-superficie` dentro de cada bloque
   `@plugin "daisyui/theme"`). Tiene una consecuencia que conviene tener
   presente: la sombra pasa a ser **lo único que define la tarjeta en tema
   claro**, porque el borde se vuelve transparente — de ahí la guarda
   `[SOMBRA]`, cuyo piso también hay que calibrar con la corrida limpia.
2. **Tarea 8 — los formularios.** Una sola regla de CSS mueve las 154 `.field` a
   etiqueta-izquierda sin tocar un HAML. Tres excepciones: `.app-aside`, abajo de
   1024px, y las islas Vue. Incluye un paso de mirar capturas a ojo, que ninguna
   guarda reemplaza.
3. **Tarea 9 — `CLAUDE.md`.** Lo más importante: la regla de `data-theme`
   **cambió** —ahora el atributo va, pero sólo si hay cookie— y hoy el archivo
   dice lo contrario. Sumar las cuatro guardas nuevas, que son **dos layouts** y
   no uno, que el PDF no tiene cobertura de tests, y los tres lugares que siguen
   sin vigilancia (`--card-fs`, `[REFERENCIA]` en la sala de la mesa, el riel a
   414px).
4. **Revisión final de toda la rama**, en el modelo más capaz, apuntándola a los
   Minor diferidos del ledger para que triage cuáles bloquean el merge.
5. **Después**, `superpowers:finishing-a-development-branch`. El push lo hace
   Raúl a mano: desde la sesión lo frena el clasificador de auto mode.

**Al reanudar:** el ledger en
`.superpowers/sdd/2026-10-05-rediseno-innk/progress.md` dice qué tareas tienen
línea `complete` — ésas no se re-despachan. Se retoma en la primera sin ella.
