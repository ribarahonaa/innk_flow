# Handoff

## Objetivo

Cerrar el eje «el estado del dominio se dibuja de una sola forma». Quedaba la
cuarta forma: la cabecera del drawer lo mostraba como **texto plano** y no como
chip. Al terminar es un chip, legible sobre el panel oscuro en los dos temas y
medido por una guarda.

Con esto **el repaso de las 66 capturas queda sin inconsistencias sistémicas
abiertas.**

## Estado actual

- **`master` está en `1a1779e` y está pusheado.** Verificado con `gh api` y no
  con `git rev-parse origin/master`, que lee una foto local. Sin ramas vivas,
  árbol limpio.
- **`make spec` → 1125 ejemplos, 0 fallas** y **`make screens` → 66 capturas,
  0 errores**.
- El árbol del merge es idéntico al de la rama.
- El stack quedó levantado. La base no se tocó.

### Decisiones de Raúl en esta sesión

Tres tandas, las tres con el mismo formato: diseño corto en el chat (bounded,
sin spec ni plan en `docs/`), ejecución nativa, revisión de rama al final, merge
`--no-ff` a master y push, sin PR.

1. **Los dos contadores.** Alcance angosto elegido explícitamente: sólo los dos
   conteos sin sustantivo.
2. **El monospace.** «dale, avisame cuando termine» — autonomía de punta a
   punta, merge incluido.
3. **El chip del drawer.** Diseño con números medidos antes de aprobar.

## Archivos y cambios

Tres merges: `9bee362` (contadores), `5e5ce7a` (monospace), `1a1779e` (chip del
drawer).

### `9bee362` — Los contadores dicen qué cuentan

`challenges/show`: la tarjeta «Flujo» da la **posición** del módulo en curso
(«ahora: X · módulo 7 de 7»), sacada del **índice** y no de `position`, que es
`decimal(20,10)` y queda fraccionario al insertar. `_flow_drawer`: el contador
suma «listos», que convivía con el «Paso 3 de 9» del pie.

### `5e5ce7a` — Monoespaciada para código, no para prosa

`.field-list__type` pierde la mono: es la columna de VALOR de una lista
etiqueta/valor y nueve vistas le mandan prosa, rótulos y números. El desglose de
evaluación deja de mostrar la **clave** del criterio y muestra el nombre y el
orden que el módulo congeló en su **snapshot**, que es de donde los toma la
tarjeta «Criterios» de la misma pantalla. Guarda **`[MONO]`**.

### `1a1779e` — El estado del desafío en el drawer es un chip

El chip toma el color del estado **aclarado hacia el texto del panel** —el
mecanismo de los puntos, con otro porcentaje— y va **fuera** de
`.flow-drawer__meta`, que tiene `opacity: .75`. Guarda **`[ESTADO-DRAWER]`** más
un spec que ata sus variantes a `Challenge::STATUSES`.

Números, todos medidos contra la app: sin tratar, en tema **claro**, el neutro
da **1,00:1** y el acento 2,80. Tratados: 8,30 y 5,61 en claro, 9,43 y 7,93 en
oscuro. La mezcla de los puntos (40/55) daría 3,59 y 4,77 — el neutro no llega
al 4,5 de un texto, y el piso de los puntos es 3:1 porque no son texto. La
pastilla sale sola, porque `badge-soft` deriva relleno y borde de
`currentColor`.

## Intentos fallidos

**El patrón de la sesión, en las tres tandas: el hallazgo más caro salió de la
revisión de rama, y casi siempre fue una guarda propia declarada probada.**
Seis guardas que no probaban nada, cada una por un mecanismo distinto:

- **Subcadena.** «1 de 3 listo» está contenido en «1 de 3 listos», así que el
  único caso que probaba la concordancia sobrevivía a concordar con el TOTAL.
- **Fixture sin variación.** Con posiciones 1, 2 y 3 el índice y `position` dan
  el mismo número. La fixture usa **2,5**, que es lo que deja `(a+b)/2`.
- **Caché de consultas.** El test del N+1 pasó apenas escrito y NO porque no
  hubiera N+1: los cuatro puntajes apuntaban al **mismo** criterio, así que
  Rails resolvía las lecturas siguientes y `consultas_a` las saltea por
  `payload[:cached]`. **Un ejemplo de N+1 con un solo padre no prueba nada.**
- **Afirmaciones que el código viejo ya cumplía.** «2 de 2 · flujo terminado»
  contiene «flujo terminado» y no contiene «sin empezar».
- **Contar iteraciones en vez de mediciones.** `[ESTADO-DRAWER]` comparaba
  `medidos.length` con `VARIANTES.length`, y `medidos` se llenaba una vez por
  iteración: inalcanzable. Con el arreglo vacío, la guarda entera pasaba sin
  medir nada. Va contra un **literal**, como `esperados` en `revisarPuntos`.
