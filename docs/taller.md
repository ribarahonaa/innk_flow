# El taller

Un taller es un **evento que abarca N desafíos**, no un módulo más del flujo.

Ésa es la frase de la que cuelga todo lo demás. El motor tiene un módulo activo
por construcción (`Flow::Pipeline#active_step`), y el taller **se monta encima
de la fase que cada desafío ya está corriendo**: no lo hace avanzar ni lo traba
—nada se engancha en `advance!`—.

Lo que ata el taller al desafío es el **MÓDULO**
(`workshop_challenges.challenge_step_id`), resuelto al abrir con el mismo late
binding del pipeline.

## El ciclo de vida

```
draft ──Open──> open ──Close──> closed
                 │
                 └─ MaterializeClosures cierra vínculos vencidos, de a uno,
                    y NUNCA cierra el taller
```

| Estado | Qué significa |
|---|---|
| `draft` | Se arma: se le suman desafíos y se convoca gente. Los vínculos **no tienen módulo todavía** |
| `open` | Trabaja. Cada vínculo abierto tiene su `challenge_step` resuelto |
| `closed` | Terminó. `Close` cierra el taller **y** todos sus vínculos |

**Y un taller abierto puede no tener NINGUNA fase: ahí está la trampa.**
`MaterializeClosures` cierra los vínculos vencidos de a uno y **nunca** cierra
el taller, así que «abierto con todos sus vínculos cerrados» es un estado que la
app produce sola. `AssignGroups` lo rechaza con su propio mensaje
(«Los vínculos de este taller ya se cerraron») y la vista pregunta lo mismo. Sin
esa guarda el ternario caía en la rama de idear y `participant_ids` sentaba a
**todos los `participant` de la empresa**, a ninguno de los cuales convocó
nadie.

`Close` **exige `open?`**: sin la guarda, un POST sobre un borrador lo saltaba a
`closed`, y como `Open` exige `draft?` no se podía volver atrás nunca. Un estado
terminal sin guarda no es una decisión de producto, es un bug de máquina de
estados.

## Abrir: un taller trabaja sobre UNA sola fase

`Flow::Workshops::Open` resuelve, de una vez, contra qué módulo trabaja en cada
desafío, y verifica que todos estén en la misma fase.

Las dos únicas fases trabajables son `ideation` y `evolution`
(`WorkshopChallenge::WORKABLE_KINDS`). Un desafío en evaluación, selección,
reportería o testing se **cierra con su motivo** al abrir.

Tres cosas de este servicio que no son obvias:

**La fase se verifica ACÁ y no como validación de modelo.** En borrador el
vínculo todavía no tiene `challenge_step`, así que la fase no existe y no hay
con qué comparar. Y se verifica **sobre todo junto**, que es lo que ningún otro
lugar puede hacer.

**Va antes de escribir nada.** Rechazar después de cerrar vínculos dejaría el
taller a medio abrir hasta que el rollback lo deshaga, y el motivo del rechazo
se leería sobre un estado que ya no existe.

**El mensaje nombra qué desafío está en cuál fase.** «El taller mezcla fases»
sin los nombres deja a quien lo lee abriendo los desafíos de a uno.

Y un taller sin una sola sala no se abre: el rollback deja todo como estaba,
también los vínculos que se acababan de cerrar en el mismo intento. Un taller
«abierto» con la pantalla vacía es peor que el error.

### El cierre es perezoso

`Flow::Workshops::MaterializeClosures` corre en las **DOS** entradas
—`workshops#show` y la sala—, en las dos **antes** de leer los vínculos.

Nada se engancha en `advance!`: eso le daría a un evento poder sobre el motor, y
un taller olvidado abierto dejaría un desafío trabado. **Entrar es justo lo que
hace que el taller se entere de que el desafío avanzó.** Sin eso el vínculo
quedaba `open` con su `challenge_step` ya `completed`: la sala no lo dibujaba en
ninguna cara —salía **en blanco**— y el armado lo listaba sin motivo.

El motivo lo arma `Open.reason_for`, que es **público y de clase** para que lo
reuse el cierre perezoso: dos textos para lo mismo divergen, y el día que
difieran uno estaría mintiendo. `MaterializeClosures` agrega el único caso que
`Open` no tiene —el desafío avanzó a una fase que el taller **también** sabe
trabajar (idear → evolución)—: el vínculo se cierra igual, porque **el modo de
trabajo de una mesa no puede cambiar debajo de sus pies a mitad de sesión**.

## Las mesas

### Convocar es sumar a una mesa

`Flow::Workshops::Convoke`. **No hay una lista de convocados aparte**: dos
fuentes para «quién está en este taller» divergen, y la primera vez que difieran
una de las dos estaría mintiendo. **Estar convocado ES estar en una mesa.**

