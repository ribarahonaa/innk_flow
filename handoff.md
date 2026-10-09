# Handoff — entrar a una mesa (quien administra trabaja sin estar sentado)

Escrito el 2026-10-08; la ronda final de la revisión de rama lo actualizó el
2026-10-09 (§4 y §6).

## 1. Objetivo

Quien administra un desafío puede **entrar a cualquier mesa** de un taller que
lo trabaja y trabajarla **como si fuera la suya**, sin ocupar un asiento.

El punto de partida era un estado documentado a propósito: la sala resolvía su
mesa siempre con `Workshop#group_of(current_user)`, así que quien administra
entraba y recibía «no estás en ninguna de este taller». Las otras dos mitades ya
funcionaban y eso acotó el alcance: la lista completa de mesas ya se veía detrás
de `can_assemble`, y el reparto ya **no** sienta a quien administra —entrar no
tiene que ocupar un asiento, porque ocuparlo cambia el tamaño de la mesa, entra
al reparto y mueve los racimos de evolución—.

La forma elegida: **una pregunta nueva, no una segunda fuente**. `group_of`
sigue significando «mi mesa»; al lado vive «sobre qué mesa estoy actuando», una
vez, en un concern.

Seis tareas por subagentes, con revisión y loop de arreglos cada una: la quinta
fue sólo documentación, y la sexta salió de medir en la quinta —el parámetro
`mesa` no lo mandaba ningún formulario—. Encima, la **ronda final de la revisión
de rama**, que arregló once hallazgos; uno de ellos cambia el comportamiento de
la feature y está en §4.

## 2. Estado actual

**NO mergeada, NO pusheada.** Rama `entrar-a-una-mesa` sobre `master` (`d8be50f`).

- `make spec`: **1821 ejemplos, 0 fallas** (baseline de la rama: 1770).
- `make screens` (tras `make seed` y `make yarn-build`): verde, «Sin errores de
  JS ni respuestas >= 400», con las once cifras y los tres pisos exactos en su
  valor: ver la línea literal en §6.
- Commits: `git log --oneline master..HEAD`. Van del más nuevo al más viejo y la
  lista no se copia acá, porque una lista de commits pegada a mano se queda
  corta en cuanto se suma uno —ya pasó, este mismo archivo terminaba en
  `361319a`—.

**Lo que hay que leer antes de mergear:** §4, el bloque de la ronda final. **La
precedencia de la mesa se invirtió** y es un cambio de comportamiento, no una
corrección de texto: gana la mesa NOMBRADA y el asiento propio quedó como
fallback de la entrada sin parámetro. Y la contradicción que se deja escrita y
no arreglada: **el seed sienta al admin**, que es una conveniencia de la siembra
y no el modelo del dominio.

## 3. Archivos y cambios

28 archivos, +3.044/−397 (la mayoría specs y los documentos del plan).

