# Handoff

## Objetivo

La tercera y última de las inconsistencias sistémicas del repaso de las 66
capturas: **la fuente monoespaciada se usaba para prosa y para números.** Al
terminar, mono queda sólo donde hay código o un identificador, y una guarda lo
mide en las 66 pantallas.

Con esto **las tres inconsistencias del repaso están cerradas** (las otras dos
fueron el estado dibujado de tres formas, y los dos contadores que se leían
como posición).

## Estado actual

- **`master` está en `5e5ce7a` y está pusheado.** Verificado con `gh api` y no
  con `git rev-parse origin/master`, que lee una foto local. Sin ramas vivas,
  árbol limpio.
- **`make spec` → 1123 ejemplos, 0 fallas** (venía de 1122: uno nuevo, y el del
  N+1 se borró porque el arreglo lo volvió imposible) y **`make screens` → 66
  capturas, 0 errores**.
- El árbol del merge es idéntico al de la rama, así que las corridas valen.
- El stack quedó levantado. La base no se tocó.

### Decisiones de Raúl en esta sesión

Dos tandas, las dos con el mismo formato: diseño corto en el chat (bounded, sin
spec ni plan), ejecución nativa, revisión de rama al final, merge `--no-ff` a
master y push, sin PR.

- **Primera tanda, alcance angosto elegido explícitamente:** sólo los dos
  conteos sin sustantivo. Quedaron afuera el «3 / 2» de evaluación y el «N / M»
  de reportería, el estado del desafío sin chip en el drawer, y el «Paso 3 de 9»
  del pie.
- **Segunda tanda:** «dale, avisame cuando termine» — autonomía para el
  monospace de punta a punta, incluido el merge.

## Archivos y cambios

Dos merges: `9bee362` (los contadores) y `5e5ce7a` (el monospace). Sin
documentos de diseño: el alcance no los pedía.

### `9bee362` — Los contadores dicen qué cuentan

`challenges/show.html.haml`: la tarjeta «Flujo» da la **posición** del módulo
en curso («ahora: X · módulo 7 de 7»). Contar los que quedaron atrás daba el
número del módulo ANTERIOR al que corre. Sale del **índice** y no de
`actual.position`, que es `decimal(20,10)` y queda fraccionario al insertar
entre dos módulos; con el índice el encabezado, la columna «#», el mapa del
flujo y el drawer imprimen todos el mismo número.

`layouts/_flow_drawer.html.haml`: el contador suma «listos». Convivía con el
«Paso 3 de 9» del pie: dos «de 9», uno conteo y otro posición.

### `5e5ce7a` — Monoespaciada para código, no para prosa

`.field-list__type` pierde la mono. Se llama así por su primer uso pero es la
columna de VALOR de una lista de etiqueta/valor, y nueve vistas le mandan
prosa, rótulos traducidos y números. Además de leerse mal, la mono es más ancha
y partía la etiqueta de al lado en tres líneas en la columna de referencia.

El desglose de evaluación mostraba la **clave** del criterio. Ahora muestra el
nombre y el orden que el módulo **congeló en su snapshot** al activarse, que es
de donde los toma la tarjeta «Criterios» de la misma pantalla.

Guarda **`[MONO]`** en las 66 pantallas, con autotest de diez casos. Anotada en
CLAUDE.md.

## Intentos fallidos

**Las dos tandas terminaron igual: el hallazgo más caro salió de la revisión de
rama, y en las dos fueron guardas propias que yo había declarado probadas.**

### Guardas que pasaban sin probar nada — cuatro, en dos tandas

- **«1 de 3 listo» es subcadena de «1 de 3 listos»**, así que el único caso que
  existía para probar la concordancia sobrevivía intacto a concordar con el
  TOTAL en vez de con la cuenta. Un `'listos'` hardcodeado también lo pasaba.
- **Con posiciones 1, 2 y 3 el índice y `position` dan el mismo número**, así
  que el caso de la posición no distinguía la forma correcta de la que se rompe
  al insertar. La fixture usa **2,5**, que es lo que deja `(a+b)/2`.
- **El test del N+1 pasó apenas escrito, y NO porque no hubiera N+1:** los
  cuatro puntajes apuntaban al **mismo** criterio, así que la caché de
  consultas de Rails resolvía las tres lecturas siguientes y `consultas_a` las
  saltea por `payload[:cached]`. Con un criterio por idea falló. (Después el
  arreglo del snapshot volvió el ejemplo innecesario y se borró, pero el
  mecanismo queda anotado: **un ejemplo de N+1 con un solo padre no prueba
  nada.**)
