# El borrador de la mesa: lo que se teclea sobrevive al refresh

## El problema

La mesa de un taller se sienta cuarenta minutos a escribir en un formulario de
la sala, y **nada de lo que teclea existe hasta que alguien aprieta el botón**.
Un refresh, una pestaña que se cierra, una batería que se muere, un
`turbo:before-render` de más: se pierde todo, sin aviso y sin forma de
recuperarlo.

Son dos formularios, los dos en la sala (`workshop_rooms/show`):

- **Idear** (`workshop_rooms/_ideation`): arranca en `payload: {}` y postea a
  `WorkshopIdeasController#create`, que crea un borrador de idea con la mesa
  entera como `idea_contributors`. Desde la sala es sólo de CREAR — la lista de
  ideas linkea afuera, a `challenge_idea_path`.
- **Evolución** (`workshop_rooms/_evolution`): arranca prellenado con
  `selected.payload` —el contenido de la versión vigente— y postea a
  `WorkshopProposalsController#create`, que crea una `WorkshopProposal`
  `pending` para que el autor la acepte.

El primer formulario es el que más duele: la mesa escribe desde cero.

## Alcance: esto es B de cuatro, y más chico de lo que estaba fichado

La spec de A (`2026-10-02-sala-de-la-mesa-design.md`) fichó B como «guardado
automático que **publica** una `idea_version` nueva». **No es lo que se decidió
acá.** Lo que B hace es guardar un **borrador de trabajo que todavía no es
versión**; publicar sigue siendo un acto explícito, con el mismo botón y el
mismo camino de hoy.

Eso cambia dos cosas, y las dos para menos:

- **El choque con `WorkshopProposal` no existe.** La regla «la mesa propone y
  el autor decide» queda intacta porque el autoguardado no publica nada. La
  decisión que el handoff del 2026-10-06 declaraba abierta —qué pasa con las
  propuestas pendientes cuando el autosave publica— no tiene objeto: no hay
  publicación que las invalide.
- **El coalescing de versiones tampoco.** El handoff advertía que un autosave
  ingenuo escribe una fila de `idea_versions` por tanda de tecleo, cada una con
  su `embedding vector(1024)` y su `EmbedVersionJob`. Un borrador es **mutable**:
  se pisa en el lugar, no acumula filas y no encola un solo job.

Lo que sigue pendiente de las cuatro: **C** (dictado por voz y resumen) y **D**
(videollamada), cada una con su spec y sus bloqueos de proveedor.

Y la condición de entrada de A vale igual: esto corre **con las mesas ya
repartidas**. Desde la mesa de llegada no se trabaja, y el borrador respeta la
misma guarda (`arrival?`) que las otras puertas de la sala.

## La forma: una tabla propia

### Lo que se descartó, y por qué

- **Reusar `workshop_proposals` con un cuarto status `draft`.** Descartada
  antes de discutir lo demás: `workshop_proposals.idea_id` es **NOT NULL**
  (verificado en `db/structure.sql`), así que no cubre idear —donde la idea
  todavía no existe— y resolvería media B. Y un cuarto status obliga a tocar
  `CHIP_DE_PROPUESTA`, el locale, el CHECK de Postgres, el scope
  `pending_review`, `actionable?`, `WorkshopProposalPolicy`, el bloque «Lo que
  esta mesa propuso» y la ficha del autor, cada uno con un «y que no sea
  borrador» nuevo. Es la familia de defecto que `CLAUDE.md` ya documenta sobre
  el cuarto status de propuesta: el que falte deja texto sin mandar a un clic
  del botón de aceptar del autor. **Un borrador no es una propuesta: nunca se
  mandó.**
- **Una columna `jsonb` en `workshop_groups`.** La migración más chica posible,
  y un bolso con claves `"link_id:idea_id"` adentro: sin FK a la idea, sin FK a
  la versión, sin timestamp por borrador salvo inventando estructura dentro del
  JSON, y con claves que apuntan a nada el día que una idea se borra. Es la
  segunda fuente de verdad que este repo evita en todas partes.
