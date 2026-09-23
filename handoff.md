# Handoff

## Objetivo

Cuatro cosas, en este orden: las dos guardas que faltaban del punto 1 del
handoff anterior (la IA sobre módulos cerrados y la autobaja de la empresa),
confirmar o descartar la «fuga» de criterios, **mirar las 66 capturas** —de las
que sólo se habían mirado 21 en cinco sesiones— y arreglar los hallazgos que
Raúl fue eligiendo.

## Estado actual

- **`master` está en `3c48565` y quedan 4 commits SIN pushear.** El remoto está
  en `5d0714c`, verificado con `gh api` y no con `git rev-parse origin/master`,
  que lee una foto local. Sin ramas vivas, árbol limpio.
- **`make spec` → 1115 ejemplos, 0 fallas** (venía de 1092 al empezar) y
  **`make screens` → 66 capturas, 0 errores**. Las dos corridas sobre el
  resultado de cada merge, no sólo sobre la rama.
- El stack quedó levantado. La base no se tocó.

### El push, que en este entorno no es obvio

El remoto es SSH y acá no autentica. Sin tocar la config global ni exponer el
token en la línea de comandos:

```bash
git -c credential.helper='!gh auth git-credential' \
    push https://github.com/ribarahonaa/innk_flow.git master
```

### Decisiones de Raúl en esta sesión

- Arrancar por las dos guardas, juntas y en rama propia. `summarize_challenge`
  entra en la lista de tareas que exigen módulo abierto: era lo único que
  quedaba en duda al aprobar el diseño.
- Entrarle a la fuga de criterios —que resultó no existir— y después a las
  capturas.
- De los hallazgos del repaso: primero **los cinco de una línea**, después **las
  iniciales ambiguas y el prompt truncado**. El resto queda anotado.
- Mergear cada tanda a master localmente, sin PR.

## Archivos y cambios

### Tanda 1 — las dos guardas (`fa697ea`, `92d66b5`, merge `1e654fd`)

**La IA no trabaja sobre un módulo cerrado.** La regla estaba escrita A MANO en
cada llamador de `shared/_ai_actions` y de los ocho sólo cuatro la tenían.
Ahora la declara la tarea (`requires_active_step?`) y la consultan tres
puertas: el partial —un lugar, así que el próximo llamador no se la puede
olvidar—, `AiSuggestionPolicy#accept?`, que al ser también `request?` cubre el
pedido Y el aceptar tardío de una propuesta pendiente, y
`StepsController#evaluate_all`, que no pasa por el partial. En `true`:
`generate_ideas`, `suggest_feedback`, `decide_verdicts`, `evaluate_idea`,
`test_idea`, `summarize_challenge`.

**Nadie se saca a sí mismo de la empresa.** `quita_al_ultimo_admin?` guardaba
contra quedarse sin nadie que administre, no contra sacarse uno mismo. Hermana
de la guarda que `ChallengeGestoresController#destroy` ya tenía un nivel más
abajo.

### Tanda 2 — los cinco de una línea (merge `5d0714c`)

| Commit | Qué |
|---|---|
| `44edc2f` | La línea de corte decía el literal «TOP N». El número va dentro del nombre y lo compone `Selection.cut_rule_label`, que consultan los **tres** lugares: la línea de corte, «Cómo se decide» —que dejó de repetirlo en un «· 3» aparte— y la pista del drawer en `Flow::Setup`. |
| `e42cbc8` | `succeeded` y `accepted` eran los únicos chips en inglés, y en la pantalla de auditoría. |
| `0e81df8` | El párrafo de los estados vacíos estaba 351px a la izquierda. Con guarda `[VACIO]`. |
| `3edec28` | «1 de 1 comentario atendidos». |
| `f74580f` | La fila propia de Miembros perdía la alineación al esconder «Sacar» (regresión de la tanda 1). |

### Tanda 3 — las iniciales y el prompt (merge `3c48565`)

**`ff1ae45`.** «Elena Evaluadora» y «Emilio Evaluador» daban las dos «EE».
`Flow::Texto.initials` estira el nombre de pila, sólo él y sólo cuando choca:
«ElE», «EmE», con «GG» quieto al lado. **Desempata contra el grupo del MÓDULO y
no el de la fila** —se arma una vez en `evaluation.html.haml` y baja como
local—: si dependiera de quién evaluó cada idea, la misma persona saldría «EE»
en una fila y «ElE» en la de al lado. No resuelve dos personas con el mismo
nombre de pila y la misma inicial de apellido; está anotado en el código.