- **`undefined` que atraviesa los filtros.** `medirContraste` devuelve lista
  vacía para lo que no se ve, `const [m] = ...` daba `undefined`, y
  `undefined < 4.5` es `false`: un chip oculto dejaba la guarda en verde.

**Y dos guardas medían sólo la mitad de lo que decían:**

- `[MONO]` pedía un **espacio** para considerar algo prosa, así que no veía los
  números —«40%» no tiene ninguno— y el requerimiento los nombraba. Ahora pide
  que el texto propio sea un identificador pelado. Con la regla vieja marcaba 13
  pantallas; con la nueva, 15.
- **Una sola mutación no alcanza para una guarda de dos temas.** Sacarle el
  tratamiento de color al chip dispara `[ESTADO-DRAWER]` en claro y **no en
  oscuro**, porque ahí el chip sin tratar se lee bien. La mitad oscura seguía
  sin verse fallar hasta una segunda mutación (el color del propio panel).

**La regla que quedó: verificar mutando el código y viendo fallar el caso. Y
cuando la guarda cubre dos ejes —dos temas, dos variantes—, una mutación por
eje.**

### Dos veces agregué algo y lo justifiqué mal

- **Código muerto con una ruta falsa.** El sufijo «N módulos sin empezar» no lo
  produce nada —`close!` no toca los pasos, `advance!` activa el siguiente o
  cierra en la misma transacción, y saltear el módulo activo no lo ofrece
  ninguna vista— y mi comentario decía que lo producía `close!`. Se fue, y con
  él los dos únicos identificadores nuevos en español.
- **Dos fuentes de verdad.** El desglose leía el nombre del criterio de la fila
  **viva** de `Criterion`; la tarjeta «Criterios» de la misma pantalla lo lee
  del **snapshot** congelado. El nombre es editable con el módulo en curso, así
  que podían discrepar, y el orden alfabético por clave dejaba los mismos tres
  criterios al revés que en la tarjeta de al lado.

### Un comentario que declaraba ciega a una guarda que no lo es

Escribí que `[CONTRASTE]` «mide lo que hay, no dónde está» para justificar el
spec del chip fuera del bloque atenuado. **Es falso:** `medirContraste` compone
la opacidad de los ancestros a propósito, y `[PASTILLA]` tiene un caso de
autotest para eso. Meter el chip de vuelta adentro lo hace fallar igual
(3,75:1). El spec es el detector rápido, no el único. Corregido en el
comentario y en el mensaje del commit.

### Cosas del entorno

- **Los dos primeros commits salieron con `Co-Authored-By`**, que en este repo
  no va. No estaban pusheados: se reescribieron con
  `git filter-branch --msg-filter` sobre `master..HEAD`. El harness la inyecta
  por system-reminder en CADA sesión; hay que cortarla a mano cada vez.
- **`git merge -F -` no lee de stdin** («could not read file '-'»). El mensaje
  va a un archivo primero. `git commit -F -` sí funciona.
- **Después de tocar el CSS: `make yarn-build` ANTES de `make screens`**, o la
  guarda mide la hoja vieja. Pasó, y por suerte de rebote fue útil.
- Para corregir el mensaje del último commit con el árbol sucio:
  `git stash push -u` → `git commit --amend -F` → `git stash pop`.

**Lo que funcionó, las tres veces: medir antes de decidir.** El riesgo del
título elipsado a 1023px lo medí en vez de anotarlo (ya venía recortado: 101px
de 157). `[MONO]` se escribió ANTES del arreglo y marcó 13 pantallas, todas la
misma clase, lo que probó que había un solo culpable. Y el chip del drawer se
midió inyectándolo en el panel vivo con Playwright, con diez porcentajes de
mezcla, antes de escribir una línea de CSS: sin eso, copiar la mezcla de los
puntos habría dejado el neutro en 3,59:1.

## Próximos pasos

1. **Cinco defectos preexistentes que destaparon las revisiones**, ninguno
   alcanzable hoy por la interfaz:
   - **`StepsController#skip:114` no puede funcionar.** Hace
     `pipeline.advance! if pipeline.active_step.nil?`, y `advance!` corta con
     `failure(["no hay ningún módulo en curso"])` exactamente cuando
     `active_step` es nil. La ruta existe (`post :skip`) pero **ninguna vista la
     ofrece**. Los módulos salteados de las capturas vienen del seed.
   - **Un desafío cerrado dice «ahora: X · módulo N de M».** La rama se decide
     por «no hay módulo activo» cuando quiere decir «el desafío terminó», y
     `close!` deja el módulo activo. Venía igual con la línea vieja; la forma
     sería preguntar `closed? || archived?`.
   - **`Api::V1::CriteriaSetsController#assign` escribe `criterion.name` ANTES
     del guard de `locked?`**: el nombre de un criterio es editable aunque ya
     tenga evaluaciones. Hoy no rompe nada —desglose y tarjeta leen del
     snapshot— pero el candado no cubre lo que dice cubrir.
   - **`_como_se_decide.html.haml:26` hace `Criterion.find_by(id:)` dentro de un
     `each`**: un N+1 por filtro en la pantalla de selección.
   - **`Flow::Setup#finish_step`: la pista de no-borrador es inalcanzable.**
     `Flow::Setup` sólo se construye con el desafío en borrador, así que el
     `I18n.t("flow.challenge_statuses...")` de esa rama no se renderiza nunca.

