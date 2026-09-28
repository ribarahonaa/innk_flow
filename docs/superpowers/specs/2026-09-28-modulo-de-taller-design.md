# El taller: un evento sobre desafíos en curso

Un taller es una sesión de trabajo —un jueves a las 15:00, con gente convocada—
que ayuda a las personas a **generar ideas** para uno o varios desafíos, sola o
en mesas. No es una etapa del flujo: es un evento que se monta sobre la fase
que cada desafío ya está corriendo.

Un taller abarca **N desafíos**, y sólo admite los que están en **idear** o en
**evolución**. En un desafío que está en idear, la mesa postula ideas nuevas.
En uno que está en evolución, la mesa trabaja las ideas que ya existen y
**propone** versiones nuevas que su autor publica.

## 1 · Alcance

**Entra:**

- Las cinco tablas del taller, con tenencia y FKs compuestas.
- La sala del taller: una pantalla propia con una cara por desafío vinculado,
  según el `kind` del módulo contra el que trabaja.
- Las mesas, incluidas las de una persona sola en modo individual.
- La propuesta de versión, su aceptación desde la ficha de la idea, y el tercer
  `actor_type` de `IdeaVersion`.
- `WorkshopPolicy` con su `Scope`, y el 404 por `policy_scope`.
- Seeds propios, capturas propias y las claves de `es.yml`.

**No entra** (ver *Fuera de alcance*):

- Polinización cruzada: una mesa no trabaja ideas de gente que no está en ella.
- Tareas de IA propias del taller.
- Cualquier cambio al motor del pipeline.

## 2 · Lo que NO cambia, y por qué es el punto

Esta es la decisión de fondo, y todo lo demás cuelga de ella.

**El motor del pipeline no se toca.** `Flow::Pipeline#active_step` es
`steps.find { |s| s.active? || s.activating? }`: **un** módulo activo, por
construcción, y de ahí cuelgan `advance!`, `insertion_floor`, el drawer, el
mapa del flujo y `Flow::Setup`. El taller no es un `kind`, no ocupa posición,
no se activa ni se completa, y no aparece en el flujo de nadie.

**`Idea` no cambia.** `ideas.challenge_id` sigue siendo obligatorio y único:
cada mesa trabaja contra un desafío concreto, así que nunca hay una idea sin
desafío. No hay estado nuevo, ni columna nueva, ni dueño nuevo.

**`IdeaPolicy::Scope` no cambia.** La regla «quien participa ve sólo las ideas
en las que participa» queda intacta, y la visibilidad por mesa **cae de ella**
en vez de agregarle una excepción. Es la regla que este repo más audita, y ya
se pagó una fuga por dejar una policy vacía (`CriteriaSetPolicy`).

Si alguna tarea del plan de implementación necesita tocar uno de estos tres,
es señal de que el diseño se desvió: hay que volver acá antes de seguir.

## 3 · Las siete decisiones, y por qué

### 3.1 · La sesión es lo compartido; el vínculo apunta al MÓDULO

`workshop_challenges.challenge_step_id` guarda el módulo concreto contra el que
el taller trabaja en ese desafío, no la fase ni el desafío a secas. De ahí
salen tres cosas sin escribir código:

- El `kind` de ese módulo decide el modo de la sala: `ideation` → postular
  ideas; `evolution` → proponer versiones.
- El vínculo se cierra cuando ese módulo deja de estar activo.
- Las versiones y las propuestas nacen con **el `challenge_step_id` correcto**.
  Esto no es prolijidad: `feedback_items.challenge_step_id` «no es un dato de
  auditoría, es a qué conversación pertenece el comentario», y un desafío puede
  tener varias rondas de evolución. Un taller que guardara sólo el desafío
  mezclaría dos conversaciones.

Es el mismo *late binding* que ya usa el pipeline: `config` guarda la
intención, `resolved_config` se escribe una vez al arrancar. Acá vale igual, y
de ahí sale el ciclo de vida:

| Estado | Qué se puede hacer | Qué pasa al entrar |
|---|---|---|
| `draft` | sumar y sacar desafíos, armar mesas, convocar | — |
| `open` | trabajar en la sala | se resuelve el `challenge_step_id` de cada vínculo contra el módulo activo, y se rechaza el desafío cuyo módulo activo no sea `ideation` ni `evolution` |
| `closed` | leer | se cierran todos los vínculos |