**`850bc70`.** El prompt de la auditoría medía 2.635px más que su tarjeta, casi
cuatro veces su ancho. `pre-wrap` en vez de la barra horizontal, con guarda
`[CODIGO]`.

## Intentos fallidos

**Lo más valioso de la sesión: CINCO ítems del backlog no resistieron mirar la
fuente. Tratá el handoff y `CLAUDE.md` como pistas, no como inventario.**

- **«No hay ninguna guarda de estado, ni en el partial ni en ningún
  llamador»** — falso: cuatro de los ocho llamadores la tenían escrita a mano.
  Cambió la forma del arreglo: no era agregar una guarda, era moverla adonde no
  se pueda olvidar.
- **La «fuga» de `CriteriaSetPolicy::Scope` no existe.** Su premisa —un set
  `inline` «de un desafío que no ve»— es falsa para participante y evaluador:
  `reaches_challenge?` sale por `true unless gestor?`, así que ven todos los
  desafíos de la empresa, y esos criterios ya los veían en la columna de
  referencia del módulo. Medido por rol: participante, evaluador y admin 200;
  **gestor no asignado 404** en las dos puertas. El único rol donde la premisa
  se sostenía ya estaba cerrado. Queda una nota defensiva que NO se implementó:
  el `Scope` sale por `scope.all unless gestor?`, o sea que un rol nuevo nacería
  abierto.
- **«El embudo dibuja barras en gris plano, no con la rampa `--dato`»** —
  falso: `application.css:1598` y `:1617` usan `--dato` y `--dato-fuerte`. El
  gris ES la rampa, sacada del texto a propósito porque el acento está
  reservado para las acciones.
- **«El drawer se corta donde termina su contenido»** — artefacto de la
  captura. El fondo lo pinta `bg-neutral` sobre `%aside.flow-drawer`, un grid
  item con `grid-row: 1 / span 2`: se estira siempre. Lo que pasa es que
  `.flow-drawer__panel` es `position: sticky`, y en un screenshot de página
  completa cosido el sticky se dibuja donde estaba al scroll del momento —en
  `22b-testeo-nuevo` sale centrado verticalmente en una página de 1908px—.
- **Dos más que no eran defectos:** el módulo salteado SÍ se distingue en el
  mapa del flujo (`estilos_helper.rb:131`, `border-dashed`), y «Falta N ideas
  por testear» arriba a la derecha es `.page-head__note`, deliberado.

**Y un hallazgo PROPIO mal diagnosticado.** Reporté que el prompt de la
auditoría «se corta sin scroll ni wrap»: `.code-block` ya tenía
`overflow-x: auto`, o sea que scrolleaba. El problema era real, la causa no —no
faltaba la salida, la salida era mala—. Lo agarré leyendo la hoja antes de
escribir el arreglo. **Mis hallazgos tampoco son inventario.**

**El diseño aprobado tenía una tarea de más, y lo descubrió grepear los specs
ANTES de escribir código.** Incluía `evolve_idea`, y `gestor_spec.rb:409`
afirma lo contrario a propósito: es la decisión del rol gestor. Implementándolo
primero, la falla habría llegado disfrazada de «un test que arreglar», que ahí
era revertir una decisión en silencio.

**`make screens` estaba FIJANDO uno de los bugs.** El chequeo del selector de
cantidad miraba el módulo de idear de `merma-bodega`, que está cerrado: exigía
que el botón siguiera ofrecido justo donde el handoff lo había visto mal. Pasó
a `recorrido-ia`. **Sacar un bug puede poner en rojo un test que lo afirmaba**,
y hay que mirar cada falla antes de decidir eso.

**Un spec se acoplaba a un setup que no le correspondía.**
`panel_de_propuestas_spec` hacía `pipeline.advance!` en un `before` de arriba
para abrir la evolución —lo necesitaba un solo describe— y de paso cerraba la
ideación, que era la pantalla que otro describe miraba. Bajó al describe que lo
usa; ninguna aserción cambió.

**Una pista no visual que tampoco era un bug:** en la auditoría, cada pedido de
`detect_duplicates` aparece dos veces. `capture_screens.js` lo pide dos veces
por corrida (el clic de la línea 1389 y el `requestSubmit()` de la 1462, para
la guarda del morph).

**Una desviación del proceso, deliberada y que conviene repetir:** no se usó
worktree. El stack de Docker está atado a `/home/ribarahonaa/innk_flow`, así que
`make spec` desde un worktree correría contra otro compose.

