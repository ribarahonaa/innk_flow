# Handoff

## Objetivo

Tres cosas, en este orden: las dos guardas que faltaban del punto 1 del
handoff anterior (la IA sobre módulos cerrados y la autobaja de la empresa),
descartar o confirmar la «fuga» de criterios, y **mirar las 66 capturas** —de
las que sólo se habían mirado 21 en cinco sesiones— y arreglar lo que saliera.

## Estado actual

- **`master` está en `1f73410` y pusheado** (verificado con `gh api`, no con
  `git rev-parse origin/master`, que lee una foto local). Encima quedó
  **`b006b1d` sin pushear**: la corrección al handoff sobre la fuga de
  criterios.
- **La rama `repaso-de-capturas-arreglos` tiene 5 commits sin mergear**, uno
  por arreglo. No se mergeó ni se pusheó: queda a decisión de Raúl.
- **`make spec` → 1109 ejemplos, 0 fallas** (venía de 1092 al empezar la
  sesión) y **`make screens` → 66 capturas, 0 errores**.
- El stack quedó levantado. La base no se tocó.

### El push, que en este entorno no es obvio

El remoto es SSH y acá no autentica. Sin tocar la config global ni exponer el
token:

```bash
git -c credential.helper='!gh auth git-credential' \
    push https://github.com/ribarahonaa/innk_flow.git master
```

### Decisiones de Raúl en esta sesión

- Arrancar por las dos guardas, juntas y en rama propia; `summarize_challenge`
  entra en la lista de tareas que exigen módulo abierto.
- Mergear esas dos a master localmente, sin PR; el push lo hizo él.
- Entrarle a la fuga de criterios (que resultó no existir) y después a las
  capturas.
- De los hallazgos del repaso, arreglar **los cinco de una línea** y dejar el
  resto anotado.

## Archivos y cambios

### Mergeado a master: las dos guardas (`fa697ea`, `92d66b5`)

**La IA no trabaja sobre un módulo cerrado.** La regla estaba escrita a mano
en cada llamador de `shared/_ai_actions` y de los ocho sólo cuatro la tenían.
Ahora la declara la tarea (`requires_active_step?`) y la consultan tres
puertas: el partial, `AiSuggestionPolicy#accept?` —que al ser también
`request?` cubre el pedido y el aceptar tardío— y `StepsController
#evaluate_all`. En `true`: `generate_ideas`, `suggest_feedback`,
`decide_verdicts`, `evaluate_idea`, `test_idea`, `summarize_challenge`.

**Nadie se saca a sí mismo de la empresa.** `quita_al_ultimo_admin?` no cubría
sacarse uno mismo. Guarda hermana de la de `ChallengeGestoresController`.

### Sin mergear: los cinco arreglos del repaso

| Commit | Qué |
|---|---|
| `44edc2f` | La línea de corte decía el literal «TOP N». Ahora el número va dentro del nombre y lo compone `Selection.cut_rule_label`, que consultan los tres lugares. |
| `e42cbc8` | `succeeded` y `accepted` eran los únicos chips en inglés, y en la pantalla de auditoría. |
| `0e81df8` | El párrafo de los estados vacíos estaba 351px a la izquierda. Con guarda `[VACIO]`, verificada rompiéndola. |
| `3edec28` | «1 de 1 comentario atendidos». |
| `f74580f` | La fila propia de Miembros perdía la alineación al esconder «Sacar». |

## Intentos fallidos

**Tres afirmaciones del handoff anterior no resistieron mirar la fuente, y una
cuarta la aportó `CLAUDE.md`. Tratá esos documentos como pistas, no como
inventario.**

- **«No hay ninguna guarda de estado, ni en el partial ni en ningún
  llamador»** — falso: cuatro de los ocho llamadores la tenían escrita a mano.
  Eso cambió la forma del arreglo: no era agregar una guarda, era moverla a un
  lugar donde no se pueda olvidar.
- **La «fuga» de `CriteriaSetPolicy::Scope` no existe.** Su premisa —un set
  `inline` «de un desafío que no ve»— es falsa para participante y evaluador:
  `reaches_challenge?` sale por `true unless gestor?`, así que ven todos los
  desafíos de la empresa, y esos mismos criterios ya los veían en la columna
  de referencia del módulo. Medido por rol: participante, evaluador y admin
  200; **gestor no asignado 404** en las dos puertas. El único rol donde la
  premisa se sostenía ya estaba cerrado. Queda una nota defensiva que NO se
  implementó: el `Scope` sale por `scope.all unless gestor?`, o sea que un rol
  nuevo nacería abierto.
- **«El embudo dibuja barras en gris plano, no con la rampa `--dato`»** —
  falso: `application.css:1598` y `:1617` usan `--dato` y `--dato-fuerte`. El
  gris ES la rampa, sacada del texto a propósito porque el acento está
  reservado para las acciones.