El asiento es `workshop_group_members`, con `UNIQUE (workshop_id, user_id)`.
Ese UNIQUE es lo que `convoked?` no puede garantizar —es un `exists?` seguido de
un `save`— así que el servicio **rescata `RecordNotUnique`** y lo devuelve como
el mismo «ya está en una mesa» que la lectura habría dicho.

### La presencia se escribe de dos formas

`workshops.attendance_mode`:

| Modo | Quién escribe la presencia |
|---|---|
| `presumed` | Lo de siempre: el reparto sienta al pool completo y **marcar ausentes es la excepción**. De ahí que `attended` tenga default `true` |
| `registered` | La escribe alguien: el **check-in por link** o el **toggle** de cada integrante |

Con `registered`, convocar a mano deja el asiento **AUSENTE** —está invitado, no
llegó— y el pool de idear deja de incluir a los `participant` de la empresa. Sin
eso el escaneo es decorativo, porque el pool automático sienta igual a quien no
vino.

**El token y el modo son dos cosas.** `checkin_token` es la credencial y
`attendance_mode` la semántica: si el modo se derivara del token, rotarlo para
revocar un link filtrado devolvería la asistencia a presumida en medio de la
sesión. **Rotar revoca; apagar el modo cambia cómo se cuenta.**

### El check-in por link

`GET /checkin/:token` y `POST /checkin/:token` →
`WorkshopCheckinsController`. **Es la ÚNICA ruta pública que escribe datos del
dominio sin que nadie haya probado quién es.** El login también se sirve sin
sesión, pero elige la empresa entre las membresías de alguien que ya se
autenticó con su clave; ésta resuelve el tenant **desde un token que cualquiera
con el link tiene**.

Va colgada de la raíz y no de `workshops` justo por eso: quien escanea no tiene
sesión y el tenant sale del token.

`Flow::Workshops::CheckIn` **es idempotente, y no por prolijidad**: un link se
escanea dos veces con los dedos fríos, y la pantalla se recarga. La segunda vez
marca presente y **no mueve a nadie** —quien ya estaba convocado a la Mesa 3 no
termina en la llegada por haber escaneado—. Y si `Convoke` falla porque otro
escaneo de la misma persona ganó la carrera, eso **para el check-in es éxito**:
la persona está sentada. Propagar el fallo le diría «no entraste» a alguien que
entró, y el doble toque es lo más común que le pasa a un QR.

`Workshop#checkin_state` devuelve **un** valor cerrado
(`:off · :draft · :open · :closed`) en vez de varios booleanos, y la pantalla lo
despacha con un `case` **con `else`**: así no puede quedarse muda cuando mañana
haya un estado más, que es justo cómo una sala se renderizó vacía sin un solo
mensaje. Borrador y cerrado se distinguen porque la pantalla dice cosas
distintas —«volvé cuando empiece» sobre un taller que ya terminó es mentira—.

### La mesa de llegada

`workshop_groups.arrival`, con **índice UNIQUE parcial** (`WHERE arrival`). Es
la **sala de espera**: ahí cae quien entra por el link y quien se queda sin mesa
al borrarse la suya.

`Workshop#arrival_group!` la crea si falta, y tiene dos cosas que parecen de
más:

- **Su propio savepoint** (`transaction(requires_new: true)`). El método se
  llama FUERA de una transacción (el escaneo) y ADENTRO de una (borrar una
  mesa). Adentro, un UNIQUE violado por el `create!` aborta la transacción
  entera si no hay savepoint, y el `find_by!` del rescate corre contra una
  transacción envenenada (`PG::InFailedSqlTransaction`): un 500 justo donde se
  promete recuperar.
- **El rescate de `RecordNotUnique`**, por lo mismo que `Convoke`.

En modo `individual` devuelve `nil`: **no hay mesa de llegada**, porque cada
persona ES su mesa.

**Todo lugar que se negaría a dejar trabajar desde la llegada pregunta
`arrival?`.** No hay un número acá a propósito: una lista se verifica con
`grep -rn "arrival?" app` y un número no, y éste ya se desactualizó dos veces.
Los lugares, agrupados por lo que el chequeo **hace**:

- **Los controllers que rechazan una escritura:** `WorkshopIdeasController`,
  `WorkshopProposalsController`, `WorkshopDraftsController`,
  `WorkshopRecordingsController`.
- **Las dos caras de la sala**, que en vez del trabajo dicen que la mesa todavía
  no se armó: `workshop_rooms/_ideation` y `_evolution`.
