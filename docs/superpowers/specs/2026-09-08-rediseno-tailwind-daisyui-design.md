# Rediseño: Tailwind 4 + DaisyUI 5

> **Estado:** diseño aprobado, sin implementar.
> Rama de trabajo: `rediseno-tailwind`. Nada de esto toca `master` hasta que
> cada paso esté verde.

## El problema

La maqueta funciona y el modelo está validado, pero la interfaz no acompaña. En
palabras de quien la usa, cuatro cosas a la vez:

1. **No se sabe dónde uno está ni qué sigue.** Se entra a un módulo y no es
   obvio qué hay que hacer ahí, ni en qué punto del proceso está el desafío.
2. **Las pantallas largas son un muro.** Todo apilado con el mismo peso.
3. **Se ve plano.** Correcto pero genérico: no parece un producto.
4. **La interacción se siente tosca.** Todo es un formulario; las
   confirmaciones son el `confirm()` gris del navegador.

Medido sobre las capturas de `make screens`, el caso peor es
`steps/evaluation`: **seis tarjetas apiladas del mismo peso**, la última un muro
de quince evaluaciones, y **el 60% del ancho de una pantalla de 1440px vacío**.
El caso opuesto es `challenges/show`: limpia, pero con media pantalla en blanco.

### Lo que una librería no arregla

De las cuatro quejas, una librería resuelve bien la (4) y a medias la (3). Las
dos que más duelen —(1) y (2)— son **arquitectura de información**: decidir que
una pantalla tenga un área de trabajo principal y el resto como referencia. Eso
hay que diseñarlo igual, con Tailwind o sin nada.

Consecuencia de orden: **primero se migra la plomería** (mecánico, sin
criterio), **después se hace la estructura** sobre el sistema nuevo. Al revés es
hacer el trabajo de criterio dos veces.

---

## Punto de partida

| | |
|---|---|
| Hoja de estilos | `app/assets/stylesheets/application.scss`, **1.939 líneas** |
| ¿Usa Sass? | **Sí, una sola cosa: concatenación de selector** (`&__x`, `&--x`) en 73 lugares. Cero `@use`, `@import`, `@mixin`, `@extend`, cero variables |
| Vistas | 54 HAML, de las cuales 18 son partials |
| Clases distintas en vistas | 531 |
| Componentes Vue | 7, sin `<style>` propio, usando **119 clases** de la hoja compartida |
| Clases armadas por interpolación | **48, en 24 archivos** |
| Specs que afirman sobre clases CSS | 7 |
| Modo oscuro | No existe: cero `prefers-color-scheme` |

La primera línea de la hoja dice: *«Sin framework CSS: la maqueta define sus
propios tokens y evita heredar la deuda de Bootstrap 3 que arrastra innk_r5.»*
Este spec revierte esa decisión a propósito, y la sección siguiente dice por qué.

---

## Decisión: Tailwind 4 + DaisyUI 5

El encargo pedía tres cosas a la vez: que se vea bien para mostrarla, que sea
cómoda para seguir probando el modelo, y que no sea un callejón sin salida si
después el equipo la adopta. Eso descarta lo desechable y lo exótico.

**Tailwind** es donde está la industria y donde está la gente contratable; sirve
como reemplazo creíble del Bootstrap 3 de `innk_r5`. Solo, deja el HAML lleno de
utilidades sueltas y sin componentes. **DaisyUI** encima aporta clases
semánticas (`btn btn-primary`, `card`, `steps`) parecidas a las que ya hay, más
temas por configuración.

### Alternativas descartadas

| Opción | Por qué no |
|---|---|
| **Bootstrap 5** | El equipo ya lo habla y el camino 3→5 sería directo, pero se ve a Bootstrap: agravaría la queja «se ve plano», que es la que motivó el pedido. Y es exactamente la deuda que este repo evitó a propósito |
| **Solo el patrón, sobre la CSS actual** | Más barato y menos riesgoso, pero no le deja nada al equipo: no responde al pedido de una librería que se mantenga |
| **Librerías de componentes React** (MUI, shadcn…) | La app es server-rendered con HAML + Turbo. Adoptarlas sería reescribirla como SPA |

### Riesgos aceptados

- **Durante la migración la app se va a ver peor**, con pantallas a medio
  camino. Por eso la rama.
- **Las 30 capturas van a cambiar todas.** No rompe la verificación —falla por
  errores de JS, HTTP ≥ 400 e islas sin montar, no por comparación de píxeles—
  pero dejan de servir como referencia de «así se veía».
- **Es grande:** 54 vistas, 18 partials, 7 componentes Vue y 1.939 líneas de CSS
  a jubilar. No sale en una sesión.

