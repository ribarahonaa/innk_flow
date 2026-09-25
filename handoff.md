# Handoff

## Objetivo

Cerrar los cinco defectos preexistentes que habían destapado las revisiones de
rama de las tandas anteriores. **Tres eran defectos y dos no**, y los dos que no
eran quedaron documentados para que nadie los vuelva a discutir.

Con esto el repaso de las 66 capturas queda sin inconsistencias sistémicas
abiertas y sin defectos de dominio pendientes de las revisiones.

## Estado actual

- **`master` está en `c5ba9cf` y está pusheado.** Verificado con `gh api` y no
  con `git rev-parse origin/master`, que lee una foto local. Sin ramas vivas,
  árbol limpio.
- **`make spec` → 1141 ejemplos, 0 fallas** (venía de 1125) y **`make screens`
  → 66 capturas, 0 errores**.
- El árbol del merge es idéntico al de la rama.
- El stack quedó levantado. La base no se tocó.

### Decisiones de Raúl en esta sesión

Cuatro tandas, las cuatro con el mismo formato: diseño corto en el chat
(bounded, sin spec ni plan en `docs/`), ejecución nativa, revisión de rama al
final, merge `--no-ff` a master y push, sin PR.

1. **Los dos contadores** — alcance angosto elegido explícitamente.
2. **El monospace** — «dale, avisame cuando termine»: autonomía de punta a
   punta, merge incluido.
3. **El chip del drawer** — diseño con números medidos antes de aprobar.
4. **Los cinco defectos preexistentes.** Pidió borrar la rama muerta de
   `Setup#finish_step`; al implementarlo apareció que **no estaba muerta** y no
   se borró (ver «Intentos fallidos»).

## Archivos y cambios

Cuatro merges: `9bee362` (contadores), `5e5ce7a` (monospace), `1a1779e` (chip
del drawer), `c5ba9cf` (los cinco defectos).

### `c5ba9cf` — Los cinco defectos preexistentes

**Arreglado: saltear un módulo dejaba el flujo trabado.** `skip!` deja el módulo
`skipped`, o sea sin ninguno en curso, y `StepsController#skip` llamaba ahí a
`advance!`, que corta con `failure` exactamente en ese estado — y detrás de un
`if active_step.nil?`, que era la condición que lo garantizaba. La cola de
`advance!` se extrajo a `open_next_or_close!` y se expone como
`Pipeline#continue!`.

**Arreglado: un desafío cerrado decía «ahora: X», y la causa estaba en el
dominio.** `close!` cerraba el desafío sin tocar los pasos, así que el módulo
seguía `active?` y la contradicción se veía en TRES lugares de la misma
pantalla. Ahora `close!` saltea lo que estaba corriendo, con el motivo en
`skip_reason`.

**Arreglado: los criterios de los filtros de una selección.** Se buscaban de a
uno y su descripción se recalculaba por idea. Los dos van por memo en el
handler.

**No era un defecto: el candado de criterios.** Su propio comentario dice que lo
cosmético sigue abierto. `position` y `active`, que el comentario no nombraba,
tampoco pueden mover nada ya puntuado: el cálculo lee el snapshot y
`active_criteria` sólo lo alimenta en `activate!`.

**No era una rama muerta: la pista de `Setup#finish_step`.** No se renderiza,
pero la clase sirve el caso y hay spec de eso.

## Intentos fallidos

**El patrón de la sesión entera, en las cuatro tandas: el hallazgo más caro
salió de la revisión de rama, y casi siempre fue algo que yo había declarado
verificado.**

### Siete guardas que no probaban nada, cada una por un mecanismo distinto

- **Subcadena.** «1 de 3 listo» está contenido en «1 de 3 listos», así que el
  único caso que probaba la concordancia sobrevivía a concordar con el TOTAL.
- **Fixture sin variación.** Con posiciones 1, 2 y 3 el índice y `position` dan
  el mismo número. La fixture usa **2,5**, que es lo que deja `(a+b)/2`.
- **Caché de consultas, dos veces.** Un ejemplo de N+1 con un solo padre no
  prueba nada: la repetición es SQL idéntico y `consultas_a` la saltea por
  `payload[:cached]`. Pasó con los puntajes de una evaluación (mismo criterio
  cuatro veces) y volvió a pasar con `form_fields` en selección.
- **Afirmaciones que el código viejo ya cumplía.** «2 de 2 · flujo terminado»
  contiene «flujo terminado» y no contiene «sin empezar».
- **Contar iteraciones en vez de mediciones.** `[ESTADO-DRAWER]` comparaba
  `medidos.length` con `VARIANTES.length` y `medidos` se llenaba una vez por
  iteración: inalcanzable. Con el arreglo vacío, la guarda pasaba sin medir.
- **`undefined` atravesando los filtros.** `medirContraste` devuelve lista vacía
  para lo que no se ve, y `undefined < 4.5` es `false`: un chip oculto dejaba la
  guarda en verde.
- **Un ejemplo que se mudó de rama y dejó la vieja sin nadie.** Al poner la rama
  del desafío cerrado adelante, el ejemplo que cubría el `else` migró solo, y
  borrar ese `else` habría dejado `make spec` en verde.

**Las reglas que quedaron:**

1. **Verificar mutando el código y viendo fallar el caso**, no leyéndolo.
2. **Cuando una guarda cubre dos ejes** —dos temas, dos variantes— **una
   mutación por eje.** Sacarle el color al chip del drawer dispara en claro y no
   en oscuro, así que media guarda quedó sin verse fallar hasta una segunda
   mutación.
