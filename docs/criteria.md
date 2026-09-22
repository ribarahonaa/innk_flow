# Criterios, escalas y fórmulas

## Sets reusables, snapshot congelado

| `scope` | Qué es |
|---|---|
| `library` | Plantilla de la empresa, en `/criteria_sets` |
| `inline` | Criterios ad-hoc de un módulo (`owner_step_id`) |

**Misma tabla, un flag.** Dos code paths para lo mismo se desincronizan.

Al activar un módulo de evaluación, sus criterios se **congelan** en
`resolved_config["criteria"]`, y `assessment_scores` persiste `criterion_key` y
`weight_used`.

> **Por qué no es paranoia.** En `innk_r5`, `Objective#reset_ponderations` muta
> las ponderaciones in-place *y dispara un worker que recalcula los promedios de
> ideas históricas*. O sea: editar un criterio hoy reescribe los puntajes del año
> pasado. Acá la matemática usa el snapshot; editar el set solo afecta a módulos
> que se activen después.

Validez de un set: ≥1 criterio activo, pesos que suman 1.0 ± 1e-6, y cada escala
bien configurada. Se chequea en el mantenedor **y** en `can_activate?` del
módulo: un set puede volverse inválido después de asignarse.

---

## La biblioteca no se pisa: se versiona

El snapshot protege los puntajes **ya calculados**. Falta la otra mitad: un set
de biblioteca lo usan varios desafíos a la vez, y editarlo cambiaba en silencio
lo que iban a evaluar todos los que todavía no arrancaron.

Guardar un set de biblioteca que **ya usa algún módulo** no lo modifica: crea la
versión siguiente y deja la anterior intacta.

| Columna | Qué guarda |
|---|---|
| `family_id` | La identidad a través de las versiones. Cada set nace siendo su propia familia |
| `version` | 1, 2, 3… `label` muestra «Nombre · v2» a partir de la segunda |
| `superseded_at` | Cuándo dejó de ser la vigente. `scope :current` filtra por esto |

Los módulos que usaban la versión anterior **siguen con ella** hasta que alguien
los pase a la nueva desde la pantalla del módulo. Nadie se entera de un cambio
que no pidió.

El aviso y el pase viven en el bloque de criterios de la cara de configuración
(`steps/_criterios_editor.html.haml`, detrás de `configure?`): si el set
asignado ya fue reemplazado, `CriteriaSet#newer_version` devuelve la vigente de
la familia y la pantalla ofrece «Pasarlo a …». No hay endpoint propio — el pase
es un `PATCH steps#update` con `criteria_set_id`, el mismo y único camino de
escritura de la configuración de un módulo. Ahí mismo está el select que elige
cualquier set vigente de la biblioteca (`CriteriaSet.asignables_para`), que es
lo que hace verdadera la advertencia de `Flow::Pipeline#validate`.

Los dos controles vivían en el panel del builder (`step_config.vue`) y se
perdieron cuando ese panel se borró (`58bd076`): durante esa ventana **nada**
apuntaba un módulo a la biblioteca —el único escritor de `criteria_set_id` era
la copia `inline` de `StepCriteriaController#create`— y dos textos de la app
seguían instruyendo a hacerlo. Volvieron en HAML, no en la isla: el builder es
dueño del armado, no de la configuración.

Con el módulo ya arrancado no se cambia: `criteria_set_id` está en
`ChallengeStep::FROZEN_ATTRIBUTES` y la pantalla pasa a su cara de ejecución,
que no ofrece ninguno de los dos controles.

Un set que **no usa nadie** se edita en el lugar: versionar lo que ningún módulo
tiene asignado no protege a nadie y llenaría la biblioteca de versiones muertas.

### Esto reemplaza al candado, pero solo en la biblioteca

Antes, un set con evaluaciones encima quedaba con peso y escala bloqueados. Al
versionar ya no hace falta: **sobre una versión nueva nadie puntuó nada**, así
que todo vuelve a ser editable.

En un set `inline` no hay a quién proteger copiando —es de un módulo y de nadie
más—, así que ahí el candado sigue siendo la respuesta (`locked?` en
`Api::V1::CriteriaSetsController`).

### Dos trampas que ya se pagaron

- El fork va **dentro** de la transacción del guardado. Afuera, un guardado que
  falla deja una versión huérfana que nadie pidió.
