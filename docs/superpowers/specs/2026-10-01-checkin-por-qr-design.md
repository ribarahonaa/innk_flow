# Check-in por QR en el taller

Diseño acordado el 2026-10-01. Convierte la asistencia del taller —hoy una
columna que sólo escriben los specs— en la puerta de entrada: se escanea un QR,
se entra, y quien no tiene cuenta se la crea ahí mismo.

## Qué resuelve

`workshop_group_members.attended` está código-completa desde el reparto de mesas
—la columna, el scope `presentes`, el descuento en las dos fases, el asiento que
el ausente conserva— y **ninguna ruta de la app la escribe**. Es una capacidad
del dominio sin interfaz, igual que el payload editable de `Tasks::EvaluateIdea`
antes de que se borrara.

Lo que falta no es el toggle que el handoff dejó fichado. Es la pregunta de la
que ese toggle era media respuesta: **cómo se entera el taller de quién vino**.
Hoy la convocatoria la escribe quien lleva el taller, de a una persona
(`Flow::Workshops::Convoke`), antes de la sesión y a mano. En una sesión real la
gente llega, varios no están en la empresa todavía, y quien facilita no puede
estar tipeando nombres mientras la sala se llena.

Lo que se pide: **un QR que se proyecta y es la puerta**. Se escanea, se entra, y
si no hay cuenta se crea en el acto.

## Las cinco decisiones

Las cinco se tomaron explícitamente, con el costo de cada una a la vista.

1. **El QR es la PUERTA, no un registro de asistencia.** Escanear convoca —crea
   el asiento— y marca presente. No hay una lista previa contra la que validar.
2. **La semántica de la asistencia es por taller, no global.** Un modo declarado
   (`attendance_mode`): en `presumed` todo sigue como hoy; en `registered` la
   presencia la escribe el escaneo y el pool de idear deja de ser toda la
   empresa. Se eligió por taller y no global para no dejar a los tres talleres
   sembrados —y a los 19 ejemplos de `assign_groups_spec`— con todos ausentes.
3. **El registro pide nombre, email y clave.** Cuenta completa desde el minuto
   cero. Se descartó entrar sin clave: `has_secure_password validations: false`
   lo permite, pero una cuenta sin digest no puede loguearse nunca más y
   `sessions#create` le diría «clave incorrecta» a una cuenta que sí existe —un
   estado nuevo que el resto de la app no sabe manejar, y sin «recuperar clave»,
   que no existe—.
4. **Cualquiera con el QR entra; lo que acota es el token.** Sin padrón previo:
   un padrón es la segunda fuente de «quién está en este taller» que el modelo de
   mesas evitó a propósito, y choca de frente con el motivo del QR («vino alguien
   que no estaba en la lista»). El token es de UN taller, sirve sólo mientras
   está `open` y en modo `registered`, y se revoca rotándolo.
5. **Quien escanea queda en una «Mesa de llegada» compartida, que es sala de
   espera.** Una mesa y no N, y de ella **no se trabaja** hasta que se reparte.

## Lo que NO entra

- **Una pantalla de proyección a pantalla completa.** El QR va en el bloque de
  armado, a 240px, con el link en texto debajo. Agrandarlo es zoom del
  navegador.
- **Rate limiting de la ruta pública.** Rails 7.1 no trae uno (8.0 sí). Ver
  «Riesgos».
- **Recuperar clave.** Sigue sin existir, y la decisión 3 es justamente lo que
  evita necesitarla para esto.
- **Un QR por mesa o por tanda, con vencimiento y usos contados.** Era el
  enfoque de la tabla `workshop_invitations`, y se descartó por YAGNI: la
  auditoría que agregaría —quién llegó y cuándo— ya la dan
  `workshop_group_members.created_at` y `attended`. Si algún día hace falta más
  de un token por taller, esa tabla es el camino.
- **Marcar presente a alguien desde la sala.** La presencia se escribe desde el
  escaneo o desde el bloque de armado, que es donde se arman las mesas.

## El esquema: tres columnas

Las tres en inglés, como manda CLAUDE.md para todo lo nuevo.

### `workshops.attendance_mode`

Varchar, `NOT NULL`, default `'presumed'`, con CHECK en
(`presumed`, `registered`).

**El modo declara la semántica, no el gadget.** `registered` no dice «QR»: dice
que la presencia se registra en vez de presumirse. El QR es una forma de
registrarla y el toggle manual es la otra; el día que haya una tercera, el modo
no cambia. Llamarlo `qr` habría atado el nombre de la columna al mecanismo que
hoy la escribe.

