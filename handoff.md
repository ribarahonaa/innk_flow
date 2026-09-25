# Handoff

## Objetivo

Cerrar los cuatro menores que el handoff anterior dejaba «con el terreno
medido»: el memo de la ficha de evaluación, `skip!` sobre un módulo terminado,
`StepNotReady` sin rescate y la ceguera de `[MONO]` a la prosa partida.

Los cuatro están cerrados, y la revisión de rama destapó un quinto —la ficha de
evaluación DE VERDAD conservaba el fan-out— que se cerró en la misma tanda.

## Estado actual

- **El merge quedó en `01afef4`; encima de él va sólo este handoff, así que la
  punta de `master` es el commit siguiente.** (El handoff anterior decía «master
  está en X» apuntando al merge y no a la punta, y esa línea confundió al
  abrirlo.) Pusheado, sin ramas vivas, árbol limpio.
- **`make spec` → 1149 ejemplos, 0 fallas** (venía de 1141) y **`make screens`
  → 66 capturas, 0 errores**.
- El árbol del merge es idéntico al de la rama.
- El stack quedó levantado. La base no se tocó.

### Decisiones de Raúl en esta sesión

Una sola tanda, con el formato de siempre: diseño corto en el chat (bounded,
sin spec ni plan en `docs/`), ejecución nativa, revisión de rama al final,
merge `--no-ff` a master y push, sin PR. «Avisame cuando termine»: autonomía de
punta a punta, merge incluido.

Se le ofreció acotar dos cosas del diseño —dejar `start!` afuera del punto 3, y
que `skip!` siguiera devolviendo el step con el mensaje resuelto en el
controller— y no acotó ninguna.

## Archivos y cambios

Un merge: `01afef4`. Cinco commits: `ac19eff` (el memo), `5912893` (el salteo
de un módulo terminado), `2f8b703` (los rescates), `e9f27ed` (`[MONO]`) y
`c0ee2ab` (lo que encontró la revisión).

**El memo de los criterios, en las DOS pantallas.** `Evaluation#snapshot_records`
trae las filas vivas del snapshot en una consulta. Lo usan `criteria_preview`
—la previsualización de quien configura— y `assessments/new`, que es la ficha
que se completa una vez por idea. La segunda no estaba en el plan: la encontró
la revisión, y es la que pesa.

**`skip!` no reescribe un módulo que ya terminó.** Se niega sobre `completed?` o
`skipped?` y devuelve `false`; el controller lee esa respuesta para el aviso en
vez de repetir el predicado.

**Los tres rescates de `StepNotReady`, afuera del `with_lock`.** `start!`,
`advance!` y `continue!` devuelven un `failure` en vez de morir con 500.

**`[MONO]` une los nodos de texto propios con espacio.** Dos fragmentos
separados por un hijo inline ya no se fusionan en un falso identificador.

## Intentos fallidos

### Dos datos del handoff anterior que estaban mal, y los dos cambiaban el arreglo

- **«Hoy nadie lo alcanza así» (sobre `skip!`) era falso.**
  `ChallengeStepPolicy#skip?` es `administers?(challenge)` y no mira el estado
  del módulo, así que la ruta llega a uno completado. No era una guarda
  preventiva: era un defecto vivo, misma superficie que el bug de salteo de la
  tanda anterior —sin control en ninguna vista, pero la ruta y la policy sí—.

- **El ejemplo con el que `[MONO]` estaba documentado no tiene el bug que
  ilustra, y falla de dos formas a la vez.** `<span>Impacto<b>·</b>Numérico</span>`:
  (a) el `<b>` se reporta por su cuenta, porque «·» no es identificador, así que
  la guarda «dispara» y la falta del padre queda tapada; y (b)
  «ImpactoNumérico» no pasa `^[A-Za-z0-9_.-]+$` por la tilde, así que ese padre
  se reportaba igual. Un autotest escrito con ese caso pasa en verde con el
  defecto adentro. El caso que quedó va sin tilde y con separador sin texto
  propio, que es la única combinación que se escapaba. La (b) la encontró la
  revisión; yo había corregido sólo la (a) y repetido el ejemplo acentuado en
  la prosa y en el mensaje del commit.

### Una guarda mía que medía el costo y no la corrección

