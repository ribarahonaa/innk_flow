# Rediseño, plan 2b: la pantalla del módulo

> **Estado:** implementado en la rama `rediseno-2b`. Selección quedó sin
> referencia: el ranking no se leía en el centro angosto (ver el commit de la
> Tarea 5).

Continúa `2026-09-16-rediseno-2a-vocabulario-design.md`, que es el paso 5 del
spec original (`2026-09-08-rediseno-tailwind-daisyui-design.md`). Esto es el
**paso 6**, «pantalla por pantalla, la peor primero», partido en dos:

| Plan | Paso del spec | Qué |
|---|---|---|
| 2a | 5 | El vocabulario compartido: tarjetas, chips, avisos, tablas. Mergeado |
| **2b** | 6 | **La pantalla del módulo**, en sus dos caras: estructura y `card` |
| 2b-bis | 6 | El resto de las pantallas: solo `card` |
| 2c | 7 | Las islas Vue |

---

## Qué cambió desde el handoff del 2a

El handoff estimaba el 2b como una migración: `.panel` → `card` + `card-body`,
más los pendientes que dejó el 2a. **Le faltaba la mitad del paso.** El spec
original no definía el paso 6 por la tarjeta sino por la arquitectura de
información —«la columna central es lo que se hace; la lateral derecha es lo
que se consulta»—, que es lo que ataca las dos quejas que más dolían: «no se
sabe dónde uno está» y «las pantallas largas son un muro».

La fase 1 construyó la columna de referencia y la pobló **en una sola
pantalla** como prueba del mecanismo, con la nota «el resto va en el plan
siguiente» (`7a843a9`). Medido sobre las capturas de `master`:

- **Selección y reportería** no tienen columna derecha. «Cómo quedó
  configurado» y «El módulo» van apilados arriba del trabajo, con su mismo
  peso.
- **Evolución e idear**, igual; idear además tiene el editor entero del
  formulario entre el progreso y las ideas postuladas.
- **Evaluación** tiene referencia y sigue siendo un muro: «Evaluaciones hechas»
  son quince bloques abiertos, y la pantalla mide 4.239px de alto.

Migrar la tarjeta sin decidir la estructura obliga a tocar cada pantalla dos
veces. Por eso el 2b hace las dos cosas juntas, pantalla por pantalla, y lo que
no es pantalla de módulo pasa al 2b-bis, que es solo la tarjeta.

---

## 1 · Alcance

**2b es la pantalla del módulo** (`StepsController#show`), en sus dos caras:

- la de **ejecución**: `steps/ideation`, `evolution`, `evaluation`,
  `selection`, `reporting`, con sus partials;
- la de **configuración**: `steps/config/<kind>`, con `_modulo`,
  `_criterios_editor`, `_campos_editor` y las asignaciones.

**2b-bis es el resto**, solo `.panel` → `card` + `card-body`: la ficha de la
idea, su alta, edición y diff; la ficha de evaluación (`assessments/new`); los
desafíos (índice, ficha, alta, builder, vista previa); criterios; miembros;
avisos; corridas de IA; selección de empresa; home; errores. `.panel` se borra
al terminar el 2b-bis.

`assessments/new` queda en el 2b-bis aunque sea el trabajo de quien evalúa: no
es la pantalla del módulo, y la línea entre los dos planes es esa.

---

## 2 · Reglas comunes

### Tres zonas en la cara de ejecución

| Zona | Qué va | Regla |
|---|---|---|
| **Centro, arriba** | El trabajo del módulo, y las propuestas de la IA pendientes | Lo que se hace |
| **Referencia** (derecha) | Progreso, lo propio del módulo, quién participa, «Cómo quedó configurado» | Lo que se consulta y no se edita |
| **Centro, al final: «Ajustes del módulo», plegado** | Nombre y modo de IA; edición de asignaciones y pesos; en idear, el editor del formulario | Lo que se edita, pero casi nunca |

La referencia va siempre en ese orden: el progreso primero, porque es lo que
más se mira; la configuración congelada al final, porque no cambia.