| Pieza | Dónde |
|---|---|
| El permiso: `ChallengePolicy#enter_any_group?` (= `administers?(record)`), predicado propio y no `builder?`/`curate_pool?` | `app/policies/challenge_policy.rb` |
| La mesa por id, segura por el scope **y** por el tipo `uuid`: `Workshop#group_named` | `app/models/workshop.rb` |
| La pregunta nueva, UNA vez: `acting_group(workshop, link)` = `named_group \|\| own_group` —la mesa nombrada gana, el asiento es el fallback—, con `own_group` memoizado | `app/controllers/concerns/acts_on_a_group.rb` |
| Los cinco consumidores: el GET de la sala (`@group`, `@mesa_propia`) y los cuatro que escriben | `workshop_rooms_controller.rb`, `workshop_ideas_controller.rb`, `workshop_proposals_controller.rb`, `workshop_drafts_controller.rb`, `workshop_recordings_controller.rb` |
| El audio: `alcanzables` pasa de `policy(@workshop).update?` (por TALLER) a `policy(@link.challenge).enter_any_group?` (por DESAFÍO) | `workshop_recordings_controller.rb` |
| Los textos: `de_la_mesa` (una variable por archivo) y el local `mesa_propia` con default `true` | `workshop_rooms/_ideation`, `_evolution`, `_referencia`, `show`, `workshops/_my_group` |
| El aviso de mesa ajena, escapado por el sufijo `_html` de la clave y **no** sobre la llegada (ahí los cuatro endpoints devuelven 403) | `workshop_rooms/_aviso_mesa_ajena.html.haml`, `config/locales/es.yml` |
| El «Entrar» por mesa y por vínculo trabajable, `link_to` (no `button_to`: hay un form alrededor); pregunta `rooms.workable`, la misma que el selector y el redirect, sobre la colección ya cargada | `app/views/workshops/_groups.html.haml`, con `rooms` bajando desde `show` por `_assembly` |
| El parámetro en la ESCRITURA: cinco helpers de ruta con `mesa: group&.id` (Tarea 6) | `workshop_rooms/_ideation`, `_evolution`, `_recording` |
| Specs | `spec/models/workshop_acting_group_spec.rb` (7), `spec/requests/entrar_a_una_mesa_spec.rb` (19), `spec/requests/escribir_en_una_mesa_ajena_spec.rb` (19), `spec/requests/la_mesa_viaja_en_la_escritura_spec.rb` (6) |
| Los documentos | `CLAUDE.md`, la spec de diseño y el plan (los dos con su nota fechada de la inversión), este archivo |

### Qué mutación puso en rojo a qué, por tarea

Lo que más cuesta reconstruir después. Los outputs crudos están pegados en
`.superpowers/sdd/2026-10-08-entrar-a-una-mesa/task-*-report.md`.

**Tarea 1 — el mecanismo (`13ac246`).** RED: 6 ejemplos, 6 fallas
(`NoMethodError` de `group_named` y `enter_any_group?`). GREEN: 6/0, suite 1776.
**Sin mutación propia, y ahí estuvo el hallazgo:** el reviewer notó que el
concern **no tenía ningún ejemplo** —se podía invertir el `||` de `acting_group`
o borrar el guard de permiso de `named_group` y los 6 seguían verdes—. Se plegó
a la Tarea 2 como enmienda.

**Tarea 2 — la sala (`d4dd45c`, `590be50`, `9a5e580`).** Dos mutaciones, y
fallan distinto a propósito:

- `@mesa_propia = true` fijo (el servidor miente diciendo que la mesa es propia):
  sobre los 13 ejemplos finales caen **7, repartidos 3 de idear y 4 de
  evolución** (títulos con el nombre, aviso de mesa ajena, rama de llegada; y en
  evolución título, rama de vacío, rama de llegada y aviso de base vieja).
  Quedan verdes los dos de `participant`, que es correcto: para ellos la mesa
  **es** la propia. En la primera entrega, con 8 ejemplos, caían 3 — todos de
  idear, porque evolución no tenía testigo (ver §4).
- `||` invertido: cae **UNO**, siempre el mismo, el de la precedencia. Ojo al
  leerlo hoy: en esa tarea el orden embarcado era `own_group || named_group` y la
  mutación era `named_group || own_group`, que es lo que la ronda final dejó como
  **el orden correcto** (§4). La lección sobrevive igual al cambio de signo: ese
  ejemplo es el único que mide el orden. Ver §5.2.

**Tarea 3 — los cuatro caminos de escritura (`5cb469b`).** Cinco mutaciones, y
**cada una puso rojo SÓLO el bloque de su propio endpoint**, que es lo que
prueba que los cuatro bloques son independientes y que la verificación por
endpoint no es una ilusión:

| Mutación | Rojo |
|---|---|
| ideas → `group_of(current_user)` | 2 (administra crea la idea; llegada nombrada) |
| proposals → `group_of(current_user)` | 2 (administra propone; llegada nombrada) |
| drafts → `group_of(current_user)` | 1 (administra escribe el borrador) |
| recordings `create` → `group_of(current_user)` | 1 (administra graba) |
| `alcanzables` → `policy(@workshop).update?` | 1 (el gestor ajeno baja el audio: 200 en vez de 404) |

