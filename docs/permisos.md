# Roles y permisos

**Pundit, no CanCanCan.** El `ability.rb` de `innk_r5` tiene 2.045 líneas en un
solo `initialize`, y es exactamente el archivo donde se escondieron las fugas de
`can :manage` pelado. Una policy por recurso mantiene la superficie legible y
auditable.

**En una policy, `user` es el MEMBERSHIP, no el User.** El rol es por empresa, y
una persona puede estar en varias.

```ruby
class ApplicationPolicy
  def initialize(membership, record)
```

## Los cuatro roles

| Rol | Qué hace |
|---|---|
| `admin` | Administra la empresa |
| `gestor` | Administra **los desafíos que le asignaron** |
| `evaluator` | Evalúa **lo que se le asigna** |
| `participant` | Postula y comenta |

**`owner` no existe**: daba los mismos permisos que `admin`.

`memberships.role` es un CHECK de Postgres. El valor `"gestor"` está en español
—herencia de una regla anterior— y **no se renombra**: es una migración con
cambio de datos que toca modelo, rutas, policies, seeds, el CHECK y las
capturas.

## Los tres predicados base

Todo cuelga de estos tres, en `ApplicationPolicy`:

```ruby
def manager? = membership.present? && membership.manages_challenges?

def reaches_challenge?(challenge)
  return false if membership.nil?
  return true unless membership.gestor?
  return false if challenge.nil?
  ChallengeGestor.exists?(challenge_id: challenge.id, user_id: membership.user_id)
end

def administers?(challenge)
  manager? || (membership.present? && membership.gestor? && reaches_challenge?(challenge))
end
```

| Predicado | Significa |
|---|---|
| `manager?` | **Administra la EMPRESA.** Protege lo que no cuelga de ningún desafío: las membresías, la auditoría de IA y la biblioteca de criterios |
| `reaches_challenge?` | **Llega a ESE desafío.** Es la regla que rompe la equivalencia «tener membresía = ver todo lo de la empresa» |
| `administers?` | **Administra ESE desafío.** `manager?` o gestor asignado |

**De rebote, una puerta nueva escrita con `manager?` nace cerrada para el
gestor, que es el lado seguro.** Abrirla es una decisión que se toma, no un
default.

`administers?` tiene que aceptar `nil` sin reventar: el desafío llega por cadenas
opcionales (`record.challenge_step&.challenge`). Para un gestor eso es `false`, y
un admin ya salió antes por `manager?`.

## El gestor

**Es interempresa**: una membresía con rol `gestor` por cada empresa, igual que
cualquiera que esté en más de una. Lo nuevo es que **tener membresía dejó de
significar ver todo**: un gestor sólo ve los desafíos de `challenge_gestores`.

Dentro de uno, puede lo mismo que quien administra la empresa: armarlo,
arrancarlo, configurarlo, testear, avanzar, reportar, asignar, y trabajar sus
ideas sin esperar una ronda de evolución.

**Se asigna desde el módulo de evolución**, que es donde tiene algo que hacer
—igual que los evaluadores se asignan desde el módulo de evaluación—, aunque el
acceso que otorga es al **desafío entero** y la pantalla lo dice. La ficha del
desafío sólo lo ofrece si quedaron gestores sin módulo de evolución donde
administrarlos.

**Dos cosas no se abrieron, y son de otro eje:**

```ruby
IdeaPolicy#create? = membership.present? && !membership.gestor?
IdeaPolicy#submit? = update? && !assigned_gestor?
```

**No postula ideas propias** ni **postula por el autor**. Son **conflicto de
interés, no permisos**: proponer las propias lo pondría a guiar su competencia.
`submit?` sigue cerrado aunque `update?` se haya abierto — por eso
`assigned_gestor?` se quedó aunque su otra rama murió.

**`create?` es la única puerta que no pregunta por la asignación**: el desafío
todavía no existe. Lo que la acota es que `ChallengesController#create`
**auto-asigna al gestor que lo crea**, en la misma transacción que el `save`.

El reparto entero se lee en `spec/policies/gestor_administra_spec.rb`, que existe
porque **abrir un permiso de más no rompe ningún test**.

## Lo que no vive en el rol

### Evaluar depende de la asignación