- **`localStorage`.** Cero tablas, cero endpoint, cero tenencia que auditar — y
  cero utilidad para el caso que B existe para resolver: muere con la pestaña en
  incógnito o con la caché limpia, no sigue a otro dispositivo, y es invisible
  para el resto de la mesa. Si al escribiente se le muere la máquina, la mesa
  pierde el texto igual. Además no hay un solo uso de `localStorage` en el repo
  hoy, así que no hay patrón a seguir ni guarda que lo vigile.
- **Edición colaborativa en vivo.** No hay websockets —no hay `app/channels` y
  `turbo-rails` no está en el Gemfile, sólo el paquete npm—, y un formulario que
  se morfea bajo el cursor es peor que no tener nada. El borrador es un buffer
  compartido con última-escritura-gana, no un editor en tiempo real.

### De quién es el borrador

**De la mesa, no de cada persona.** Un borrador por `(mesa, sala)` en idear y
por `(mesa, sala, idea)` en evolución. Quien abre la sala ve lo último que
guardó cualquiera de la mesa.

Es lo que la pantalla ya promete —«el borrador se comparte con Paula
Participante…: es de la mesa, no solo tuyo»— y es lo único que sobrevive al caso
que B existe para prevenir: al escribiente se le muere la máquina o se va, y el
texto sigue ahí para el resto. El precio es que dos personas tecleando a la vez
se pisan y, sin websockets, nadie se entera en vivo. Lo que se da en cambio es
el nombre de quien tocó último, en el sello (ver «El sello»).

## El dato

```ruby
tenant_table :workshop_drafts do |t|
  t.uuid :workshop_group_id,     null: false   # de quién es
  t.uuid :workshop_challenge_id, null: false   # qué sala
  t.uuid :idea_id                              # NULL en idear
  t.uuid :based_on_version_id                  # contra qué versión se tecleó
  t.jsonb :payload, null: false, default: {}
  t.references :updated_by, type: :uuid, null: false,
               foreign_key: { to_table: :users }
  t.timestamps
end

add_index :workshop_drafts, %i[workshop_group_id workshop_challenge_id],
          unique: true, where: "idea_id IS NULL",
          name: "index_workshop_drafts_ideation_uniq"
add_index :workshop_drafts, %i[workshop_group_id workshop_challenge_id idea_id],
          unique: true, where: "idea_id IS NOT NULL",
          name: "index_workshop_drafts_evolution_uniq"

add_tenant_fk :workshop_drafts, :workshop_groups,     column: :workshop_group_id
add_tenant_fk :workshop_drafts, :workshop_challenges, column: :workshop_challenge_id
add_tenant_fk :workshop_drafts, :ideas,               column: :idea_id
add_tenant_fk :workshop_drafts, :idea_versions,       column: :based_on_version_id,
                                                      on_delete: :nullify
```

Toda columna nueva en inglés, sin excepción: es la regla vigente y es donde el
costo de arrepentirse es más alto.

**Dos índices parciales y no uno.** Postgres trata los NULL como distintos, así
que un `UNIQUE(group, link, idea)` a secas dejaría a una mesa acumular un
borrador de idear **por autoguardado** — una fila cada dos segundos. Es el mismo
patrón que `index_workshop_groups_on_workshop_id_arrival ... WHERE arrival`.

**`nullify` en la versión y no `cascade`.** Si se borrara una versión, el
cascade se llevaría el texto de la mesa por un evento ajeno a ella. Nulificando
se pierde sólo el marcador de «contra qué se tecleó» —el aviso de base vieja
degrada— y el texto queda. El helper acota el `SET NULL (columna)` para no
nulear también `company_id`, que es NOT NULL (PG 15+).

**`updated_by_id` NOT NULL es funcional, no auditoría.** Es la única señal de
colisión que se puede dar sin websockets: el sello dice quién guardó último, y
quien llega sabe que no está escribiendo solo.

### El modelo

```ruby
class WorkshopDraft < ApplicationRecord
  include TenantScoped

  belongs_to :workshop_group
  belongs_to :workshop_challenge
  belongs_to :idea, optional: true
  belongs_to :based_on_version, class_name: "IdeaVersion", optional: true
  belongs_to :updated_by, class_name: "User"

  validate :idea_matches_room
  validate :version_belongs_to_idea
end
```

