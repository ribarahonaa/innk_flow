# El gestor administra los desafíos que le asignaron

Hoy `gestor` es un rol angosto: ve los desafíos que le asignaron, mira el pool
entero, comenta, cierra comentarios y edita una idea **sólo** mientras hay una
ronda de evolución abierta. Todo lo demás —arrancar, configurar, testear,
avanzar, reportar, asignar— es `admin` a secas.

El rol que se quiere es otro, y el propio código ya lo insinúa: `ChallengeGestor`
dice «un gestor **contratado** para un desafío». La figura es la de alguien que
entra a hacer correr un desafío ajeno, en varias empresas a la vez. Lo que le
falta son las manos.

Después de este cambio: **dentro de un desafío que le asignaron, el gestor puede
lo mismo que un admin.** Fuera de él no ve nada, y lo que es de la empresa
—la gente, la biblioteca de criterios, la auditoría de IA— sigue siendo de
`admin`.

## 1 · Alcance

**Entra:**

- El predicado `ApplicationPolicy#administra?(challenge)`, que es la regla
  nueva, escrita una vez.
- Su aplicación puerta por puerta en `ChallengePolicy`, `ChallengeStepPolicy`,
  `IdeaPolicy`, `AssessmentPolicy`, `FeedbackItemPolicy` y `CriteriaSetPolicy`.
- Que el gestor pueda **crear** un desafío, quedando asignado a él en el mismo
  movimiento.
- Que **no pueda sacarse a sí mismo** de un desafío que acompaña.
- Esconder «Guardarlos también en la biblioteca» a quien no puede escribir en
  la biblioteca.
- Dar vuelta los ejemplos de la suite que hoy afirman lo contrario, y una spec
  de policy tabular que fije el reparto entero.

**No entra:** las membresías, la auditoría de IA (`/admin/ai_runs`) y crear o
editar sets **de biblioteca** siguen siendo de `admin`. Tampoco se toca ninguna
vista salvo la del botón de promover.

## 2 · Las decisiones, y por qué

### 2.1 · La regla se llama `administra?` y vive una sola vez

En `ApplicationPolicy`, junto a `manager?` y `reaches_challenge?`:

```ruby
# Administrar ESTE desafío: quien administra la empresa, y el gestor al que se
# lo asignaron. `manager?` sigue significando «administra la empresa» y es lo
# que protege lo que no cuelga de ningún desafío.
def administra?(challenge)
  manager? || (membership.present? && membership.gestor? && reaches_challenge?(challenge))
end
```

No es una forma nueva: es exactamente la expresión que `ChallengePolicy#curate_pool?`
ya tenía escrita a mano, la única puerta que el gestor había ganado hasta hoy.
Lo que cambia es que ahora tiene nombre y la usan todas.

### 2.2 · Por qué no se toca `manages_challenges?` ni se vuelve mágico `manager?`

Se evaluaron dos atajos y los dos se descartan:

- **`Membership#manages_challenges? = admin? || gestor?`** es un carácter de
  diff y abre las membresías, la auditoría de IA y la biblioteca a **todo
  gestor de la empresa, sin acotar por desafío**. El método se llama
  «manages_challenges?», así que es la tentación obvia; es la que no hay que
  tomar.
- **`manager?` sensible al record** —que cada policy diga cómo llega a su
  desafío— abre de una las dieciocho puertas por-desafío sin tocar una sola call site. Pero entonces
  `MembershipPolicy` y `AiRunPolicy` quedan cerradas **por accidente**
  (`reaches_challenge?(nil)` da `false`), y la razón por la que las membresías
  siguen siendo de admin deja de estar escrita. Además `authorize AiRun, :index?`
  pasa la **clase**, no una instancia, así que un `record.challenge` genérico
  revienta.

Con `administra?` explícito, las tres puertas que quedan de admin se quedan
**porque nadie las tocó**, y eso se lee en el diff. Y una puerta futura nace
como `manager?`, que es el lado seguro.

### 2.3 · El reparto

| Policy | Puertas | Después |
|---|---|---|
| `ChallengePolicy` | `builder?` `start?` `close?` `update_pipeline?` `curate_pool?` | `administra?(record)` |
| `ChallengeStepPolicy` | `advance?` `skip?` `manage_form?` `manage_criteria?` `manage_assignments?` `report?` | `administra?(record.challenge)` |
| `IdeaPolicy` | `update?` `destroy?` | `administra?(record.challenge)` |
| `AssessmentPolicy` | `create?` `update?` | `administra?` del desafío del módulo |
| `FeedbackItemPolicy` | `resolve?` | `administra?(record.idea.challenge)` |
| `CriteriaSetPolicy` | `update?` de un set `inline` | `administra?(record.owner_step.challenge)` |
| `ChallengePolicy` | `create?` | `manager? \|\| gestor?` — ver 2.4 |
| `MembershipPolicy` · `AiRunPolicy` · `AiSuggestionPolicy#index?` · `CriteriaSetPolicy` sobre la biblioteca | todas | **sin cambio** |

