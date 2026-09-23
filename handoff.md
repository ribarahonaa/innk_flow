# Handoff

## Objetivo

Cuatro cosas: dejar la base con sólo los desafíos del seed, abrir el rol
`gestor` para que administre los desafíos que le asignaron, corregir la regla
de idioma del repo —que decía lo contrario de lo que Raúl esperaba— y empezar
a mirar las capturas, que nadie había revisado en cinco sesiones.

Lo segundo se ejecutó con `superpowers:subagent-driven-development`: spec de
diseño, plan de seis tareas, un subagente fresco por tarea, revisión por tarea
con dos veredictos, y una revisión de rama entera en Opus al final.

## Estado actual

- **`master` está en `e7b0b4c` y pusheado.** Verificado contra el remoto con
  `gh api`, no con `git rev-parse origin/master` —que lee una foto local—. Sin
  ramas vivas. El merge del rol gestor es `a6aa59e`; encima van el handoff y
  los tres commits de la regla de idioma.
- **`make spec` → 1092 ejemplos, 0 fallas** (venía de 1017), corrido sobre el
  resultado del merge y no sólo sobre la rama. **`make screens` → 66 capturas,
  0 errores.**
- **La base quedó limpia**: 9 desafíos, todos del seed. Los hechos a mano se
  borraron y el respaldo se eliminó, por decisión de Raúl. El stack quedó
  levantado.
- **El 400 del proveedor real se resolvió** (lo confirmó Raúl desde la app), así
  que el punto 1 del handoff anterior está cerrado.

### El push va por HTTPS, y hay una forma limpia de hacerlo

El remoto es SSH y en este entorno no autentica. Lo que funciona **sin tocar la
config global ni exponer el token en la línea de comandos**:

```bash
git -c credential.helper='!gh auth git-credential' \
    push https://github.com/ribarahonaa/innk_flow.git master
```

## Archivos y cambios

### El rol gestor (merge `a6aa59e`, 18 commits)

`ApplicationPolicy#administra?(challenge)` es la regla nueva y vive una sola
vez: `manager? || (membership.present? && membership.gestor? &&
reaches_challenge?(challenge))`. Generaliza la expresión que `curate_pool?` ya
tenía escrita a mano —la única puerta que el gestor tenía hasta ahora—.

**Se aplicó puerta por puerta y no tocando `manages_challenges?`.** Ese atajo
—un carácter de diff— abría membresías, auditoría de IA y biblioteca a todo
gestor de la empresa sin acotar por desafío. Con el predicado explícito, las
tres puertas que quedan cerradas se quedan **porque nadie las tocó**, y eso se
lee en el diff.

Se abrieron 18 puertas por-desafío en seis policies. `configure?` y pedirle
cosas a la IA sobre el desafío se abrieron **solos**, por delegación.
**Ninguna vista hubo que tocar para eso**: los 45 usos de permisos en HAML
preguntan por `policy(...)`, que es donde CLAUDE.md manda que viva la guarda.

Dos huecos que el cambio abría, cerrados acá: el editor de criterios se
renderiza por `configure?` pero guardaba por `CriteriaSetPolicy` (el gestor
veía el editor y no podía guardar), y crear un desafío sin auto-asignarse lo
sacaba de la lista de su propio creador en el mismo movimiento.

**`administra?` tiene una redundancia aparente que es load-bearing.**
`manager? || reaches_challenge?(challenge)` NO es equivalente: abriría todo
para `participant` y `evaluator`, por la rama `return true unless gestor?` de
`reaches_challenge?`. Está comentado en el código; no lo "limpies".

### Lo que encontró la revisión final, y ninguna revisión por tarea podía ver

Las tres estaban en **vistas**, porque la spec dijo «no se toca ninguna vista
salvo la del botón de promover» y eso fue un punto ciego de la spec:

- **Las dos pantallas donde se otorga el acceso describían el rol al revés.**
  `_gestores.html.haml` decía «No evalúan ni configuran» y `es.yml` decía
  «Acompaña la evolución». Las dos eran ciertas antes y pasaron a ser falsas.
  Son los dos únicos lugares donde una persona decide entregar este poder.
- **Dos links con 403 garantizado** («Ver el set», «Editar el set»): gateaban
  por `update_pipeline?` y su destino exige `manager?`. El principio del
  arreglo: **la guarda de un link pregunta lo mismo que autoriza su destino**.
- **`create?` abierto sin entrada en la UI**: los dos únicos
  `new_challenge_path` colgaban de `manages_challenges?`.

### La regla de idioma (commits `274fd20`, `9dd1302`, `e7b0b4c`)

