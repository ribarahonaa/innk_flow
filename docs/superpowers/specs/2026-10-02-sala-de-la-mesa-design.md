# La sala de la mesa: una pantalla por desafío

## El problema

Las mesas ya están armadas y la gente está sentada. A partir de ahí, lo que la
app le ofrece a quien participa es **la pantalla del taller con todas las salas
apiladas**: un formulario de ideación por cada desafío vinculado, uno debajo del
otro, sin nada que diga de qué trata cada desafío y sin forma de elegir.

Tres huecos concretos, medidos en el código de hoy:

- **No se ve con quién estás sentado.** El bloque que lista las mesas
  (`workshops/_groups`) vive detrás de `can_assemble`, que es
  `policy(@workshop).update?`: lo ve sólo quien administra. Quien participa lee
  una sola frase, dentro de la sala de idear: «el borrador se comparte con
  Paula Participante…».
- **El desafío no se presenta.** `challenges.brief` existe y la sala no lo
  muestra en ninguna parte. La mesa decide sobre qué trabajar leyendo el nombre.
- **Lo que la mesa produce desaparece.** `WorkshopIdeasController#create` y
  `WorkshopProposalsController#create` redirigen al taller con un aviso. El
  borrador recién creado no se lista en ninguna pantalla que la mesa esté
  mirando, y la propuesta enviada tampoco: la mesa no tiene de dónde saber que
  ya lo hizo, así que lo hace de nuevo.

Lo que pidió Raúl: que la mesa vea con quiénes está, que elija un desafío
—viendo de qué trata antes de elegir, salvo que haya uno solo—, que el
formulario aparezca recién después de elegir, y que en un taller de evolución
vea las ideas de su mesa con la participación de cada uno y pueda abrir una y
ver su contenido.

## Alcance: esto es A de cuatro

El pedido original abarcaba cuatro subsistemas. Se decidió partirlo y esta spec
es **sólo el primero**:

| | Subsistema | Estado |
|---|---|---|
| **A** | La sala de la mesa: mesa visible, selector de desafío con brief, formulario al elegir, selector de idea en evolución | **esta spec** |
| **B** | Guardado automático que publica una `idea_version` nueva | pendiente, spec propia |
| **C** | Dictado por voz, resumen de la reunión con IA y «armar la idea desde el resumen» | pendiente, spec propia |
| **D** | Videollamada dentro de la sala, con notas y resumen | pendiente, spec propia |

Dos cosas quedaron decididas acá y condicionan las otras:

- **A no toca el camino de escritura.** En evolución, el formulario sigue
  creando una `WorkshopProposal` `pending` que el autor acepta o rechaza. El
  guardado directo como versión nueva borraría la regla «nadie reescribe la
  idea de otro» y eso se decide completo en B, no de costado acá.
- **A no necesita proveedor nuevo.** C sí: no hay speech-to-text en el repo, y
  no lo hay porque Anthropic no lo expone — `FLOW_AI_PROVIDER` (chat) y
  `FLOW_EMBEDDINGS_PROVIDER` (vectores) son los dos ejes que existen.

Y una condición de entrada que vale para las cuatro: **esto corre con las mesas
ya repartidas.** Antes del reparto, la mesa de quien entra es la de llegada, y
ahí la sala dice «tu mesa todavía no se armó» — la misma guarda (`arrival?`) que
ya protege las otras tres puertas.

## La forma: una pantalla por sala

Se descartaron dos alternativas:

- **Un acordeón por desafío dentro de `workshops/show`.** Sin rutas nuevas,
  pero la pantalla carga los formularios de todos los desafíos, la mesa no
  puede ir en columna propia sin pelearse con el bloque de armado, y no queda
  link a «mi sala».
- **Una isla Vue.** Las cuatro islas que hay son todas de configuración, con
  props serializadas por un presenter. En A no hay estado de cliente que
  justifique una quinta, y suma recompilar el bundle y las guardas de islas de
  `make screens`. Si B necesita guardado automático, Turbo con debounce alcanza.

### La ruta

Reusa el anidado que ya existe, cambiando `only: []` por `only: %i[show]`:

```ruby
resources :workshop_challenges, only: %i[show], path: "salas", as: :sala,
          controller: "workshop_rooms" do
  resources :ideas, only: %i[create], controller: "workshop_ideas"
  resources :proposals, only: %i[create], controller: "workshop_proposals"
end
```

`GET /workshops/:workshop_id/salas/:id` → `WorkshopRoomsController#show`. Los
dos POST no se mueven: su ruta ya era la correcta y el id que viaja en ella es
el del **vínculo**, no el del desafío, que es lo que sabe contra qué módulo se
trabaja.

El vínculo se busca con `@workshop.workshop_challenges.find_by!` sobre un taller
que ya pasó por `policy_scope(Workshop)`: lo que no se ve da 404 y no 403.

