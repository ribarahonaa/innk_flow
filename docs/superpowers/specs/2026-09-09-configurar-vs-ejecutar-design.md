# Configurar y ejecutar: dos caras de la pantalla del módulo

> Estado: diseño aprobado, sin implementar.
> Rama sugerida: `configurar-vs-ejecutar`, encima de `rediseno-tailwind`.

## El problema

Configurar un módulo hoy está repartido en cuatro pantallas, y ninguna de ellas
es la del módulo:

| Qué configurás | Dónde vive hoy |
|---|---|
| Nombre, modo de IA, ajustes del kind | El builder, panel derecho |
| Los campos del formulario de postulación | `/challenges/:id/form` |
| Los criterios / filtros | `/criteria_sets/:id/edit` · `/challenges/:cid/steps/:sid/criteria` |
| Evaluadores, gestores, modo de IA (otra vez) | La pantalla del módulo |

No existe ninguna ruta de configuración por módulo. La pantalla del módulo es la
de ejecución, con unos pocos controles de configuración filtrados adentro.

El síntoma con el que apareció: en la ficha «Cómo se decide» de una selección, el
corte se mostraba como un hecho de sólo lectura, con un botón «Editar el set» al
lado que edita **otra** cosa. El módulo estaba `pending` —o sea, el corte era
perfectamente editable— pero desde ahí no había cómo. El primer arreglo agregó un
link al builder, y eso confirmó el diagnóstico en vez de resolverlo: el problema
no era que faltara un link, era que configurar exige rebotar entre pantallas.

### Lo que ya está bien y no se toca

El modelo ya tiene la regla que hace falta. `ChallengeStep::FROZEN_ATTRIBUTES`
congela `kind`, `slug`, `position`, `config`, `source_step_id` y los criterios en
cuanto el módulo se toca; `ADJUSTABLE_ATTRIBUTES` deja `name` y `ai_mode` vivos.
`touched?` es el predicado. Nada de eso cambia: lo que falta es que la UI lo
refleje.

## Decisión

**La pantalla del módulo tiene dos caras, y la cara la decide `step.touched?`.**

No la decide el estado del desafío. Un desafío en curso sigue teniendo módulos
pendientes más adelante y esos son configurables — es la misma regla de la línea
de agua (`Flow::Pipeline#insertion_floor`) que ya existe. La cara es por módulo.

El builder queda haciendo una sola cosa: armar el flujo. Clic en una tarjeta =
ir a configurar ese módulo.

### Alternativas descartadas

- **Una pantalla «Configurar» con los 8 módulos desplegables.** Se descartó
  porque duplica lo que ya muestran las pantallas de módulo y se vuelve una
  página larguísima con cinco kinds de configuración adentro.
- **Meter todo en el builder.** Habría que embeber las dos islas más grandes
  (formulario y criterios) dentro de la tercera, y deja la configuración lejos de
  donde se ve el trabajo del módulo.

## 1 · Las dos caras

### Cara A — Configurar (`pending`)

| Bloque | Qué trae | Kinds |
|---|---|---|
| El módulo | Nombre, modo de IA | los 5 |
| Los ajustes | Lo que declara `Flow::StepSettings` | los 5 |
| Los criterios | Editor inline (pauta o filtros) | evaluación, selección |
| El formulario | Editor de campos inline | idear |
| Quiénes participan | Evaluadores con peso · gestores | evaluación, evolución |

Los ajustes por kind, tal como los declara hoy el esquema:

| kind | Esencial | Avanzado |
|---|---|---|
| `ideation` | `min_ideas` | `generated_ideas` |
| `evolution` | `require_response` | — |
| `evaluation` | `min_assessments` | `evaluator_aggregation` |
| `selection` | `source_step_id`, `cut.mode`, `cut.value` | `score_source.combine`, `cut.tie_break` |
| `reporting` | `mode` | `include_eliminated`, `step_slugs` |

### Cara B — Ejecutar (`active`, `completed`, `skipped`)

El trabajo: las tablas, los veredictos, el corte, los reportes. Arriba, la
configuración como resumen de sólo lectura, con candado y «se fijó al arrancar el
módulo».