En la corrida RED fallaban **7 de 18**, o sea que once ejemplos pasaban ya antes
del cambio. Se revisaron uno por uno y **ninguno es vacuo**: los dos de llegada
pasan en RED porque sin mesa nombrada el admin igual come 403, pero después del
cambio el único freno es `return head :forbidden if group.arrival?` y borrar esa
línea los pone rojos; los cuatro del gestor ajeno guardan el `enter_any_group?`
de `named_group`; los cuatro de `participant` son guardas de regresión que
comparan la FILA `workshop_group` y no títulos; y el GET 200 guarda que el 404
nuevo del audio no cierre de más.

**Tarea 4 — el «Entrar» (`047b912`, `361319a`).** Mutación
`enter_any_group?` → `true`: **1** rojo, el del gestor que administra uno de los
dos desafíos del taller y tiene que ver el «Entrar» de ese y no el del otro. Los
otros dos ejemplos negativos («no aparece en la llegada», «quien participa no ve
ninguno») pasan antes y después: el segundo prueba `can_assemble` —el partial
entero no se renderiza—, no el predicado. Son guardas de regresión y su nombre
lo dice.

## 4. Intentos fallidos y lo que se encontró midiendo

Todo esto salió de la ejecución y **no estaba en el plan**. Cuatro de los cinco
son defectos del plan mismo.

- **Un conteo de ejemplos del plan estaba mal, y el implementador NO lo tapó.**
  El brief de la Tarea 1 pedía 7 ejemplos y el spec que él mismo traía tenía 3 +
  3 = 6; la suite dio 1776 y no 1777. Lo reportó como diferencia en vez de
  inventar un ejemplo para que cuadrara, que es lo correcto. Corregido en el plan
  por `2a4bcab`. Es la quinta vez en este proyecto que un conteo de ejemplos del
  plan sale mal.
- **El ejemplo que el plan YA tenía para el asiento propio no discriminaba
  nada.** Era un `participant` sentado mandando el parámetro de otra mesa — y a
  esa persona `named_group` le devuelve `nil` **por permiso**, así que cae a su
  asiento **de rebote** y no por precedencia: pasa con el `||` en cualquier
  orden. Hizo falta un admin **sentado**, que es lo único que mide el orden del
  `||`.
- **El spec de la Tarea 2 no podía pasar como estaba escrito.** Sin ninguna idea
  sembrada en la mesa, la cara de idear dibuja el vacío («Ninguna idea en esta
  mesa todavía») y el título «Las ideas de …» **no existe**, así que los ejemplos
  fallaban por el motivo equivocado. Es la familia «un bloque que sólo se dibuja
  con datos se fotografía AUSENTE y da verde» que `CLAUDE.md` ya documenta. Se
  arregló sembrando una idea.
- **El XSS que se reportó NO existía, y el peligro real era el `.html_safe`.** El
  implementador avisó que el aviso interpolaba el nombre de la mesa crudo. Se
  midió: con la clave `foreign_group_html` el valor sale **ya escapado**, y un
  `ERB::Util.html_escape` explícito encima da una salida **byte por byte
  idéntica** (`==` → true), o sea que no había XSS ni doble escape. El control
  —la misma clave **sin** el sufijo más un `.html_safe`— sí da
  `<script>alert(1)</script>`. Conclusión invertida: lo que había que sacar era
  el `.html_safe`, que es un no-op hoy y un arma cargada el día que alguien
  renombre la clave. La línea quedó con el sufijo como único mecanismo.