`authorize @workshop, :work?` — el mismo predicado que los dos POST, no uno
nuevo. Eso incluye a quien administra sin estar sentado, porque `work?` devuelve
true por `administers_any?`: la sala se lo dice y no le ofrece formulario, igual
que hoy.

`Flow::Workshops::MaterializeClosures` corre también en la sala, **antes** de
leer el vínculo. El cierre es perezoso —nada se engancha en `advance!`— y entrar
a la sala es justo lo que hace que el taller se entere de que el desafío avanzó;
sin eso la sala dibujaría trabajo sobre un módulo ya cerrado.

### `workshops/show` pasa a ser selector

Una tarjeta por vínculo: nombre del desafío, `brief` truncado, y «Entrar». Qué
se ofrece lo decide `link.room_state`, que ya existe y ya tiene rama por
defecto: `:ideation` y `:evolution` entran; `:closed`, `:unopened` y `:stale` se
listan **con su motivo y sin botón**. No desaparecen: una sala escondida no se
distingue de una que nunca existió, y ese silencio es exactamente el defecto que
`room_state` se escribió para cerrar.

El bloque de armado (`workshops/_assembly`, detrás de `can_assemble`) no se
toca.

### El redirect con una sola sala, y el bucle que abre

Con una sola sala trabajable, el taller **redirige a ella**: es la excepción que
pidió Raúl («a excepción de que solamente hubiera un desafío en el taller»).
Pero sólo cuando la persona no tiene nada más que hacer en el taller:

```
redirige  ⟺  !can_assemble && salas_trabajables.one?
```

Quien administra nunca se redirige: ahí está el bloque de armado.

`salas_trabajables` son los vínculos cuyo `room_state` es `:ideation` o
`:evolution` — o sea `WorkshopChallenge::WORKABLE_KINDS`, no una lista nueva.
`Flow::Workshops::Rooms` expone exactamente dos cosas: ese conjunto y
`redirige?(membership_o_policy)`; nada más, para que no se vuelva el lugar donde
cae todo lo del taller.

Eso abre una trampa. Si el taller redirige a la sala, un link «volver al taller»
rebota en bucle. Así que **el breadcrumb de la sala pregunta exactamente lo
mismo que el redirect**: si hubo redirect va al índice (`Talleres`), si no va al
taller. La pregunta vive UNA vez —`Flow::Workshops::Rooms`, que consultan
`workshops#show` y la sala— y no escrita dos veces: el día que una cambie, la
otra mentiría.

## La sala de idear

Las guardas quedan en el orden de hoy, porque cada una dice algo distinto:

1. sin mesa en este taller → «sólo se crea un borrador desde una mesa»;
2. `group.arrival?` → «tu mesa todavía no se armó: en cuanto se reparta, acá
   aparece el formulario»;
3. sin `IdeaPolicy#create?` (el gestor, por conflicto de interés) → «podés
   acompañar a la mesa, pero no proponer ideas propias».

Recién después, el trabajo, en dos bloques y en este orden:

### 1. «Lo que ya creó la mesa»

Lo nuevo. Sale de **`policy_scope(Idea)` sobre el desafío, con `status` en
`draft` o `active`**, y NO de `WorkshopGroup#workable_ideas`.

El porqué importa. `workable_ideas` filtra con `Idea.alive`, que es
`where(status: "active")`: no trae borradores, y su comentario documenta que
exponer a toda la mesa los borradores que un integrante creó **fuera** del
taller fue una fuga ya arreglada. Con `policy_scope` la fuga es imposible por
construcción: un borrador creado en la sala lleva a toda la mesa como
`idea_contributors` —eso lo hace `WorkshopIdeasController` desde el minuto
cero—, así que cada integrante lo ve por `IdeaPolicy::Scope` tal como está; y el
borrador privado de alguien de afuera lo sigue viendo sólo él.

Se descartó agregar una columna de procedencia (`ideas.workshop_group_id`) para
distinguir «creada en la sala» de «creada afuera»: `policy_scope` ya da la
respuesta correcta sin migración, y una columna nueva es el costo más alto de
arrepentirse.

Cada fila: título, chip de estado, versión vigente, quiénes participan, y link
a la ficha. El chip va con `chip_de_estado` y la etiqueta con
`t("flow.idea_statuses.…")` —«Borrador» y «En carrera»—, el mismo vocabulario
que ya usa `ideas/show`: una etiqueta nueva inventada acá sería una segunda
forma de nombrar lo mismo. **Postular no se duplica**: vive en la ficha, detrás
de `IdeaPolicy#submit?`.

### 2. El formulario

Igual que hoy: `ideas/form_fields` con los campos de `link.challenge_step`,
`multipart`. El encabezado dice «Crear otro borrador» si el primer bloque trae
algo, «Crear un borrador» si está vacío.