- Los criterios que llegan del editor traen los ids de la versión **anterior**.
  `fork_version!` los traduce por `key` a los de la copia; sin eso la
  reconciliación no reconoce ninguno, los borra todos y los crea de nuevo.

---

## Un criterio tiene DOS ejes

Antes estaban colapsados en `scale_type`, y `formula` figuraba como si fuera una
escala cuando en realidad es un origen.

| `source` — quién produce el valor | |
|---|---|
| `manual` | Lo puntúa una persona en la ficha de evaluación |
| `automatic` | Lo verifica el sistema sobre la idea. Nadie lo responde |
| `ai` | Lo decide la IA |
| `formula` | Se calcula a partir de otros criterios del set |

| `scale_type` — qué forma tiene | |
|---|---|
| `numeric` · `letter` · `rubric` | Escalas de puntuación |
| `boolean` | Sí / no. La forma de un veredicto |

**El origen manda sobre la forma cuando la determina**: un criterio automático
siempre es `boolean` (la verificación pasa o no pasa) y uno de fórmula siempre
es `numeric` (produce un número en un rango). El modelo lo fuerza en
`align_scale_with_source`, para que no exista un check con escala de letras.

### Criterios automáticos

Se verifican solos contra la idea y valen 1 si pasan, 0 si no — con el mismo
peso que cualquier otro criterio del set.

| `check` | Qué verifica | Config |
|---|---|---|
| `field_present` | El campo tiene contenido | `field_key`, `min_length` |
| `contributors_count` | Participan al menos N personas | `minimum` |
| `version_count` | La idea evolucionó | `minimum` |
| `feedback_addressed` | No quedó feedback sin atender **en la última ronda** | — |
| `has_attachment` | Adjuntó un archivo | `field_key` |
| `testing_passed` | Pasó su prueba de factibilidad, en el módulo de testing más reciente que la probó | `accepts`, `sin_testeo` |

```jsonc
{ "check": "field_present", "field_key": "costo", "min_length": 200 }
```

Un `check` desconocido o mal configurado **no deja guardar el criterio**.

**`feedback_addressed` mira una sola ronda.** Un desafío puede tener varias
evoluciones, y un check no sabe en cuál lo están corriendo: solo tiene su
`criterion`. Así que «la última» es la ronda más reciente que le dio feedback a
**esa** idea — no se puede tener sin atender lo que nadie comentó. Mirando
todas, un comentario que quedó abierto en una ronda vieja bloqueaba a la idea
para siempre: nadie vuelve a cerrar comentarios de una conversación que ya
terminó.

**`testing_passed` tiene el mismo problema, con otra tabla.** Un check no sabe
en qué módulo lo corren, así que «el testeo» es el vigente del módulo de
testing con la posición más alta entre los que probaron esa idea —igual que
`feedback_addressed`, mirando todos un veredicto viejo decidiría para siempre—.
`accepts` decide qué veredictos cuentan como aprobados: `solo_factible` o
`factible_o_con_reservas` (el default). `sin_testeo` decide qué hace una idea
que nadie testeó todavía: `pasa` (el default, por simetría con
`feedback_addressed`: no se puede tener sin atender lo que nadie comentó) o
`no_pasa`.

```jsonc
{ "check": "testing_passed", "accepts": "solo_factible", "sin_testeo": "no_pasa" }
```

---

## Un set sirve para evaluar y para seleccionar

Es el mismo objeto con dos usos:

| Módulo | Qué hace con los criterios |
|---|---|
| **Evaluación** | Los puntúa. Cada uno aporta según su peso |
| **Selección** | Los usa como **filtros**: la idea avanza solo si los cumple todos |

En una selección, los automáticos se verifican solos y los de sí/no los responde
una persona o la IA (`selection_verdicts`). Después de filtrar se aplica el corte
por puntaje, **entre las que quedaron habilitadas**.

Una selección con filtros propios **no necesita una evaluación previa**: se
sostiene sola.

Un veredicto sin responder deja a la idea en el limbo, así que el módulo no se
puede cerrar hasta resolverlos todos. Los veredictos quedan anclados a la
versión que se juzgó, igual que las notas.

---

## Toda escala aterriza en [0,1]

Es lo que hace comparables una nota 1-10, una letra A-F y una fórmula. El módulo
de selección lee un número entre 0 y 1 **sin saber ni preguntar** de qué escala
vino.