2. **Una convención sin decidir:** conviven dos concordancias para la misma
   forma de frase — `ideas/show:114` concuerda el adjetivo con el TOTAL («1 de 3
   comentarios atendidos») y el drawer con la CUENTA («1 de 3 listo»). Las dos
   se defienden en español. Si se quiere una sola regla, el lugar es una línea
   al lado de `Flow::Texto.plural`.

3. **Lo que quedó afuera de las tandas, con el terreno medido:**
   - El **«3 / 2»** de `steps/_celdas_de_evaluacion.html.haml:9` (evaluaciones
     hechas sobre el mínimo, con el numerador capaz de pasar al denominador) y
     el **«N / M»** de `steps/reporting.html.haml:134`.
   - El `min-width: 110px` del criterio del desglose alinea la columna de
     puntajes **sólo mientras cada nombre entre en 110px**; con nombres (más
     largos que las claves) el riesgo es nuevo. El comentario ya lo dice y
     propone la forma (`flex: 0 0 110px` o una grilla de dos columnas).
   - **`[MONO]` no ve prosa partida por un hijo inline**:
     `<span>Impacto<b>·</b>Numérico</span>` junta «ImpactoNumérico», que pasa
     por identificador. `_como_se_decide` tiene esa forma, hoy sin mono.

4. **Lo visual que sigue en pie del repaso de capturas:** `Choose File / No file
   chosen` sin estilo en `16-idea-new`; `18-select-company` con el rol fuera del
   botón y el separador colgando; el popup de espera sin backdrop
   (`09-13-ia-espera`); la previsualización que se repite a sí misma en 5 de 7
   tarjetas; el popup de la IA que dice lo mismo tres veces; el hueco muerto del
   Brief; «Cómo quedó configurado» encabalgado; la columna «Acción» que apila;
   «Armar el flujo con IA» sin controles con el flujo arrancado; «Distribución
   de puntajes» con dos filas de números; «Quién evalúa» duplicado sin el peso.

5. **Los minors diferidos de la revisión de la pastilla**, ninguno urgente:
   `[PASTILLA]` no asegura «midió al menos N» por pantalla; la regla de
   `currentColor` debilita `[CLASES]` para los chips suaves; un borde punteado
   se acredita como pastilla entera; `flow.entry_statuses.skipped` huérfano en
   `es.yml`; los números del comentario de la hoja salen de 7 pantallas y el
   comentario no lo acota; `medirContraste` corre dos veces por pantalla sobre
   `.badge`; y **`.alert` sigue con el 8% de relleno de DaisyUI** — extender
   `[PASTILLA]` a `.alert` es cambiar un selector.

6. **Los menores diferidos del rol gestor** (variable muerta en
   `_referencia_evaluacion.html.haml:8`, `AssessmentPolicy#update?` sin
   cobertura ni llamador vivo, `CriteriaSetPolicy#update?` con
   `owner_step: nil`, «Ver el set» sin test de polaridad, la tabla de
   `gestor_administra_spec.rb` sin columnas de `participant` ni `evaluator`) y
   **dos rastros del renombre dejados a propósito** (el nombre de
   `gestor_administra_spec.rb` y los documentos de `docs/superpowers/`).

7. **El backlog largo, intacto:** el breadcrumb de `criteria_sets/edit` que para
   un set `inline` vuelve a una lista que nunca lo muestra;
   `Pipeline#validate` vs `Selection#can_activate?`; las once FKs con
   `ON DELETE SET NULL` sin acotador; `[FORMS]` que no cubre las pantallas a
   las que se llega por clic; los cuatro menores del módulo de testing; el plan
   2c (el resto de las islas Vue), `SelectionsController#update` sin validación
   server-side, `criteria_sets#show` huérfana, las 3 consultas de evolución,
   los tres temas de seguridad preexistentes, y que nada vigila el relleno por
   default de `card` desde que se retiró `[CARD]`.

8. **Sobre el recorrido como red, tres límites que conviene no olvidar:**
   - Dos pares de capturas son la MISMA pantalla (`03c-paso-a-paso` =
     `09-10-form-vacio`, `05e-config-seleccion` = `09-12-criterios-del-modulo`),
     así que las 66 capturas no son 66 pantallas.
   - **Sólo corre a 1440 y 1100px.** Abajo de 1024, donde el drawer pasa a ser
     una tira horizontal y el título se elipsa, no lo mira nada.
   - **La pasada oscura son diez pantallas y tres no tienen drawer**, así que
     toda variante que sólo aparezca en un desafío en borrador no se mide en
     oscuro. Es lo que motivó `[ESTADO-DRAWER]`; puede volver a morder con otra
     cosa.