- **La negativa a BORRAR la llegada** —no a trabajar desde ella—:
  `WorkshopGroupsController#destroy`, que redirige con aviso (la llegada se va
  sola cuando el reparto la vacía).
- **El panel «Tu mesa»**: `workshops/_my_group`.
- **Las lecturas que devuelven nada**: `WorkshopGroup#workable_ideas`
  (`Idea.none`) y, en `WorkshopRoomsController`, `load_ideation`,
  `load_recordings` y las dos cargas del borrador.

`load_ideation` es **load-bearing** y no prolijidad: `policy_scope(Idea)`
devuelve `all` a todo rol que no sea `participant`, así que sin ella quien
administra y está sentado en la llegada vería las ideas de los treinta que
esperan, bajo el título «Las ideas de tu mesa».

Y `AssignGroups#seat!` la **excluye de las mesas reusables**: es la primera
creada, así que la habría convertido en «Mesa 1» con `arrival: true` puesto y su
sala habría quedado muda para siempre.

## El reparto

Dos objetos, y la división importa:

| Objeto | Qué hace |
|---|---|
| `Flow::Workshops::Seating` | **No toca la base.** Recibe grupos indivisibles y un tamaño, devuelve mesas más lo que tuvo que desprender |
| `Flow::Workshops::AssignGroups` | Elige la ENTRADA según la fase, pone los guardas y persiste |

### Idear no es otro algoritmo

Es el mismo con **grupos de una persona**. `AssignGroups` arma la entrada según
la fase —en evolución un grupo por idea con su gente, en idear uno por persona—
y `Seating` hace el reparto igual. Un mecanismo y un gancho.

El algoritmo: componentes conexos sobre «comparten una persona» (racimos), cada
racimo partido en bloques que entren, y los bloques chicos empacados por
first-fit decreciente. **«Indivisibles» tiene una excepción, y es la única:** un
grupo más grande que el tamaño no tiene frontera por donde cortar, así que se
parte su gente y el aviso sale con `inside: true`.

### Los cuatro guardas de `AssignGroups`

1. **`open?`** — en borrador los vínculos no tienen módulo, así que no hay fase
   con la que elegir el criterio.
2. **No `individual?`** — juntaría las mesas de una persona, y una mesa reusada
   conservaría el nombre que `Convoke#own_group` le puso.
3. **`phase` no nula** — el estado que la app produce sola, arriba.
4. **Sin propuestas.** Rearmar borra las mesas que queden vacías, y
   `workshop_proposals.workshop_group_id` es **`ON DELETE CASCADE`**: una mesa
   con propuestas se llevaría las aceptadas, que son la **procedencia de
   versiones ya publicadas**. Con trabajo hecho, las mesas se mueven a mano.

El borrado que lo haría va por Rails —`WorkshopGroup` declara
`has_many :workshop_proposals, dependent: :destroy`— y debajo está el piso de la
FK. **Los dos**, porque sacar la cascada de la FK no quitaría el riesgo: el que
está en el camino es el `dependent:`.

### Nunca evicta, y borra sólo las mesas que quedan vacías

Quien está sentado **por una convocatoria a mano** entra al reparto aunque su
rol no esté en el pool automático: sacarlo desharía una decisión que alguien
tomó a propósito.

Un **ausente conserva su asiento**, así que su mesa no queda vacía y no se borra
— y de rebote una mesa reusada puede terminar con **MÁS gente que el tamaño
pedido**. Es a propósito: **el tamaño habla de quién está presente.**

Los ausentes se descuentan en las **dos** fases: en evolución, si alguien no
vino su idea pierde a esa persona y eso **cambia los racimos**. Y cómo se lee
«no vino» depende del modo: con la presencia presumida se descuenta sólo a quien
está marcado ausente; con la presencia registrada no alcanza, porque
`absent_ids` sólo conoce a quien TIENE asiento y el autor que nunca escaneó
armaría su mesa igual, alrededor de alguien que no está en la sala.

**En evolución sólo se vuelve grupo de una persona quien está sentado y no está
en ninguna idea.** Sumar un grupo de una persona que YA está en una idea no
cambia las mesas —el racimo las une y la deduplicación lo absorbe—, pero sí
agrega una clave que el reparto puede elegir para desprender, y ahí el aviso
anuncia un corte que no movió a nadie.

### El barrido de mesas vacías y la carrera

`seat!` borra una mesa sólo si está **vacía de las cuatro cosas**:

```ruby
mesa.destroy! if mesa.workshop_group_members.empty? &&
  mesa.workshop_proposals.empty? && mesa.workshop_drafts.empty? &&
  mesa.workshop_recordings.empty?
```

Las tres últimas cláusulas no son cinturón y tirantes:

- **Propuestas:** el guarda de arriba corrió **fuera del lock**, contra un
  escritor que no toma ninguno. Si una propuesta entra a mitad del reparto y
  deja a su mesa vacía, borrarla se llevaría la propuesta por el CASCADE.
- **Borradores:** su escritor tampoco toma lock y se dispara una vez cada dos
  segundos mientras alguien teclea. Y acá la cláusula **es el ÚNICO chequeo**,
  porque el guarda de arriba no mira borradores.
- **Grabaciones:** acá no hace falta ninguna carrera. En idear el guarda de
  arriba **no se interpone nunca** —sólo mira `WorkshopProposal`, que es un
  artefacto de evolución—, así que cambiar el tamaño de mesa y repartir de nuevo
  es una operación común y las mesas de más quedan vacías. El barrido se las
  llevaba con sus grabaciones, y `has_one_attached :file` **purga el blob**.

Lo que **no** se extiende es el guarda de arriba: negarse a repartir porque
alguien tecleó una palabra —o grabó— bloquearía una operación común. Ese guarda
existe por la procedencia de versiones publicadas, y un borrador no la tiene.

### El límite aceptado: las filas de mesa se reusan por índice

`seat!` toma `workshop_groups.where(arrival: false).order(:created_at)` y le
asigna el reparto nuevo, así que **«Mesa 1» puede quedar con gente
completamente distinta**.

En idear el borrador cuelga de la **fila** de la mesa y no tiene idea a la cual
colgarse: su única llave es esa fila. Quien escribió entra a su mesa nueva y no
encuentra su texto; quien cae en la fila vieja lo recibe prellenado, y si aprieta
«Crear borrador» se publica una versión con ese texto **a su nombre**. El sello,
que nombra a quien escribió, mitiga y no arregla.

**La grabación hereda eso mismo, con voces de personas adentro**, y el cálculo
no es el mismo: lo que cambia de dueños es una conversación grabada,
identificable por la voz, y la tarjeta de la mesa nueva ofrece el link para
**descargarla**. Un borrador se lee y se puede tirar; una grabación se baja.

Las dos cosas están **aceptadas como límite** porque las salidas son peores:
borrar al repartir destruye lo único irrecuperable —«sin el audio una
transcripción mala es definitiva»— y negar el reparto bloquea una operación
común. Mover mesas a mano, con trabajo hecho, es lo que la pantalla recomienda.

## La sala

**La pantalla del taller ELIGE; la sala trabaja.**

```
GET /workshops/:id                          workshops#show        el selector
GET /workshops/:workshop_id/salas/:id       workshop_rooms#show   el trabajo
```

El `:id` de la sala es el del **VÍNCULO**, no el del desafío, porque es el
vínculo el que sabe contra qué módulo se trabaja.

Antes `workshops#show` apilaba un formulario por desafío, uno debajo del otro y
sin decir de qué trataba ninguno. Hoy es una fila por vínculo con el nombre del
desafío, su `brief` truncado y «Entrar».

**Los vínculos no trabajables se listan con su motivo y sin botón**: una sala
escondida no se distingue de una que nunca existió, y entrar a una por URL
renderiza el motivo y **no** 404 —el vínculo existe y el selector lo lista;
esconderlo ahí sería el oráculo al revés—.

### Con una sola sala el taller redirige

Y el breadcrumb de la sala pregunta lo **MISMO**. Si el taller manda a la sala,
un link «volver al taller» rebota en bucle: por eso la pregunta vive **una** vez,
en `Flow::Workshops::Rooms#redirects?`.

Son **dos** condiciones y la segunda no es la obvia: que quien mira no pueda
armar el taller **y** que el taller tenga un solo vínculo EN TOTAL
(`links.one?`), no una sola sala trabajable. Con dos vínculos donde uno cerró,
redirigir dejaba la sala cerrada y su motivo **sin ningún camino** —el
breadcrumb, correctamente, no ofrece volver—, así que quien no administra nunca
se enteraba de que ese desafío estuvo en el taller: exactamente lo que el
selector existe para no hacer.

`Rooms` expone sólo `links`, `workable`, `only_room` y `redirects?`, y nada más
a propósito, para que no se vuelva el cajón de todo lo del taller.

`workshops#show` **conserva el flash al redirigir** (`flash.keep`), y es una
línea defensiva: el aviso llega a la sala sin ella, porque esa rama no instancia
el flash. Importa porque es la única cadena de DOS redirects de la app
(`POST /checkin/:token` → `workshops#show` → la sala) y un `flash.now` agregado
ahí mañana se llevaría puesto, en silencio, el único acuse del único camino
público que escribe datos del dominio.

