# Handoff

## Objetivo

Dos cosas, las dos terminadas y mergeadas.

**Los siete menores** que la revisión final del plan 2b dejó pasar: guardas que
no podían fallar, un N+1, una regla de rol escrita en una vista, niveles de
título desparejos.

**El plan 2b-bis del rediseño**: el resto de la app de la clase propia `.panel`
al `card` de DaisyUI —42 tarjetas en 23 vistas HAML y 4 en dos islas Vue— y
después borrar la regla, sus tres selectores compuestos y la guarda `[CARD]`.
`.panel` ya no existe.

## Estado actual

- **Todo mergeado y pusheado.** `master` y `origin/master` están en `eec32c9`.
  Dos integraciones `--no-ff`: `00fb1b3` (los menores) y `eec32c9` (el 2b-bis).
  En los dos casos el árbol del merge quedó idéntico al de la rama verificada.
- **Verificación, corrida por el controller y no sólo reportada:**
  `make spec` 919 ejemplos 0 fallas · `make screens` **62 capturas**, sin
  errores de JS ni respuestas >= 400.
- El recorrido pasó de 52 capturas a 62. **Nueve pantallas no tenían ninguna**,
  y dos de ellas lo destaparon recién al ir a usarlas.
- `.panel` no queda en vistas, islas, hoja ni builds. Lo único que sobrevive
  son comentarios históricos de `application.css`, conservados a propósito.
- **Todas las ramas mergeadas están borradas**, local y remoto: queda sólo
  `master` en los dos lados. Se verificó una por una antes de tocarlas —las
  locales con `git branch --merged master`, las remotas comprobando que su
  punta fuera ancestro de `master`—. El `ls-remote` destapó tres que ningún
  handoff listaba (`menores-2b`, `rediseno-2b`, `rediseno-2b-bis` también
  existían en `origin`); también estaban mergeadas y se fueron.
- **El borrado de ramas remotas ya funciona.** El handoff anterior decía que lo
  bloqueaba el filtro de permisos; esta vez pasó sin problema.

### Hechos del entorno que muerden

- El push por SSH no anda. Va por HTTPS con el token de `gh`:
  `git -c credential.helper= -c credential.helper='!gh auth git-credential' push https://github.com/ribarahonaa/innk_flow.git <ref>`.
  `git fetch` a secas también rebota: hay que darle la URL HTTPS igual.
- **El contenedor `app` no recompila CSS ni JS solo:** `make yarn-build` antes
  de `make screens` siempre que se toque la hoja o una isla.
- **Nunca un worktree para ejecutar planes acá.** `docker-compose.yml` monta
  `.` en `/rails`, así que `make spec` y `make screens` corren SIEMPRE contra
  el checkout principal: un worktree verificaría el árbol equivocado y daría
  verde sobre código que no es el editado.
- **Dos corridas de `make screens` en paralelo se pisan.** Borra y reescribe
  `tmp/screenshots/` entero al arrancar. Ya arruinó una verificación: un
  revisor se quedó a mitad de comparar capturas porque otra tarea empezó a
  reescribirle el directorio.
- `make seed` siembra ahora **tres** desafíos que existen sólo para el
  recorrido: `sin-formulario`, `con-salteado` y `comite-abierto`.

## Archivos y cambios

**Los siete menores** (rama `menores-2b`, merge `00fb1b3`)

- `da3edda` — la pasada oscura abre los plegables. **El menor no existía**: las
  guardas ya medían adentro de un `<details>` cerrado. Quedó el cambio por la
  foto, y se corrigió el comentario falso que también estaba en la pasada clara.
- `be86ee4` — cada módulo del recorrido cae en exactamente una lista de
  `MODULOS_*`. Antes, renombrar uno lo sacaba de las dos y sus zonas dejaban de
  chequearse sin que nada lo dijera.
- `f9073e3` — el nivel del título lo pone la zona: `h3` en la referencia, `h2`
  al centro. `.section-title` da tamaño y color por clase, así que el nivel no
  se ve en pantalla: sólo ordena el outline.
- `f04f1bc` — el resumen del plegable sale de las mismas guardas que sus
  bloques. Divergía en UNA pantalla: evolución con el desafío cerrado.