Lo que se lee en la referencia y se edita en los ajustes aparece dos veces —la
lista de quién evalúa, leída con sus conteos a la derecha y con sus campos de
peso abajo—. Es a propósito: la fase 1 no mudó las asignaciones porque «una
tarjeta que es toda formulario no se puede partir sin repetir la misma lista»,
y la respuesta es que leer y editar son dos usos distintos de la misma lista.

### Nadie ve nada que hoy no vea

Esto es markup: **no se toca ninguna policy**. Cada bloque se muda con su
guarda puesta. La lista de quién evalúa, aunque ahora sea de lectura, sigue
detrás de `manage_assignments?`; la de quién acompaña, detrás de
`update_pipeline?`; los ajustes del módulo, detrás de `advance?`; el editor
del formulario, detrás de `manage_form?`.

Si a alguien no le toca ningún bloque de los ajustes, **el plegable no se
dibuja**: un «Ajustes del módulo» que se abre vacío es el mismo control
fantasma que la rama de configurar/ejecutar existió para sacar.

Y a quien participa o evalúa la referencia se le achica sola: progreso, lo
propio del módulo y la configuración.

### Cómo se ve una `card` sin repetir utilidades

La `card` de DaisyUI (verificado en `daisyui/components/card.css`, 5.7.28) trae
el radio y `display: flex` en columna, y **nada más**: ni fondo, ni borde, ni
sombra. Su `card-body` pone `padding: var(--card-p, 1.5rem)`,
`font-size: var(--card-fs, .875rem)`, `gap: .5rem` y `.card-body p { flex-grow: 1 }`.

Escribir `card card-border bg-base-100 shadow-sm` en cada vista es la regla del
spec al revés —si aparece en más de dos vistas es un componente—. Así que:

- **una regla en la hoja le da a `.card` la superficie, el borde y la sombra**
  que hoy tiene `.panel`, con los mismos tokens;
- `--card-p` y `--card-fs` se fijan a lo que mide hoy `.panel`: 20px de
  relleno —DaisyUI pone 24— y 14px de letra, que es el `font-size` del `body`
  y coincide con el `.875rem` de DaisyUI. Así el cambio de clase no cambia la
  densidad;
- las vistas escriben `.card` y `.card-body`, y nada más.

El `gap` de `card-body` se suma a los márgenes que ya tienen títulos y
párrafos: eso se ajusta pantalla por pantalla, mirando la captura. El
`p { flex-grow: 1 }` solo estira dentro de tarjetas de alto fijo, y en una
grilla con filas parejas se nota.

### Lo plegable es `<details>`, y el morph no lo cierra

Un `<details>` que abre quien usa la pantalla tiene el `open` puesto **por el
cliente**. Guardar algo adentro —un peso en los ajustes— redirige a la misma
URL, Turbo morfea contra el HTML del servidor, que no trae `open`, y **el
plegable se cierra justo después de guardar**.

Se resuelve en `application.js` escuchando `turbo:before-morph-attribute`
(existe en el Turbo instalado, 8.0.23, y trae `attributeName` y
`mutationType` en el `detail`): si el elemento es un `DETAILS`, el atributo es
`open` y la mutación es `remove`, se cancela. Solo la remoción: un `open` que
agrega el servidor sigue entrando. Es un gancho para todo plegable de la app, y es la
razón por la que todo lo que se pliega es un `<details>` y no un checkbox o un
botón con `hidden`: un solo mecanismo, un solo gancho.

La ficha de la idea ya pliega las rondas cerradas con `<details>`; hoy también
se cierran si algo morfea esa pantalla.

### Las tablas anchas

Con la referencia puesta, a 1440px el centro pasa de unos 1.160px a unos 850.
Toda tabla dentro de una tarjeta va envuelta en un contenedor con
desplazamiento horizontal propio: que la tabla se desplace es mejor que la
página entera.

---

## 3 · Pantalla por pantalla

### Cara de ejecución