**Dos validaciones, y la primera no puede ser un CHECK.** `idea_id` presente
⟺ la sala es de evolución: Postgres no alcanza el `kind`, que está tres tablas
más allá (`workshop_challenges` → `challenge_steps` → `kind`), así que la regla
vive en el modelo.

Y tiene un caso nil que hay que declarar: **`WorkshopChallenge#kind` es
`challenge_step&.kind`**, o sea **nil mientras el taller es borrador** —el
vínculo todavía no tiene módulo resuelto; es el mismo late binding por el que
`Flow::Workshops::Open` verifica la fase y no lo hace una validación de modelo—.
Con `kind` nil la validación **no opina**: no hay fase contra la que comparar, y
rechazar ahí inventaría una regla sobre un estado que no existe. Lo que cierra
ese camino es el guarda `workable?` del controller, que rechaza antes de llegar
al modelo. Hacer que la validación falle con nil la convertiría en el segundo
lugar que decide si una sala admite trabajo, y los dos divergen. La segunda —`based_on_version.idea_id == idea_id`— cuida que
un borrador no diga basarse en la versión de otra idea, que volvería absurdo el
aviso; es una invariante que hoy sólo el servidor puede romper, y por eso mismo
es la que un copy-paste rompe sin que nada se queje.

`WorkshopGroup` gana `has_many :workshop_drafts, dependent: :destroy`.

### Sin `WorkshopDraftPolicy`, a propósito

Nunca se autoriza un borrador como registro: se **lee** por
`@group.workshop_drafts` —la mesa lo ata por construcción, igual que
`@group.workshop_proposals`— y se **escribe** por un endpoint que autoriza
`@workshop, :work?`. Una policy vacía heredaría `show? = membership.present?`,
o sea «cualquiera de la empresa lee esto», que es exactamente la fuga que una
auditoría encontró en `CriteriaSetPolicy`. **Si mañana aparece un GET de
borrador, necesita un `Scope` de verdad** — no una policy vacía.

## El ciclo de vida

| Evento | Qué pasa | Por qué |
|---|---|---|
| Se manda la propuesta | se borra, en la **misma transacción** | si no, el formulario sigue prellenado con lo ya mandado y la mesa lo manda de nuevo: es el defecto que A existe para arreglar |
| El `create!` de la propuesta hoy NO está en una transacción | **se envuelve** | borrar el borrador y crear la propuesta tienen que ser atómicos: si la creación falla, el texto no puede haberse ido. `WorkshopIdeasController` ya tiene su `ActiveRecord::Base.transaction` con `raise ActiveRecord::Rollback`, así que ahí el borrado entra adentro y no hace falta envolver nada |
| Se crea el borrador de idear | se borra, misma transacción | ídem |
| Se borra la mesa | cascade | `dependent: :destroy` más la FK compuesta |
| La ronda cierra | **nada** | el vínculo deja de ser `workable?` y el formulario no se dibuja; la fila queda inerte. Un vínculo cerrado no se reabre, así que nunca resurge. Un job de limpieza es infraestructura para unas pocas filas |

### El reparto de mesas: una cláusula, y nada más

`Flow::Workshops::AssignGroups` tiene dos cosas distintas, y sólo una se toca:

- **`seat!` borra las mesas que quedan vacías**, con una segunda cláusula
  (`workshop_proposals.empty?`) que su propio comentario declara **LA CARRERA**
  y no cinturón y tirantes: el guarda de propuestas corre FUERA del lock, contra
  un escritor que no toma ninguno. Con `dependent: :destroy`, una mesa vacía que
  tiene borrador perdería el texto en ese barrido. **Se suma
  `workshop_drafts.empty?` a esa cláusula.** Una mesa que sobrevive sólo por
  tener borrador es un sobrante inocuo — exactamente el razonamiento que el
  comentario ya da para las propuestas.
- **El guarda de arriba** (`return failure("Ya hay propuestas en este taller…")`)
  **NO se toca.** Negarse a repartir porque alguien tecleó una palabra bloquearía
  una operación común por texto sin mandar. Ese guarda existe por la
  **procedencia** de versiones ya publicadas; un borrador no la tiene.

## El camino de escritura

### La ruta