**`CLAUDE.md:9` decía «El código, los comentarios y los mensajes de commit van
en español»**, desde el primer commit de la guía (2026-09-02). Todo el repo se
escribió bajo esa regla. Raúl esperaba lo contrario: **código en inglés,
comentarios en español**.

Medido antes de tocar nada, para que la decisión de alcance fuera informada:
~40 métodos con nombre en español en `app/` y `lib/` repartidos en 17 archivos,
~25 partials y archivos, los specs enteros, y —lo caro— `challenge_gestores`
como tabla y `"gestor"` como valor de `memberships.role`, que no se renombran
sin migración con cambio de datos.

Lo que se hizo:

- **La regla se corrigió**, con una advertencia explícita de **no renombrar al
  pasar**: un repo migrado a medias es peor que el mix, porque nadie sabe qué
  convención está mirando.
- **`administra?` → `administers?`** y **`acompana?` → `assigned_gestor?`**, los
  dos identificadores en español más nuevos del repo (se habían escrito ese
  mismo día). 34 reemplazos en 12 archivos, comentarios incluidos.
  `administers?` y no `manages_challenge?` porque **`Membership#manages_challenges?`
  ya existe y significa `admin?`**: dos métodos casi homónimos con significados
  distintos son peores que el español.
- **El resto se queda como está**, por decisión de Raúl. La regla rige sólo
  para lo que se escribe de ahora en más.
- **Lo que ya está en la base se queda; toda tabla y columna NUEVA va en
  inglés**, sin excepción.

### El repaso de las capturas (21 de 66 miradas)

Se miraron 21 a mano. Dos hallazgos NO son visuales y se verificaron en la
fuente, no sólo en la imagen:

**Los botones de IA se ofrecen en módulos ya cerrados, y en idear el pedido
además pasa.** `shared/_ai_actions` sólo mira el MODO de IA (`human`) y
`always`: **no hay ninguna guarda de estado del módulo, ni en el partial ni en
ningún llamador**. En `steps/ideation.html.haml` se ve al lado: «Postular una
idea» está gateado por `@step.active?` y el bloque de IA de abajo no. Visto en
«Postulación de ideas · Completado» (con «Generar ideas candidatas») y en
«Ronda de feedback · Completado» (con «Sugerir feedback con IA»).

No queda en lo visual: `GenerateIdeas#apply!` crea ideas sin mirar el estado
del paso, `AiRequestsController` tampoco, y la policy da permiso porque el
DESAFÍO sigue en curso. Las ideas nacen `draft`, así que el daño está acotado
—pero `Flow::Cohort.sync!` arma las `step_entries` al ACTIVAR el módulo, así
que una idea que entre después no tiene fila en ningún lado.

**Quien administra puede sacarse a sí mismo de la empresa.**
`MembershipsController#destroy` guarda contra sacar al ÚLTIMO admin, no contra
sacarse uno mismo: con otro admin en la empresa, «Sacar» sobre la propia fila
funciona y deja afuera en el acto. Es el mismo defecto que se cerró para el
gestor, un nivel más arriba. Preexistente.

**Y una corrección al handoff anterior:** lo de «los `select` no se distinguen
de un campo de texto, sin flecha» **no se ve en ninguna captura**. Todos los
`select` mirados —editor de criterios, modo de IA, roles, colaboradores—
tienen su chevron. O se arregló o se observó mal.

**Un hueco del propio recorrido:** `21-evaluar-idea` usa una idea que **sólo
tiene título** (verificado en la base), así que esa captura no puede detectar
ningún problema de maquetado en la ficha de evaluación con una idea completa.
Es honesta; lo que no sirve es como red.

## Intentos fallidos

**El patrón de la ejecución: los dos únicos hallazgos serios fueron agujeros de
cobertura, no bugs de código.** Ninguna tarea escribió una policy mal. Tiene
sentido para este cambio —abrir un permiso de más no rompe ningún test,
simplemente deja pasar—, así que el riesgo nunca estuvo en el código sino en si
la red existía. Las dos veces el brief que los originó lo había escrito yo.

- **Una fila sin su control de admin** (`IdeaPolicy#destroy?`) pasaba igual con
  la policy rota. Resultó que **ningún test de la suite cubría que un admin
  pueda borrar una idea**.
- **Nada fijaba la polaridad del botón de promover**: un `unless` en vez del
  `if` pasaba la suite entera en silencio. Es el mismo modo de falla que
  `dos_caras_spec.rb:264-267` documenta para la guarda de afuera.