Qué cambia con `registered`:

- Un asiento creado por convocatoria a mano nace **ausente**: está invitado, no
  llegó.
- El pool de idear de `Flow::Workshops::AssignGroups` deja de incluir a los
  `participant` de la empresa.

### `workshops.checkin_token`

Varchar, `NOT NULL`, UNIQUE, por `has_secure_token`.

**Separada del modo a propósito.** La tentación es derivar el modo del token
—«hay token, entonces hay QR»— y con una columna menos. No se hace: rotar el
token para revocar un link filtrado devolvería la asistencia a presumida **en
medio de la sesión**, y `AssignGroups` volvería a sentar a toda la empresa sin
que nadie lo pidiera. Son dos hechos distintos: cómo se establece la presencia, y
con qué credencial se entra.

Todo taller tiene token desde que nace, también en modo `presumed`. Un token
filtrado de un taller en modo presumido no abre nada, porque el modo es lo que
autoriza; y así no hace falta generarlo condicionalmente ni tolerar la columna
nula.

### `workshop_groups.arrival`

Boolean, `NOT NULL`, default `false`, con índice **UNIQUE parcial**
`(workshop_id) WHERE arrival`.

Una mesa de llegada por taller, y lo garantiza la base: dos personas que escanean
en el mismo segundo la crean a la vez, y el `find_or_create_by!` de la segunda
tiene que chocar contra el índice y no duplicarla. El servicio rescata
`RecordNotUnique` y vuelve a buscar, igual que `Convoke` ya hace con el UNIQUE
del asiento.

`workshop_group_members.attended` **no se toca**: el default sigue `true`. Lo que
cambia es que cada escritor dice lo que quiere en vez de heredarlo.

## Quién escribe la presencia

Cuatro escritores, los cuatro explícitos. Que el default de la columna siga
siendo `true` y que el modo del taller pueda querer lo contrario es exactamente
el caso en que heredar un default es una bomba: se dice en cada lugar.

| Escritor | Qué escribe | Por qué |
|---|---|---|
| `Flow::Workshops::Convoke` | `attended:` opcional, default `workshop.presumed_attendance?` | Convocar a mano en un taller con registro deja el asiento ausente: está invitado, no llegó. |
| `AssignGroups#seat!` | `attended: true` explícito | Hoy hereda el default y acierta por casualidad. Sólo siembra a quien venía de `seated_present_ids`, o sea presente: lo afirma. |
| `Flow::Workshops::CheckIn` | `attended: true` | Es el escaneo. |
| `WorkshopAttendancesController#update` | lo que pide el control | El toggle. Único escritor de presencia en un taller en modo presumido. |

`Convoke` gana un parámetro y ninguna rama: `attended: @attended` donde
`@attended` se resolvió en el `initialize` con el default. El servicio no
pregunta por el modo en dos lugares.

## El pool de idear cambia con el modo

`AssignGroups#groups_by_person`:

```ruby
ids = if @workshop.registered_attendance?
        seated_present_ids
      else
        (participant_ids | seated_present_ids) - absent_ids
      end
```

Sin esto **el escaneo es decorativo para idear**: `participant_ids` son todos los
`participant` de la empresa, así que el reparto sienta igual a quien no vino y da
lo mismo haber escaneado. Es el mismo defecto que el handoff anterior documentó
para el taller sin fase: caer en una rama que sienta a gente que nadie convocó.

En la rama `registered` no hace falta restar `absent_ids`: `seated_present_ids`
sale de `WorkshopGroupMember.presentes` y una persona tiene un solo asiento por
taller (UNIQUE `(workshop_id, user_id)`), así que no puede estar en las dos
listas.

## La mesa de llegada: cuatro puertas, no una

La mesa es **la unidad de visibilidad**. `WorkshopGroup#workable_ideas` es la
unión sobre sus integrantes, y `WorkshopIdeasController#create` escribe
`idea_contributors` **para toda la mesa** desde el minuto cero —es lo que hace
que «veo las ideas de mi mesa» sea `IdeaPolicy::Scope` tal como está, sin una
excepción nueva—.

