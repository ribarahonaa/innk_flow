# Rediseño, plan 2b-bis: el resto de la app

`.panel` → `card` + `card-body` en las 24 vistas que quedaron fuera del 2b, más
el markup de tarjeta de las dos islas Vue. Al terminar, `.panel` no existe.

Es un **cambio de vocabulario, no de diseño**: las zonas, la jerarquía y la
densidad de estas pantallas quedan como están. Lo único que se ajusta es el
espaciado que el cambio de clase mueve por sí solo.

Leé primero `2026-09-17-rediseno-2b-pantallas-de-modulo-design.md`: la plomería
que este plan usa —el aspecto de `.card` en la hoja, los ajustes de
`card-body`, la guarda `[CARD]`— se construyó ahí y acá no se toca.

---

## Qué cambió desde el spec del 2b

El 2b declaró el alcance del 2b-bis y prometió que **`.panel` se borra al
terminarlo**. Medido antes de escribir este plan, eso no se podía cumplir: las
dos islas Vue emiten `.panel` en cuatro lugares
(`pipeline_builder.vue:4` y `:38`, `criteria_editor.vue:11` y `:22`), y las
islas son el plan 2c.

**Decisión: el 2b-bis se lleva esos cuatro.** Sólo el markup de tarjeta; el
comportamiento, el CSS muerto del editor de criterios y `.btn-link` siguen
siendo 2c. Así la promesa del 2b se cumple y `.panel` muere acá.

El otro hallazgo del relevamiento es que **un tercio de la migración está fuera
de cámara**: ocho de las 24 vistas no tienen ninguna captura, así que ninguna
guarda del recorrido las mira. Se resuelve en la tarea 1.

---

## 1 · Alcance

**Entra:** las 42 apariciones de `.panel` en 24 vistas HAML, más las 4 de las
dos islas. Total 46.

| Familia | Vistas | `.panel` |
|---|---|---|
| Sistema | `errors/forbidden`, `errors/not_found`, `pages/home`, `sessions/select_company`, `notifications/index`, `shared/_setup_outline` | 6 |
| Ideas | `ideas/index` (2), `show` (4), `new`, `edit`, `diff` (2), `_contributors` | 11 |
| Desafíos | `challenges/index`, `show` (2), `new`, `builder` (3), `previews/show` (2) | 9 |
| Criterios, IA y miembros | `criteria_sets/index` (2), `show`, `_form`, `ai_runs/index`, `ai_runs/show` (3), `memberships/index` (3) | 11 |
| Ficha de evaluación | `assessments/new` | 5 |
| Islas | `pipeline_builder.vue` (2), `criteria_editor.vue` (2) | 4 |

`assessments/new` está acá y no en el 2b aunque sea el trabajo de quien evalúa:
no es la pantalla del módulo, y ésa es la línea entre los dos planes.

**No entra:** policies, dominio, motor, IA. Tampoco rediseño de estas
pantallas. Si algo parece necesitar un cambio de permiso, es un hallazgo y se
consulta.

---

## 2 · Reglas comunes

### La plomería ya existe y no se toca

El 2b dejó en la hoja la regla que le da a `.card` la superficie, el borde, el
radio y la sombra de `.panel`, con `--card-p: 20px` y `--card-fs: 14px` —lo que
mide `.panel`— para que el cambio de clase no cambie la densidad. Las vistas
escriben `.card` > `.card-body` y nada más: `card card-border bg-base-100
shadow-sm` en cada vista sería la regla de los componentes al revés.

También existen ya los cinco ajustes `.card-body > …` que el 2b necesitó.

### El `gap` de `card-body` mueve el espaciado

`card-body` es flex en columna con `gap: 8px`, y **en flex los márgenes no
colapsan**: el de abajo de un título, el gap y el de arriba de lo que sigue se
suman. En `.panel` —bloque— colapsaban. Así que «no cambia nada» no existe del
todo: cada pantalla se mira en su captura y se le descuenta a los márgenes lo
que el gap ya pone.

**Si un patrón aparece en más de dos vistas, va como regla `.card-body > X` en
la hoja**, no como utilidades sueltas repetidas. Es la misma regla de las tres
capas.

### Los hallazgos no entran al plan