**De ahí salió la práctica que más sirvió: romper la guarda a mano y confirmar
que el test falla.** En las tareas 3 y 5 el resultado fue el necesario —fallaron
sólo los ejemplos nuevos, el resto de la suite quedó verde con el código
roto—, lo que prueba dos cosas de una: que la cobertura nueva sirve y que el
agujero anterior era real.

**Un hook de seguridad bloqueó esa prueba una vez** (`[Security Weaken]`, al
intentar debilitar `configure?`). El subagente no insistió por otra vía y yo
tampoco lo hice desde otra silla. Consecuencia: la cobertura de `configure?`
es la única sostenida sólo por lectura de código.

**Errores míos de esta sesión:**

- **Afirmé que el gestor podría borrar el desafío** y no existe ruta de borrado:
  `resources :challenges, only: %i[index new create show]`. `ChallengePolicy#update?`
  y `#destroy?` son código muerto.
- **Commiteé la spec y el plan directo a `master`** y hubo que moverlos a una
  rama. La convención es rama por tanda.
- **Le puse línea `Co-Authored-By` al primer commit**, contra la regla.
- **La spec excluyó las vistas**, que es de donde salieron los tres hallazgos
  de la revisión final.
- **Conté mal las puertas** («~15» cuando son 18) en un borrador de la spec.
- **El renombre masivo pisó la propia lista de ejemplos de `CLAUDE.md`**, que
  quedó citando `administers?` y `assigned_gestor?` como identificadores en
  español —los dos que acababan de dejar de serlo—. Lo encontré al releer el
  archivo, no por una prueba: **un `sed` sobre la documentación toca también
  los ejemplos que la documentación da sobre sí misma.**

## Próximos pasos

1. **Dos guardas que faltan, salidas del repaso de capturas.** Son lo único
   de esta lista con consecuencia sobre datos:
   - **Ningún bloque de IA mira el estado del módulo.** La guarda va en
     `shared/_ai_actions` —un lugar, seis pantallas— y no en cada llamador:
     hoy el partial sólo sabe del modo de IA. Ojo al decidir el predicado: las
     acciones de AUTORÍA (`always: true`) se ofrecen a propósito fuera del
     trabajo del módulo, así que la guarda de estado no puede taparlas.
     Conviene además cerrar el camino en el servidor y no sólo en la vista:
     `GenerateIdeas#apply!` no mira el estado del paso, y la policy dice que sí
     porque mira el DESAFÍO.
   - **Nadie debería poder sacarse a sí mismo de la empresa.**
     `MembershipsController#destroy` ya tiene la forma del arreglo en
     `quita_al_ultimo_admin?`: es una guarda hermana. Y la vista debería
     esconder el botón sobre la propia fila, como se hizo en
     `challenges/_gestores.html.haml`.

2. **Los menores diferidos del rol gestor**, ninguno bloqueante:
   - Una variable local muerta (`- desafio = step.challenge`) en
     `_referencia_evaluacion.html.haml:8`, que quedó sin uso al arreglar el
     link. Trivial.
   - `AssessmentPolicy#update?` cambió de contrato sin cobertura; hoy no tiene
     llamador vivo en `app/`.
   - Sin cobertura de `CriteriaSetPolicy#update?` con `owner_step: nil`. No se
     alcanza por la app (la FK es `ON DELETE CASCADE`) y **falla cerrado**.
   - «Ver el set» de `_referencia_evaluacion` usa el mismo predicado que su
     hermano pero no tiene test de polaridad propio.
   - La tabla de `gestor_administra_spec.rb` no tiene columna de `participant`
     ni `evaluator`. Seguro por la forma del predicado; tres líneas si se
     quiere la red.

3. **Dos rastros del renombre, dejados a propósito.** No son deuda; están así
   porque la regla nueva dice no renombrar al pasar:
   - **`spec/policies/gestor_administra_spec.rb` conserva el nombre**, aunque
     prueba `administers?`. Renombrar archivos es el principio de la migración
     grande que se decidió NO hacer. Es un `git mv` si alguna vez se quiere.
   - **La spec y el plan en `docs/superpowers/` siguen diciendo `administra?`.**
     Son documentos históricos —el repo ya trata así a los anteriores—: cuentan
     lo que se decidió ese día, no cómo se llama hoy.

4. **Dos preexistentes que merecen rama propia**, los dos confirmados esta
   sesión:
   - **`CriteriaSetPolicy::Scope` achica sólo para el gestor**, así que un
     participante abre **por id** un set `inline` de un desafío que no ve
     (`show?` heredado = `membership.present?`). El índice no lo lista —filtra
     a biblioteca—, así que la fuga es por id, no por listado.
   - **El breadcrumb de `criteria_sets/edit.html.haml`** siempre enlaza a
     `criteria_sets_path`, que sólo lista biblioteca: para un set `inline` la
     vuelta va a una lista que nunca lo muestra.