- **La cara de evolución entera no tenía un solo testigo.** Los 8 ejemplos de la
  primera entrega usaban sólo el link de idear, y cuatro de las frases viven en
  `_evolution.html.haml`: podían volver a decir «tu mesa» sin que nada se
  pusiera rojo. Es el riesgo nº1 de la feature sin cubrir en la mitad de las
  frases, y era **plan-mandated** (el brief pedía siete ejemplos, todos de
  idear). La ronda de arreglo sumó 5 ejemplos y la mutación `@mesa_propia` pasó
  de 3 rojos a 7. El argumento es el mismo que el repo ya usa para `[DRAFT]` y
  `[GRABAR]`: las dos caras se miden POR SEPARADO porque un piso flojo no
  cazaría que una dejó de medirse.
- **Un cómputo invariante dentro de un loop, y el plan lo traía así.** `entrables`
  se calculaba **dentro** del `groups.each` y no depende de `group`: se
  recalculaba una vez por mesa, con un `select` que llama
  `policy(l.challenge).enter_any_group?` por vínculo. Para quien administra la
  empresa `manager?` corta antes y no consulta; **para un gestor
  `reaches_challenge?` hace `ChallengeGestor.exists?` sin memoización**, o sea
  mesas × vínculos llamadas. El query cache de Rails amortigua —la base ve ~1
  consulta por vínculo— pero sigue siendo trabajo de Ruby repetido y depende del
  caché. Es la familia que este repo ya pagó con el `newer_version_for` del
  builder. Movido arriba del loop (`361319a`), junto a `already_in_ids`,
  `can_edit` y `convocable`; el reviewer confirmó que fue **puro movimiento**.
- **El defecto de maquetación lo vio una persona abriendo la captura, no una
  guarda.** El «Entrar» salía alineado a la **derecha** dentro de la caja angosta
  del listado de integrantes (~280px), con los 24px de `.form-actions` arriba,
  mientras el «Convocar» de la misma mesa iba a la izquierda: dos controles de la
  misma mesa contra bordes opuestos. Se vio en `tmp/screenshots/25a-taller-salas.png`.
  Arreglado cambiando el wrapper por `.flex.flex-wrap.gap-2.mt-2` (utilidades
  puras, con `make yarn-build` después) — y ese wrapper es justamente **invisible**
  para `[CLASES]`, que mira una lista fija de familias.
- **Dos textos más mentían, y el grep del plan no los veía.** El plan contaba los
  «tu mesa» y `workshops/_my_group` tenía además «Estás en la mesa de llegada…» y
  «Trabajás sola o solo en este taller». **Medido en la Tarea 5: de esos dos sólo
  el segundo se le escapa al grep** —el primero termina en «acá aparece tu mesa»,
  así que `grep -rni "tu mesa"` sí lo encuentra—. Los dos se condicionaron a
  `mesa_propia`.
- **`String#capitalize` minusculiza el resto.** «Mesa A» → «Mesa a». Hoy sólo se
  alcanza con la llegada, cuyo nombre lo pone la app, pero el nombre de una mesa
  en general lo escribe una persona. Reemplazado por `sub(/\A./, &:upcase)`.
- **Y el hallazgo de la Tarea 5, que ninguna revisión de tarea podía ver porque
  mira un archivo a la vez: el parámetro `mesa` no lo manda nadie.** Ver §5.1.

### La ronda final de la revisión de rama

Once hallazgos —cinco Important y seis Minor—, y **cuatro de ellos eran
comentarios o documentación que afirmaban algo que el código no hacía**, que es
la familia que este repo paga más caro. Lo que cambió de verdad:

- **La precedencia se INVIRTIÓ** (`named_group || own_group`), y es el único
  cambio de comportamiento de la ronda. El dueño del producto aclaró el modelo:
  los únicos que se mueven entre mesas son quien administra y el gestor, y
  **nunca están participando en una**. O sea que para ellos no hay asiento
  propio que proteger, y la regla anterior existía para un caso que no ocurre
  —produciendo un control que no responde: estando sentado, «Entrar» en otra
  mesa navegaba, cambiaba la URL y dibujaba la propia con el título «tu mesa»,
  sin una palabra, y en el seed eso valía para TODO «Entrar» a otra mesa—. Cayó
  **un solo** ejemplo de los 1818, el que aseveraba lo contrario, y se reescribió
  en dos: uno por cada rama del `||`.