O sea que una mesa de llegada de treinta personas, dejada como mesa normal, tiene
dos consecuencias de distinto peso: las treinta leen y proponen sobre las ideas
de las otras (reversible: se reparte y se termina), y **el primer borrador que
alguien cree ahí nace con treinta contribuyentes escritos** (no reversible:
repartir no los borra, y `IdeaContributor` alimenta `IdeaPolicy::Scope` y los
racimos de `AssignGroups` para siempre).

Por eso la mesa de llegada es sala de espera. Y cerrarla son **cuatro** lugares,
porque cada sala tiene lectura y escritura:

| | Idear | Evolución |
|---|---|---|
| **Lectura** | `_sala_idear`: rama `elsif group.arrival?` con su mensaje | `WorkshopGroup#workable_ideas` devuelve `Idea.none` |
| **Escritura** | `WorkshopIdeasController#create` rechaza | `WorkshopProposalsController#create` rechaza |

Las cuatro preguntan **lo mismo** (`group.arrival?`) para que no puedan divergir,
que es la forma que ya fijó `_criterios_editor.html.haml` con su variable única.
Y hay un ejemplo de request por celda: es la misma lección que el handoff
anterior dejó escrita —un defecto sobrevivió seis revisiones porque ningún test
ejecutaba esa rama—.

En evolución el rechazo del controller es explícito aunque `workable_ideas`
devuelva `none` y el `find_by!` ya dé 404: un 404 sin mensaje en una sala que
debería decir «tu mesa todavía no se armó» es el control que no responde que
este repo persigue.

**En modo individual no hay mesa de llegada.** `Convoke#own_group` ya arma la
mesa de una persona, que es el diseño de ese modo: una mesa es una persona.

### La trampa de `seat!`

`AssignGroups#seat!` reusa las mesas existentes por `created_at`, y la de llegada
es la primera creada: sin tocar nada se convertiría en «Mesa 1» **conservando
`arrival: true` y su nombre**, y la sala de la mesa 1 quedaría muda para
siempre. `seat!` la excluye de las reusables; el barrido de vacías que ya existe
la borra cuando se queda sin nadie.

## La ruta pública

Es la primera de la app. Todo lo demás cuelga de `require_authentication` +
`require_company` + `verify_pundit_usage`.

```ruby
get  "checkin/:token", to: "workshop_checkins#show", as: :checkin
post "checkin/:token", to: "workshop_checkins#create"
```

Al tope, al lado de `login`: no cuelga de `workshops` porque quien la abre
todavía no puede ver ningún taller.

`WorkshopCheckinsController` saltea `require_authentication` y `require_company`,
y se suma al `skip_pundit?` de `ApplicationController` con su razón: no hay
membresía con la cual autorizar todavía, que es lo mismo que ya vale para
`SessionsController`.

Layout `auth`: sin bundle de JS, viewport móvil y flash ya resueltos. La pantalla
se abre en un teléfono con la red del lugar, así que no carga nada que no
necesite.

### El tenant sale del token

```ruby
@workshop = Flow::Tenant.bypass! { Workshop.find_by(checkin_token: params[:token]) }
raise ActiveRecord::RecordNotFound if @workshop.nil?
Current.company = @workshop.company
```

`Workshop` es `TenantScoped`, así que sin el bypass la consulta revienta con
`MissingTenant` antes de encontrar nada. La excepción se declara en
`spec/lint/tenant_bypass_spec.rb` con su razón escrita, al lado de la que ya
tiene `sessions_controller.rb` —que está por lo mismo: el tenant todavía no
existe—.

Dos cosas verificadas para no suponerlas:

- El layout `application` envuelve **todo** lo que lee la sesión en `signed_in?`,
  así que el 404 de `render_not_found` renderiza sin sesión. `desafio_del_shell`
  devuelve `nil` sin tenant, que ya está documentado.
- `TenantScoped` llena `company_id ||= Current.company_id` en el
  `before_validation`, así que la membresía nueva nace en la empresa del taller
  sin pasárselo, y `tenant_matches_current` la deja pasar.

### Los estados del GET

El GET **nunca muta**: un prefetch del navegador o del chat por donde viaja el
link no puede sentar a nadie. Siempre renderiza, y el botón POSTea.

| Caso | Respuesta |
|---|---|
| Token desconocido | **404** |
| Token válido, taller `draft` o `closed` | Pantalla con el motivo, 200 |
| Token válido, modo `presumed` | Pantalla con el motivo, 200 |
| Token válido, taller `open` y modo `registered` | El formulario |

Los 200 no son un oráculo de existencia: quien tiene el token ya sabe que el
taller existe, así que decirle por qué no puede entrar no le confirma nada que no
supiera. El 404 del token desconocido sí es la regla de siempre.