- **Un caso del flujo terminado ya cumplía sus dos afirmaciones** contra el
  código viejo («2 de 2 · flujo terminado» contiene «flujo terminado» y no
  contiene «sin empezar»).

**La regla que quedó: verificar mutando el código y viendo fallar el caso, no
leyéndolo.** Se hizo con las cuatro que sobrevivieron y con `[MONO]`, y cada
mutación mató exactamente un caso.

### Agregar código muerto, y justificarlo con una ruta falsa

El sufijo «N módulos sin empezar» de la rama del flujo terminado —aprobado en
el diseño— no lo produce nada, y mi comentario decía que lo producía `close!`:

- `close!` no toca los pasos, así que un desafío cerrado con módulo activo cae
  en la OTRA rama.
- `advance!` activa el siguiente pendiente o cierra en la misma transacción, o
  sea que llegar sin activo es haber corrido todo.
- El único productor sería saltear el módulo activo, y **ninguna vista ofrece
  ese control**.

Se fue, y con él los dos únicos identificadores nuevos en español.

### Dos fuentes de verdad para el mismo rótulo

La primera versión del desglose leía el nombre del criterio de la fila **viva**
de `Criterion`. La tarjeta «Criterios» de la columna de la derecha —treinta
líneas más arriba, en la misma pantalla— lo lee del **snapshot** congelado. El
nombre es editable con el módulo en curso y un criterio borrado nulea
`criterion_id`, así que las dos tarjetas podían discrepar. Además el orden
alfabético por clave dejaba los genéricos —Impacto, Factibilidad, Esfuerzo— al
revés que en la tarjeta de al lado: **los mismos tres criterios en órdenes
opuestos en una pantalla**, que es el síntoma que la rama vino a sacar. El
snapshot resolvió las dos cosas y de rebote borró el `includes`, el ejemplo del
N+1 y la rama de respaldo.

### Una guarda a la que le faltaba la mitad del requerimiento

`[MONO]` pedía un **espacio** para considerar algo prosa, así que no veía los
números —«40%» no tiene ninguno— y el requerimiento los nombraba. Ahora pide
que el texto propio sea un identificador pelado. Medido: con la regla vieja
marcaba 13 pantallas, con la nueva 15.

### Cosas del entorno

- **Los dos primeros commits salieron con `Co-Authored-By`**, que en este repo
  no va. No estaban pusheados: se reescribieron con
  `git filter-branch --msg-filter` sobre `master..HEAD`. El harness la inyecta
  por system-reminder en cada sesión; hay que cortarla a mano cada vez.
- **`git merge -F -` no lee de stdin** («could not read file '-'»). El mensaje
  va a un archivo primero. `git commit -F -` sí funciona.
- **Después de tocar el CSS hay que `make yarn-build` antes de `make screens`**,
  o la guarda mide la hoja vieja. Pasó: `[MONO]` marcó un caso que ya estaba
  arreglado en la fuente. De rebote fue útil —cazó que los NOMBRES de criterio
  traen espacios donde las claves no— pero el orden correcto es build y después
  screens.

**Lo que funcionó, las dos veces: medir antes de decidir.** El riesgo de que
«listos» le comiera el título al drawer abajo de 1024px lo marqué como nota y
después lo medí con Playwright a 1023/900/760: el título **ya venía elipsado**
(101px de los 157 que necesita) y «listos» lo deja en 88px, o sea 13px peor
sobre un recorte preexistente. Y `[MONO]` se escribió ANTES del arreglo y se la
vio marcar 13 pantallas, todas la misma clase: eso confirmó que para la prosa en
mono había un solo culpable y que el arreglo era una línea de CSS.

## Próximos pasos