```ruby
AssessmentPolicy#create?
  return false unless reaches_challenge?(record.challenge_step&.challenge)
  return false if record.idea&.participates?(membership.user)
  return true if administers?(record.challenge_step&.challenge)
  record.challenge_step.step_assignments.exists?(user_id: membership.user_id)
```

**Y nadie evalúa una idea de la que participa**, ni siquiera quien administra:
el conflicto de interés es el mismo. Postular sigue permitido; lo que no se puede
es puntuarse a uno mismo.

Por eso **el mínimo de evaluaciones baja por idea** cuando su autor está entre
quienes evalúan: esperar el mínimo entero trabaría el módulo esperando una
evaluación imposible.

El link «Evaluar» de cada fila pregunta **la misma policy que autoriza el
controller** —`policy(Assessment.new(challenge_step:, idea:))`— y no
`step.active?` a secas: con eso lo veía en todas las filas quien evalúa sin
asignación en ese módulo, y quien acompaña el desafío, que no es `manager?`. Los
dos se comían un 403 al apretarlo.

**No hay `update?` propio.** `resources :assessments, only: %i[new create]`: una
evaluación no se edita, se vuelve a evaluar. El que había no tenía ruta, ni
llamador, ni cobertura, y era **más** permisivo que el default heredado: un
permiso abierto esperando a que alguien le cableara una ruta.

### No todas las voces pesan igual

`step_assignments.weight` entra en el agregado, en la dispersión y en el promedio
por criterio. Dos reglas que no se ven en el código si no se buscan:

- **Los pesos sólo entran cuando alguien puso pesos distintos.** Con todos
  iguales la mediana ponderada no devuelve lo mismo que la mediana de siempre, y
  asignar gente sin tocar pesos no puede mover un puntaje ya calculado.
- **Cambiar un peso recalcula todas las entries del módulo**, porque si no la
  tabla sigue mostrando el número viejo.

Quien ya evaluó **no se desasigna** —su nota quedaría sin respaldo— y con el
módulo cerrado no se toca nada.

### Quien participa ve sólo las ideas en las que participa

Las que creó y aquellas en las que colabora: compite por el mismo corte que las
demás. **La regla vive UNA vez**, en `IdeaPolicy::Scope`:

```ruby
return scope.none if membership.nil?
return scope.all unless membership.participant?
colabora = IdeaContributor.where(user_id: membership.user_id).select(:idea_id)
scope.where(author_id: membership.user_id).or(scope.where(id: colabora))
```

Y las pantallas la aplican: `StepsController#show` publica `@ideas_visibles` y
los módulos filtran con eso lo que listan. **Lo que no se ve da 404, no 403.**

Quien administra, acompaña o evalúa las ve todas: las tres cosas se hacen sobre
el pool entero.

Dónde muerde en cada módulo:

| Módulo | Qué ve quien participa |
|---|---|
| **idear** | Sus ideas. Lo olvidó hasta el plan 2b: listaba todas las postuladas |
| **reportería** | Lo agregado —embudo, distribución, participación— y el ranking y la matriz **filtrados a sus ideas**. El resumen narrativo **no**, porque nombra ideas ajenas |
| **selección** | **Son dos listas, no una**: el ranking y el registro de decisiones, los dos filtrados. Lo que ahí NO se filtra es quién decidió, cuándo y el motivo de la tanda: es lo que explica por qué la idea de uno avanzó o no |

### Editar una idea es publicar una versión

```ruby
IdeaPolicy#update?
  return true if administers?(record.challenge)
  return false unless record.participates?(membership&.user)
  record.draft? || evolution_open?
```

El autor puede mientras la idea sigue en borrador, **y** cuando hay un módulo de
evolución abierto: responder al feedback actualizando la idea es exactamente
para lo que existe ese módulo. Fuera de esos dos momentos, una idea postulada no
se edita en caliente.

**Quien colabora también puede.** Colaborar es una de las dos formas de
participar —y es la regla de visibilidad—: no poder tocarla la dejaba a medias.

`manage_contributors?` **es** `update?`: un colaborador no es decorativo —hay
criterios que cuentan personas—, así que agregarlo con la evaluación en curso
movería el puntaje después del hecho.

### El puntaje y el desglose son cosas distintas

Quien participa de una idea ve su **resultado agregado** cuando el módulo cierra;
**quién puso qué** lo ven sólo quien administra y quien evaluó esa idea. Por eso
hay **dos** predicados en el handler (`score_visible_for?` y
`breakdown_visible_for?`) y no uno.