---

## 1 · El build

Hoy hay tres `esbuild.build()`: las islas, `application.js` y
`application.scss`. **El tercero sale** y lo reemplaza el CLI de Tailwind:

```bash
tailwindcss -i app/assets/stylesheets/application.css \
            -o app/assets/builds/application-build-css.css --minify
```

`yarn build` pasa a correr los dos (esbuild para JS, Tailwind para CSS), así que
`make yarn-build` no cambia. **El layout tampoco:** el archivo de salida
conserva el nombre y `stylesheet_link_tag "application-build-css"` queda igual.

### Sass se jubila entero

Salen de `devDependencies`: **`esbuild-sass-plugin`** y **`sass`**. Sale el
`sassPlugin()` de los otros dos builds —en el de `application.js` ni siquiera
hacía falta, porque no importa ninguna hoja—. Ningún componente Vue tiene
`<style>`.

La conversión tiene **dos** partes, y la segunda casi se pierde:

1. Comentarios `//` a `/* */`, y el archivo pasa a `.css`. Mecánico.
2. **Aplanar los 73 `&__x` / `&--x` a selectores explícitos.**

> **La versión anterior de este spec decía que la hoja no usaba ninguna función
> de Sass, y era falso.** La verificación que produjo esa afirmación buscó
> `@use`, `@import`, `@mixin`, `@extend` y variables, y nunca `&`. Concatenar
> con `&` **es** una función de Sass: CSS nativo tiene `&`, pero no permite
> pegarle texto. Sin Sass, `&__icon` dentro de `.bell` compila a `__icon.bell`
> —un selector de tipo de elemento que no matchea nada—, y el ícono de la
> campana de avisos, presente en el layout de todas las pantallas autenticadas,
> pasó a medir 0×0.
>
> Ni `make spec` (no ejercita CSS) ni `make screens` (falla por errores de JS y
> HTTP ≥ 400, no por diferencia visual) lo atraparon: las dos pasaron en verde
> con el bug puesto. Lo encontró una revisión midiendo en un navegador real.
>
> El anidamiento `&:hover`, `&.is-active`, `& > li` **sí** es CSS válido y se
> conserva: son 9 casos y no se tocan.

### Paquetes

| Entra | Sale |
|---|---|
| `tailwindcss@4` · `@tailwindcss/cli@4` · `daisyui@5` | `sass` · `esbuild-sass-plugin` |

### La configuración vive en el CSS

Tailwind 4 es config-por-CSS: **no hay `tailwind.config.js`**. El archivo abre
con `@import "tailwindcss"`, `@plugin "daisyui"` y los temas con
`@plugin "daisyui/theme" { … }` (ambos exports verificados en el paquete 5.7.28).

> **Trampa a verificar en el paso 1:** Tailwind 4 descubre las fuentes solo,
> saltando lo ignorado por git. Si `.haml` o `.vue` no entraran en esa
> heurística, se declaran explícitamente con `@source`. No se asume: se comprueba
> con una clase que solo exista en un `.haml`.

---

## 2 · Tokens y tema

Los tokens actuales mapean casi uno a uno a los de DaisyUI, que es lo que hace
que esto no sea empezar de cero.

| Hoy | DaisyUI 5 |
|---|---|
| `--bg` · `--surface` · `--border` | `--color-base-200` · `--color-base-100` · `--color-base-300` |
| `--text` · `--muted` | `--color-base-content` (+ opacidad para el atenuado) |
| `--accent` · `--accent-soft` | `--color-primary` · `--color-primary-content` |
| `--danger` · `--ok` · `--warn` | `--color-error` · `--color-success` · `--color-warning` |
| `--radius` | `--radius-box` · `--radius-field` · `--radius-selector` |
| `--shadow` | `--depth` |

### Modo oscuro, que hoy no existe

Un tema de DaisyUI es una lista de esos mismos tokens, así que el oscuro es
**declarar la segunda lista**, no reescribir componentes. Se elige por
`[data-theme]`, y DaisyUI además lo conmuta con un checkbox
(`input.theme-controller`), así que **el selector claro/oscuro no necesita JS**.

### El carácter: dirección «Producto»

Elegida sobre dos alternativas (una «Herramienta» densa con IBM Plex, y una
«Documento» cálida con Source Serif).

| | |
|---|---|
| Títulos | **Bricolage Grotesque** (600/700), con `letter-spacing` negativo |
| Cuerpo e interfaz | **Inter** (400/500/600) |
| Números en tablas | Inter con `font-variant-numeric: tabular-nums` |
| Acento | **Violeta `#5b3df5`**, provisorio (ver decisiones abiertas) |
| Shell | Barra lateral **oscura en los dos temas** — es el shell, no el modo oscuro |
| Forma | Redondeo generoso (`--radius-box` ≈ 13px) y sombra sutil |