1. **Lo que quedó explícitamente afuera, con el terreno ya medido:**
   - **El estado del desafío como texto plano en la cabecera del drawer**, la
     cuarta forma de dibujar estado y lo único que sigue en pie del eje
     «el estado se dibuja de una sola forma». **No es agregar una clase:** el
     drawer es oscuro en los DOS temas, y aunque la pastilla hoy se compone
     sola —la regla de `currentColor`—, el TEXTO no: un `badge-soft` neutro
     pinta con `base-content`, que en tema claro es casi negro sobre el panel
     oscuro. El comentario de `.flow-drawer__punto` ya tiene medido por qué los
     puntos no son chips (fondos suaves a 1,3:1, tonos fuertes abajo de 3:1 en
     claro). Pide un tratamiento propio más una guarda en los dos temas.
   - El **«3 / 2»** de `steps/_celdas_de_evaluacion.html.haml:9` (evaluaciones
     hechas sobre el mínimo, con el numerador capaz de pasar al denominador) y
     el **«N / M»** de `steps/reporting.html.haml:134`.
   - **Una convención sin decidir:** conviven dos concordancias para la misma
     forma de frase — `ideas/show:114` concuerda el adjetivo con el TOTAL («1
     de 3 comentarios atendidos») y el drawer con la CUENTA («1 de 3 listo»).
     Las dos se defienden en español. Si se quiere una sola regla, el lugar es
     una línea al lado de `Flow::Texto.plural`.

2. **Cuatro defectos preexistentes que destaparon las revisiones**, ninguno
   alcanzable hoy por la interfaz:
   - **`StepsController#skip:114` no puede funcionar.** Hace
     `pipeline.advance! if pipeline.active_step.nil?`, y `advance!` corta con
     `failure(["no hay ningún módulo en curso"])` exactamente cuando
     `active_step` es nil. La ruta existe (`post :skip`) pero **ninguna vista la
     ofrece** (`grep skip_challenge_step_path` → nada). Los módulos salteados de
     las capturas vienen del seed.
   - **Un desafío cerrado dice «ahora: X · módulo N de M».** La rama se decide
     por «no hay módulo activo» cuando quiere decir «el desafío terminó», y
     `close!` deja el módulo activo. Venía igual con la línea vieja; la forma
     sería preguntar `closed? || archived?`.
   - **`Api::V1::CriteriaSetsController#assign` escribe `criterion.name` ANTES
     del guard de `locked?`**, así que el nombre de un criterio es editable
     aunque ya tenga evaluaciones encima. Hoy no rompe nada —el desglose y la
     tarjeta leen los dos del snapshot— pero el candado no cubre lo que dice
     cubrir.
   - **`_como_se_decide.html.haml:26` hace `Criterion.find_by(id:)` dentro de un
     `each`**: un N+1 por filtro en la pantalla de selección.

3. **Dos minors de la última revisión, anotados y no tomados:**
   - El `min-width: 110px` del criterio del desglose alinea la columna de
     puntajes **sólo mientras cada nombre entre en 110px**; con nombres (más
     largos que las claves) el riesgo es nuevo. El comentario ya lo dice y
     propone la forma (`flex: 0 0 110px` o una grilla de dos columnas).
   - **`[MONO]` no ve prosa partida por un hijo inline**:
     `<span>Impacto<b>·</b>Numérico</span>` junta «ImpactoNumérico», que pasa
     por identificador. `_como_se_decide.html.haml` tiene esa forma, hoy sin
     mono. Está anotado en el comentario de la guarda.

4. **Lo visual que sigue en pie del repaso de capturas:** `Choose File / No file
   chosen` sin estilo en `16-idea-new`; `18-select-company` con el rol fuera del
   botón y el separador colgando; el popup de espera sin backdrop
   (`09-13-ia-espera`); la previsualización que se repite a sí misma en 5 de 7
   tarjetas; el popup de la IA que dice lo mismo tres veces; el hueco muerto del
   Brief; «Cómo quedó configurado» encabalgado; la columna «Acción» que apila;
   «Armar el flujo con IA» sin controles con el flujo arrancado; «Distribución
   de puntajes» con dos filas de números; «Quién evalúa» duplicado sin el peso.
   («El desglose con claves en vez de nombres» se cerró en esta sesión.)

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

8. **Sobre el recorrido como red:** dos pares de capturas son la MISMA pantalla
   (`03c-paso-a-paso` = `09-10-form-vacio`, `05e-config-seleccion` =
   `09-12-criterios-del-modulo`), así que las 66 capturas no son 66 pantallas.
   Y el recorrido **sólo corre a 1440 y 1100px**: abajo de 1024, donde el
   drawer pasa a ser una tira horizontal, no lo mira nada.
