# Handoff

## Objetivo

Dos cosas, y sólo la primera es código.

**Un bug reportado a mano:** el corte de un módulo de selección no respetaba el
mínimo (`cut.min`) cuando los filtros no se cumplían. Arreglado, mergeado y
pusheado.

**El diseño de un sexto módulo del flujo, «testing»:** pone las ideas a prueba
contra situaciones concretas de ejecución y dictamina si son factibles. Quedó
en spec + plan de la tanda 1. **No se escribió una línea de implementación.**

## Estado actual

- **`master` está en `3f4e015`** y `origin/master` en `4af97ab`: quedan **dos
  commits sin pushear**, los dos de documentación (`faf40d0` el spec,
  `3f4e015` el plan). Árbol limpio, sólo `master` en los dos lados.
- **El bug del piso está cerrado**: merge `--no-ff` `8bc0c45`, con el árbol del
  merge idéntico al de la rama verificada. `make spec` **928 ejemplos, 0
  fallas** y `make screens` **62 capturas** sin errores de JS ni respuestas
  >= 400, corridos sobre el merge y no sólo sobre la rama. La rama
  `piso-sobre-filtros` ya está borrada en los dos lados.
- **Los tres commits de la rama quedaban verdes por su cuenta**, verificado
  stasheando el resto: `031b6e7` da 925/0 y `213b7d7` da 928/0. Era
  bisecteable.
- **El módulo de testing no existe todavía.** Hay spec y plan, nada más.

### Cambió una convención de commits

**Los mensajes de commit ya no llevan la línea `Co-Authored-By`.** Raúl lo pidió
a mitad de sesión. Los cuatro commits anteriores a ese momento la conservan
—`031b6e7`, `213b7d7`, `1ab2fe9` y el merge `8bc0c45`—: se decidió **no**
reescribir historia ya pusheada por una línea de ruido en el log. Está guardado
en la memoria del proyecto (`sin-coautoria-en-commits`).

### Hechos del entorno que muerden

Todos los del handoff anterior siguen valiendo. Dos precisiones nuevas:

- El push por SSH no anda; va por HTTPS con el token de `gh`. **`git fetch`
  también**, y para que `--prune` limpie una rama borrada hay que darle el
  refspec entero:
  `fetch --prune <url> '+refs/heads/*:refs/remotes/origin/*'`.
- **`git rev-parse origin/master` lee una foto local, no el remoto.** Ver
  *Intentos fallidos*.
- **Nunca un worktree:** `docker-compose.yml` monta `.` en `/rails`, así que
  `make spec` y `make screens` corren siempre contra el checkout principal.
- **Dos `make screens` en paralelo se pisan**: borra `tmp/screenshots/` entero
  al arrancar.
- `make yarn-build` antes de `make screens` sólo si se tocó la hoja o una isla.
  Esta sesión no lo necesitó: el chip nuevo reusa una clase que ya estaba.

## Archivos y cambios

### El bug del piso — rama `piso-sobre-filtros`, merge `8bc0c45`

**La causa raíz.** `Flow::Handlers::Selection#ranking` calculaba el piso **sólo
sobre las filas que ya habían pasado los filtros**:

```ruby
eligible = ordered.select(&:passes_gates?)
cutoff   = cut_size(eligible)   # y cut_size topea el piso con el scored? de ESE subconjunto
```

Así cada idea filtrada encogía el mínimo en silencio. Medido con piso 2 sobre
cinco ideas: con una sola pasando los filtros avanzaba **una**; con ninguna
pasando avanzaban **cero** —justo lo que el piso existe para evitar—. El único
tope que el esquema declaraba era «las que hay **evaluadas**».

**Por qué no lo agarró nadie:** el piso y los filtros tenían specs cada uno por
su lado y **nunca juntos** (`selection_spec.rb:107` y `:281`).

- `031b6e7` — el handler. El corte se arma en dos pasadas: `quienes_avanzan`
  deja que la regla decida entre las que pasan los filtros, y
  `relleno_del_piso` completa con las mejores puntuadas de las que fallaron.
  `Row#por_el_piso?` marca esas filas. `piso_aplicado?` pasó a compararse
  contra lo que efectivamente pasó.
- `213b7d7` — la pantalla. Dos arrastres del cambio, los dos invisibles en el
  DOM: la casilla del corte iba `disabled` por no pasar un filtro (**y una
  casilla deshabilitada no se envía**, así que la idea subida por el piso no
  avanzaba igual al confirmar), y la línea de corte se dibujaba en
  `above.size`, que asume un prefijo contiguo. Más el chip «pasa por el
  mínimo».