- **Dos «Tu mesa todavía no se armó» fijos en los CONTROLLERS**
  (`WorkshopIdeasController` y `WorkshopProposalsController`), alcanzables justo
  por el camino que la feature abrió. El censo de la spec no los vio porque contó
  «diez textos en cuatro VISTAS» y el grep de `CLAUDE.md` miraba `app/views`.
  Quedaron **neutros** («esa mesa»), que no puede mentir y es más barato que
  condicionar un redirect, y el grep pasó a `app/`. Los dos ejemplos que recorren
  ese texto aseveran la subcadena común («todavía no se armó»), así que **no se
  pusieron rojos**: el arreglo no tiene testigo nuevo.
- **El aviso de mesa ajena se dibujaba también sobre la mesa de LLEGADA**, donde
  los cuatro endpoints devuelven 403: prometía «lo que escribas queda a tu
  nombre» justo arriba de «… todavía no se armó». Se le sumó `|| group.arrival?`
  y la negativa se metió en los dos ejemplos de llegada que ya existían.
- **`entrables` era una segunda copia de «¿este vínculo es trabajable?»**, contra
  la advertencia escrita al lado en `_room_picker`, y además pagaba consultas ya
  hechas (`workshop.workshop_challenges` sin precarga en un render que ya tenía
  la colección). Hoy es `rooms.workable`, con `rooms` bajando de `show` por
  `_assembly`. La divergencia era inalcanzable hoy —`Open` sólo abre
  `WORKABLE_KINDS`— pero `workable?` no mira el `kind` y `workable` sí.
- **El locator de `goToRoom` quedó anclado al selector de salas.** Su comentario
  decía que lo que lo desempataba era «tener un Entrar, que es del selector y de
  nadie más», y desde `047b912` cada mesa tiene el suyo. Hoy no colisiona por
  casualidad (un vínculo trabajable por taller en el seed), y con dos salas
  `first()` habría tomado el de la mesa —el bloque de armado se renderiza antes—
  y la corrida habría seguido verde midiendo otra navegación.
- **`form[action*="/ideas"]` volvió a `*="/ideas?"`** (ídem proposals): el cambio
  era forzado por el query nuevo, pero aflojó el borde del segmento sin
  necesidad. Las otras dos rutas (`RUTA_DEL_AUTOGUARDADO`,
  `RUTA_DE_GRABACIONES`) ya estaban bien ancladas con `(\?.*)?$`.
- **Un ejemplo positivo del gestor**, que es el rol para el que la feature es
  menos obvia: estaba probado negativo cuatro veces (administrando OTRO desafío)
  y el positivo sólo con el admin. Ahora un gestor asignado a ESE desafío y sin
  asiento escribe el borrador sobre la mesa nombrada.
- **Dos textos de documentación que la rama volvió falsos.** El `grupo.nil?` de
  `alcanzables` se presentaba como defensivo-e-inalcanzable: con la guarda nueva
  —`enter_any_group?`, por desafío— un gestor del desafío B del mismo taller pasa
  `work?`, no pasa la guarda y no está sentado, así que cae ahí. Y «`[DRAFT]` y
  `[GRABAR]` no mandan `mesa`» es falso desde `2fb718a`: **lo mandan**, con el id
  del propio asiento, que es por lo que resuelve igual en cualquier orden.
- **«Un array castea a `nil`» era más de lo medido, y se midió de nuevo.** Ver
  §6.

### Lo que quedó parkeado a propósito

- **El setup de grabación duplicado** en `spec/requests/escribir_en_una_mesa_ajena_spec.rb`:
  dos veces las mismas seis líneas. Es setup de test y no un bloque de lógica, y
  son dos ocurrencias; una ronda de arreglo por eso cuesta más de lo que rinde.