## La regla de oro: 404, no 403

**Un 403 es un oráculo de existencia.**

El 403 existe —`Pundit::NotAuthorizedError` lo devuelve— y es **correcto para lo
que SÍ se ve pero no se puede hacer**: ver un desafío y no poder editarlo no
confirma nada que no supieras.

### La trampa es el ORDEN, no el `authorize`

Buscar con el scope de tenencia y autorizar **después** devuelve 403 sobre algo
que no se debería ver. A quien participa, **una idea ajena le daba 403 y un id
inexistente 404**, y esa diferencia confirma que existe.

Pasó en **cuatro de los seis** controllers que buscaban una idea, cada uno con su
`authorize` escrito. Por eso:

```ruby
# Bien
policy_scope(Idea).find_by!(id: params[:id])
policy_scope(Challenge).find_by!(slug: params[:challenge_id])

# Mal
Idea.find_by!(id: params[:id])     # + authorize después → 403 donde iba 404
```

Los controllers del taller y de las salas buscan el desafío con
`policy_scope(Challenge).find_by!` por esto mismo.

Qué lo cuida:

| Guarda | Qué ve | Qué NO ve |
|---|---|---|
| `spec/lint/ideas_por_policy_scope_spec.rb` | Usos de `Idea` o `.ideas` fuera de un `policy_scope`, **sólo en controllers** | Ideas a las que se llega por otro registro, `public_send`, heredocs. Y nada de comentarios ni propuestas |
| `spec/requests/participant_rules_spec.rb` | Los `[404, 404]` ruta por ruta. **Es lo que prueba el comportamiento** | |

La guarda de lint **prueba su propio detector**, porque las dos revisiones la
evadieron. Su comentario dice qué no ve. **No le creas más que eso.**

### Lo que cuelga de una idea hereda su visibilidad

Comentarios y propuestas de la IA se buscaban por id en toda la empresa, con el
mismo 403-contra-404.

- **Un comentario** se busca dentro del paso de la URL y sobre una idea visible
  (`FeedbackItemsController#comentario`).
- **Una propuesta** la ve quien administra, y cualquier otra persona si **le
  aparece en un panel Y ve aquello sobre lo que actúa**:

```ruby
AiSuggestionPolicy#visible?
  return true if manager?
  return false unless accept? && reaches_challenge?(desafio)
  record.idea.nil? || IdeaPolicy.new(membership, record.idea).show?
```

**Llevó tres intentos, y cada uno falló por una mitad:**

| Intento | Qué rompía |
|---|---|
| `accept?` a secas | Volvía 404 el 403 legítimo de quien administra un desafío cerrado |
| «se ve si se ve su objetivo» | Dejaba 403 a quien participa por una propuesta del flujo, que no le aparece en ningún lado |
| `manager? \|\| accept?` | Un gestor dado de baja con la asignación intacta **aplicaba una evaluación** sobre un desafío que le da 404 |

El tercero es el que llevó a `AssessmentPolicy#create?` a preguntar
`reaches_challenge?`. Tiene spec de policy directo
(`spec/policies/assessment_policy_spec.rb`, el único: por request esa línea la
tapan otros).

### Una policy sin nada propio hereda `show? = membership.present?`

O sea **«cualquiera de la empresa lee esto»**.

`CriteriaSetPolicy` estaba vacía, y un gestor abría por id —**200, con los
criterios adentro**— el set `inline` de un desafío que no le asignaron. No era un
oráculo: era una **fuga de lectura**, y la encontró una auditoría, no un test.

Ahora su `Scope` deja la biblioteca a la vista de la empresa y cada set `inline`
a la de su desafío. Y `WorkshopPolicy` lleva un comentario al tope que dice que
**no nace vacía** por esto.

**Antes de dejar una policy vacía, preguntate de qué desafío cuelga lo que
protege.**

### Sin membresía, `none`

La sesión guarda la empresa elegida y **no vuelve a pedir la membresía**: a quien
se la sacaron le queda el tenant puesto y `current_membership` en `nil`.

`ChallengePolicy::Scope` hacía `scope.all unless gestor?`, y quien acababa de
perder el acceso **listaba todos los desafíos** —un gestor removido, más que
antes—.

```ruby
def resolve = membership.nil? ? scope.none : scope.all
```

