# Handoff

## Objetivo

La segunda de las tres inconsistencias sistémicas que dejó el repaso de las 66
capturas: **dos contadores «N de M» se leían como una posición y no lo eran.**
Al terminar, los dos dicen qué cuentan, y el de la ficha del desafío pasó a dar
la posición de verdad.

## Estado actual

- **`master` está en `9bee362` y está pusheado.** Verificado con `gh api` y no
  con `git rev-parse origin/master`, que lee una foto local. Sin ramas vivas,
  árbol limpio.
- **`make spec` → 1122 ejemplos, 0 fallas** (venía de 1118: cinco nuevos menos
  uno que se borró en la revisión) y **`make screens` → 66 capturas, 0
  errores**.
- El árbol del merge es idéntico al de la rama (`git diff` vacío entre las dos),
  así que las corridas de la rama valen para el merge.
- El stack quedó levantado. La base no se tocó.

### Decisiones de Raúl en esta sesión

- Arrancar por esta inconsistencia y no por el monospace.
- **Alcance angosto a propósito: sólo los dos conteos sin sustantivo.** Quedaron
  afuera, elegidos uno por uno: el «3 / 2» de evaluación y el «N / M» de
  reportería, el estado del desafío sin chip en la cabecera del drawer, y el
  «Paso 3 de 9» del pie (que está bien como está).
- Con ese alcance esto pasó a ser **bounded**: diseño corto en el chat, sin
  spec ni plan en `docs/superpowers/`.
- Ejecución nativa, con revisión de rama al final. Merge `--no-ff` a master
  local y push, sin PR.

## Archivos y cambios

Merge `9bee362`. No hay documento de diseño: el alcance no lo pedía.

### `94a4354` — Los dos contadores dicen qué cuentan

`challenges/show.html.haml`: la tarjeta «Flujo» pasa a dar la **posición** del
módulo en curso («ahora: X · módulo 7 de 7»). Contar los que quedaron atrás
daba el número del módulo ANTERIOR al que corre, y el 6 se leía como la
posición del que se nombraba al lado.

Sale del **índice** y no de `actual.position`: `position` es `decimal(20,10)` y
queda fraccionario apenas alguien inserta entre dos módulos. Con el índice, el
encabezado, la columna «#» de la tabla, el mapa del flujo y el drawer imprimen
todos el mismo número, porque los cuatro recorren el mismo arreglo cargado bajo
el `-> { order(:position) }` de la asociación.

No lleva sustantivo porque no hay uno honesto: lo que se contaba mezclaba
`completed` con `skipped`, y «Cerrado» ya es el rótulo del desafío `closed`, que
se lee dos tarjetas más arriba.

`layouts/_flow_drawer.html.haml`: el contador suma «listos», concordado con
`Flow::Texto.plural`. En la pantalla de un módulo en borrador convivía con el
«Paso 3 de 9» del pie: dos «de 9» distintos, uno conteo y otro posición.

### `0fc2cce` — La rama del flujo terminado no dibuja un estado que no ocurre

Los dos Important de la revisión. Ver «Intentos fallidos».

## Intentos fallidos

**Lo más caro de la sesión volvió a salir de la revisión de rama, y otra vez
fueron guardas que yo había declarado probadas.**

- **Dos de los cinco casos nuevos no discriminaban**, cada uno por un motivo
  distinto:
  - «1 de 3 listo» es **subcadena** de «1 de 3 listos», así que el caso del
    singular sobrevivía intacto a concordar con el TOTAL en vez de con la
    cuenta —que es la otra convención viva en la app, en `ideas/show`—. Un
    `'listos'` hardcodeado también lo pasaba. O sea: el único caso que existía
    para probar la concordancia no afirmaba nada sobre la concordancia.
  - Con posiciones 1, 2 y 3 el índice y `position` dan el mismo número, así que
    el caso de la posición no distinguía la forma correcta de la que se rompe
    al insertar. La fixture ahora usa **2,5**, que es lo que deja `(a+b)/2`.
  - Un tercero ya lo había cazado yo al escribirlo, y por el mismo mecanismo:
    pasaba contra el código viejo porque «2 de 2 · flujo terminado» ya cumplía
    sus dos afirmaciones.
  - **Las cuatro que quedaron se verificaron mutando el código y viendo fallar
    el caso**, no leyéndolas. Cada mutación mató exactamente un caso.
- **Agregué código muerto y lo justifiqué con una ruta que no lo produce.** El
  sufijo «N módulos sin empezar» de la rama del flujo terminado, aprobado en el
  diseño, no lo produce nada: `close!` no toca los pasos, así que un desafío
  cerrado con módulo activo cae en la OTRA rama; y `advance!` activa el
  siguiente pendiente o cierra en la misma transacción, así que llegar sin
  activo es haber corrido todo. Mi comentario decía que `close!` lo producía.
  Se fue, y con él los **dos únicos identificadores nuevos en español**
  (`sin_empezar`, `pendientes`), que eran el otro Important — la regla de
  CLAUDE.md desde el 2026-09-23 es código en inglés, y el «se quedan como
  están» cubre los existentes, no los nuevos.