Las fuentes entran por Google Fonts con `display=swap` y pila de respaldo: si no
cargan, la app no se rompe.

---

## 3 · El patrón de layout

Tres regiones. La regla que decide qué va dónde:

> **La columna central es lo que se hace. La lateral derecha es lo que se
> consulta y no se edita en el curso normal del trabajo.**

```
┌──────────────────────────────────────────────────────────┐
│  barra superior: marca · navegación · sesión             │
├───────────┬──────────────────────────────┬───────────────┤
│ drawer    │  trabajo                     │  referencia   │
│ el flujo  │  (columna principal)         │  (columna     │
│ del       │                              │   angosta)    │
│ desafío   │                              │               │
└───────────┴──────────────────────────────┴───────────────┘
```

- **Izquierda (`drawer`):** los módulos del desafío en orden, con el actual
  marcado y los ejecutados atenuados. Persistente en todas las pantallas del
  desafío. Responde «dónde estoy y qué sigue».
- **Centro:** el trabajo del módulo.
- **Derecha:** referencia. Es lo que hoy son cuatro tarjetas del mismo peso
  comiéndose la pantalla.

### Qué va en la referencia, por tipo de módulo

| Módulo | Centro | Referencia |
|---|---|---|
| Idear | Ideas postuladas · formulario | Progreso · campos · modo de IA |
| Evolución | Ideas y su feedback | Progreso · quién acompaña · modo de IA |
| Evaluación | Ideas a evaluar · evaluaciones hechas | Progreso · criterios · quién evalúa · modo de IA |
| Selección | Tabla del corte · veredictos | Progreso · filtros · fuente de puntaje · modo de IA |
| Reportería | Tablero · reportes | Progreso · modo de IA |

### Comportamiento por ancho

| Ancho | Qué pasa |
|---|---|
| ≥ 1280px | Las tres regiones a la vez |
| 1024–1280px | La referencia baja debajo del centro |
| < 1024px | El `drawer` pasa a superposición, con su botón. Lo resuelve DaisyUI |

Las pantallas fuera de un desafío (`/criteria_sets`, `/members`,
`/admin/ai_runs`, login) **no llevan drawer**: no hay flujo que mostrar.

---

## 4 · La capa de componentes

El riesgo concreto de Tailwind es que el HAML se vuelva ilegible: doce o quince
utilidades por elemento, repetidas en 54 vistas y 7 componentes Vue. Sería
cambiar un problema de diseño por uno de mantenimiento.

> **Regla: si una clase aparece en más de dos vistas, es un componente — no
> utilidades sueltas.**

Tres capas, en este orden:

1. **Componentes de DaisyUI** donde existen.
2. **Clases propias declaradas en el CSS**, para el vocabulario que es de esta
   app y se repite: `.flow-strip`, `.step-card`, `.island-placeholder`,
   `.radio-cards`, `.empty-state`. Siguen teniendo nombre semántico.
   Van en **`@layer components`** con CSS plano —son clases de varias
   propiedades—; `@utility` de Tailwind 4 queda para utilidades de un solo
   propósito, que no es este caso.
3. **Utilidades sueltas en el HAML** solo para lo irrepetible.

### Mapeo

> **Actualizado por el plan 2a** (`2026-09-16-rediseno-2a-vocabulario-design.md`): `.card` pasa primero por `.panel`, los avisos van a `alert-soft` y `toast` no entra, y `.flow-strip` queda como contenedor propio con nodos `badge`. Leé ese spec antes de usar esta tabla.

| Hoy | DaisyUI |
|---|---|
| `.card` | `card` |
| `.btn` · `--primary` · `--ghost` · `--sm` | `btn` · `btn-primary` · `btn-ghost` · `btn-sm` |
| `.status-chip--*` | `badge badge-*` |
| `.step-table` | `table` |
| `.flash--alert` / `--notice` | `alert alert-error` / `alert-success` |
| `.flow-strip` | **`steps`** — existe con estados |
| `.radio-cards` · `.empty-state` | Se quedan propias (capa 2) |

### Lo que se gana

`drawer` (la barra lateral, con su comportamiento móvil resuelto) · `collapse`
(plegar configuración) · `toast` (los flash dejan de empujar el contenido) ·
`loading` (con proveedor real un pedido de IA tarda 10–70 s y hoy el único aviso
es el `aria-busy` del turbo-frame) · `modal` · `tooltip`.

### No se suma JavaScript