| Módulo | Referencia | Centro | Ajustes plegados |
|---|---|---|---|
| **Evaluación** | Progreso · Criterios · Quién evalúa · Cómo quedó configurado | Propuestas · «Ideas a evaluar», con el pedido a la IA como barra arriba de la lista y el desglose por fila | Nombre y modo de IA · asignaciones y pesos |
| **Selección** | — sin referencia: «Cómo se decide» quedó arriba del ranking | Propuestas · Cómo se decide (filtros y corte, con «Editar el set») · Ranking, con el pedido de veredictos como barra arriba · Registro de decisiones | Nombre y modo de IA |
| **Evolución** | Progreso · Quiénes acompañan · Cómo quedó configurado | Propuestas · «Sugerir feedback con IA» · las ideas con su feedback | Nombre y modo de IA · gestores |
| **Idear** | Progreso · El formulario (lista de campos) · Cómo quedó configurado | Propuestas · «Postular una idea» · Ideas postuladas, con «Generar con IA» | Nombre y modo de IA · editor del formulario |
| **Reportería** | Cómo quedó configurado · Descargas | El reporte: resumen narrativo, embudo, ranking, distribución, participación, matriz | Nombre y modo de IA |

**Evaluación va primero** porque es la peor y porque era la única que ya tenía
referencia: se agrega a lo que hay en vez de inventar.

#### El desglose de evaluación

«Evaluaciones hechas» **desaparece como sección**. El detalle de cada
evaluación —quién, versión, nota, comentario, puntaje por criterio, el chip de
desactualizada— pasa a vivir **dentro de la fila de su idea**, que se
despliega.

- Cada idea es un `<details>`. El `summary` es la fila: idea y autor,
  evaluaciones con sus iniciales, puntaje, dispersión.
- **«Evaluar» e «IA» quedan afuera del `summary`**, a la derecha de la fila. Un
  clic en un botón dentro de un `summary` también despliega, y un `button_to`
  es un formulario: adentro de un `summary` es contenido interactivo donde el
  HTML no lo permite.
- La fila se despliega **solo** si `breakdown_visible_for?` lo permite. Si no,
  es una fila común, sin flechita y sin `<details>`: una flechita que abre algo
  vacío es un control que no responde.
- La lista deja de ser `<table>`, porque un `<details>` no puede abarcar una
  fila de tabla. Se arma como grilla con columnas fijas compartidas entre el
  encabezado y las filas, con el aspecto de `table`.
- La pista «las de la IA cuentan igual que las de una persona» pasa arriba de
  la lista, junto a la que ya explica por qué los puntajes se ocultan.

#### Selección y el ancho

El ranking tiene una columna por filtro y una por módulo fuente: siete en el
seed. **Si en 850px no se lee** —la idea partida en tres renglones, los
encabezados de los filtros encimados—, selección se queda sin referencia y
«Cómo se decide» vuelve arriba del ranking. Se decide mirando la captura de la
tarea, no de antemano, y la decisión queda en el commit.

**Resuelto: no se lee.** Medido en «Corte a top 3» (dos filtros y una fuente)
con la referencia puesta: a 1440px el centro quedaba en 888px y la columna
«Idea» en 205px —tres de las cinco ideas en tres renglones—; a 1280px la tabla
pedía scroll horizontal (710px de contenido en 637); y a 1100px `[REFERENCIA]`
fallaba, con el título del módulo en 473px. Selección quedó **sin referencia**
y «Cómo se decide» arriba del ranking (Tarea 5, `96ad0b6`).

#### Reportería no tiene progreso

Su referencia se lleva las **descargas**: generar Excel y PDF, y la lista de
archivos generados. Son herramientas que se usan al costado del reporte, no el
reporte. El pedido del resumen narrativo a la IA se muda al lado de la tarjeta
del resumen, que es donde aparece lo que produce.

#### Idear: el formulario, leído y editado

`_campos_editor` hoy decide las dos cosas —el editor para quien puede, la
lista de lectura para el resto—. En la cara de ejecución se parte: la lista de
lectura va a la referencia **para todos**, y el editor, con su aviso de «ya hay
ideas postuladas», va a los ajustes detrás de `manage_form?`. En la cara de
configuración `_campos_editor` sigue como está.