El conteo de consultas de `previews_spec` no ataba nada de lo que el memo tiene
que producir: el NOMBRE del criterio lo pinta el snapshot, así que con
`snapshot_records` devolviendo `{}` las consultas desaparecen, el conteo pasa y
el `include("Impacto","Riesgo","Costo")` sigue verde mientras la ficha se
degrada a «Criterio sin escala resoluble.» en los tres. Es el mismo mecanismo
que el inventario anterior ya listaba: una aserción que el código roto también
satisface. Lo ata el `name="scores[impacto]"`, que sólo existe si la fila viva
resolvió su escala.

**La regla que queda: un conteo de consultas mide el costo, nunca la
corrección. Va siempre con una aserción sobre lo que se pinta, en el mismo
ejemplo.**

### Un identificador en español escrito bajo la regla nueva

`no_pudo_abrir` fue el primero desde que CLAUDE.md dice que el código va en
inglés. Lo cazó la revisión; pasa a `not_ready_failure`, y el helper nuevo del
spec a `with_broken_set!`. La regla es fácil de violar justo donde el resto del
archivo está en español (comentarios) y el método es privado.

### Lo que funcionó

**Mutar de a un eje por vez.** La posición del `rescue` no se prueba sacándolo
—eso sólo devuelve la excepción cruda— sino MOVIÉNDOLO adentro del lock: ahí el
ejemplo falla por el módulo que quedó completado, que es lo único que demuestra
que el diseño es la posición y no el `rescue`. Lo mismo con `skip!`: la mutación
útil fue guardar el RETURN dejando viva la escritura, para que las aserciones
de estado tuvieran que fallar solas y no taparse con el mensaje.

### Cosas del entorno

- El harness sigue inyectando `Co-Authored-By` por system-reminder en cada
  sesión; hay que cortarla a mano. En los cinco commits no quedó.
- `git merge -F -` no lee de stdin: el mensaje va a un archivo primero.

## Próximos pasos

1. **Lo que la revisión dejó anotado y no se tomó, con el motivo:**
   - **El aviso de «no está listo» no dice QUÉ módulo.** Con dos evaluaciones
     en el flujo, «el set necesita al menos un criterio activo» no alcanza para
     saber a cuál ir. El arreglo prolijo es sumar el nombre a los errores de
     `Evaluation#can_activate?` —`Ideation` y `Selection` ya lo incluyen—, que
     es un cambio de texto del dominio con su propia guarda.
   - **`db/seeds.rb` ignora los `Result` de `advance!`.** No lo abre esta rama:
     el seed ya ignoraba los failures de `can_complete?` desde siempre, y su
     convención declarada es tratar el Result como valor y mostrar el estado
     por `puts` (`seeds.rb:722`). Si algún día se quiere ruidoso, es un `raise`
     en un helper del seed y no en once llamadas.
   - **El mismo `Criterion.find_by` por criterio queda en caminos de ESCRITURA**:
     `score_assessment.rb:48,131`, `ai/tasks/evaluate_idea.rb:121,170` y
     `assessments_controller.rb:94`. El memo aplica igual; ninguno estaba en el
     backlog.
   - **`Flow::Steps::ActivateJob:22` deja escapar `StepNotReady`.** Es un job:
     fallar fuerte y reintentar es lo correcto, y por eso no se tocó.

2. **Dos capacidades de dominio sin control en ninguna vista**, que es por lo
   que sus defectos sobreviven sin que nada los toque: **saltear un módulo**
   (`post :skip`) y **cerrar un desafío a mano** (`post :close`). Las dos tienen
   policy, cobertura y funcionan; ofrecerlas es decisión de producto y no se
   tomó. Si se ofrece el salteo, ojo con dos cosas ya anotadas: saltear un
   módulo PENDIENTE sube el piso de inserción y congela los pendientes
   anteriores; y `ChallengeStepPolicy#skip?` dice que sí también sobre un módulo
   cerrado, así que el control tiene que preguntar por el estado —el predicado
   vive en `Handlers::Base#skip!` y no se duplica—.

3. **Una convención sin decidir:** conviven dos concordancias para la misma
   forma de frase — `ideas/show:114` concuerda el adjetivo con el TOTAL («1 de 3
   comentarios atendidos») y el drawer con la CUENTA («1 de 3 listo»). Las dos
   se defienden en español. Si se quiere una sola regla, el lugar es una línea
   al lado de `Flow::Texto.plural`.