**Todo `Scope` que lo sobreescriba tiene que hacer la misma pregunta primero**
(`spec/tenancy/sin_membresia_spec.rb`). **La sesión sigue viva igual**: esto
cierra lo que se ve, no la puerta.

## Las doce policies

| Policy | Qué protege | Nota |
|---|---|---|
| `ApplicationPolicy` | Los tres predicados base y el `Scope` por default | |
| `ChallengePolicy` | El desafío y su flujo | Ver abajo |
| `ChallengeStepPolicy` | El módulo | Ver abajo |
| `IdeaPolicy` | La idea | `Scope` propio: quien participa ve las suyas |
| `AssessmentPolicy` | Evaluar | Sólo `create?`: no se edita, se vuelve a evaluar |
| `FeedbackItemPolicy` | Comentar y cerrar comentarios | `resolve?` mira `step.active?` |
| `CriteriaSetPolicy` | Sets de criterios | `Scope` propio. `update?`: biblioteca → `manager?`; inline → `administers?` de su desafío |
| `AiSuggestionPolicy` | Pedir, aceptar y ver propuestas de IA | Ver abajo |
| `AiRunPolicy` | La auditoría | `manager?` a secas |
| `MembershipPolicy` | La gente | `manager?` a secas |
| `WorkshopPolicy` | El taller | `Scope` propio. Ver [`taller.md`](taller.md) |
| `WorkshopProposalPolicy` | Aceptar lo que propuso una mesa | `author?`: es del autor de la idea |

Cada policy **declara su `Scope` explícitamente**
(`class Scope < ApplicationPolicy::Scope; end`), aunque esté vacío: Pundit usa
`const_get(:Scope, false)` y **no lo hereda**.

### `ChallengePolicy`

| Predicado | Es |
|---|---|
| `show?` | `reaches_challenge?(record)` |
| `create?` | `manager?` o gestor (auto-asignado al crear) |
| `builder?` | `administers?` |
| `start?` / `close?` | `administers?` + el estado correcto |
| `update_pipeline?` | `administers?` y no cerrado ni archivado |
| `curate_pool?` | `administers?` |
| `enter_any_group?` | `administers?` — **trabajar cualquier mesa de un taller** |
| `read_pool?` | `reaches_challenge?` y **no** `participant?` |

`builder?`, `curate_pool?` y `enter_any_group?` son hoy **los tres exactamente
`administers?(record)`**, y son **tres predicados y no uno** a propósito: reusar
un nombre ata un permiso al significado de otra cosa, y el día que alguien mueva
uno los otros se mueven con él sin que nadie lo decida.

### `ChallengeStepPolicy`

`show?` es `reaches_challenge?(record&.challenge)`, o sea **cualquiera de la
empresa que llegue al desafío**. Eso tiene una consecuencia grande:

**La guarda de permiso de un editor embebido vive en la VISTA, no en el
controller.** Un editor que antes vivía en pantalla propia —con su propio
controller pidiendo `manage_criteria?`, `manage_form?`— pasa a embeberse en la
pantalla del módulo, que sirve `show?`. Heredar ese permiso amplio sin poner uno
más estricto en el partial deja la isla y los botones **montados para quien no
puede usarlos**, y apretarlos rebota en un 403.

El mismo defecto apareció dos veces: primero el form completo de
`steps/config/_modulo` se servía sin ninguna policy; después, en
`_criterios_editor`, el panel de sugerencias de IA quedó afuera de la guarda que
sí envolvía el resto.

**La forma que quedó:** nada que no sea el encabezado se sirve sin la guarda, y
la guarda es **UNA variable** (`puede_configurar`, calculada una vez arriba) y
no un predicado escrito en cada bloque.

Cuál predicado según qué bloque:

| Bloque | Predicado |
|---|---|
| Los ajustes del módulo y sus criterios | `configure?` (= `ChallengePolicy#update_pipeline?`) |
| Los campos del formulario | `manage_form?` |
| Quién evalúa y cuánto pesa | `manage_assignments?` |
| Quién acompaña la evolución | `update_pipeline?` |

**El panel de propuestas de la IA es la excepción a esa guarda única:** filtra
propuesta por propuesta con `AiSuggestionPolicy#accept?`, porque quién revisa
depende de sobre qué actúa cada tarea. Se sirve en **once** lugares —nueve pantallas
más los dos editores embebidos—, y sin ese filtro les mandaba a quien participa y a quien evalúa propuestas que no podían
revisar, con la vista previa incluida.