### Cara de configuración

Una sola columna, en el orden de hoy: el módulo, los criterios o los campos,
las asignaciones, el pie del paso a paso. Todo lo que hay es edición, y lo que
falta configurar ya lo dice el drawer.

Lo que cambia es **juntar lo que está partido**. En `_criterios_editor`, el
encabezado, su descripción, el aviso de «estos criterios son de este módulo» y
el botón «Rehacer los criterios con IA» son hoy cuatro bloques sueltos, dos de
ellos tarjetas con una sola cosa adentro. Pasan a ser **una** `card`.
`_campos_editor` igual.

Las tarjetas **de adentro** de las islas —la barra de «Volver / Guardar set»,
la de la descripción, la de la lista de criterios— son del 2c.

> **Corregido en el 2b-bis.** El markup de tarjeta de las dos islas
> (`pipeline_builder.vue`, `criteria_editor.vue`, cuatro lugares) se llevó ahí
> igual: sin esos cuatro, `.panel` no se podía borrar, que era la promesa de
> este mismo spec. El resto de las islas —comportamiento, el CSS muerto del
> editor de criterios, `.btn-link`— sigue siendo 2c.

---

## 4 · Lo que se arrastra del 2a

### Los seis chips escritos a mano

`version-chip`, `stale-chip`, `here-chip`, `out-chip`, `evaluator-chip` y
`derived-chip` pasan a `badge` vía `EstilosHelper`, como las cuatro familias
del 2a, y entran al muestrario de contraste. `version-chip` también vive en
pantallas del 2b-bis (`criteria_sets/index`, `ideas/_list`): cambia ahí igual,
porque es vocabulario y no pantalla.

`evaluator-chip` es el único que no es una píldora de texto: es un círculo de
20px con iniciales. Se mide si `badge` lo sostiene; si no, queda propio con
nombre semántico y se dice por qué.

### La captura del salteado

Ningún seed tiene un módulo salteado, y el nodo salteado quedó negro en el 2a
sin que nada lo viera. Un desafío en borrador —`sin-formulario`— no puede tener
uno. Entra **un desafío nuevo en el seed, solo para el recorrido**, con un
módulo salteado; no se toca `sin-formulario` ni nada que se use a mano.

### Los dos acoples al color del chip

- El borde por tipo de feedback es `.feedback-item:has(… > .badge-error)`:
  cambiar la variante del chip le cambia el borde a la tarjeta. Pasa a colgar
  de un `data-kind` en el comentario.
- Los puntos de estado del drawer son `.flow-drawer .badge`. Pasan a una clase
  propia.

### `toast` no entra

Por lo mismo que en el 2a: no se cierra solo sin JavaScript, y cambiar cómo se
comporta un aviso merece su propio paso.

---

## Fuera de alcance

- `.panel` → `card` fuera de la pantalla del módulo: 2b-bis.
- Las islas Vue, incluidas sus tarjetas internas: 2c. **Corregido en el
  2b-bis:** se llevó las cuatro tarjetas internas (`pipeline_builder.vue`,
  `criteria_editor.vue`) porque sin ellas `.panel` no se podía borrar, que es
  lo que este mismo spec prometía. El resto de las islas —comportamiento, el
  CSS muerto del editor de criterios, `.btn-link`— sigue siendo 2c.
- Policies, dominio, motor, IA: nada. Si algo de esto parece necesitar un
  cambio de permiso, es un hallazgo y se consulta.
- Qué pantallas existen y qué hace cada una: igual que en el spec original.

---

## Orden

Un commit por tarea, con `make spec` y `make screens` en verde:

| # | Tarea | ¿Cambia lo que se ve? |
|---|---|---|
| 1 | Plomería: aspecto de `.card` en la hoja; guardas y reglas que aceptan `.card`; gancho del `<details>` con su guarda; contenedor de tablas | No |
| 2 | Los seis chips a `badge` | Poco |
| 3 | **Evaluación**: referencia completa, desglose por fila, ajustes plegados | Mucho |
| 4 | Selección | Sí |
| 5 | Evolución | Sí |
| 6 | Idear | Sí |
| 7 | Reportería | Sí |
| 8 | Las cinco caras de configuración | Poco |
| 9 | Captura del salteado y los dos desacoples | No |
| 10 | Cierre: CSS muerto, `CLAUDE.md`, revisión final de la rama | No |