El 2b terminó con cinco arreglos que no eran del rediseño —tres fugas de
lectura y dos controles fantasma— y cada uno fue un commit propio, con decisión
explícita. Acá vale lo mismo: cualquier cosa que aparezca mirando 24 pantallas
se anota, se consulta y se decide aparte. Lo que este plan cambia es la clase y
el espaciado.

---

## 3 · Las ocho pantallas sin captura (tarea 1)

Ninguna guarda del recorrido mira hoy `ai_runs/show`, `criteria_sets/show`,
`errors/forbidden`, `errors/not_found`, `ideas/edit`, `ideas/new`, `pages/home`
ni `sessions/select_company`. (`10b-criteria-editor` es `edit`, no `show`;
`/admin/ai_runs` es el índice, no la ficha.)

Las capturas van **antes** de tocar una clase y tienen que dar verde con
`.panel` todavía puesto: así se prueba que la captura funciona, no que la
migración funcionó. Es la lección de `2029528`, donde `make spec` y
`make screens` quedaron en verde con una pantalla rota porque ninguna aserción
la miraba.

| Captura | Cómo se llega |
|---|---|
| `pages/home` | `/` como admin |
| `ai_runs/show` | clic en una fila de `/admin/ai_runs` |
| `criteria_sets/show` | clic en el nombre de un set, no en «Editar» |
| `ideas/new` | «Postular una idea» desde la lista |
| `ideas/edit` | «Editar» en la ficha de una idea |
| `sessions/select_company` | login como `multi@demo.test`, que el seed deja con dos membresías |
| `errors/forbidden` | `part1@demo.test` en `/challenges/merma-bodega/builder` |
| `errors/not_found` | `/challenges/no-existe` |

Tres consecuencias de forma:

- **El 403 tiene que ser uno legítimo.** `ChallengePolicy#builder?` es
  `manager?`, y quien participa **sí** ve el desafío, así que el builder le da
  403 y no 404: es exactamente el caso que CLAUDE.md describe como correcto.
  Un 403 sobre algo que no se debería ver sería un oráculo de existencia, y
  fotografiarlo sería fotografiar un bug.
- **El recorrido falla hoy con CUALQUIER respuesta >= 400**
  (`page.on('response')`). Las dos pantallas de error tienen que declarar el
  estado que esperan, y si llega otro sigue fallando. Aflojar la regla a «>=
  400 se ignora» volvería ciega la corrida entera.
- Las tres últimas piden **otra sesión**, así que van en un bloque al final de
  la pasada clara, después de que el recorrido como admin terminó.

---

## 4 · Orden

Un commit por tarea, con `make spec` y `make screens` en verde.

| # | Tarea | Vistas | `.panel` | ¿Cambia lo que se ve? |
|---|---|---|---|---|
| 1 | Las ocho capturas | — | 0 | No |
| 2 | Sistema | 6 | 6 | Poco |
| 3 | Ideas | 6 | 11 | Sí |
| 4 | Desafíos | 5 | 9 | Sí |
| 5 | Criterios, IA y miembros | 6 | 11 | Sí |
| 6 | Ficha de evaluación | 1 | 5 | Sí |
| 7 | Las dos islas | 2 | 4 | Sí |
| 8 | Cierre | — | — | No |

La 2 va primera porque son seis pantallas chicas y de una tarjeta: ahí se
calibra el ajuste de espaciado barato, antes de aplicarlo a una familia entera.
La 6 va sola porque concentra cinco usos en la pantalla más densa. La 7 va
antes del cierre porque borrar `.panel` exige cero usos.

---

## 5 · Verificación

### No hay request specs nuevos

Esto no cambia qué se sirve ni quién lo ve, y un request spec no mira CSS. La
verificación es el recorrido.

`make spec` tiene que seguir verde igual: los ocho asertos de `.panel` que hay
en `spec/requests/pantalla_del_modulo_spec.rb` esperan **cero** y lo van a
seguir haciendo. Ningún spec se apoya en que la clase exista.

### Las guardas que ya miran estas pantallas

Con las ocho capturas sumadas, las 24 vistas quedan cubiertas por
`[PANEL]` (una `card` sin `card-body`), `[CLASES]`, `[RITMO]` y `[CONTRASTE]`,
más `[CARD]`, que vigila la paridad hasta la tarea 8.