Por eso `challenge_step_id` es nulo mientras el taller es borrador: entre que
se arma y que se abre, el desafío pudo avanzar. La fase se verifica **al
abrir**, no al sumar, y después se verifica sola (3.7).

### 3.2 · Convocar es sumar a una mesa

No hay una lista de convocados aparte de las mesas: **estar convocado es estar
en una mesa.** Convocable es cualquiera con membresía en la empresa, y en modo
`individual` sumar a una persona le crea su mesa de uno en el acto.

Una lista de convocados separada de las mesas serían dos fuentes para la misma
pregunta —«¿quién está en este taller?»— y la primera vez que difirieran, una
de las dos estaría mintiendo.

### 3.3 · La mesa existe siempre

En modo `individual` el taller crea **una mesa por persona**. No hay dos
caminos en el código —uno para individual y otro para grupal—: hay mesas, y a
veces son de a uno.

Un mecanismo y un gancho. Es la misma razón por la que todo lo plegable de la
app es un `<details>`.

### 3.4 · La visibilidad por mesa no se programa

Crear un borrador en la sala **es** crear una `Idea` en `draft`, con quien lo
crea como `author` y **el resto de la mesa como `idea_contributors` desde el
minuto cero**.

Con eso, «veo las ideas de mi mesa y no las de las otras» es exactamente
`IdeaPolicy::Scope` tal como está: «las que creó y aquellas en las que
colabora». Y «quien administra o acompaña ve todas las mesas» también, porque
esas tres cosas ya se hacen sobre el pool entero.

La alternativa —un `workshop_group_ideas` con su propia rama de visibilidad—
se descartó: agrega una excepción a la única regla que no conviene tener
repartida.

**Consecuencia aceptada:** al cerrar el taller, lo que no se postuló queda como
borrador y **sigue siendo de su mesa**, porque los `idea_contributors`
persisten. Es lo correcto: lo trabajaron entre todos.

### 3.5 · En evolución, la mesa trabaja lo de sus integrantes

Una mesa puede trabajar una idea si alguno de sus miembros la creó o colabora
en ella. Nada más.

Esto cierra la puerta a la polinización cruzada —una mesa no puede tomar con
ojos frescos la idea de alguien que no está en ella— y a cambio deja
`IdeaPolicy::Scope` sin una sola línea nueva. Es un formato de taller real:
traé tu idea y la mejoramos entre los de la mesa.

Si algún día se quiere lo otro, el lugar es una rama declarada en
`IdeaPolicy::Scope` y una tabla de asignación, acotada a mientras el vínculo
esté abierto. Está fuera de alcance.

### 3.6 · El taller propone; el autor publica

Una propuesta de versión nace `pending` en `workshop_proposals` y **se muestra
en la ficha de la idea**, al lado de donde ya se muestran las propuestas de la
IA. Quien es autor acepta y ahí se publica la versión; descarta y no pasa nada.

**El paso de aceptación va siempre, incluso cuando el autor está en la mesa.**
Dos razones: el autor puede no estar —alguien colabora en la idea de otro y
están en mesas distintas— y un solo camino vale más que dos. Con el autor en la
mesa es un clic.

**No se edita al aceptar.** Precedente directo y reciente:
`Tasks::EvaluateIdea#editable?` se borró porque aceptar una propuesta
admitiendo un payload editado era una capacidad del dominio sin interfaz.

Al aceptar se publica una `IdeaVersion` con `actor_type: "workshop"`,
`source_step` = la ronda de evolución del vínculo, `created_by` = quien aceptó,
y los integrantes de la mesa se suman como `idea_contributors`.

**Una propuesta pendiente se vence con su ronda.** Aceptar publica una versión
`source_step` de esa ronda de evolución, y publicar dentro de una ronda que ya
cerró escribiría en una conversación terminada. Así que aceptable es
`pending? && challenge_step.active?`, y no hay estado nuevo: se muestra vencida
por el mismo predicado perezoso con que se cierra el vínculo (3.7). Un estado
`expired` obligaría a alguien a escribirlo, y ese alguien sería un hook en el
motor.

**No se reusa `ai_suggestions`.** `AiSuggestion belongs_to :ai_run` es
obligatorio y `ai_runs.purpose` tiene un CHECK de Postgres: meter ahí una
propuesta que no viene de la IA obliga a aflojar esa FK y ensucia la pantalla
de auditoría de IA, que es una pantalla del producto. El ahorro sería de
vistas; el costo, conceptual y permanente.