### Las dos listas de ideas salen de fuentes distintas

Es lo primero que un lector va a equivocar.

| Cara | Fuente | Qué trae |
|---|---|---|
| **idear** | `policy_scope(Idea)` con el filtro por integrantes de la mesa **adentro** del scope | `status` en `draft` o `active` |
| **evolución** | `WorkshopGroup#workable_ideas` | La unión sobre los integrantes: «traé tu idea y la mejoramos entre todos». `Idea.alive`, o sea sin borradores |

El filtro va **adentro** del scope y no en vez de él: el scope hace la fuga
imposible por construcción (un borrador creado en la sala nace con la mesa
entera como `idea_contributors`, así que cada integrante lo ve por
`IdeaPolicy::Scope`), y el filtro es lo que impide que a quien el scope le
devuelve `all` —todo rol que no sea `participant`— le liste las ideas de OTRAS
mesas bajo un título que dice que son de ésta.

Y la consulta de idear vive **en el controller** a propósito:
`spec/lint/ideas_por_policy_scope_spec.rb` sólo mira controllers, así que
escondida en un presenter o en el HAML no la ve nadie.

### Sobre qué mesa actúo

Son **dos preguntas distintas**, y por eso hay dos métodos:

| Método | Pregunta |
|---|---|
| `Workshop#group_of(user)` | **Mi** mesa. La preguntan el panel «Tu mesa» y el camino sin administrar de las grabaciones |
| `ActsOnAGroup#acting_group(workshop, link)` | La mesa **sobre la que actúo**. La consultan los cinco caminos de la sala |

Darle un parámetro a `group_of` era la tentación obvia y es la peor salida: dos
de sus llamadores preguntan legítimamente por la propia, y un método con dos
significados es cómo se abren las fugas. Se verifica con
`grep -rn "group_of(current_user)" app`.

**La mesa NOMBRADA gana, y el asiento propio es el FALLBACK:**

```ruby
def acting_group(workshop, link)
  named_group(workshop, link) || own_group(workshop)
end
```

El orden sale del **modelo del dominio** y no de la implementación: los únicos
que se mueven entre mesas son quien administra la empresa y el gestor, y
**ninguno de los dos participa en una** —se mueven para monitorear y dar
feedback—, así que para ellos no hay asiento propio que proteger y nombrar una
mesa es la forma normal de entrar. Quien participa nunca se mueve solo: lo mueve
quien administra.

**Al revés —el asiento primero— era un control que no responde:** estando
sentado en una mesa, apretar «Entrar» en otra navegaba, cambiaba la URL y
dibujaba la mesa propia con el título «tu mesa», **sin una palabra**.

**Para quien no administra ese desafío el parámetro se IGNORA, no se rechaza.**
Cae a su propio asiento, sin 403. Un 403 confirmaría que esa mesa existe.

### El parámetro `mesa` viaja en la ESCRITURA

Cinco helpers de ruta lo arman con `mesa: group&.id`: las ideas y el borrador en
`_ideation`, las propuestas y el borrador en `_evolution`, y las grabaciones en
`_recording`.

Va en el **query de la URL de acción** y no en un campo oculto, para que sea un
solo mecanismo también en `draft_url` y `recording_url`, que no son formularios
sino URLs que lee el JavaScript. **No es** un segundo id en el segmento de ruta,
que mentiría: el `:id` es el del vínculo.

**No lo «limpies» por redundante:** sin él quien administra y no está sentado
ENTRA, lee la mesa ajena, y cada escritura cae a `own_group` → `nil` y rebota.
Un formulario que se dibuja y no responde.

Su testigo es `spec/requests/la_mesa_viaja_en_la_escritura_spec.rb`, que
renderiza la sala, **saca la URL de acción del HTML servido** y escribe contra
ÉSA. Los request specs que mandan `mesa` a mano no cubren la cadena: estuvieron
verdes con las cinco vistas sin el parámetro.

### Los textos que dicen «tu mesa»

Salen de **una variable por archivo**, no de un `if` por frase: `de_la_mesa` en
`_ideation` y `_evolution`, y el local `mesa_propia` —con default `true`— en
`workshops/_my_group`, que es el partial compartido. Con una mesa ajena cada
frase dice el **NOMBRE**.

**Si alguien agrega un texto nuevo con «tu mesa» fijo, miente en cuanto la mesa
es ajena.** El grep es `grep -rni "tu mesa" app/` —y es `app/` y no `app/views`
a propósito: **los controllers también tienen textos**—. Y **no los encuentra
todos**: «Trabajás sola o solo en este taller» no contiene «tu mesa» y también
mentía. En un redirect la salida es un texto **neutro** («esa mesa»):
condicionarlo cuesta más y neutro no puede mentir.