**Lo que funcionó:** romper cada guarda a mano y confirmar que falla **sólo** lo
nuevo. Se hizo con las cinco guardas de la tanda 1, con la polaridad del
`unless` de Miembros, con `[VACIO]` (marca los 351px) y con `[CODIGO]` (marca
los 2.635px).

## Próximos pasos

1. **Pushear `master`**: 4 commits (ver el comando arriba).

2. **Lo que sigue abierto del repaso de capturas.** Ninguno es de datos:
   - **Las tres inconsistencias sistémicas.** Son las que más rinden por
     arreglo —tocan muchas pantallas— y las únicas que **no** son de una línea:
     hay que decidir un vocabulario antes de tocar nada.
     · **El estado se dibuja de tres formas:** badge en la ficha del desafío y
     en el builder en borrador; **texto de color sin badge** en el builder con
     el flujo arrancado; y en «Cómo le fue» de la idea, una palabra gris con un
     borde izquierdo de 3px cargando toda la distinción. Es la que más confunde
     y por la que arrancaría.
     · **Monospace para prosa y para números:** «veredicto por idea», «pasó su
     prueba de factibilidad, con reservas o sin ellas; sin testear, no pasa»,
     los pesos (40%, 25%), las claves de criterio, «Por versión: cada puntaje
     dice qué versión se evaluó». Es lo que hace parecer volcado de debug a
     «Cómo quedó configurado», y el problema no está sólo ahí.
     · **«N de M · ahora: X» se lee como posición y no lo es:** en `04` dice
     «6 de 7 · ahora: Reporte de cierre», que es el módulo 7. Cuenta módulos
     terminados o salteados. Misma familia que el «3 / 2».
   - **`Choose File / No file chosen` sin estilo** en el formulario real de
     postulación (`16-idea-new`), no sólo en la previsualización. Es el único
     control nativo sin tocar de la app.
   - **`18-select-company`:** el rol va fuera del botón de cada empresa, abajo
     a la izquierda, así que se lee como etiqueta del botón siguiente; y el
     header muestra «Marta Multiempresa —» con un separador colgando.
   - **El popup de espera** (`09-13-ia-espera`) sale translúcido y sin
     backdrop; el de respuesta no. O falta el backdrop, o la captura no espera
     a que termine la transición — y si es lo segundo es peor, porque esa
     captura no sería determinista.
   - **Lo visual ya conocido que sigue en pie:** la previsualización que se
     repite a sí misma en 5 de 7 tarjetas, el popup de la IA que dice lo mismo
     tres veces, el desglose con claves en vez de nombres, el hueco muerto del
     Brief, «En curso» sin badge, «Cómo quedó configurado» encabalgado, los
     separadores colgando, la columna «Acción» que apila, «Armar el flujo con
     IA» sin controles con el flujo arrancado, «Distribución de puntajes» con
     dos filas de números y «Quién evalúa» duplicado sin el peso.

3. **Sobre el recorrido como red:** dos pares de capturas son la MISMA pantalla
   (`03c-paso-a-paso` = `09-10-form-vacio`, `05e-config-seleccion` =
   `09-12-criterios-del-modulo`), así que las 66 capturas no son 66 pantallas.

4. **Los menores diferidos del rol gestor** (variable muerta en
   `_referencia_evaluacion.html.haml:8`, `AssessmentPolicy#update?` sin
   cobertura ni llamador vivo, `CriteriaSetPolicy#update?` con
   `owner_step: nil`, «Ver el set» sin test de polaridad, la tabla de
   `gestor_administra_spec.rb` sin columnas de `participant` ni `evaluator`) y
   **dos rastros del renombre dejados a propósito** (el nombre de
   `gestor_administra_spec.rb` y los documentos de `docs/superpowers/`).

5. **El backlog largo, intacto:** el breadcrumb de `criteria_sets/edit` que
   para un set `inline` vuelve a una lista que nunca lo muestra;
   `Pipeline#validate` vs `Selection#can_activate?`; las once FKs con
   `ON DELETE SET NULL` sin acotador; `[FORMS]` que no cubre las pantallas a
   las que se llega por clic; los cuatro menores del módulo de testing; el plan
   2c (el resto de las islas Vue), `SelectionsController#update` sin validación
   server-side, `criteria_sets#show` huérfana, las 3 consultas de evolución,
   los tres temas de seguridad preexistentes, y que nada vigila el relleno por
   default de `card` desde que se retiró `[CARD]`.