```ruby
resources :workshop_challenges, only: %i[show], path: "salas", as: :sala,
                                controller: "workshop_rooms" do
  resources :ideas,     only: %i[create], controller: "workshop_ideas"
  resources :proposals, only: %i[create], controller: "workshop_proposals"
  # Singular: una mesa tiene UN borrador por sala. El id de la idea viaja en el
  # cuerpo y no en la ruta —igual que el `hidden_field_tag :idea_id` del form de
  # propuesta—, porque el cliente no conoce el id del borrador.
  resource :draft, only: %i[update], controller: "workshop_drafts"
end
```

→ `PATCH /workshops/:workshop_id/salas/:sala_id/draft`

### Las cuatro guardas, en el mismo orden que los otros dos POST

```ruby
authorize @workshop, :work?
return head :conflict  unless @link.workable?
group = @workshop.group_of(current_user)
return head :forbidden unless group
return head :forbidden if group.arrival?
```

Repetidas y no reescritas: divergir es cómo se abrió la fuga que
`WorkshopIdeasController` documenta —`work?` da true por `administers_any?` sin
mesa, y sin la guarda del grupo quien administra creaba una idea a su nombre en
la sala de un desafío ajeno—.

### Códigos pelados, nunca un redirect

Los otros dos controllers de la sala redirigen con flash porque los dispara una
persona apretando un botón. **Esto lo dispara un temporizador.** Un
`redirect_to` haría que el `fetch` siga la redirección y traiga la pantalla
entera cada dos segundos. Responde `204 No Content` en el camino feliz.

### La idea se resuelve con el idioma de `WorkshopProposalsController`

```ruby
idea = group.workable_ideas(@link.challenge).find_by!(id: params[:idea_id])
```

Y **no** `policy_scope(Idea)`, por la razón que ya está escrita ahí: ese scope
deja ver a quien participa sólo lo que creó o comparte, y la mesa trabaja la
idea de CUALQUIERA de sus integrantes. El 404 se conserva igual —una idea fuera
del conjunto no se distingue de una inexistente—, así que no es un oráculo.

Pasa `spec/lint/ideas_por_policy_scope_spec.rb` sin excepción nueva, y se
verificó contra el detector en vez de suponerlo: el detector pide `\.ideas\b`
con punto literal, y en `workable_ideas` el carácter previo a `ideas` es `_`. El
comentario del porqué va igual, copiando el que ya existe — el lint no lo
explica.

### El payload y la escritura

El `payload` se filtra contra `form_fields` con el mismo `payload_params` de los
otros dos controllers: una clave que no es de un campo se descarta. Los campos
`file` se excluyen — un borrador no guarda archivos.

```ruby
draft = @group.workshop_drafts.find_or_initialize_by(
  workshop_challenge: @link, idea_id: idea&.id
)
draft.update!(payload: filtered, updated_by: current_user,
              based_on_version_id: idea&.current_version_id)
```

**`based_on_version_id` lo escribe el servidor, nunca el cliente:** es el dato
del que depende el aviso de base vieja, y un cliente que lo manda puede
mentirlo.

**La carrera es real y se maneja.** Dos personas de la mesa guardando a la vez
no encuentran fila, las dos insertan, y el índice parcial levanta
`ActiveRecord::RecordNotUnique`. Se rescata y se reintenta una vez: en el
reintento la fila ya existe y el `find_or_initialize_by` la actualiza. Un
`upsert` sería una sola sentencia, pero saltea las dos validaciones del modelo,
que es justo lo que no se quiere saltear.

### Cuándo dispara

Archivo nuevo `app/javascript/workshop_draft.js`, importado desde
`application.js`. **El ciclo de vida es el mismo par que `arrival_live.js` e
`islands.js`** —`turbo:load` para arrancar, `turbo:before-render` para
limpiar—: un mecanismo, no tres. Sin el limpiado, navegar a otra pantalla deja
un temporizador pidiendo contra una pantalla que ya no está.

- **Debounce de 2 s sobre `input`**, delegado en el formulario. **Sin
  `setInterval`:** el de `arrival_live.js` existe porque el dato cambia en el
  servidor; acá cambia en el navegador.
- **Descarga de lo pendiente** en `visibilitychange → hidden` y en
  `turbo:before-render`, con `keepalive: true`, para que irse de la pantalla no
  se lleve los últimos dos segundos.