La plomería va primero por lo mismo que el renombre del 2a: es la que se
verifica por «no cambió nada» y deja las guardas mirando `.card` **antes** de
que exista la primera. Los chips van antes que las pantallas porque las cinco
los usan.

---

## Verificación

### Lo que ya existe, ajustado en la tarea 1

Tres cosas miran `.panel` y pasarían en verde sin probar nada:

- `[RITMO]` en `script/capture_screens.js` (`.app-main > .panel`) y la lista de
  familias de `[CLASES]`: pasan a mirar `.card` también.
- El muestrario de contraste se inyecta en una `.panel`: acepta las dos.
- Las reglas de la hoja que cuelgan de `.panel` desde afuera —`.app-main >
  .panel p:not([class])`, `.muted`, `.field-hint`— necesitan su par con
  `.card`. Es la trampa de «renombrar deja muertas en silencio las reglas que
  la usaban desde afuera»: la tarea busca `.panel` en selectores compuestos,
  descendientes y `:has()`, y en los localizadores de las capturas.

### Guardas nuevas en `make screens`

- **El plegable sobrevive al morph.** Abre un `<details>`, provoca un morph de
  la misma forma que `revisarMorphing`, y falla si quedó cerrado. Se escribe
  contra las rondas cerradas de la ficha de la idea, que ya existen, y **se la
  ve fallar sin el gancho** antes de darla por buena.
- **La pasada oscura recorre las pantallas de módulo.** Hoy son cuatro
  pantallas y ninguna es de un módulo. Suma evaluación, selección, evolución y
  reportería.
- La captura del salteado (tarea 9).

### Request specs: nadie ve nada nuevo

Por módulo y por rol —quien administra, quien evalúa, quien participa—, qué
hay en la referencia y qué hay en los ajustes. Mudar un bloque no puede
sacarlo de atrás de su guarda, y un spec que solo mira a quien administra no
lo ve.

### A mano

- **Las capturas de antes y de después, pantalla por pantalla, en los dos
  temas.** Nada compara píxeles.
- **`Flow::Setup` en la tarea 8.** Tocar las caras de configuración puede
  dejar una sin su `setup_nav`, y la suite ya demostró dos veces que no lo
  nota (`2029528`, `df0681d`). Se revisa que las cinco lo sigan dibujando.

### `CLAUDE.md`

Se actualiza en el commit que vuelve falsa cada frase: la regla de las tres
zonas, el gancho del `<details>`, los chips que ya no están escritos a mano,
que `card` deja de no usarla nadie.

---

## Riesgos

- **El ancho del centro** con la referencia puesta. Selección tiene salida
  declarada; reportería y su matriz dependen del contenedor con
  desplazamiento.
- **`card-body` es flex en columna.** Cada hijo directo pasa a ser un ítem
  flex: un `%span` suelto se estira a lo ancho, los márgenes no colapsan y
  se suman al `gap`. Es lo que más puede estirar cada tarea.
- **Una isla montada adentro de un plegable cerrado** (el editor del
  formulario en idear): monta igual, pero sin caja. `make screens` falla con
  `.island-placeholder` sin montar; lo que hay que confirmar es que las guardas
  de contraste y de clases no midan cero y den verde por no ver nada.
- **El gancho del `<details>` cancela también un cierre que manda el
  servidor**: un `<details>` que el servidor deja de dibujar abierto se queda
  abierto. Hoy ninguna pantalla lo hace; si alguna lo necesita, el gancho se
  acota con un atributo.

---

## Decisiones abiertas

1. **La marca de innk**, que sigue abierta desde el spec original y sigue sin
   bloquear.
2. **Selección con o sin referencia**, que se decide en su tarea mirando la
   captura (§3).