### 3.7 · El cierre del vínculo es perezoso

Cuando un desafío avanza de fase, su vínculo con el taller se cierra: no se le
puede aportar más, y el taller sigue vivo para los demás. **El flujo manda
sobre el evento, no al revés.**

Pero nada se engancha en `advance!`. `WorkshopChallenge#open?` pregunta si su
módulo sigue activo, y `closed_at`/`closed_reason` se materializan cuando
alguien entra a la sala. El taller se entera; no interviene.

La alternativa —que un taller abierto trabe el avance— le daría a un evento
poder sobre el motor, y un taller olvidado abierto dejaría un desafío trabado.

**Nota:** el vínculo se cierra ante **cualquier** avance, incluido el de idear
a evolución, que es una fase también admitida. El modo de trabajo de una mesa
no puede cambiar debajo de sus pies a mitad de sesión. Un taller que quiera
acompañar las dos fases se vuelve a vincular.

## 4 · Modelo de datos

Cinco tablas nuevas, todas por `tenant_table` y con `add_tenant_fk`, todas en
inglés (`CLAUDE.md`: «toda tabla y toda columna nueva va en inglés, sin
excepción»). Las cinco llevan `company_id` por `tenant_table`, y cada FK de
abajo es compuesta `(x_id, company_id)`.

```
workshops
  name              string   NOT NULL
  mode              string   NOT NULL  CHECK ("individual"|"group")
  status            string   NOT NULL  CHECK ("draft"|"open"|"closed")
  scheduled_at      datetime
  created_by_id     → users

workshop_challenges
  workshop_id       → workshops
  challenge_id      → challenges
  challenge_step_id → challenge_steps      el módulo contra el que trabaja;
                                           NULL mientras el taller es borrador
  status            string  CHECK ("open"|"closed")
  closed_reason     string
  closed_at         datetime
  unique (workshop_id, challenge_id)

workshop_groups
  workshop_id       → workshops
  name              string   NOT NULL     "Mesa 1"

workshop_group_members
  workshop_group_id → workshop_groups
  user_id           → users
  unique (workshop_group_id, user_id)

workshop_proposals
  workshop_group_id → workshop_groups
  idea_id           → ideas
  challenge_step_id → challenge_steps      la ronda de evolución
  payload           jsonb    NOT NULL
  status            string   CHECK ("pending"|"accepted"|"rejected")
  reviewed_by_id    → users
  reviewed_at       datetime
```

`challenge_id` convive con `challenge_step_id` en `workshop_challenges` aunque
sea derivable: es lo que permite el índice único por desafío y evita un join
para listar los desafíos de un taller.

**Cambio a una tabla existente:** `idea_versions.actor_type` suma `workshop` a
`ACTOR_TYPES`. Hay **CHECK de Postgres** sobre esa columna, así que va con
migración; sin ella revienta con `PG::CheckViolation` antes de crearse, igual
que pasó con `ai_runs.purpose`.

**Una persona, una mesa por taller.** Validación de modelo, más un índice único
que la respalde.

## 5 · Las dos caras de la sala

`WorkshopsController#show` despacha por el `kind` del módulo de cada vínculo,
igual que `StepsController#show` despacha por `step.touched?`.

### Cara «idear»

La mesa tiene un tablero de borradores del desafío vinculado. Crear uno crea la
`Idea` en `draft` (ver 3.4). El payload toma la forma de los `form_fields` del
módulo de idear de **ese** desafío.

Postular usa el camino que ya existe. El módulo de idear está activo por
definición —es la condición del vínculo—, así que no hay riesgo de la idea sin
fila en ninguna `step_entries`, que es el bug que `CLAUDE.md` deja anotado.

### Cara «evolución»

La mesa ve las ideas que puede trabajar (3.5) y edita un payload propuesto.
Guardar crea el `workshop_proposals` en `pending`. La aceptación no ocurre acá:
ocurre en la ficha de la idea.

### Vínculo cerrado

Se muestra cerrado, **con el motivo**, y no desaparecido. Una sala que pierde
un desafío sin decir por qué es el mismo control fantasma que el repo viene
sacando.

## 6 · Permisos