### Dos cambios chicos, con motivo

- `WorkshopIdeasController#create` redirige **a la sala**, no al taller. Hoy
  vuelve al taller y el borrador recién creado no se ve en ninguna parte.
- Se cae el `id_prefix` del render de `form_fields`. Existía porque dos salas se
  renderizaban en la misma pantalla y las dos emitían `id="payload_titulo"`, así
  que el `<label for>` de la segunda enfocaba el campo de la primera. Con una
  sala por pantalla la colisión no puede existir. El `shared/_workshop_proposal`
  de `ideas/show` lo sigue usando y no se toca.

## La sala de evolución

Mismas guardas de entrada (sin mesa, mesa de llegada). Después, cuatro bloques.

### 1. Selector de ideas de la mesa

Acá sí sale de `group.workable_ideas(link.challenge)`: es el método que existe
para esto —la unión sobre los integrantes, «traé tu idea y la mejoramos entre
todos»— y ya excluye la mesa de llegada, lo eliminado y lo retirado.

Cada fila: título, versión vigente, y **la participación de cada integrante en
esa idea**: quién la creó y quién colabora, con su rol
(`IdeaContributor::ROLES` — contributor / sponsor / reviewer). La fila
seleccionada se marca.

### 2. El contenido de la idea seleccionada

La misma forma que la tarjeta «Contenido» de `ideas/show`: `%dl.answer-list`,
etiqueta y valor por campo del módulo de ideación, `—` cuando está vacío.

### 3. El formulario de propuesta

Como hoy: campos de ideación con el payload vigente precargado, los de archivo
excluidos con el aviso que ya existe («el campo X no se propone desde el taller,
por eso no está»), POST sin cambios a `workshop_sala_proposals_path`.

### 4. «Lo que esta mesa propuso»

Nuevo, y sólo lectura. Las `WorkshopProposal` de esta mesa sobre la idea
seleccionada, con chip de estado (`pending` / `accepted` / `rejected`) y, cuando
`actionable?` es false, el mismo motivo que ya dice la ficha («la ronda ya
cerró: esta propuesta venció»). Por el mismo defecto que en idear: hoy la
propuesta se manda y desaparece, así que la mesa propone de nuevo. Aceptar y
descartar siguen siendo del autor, en la ficha.

### Cuál idea está seleccionada

Viaja como `?idea=<id>`, leída con `workable_ideas(...).find_by(id: params[:idea])`:
fuera de ese conjunto devuelve `nil`, igual que un id inexistente, así que no
confirma nada. Param y no ruta anidada porque el id de la idea ya tiene su lugar
en el POST de la propuesta, y un GET anidado sería un segundo lugar que la
nombra.

Con una sola idea trabajable se preselecciona sola. Es un **default**, no un
redirect: misma URL, sin riesgo de bucle.

## La columna de referencia

La sala llena `content_for :referencia` y el layout la lee después del `yield`.
No declara layout: `.app-shell` se acomoda con `:has()`. En el taller no hay
drawer —`ShellHelper#desafio_del_shell` devuelve `nil`, porque el taller no
cuelga de un desafío—, así que la grilla queda centro + referencia.

**Orden fijo: primero el desafío, después la mesa.** Es el orden que ya fijaron
las pantallas de módulo —lo propio del módulo, y después quién participa—;
invertirlo acá enseñaría dos órdenes distintos para la misma columna.

1. **«El desafío»**: el `brief` completo, el nombre del módulo contra el que
   trabaja la sala y su fase. El brief truncado va en las tarjetas del selector;
   el completo acá, que es «lo que se consulta y no se edita».
2. **«Tu mesa»**: nombre de la mesa y sus integrantes, uno por línea, vos
   marcado con «(vos)» y quien no vino con «· ausente». **Sin controles**:
   marcar presente y sacar son de quien administra y viven en el bloque de
   armado. En modo `individual` la mesa es de una persona y el panel lo dice en
   vez de esconderse — un panel que desaparece no se distingue de uno roto.

Un solo partial (`workshops/_my_group`), usado por la sala **y** por
`workshops/show`: quien cae en el selector ya ve con quién está. Dos copias del
mismo markup divergen y nadie se entera.

### Sin CSS nuevo

`card` + `card-body`, `.field-list` sin recuadro por ítem (la densidad que ya
pide `.app-aside`), chips por `EstilosHelper` —nunca interpolados, que es lo que
cuida `spec/lint/clases_interpoladas_spec.rb`— y `empty-state` donde no hay
nada. Eso deja sin deuda nueva a `[PANEL]`, `[RELLENO]`, `[CLASES]`,
`[CONTRASTE]` y `[REFERENCIA]`, que mide a 1440×1000 y a 1100×900, donde la
columna sube arriba del trabajo en una fila que se desliza de costado.