**No hay ninguna guarda**: ni un lint ni `make screens` cazarían un texto fijo
nuevo. Lo único que cubre esto son los ejemplos de
`spec/requests/entrar_a_una_mesa_spec.rb`.

El aviso de mesa ajena se escapa con el **sufijo `_html` de la clave de
traducción**, y con nada más: el nombre de la mesa es texto libre y el aviso lo
interpola adentro de un `<strong>`. La línea **no lleva `.html_safe`**: sería un
no-op hoy y volvería explotable un renombre de la clave mañana.

## El borrador de la mesa

**Lo que la mesa teclea se autoguarda en el SERVIDOR dos segundos después de la
última tecla, sin publicar nada.** Vive en `workshop_drafts` y mandarlo sigue
siendo apretar el botón.

**El borrador es de la MESA y no de cada persona** (último que escribe gana, del
lado del servidor). Es lo único que sobrevive al caso que esto existe para
evitar: que al que escribe se le muera la máquina o se vaya, y el texto quede
para el resto.

**Gana el borrador sobre la versión vigente, CON aviso.** Las otras dos opciones
estaban mal: que ganara la versión tira el trabajo de la mesa sin preguntar —el
autor aceptando algo desde su teléfono le borraría el texto en medio de la
sesión— y que ganara en silencio hace que la mesa mande una propuesta que
revierte la versión nueva sin enterarse.

### El sello de la versión

`based_on_version_id` **se escribe SÓLO al crear la fila**
(`if draft.new_record?`). Si se reescribiera en cada autoguardado, el aviso de
base vieja no podría dispararse nunca.

**Y esa versión la dice el CLIENTE, no la base.** Es el único lugar de la app
donde un dato del navegador entra a una columna con FK: la vista publica
`draft_base`, el JS lo lee de `dataset.draftBase` y lo manda como
`base_version_id`, y el servidor lo busca en `idea.versions`.

El motivo es que el formulario se prellena al **renderizar** y la mesa puede
tardar en teclear: entre el render y la primera tecla la versión puede avanzar, y
sellar la nueva sobre contenido de la vieja apagaba el aviso para siempre.

**Lo que lo hace seguro son tres cosas, y sólo una está escrita en el código.**
El `find_by` cuelga de `idea.versions`, que filtra por `idea_id` y —por
`TenantScoped`— por `company_id`. La columna es `uuid`, así que basura o una
clave ausente castean a `nil` antes del SQL. Y lo peor que logra un cliente que
miente con una versión vieja de SU idea es que el aviso dispare de más, que es
el lado seguro.

**Ojo con las dos últimas: son portantes y no se leen del código.** Si la
columna cambiara de tipo, o si el `find_by` se moviera a `IdeaVersion`, se irían
a la vez la seguridad de tipo y el scope.

Y el eslabón del medio —que el JS lo lea y lo mande— **no lo caza ningún request
spec** (mandan `base_version_id` a mano) ni la guarda del navegador (no publica
ninguna versión entre el render y el tipeo). Lo cuida
`spec/lint/sello_del_borrador_spec.rb`, que compara contra el código SIN
comentarios —los tres nombres aparecen también en prosa—.

### Tres detalles del endpoint

- **Un `PATCH` sin `payload` es un no-op a propósito**, y lo mismo si después de
  filtrar no sobrevive ninguna clave: con `fetch(:payload, {})` un bug del
  cliente pisaría el texto de la mesa con nada. Los tres caminos responden 204,
  así que el endpoint manda la cabecera **`X-Draft-Saved: "0"`** en los dos que
  NO escriben — sin eso el sello diría «Guardado ahora.» sobre un guardado que
  no ocurrió.
- **El JS exige exactamente 204, no `res.ok`.** Un `before_action` que redirige
  —sesión caída, membresía revocada— le llega al `fetch` como 200: el `fetch`
  sigue el 302 y convierte el PATCH en GET, así que la pantalla de login
  satisface `res.ok`. Con `!res.ok` el sello diría «Guardado ahora.» cada dos
  segundos sobre un guardado que nunca ocurrió, y **la mesa pierde todo al
  mandar**. Ese bug es silencioso por construcción.
- **La fase la decide la SALA**: un `idea_id` mandado a la cara de idear se
  ignora.

### Lo que no cubre nada