- **Los dos commits salieron con la línea `Co-Authored-By`**, que en este repo
  no va. No estaban pusheados, así que se reescribieron con
  `git filter-branch --msg-filter` sobre `master..HEAD`. El harness la inyecta
  por system-reminder en cada sesión; hay que cortarla a mano cada vez.
- **`git merge -F -` no lee de stdin** («could not read file '-'»). El mensaje
  del merge va a un archivo primero. `git commit -F -` sí funciona.

**Lo que funcionó:** medir en vez de anotar el riesgo. Marqué que «listos» le
podía comer el título al drawer abajo de 1024px, y el recorrido sólo corre a
1440 y 1100px, así que nadie lo iba a ver. Con Playwright a 1023/900/760 quedó
claro que **el título ya venía elipsado antes del cambio** (101px de los 157 que
necesita) y que «listos» lo deja en 88px: 13px peor sobre un recorte
preexistente, no un defecto nuevo. Eso convirtió un bloqueo posible en una nota.

**Lo que la revisión confirmó y no había que tocar:** el índice contra
`position`, que `!touched?` es exactamente el conjunto `pending`, que nada más
leía el `hechos` que se borró, y que ninguna lectura del dominio se escapó de
`as_company`.

## Próximos pasos

1. **La tercera inconsistencia sistémica, que es la última que queda:**
   **monospace para prosa y para números** — «veredicto por idea», «pasó su
   prueba de factibilidad, con reservas o sin ellas», los pesos (40%, 25%), las
   claves de criterio. Es lo que hace parecer volcado de debug a «Cómo quedó
   configurado».

2. **Lo que quedó explícitamente afuera de esta tanda**, con el terreno ya
   medido:
   - **El estado del desafío como texto plano en la cabecera del drawer**, la
     cuarta forma de dibujar estado. **No es agregar una clase:** el drawer es
     oscuro en los DOS temas, y aunque la pastilla hoy se compone sola —la regla
     de `currentColor` de la sesión anterior—, el TEXTO no: un `badge-soft`
     neutro pinta con `base-content`, que en tema claro es casi negro sobre el
     panel oscuro. El comentario de `.flow-drawer__punto` ya tiene medido por
     qué los puntos no son chips (fondos suaves a 1,3:1, tonos fuertes abajo de
     3:1 en claro). Pide un tratamiento propio más una guarda en los dos temas.
   - El **«3 / 2»** de `steps/_celdas_de_evaluacion.html.haml:9` (evaluaciones
     hechas sobre el mínimo, con el numerador capaz de pasar al denominador) y
     el **«N / M»** de `steps/reporting.html.haml:134`.
   - **Una convención sin decidir:** ahora conviven dos concordancias para la
     misma forma de frase — `ideas/show:114` concuerda el adjetivo con el TOTAL
     («1 de 3 comentarios atendidos») y el drawer con la CUENTA («1 de 3
     listo»). Las dos se defienden en español. Si se quiere una sola regla, el
     lugar es una línea al lado de `Flow::Texto.plural`.

3. **Dos defectos preexistentes que destapó la revisión**, ninguno alcanzable
   hoy por la interfaz:
   - **`StepsController#skip:114` no puede funcionar.** Hace
     `pipeline.advance! if pipeline.active_step.nil?`, y `advance!` corta con
     `failure(["no hay ningún módulo en curso"])` exactamente cuando
     `active_step` es nil. Saltear el módulo activo dejaría el flujo trabado. La
     ruta existe (`post :skip`) pero **ninguna vista la ofrece**
     (`grep skip_challenge_step_path` → nada), así que está dormido. Los módulos
     salteados que muestran las capturas vienen del seed, no de esa acción.
   - **Un desafío cerrado sigue diciendo «ahora: X · módulo N de M».** La rama
     se decide por «no hay módulo activo» cuando lo que quiere decir es «el
     desafío terminó», y `close!` deja el módulo activo. Venía igual con la
     línea vieja; la forma sería preguntar `closed? || archived?`.

4. **Lo visual que sigue en pie del repaso de capturas:** `Choose File / No file
   chosen` sin estilo en `16-idea-new`; `18-select-company` con el rol fuera del
   botón y el separador colgando; el popup de espera sin backdrop
   (`09-13-ia-espera`); la previsualización que se repite a sí misma en 5 de 7
   tarjetas; el popup de la IA que dice lo mismo tres veces; el desglose con
   claves en vez de nombres; el hueco muerto del Brief; «Cómo quedó
   configurado» encabalgado; la columna «Acción» que apila; «Armar el flujo con
   IA» sin controles con el flujo arrancado; «Distribución de puntajes» con dos
   filas de números; «Quién evalúa» duplicado sin el peso.

5. **Los minors diferidos de la revisión de la tanda anterior**, ninguno
   urgente: `[PASTILLA]` no asegura «midió al menos N» por pantalla; la regla
   nueva debilita `[CLASES]` para los chips suaves; un borde punteado se
   acredita como pastilla entera; `flow.entry_statuses.skipped` huérfano en
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