`WorkshopPolicy` **no nace vacía**: una policy sin nada propio hereda
`show? = membership.present?`, o sea «cualquiera de la empresa lee esto», y eso
ya causó una fuga con `CriteriaSetPolicy`. Su `Scope` pregunta primero por la
membresía: sin membresía, `none` (`spec/tenancy/sin_membresia_spec.rb`).

| Acción | Quién |
|---|---|
| Ver un taller | quien está en alguna de sus mesas, o quien administra alguno de sus desafíos |
| Crear, abrir, cerrar | `administers?` |
| Sumar un desafío | `administers?(ese desafío)` — un gestor sólo suma los suyos |
| Armar mesas | quien administra alguno de sus desafíos |
| Trabajar en la sala | quien está en una mesa |
| Aceptar una propuesta | **sólo** quien es autor de la idea |

Dos cosas que la tabla no dice y conviene que estén escritas:

**Participar de un desafío vinculado NO alcanza para ver el taller.** Un taller
es por convocatoria: se ve si se está en una mesa. Que el desafío de uno esté
en el taller no es una invitación.

**Aceptar una propuesta es sólo del autor, ni siquiera de quien administra.**
El sentido del paso es que a nadie le reescriban la idea sin que participe; un
atajo para administradores lo borraría. La consecuencia —si el autor no
vuelve, la propuesta se vence con su ronda— es el precio y es correcto.

Los talleres se buscan por `policy_scope(Workshop).find_by!`: **lo que no se ve
da 404**, no 403, porque un 403 sobre algo que no se debería ver es un oráculo
de existencia. Mismo patrón que desafíos e ideas.

Todo controller del taller que llegue a una idea va por `policy_scope`. Ojo con
el lint: `spec/lint/ideas_por_policy_scope_spec.rb` es texto y su comentario
dice qué no ve; lo que prueba el comportamiento son los `[404, 404]` ruta por
ruta.

## 7 · Cómo se verifica

- **`make screens`** con **desafíos de seed propios del taller**. `CLAUDE.md`
  es explícito: apuntar una captura a un desafío que también se usa a mano ya
  rompió la corrida dos veces. Navegación **por link**, nunca `goto`.
  Capturas: sala en idear, sala en evolución, la propuesta en la ficha de la
  idea, taller cerrado, y un vínculo cerrado por avance de fase.
- **`spec/tenancy/`**: el `default_scope` de los cinco modelos y las FKs
  compuestas. El acotador de `SET NULL` ya lee el catálogo entero, así que
  cubre las nuevas solo.
- **`spec/policies/`**: el reparto completo, al estilo de
  `gestor_administra_spec.rb`, que existe porque **abrir un permiso de más no
  rompe ningún test**.
- Un request spec con los **`[404, 404]` ruta por ruta**, al estilo de
  `participant_rules_spec.rb`.
- Las claves de `es.yml`: sin ellas los rótulos salen en inglés por el fallback
  `humanize`, que es como `test_idea` se quedó sin traducir.

## 8 · Fuera de alcance

- **Polinización cruzada** (3.5). El día que se quiera: una rama declarada en
  `IdeaPolicy::Scope` y una tabla de asignación, acotada a mientras el vínculo
  esté abierto.
- **Tareas de IA del taller.** El marco existe (`Tasks::Base.scope_of`,
  `AiSuggestionPolicy`, los tres modos), y sumar una tarea son cuatro lugares
  —la clase, `AiRun::PURPOSES`, el CHECK de Postgres y `flow.ai_purposes`—.
  Nada lo impide; no entra ahora.
- **Módulos en paralelo.** Si algún día el producto los necesita, es un cambio
  del motor y merece su propio diseño. El taller no lo justifica solo.
- **Publicar directo cuando el autor está en la mesa** (3.6). Es una línea si
  se decide; queda el camino uniforme.

## 9 · Riesgos

- **El taller toca `ideas` desde afuera del flujo.** Es la primera cosa que
  crea ideas sin ser el módulo de idear. La condición del vínculo lo acota —el
  módulo de idear está activo—, pero es la línea a vigilar en la revisión.
- **Cinco tablas es mucha superficie de tenencia de una sola vez.** Los specs
  de `spec/tenancy/` no son opcionales acá.
- **La sala es una pantalla con dos caras y N desafíos.** Es donde más fácil se
  cuela un control que no responde: un bloque servido sin su guarda. La forma
  que el repo ya fijó es una variable calculada una vez arriba, no un predicado
  escrito en cada bloque.