- `dd63a68` — `ve_el_pool` pasa de la vista a `ChallengePolicy#read_pool?`.
- `d0662ea` — **eran dos N+1, uno tapando al otro.** El reportado
  (`assessment.stale?`) medía cero consultas propias porque el caché del
  request se las comía; el de abajo era la lista de pendientes sin `includes`.
  Cuatro filas pasaron de 6 consultas a `ideas` a 2.
- `98f931d` — la referencia de reportería sigue el orden que CLAUDE.md declara.

**El 2b-bis** (rama `rediseno-2b-bis`, merge `eec32c9`, 19 commits)

- `315be1c` `f544454` — spec y plan.
- `d0fb7bd` `f182f45` — las capturas que faltaban, y sacar `13-home`.
- `fb3f6ff` `c461304` `cd97eb8` `40e9a82` `4edf290` `1655f06` — las seis tandas
  del swap: sistema, ideas, desafíos, criterios/IA/miembros, ficha de
  evaluación, islas.
- `62084ff` — **se borra `pages/home.html.haml` y su controller.** Era
  inalcanzable: `routes.rb:113` es `root "challenges#index"` y nada ruteaba a
  `PagesController#home`. `skip_pundit?` lo nombraba, así que borrarlo sin
  tocar esa línea reventaba con `NameError`.
- `1413414` — `comite-abierto`, fixture de un solo propósito.
- `c69faad` — se borra `.panel`: la regla, sus tres selectores compuestos y
  `[CARD]`.
- `880c874` — los seis hallazgos de la revisión final de la rama.
- `c8afc0f` — el seed duplicaba «Filtros de pase a comité» en cada corrida.

**Lo que no era el swap y salió al hacerlo**

- El `%td: %code=` de `criteria_sets/show:20` era sintaxis de **Slim**, no de
  HAML: salía `<td:>%code= criterion.key</td:>` y la columna «Clave» mostraba
  el literal. Arreglado en la tanda que migraba esa vista.
- El seed duplicaba un set de biblioteca: la línea 96 tenía su `destroy_all` y
  la 130 no.

## Intentos fallidos

**Lo que se creyó y no era.** Vale la pena leer esta sección entera: el patrón
se repitió seis veces.

- **El menor de los plegables no existía.** Un `<details>` cerrado NO le saca la
  caja a sus descendientes en Chromium, así que `medirContraste` y
  `revisarClasesDescartadas` ya medían adentro. Comprobado de dos formas: 138 y
  37 elementos con caja adentro del desglose y de los ajustes, idénticos
  abierto y cerrado en los dos temas; y un `.badge` de 1,20:1 metido adentro,
  que `[CONTRASTE]` reportó en seis pantallas **incluidas las que lo tienen
  cerrado**.
- **Tres reportes seguidos acertaron la conclusión y erraron la razón**, y dos
  de esas razones falsas quedaron grabadas en mensajes de commit (`c461304`).
  La correcta, medida: el `p { flex-grow: 1 }` de `card-body` sólo estira
  cuando el contenedor **tiene espacio sobrante que repartir**. Y hay DOS
  grillas de tarjetas que se comportan distinto: en `challenges/index` las
  tarjetas llevan `.challenge-card` con `display: block` **sin capa**, que le
  gana al flex de DaisyUI; en `criteria_sets/index` son `.card` a secas y el
  sobrante sí se reparte adentro. Está escrito en la hoja.
- **La tabla de cobertura del spec se armó leyendo NOMBRES de captura**, no a
  qué URL va cada una. Costó dos defectos: `13-home` fotografiaba el índice de
  desafíos (mismo md5 que `02-challenges`) y `09-11-panel-evaluacion` es la
  pantalla del módulo, no `assessments/new`. Las dos las destaparon las tareas
  al ir a usarlas.
- **`.panel` se escribe de DOS formas** y todos los conteos del plan veían una:
  la abreviatura de HAML y el atributo de cadena
  (`class: "panel challenge-card"`). Lo grave no era el conteo: el paso que
  autorizaba el borrado de la regla usaba ese mismo grep. El que sirve:
  `grep -rnE '(\.panel\b|class[:=].*"[^"]*\bpanel\b)'`.