- **«El drawer se corta donde termina su contenido»** — casi seguro un
  artefacto de la captura. El fondo lo pinta `bg-neutral` sobre
  `%aside.flow-drawer`, un grid item con `grid-row: 1 / span 2`: se estira
  siempre. Lo que pasa es que `.flow-drawer__panel` es `position: sticky`, y
  en un screenshot de página completa cosido el sticky se dibuja donde estaba
  al scroll del momento — en `22b-testeo-nuevo` sale centrado verticalmente en
  una página de 1908px.
- **Dos cosas más que no eran defectos:** el módulo salteado SÍ se distingue
  en el mapa del flujo (`estilos_helper.rb:131`, `border-dashed`), y «Falta N
  ideas por testear» arriba a la derecha es `.page-head__note`, un componente
  deliberado.

**El diseño aprobado tenía una tarea de más, y lo descubrió grepear los specs
ANTES de escribir código.** Incluía `evolve_idea`, y `gestor_spec.rb:409`
afirma lo contrario a propósito: es la decisión del rol gestor. Implementándolo
primero, la falla habría llegado disfrazada de «un test que arreglar».

**`make screens` estaba FIJANDO uno de los bugs.** El chequeo del selector de
cantidad miraba el módulo de idear de `merma-bodega`, que está cerrado: exigía
que el botón siguiera ofrecido justo donde el handoff lo había visto mal. Pasó
a `recorrido-ia`. **Sacar un bug puede poner en rojo un test que lo afirmaba**,
y hay que mirar cada falla antes de decidir eso.

**Y una pista no visual que tampoco era un bug:** en la auditoría, cada pedido
de `detect_duplicates` aparece dos veces. No es doble ejecución:
`capture_screens.js` lo pide dos veces por corrida (el clic de la línea 1389 y
el `requestSubmit()` de la 1462, para la guarda del morph).

**Lo que funcionó y conviene repetir:** romper cada guarda a mano y confirmar
que falla **sólo** lo nuevo. Se hizo con las cinco guardas de la primera tanda,
con la polaridad del `unless` de Miembros y con la guarda `[VACIO]`.

## Próximos pasos

1. **Decidir qué hacer con `repaso-de-capturas-arreglos`** (5 commits, verde) y
   pushear `b006b1d`.

2. **Hallazgos del repaso que quedaron SIN arreglar.** Ninguno es de datos:
   - **Dos personas, el mismo chip:** en el desglose de evaluación, Elena
     Evaluadora y Emilio Evaluador son las dos «EE». No hay forma de saber
     quién puso qué.
   - **El prompt de la auditoría se corta** a la derecha sin scroll ni wrap
     (`14-ai-run`): la pantalla que existe para auditar no muestra lo que se
     mandó.
   - **`Choose File / No file chosen` sin estilo** en el formulario real de
     postulación (`16-idea-new`), no sólo en la previsualización.
   - **`18-select-company`:** el rol va fuera del botón de cada empresa, así
     que se lee como etiqueta del botón siguiente; y el header muestra «Marta
     Multiempresa —» con un separador colgando.
   - **El popup de espera** (`09-13-ia-espera`) sale translúcido y sin
     backdrop; el de respuesta no. O falta el backdrop, o la captura no espera
     a que termine la transición — y las capturas tienen que ser
     deterministas.
   - **Tres inconsistencias sistémicas**, cada una un arreglo en muchos
     lugares: el estado se dibuja de tres formas (badge / texto de color /
     palabra gris con borde izquierdo); el monospace se usa para prosa y para
     números, que es lo que hace parecer debug a «Cómo quedó configurado» y a
     media docena de lugares más; y «N de M · ahora: X» se lee como posición
     cuando cuenta módulos terminados.
   - **Lo visual ya conocido que sigue en pie:** la previsualización que se
     repite a sí misma en 5 de 7 tarjetas, el popup de la IA que dice lo mismo
     tres veces, el desglose con claves en vez de nombres, el hueco muerto del
     Brief, «En curso» sin badge, «Cómo quedó configurado» encabalgado, los
     separadores colgando, la columna «Acción» que apila, el «3 / 2», «Armar
     el flujo con IA» sin controles con el flujo arrancado, «Distribución de
     puntajes» con dos filas de números y «Quién evalúa» duplicado sin el peso.

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
   las que se llega por clic; los cuatro menores del módulo de testing; el
   plan 2c (el resto de las islas Vue), `SelectionsController#update` sin
   validación server-side, `criteria_sets#show` huérfana, las 3 consultas de
   evolución, los tres temas de seguridad preexistentes, y que nada vigila el
   relleno por default de `card` desde que se retiró `[CARD]`.