5. **Lo que sigue abierto de handoffs anteriores:**
   - **Las 45 capturas que todavía no se miraron.** De las 21 que sí, lo
     visual pendiente, ordenado por si conviene arreglarlo una vez o doce:
     · **La previsualización se repite a sí misma en 5 de 7 tarjetas**, no
     sólo en testing: cada una imprime la descripción genérica del `kind` y
     después la concreta, y dicen lo mismo. Son DOS fuentes de descripción que
     nadie coordinó.
     · **El popup de la IA muestra el mismo contenido tres veces**: el título
     dice «La IA respondió», la primera línea del cuerpo lo repite, y el bloque
     que muestra ya está renderizado detrás en el panel de propuestas.
     · **El desglose muestra las CLAVES y no los nombres** de los criterios
     (`esfuerzo`, `factibilidad`) en monospace, mientras la columna derecha
     muestra «Esfuerzo», «Factibilidad».
     · **El drawer se corta donde termina su contenido**, no al fondo de la
     página. Se ve muchísimo más en modo oscuro.
     · **La tarjeta «Brief» tiene un hueco muerto** y el texto flota a media
     altura. Las de «Todavía nadie dio feedback» igual.
     · **«En curso» es el único estado sin badge** en la tabla del flujo.
     · **Las filas etiqueta/valor de «Cómo quedó configurado» se encabalgan**
     cuando cualquiera de los dos lados es largo, y el valor va en monospace,
     que lo hace parecer texto de debug. Testing y reportería, claro y oscuro.
     · **Separadores colgando al final de renglón** (el `›` del flujo, el `·`
     antes del autor) cuando el contenido envuelve.
     · **La columna «Acción» apila los botones**: «Re-testear» parte en dos
     renglones y el botón «IA» cae debajo con otro ancho.
     · **«3 / 2»** se lee como «3 de 2»: el segundo número es el mínimo.
     · **«Armar el flujo con IA»** es un título que promete una acción y cuyo
     cuerpo explica que no se puede; no tiene ningún control.
     · **El embudo dibuja barras en gris plano**, no con la rampa `--dato`.
     · **«Distribución de puntajes» tiene dos filas de números** bajo el eje y
     se lee como dos ejes.
     · **«Quién evalúa» duplicado**: la copia de los ajustes omite el peso,
     que es lo único que distingue a esa persona.
   - **`Pipeline#validate` vs `Selection#can_activate?`**: una selección de
     sólo filtros no arranca el flujo salvo que se le declare el puntaje
     manual. Hay tres lugares documentando el mismo rodeo. Merece issue propio.
   - **Las once FKs con `ON DELETE SET NULL` sin acotador.** El helper ya está
     arreglado, las viejas no.
   - **`[FORMS]` no cubre las pantallas de formulario a las que se llega por
     clic.**
   - **Cuatro menores del módulo de testing**, diferidos con triage.
   - **Plan 2c** (el resto de las islas Vue), `SelectionsController#update` sin
     validación server-side, `criteria_sets#show` huérfana, las 3 consultas de
     evolución, los tres temas de seguridad preexistentes, y que nada vigila el
     relleno por default de `card` desde que se retiró `[CARD]`.

## Decisiones de Raúl en esta sesión

- **Limpiar la base dejando sólo los desafíos del seed**, y **borrar el
  respaldo** con los hechos a mano.
- **Gestor = admin en sus desafíos**, y no el punto medio ni el cambio acotado
  a testear.
- **De las puertas que no cuelgan de un desafío, sólo se abre crear desafíos**:
  membresías, auditoría de IA y biblioteca de criterios siguen siendo de admin.
- **Equivalencia completa**: la apertura pisa las dos reglas que acotaban al
  gestor (editar una idea sólo con la ronda abierta, evaluar sólo con
  asignación). Quedan las dos exclusiones por conflicto de interés, que son de
  otro eje.
- **Ejecutar el plan por subagentes**, no inline.
- **Mergear a master y pushear.**
- **El código va en inglés y los comentarios en español**, contra lo que decía
  `CLAUDE.md` desde el primer commit de la guía.
- **Migrar sólo `administra?` y `acompana?`**, no el resto: «es mucho lo
  anterior». La regla rige para lo nuevo y nada más que para eso.
- **Lo que ya está en la base se queda** —`challenge_gestores`, el valor
  `"gestor"`— **pero toda tabla nueva va en inglés.**