**Un envío FALLIDO pierde lo tecleado desde la última pausa de dos segundos.**
El listener de `submit` pone `sucio = false` —tiene que hacerlo: si no, cada
envío exitoso recrearía el borrador con lo que el servidor acaba de publicar—, y
los caminos de rechazo de la sala redirigen con un `alert:`, o sea 302 → 200, así
que `turbo:submit-end` informa `success: true`. Encima el morph pisa lo tecleado:
Turbo 8 llama a `morphElements` **sin `ignoreActiveValue`**, así que
`syncInputValue` le devuelve al campo el valor del servidor, incluso al que
tiene el foco.

**No es que no haya salida: no hay salida barata.** El discriminador no es el
código de estado sino **si el borrador sobrevivió**: capturar el cuerpo en el
`submit`, y en el render siguiente mirar si `#draft-stamp` volvió NO vacío. Que
no se descarte creyendo que es imposible.

Y **el camino concurrente no lo mide nada**: el `AbortController`, los dos
`form !== enviadoDesde` que impiden que un acuse aterrice en el sello de otra
idea, `descargar()`, el `keepalive` y el `visibilitychange`. La guarda del
navegador llena los campos seguidos —cada `fill` reinicia el debounce— así que
dispara **un solo** `guardar()` por cara. No se le puso guarda a propósito: una
que depende de ganarle a una carrera cuesta más en fallas intermitentes de lo que
ahorra.

## La grabación

El audio sube **de una vez, al parar** (`WorkshopRecordingsController`), un job
lo transcribe con `Flow::AI.speech_provider` y la tarjeta muestra las utterances
con sus hablantes.

### La línea de sonido va en barras del DOM y NUNCA en un `<canvas>`

No hay un solo canvas en el repo, y el motivo de que siga así es que **un canvas
es una caja negra para todas las guardas** —las de clases, contraste y sombra no
ven adentro— y una guarda que no puede ver **da permiso**.

Las 40 barras nacen en el **MARKUP** y el JS sólo escribe su `height`: así
Tailwind ve las clases, y un morph que borre los `style` en línea se arregla en
el frame siguiente. El color sale de `--dato` / `--dato-fuerte`: tinta de DATOS
y no el acento, porque una barra pintada del color del botón de al lado se lee
como un control.

**Lo que hace medible a la onda es `data-level`**, donde el bucle de dibujo
publica el RMS crudo. La guarda del navegador lo muestrea cada 100 ms y exige
dos cosas: un pico durante la voz **y una corrida de muestras cerca de cero**.
Sólo la segunda discrimina: una onda decorativa hecha con `Math.random()` pasa
el umbral del pico de sobra y no produce nunca la corrida. Por eso
`script/fake_audio.wav` está armado **voz → SILENCIO → voz**. Si alguien
«simplifica» ese wav a una sola voz corrida, la guarda queda midiendo que algo se
mueve y nada más.

### `workshop_recording.js` NO para en `turbo:before-render`

Y es a propósito, **al revés de sus dos hermanos**. `arrival_live.js` para ahí y
`workshop_draft.js` descarga ahí, pero ese evento dispara también **en un
morph**, y un morph ocurre con cualquier POST a la misma URL: alguien apretando
«Crear borrador» cortaría la reunión.

Lo que lo permite es que el `MediaRecorder` y los trozos son variables de
**MÓDULO**, así que un morph que reemplaza el botón y las barras no los toca.

**Y `start()` tiene que REPINTAR en un morph, no sólo recablear:** el servidor
renderiza el botón diciendo «Grabar» y el sello vacío, y con un retorno temprano
el micrófono seguía abierto mientras el botón mentía.

**«El estado vive en el módulo» incluye A DÓNDE va lo grabado.** `urlDeSubida` e
`ideaDeSubida` se leen del DOM en `arrancar()`, en el clic, y `subir()` usa ésos
y no `caja.dataset`. Parece redundancia hasta que se ve el camino: `start()` hace
`caja = encontrado` **antes** del `rec.stop()`, así que en una navegación real el
handler de parada corría contra el contenedor de la pantalla NUEVA. Repro de dos
clics: grabando en la sala A, al selector, «Entrar» a la sala B, y **la
conversación de la mesa A se guardaba como grabación de la mesa B**, con su link
de descarga.

### Tres límites declarados

- **Una navegación en medio de la grabación PIERDE el audio**, y `keepalive` no
  lo salva: la spec de Fetch topa el cuerpo de un `keepalive` en 64 KB y el
  audio son megabytes. Sin subida progresiva lo único posible es **avisar**, que
  es lo que hace el `beforeunload`.
- **La tarjeta de grabaciones NO se refresca sola.** No hay frame, ni
  `data-live`, ni poller: el único intervalo es el cronómetro. La mesa sube, ve
  «en cola», y la tarjeta no se mueve hasta que navegue o recargue. El arreglo
  barato está descartado por una razón dura: un poller de página completa le
  pisaría a la mesa lo que está tecleando en el borrador (el morph sin
  `ignoreActiveValue`).