- **`.empty-state` dentro de un `card-body` flex desarma la pantalla.** Medido:
  el botón pasó de 147px a **1350px** de ancho y el hueco título→texto de 17 a
  39px. Ninguna captura miraba las cinco pantallas vacías. Se arregla con
  `.card-body.empty-state { display: block; }` y ahora hay dos capturas.
- **Una regla por elemento alcanza más de lo que su comentario dice.**
  `.card-body > h1` es (0,1,1) y `.page-title` (0,1,0): le ganaba y le comía
  4px a tres vistas más de las declaradas. Acotada con `:not([class])`.

**Datos del seed que bloquearon capturas, y cómo se resolvieron**

- `sin-formulario` tiene **cero ideas**: no sirve para fotografiar `ideas/new`
  ni `ideas/edit`. Se usa `merma-bodega`, que es el del recorrido.
- En `merma-bodega` la postulación está `completed`, así que **no existe el
  link «Postular una idea»** — se va por `goto` con guarda.
- **Ningún desafío sembrado dejaba un módulo de evaluación `activo`**, y el
  link «Evaluar» lo exige además de la policy. Por eso se sembró
  `comite-abierto`.
- `sessions#destroy` no está en las excepciones de `require_company`, así que
  cerrar sesión de una cuenta multiempresa **rebota en `/select_company`**.

**Lo que se perdió al borrar `[CARD]`, y no se reemplazó del todo.** `[CLASES]`
caza un `.panel` reintroducido —se lo vio fallar— pero marca un elemento sólo
si no tiene fondo **Y** no tiene relleno **Y** no tiene borde, y en un `.card`
el relleno es siempre 0 porque vive en el `card-body`. `[CARD]` era lo único
que medía el **aspecto**: los 20px de `--card-p`, los 14px de `--card-fs` y la
sombra. Hoy nada vigila que DaisyUI no recupere sus 24px por default.

## Próximos pasos

1. **Mirar las 62 capturas.** Es lo único de los dos planes que no hizo una
   máquina. Las nuevas: `14-ai-run`, `15-criteria-set`, `16-idea-new`,
   `17-idea-edit`, `18-select-company`, `18b-desafios-vacio`,
   `18c-criterios-vacio`, `19-forbidden`, `20-not-found`, `21-evaluar-idea`.
2. **Plan 2c: las islas Vue.** Es lo que queda del rediseño. El CSS muerto que
   espera ahí ya está confirmado con **cero** usos: `checks-help`,
   `inline-label` y `.btn-link`; `.criterion-row*` sólo aparece como nombre de
   componente Vue, no como clase.
3. **Dos hallazgos sin decidir**, los dos anotados y sin tocar:
   - **`criteria_sets#show` es una pantalla huérfana**: nada en la app la
     linkea. O se linkea desde el índice, o se borra.
   - **Evolución hace 3 consultas a `ideas`** con una sola idea sembrada
     (`evolution.html.haml:15` y `:22`). No se determinó si escala: haría falta
     un seteo de varias ideas prearranque.
4. **Evolución no tiene encabezados en el centro**: el título de cada tarjeta
   de feedback es un `link_to` con clase propia, no un `h2`. Misma familia que
   el menor de los niveles de título, otra pantalla.
5. **Tres temas de seguridad preexistentes, sin arreglar** (vienen de handoffs
   anteriores y no se verificaron en esta sesión): la sesión de quien perdió la
   membresía sigue viva; los links de adjuntos de Active Storage no vencen y
   quedan fuera de Pundit; se puede asignar a evaluar a alguien con rol
   `participant` por POST directo.
**Decisiones de Raúl en esta sesión**

- `ve_el_pool` pasa a un predicado nuevo (`read_pool?`) y **no** se reusa
  `curate_pool?`: leer un resumen no decide nada, y quien evalúa ve el pool
  entero.
- `pages/home.html.haml` se **borra** por inalcanzable, no se migra a ciegas.
- El bug del `%td:` se arregla en la tanda que migra esa vista, no antes.
- `comite-abierto` queda como fixture sembrada.
- El commit de cierre va **antes** del merge, para que la regresión medida de
  las pantallas vacías no entre a `master`.