### Dos límites, declarados y no resueltos

- La referencia es pegada con `max-height: 100vh`: una mesa muy grande queda
  detrás de su propio scroll. En la práctica `AssignGroups` dimensiona las
  mesas (4 a 8 personas), así que no se mitiga ahora.
- `[ZONAS]` mira pantallas **de módulo**, que la sala no es. No se la suma a esa
  lista y la sala no lleva «Ajustes del módulo».

## Estados raros

Entrar por URL a la sala de un vínculo `:unopened`, `:closed` o `:stale`
renderiza la sala con su motivo y sin formulario. **No 404**: el vínculo existe y
se lista en el selector, así que esconderlo ahí sería el oráculo al revés.

Taller cerrado: `work?` sigue siendo true y el vínculo no es `workable?`, así que
cae en la rama del motivo. Nada que agregar.

## Specs

Request:

- `workshop_sala_idear_spec.rb` y `workshop_sala_evolucion_spec.rb` ya existen y
  hoy asertan sobre `workshops/show`: pasan a asertar sobre la sala.
- Nuevo `workshop_room_spec.rb`: 404 del taller que no se ve; el redirect con una
  sola sala trabajable y que a quien administra **no** lo redirige; el selector
  con brief; los tres mensajes de guarda; la lista de borradores; el selector de
  ideas con la participación de cada uno; `?idea=` con un id ajeno → sin
  selección, no 403; el vínculo no trabajable → motivo y no 404.
- `workshops_spec.rb`: el selector y el redirect.

**La consulta de borradores va en el controller, no en la vista.**
`spec/lint/ideas_por_policy_scope_spec.rb` sólo mira controllers: escrita ahí, la
guarda la cubre; escondida en un presenter o en el HAML, no la ve nadie.

Toda lectura del dominio en los specs va dentro de `as_company(company) { … }`,
incluido un `.new`.

## Capturas: cuatro se rompen, y una a propósito

El recorrido corre como quien administra, y los talleres y desafíos del taller
son **propios del recorrido** (`taller-idear`, `taller-evolucion`,
`taller-avanzado`, más el borrador): no se usan a mano, así que no hace falta
sembrar nada nuevo. Las capturas nuevas también son read-only, para que dos
corridas sin resembrar vean lo mismo.

- **25** (sala de idear) y **26** (sala de evolución) asertan hoy sobre la
  pantalla del taller. Pasan a entrar a la sala **por link** desde el selector
  —nunca `goto`: Turbo no dispara `DOMContentLoaded` al navegar por link y un
  `goto` esconde el bug—. En 26 la aserción cambia de «2 formularios de
  propuesta» a «el selector lista 2 ideas y hay 1 formulario para la
  seleccionada».
- **30b** espera hoy el mensaje de la mesa de llegada en la pantalla del taller.
  El «Taller con check-in» tiene **un solo** desafío (`db/seeds.rb`:
  `checkin_workshop.workshop_challenges.create!(challenge: ideation_challenge)`)
  y Lucía Llegada no administra, así que el taller la **redirige a la sala** y el
  mensaje aparece allá: la captura sigue el redirect con `waitForURL` sobre
  `/salas/`. Es el único cambio de comportamiento visible para alguien que ya
  usaba la app, y es el que se pidió.
- **28** (vínculo cerrado con su motivo) se queda en el taller: el selector lista
  los vínculos no trabajables con su motivo. Hay que confirmar que su
  localizador —`.card` con el nombre del desafío + `p.muted`— sigue matcheando
  el markup del selector.

Capturas nuevas: el selector con brief y «Entrar», y la sala de evolución con una
idea seleccionada (contenido + propuestas de la mesa).

**`make yarn-build` antes de `make screens`.** Se tocan vistas; aunque el plan es
no agregar utilidades nuevas, la hoja y el bundle viven sólo en el contenedor y
están gitignoreados: si se cuela una clase nueva, `make screens` valida en verde
una pantalla distinta de la que escribimos.

## Riesgos

- **El breadcrumb condicional es la pieza frágil.** Si el redirect y el
  breadcrumb dejan de preguntar lo mismo, aparece un bucle o un link muerto. Por
  eso la pregunta vive en un solo lugar y hay spec de las dos ramas.
- **La lista de borradores es la superficie de fuga de esta rama.** Es el único
  lugar nuevo que lista ideas, y el repo ya pagó esta familia de errores cuatro
  veces. Va por `policy_scope(Idea)` en el controller, donde la guarda de lint la
  ve.
- **`workshops/show` cambia para todo el mundo**, no sólo para quien participa:
  el admin deja de ver los formularios apilados. Es intencional —configurar y
  trabajar son pantallas distintas— pero es un cambio de hábito.