- **El `include ActsOnAGroup` debajo de la constante `AUDIO_TYPES`** en
  `workshop_recordings_controller.rb`. Cosmético.
- **El ejemplo de «otra mesa de otro taller» no cruza empresas.** Esa mitad la
  cubre `spec/tenancy/`, y `group_named` queda excluida dos veces de todos modos.
- **El predicado `unless mesa_propia || group.nil? || group.arrival?` repetido**
  en las dos caras de la sala. Son dos lugares que preguntan lo mismo, así que no
  pueden divergir; una variable de controller por dos usos es la abstracción
  prematura que el repo evita.
- **Un ejemplo de la precedencia por endpoint.** Es un mecanismo único en una
  línea del concern; cuatro ejemplos más no agregan. El costo de esa decisión
  está en §5.2 y escrito en `CLAUDE.md`.

## 5. Próximos pasos

1. **(Resuelto) El parámetro `mesa` ahora viaja en la escritura.** Los cinco
   helpers de ruta de las vistas de la sala lo arman con `mesa: group&.id`, en el
   query de la URL de acción. Lo cuida
   `spec/requests/la_mesa_viaja_en_la_escritura_spec.rb`, que saca la URL del HTML
   servido y escribe contra ella. La lección que queda: los request specs que
   mandan `mesa` a mano (`escribir_en_una_mesa_ajena_spec.rb`) prueban el servidor
   y no la cadena, y estuvieron verdes con el defecto entero.
2. **La precedencia tiene DOS testigos y ninguna guarda del recorrido la
   respalda.** Son dos ejemplos de `entrar_a_una_mesa_spec.rb` con un admin
   **sentado**: nombrando otra mesa entra a la NOMBRADA, y sin nombrar ninguna
   cae a su asiento. Los cuatro bloques de escritura pasan con el `||` en
   cualquier orden, y `[DRAFT]`/`[GRABAR]` tampoco lo cazan — pero **no** porque
   no manden `mesa`: lo mandan, y es el id de su propio asiento, así que las dos
   ramas resuelven la misma fila. Si alguien borra esos dos ejemplos, la
   precedencia se queda sin nada.
3. **Nada mide el «Entrar» en el recorrido.** `[CLASES]` lo ve sólo por la familia
   `btn` y sólo saltaría si perdiera **toda** regla —imposible en la práctica:
   `btn`, `btn-ghost` y `btn-sm` ya existen por el «Convocar» de la misma mesa—, y
   el wrapper de utilidades le es invisible. Que el link esté, que lleve el `mesa=`
   correcto, el rótulo y el colapso a «Entrar» pelado los cubren los ejemplos de
   request; la maquetación, nadie.
4. **El selector de mesa dentro de la sala** se descartó para esta spec y se puede
   sumar encima de este mecanismo: hoy, para ver otra mesa hay que volver al
   taller. Deja la sala con dos modos y un control que hay que esconder para quien
   no administra.
5. **La atribución no alcanza como auditoría.** Cada fila dice quién actuó
   (`updated_by`, `recorded_by`, el autor de la `Idea`), pero **ninguna pantalla
   lista «lo que hizo quien administra desde afuera»**. Si eso hace falta, es otra
   feature.
6. **La carrera entre quien administra y la mesa tecleando el mismo borrador** es
   último-que-escribe-gana por diseño y el sello nombra a quien tecleó — pero
   ahora los dos pueden ser personas que no se ven entre sí, y a la mesa no se le
   avisa en vivo que alguien entró desde afuera (un push pediría el canal
   autenticado y scopeado por empresa que la spec de la lista de llegada ya
   descartó).
7. **El seed sienta al admin, y eso contradice el modelo del dominio.** Quien
   administra no participa de ninguna mesa; la siembra lo sienta igual porque
   `[DRAFT]` y `[GRABAR]` —piso EXACTO en 2— necesitan a alguien escribiendo
   desde una sala. **Queda así a propósito**: rehacerlo es rehacer parte del
   recorrido. Está anotado en `CLAUDE.md` para que nadie deduzca del admin
   sentado que los admins se sientan. Si algún día el seed usa un `participant`
   para esas dos guardas, ese asiento se puede sacar.