| `scale_type` | `scale_config` | Normalización |
|---|---|---|
| `numeric` | `{min, max, step, direction}` | `(v-min)/(max-min)`, invertido si `lower_better` |
| `letter` | `{levels: [{key, value}]}` | `value / max_value` |
| `rubric` | igual + `descriptor` por nivel | Idéntica a `letter` |
| `boolean` | `{true_label, false_label, direction}` | 1 o 0; `lower_better` invierte |
| (source `formula`) | `{expression, output: {min, max}}` | Criterio **derivado** |

`rubric` hereda de `letter`: la matemática es idéntica, lo único que agrega es
prosa que guía al evaluador. Un motor menos que mantener.

`direction: "lower_better"` sirve para costo, esfuerzo o riesgo — un 1 es
excelente y un 10 es pésimo.

### Agregación, en dos saltos

1. **Por evaluación**: media ponderada de sus notas, **renormalizada por la suma
   de pesos respondidos**. Una evaluación parcial no se castiga por los
   criterios que faltan.
2. **Por idea**: `step_entries.result["score"]`, combinando las evaluaciones de
   todos los evaluadores (`mean`, `median` o `trimmed_mean`) **con el peso de
   quien puso cada una** (`step_assignments.weight`).

### No todas las voces pesan igual

El peso por evaluador entra en el agregado, en la dispersión y en el promedio
por criterio. Dos reglas que no se ven leyendo el código si no se buscan:

- **Los pesos solo entran cuando alguien puso pesos distintos.** Con todos
  iguales la mediana ponderada no devuelve lo mismo que la mediana de siempre
  —con cantidad par, una promedia los dos del medio y la otra devuelve el de
  abajo—, así que asignar gente sin tocar pesos movería un puntaje ya
  calculado. Nadie pidió eso.
- **Cambiar un peso recalcula todas las entries del módulo.** Si no, la tabla
  sigue mostrando el número viejo y solo se actualiza cuando alguien más evalúa.

La dispersión se calcula ponderada **cuando el puntaje lo es**: una dispersión
sobre otra distribución que la del número que acompaña no describe nada.

Quien ya evaluó no se desasigna —su nota quedaría sin respaldo— y con el módulo
cerrado no se toca nada.

`raw_score` solo se guarda si **todas** las escalas comparten rango. Si el set
mezcla una nota 1-10 con una letra A-F, el número crudo no significa nada: se
deja `nil` y la UI muestra porcentaje.

---

## Fórmulas: nunca `eval`

La expresión la escribe el dueño del desafío. Es entrada de usuario que se
evalúa.

**Gema `dentaku`.** Ruby puro con tokenizer, parser y evaluator propios: la
expresión se convierte en AST y se recorre — no hay `eval`, `instance_eval` ni
`send` en el camino, y nunca toca un objeto Ruby.

El calculador se construye **sin `add_function`**: si una función no está
registrada, no existe. La whitelist es por construcción, no por filtro.

### Seis chequeos estáticos, todos antes de ejecutar nada

| # | Chequeo |
|---|---|
| 1 | **Límites duros primero**: ≤500 caracteres. Una expresión patológica no llega al parser |
| 2 | **Parse**, con error legible |
| 3 | **Profundidad** de AST ≤ 20 |
| 4 | **Referencias**: cada variable es el `key` de otro criterio activo del mismo set. Máximo 25 |
| 5 | **Whitelist de funciones**: walk del AST contra `IF MIN MAX ROUND ROUNDUP ROUNDDOWN ABS AND OR NOT` |
| 6 | **Ciclos**: DFS sobre el grafo del set, con el camino en el mensaje |

`spec/lib/flow/formula/validator_spec.rb` verifica que **once formas de
inyección** se rechazan: `system(...)`, backticks, `%x{}`, `File.read`,
`Kernel.exit`, `eval`, `.send`, variables globales y de instancia, y
`expr; system(...)`.

### En runtime

Una fórmula rota **no tumba la evaluación**: el criterio queda con `error` y se
muestra "—" con el motivo; el resto de los criterios sigue contando.

Los criterios fórmula son **derivados**: no aparecen en el formulario del
evaluador y se calculan después, en orden topológico.

### El límite del scope

Las fórmulas viven **dentro de un criteria_set**. Combinar puntajes *entre
módulos* ("0.3 × técnica + 0.7 × comité") **no** es dentaku: es
`score_source.weights` del módulo de selección, declarativo.

Si dentaku cruzara módulos, la validación de referencias tendría que resolver el
pipeline entero y volveríamos al acoplamiento por posición que el diseño evita.