4. **Lo que sigue midiendo el terreno, del inventario anterior:**
   - El **«3 / 2»** de `steps/_celdas_de_evaluacion.html.haml:9` (evaluaciones
     hechas sobre el mínimo, con el numerador capaz de pasar al denominador) y
     el **«N / M»** de `steps/reporting.html.haml:134`.
   - El `min-width: 110px` del criterio del desglose alinea la columna de
     puntajes **sólo mientras cada nombre entre en 110px**. El comentario ya lo
     dice y propone la forma.
   - **El falso positivo que habilita el `join(' ')` de `[MONO]`**: dos
     identificadores separados por un hijo SIN texto —«v3» + ícono + «v4»— leen
     como prosa. Hoy da cero en las 66 pantallas; cuando aparezca, la respuesta
     es darle a cada identificador su propio elemento mono, no aflojar el join.
     Está escrito al lado del cambio.

5. **Lo visual que sigue en pie del repaso de capturas:** `Choose File / No file
   chosen` sin estilo en `16-idea-new`; `18-select-company` con el rol fuera del
   botón y el separador colgando; el popup de espera sin backdrop
   (`09-13-ia-espera`); la previsualización que se repite a sí misma en 5 de 7
   tarjetas; el popup de la IA que dice lo mismo tres veces; el hueco muerto del
   Brief; «Cómo quedó configurado» encabalgado; la columna «Acción» que apila;
   «Armar el flujo con IA» sin controles con el flujo arrancado; «Distribución
   de puntajes» con dos filas de números; «Quién evalúa» duplicado sin el peso.

6. **Los minors diferidos de la revisión de la pastilla**, ninguno urgente:
   `[PASTILLA]` no asegura «midió al menos N» por pantalla; la regla de
   `currentColor` debilita `[CLASES]` para los chips suaves; un borde punteado
   se acredita como pastilla entera; `flow.entry_statuses.skipped` huérfano en
   `es.yml`; los números del comentario de la hoja salen de 7 pantallas y el
   comentario no lo acota; `medirContraste` corre dos veces por pantalla sobre
   `.badge`; y **`.alert` sigue con el 8% de relleno de DaisyUI** — extender
   `[PASTILLA]` a `.alert` es cambiar un selector.

7. **Los menores diferidos del rol gestor** (variable muerta en
   `_referencia_evaluacion.html.haml:8`, `AssessmentPolicy#update?` sin
   cobertura ni llamador vivo, `CriteriaSetPolicy#update?` con
   `owner_step: nil`, «Ver el set» sin test de polaridad, la tabla de
   `gestor_administra_spec.rb` sin columnas de `participant` ni `evaluator`) y
   **dos rastros del renombre dejados a propósito** (el nombre de
   `gestor_administra_spec.rb` y los documentos de `docs/superpowers/`).

8. **El backlog largo, intacto:** el breadcrumb de `criteria_sets/edit` que para
   un set `inline` vuelve a una lista que nunca lo muestra;
   `Pipeline#validate` vs `Selection#can_activate?`; las once FKs con
   `ON DELETE SET NULL` sin acotador; `[FORMS]` que no cubre las pantallas a
   las que se llega por clic; los cuatro menores del módulo de testing; el plan
   2c (el resto de las islas Vue), `SelectionsController#update` sin validación
   server-side, `criteria_sets#show` huérfana, las 3 consultas de evolución,
   los tres temas de seguridad preexistentes, y que nada vigila el relleno por
   default de `card` desde que se retiró `[CARD]`.

9. **Sobre el recorrido como red, tres límites que conviene no olvidar:**
   - Dos pares de capturas son la MISMA pantalla (`03c-paso-a-paso` =
     `09-10-form-vacio`, `05e-config-seleccion` = `09-12-criterios-del-modulo`),
     así que las 66 capturas no son 66 pantallas.
   - **Sólo corre a 1440 y 1100px.** Abajo de 1024, donde el drawer pasa a ser
     una tira horizontal y el título se elipsa, no lo mira nada.
   - **La pasada oscura son diez pantallas y tres no tienen drawer**, así que
     toda variante que sólo aparezca en un desafío en borrador no se mide en
     oscuro.