**Tres cosas siguen vivas y la pantalla las muestra como vivas, no como
bloqueadas:**

- **El modo de IA.** Es política operativa: decidir «de acá en más acepto ayuda
  de la IA» no reescribe nada de lo hecho. Ya funciona así (`steps/_ai_mode`).
- **El nombre.** Junto con `ai_mode`, los dos `ADJUSTABLE_ATTRIBUTES`.
- **Las asignaciones.** Se puede sumar un evaluador con el módulo en curso. No se
  desasigna a quien ya puntuó —su nota quedaría sin respaldo— y con el módulo
  cerrado no se toca nada.

Un módulo `skipped` cae en la cara B: subió la línea de agua igual que si se
hubiera ejecutado, así que muestra su configuración congelada y un «se salteó».

## 2 · Un solo camino de escritura

Esto es lo que hay que hacer bien o el resto no importa.

Hoy `Api::V1::PipelinesController#update_existing` escribe, para todo módulo no
tocado:

```ruby
step.config = attrs[:settings] if attrs.key?(:settings)
step.source_step_id = attrs[:sourceStepId].presence
step.criteria_set_id = attrs[:criteriaSetId].presence if attrs.key?(:criteriaSetId)
```

Si la configuración se muda a la pantalla del módulo pero el builder sigue
mandando esas claves desde props cargadas antes, **guardar el flujo revierte lo
que configuraste**. El bloqueo optimista no lo atrapa: `lock_version` es del
desafío y un PATCH al módulo no lo incrementa.

| | Dueño hoy | Dueño después |
|---|---|---|
| `kind`, `position`, alta y baja | builder (`PUT .../pipeline`) | igual |
| `name`, `ai_mode` | builder **y** pantalla del módulo | pantalla del módulo |
| `config`, `source_step_id`, `criteria_set_id` | builder | pantalla del módulo |
| criterios | editor de criterios | igual, embebido |
| campos del formulario | editor de formulario | igual, embebido |

El builder deja de mandar esas tres claves y `update_existing` deja de
escribirlas. Es la regla que el repo ya aplica a las islas —un solo camino de
escritura, el server reconcilia— extendida al builder.

### `steps#update` como ese camino

Ya existe (`resources :steps, only: %i[show update]`) y hoy lo usa el selector de
modo de IA. Pasa a recibir también lo estructural.

**Autorización según lo que llega**, porque las dos cosas no piden lo mismo:

```ruby
estructural = (step_params.keys & %w[config source_step_id criteria_set_id]).any?
authorize @step, estructural ? :configure? : :advance?
```

`ChallengeStepPolicy#advance?` es lo que ya pide el selector de modo de IA en la
cara B. `configure?` va en la misma policy y delega en
`ChallengePolicy#update_pipeline?`.

Los dos predicados dan `manager?`, así que **no** separan a dos grupos de
personas: lo que agrega `update_pipeline?` es `&& !record.closed? && !record.archived?`.
Ésa es exactamente la diferencia que se busca. Con el desafío cerrado, ajustar el
modo de IA de un módulo sigue siendo legítimo —es política operativa— y reescribir
su configuración no lo es.

**El congelamiento no lo cuida el controller.** Ya lo impone `FROZEN_ATTRIBUTES`
como validación de modelo, así que un PATCH tramposo a un módulo en curso falla
en la capa correcta y no hay una segunda copia de la regla que se pueda
desincronizar.

### El `config` se filtra contra el esquema

`params.permit(config: {})` es un escritor de jsonb arbitrario. El `config` que
llega se filtra contra `Flow::StepSettings`: sólo las claves que el esquema
declara para ese `kind`, casteadas al tipo declarado.

Sin el casteo, `cut.value` llega como `"4"` y no como `4` — y el handler hace
`.to_f`, así que el bug no aparece hasta que alguien compara o serializa.

Va como método del propio esquema (`Flow::StepSettings.filtrar(kind, hash)`), que
es donde vive la fuente única.

## 3 · Los ajustes: la isla se muda