- `1ab2fe9` — el `hint` de `cut.min` en `Flow::StepSettings`, que describía la
  regla vieja. Importa doble: es lo que se lee al configurar **y**, vía
  `json_schema`, lo único que ve el modelo al proponer un flujo.

### El módulo de testing — sin implementar

- `faf40d0` — `docs/superpowers/specs/2026-09-21-modulo-de-testing-design.md`
  (432 líneas). Las cinco decisiones con su porqué, el modelo de datos, las dos
  caras, la tarea de IA con el contrapeso de su prompt, y el check que conecta
  con la selección. Dos tandas.
- `3f4e015` — `docs/superpowers/plans/2026-09-21-modulo-de-testing-tanda-1.md`
  (1458 líneas). Siete tareas con código real, no descripciones.

**Las cinco decisiones, en una línea cada una** (el porqué está en el spec):

1. Deja un veredicto, **no elimina**: `ideas.status` sigue con un solo escritor.
2. Las **situaciones las arma quien testea, por idea**; el módulo configura
   sólo el marco (dimensiones · mínimo · severidad).
3. **Un testeo vigente por idea con historial**, con la unicidad garantizada por
   un índice parcial de Postgres y no por una validación.
4. Veredicto **ternario** (`factible` / `con_reservas` / `no_factible`) más
   lista de reservas; la vara la pone el filtro de la selección.
5. **Testear es de quien administra o acompaña**: cierra por permiso el
   re-roll que sale de combinar «un vigente, el último manda» con «el autor
   puede pedirlo».

## Intentos fallidos

Nueve cosas que se creyeron y no eran, o que casi se hacen mal. El patrón se
repite: **acertar la conclusión por la razón equivocada**.

- **La primera reproducción falló por un error MÍO, no del código.**
  `ArgumentError: wrong number of arguments (given 0, expected 1)` en un helper
  del spec: `def armar(config, set: nil)` tiene un kwarg, así que
  `armar("cut" => …)` se lo come como keywords y deja el posicional vacío.
  Leer ese stacktrace como una falla del dominio manda la investigación para
  cualquier lado. **Un helper de spec con un kwarg se traga el hash final.**

- **«Las demás condiciones» era ambiguo y casi se resuelve adivinando.** Podía
  ser la regla de corte o los filtros. Lo desempató el vocabulario de la propia
  app: `steps/_como_se_decide.html.haml:19` llama **«condición»** a cada filtro.
  Antes de elegir entre dos lecturas de un reporte, buscá la palabra del
  reporte en las vistas.

- **`piso_aplicado?` mentía en el caso intermedio y no se vio leyéndolo.** Con
  una idea pasando el filtro y piso 2 devolvía `true` —la pantalla imprimía
  «Pasan por el mínimo… avanzan las mejores»— mientras avanzaba una sola. Salió
  de instrumentar los tres escenarios en una corrida, no de revisar el método.

- **El arreglo habría quedado medio muerto en la pantalla real, con la suite y
  las capturas en verde.** El `disabled` de la casilla. Ni un spec ni una
  captura lo miraban. Se encontró **leyendo la vista ANTES de escribir el fix**.

- **La línea de corte asumía un prefijo contiguo**, y eso deja de valer en
  cuanto el piso sube filas desde el fondo.

- **Un test nuevo pasó desde el principio y se lo hizo fallar a propósito.** El
  de «no completa con una idea que tiene un filtro sin responder» es guarda de
  regresión, no RED: se le sacó el chequeo de pendientes al handler para verlo
  fallar y recién ahí se lo dio por bueno.

- **El spec del módulo de testing afirmaba que había que tocar
  `EstilosHelper`. Es falso.** `CLASE_DE_NODO_DE_FLUJO` y `PUNTO_DE_ESTADO`
  mapean por **estado** (`pending`/`active`/`completed`/`skipped`), nunca por
  `kind`: el drawer y el mapa del flujo dibujan un módulo nuevo sin una línea de
  helper ni de CSS. Lo encontró el auto-review del spec; quedó escrito como
  afirmación verificada para que nadie lo vuelva a meter al plan.

- **El plan tenía tres lugares que describían en vez de mostrar**, que es lo que
  la skill de planes llama un fallo de plan. Los tres se arreglaron
  verificando: los nombres de los cuatro partials de la referencia, el
  precedente real de la ruta (`assessments`, no `selections`) y el seed, que
  ahora trae el bloque completo de `testeo-abierto` con los correos sembrados
  verificados en `db/seeds.rb:57`.