Y son 200 y no 409 también por una razón de verificación: `make screens` falla
con cualquier HTTP >= 400 que no esté declarado, y la pantalla renderizó bien.

### El POST: un formulario, sin oráculo de cuentas

Email, nombre y clave. Un solo endpoint y un solo formulario para las tres
situaciones.

1. **Con sesión viva** se ignora el formulario y entra `current_user`. Sirve para
   quien ya es de la empresa y escanea igual, y para quien es de otra empresa: el
   token autoriza la membresía nueva.
2. **Email que ya existe** → `user.authenticate(password)`. Si falla, 422 con **el
   mismo mensaje genérico** que el login: no se distingue «cuenta existente con
   clave mala» de «cuenta nueva». Es lo que hace que el formulario único no sea un
   oráculo de cuentas.
3. **Email nuevo** → `User` + `Identity(provider: PASSWORD, uid: email)`, igual
   que el seed. El nombre se usa acá y se ignora en el caso 2: la cuenta ya tiene
   el suyo.

Después, en los tres casos:

- **Membresía:** `find_or_create_by!(user_id:)` con el rol **sólo en el bloque de
  creación**. Con `role: "participant"` en el `where`, un admin existente no se
  encontraría, el `create` chocaría contra el UNIQUE `(user_id, company_id)` y en
  el mejor de los casos le bajaría el rol a quien lleva el taller por escanear su
  propio QR.
- **Sesión y cookie.** Las tres banderas (`permanent`, `httponly`,
  `same_site: :lax`) salen de `SessionsController#create` a un concern
  `Authentication#sign_in!(user, company:)` que usan los dos. Dos políticas de
  cookie que algún día divergen es peor que el refactor, y es el único lugar donde
  este diseño toca el login existente.
- **`Flow::Workshops::CheckIn`**, que sienta y marca presente.
- **Redirect a `workshop_path(@workshop)`.** Ahí la pantalla ya funciona:
  `WorkshopPolicy::Scope` deja ver el taller a quien está en una mesa, y la
  persona acaba de quedar en una. Cae en la sala con el mensaje de la mesa de
  llegada, que es exactamente lo que tiene que leer: llegó, está dentro, y espera
  el reparto.

El GET que renderiza el formulario es además lo que hace que el CSRF funcione en
una ruta pública: el token viaja con el formulario servido, y la cookie de sesión
de Rails se establece en ese mismo GET. Un POST directo al link, sin pasar por la
pantalla, no tiene con qué.

### `Flow::Workshops::CheckIn`

Un servicio con la forma de los otros cinco (`Result = Data.define(:ok, :member,
:errors)`), y las guardas repetidas aunque el controller ya preguntó: es el
patrón de `AssignGroups`, y lo que las hace valer es que el servicio es el que
escribe.

- Rechaza si el taller no está `open` o el modo no es `registered`.
- **Si ya tiene asiento en el taller, lo marca presente y NO lo mueve de mesa.**
  Alguien que escanea dos veces, o que ya estaba convocado a la mesa 3, no
  termina en la llegada.
- Si no tiene: modo por mesas → `Convoke` contra la mesa de llegada
  (`find_or_create_by!(arrival: true)`, nombre «Mesa de llegada», con el rescate
  de `RecordNotUnique`); modo individual → `Convoke` con `group: nil`, que arma
  su mesa.
- En los dos casos `Convoke` recibe `attended: true`, así que la presencia se
  escribe en el mismo `INSERT` y no en un `update` posterior.

Idempotente, que es lo que un link escaneado con los dedos fríos necesita.

## El QR y los controles de quien lleva el taller

La gema es `rqrcode` 2.2.0 —`as_svg`, Ruby puro, sin red— y se verificó que baja
en el contenedor antes de elegirla. Agregar una gema es `make rebuild`.

SVG inline a 240px, con el link **en texto debajo**: la cámara falla, el lugar
tiene mala luz, y alguien va a querer tipearlo. Nada de JS y nada que le pida un
PNG a un tercero.

Vive en el bloque de armado, detrás del `can_assemble` que `show.html.haml` ya
calcula una vez y pasa por la cadena. Tres acciones member en
`WorkshopsController`, al lado de `open` y `close`, las tres con
`authorize @workshop, :update?`:

| Acción | Qué hace |
|---|---|
| `enable_checkin` | `attendance_mode = "registered"` |
| `disable_checkin` | `attendance_mode = "presumed"` |
| `rotate_checkin_token` | `regenerate_checkin_token`, con `turbo_confirm`: el QR anterior deja de servir |

No van por `workshops#update`, que es sólo de borrador (`reject_not_draft`):
activar el check-in **tiene** que poder hacerse con el taller abierto, que es
cuando la gente está llegando.

**Cambiar el modo no reescribe la asistencia ya registrada.** Quien fue convocado
a mano antes de activar el QR sigue presente sin haber escaneado. Reescribirlo
sería destruir dato por un cambio de configuración; para eso está el toggle. Y
apagarlo devuelve el pool de idear a toda la empresa: la pantalla lo dice donde
está el botón, no en una nota al pie.

## El toggle manual: el punto 1 del handoff anterior

```ruby
patch :attendance, to: "workshop_attendances#update"
```

Mismo patrón que `convoke` y `dismiss`, que también son acciones member del
taller delegadas a un controller propio. Recibe `user_id` y el valor.

Un `button_to` por integrante en `_groups`, detrás del `can_edit` que ya está
calculado. **Hermano del formulario de convocar y no adentro**: un `button_to`
es un `<form>`, uno dentro de otro es HTML inválido y el navegador aplana el
interno —pasó en la pantalla del corte, y no se ve en el DOM porque el parser ya
lo resolvió—.

Con el taller cerrado no se toca nada, igual que convocar y desconvocar
(`reject_closed`).

Es el único escritor de presencia para un taller en modo presumido, y el que
cubre a quien vino sin teléfono.

## Seed y capturas

Un **cuarto taller**, `attendance_mode: "registered"` y abierto, sobre
`taller-idear` —un desafío que ya existe sólo para capturas—, y **sin nadie
sentado**: así la captura muestra el estado vacío de la llegada, que es el que
ve quien proyecta el QR antes de que llegue nadie.

Sobre el mismo desafío y no uno nuevo: dos talleres pueden vincular el mismo
desafío (`WorkshopChallenge` es único por taller) y apuntan al mismo
`challenge_step`, pero las mesas son de cada taller. El acoplamiento es de una
sola dirección —el nuevo lee el paso, escribe sólo sus propias mesas— y evita
sembrar un desafío más.

Dos capturas:

- **`29-taller-checkin`**: el bloque de armado con el QR, como admin.
- **`30-checkin-publico`**: la pantalla pública sin sesión, y el registro
  completo.

**Sin sesión es `salir()`, NO un `browser.newContext()`.** El recorrido ya tiene
ese helper y lo usa para las tres capturas que piden otra sesión. Un contexto
nuevo traería una `page` nueva **sin los listeners de `pageerror` y de
`response`**, que se registran una sola vez sobre la `page` del recorrido: la
captura quedaría ciega justo a lo que `make screens` existe para cazar —un error
de JS y cualquier HTTP >= 400—, y daría verde igual. Es la misma clase de guarda
que mide cero y no se distingue de una que funciona.

El link se **lee de la pantalla de admin** (la captura 29), que es para lo que el
diseño lo pone en texto debajo del QR: el token es aleatorio por siembra, así que
no se puede escribir en el script. Y ahí el `goto` es correcto —no hay link que
seguir, y la pantalla pública no monta ninguna isla ni carga el bundle de JS, que
es lo que la regla de «navegá por link» protege—.

La captura del registro usa un email **fijo**, `llegada@taller.example`, y es
idempotente por diseño: la primera corrida crea la cuenta, las siguientes
autentican con la misma clave y el check-in sólo re-marca presente. Es la misma
propiedad que hace que el formulario único no sea un oráculo, usada acá para que
el recorrido no se rompa en la segunda corrida.

`.example` y no `.test`: `Flow::Demo` identifica lo sembrado por el sufijo
`.test`, así que una cuenta `@demo.test` creada por el recorrido aparecería en la
lista de cuentas de la pantalla de login y cambiaría esa captura. Las dos son
reservadas por RFC 2606.

Y el taller nuevo existe **sólo** para estas capturas, que es la regla que
CLAUDE.md fija después de que compartir `onboarding-remoto` con pruebas manuales
rompiera la corrida dos veces.

## Specs