`ChallengeStepPolicy#configure?` delega en `ChallengePolicy#update_pipeline?`,
así que se abre solo. Y `AiSuggestionPolicy#accept?` cae en `update_pipeline?`
para las tareas de alcance `:challenge`, así que **pedirle y aceptarle cosas a
la IA sobre su desafío también se abre solo**: no hay nada que tocar ahí, y hay
que probarlo igual.

**Ninguna vista cambia por esto.** Los 45 usos de permisos en HAML preguntan por
`policy(...)`, que es justamente donde CLAUDE.md manda que viva la guarda.

### 2.4 · Crear un desafío, y quedar asignado a él

`ChallengePolicy#create?` pasa a aceptar al gestor. Sin nada más, sería una
trampa: el `Scope` filtra por `challenge_gestores`, así que el gestor crearía el
desafío y desaparecería de su lista en el mismo movimiento.

Por eso `ChallengesController#create`, **dentro de la misma transacción que el
`save`**, le crea su `ChallengeGestor` cuando quien crea es gestor. La
validación `user_must_be_gestor` ya se cumple por construcción: tiene rol
`gestor` en esa empresa, que es lo que lo trajo hasta acá.

Es la única acción del cambio que escribe un registro, y por eso es la única que
necesita transacción.

### 2.5 · Nadie se saca a sí mismo

Con `update_pipeline?` abierto, el gestor administra `challenge_gestores` de su
desafío: suma y saca gente. Sacarse a sí mismo lo deja afuera en el acto, sin
forma de volver salvo que un admin lo reasigne.

`ChallengeGestoresController#destroy` rechaza ese caso y sólo ese. Un admin no
puede caer en él: `user_must_be_gestor` impide que un admin esté en la tabla.
Sacar a **otro** gestor sigue permitido — es parte de administrar el desafío.

### 2.6 · Las dos exclusiones que se quedan, y por qué son de otro eje

`IdeaPolicy#create?` (el gestor no postula ideas propias) y `#submit?` (no
postula por el autor) **no se tocan**. No son tacañería de permisos: son
conflicto de interés. Un gestor que propone ideas en el desafío que administra
guía a su propia competencia, y postular por el autor le saca al autor la
decisión de presentarse.

`submit?` es `update? && !acompana?`, así que sigue funcionando **sin tocarlo**
aunque `update?` se abra. Era lo que más riesgo tenía de romperse en silencio,
y por eso tiene ejemplo propio en la verificación.

### 2.7 · Los sets `inline` sí, la biblioteca no

Un set `inline` es de un módulo: lo edita quien administra ese desafío. Un set
`library` se comparte entre **todos** los desafíos de la empresa, incluidos los
que el gestor no ve, así que crearlo y editarlo sigue siendo de admin.

`CriteriaSetPolicy#destroy?` se queda en `manager?` sin excepción: borrar un
set es una acción de las pantallas de biblioteca, y un set `inline` se va solo
con su módulo.

De ahí sale un botón que hay que esconder. `steps/_criterios_editor.html.haml`
ofrece «Guardarlos también en la biblioteca», y vive detrás de `configure?`. Con
`configure?` abierto y la biblioteca cerrada, al gestor le aparecería un botón
que le rebota con 403 — el control fantasma que esta app viene persiguiendo. El
link pasa a preguntar por `CriteriaSetPolicy#create?`.

### 2.8 · Código que queda muerto y se borra

La rama `acompana?` de `IdeaPolicy#update?` deja de alcanzarse: para un gestor
asignado, `administra?` ya devolvió `true` antes. Se borra la rama; **el método
privado `acompana?` se queda**, porque `submit?` lo sigue usando.

Lo mismo con la línea `return reaches_challenge?(...) if membership.gestor?` de
`FeedbackItemPolicy#resolve?`, que `administra?` cubre entera.

## 3 · Archivos que se tocan

- `app/policies/application_policy.rb` — el predicado nuevo.
- `app/policies/challenge_policy.rb`, `challenge_step_policy.rb`,
  `idea_policy.rb`, `assessment_policy.rb`, `feedback_item_policy.rb`,
  `criteria_set_policy.rb` — el reparto de 2.3.