DaisyUI es CSS puro: modales, drawers, tabs y el conmutador de tema funcionan
sin una línea de JS, lo que encaja exacto con Turbo. **No entra Stimulus, ni
Alpine, ni nada.**

Única excepción: un gancho chico para que `turbo_confirm` abra un `<dialog>` en
lugar del `confirm()` del navegador.

---

## 5 · Las 48 clases dinámicas

Tailwind escanea texto. Una clase construida así **no la ve y la descarta**:

```haml
%span{ class: "status-chip--#{step.status}" }
```

Hay 48 casos en 24 archivos. **Se resuelven mudándolas a helpers de
presentación, no con un safelist.** Hoy además hay ternarios repetidos en cinco
vistas:

```ruby
run.succeeded? ? 'completed' : (run.failed? ? 'skipped' : 'pending')
```

Un helper que devuelva el nombre completo hace tres cosas a la vez:

1. Tailwind ve la cadena literal y no la descarta.
2. La traducción estado → estilo queda en **un** lugar.
3. Desaparece la duplicación.

Es mejor código que el de hoy, no un rodeo. Los helpers viven en
`app/helpers/`, devuelven la clase completa (`"badge badge-success"`) y **nunca**
la interpolan.

---

## 6 · Orden de migración

Cada paso se mergea solo, con la suite y las capturas en verde.

| # | Paso | Al terminar, la app… |
|---|---|---|
| 1 | Tailwind + DaisyUI entran; Sass sale. Tema con la **paleta actual** | …se ve **idéntica** |
| 2 | Los 48 casos dinámicos pasan a helpers | …se ve idéntica |
| 3 | El tema pasa a «Producto»: tipografías, paleta, tema oscuro | …cambia entera, coherente, con el layout viejo |
| 4 | El shell: layout B con `drawer` y tres regiones | …tiene la estructura nueva en todas las pantallas del desafío |
| 5 | Los 18 partials compartidos | …deja de repetir markup viejo |
| 6 | Pantalla por pantalla, la peor primero (`steps/evaluation`) | |
| 7 | Los 7 componentes Vue (119 clases) | |

**El paso 1 es el punto de control.** Migrar la plomería sin cambiar nada
visual: si algo va a salir mal con esbuild, el CLI o el escaneo de clases, sale
mal ahí, con un diff reversible y con las 30 capturas todavía sirviendo de
referencia.

Los pasos 1 y 2 son mecánicos y verificables por «no cambió nada». Del 3 en
adelante hay criterio y hay que mirar la pantalla.

### La rama, no un worktree

Se evaluó un worktree para poder usar la app actual en paralelo. No conviene: el
stack de Docker, los puertos (3001/5434/6381) y la base sembrada cuelgan de este
directorio, y un worktree necesitaría su propio stack y su propia base. Rama
`rediseno-tailwind`; `git switch master` devuelve la app de hoy en segundos
porque la CSS compilada está gitignoreada.

---

## 7 · Verificación

Todo lo existente sigue sirviendo, porque nada compara píxeles.

| Qué | Cubre |
|---|---|
| `make spec` · 650 ejemplos | Los 7 que miran clases se ajustan en su paso |
| `make screens` · 30 capturas | Error de JS · HTTP ≥ 400 · isla sin montar · formulario anidado · plural en inglés · morphing roto |

**Se suma una revisión nueva a `make screens`:** que ninguna clase quede
descartada por el escaneo de Tailwind.

Concretamente: en cada pantalla del recorrido, para cada elemento que lleve una
clase de una familia conocida (`badge-*`, `btn-*`, `alert-*`, `steps`), se lee
su estilo **computado** y se falla si quedó con el valor por defecto del
navegador —`background-color` transparente en un `badge`, por ejemplo—. Una
clase descartada existe en el HTML y no tiene ninguna regla detrás: en el DOM se
ve bien y en pantalla no, que es exactamente el síntoma de la sección 5 y el que
ninguna otra prueba atrapa.

Cada paso se verifica por mutación donde tenga sentido, como el resto del repo.

---

## Fuera de alcance

No se toca el dominio, ni las policies, ni el motor del pipeline, ni la capa de
IA. Es markup, CSS y helpers de presentación.

Tampoco entra: rediseñar los flujos (qué pantallas existen y qué hace cada una
queda igual), ni accesibilidad más allá de lo que DaisyUI trae, ni internacionalizar.

---

## Decisiones abiertas

1. **¿Tiene innk marca propia —color, tipografía, logo— que esto deba
   respetar?** Sin respuesta al cierre de este diseño. El violeta queda como
   provisorio; por vivir en `--color-primary`, cambiarlo es una línea y arrastra
   botones, chips, foco y links. **No bloquea la implementación.**