- El cuerpo se arma con `URLSearchParams` desde los inputs `payload[...]`,
  **excluyendo `type=file`**: un `FormData` crudo subiría el archivo elegido
  cada dos segundos. Las claves repetidas `payload[k][]` del `multi_select`
  entran como repetidas, que es lo que Rails espera.
- `X-CSRF-Token` del meta tag (`csrf_meta_tags` está en los dos layouts).
- **Qué hace el JS lo dice la VISTA**, igual que `data-live` en
  `arrival_live.js`: el formulario lleva `data-draft-url`, `data-debounce`,
  `data-saved-text` y `data-failed-text`. Las palabras quedan en el locale y el
  JS no sabe de talleres.

**Sin Turbo Streams, y la razón es medida:** `turbo-rails` **no está en el
Gemfile** —sólo el paquete npm `@hotwired/turbo-rails`—, así que no hay
`format.turbo_stream` ni helper que renderice el sello del lado del servidor.
El endpoint devuelve 204 y el JS escribe el texto que la vista le dio. El caso
«guardado por Paula hace dos minutos» lo resuelve el render de HAML, que es
donde el nombre ya está; al JS le queda una cadena fija.

**Un fallo se dice, no se traga.** Con 4xx o 5xx el temporizador para y el sello
pasa a `data-failed-text` —«No se pudo guardar: copiá el texto antes de salir»—.
Un autoguardado que falla en silencio es peor que no tenerlo: la mesa confía y
pierde todo.

## El camino de lectura

### El prellenado

`WorkshopRoomsController` carga el borrador junto con el resto, por la mesa:

```ruby
# load_ideation
@draft = @group.workshop_drafts.find_by(workshop_challenge: @link, idea_id: nil) if @group && !@group.arrival?

# load_evolution
@draft = @group.workshop_drafts.find_by(workshop_challenge: @link, idea: @selected_idea) if @group && @selected_idea
```

Y cada partial cambia **una línea** en la llamada a `ideas/form_fields`:

| Cara | Antes | Después |
|---|---|---|
| idear | `payload: {}` | `payload: draft&.payload \|\| {}` |
| evolución | `payload: selected.payload` | `payload: draft&.payload \|\| selected.payload` |

Nada más: el partial de campos ya pinta lo que recibe.

### El aviso de base vieja

Sólo en evolución, y sólo cuando
`draft.based_on_version_id.present? && draft.based_on_version_id != selected.current_version_id`.

Un `alert alert-soft alert-warning` que nombra las dos versiones y linkea a la
ficha de la idea para ver el contenido nuevo. Dos cosas que no son adorno:

- **Todo el contenido dentro de UN `%div`.** `alert` es `display: grid` con
  `grid-auto-flow: column`: varios hijos se reparten en columnas.
- **Dice explícitamente que lo que se ve es el texto de la mesa y no la versión
  vigente.** Sin esa frase el aviso es peor que nada: la mesa no puede saber
  cuál de los dos está leyendo.

La decisión de fondo: **gana el borrador, con aviso.** Que gane la versión
tiraría trabajo de la mesa sin preguntar —el autor aceptando algo desde su
teléfono le borraría el texto a la mesa en medio de la sesión—, y que gane el
borrador en silencio haría que la mesa mande una propuesta que revierte la
versión nueva sin saberlo, y que el autor reciba algo que deshace lo que acaba
de aceptar sin ninguna señal de por qué.

### El sello

En `.form-actions`, al lado del botón, porque es donde se mira antes de mandar.
Render del servidor cuando hay borrador: «Guardado por ‹nombre› hace ‹tiempo›».
El JS lo reemplaza por `data-saved-text` tras un guardado propio, o por
`data-failed-text` si falló.

El nombre de quien tocó último es lo que hace honesto el caso de dos personas
tecleando: sin websockets no hay aviso en vivo, pero quien recarga ve que no
está solo.

## Lo que NO cubre, declarado

- **Los campos `file` no autoguardan.** Un `<input type=file>` no sobrevive una
  recarga en ningún navegador, así que es consistente con la web — pero va
  dicho para que nadie lo dé por cubierto.
- **No hay historial de borradores.** Se pisa. Lo que la mesa quiera conservar
  lo manda.