| Archivo | Qué fija |
|---|---|
| `spec/lib/flow/workshops/check_in_spec.rb` | Idempotencia; no mueve de mesa a quien ya tiene; la llegada es una sola; individual no usa llegada; rechazo por modo y por estado |
| `spec/requests/workshop_checkin_spec.rb` | **Sin sesión**: 404 del token desconocido; el motivo del taller cerrado y del modo apagado; el registro completo (user, identity, membresía, asiento presente, sesión); email existente con clave buena; clave mala con mensaje genérico que **no** revela que el email existe; no le baja el rol a un admin |
| `spec/requests/workshop_arrival_spec.rb` | Las cuatro celdas de la mesa de llegada |
| `spec/lib/flow/workshops/assign_groups_spec.rb` | El pool en modo registrado; la llegada no se reusa como «Mesa 1» y se borra vacía |
| `spec/models/workshop_spec.rb` | Los dos modos, el token único, `registered_attendance?` |
| `spec/requests/workshop_checkin_settings_spec.rb` | Activar, apagar y rotar detrás de `update?`; rotar invalida el link anterior |
| `spec/requests/workshop_attendances_spec.rb` | El toggle detrás de `manage_groups?`; cerrado no toca nada |
| `spec/lint/tenant_bypass_spec.rb` | La entrada nueva en `ALLOWED`, con su razón |

De cada ejemplo hay que preguntar **qué tendría que romperse para que se ponga
rojo**, no sólo correrlo mutado: es la lección que el handoff anterior dejó con
cinco tests que no podían fallar, dos de ellos escritos por quien revisaba.

## Riesgos, declarados y no tapados

- **Una ruta pública que crea cuentas, sin rate limit.** Rails 7.1 no trae
  limitador (8.0 sí) y no se agrega uno acá. Lo que lo acota: el token sirve sólo
  con el taller `open` y en modo `registered`, las dos cosas son ventanas cortas
  que alguien abre a propósito, y rotar el token corta el acceso. Queda escrito
  como riesgo asumido.
- **Una foto del QR compartida afuera crea cuentas `participant` en la empresa**,
  que ven los desafíos y las ideas en las que participan. Es el precio de la
  decisión 4, y la alternativa —dominios de email permitidos— está descrita en
  «Lo que NO entra» por si cambia.
- **La pantalla es un oráculo de existencia por el RESULTADO, no por el texto, y
  con el QR se pueden pre-registrar cuentas con emails ajenos.** Lo encontró la
  revisión de la ruta pública, y se decidió dejarlo declarado el 2026-10-01.
  Con el token en la mano, un email que no es propio más una clave inventada da
  422 si la cuenta ya existe y «cuenta creada y adentro» si no: el mensaje es el
  mismo en los dos casos, pero el desenlace no, así que distingue qué emails
  tienen cuenta. Y de paso deja sentar a alguien bajo el correo de otra persona.
  Es **inherente al formulario único que además registra** —la decisión 3 más la
  4—: hacerlo indistinguible exigiría confirmar por correo antes de entrar, que
  es otro subsistema y mata el caso de uso de entrar caminando a un taller. Lo
  acota lo mismo que acota el abuso: el token sirve sólo con el taller `open` y
  el modo `registered`, y se rota. Las dos salidas, si algún día deja de
  alcanzar, son los dominios de email permitidos o pedir confirmación **sólo**
  cuando el email no existe.
- **El token es una URL-capacidad y viaja en el PATH, así que queda escrito
  donde una clave nunca queda.** Los parámetros se filtran —`:passw` y `:token`
  están los dos en `config.filter_parameters`, así que la clave que se tipea en
  esta pantalla no toca ningún log— y un segmento de la ruta no se filtra: el
  token entra entero en el `Started POST "/checkin/…"` del log y queda en el
  historial del navegador de quien escaneó, de donde lo lee cualquiera que
  llegue a esos dos lugares.
  Tampoco expira: la única revocación es rotarlo, y es a mano. Lo acota lo mismo
  que acota los otros dos —el taller `open`, el modo `registered`, dos ventanas
  cortas que alguien abre a propósito— y que la pantalla pública no tiene un
  solo link hacia afuera, así que no hay `Referer` que se lo lleve a un
  tercero. Las salidas, si deja de alcanzar: un vencimiento por tiempo sobre el
  token, o rotarlo al ABRIR el taller, para que lo que quedó escrito no sirva en
  la sesión siguiente.
- **El modo se puede apagar con gente ya marcada presente**, y el pool de idear
  cambia de significado en ese momento. No se reescribe nada; la pantalla lo
  avisa donde está el botón.
