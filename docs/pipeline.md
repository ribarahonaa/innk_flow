# El motor de pipeline

## El problema que resuelve

En `innk_r5` el ciclo de vida de una idea es `ideas.stage`, un entero 0..7
hardcodeado, con las transiciones en un `case` del controller. Es el mismo para
todos los clientes: no hay forma de que una empresa evalúe dos veces, o corte
antes de evaluar, o salte la etapa técnica.

Acá el dueño del desafío arma su propio proceso con cinco tipos de módulo.

| kind | Qué hace | Repetible |
|---|---|---|
| `ideation` | Generación de la idea | **No — exactamente 1** |
| `evolution` | Feedback; el autor actualiza → versión nueva | Sí |
| `evaluation` | Puntuación por criterios | Sí |
| `selection` | Reduce el pool | Sí |
| `reporting` | Reportes del estado en ese punto | Sí |

---

## La regla dura: el insertion floor

```
challenge.draft?   → agregar / reordenar / borrar libremente
challenge.running? → floor = MAX(position WHERE status != 'pending')
                     solo se inserta en position > floor  (estricto)
```

`skipped` **cuenta**: fue tocado aunque no se ejecutara, así que sube el piso.
Saltear un módulo no reabre la puerta a insertar antes de él.

Vive en `Flow::Pipeline#insertion_floor` **y** se replica como validación en
`ChallengeStep#position_respects_insertion_floor`. Lo segundo no es redundancia:
el Pipeline es la API cómoda, pero nada impide un `step.update(position: 0.5)`
desde la consola.

La UI **muestra** la restricción —la "línea de agua" del builder, con los
módulos ejecutados sin handle de arrastre— en vez de solo rechazarla al
guardar. Y el server revalida todo igual: nunca confía en el cálculo del
cliente.

### Reordenar sí, mover lo ejecutado no

`can_reorder?` es true mientras el desafío no esté cerrado. Reacomodar módulos
**pendientes** con el flujo en curso es legítimo: la regla limita dónde se puede
*colocar* algo, no prohíbe reordenar lo que todavía no pasó. `#reorder` aplica
la regla fina: el prefijo ya tocado tiene que llegar intacto.

---

## Referencias entre módulos: slug, no posición

El caso duro: dos evaluaciones seguidas, ¿de cuál toma el puntaje la selección?

La posición es **mutable por diseño**, así que referenciar por ella es una
bomba. Se referencia por `slug` —único por desafío, editable mientras el step
está `pending`, inmutable desde la activación.

Y hay **late binding congelado**:

| Campo | Qué guarda | Cuándo se escribe |
|---|---|---|
| `config` | La intención del autor. Puede decir `auto` | Cuando se edita el módulo |
| `resolved_config` | La materialización, con ids concretos | **Una sola vez, en `activate!`** |

Regla de `auto`: la evaluación **completada más cercana hacia atrás**. Si no hay
ninguna, `can_activate?` falla con un mensaje legible.

Consecuencia: reordenar el pipeline después de que una selección arrancó no
puede cambiar de dónde saca el puntaje, porque ya está congelado con ids.

> **Un solo accesor: `step.settings`.** Devuelve `resolved_config` si el step
> fue tocado, `config` si está pendiente. Leer la fuente equivocada da
> comportamiento distinto según el estado; el accesor único elimina esa clase
> de bug.

---

## Ordenamiento fraccional

`position` es `decimal(20,10)`. Insertar entre A y B es `(a+b)/2` — **una sola
fila escrita**, sin desplazar a nadie. El builder manda la lista completa y el
server renumera a `1.0, 2.0, 3.0…`, así que la precisión nunca se degrada.

Descartado `acts_as_list`: su shifting puede mover filas de steps ya completados
**en silencio**, violando el insertion floor. La gema no conoce la invariante.

El ordinal de display ("Paso 3 de 7") **no se persiste**: se calcula.

---

## El cohorte: lazy, nunca eager

`step_entries` se crea al **activar** el step, y solo para las ideas vivas
(`Flow::Cohort.sync!`).

Tres cosas salen gratis de esa decisión:

1. Una idea eliminada en una selección **no genera fila** en los módulos
   siguientes. `step_entries` significa exactamente *participación real*, así
   que los reportes son `COUNT(*)` y no `COUNT(*) WHERE status != '...'` — la
   condición que alguien olvida y produce un reporte mal.
2. Agregar un módulo con ideas en vuelo **no necesita backfill**: el insertion
   floor garantiza que nace `pending`, y un step pendiente no tiene entries.
3. La **repesca** funciona sola: `sync!` es idempotente (índice único
   `(step_id, idea_id)`), así que crea solo la entry que falta.

Costo aceptado: "¿cuántas ideas llegan al módulo 5?" no es consultable antes de
activarlo. Es una proyección (`Cohort.for`), y la UI la rotula como estimación.

---

## Handlers

Un handler por kind. El Pipeline solo orquesta el orden.

```ruby
Flow::Handlers::Base.for(step)
  #can_activate? -> [bool, razones]
  #activate!        # idempotente: resolve_config! + Cohort.sync! + efectos
  #progress      -> Progress(done:, total:, label:)
  #can_complete? -> [bool, razones]
  #complete!        # idempotente
  #skip!(reason:)
```

| Handler | `activate!` | `can_complete?` |
|---|---|---|
| `Ideation` | Siembra el formulario por defecto. **Cohorte vacío**: las ideas nacen acá | `min_ideas` postuladas |
| `Evolution` | `Cohort.sync!`; encola feedback IA si el modo no es `human` | Todas respondieron, o `allow_partial` |
| `Evaluation` | **Congela los criterios**; asigna evaluadores | `min_assessments` por idea |
| `Selection` | Resuelve `score_source` a ids | Toda idea decidida, o corte automático |
| `Reporting` | Genera el tablero; encola narrativa IA | Siempre |

Tanto `Ideation` como `Evaluation` **siembran configuración por defecto** si
nadie la definió (campos de formulario, criterios inline). La maqueta corre de
punta a punta sin obligar a configurar todo primero.

---

## Síncrono vs. Sidekiq

A Sidekiq va lo que **(a)** llama a un servicio externo, **(b)** es O(cantidad
de ideas), o **(c)** produce un archivo. El resto es síncrono.

| | |
|---|---|
| **Síncrono** | Mutaciones de pipeline · guardar un assessment + recalcular esa entry · una decisión de selección · publicar una versión |
| **Sidekiq** | `AI::RunJob` (una llamada = un job) · `Reports::GenerateJob` · `Steps::ActivateJob` |

Todo job abre con `Flow::Tenant.with(Company.find(company_id))`: el tenant viaja
en el payload, nunca se asume.

---

## Concurrencia

`challenge.with_lock` en toda mutación de pipeline, y `lock_version` optimista
en `challenges` y `challenge_steps`: dos personas arrastrando a la vez reciben
un 409, no un last-write-wins silencioso.

> **Trampa conocida:** `with_lock` (SELECT FOR UPDATE) **deadlockea en los
> system specs**. Rails comparte el pool de conexiones entre el hilo del test y
> el del servidor, y el spec se cuelga *sin dar error*. Por eso el recorrido
> completo se verifica con `make screens` (Playwright contra la app corriendo)
> y con request specs, no con system specs. Ver `spec/system/smoke_spec.rb`.