- **No hay aviso en vivo de que otra persona está escribiendo.** Lo más cercano
  es el sello al recargar, y es a propósito: el push pediría el canal
  autenticado y scopeado por empresa que la spec de la lista de llegada ya
  descartó.
- **El borrador de una ronda cerrada queda inerte en la base.** No se borra ni
  se muestra.

## Verificación

### Specs de request

`spec/requests/workshop_drafts_spec.rb` (nuevo; nombre en inglés por la regla
vigente, aunque los specs viejos estén en español):

- Las cuatro guardas, cada una con su código: sin mesa, desde la mesa de
  llegada, sala no trabajable, sala de otro taller.
- **Dos PATCH de dos personas de la misma mesa dejan UNA fila.** Es lo que
  prueba el índice parcial, y no la intención de que haya uno solo.
- El prellenado en las dos caras.
- El aviso aparece con la versión avanzada **y no aparece** cuando no avanzó:
  las dos mitades, porque una guarda que siempre dispara no discrimina.
- El borrado al mandar: la propuesta en evolución y el borrador de idea en
  idear.
- **`ideas` no tiene columna `title`:** las ideas del spec llevan versión
  publicada con título propio, o se asevera sobre la URL. Sin eso todas
  devuelven `"(sin título)"` y la aserción pasa sola — pasó de verdad en los
  specs de la sala de la mesa.

### Tenencia

`spec/tenancy/schema_spec.rb` introspecciona `pg_constraint` y falla si aparece
una FK simple entre dos tablas con `company_id`, así que las cuatro FK
compuestas quedan cubiertas sin escribir un ejemplo nuevo. Toda lectura del
dominio va dentro de `as_company(company) { ... }`, el `.new` incluido —toca el
`default_scope`—.

### `make screens`: la guarda `[DRAFT]`

Tipea en el formulario, espera el debounce, **recarga la pantalla** y asevera
que el texto volvió. Es lo único que un spec de Ruby no puede ver: el bundle, el
temporizador y el endpoint pueden estar los tres en verde y el texto no volver —
es exactamente la forma del fallo que `[LIVE]` cazó con `arrival_live.js`.

Con **contador y piso**, porque una guarda que mide cero da verde y es
indistinguible de una que funciona.

Tres reglas de esta casa que aplican con fuerza acá:

1. **`make yarn-build` ANTES de `make screens`.** `workshop_draft.js` es un
   archivo nuevo importado desde `application.js`, y `app/assets/builds/*` está
   gitignoreado entero: sin compilar, el archivo **no existe para el navegador**
   y el recorrido valida en verde una app distinta de la que se escribió. Pasó
   con `llegada_en_vivo.js`: 1558 ejemplos en verde y cero referencias al
   archivo en el bundle.
2. **La guarda se prueba contra un baseline que funciona.** Primero la corrida
   limpia en verde; recién después la mutación. La primera mutación de `[LIVE]`
   corrió sobre el bundle viejo, donde el estado sano y el mutado daban el
   MISMO resultado: no probó nada.
3. **`PISO_DE_BANDAS` es exacto.** Si la sala suma una pantalla con banda, el
   piso sube con ella en el mismo commit.

## Riesgos

- **Dos personas de la mesa tecleando a la vez se pisan**, y el único testigo es
  el sello al recargar. Es el precio aceptado de que el borrador sea de la mesa;
  la alternativa —un buffer por persona— pierde el texto cuando el escribiente
  se va, que es el caso que B existe para prevenir.
- **El debounce de 2 s es un número elegido, no medido.** Más corto multiplica
  los PATCH; más largo agranda lo que se pierde al cerrar la pestaña, aunque la
  descarga en `visibilitychange` y `turbo:before-render` acota eso. Vive en
  `data-debounce`, así que se cambia en la vista y no en el JS.
- **El aviso de base vieja depende de `based_on_version_id`**, que `nullify`
  puede dejar en NULL si alguna vez se borra una versión. En ese caso el aviso
  no aparece y el borrador se prellena en silencio, que es el comportamiento que
  esta spec descartó. Hoy no hay camino que borre una versión sin borrar la
  idea —y la idea cascadea el borrador—, así que es teórico; queda anotado
  porque el día que exista, falla hacia el lado silencioso.