3. **Un conteo de consultas con un solo padre no mide nada**, y hay cosas que
   NINGÚN conteo puede pinchar porque la caché las esconde. Cuando es así, se
   escribe que no hay guarda posible en vez de inventar una que pase.

### Cuatro veces afirmé algo medido que no era cierto

- **Código muerto justificado con una ruta falsa.** El sufijo «N módulos sin
  empezar» no lo produce nada, y mi comentario decía que lo producía `close!`.
- **Dos fuentes de verdad.** El desglose leía el nombre del criterio de la fila
  viva; la tarjeta de al lado, del snapshot congelado.
- **Declaré ciega a una guarda que no lo es.** Escribí que `[CONTRASTE]` «mide
  lo que hay, no dónde está»: compone la opacidad de los ancestros a propósito,
  así que sí caza mover el chip adentro del bloque atenuado (3,75:1).
- **Afirmé una independencia de la caché que no había conseguido.** El memo de
  los criterios de filtro movía el fan-out de `criteria` a `form_fields` y el
  comentario decía que el problema estaba resuelto.

### Y una vez mi arreglo fue destructivo

Sacar el `if active_step.nil?` de `skip` sacó una protección **accidental**: en
un desafío en borrador tampoco hay módulo en curso, y ni la policy ni `skip!`
miran el estado del desafío, así que un salteo autorizado sobre un borrador lo
**cerraba** de un POST, sin camino de vuelta en la app. `open_next_or_close!`
ahora pide `running?`, y las dos guardas se leen adentro del lock.

### Una instrucción que ejecuté al revés, y con razón

Raúl pidió borrar la «rama muerta» de `Setup#finish_step` **porque yo le había
dado mal el dato**. `spec/lib/flow/setup_spec.rb` instancia `Flow::Setup` con el
desafío arrancado y afirma que el paso final queda `done`: la clase sirve ese
caso. Borrar la pista habría dejado `status` atendiendo no-borrador y `hint` no.
Se documentó y se le puso test a la pista, que era el único argumento a favor de
conservarla y era un comentario.

### Cambiar el dominio rompió un spec, y cómo se resolvió

Hacer que `close!` saltee el módulo en curso rompió `testing_ia_spec`, cuyo
escenario era «cerrado + módulo activo». **Los dientes de esa guarda vienen del
DESAFÍO cerrado y no del estado del módulo** —`advance?` no pregunta por
`closed?` y `update_pipeline?` sí—, así que sigue cazando el bug viejo con el
módulo salteado. Se actualizó el escenario y los **dos** comentarios que
afirmaban lo que `close!` ya no hace (`testing_ia_spec` y
`pantalla_del_modulo_spec`). Al cambiar el dominio, buscar con `grep` los
comentarios que describían el comportamiento viejo es parte del trabajo.

### Cosas del entorno

- **Los dos primeros commits de la sesión salieron con `Co-Authored-By`**, que
  en este repo no va. No estaban pusheados: se reescribieron con
  `git filter-branch --msg-filter` sobre `master..HEAD`. El harness la inyecta
  por system-reminder en CADA sesión; hay que cortarla a mano cada vez.
- **`git merge -F -` no lee de stdin** («could not read file '-'»). El mensaje va
  a un archivo primero. `git commit -F -` sí funciona.
- **Después de tocar el CSS: `make yarn-build` ANTES de `make screens`**, o la
  guarda mide la hoja vieja.
- Para corregir el mensaje del último commit con el árbol sucio:
  `git stash push -u` → `git commit --amend -F` → `git stash pop`.
- **HAML no acepta un comentario entre una rama y su `elsif`**: rompe la cadena
  con `Haml::SyntaxError`. Va adentro de la rama.

**Lo que funcionó, las cuatro veces: medir antes de decidir, y volver a medir
para saber el tamaño.** El chip del drawer se midió inyectándolo en el panel
vivo con diez porcentajes de mezcla antes de escribir una línea de CSS —copiar
la mezcla de los puntos habría dejado el neutro en 3,59:1—. `[MONO]` se escribió
ANTES del arreglo y marcó 13 pantallas, todas la misma clase. Y medir el N+1
corrigió mi propia afirmación sobre su tamaño dos veces.

## Próximos pasos

1. **Dos capacidades de dominio sin control en ninguna vista**, que es por lo
   que sus defectos sobrevivieron sin que nada los tocara: **saltear un módulo**
   (`post :skip`) y **cerrar un desafío a mano** (`post :close`). Las dos tienen
   policy, ahora tienen cobertura y funcionan; ofrecerlas es decisión de
   producto y no se tomó. Si se ofrece el salteo, ojo con lo que ya quedó
   anotado: saltear un módulo PENDIENTE sube el piso de inserción y congela los
   pendientes anteriores contra borrado y reordenamiento.

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
     puntajes **sólo mientras cada nombre entre en 110px**. El comentario ya lo
     dice y propone la forma.
   - **`[MONO]` no ve prosa partida por un hijo inline**:
     `<span>Impacto<b>·</b>Numérico</span>` junta «ImpactoNumérico», que pasa
     por identificador. `_como_se_decide` tiene esa forma, hoy sin mono.
   - **`Evaluation#criteria_preview` tiene el mismo `Criterion.find_by` por
     criterio** que se acaba de sacar de selección; el mismo memo aplica.
   - **`Handlers::Base#skip!` no mira el estado del módulo**: sobreescribe el
     `status` y el `completed_at` de uno ya completado. Hoy nadie lo alcanza así.
   - **`activate!` levanta `Flow::Errors::StepNotReady` y nada lo rescata**, así
     que `continue!` puede dar 500 después de que el salteo ya se guardó. En el
     camino en curso `validate` en `start!` lo vuelve un borde; el `advance`
     tiene el mismo hueco.

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