- **`getUserMedia` no existe fuera de un contexto seguro**, y `docker-compose`
  publica el puerto en HTTP plano. Desde la máquina que corre Docker es
  `localhost` y anda; **desde un teléfono de la red en `http://<ip>:3001`,
  `navigator.mediaDevices` es `undefined` y no hay grabación.** La pantalla lo
  detecta y lo dice en vez de dejar un botón mudo. El recorrido corre en
  `localhost`, que es contexto seguro siempre: **ninguna corrida verde dice nada
  sobre esto**.

Y **los hablantes no están verificados con voces reales**: las dos pruebas que
hay usan voces sintéticas y las dos dieron un solo hablante; el español no se
midió nunca. La tarjeta avisa cuando la mesa es de dos y la transcripción trae
uno solo (`collapsed_diarization?`).

## Permisos del taller

Resumen; el detalle está en [`permisos.md`](permisos.md).

| Pregunta | Policy | Qué es |
|---|---|---|
| ¿Lo veo? | `WorkshopPolicy#show?` | Pasa el `Scope`: estar en una mesa, o administrar |
| ¿Lo armo? | `#update?` = `administers_any?` | Administrar **ALGUNO** de sus desafíos |
| ¿Entro a la sala? | `#work?` | Administrar alguno, o estar en una mesa |
| ¿Sumo un desafío? | `#add_challenge?(challenge)` | Se pregunta por el **DESAFÍO**: un gestor no cuela uno ajeno |
| ¿Trabajo en cualquier mesa? | `ChallengePolicy#enter_any_group?` | **Por DESAFÍO**, no por taller |

**`enter_any_group?` es por desafío y no por taller a propósito.** Si la sala ya
le esconde a un gestor el `brief` de un desafío que no le asignaron, dejarlo
**ESCRIBIR** ahí sería abrir escritura sobre algo que no puede leer. Y el
predicado es **NUEVO**: no reusa `builder?` ni `curate_pool?`, que hoy son los
dos exactamente `administers?(record)`. Reusar uno ata el acceso a las mesas al
significado de otra cosa, y el día que alguien mueva `curate_pool?` esto se
movería con él sin que nadie lo decida. **Un nombre prestado es cómo un permiso
se ensancha en silencio.**

**La sala no describe un desafío que quien mira no alcanza.** El NOMBRE se
muestra igual —es lo que dice de qué sala es ésta—; el link, el módulo con su
fase y el `brief` van detrás de `alcanza = policy(link.challenge).show?`, **una**
variable calculada arriba del partial. Lo que **no** se gateó, a propósito: el
`closed_reason` del selector, que nombra la fase del desafío. Es el motivo por el
que esa sala no se puede trabajar —información del taller, no sólo del desafío—.

**Las dos reglas del gestor con las ideas no se abrieron**, y no hizo falta
escribir nada para que se cumplan adentro de la sala: el formulario de idear ya
vive detrás de `puede_crear`, que **es** `IdeaPolicy#create?`. Un gestor que
entra a una mesa ve las ideas, el borrador, las propuestas, la grabación y las
transcripciones, y **no** ve el formulario.

## El seed

**Cuatro talleres, y no por una sola razón.** La regla de una sola fase explica
los tres primeros —sin ella serían dos—:

| Taller | Para qué |
|---|---|
| sobre **idear** | Lleva el desafío que se rechaza al abrirse (de ahí el vínculo cerrado con motivo) y un borrador de Mesa Bodega que existe **sólo** para que la captura dibuje «Las ideas de tu mesa» |
| sobre **evolución** | Lleva la propuesta pendiente |
| **borrador** | La cara de un taller sin abrir |
| **con check-in** | Existe SÓLO para las tres capturas del escaneo, y va **sin nadie sentado** porque una de ellas tiene que mostrar la llegada vacía |

Dos trampas del seed:

- El borrador de Mesa Bodega va **sin postular** a propósito: el editor de
  campos del formulario tiene un candado más fino que `touched?`
  (`ideas.submitted.exists?`), así que postularlo trabaría ese editor por una
  idea que nadie postuló.
- **Sentar a alguien a mano en el taller con check-in rompe su captura**;
  reusarlo para otra cosa, también.

**Y el seed contradice el modelo del dominio en una cosa: sienta al admin en los
dos talleres con mesas.** Es una conveniencia de la SIEMBRA —las guardas del
borrador y de la grabación necesitan a alguien escribiendo desde una sala— y se
deja así a propósito, porque rehacerlo es rehacer parte del recorrido. **No
deduzcas del admin sentado que los admins se sientan.**