### Las seis menciones de `.panel` en `script/capture_screens.js`

No se tratan igual, y confundirlas deja guardas muertas en silencio. Los
números de línea son los de hoy (`00fb1b3`) y se mueven; lo que identifica cada
una es la guarda:

| Línea | Qué es | Qué se hace |
|---|---|---|
| 534-566 | `[CARD]`: inyecta un `.panel` y una `card` y compara seis propiedades computadas | **Se borra.** Sin `.panel` no hay contra qué comparar |
| 204 | `[CLASES]`: `.panel` está en su lista de selectores | **Se queda.** Es lo que caza un `.panel` reintroducido: sin regla detrás queda sin fondo, sin relleno y sin borde, que es justo lo que esa guarda marca |
| 139 | `[RITMO]`: `.app-main > .panel, .app-main > .card` | Se le saca la mitad `.panel`, que queda muerta |
| 486 | Destino del muestrario: `.card-body \|\| .panel \|\| .app-main` | Ídem |
| 245 | Mensaje de `[PANEL]`: «tienen que ser `panel`» | **Se reescribe.** Después de esto, una `card` sin `card-body` es un error de maquetado, no una tarjeta sin migrar |

`[CARD]` era andamio: existía para que la `card` no se desviara del `.panel`
mientras convivían. `[CLASES]` es su reemplazo y ya está escrito.

### Qué se borra de la hoja

La regla `.panel` y los tres selectores compuestos
`.app-main > .panel p:not([class])`, `.muted` y `.field-hint`. Los `.card`
equivalentes ya existen al lado, así que la prosa sigue con su medida.

### Los documentos

- **CLAUDE.md**: tres pasajes hablan de `.panel` como vocabulario vivo —la
  sección del sistema visual, la guarda `[CARD]` y «el resto de la app sigue en
  `.panel`: ésas son 2b-bis»—. Los tres se actualizan en la tarea 8.
- **El spec del 2b**: su línea de alcance dice que las islas son 2c. La
  decisión de este plan la cambia para los cuatro `.panel`, y se anota ahí.

### A mano

Mirar las capturas. Es lo único que no hace una máquina, y en un plan que sólo
cambia cómo se ve es la verificación principal, no un extra.

---

## Fuera de alcance

- Las islas Vue más allá de su markup de tarjeta: comportamiento, props, CSS
  muerto del editor de criterios (`checks-help`, `inline-label`, `.btn-link`,
  que ya tienen **cero** usos) — todo eso es 2c.
- Rediseñar alguna de estas pantallas como el 2b rediseñó las de módulo. Si
  `ideas/show` o `pages/home` lo piden, es otro plan del tamaño del 2b.
- Policies, dominio, motor, IA.

---

## Riesgos

- **El `p { flex-grow: 1 }` de DaisyUI dentro de tarjetas hermanas.** Sólo
  estira en tarjetas de alto fijo, y `challenges/index` e `ideas/index` listan
  tarjetas hermanas en grilla. Si aparece, se resuelve con una regla en la
  hoja, no con utilidades por vista.
- **Las dos islas son otro lenguaje.** Un `.panel` en un `.vue` no es lo mismo
  que en HAML: Tailwind escanea `app/javascript` igual, pero el componente
  puede tener CSS propio colgado de esa clase. Antes de renombrar, buscar la
  clase en selectores compuestos, descendientes y `:has()` — es la trampa que
  el 2a ya pagó dos veces.
- **`[CLASES]` es ciega a un renombre consistente.** Si la clase y su regla se
  renombran juntas no dice nada. Por eso el borrado de `.panel` va en la tarea
  8 y no antes: mientras exista, `[CARD]` compara.

---

## Decisiones tomadas

1. **Las islas entran**, sólo su markup de tarjeta, para que `.panel` muera acá
   como el 2b prometió.
2. **Las ocho capturas van primero**, verdes con `.panel` puesto.
3. **Swap más espaciado**; todo otro hallazgo se consulta y va en commit
   propio.
4. **`[CARD]` no se reemplaza**: era andamio, y `[CLASES]` ya cubre el caso.