`step_config.vue` y `config_field.vue` **salen** de `pipeline_builder` y pasan a
ser una isla propia, `step-settings`, que se monta en la cara de configuración
(`%div{ "data-island": "step-settings", data: { props: … } }`, igual que las otras
tres). Es una mudanza, no una reescritura: `depends_on`, el
filtrado de `source_step_id` por posición (una selección sólo puede tomar puntaje
de una evaluación anterior, y el orden cambia mientras se edita) y los defaults ya
están escritos y probados.

El cambio real: **la isla deja de tener guardado propio.** Renderiza
`name="challenge_step[config][cut][mode]"` en sus inputs, dentro del `form_with`
de Rails. Un solo botón «Guardar el módulo» manda nombre, modo de IA y ajustes
juntos, contra un solo endpoint.

Esto además saca del medio la trampa documentada de las islas —props como estado
inicial, copiar a `data()`— para este caso: el estado sigue siendo del cliente
mientras editás, pero quien guarda es el form.

El builder queda más chico: pierde el panel y gana un link por tarjeta.

### El módulo sin guardar

En el builder se puede agregar un módulo que todavía no está guardado, y sin `id`
no hay URL a la que ir. Las tarjetas nuevas se marcan «sin guardar» y no llevan
link; guardar el flujo es el paso que las hace configurables.

## 4 · Los dos editores embebidos

Los criterios ya tienen pantalla por módulo (`StepCriteriaController#show`, con
`back_url`): su contenido se muda a un bloque de la cara de configuración y la
pantalla suelta desaparece. `#create` sobrevive como acción — es la que decide con
qué arranca el set propio (`defaults`, `library`, `blank`).

El editor de campos hace lo mismo desde `/challenges/:id/form`.

Los dos siguen guardando contra su propia API, que es la regla del repo: cada isla
guarda la lista completa con un `PUT` y el server reconcilia. Así que la página
tiene el botón del módulo más el guardado de cada editor. No se inventa una
transacción entre islas.

La biblioteca de criterios sigue existiendo aparte: su razón de ser es reusar sets
entre desafíos, que no es lo mismo que configurar un módulo.

## 5 · La excepción del formulario

El formulario de postulación **no** se congela con `touched?`. Su candado es
`challenge.ideas.submitted.exists?` (`Api::V1::FormFieldsController#locked?`), y
es más fino: con el módulo de idear ya abierto pero sin ninguna postulación,
corregir el label de un campo es sano y no reescribe nada.

Se conserva. En Idear, la cara B sigue mostrando el editor de campos con su propio
candado. No es una fuga de la regla general: es que ese objeto tiene una regla
mejor.

## 6 · Verificación

Tres guardas nuevas, porque las tres fallan en silencio:

- **Guardar el flujo no pisa la configuración de un módulo.** Se configura un
  módulo, se guarda el pipeline con props viejas, y la configuración sigue ahí.
  Es la regresión más cara del cambio y la única que ningún test actual atrapa.
- **Un PATCH estructural a un módulo en curso se rechaza**, y el que sólo cambia
  el modo de IA pasa. Las dos autorizaciones, las dos direcciones.
- **`Flow::StepSettings.filtrar` descarta claves ajenas y castea los tipos.**
  Contra el esquema real de los cinco kinds, no contra una lista escrita a mano.

Más, por kind: un request spec que verifique que la cara A trae todos sus bloques
y que la cara B no trae ninguno editable salvo los tres vivos.

Y en `make screens`, las dos caras de los cinco kinds. Diez capturas nuevas, con
navegación **por link** desde el builder — que es justo el camino nuevo, y un
`goto` lo escondería.

## Fuera de alcance

- Rehacer el builder más allá de sacarle el panel y ponerle links.
- Tocar la biblioteca de criterios.
- Cambiar cualquier regla de congelamiento del modelo.
- El plan 2 del rediseño (los 18 partials compartidos, los componentes Vue).

## Decisiones abiertas

Ninguna. La única que se discutió —uniformar el candado del formulario a
`touched?`— se resolvió a favor de conservar su regla fina.