- `app/controllers/challenges_controller.rb` — la auto-asignación.
- `app/controllers/challenge_gestores_controller.rb` — no sacarse a uno mismo.
- `app/views/steps/_criterios_editor.html.haml` — la guarda del botón de
  promover. **Única vista que cambia.**
- `spec/requests/gestor_spec.rb` y los demás de la lista de verificación.

## 4 · Verificación

**Una spec de policy tabular** (`spec/policies/gestor_administra_spec.rb`) que
recorra cada puerta contra tres sujetos: admin, gestor **asignado** y gestor
**no asignado**. Es el único lugar donde el reparto entero se lee de una, y es
lo que impide que una puerta se abra de más sin que nadie lo note.

**Dar vuelta lo que hoy afirma lo contrario.** `spec/requests/gestor_spec.rb`
tiene 387 líneas y al menos tres ejemplos que afirman que el gestor **no** puede
lo que ahora sí podrá: «ni configura el flujo», «pero no puede pedirle que arme
el flujo», «pero no con la ronda cerrada». Se dan vuelta con su motivo nuevo, no
se borran: lo que probaban sigue importando, cambió la respuesta.

**Revisar, sin dar por hecho que pasan:** `pantalla_del_modulo_spec.rb` (los
bloques por rol), `dos_caras_spec.rb`, `duplicados_spec.rb`,
`evaluator_rules_spec.rb`, `ideas_spec.rb`, `memberships_spec.rb`,
`participant_rules_spec.rb`, `sin_membresia_spec.rb` y
`spec/policies/assessment_policy_spec.rb`.

**Ejemplos que no pueden faltar**, porque son los que se rompen en silencio:

- El gestor **no postula** ni postula por el autor, con `update?` ya abierto.
- Un gestor **no asignado** sigue recibiendo **404** en cada ruta, no 403.
- Un gestor **sin membresía** sigue sin ver nada (`ApplicationPolicy::Scope`).
- El gestor crea un desafío y **lo sigue viendo** en el índice.
- El gestor **no se saca a sí mismo**, y **sí saca a otro**.
- El gestor guarda los criterios `inline` de su módulo por
  `PUT /api/v1/criteria_sets/:id`, y **no** puede crear uno de biblioteca.
- El gestor pide y acepta una propuesta de IA de alcance `:challenge`.

**`make spec` y `make screens`** al cierre. `make screens` importa acá aunque no
haya CSS de por medio: el recorrido entra a las pantallas de módulo y las
capturas fallan con cualquier HTTP >= 400, que es exactamente la forma de un
permiso mal repartido.

## 5 · Fuera de alcance

- **Las membresías, la auditoría de IA y la biblioteca**, por decisión tomada.
- **`ChallengePolicy#update?` y `#destroy?`**: no se tocan porque **no existen
  como ruta**. `resources :challenges, only: %i[index new create show]` — nadie
  borra ni edita un desafío hoy, ni admin. Son código muerto y se quedan como
  están.
- **Una guarda de lint que obligue a decidir cada `manager?` nuevo.** Sería el
  equivalente de `paridad_de_rotulos_spec.rb` para permisos. Vale la pena y no
  es de esta rama.

### Hallazgo preexistente, que esta rama no arregla

`CriteriaSetPolicy::Scope` achica **sólo para el gestor**: para participante y
evaluador hace `scope.all`. Como `criteria_sets/index.html.haml` no tiene
ninguna guarda y `show?` es `membership.present?` heredado, **un participante
lista y abre por `/criteria_sets` los sets `inline` de desafíos que no puede
ver**. Es la misma fuga de lectura que CLAUDE.md cuenta haber cerrado; quedó
cerrada sólo para el rol que la destapó. Merece rama propia.

## 6 · Riesgos

- **El riesgo real es abrir de más, y es silencioso.** Un permiso que se abre no
  rompe ningún test: simplemente deja pasar. Por eso la spec tabular de 4 es
  requisito y no adorno, y por eso incluye al gestor **no asignado**, que es el
  sujeto donde un error se ve.
- **`reaches_challenge?` con `nil`.** Devuelve `false` para un gestor y `true`
  para un admin (sale antes por `manager?`). Toda llamada a `administra?` tiene
  que poder recibir un desafío nulo sin reventar: los records llegan por
  cadenas opcionales (`record.challenge_step&.challenge`).
- **El orden de `AssessmentPolicy#create?` no se toca.** Primero
  `reaches_challenge?`, después el conflicto de interés, y recién ahí el rol. Si
  `administra?` se pone antes del chequeo de participación, quien administra
  vuelve a poder puntuarse a sí mismo.