- **Se reportó una divergencia de `master` que no existía, y se hizo un
  `git reset --hard` antes de preguntarle al remoto.** `git rev-parse
  origin/master` lee una **foto local**; Raúl había reemplazado el commit del
  handoff por force push y después se pusheó el amend, así que la foto estaba
  vieja dos veces. El reset terminó siendo un no-op, pero la conclusión se
  publicó antes de verificarla. **`ls-remote` ANTES de concluir nada sobre el
  remoto, no después.**

## Próximos pasos

1. **Pushear los dos commits de documentación** (`faf40d0`, `3f4e015`). Es lo
   único pendiente del árbol.

2. **Ejecutar la tanda 1 del módulo de testing.** El plan está listo y propone
   dos caminos: subagentes (uno fresco por tarea, con revisión entre tareas) o
   inline con checkpoints. Sin elegir todavía.

3. **La tanda 2** —la tarea de IA, el segundo CHECK (`ai_runs_purpose_check`) y
   el check `testing_passed`— sale del mismo spec, §5 y §6.

4. **Nadie miró todavía las 62 capturas.** Sigue siendo lo único de las últimas
   tres sesiones que no hizo una máquina.

5. **Ninguna captura ejercita el piso sobre los filtros.** Ningún desafío
   sembrado combina filtros que fallen con un `cut.min`, así que el chip «pasa
   por el mínimo» y la casilla habilitada no se fotografían. Lo cubre el request
   spec, no `make screens`.

6. **`SelectionsController#update` no valida server-side a quién se hace
   avanzar** (`app/controllers/selections_controller.rb:9`). Es **previo** al
   arreglo de esta sesión y probablemente no sea un agujero —`advance?` ya es
   capacidad de quien administra, y «Repescar» hace lo mismo a mano—, pero
   quedó anotado y sin decidir.

7. **Plan 2c: las islas Vue.** Lo que queda del rediseño. El CSS muerto está
   confirmado con cero usos: `checks-help`, `inline-label`, `.btn-link`.

8. **Dos hallazgos sin decidir**, de handoffs anteriores:
   - `criteria_sets#show` es una pantalla huérfana: nada la linkea.
   - Evolución hace 3 consultas a `ideas` con una sola idea sembrada
     (`evolution.html.haml:15` y `:22`). No se determinó si escala.

9. **Evolución no tiene encabezados en el centro**: el título de cada tarjeta de
   feedback es un `link_to` con clase propia, no un `h2`.

10. **Tres temas de seguridad preexistentes, sin arreglar y sin verificar en
    esta sesión**: la sesión de quien perdió la membresía sigue viva; los links
    de adjuntos de Active Storage no vencen y quedan fuera de Pundit; se puede
    asignar a evaluar a alguien con rol `participant` por POST directo.

11. **Lo que se perdió al borrar `[CARD]` sigue sin reemplazo.** Nada vigila que
    DaisyUI no recupere sus 24px de relleno por default. No es un defecto —no
    hay contra qué comparar sin `.panel`—, pero que nadie lo dé por cubierto.

## Decisiones de Raúl en esta sesión

**Sobre el bug del piso**

- **El piso gana también sobre los filtros**, entre tres opciones presentadas
  con la evidencia medida al lado. Las otras dos eran trabar el cierre sin
  forzar el pase, y dejar el cálculo y arreglar sólo el texto. Se eligió a
  sabiendas de que una idea puede avanzar con una condición fallada; de ahí que
  la pantalla tenga que marcarlo.
- Tres commits separados, no uno.
- El merge `--no-ff` después del push de la rama; el borrado de la rama después
  del push del merge.

**Sobre los commits**

- **Sin línea `Co-Authored-By`.** Los cuatro que ya estaban pusheados se dejan
  como están: no se reescribe historia publicada por eso.

**Sobre el módulo de testing**

- Las cinco decisiones de diseño listadas arriba.
- **El contrapeso del prompt**: el rigor de la IA va en las **situaciones**, no
  en el veredicto. `no_factible` sólo si hay una situación que se rompe con un
  detalle concreto; si lo roto es arreglable, `con_reservas`. Sin eso, una IA
  crítica por mandato vacía el pool — el mismo escenario del bug que se arregló
  esta misma sesión.
- **`sin_testeo` del check es configurable**, y su default es `pasa`. La
  propuesta original era que no pasara; Raúl pidió que lo decida quien
  configura.
- **Enfoque en dos tandas**, con el `kind` en «Solo personas» primero.