8. **Nadie escribe desde la sala estando sentado en OTRA mesa en el recorrido.**
   Con la precedencia invertida ése es ahora el camino central de la feature, y
   lo cubren sólo los request specs: el admin del recorrido manda el `mesa` de su
   propio asiento, así que `make screens` nunca ejercita el caso en un navegador.

## 6. Lo medido en la ronda final

**`make spec`: 1821 ejemplos, 0 fallas.** Son los 1818 de `2fb718a` más tres: el
positivo del gestor escribiendo el borrador, la segunda rama del `||` (sin
nombrar ninguna mesa cae al asiento) y el array con un id real en
`group_named`.

**`make screens`**, tras `make yarn-build` y `make seed`, verde y con 76
capturas. La línea de las once cifras, literal:

```
[RITMO] 40 de 76 pantallas tuvieron dos tarjetas que comparar · [RELLENO] 299 `card-body` medidos · [PASTILLA] 790 chips y avisos medidos · [CRITERIO] 195 nombres medidos · [LIVE] 1 pantalla(s) medida(s) · [RIEL] 71 pantallas con riel · [BANDA] 71 pantallas con banda · [SOMBRA] 302 tarjetas medidas · [CAMPO] 289 campos medidos · [DRAFT] 2 caras medidas · [GRABAR] 2 caras medidas
```

**Ojo con esas cifras: cuatro de ellas sólo valen sobre una siembra FRESCA.** La
revisión de rama daba por finales `[RELLENO] 302`, `[PASTILLA] 797`,
`[SOMBRA] 305` y `[CAMPO] 291`, y medidas con `make seed` inmediatamente antes
dan 299/790/302/289. El patrón ya está documentado en `CLAUDE.md` para
`[PASTILLA]`, que crece sola entre corridas porque el recorrido le pide cosas a
la IA y después fotografía `/admin/ai_runs`; y el recorrido además siembra a
Lucía Llegada, que el seed borra. O sea: **una corrida encadenada a otra sin
resembrar mide más que una limpia**, y las once cifras son pisos, no igualdades
—salvo `[BANDA]`, `[DRAFT]` y `[GRABAR]`, que son exactas—.

**La mutación de la precedencia.** `named_group || own_group` vuelto a
`own_group || named_group`: cae **un** ejemplo, «quien administra y está sentado
/ nombrando otra mesa entra a la NOMBRADA, aunque tenga asiento», con
`expected … to include "Las ideas de Mesa del fondo"`. Y la de al lado, que es
la que prueba que el segundo ejemplo no es vacuo: borrando el fallback
(`acting_group` = `named_group` a secas) caen **cuatro**, y uno de ellos es «sin
nombrar ninguna cae a su asiento». Dos mutaciones, dos conjuntos distintos de
rojos: cada ejemplo mide su propia rama del `||`.

**`?mesa[]=<uuid real>` resuelve la mesa, y «un array castea a `nil`» era más de
lo medido.** Medido el 2026-10-09 en `app_test`: `find_by(id: [...])` no pasa el
valor entero por `cast`, arma un `IN` y castea cada elemento. Un array con un id
real no es `blank?` y **resuelve**; uno con basura cae a `nil` (`IN (NULL)`); uno
vacío es `blank?`. Un hash (`?mesa[a]=1`), una cadena basura, un no-entero, `""`
y `nil` castean los cinco a `nil`. **No es un problema de seguridad** —resuelve
la misma mesa que el parámetro plano, con el mismo filtro por taller y por
empresa— pero la frase afirmaba más de lo que alguien había medido. Hay un
ejemplo nuevo en `spec/models/workshop_acting_group_spec.rb` que lo fija.