### `AiSuggestionPolicy`: pedir y aceptar son el mismo método

```ruby
def request? = accept?
```

`AiRequestsController` arma una propuesta de mentira con lo que trae el pedido y
pregunta `request?`. **Divergieron dos veces** mientras la tabla estuvo copiada
en los dos lados:

- Primero era todo `update_pipeline?` para pedir y «admin o autor» para aceptar,
  así que quien participa no podía usar ninguna función de IA sobre su propia
  idea y quien acompaña no podía aplicar el feedback que es su trabajo.
- Después, con las dos copias ya alineadas, la policy seguía arrancando con
  `return true if manager?`, y quien administra **aplicaba sobre un desafío
  cerrado** una propuesta que ya no podía pedir.

**Quién puede pedirle algo a la IA depende de sobre qué actúa, y eso lo declara
la tarea** con `self.actua_sobre`:

| Alcance | Tareas | Lo autoriza |
|---|---|---|
| `:idea` | `coauthor_field`, `evolve_idea` | `IdeaPolicy#update?` |
| `:feedback` | `suggest_feedback` | `FeedbackItemPolicy#create?` |
| `:pool` | `detect_duplicates` | `ChallengePolicy#curate_pool?` |
| `:assessment` | `evaluate_idea` | `AssessmentPolicy#create?` |
| `:challenge` (default) | el resto | `ChallengePolicy#update_pipeline?` |

**`detect_duplicates` actúa sobre el POOL, no sobre la idea**: lo que devuelve
son títulos y resúmenes de las OTRAS ideas del desafío, que quien participa no
ve. Mientras colgó de `IdeaPolicy#update?` el autor lo pedía sobre su propio
borrador y **leía el pool entero**.

**Y un módulo cerrado no sigue aceptando el trabajo de su IA**
(`Tasks::Base.step_ready?`). Va en la policy y no sólo en el controller porque
pedir y aceptar son el mismo método: una propuesta que nació con el módulo
abierto tampoco se aplica después.

### Pedirle a la IA que evalúe no es evaluar

El botón —y el lote «evaluar todas con IA»— es de **quien evalúa en el módulo**,
por asignación o por administrarlo, **no** de `update_pipeline?`.

Y va **sin idea**: quien participa de una idea no la puntúa, pero **sí** puede
pedir que la IA la evalúe, porque la nota es de la IA. Bloquearlo trabaría el
módulo, ya que `min_assessments_for` baja el mínimo contando a la IA justamente
como quien evalúa lo que su autor no puede.

La regla está en **un solo lugar** y las tres puertas la consultan
(`AiSuggestionPolicy#evaluacion`, `AiRequestsController#autorizar!`,
`StepsController#evaluate_all`).

**Y por eso no se edita al aceptarla** (`Tasks::EvaluateIdea#editable?`):
aceptar una propuesta pendiente admitía un payload editado, y quien evaluaba **se
ponía puntaje en su propia idea con el nombre de la IA encima**. Ninguna pantalla
edita un payload antes de aceptar; era una capacidad del dominio sin interfaz.

## Dónde mirar cuando tocás esto

| Archivo | Qué prueba |
|---|---|
| `spec/policies/gestor_administra_spec.rb` | El reparto entero del gestor. Existe porque abrir un permiso de más no rompe ningún test |
| `spec/policies/assessment_policy_spec.rb` | Que evaluar pregunte por el desafío |
| `spec/requests/participant_rules_spec.rb` | Los `[404, 404]` ruta por ruta |
| `spec/tenancy/sin_membresia_spec.rb` | Que todo `Scope` devuelva `none` sin membresía |
| `spec/lint/ideas_por_policy_scope_spec.rb` | Que las ideas se busquen por `policy_scope` en los controllers |
| `spec/requests/escribir_en_una_mesa_ajena_spec.rb` | Las escrituras de la sala |
| `spec/requests/entrar_a_una_mesa_spec.rb` | La precedencia de la mesa nombrada, y los textos «tu mesa» |

Y [`tenancy.md`](tenancy.md) para las cuatro capas de aislamiento, que son la
otra mitad de esto: **los permisos dicen quién puede qué dentro de una empresa;
la tenencia dice que la empresa de al lado no existe.**
