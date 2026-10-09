# Handoff — entrar a una mesa (quien administra trabaja sin estar sentado), 2026-10-08

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

Cinco tareas por subagentes, con revisión y loop de arreglos cada una. La quinta
—esta— es sólo documentación.

## 2. Estado actual

**NO mergeada, NO pusheada.** Rama `entrar-a-una-mesa` sobre `master` (`d8be50f`).

- `make spec`: **1812 ejemplos, 0 fallas** (baseline de la rama: 1770).
- `make screens` (tras `make seed` y `make yarn-build`, en la Tarea 4): verde,
  «Sin errores de JS ni respuestas >= 400», con las once cifras y los dos pisos
  exactos en su valor:
  `[RITMO] 40 de 76 · [RELLENO] 299 · [PASTILLA] 790 · [CRITERIO] 195 · [LIVE] 1 · [RIEL] 71 · [BANDA] 71 · [SOMBRA] 302 · [CAMPO] 289 · [DRAFT] 2 · [GRABAR] 2`
- Commits (del más nuevo al más viejo):

```
361319a El «Entrar» se calcula una vez fuera del loop de mesas y se alinea a la izquierda, con el «Convocar»
047b912 La lista de mesas del taller ofrece «Entrar» por mesa y por vínculo trabajable, sólo para quien administra ese desafío
5cb469b Los cuatro caminos de escritura de la sala actúan sobre la mesa nombrada, y el audio deja de abrirse por taller
9a5e580 La cara de evolución de la sala tiene testigo propio, y la frase de la llegada ya no pone en minúscula el nombre
2a4bcab Corrijo los conteos de ejemplos del plan: eran 6 y no 7, y arrastraban
590be50 El aviso de mesa ajena deja el sufijo _html como único mecanismo de escape
d4dd45c La sala resuelve la mesa sobre la que se actúa, y los títulos dejan de decir «tu mesa» cuando es ajena
13ac246 La mesa sobre la que se actúa es una pregunta nueva, con un solo lugar donde vive
c01f891 El plan de entrar a una mesa: nueve hechos medidos del repo antes de escribirlo
eb62105 La spec de entrar a una mesa: una pregunta nueva y no una segunda fuente
```

**Lo que hay que leer antes de mergear:** §5.1. La feature está entera del lado
del servidor y **le falta la mitad del cliente**: ningún formulario ni ningún
`fetch` manda el parámetro `mesa`, así que desde un navegador quien administra y
no está sentado **lee** una mesa ajena y **no puede escribirla**. Lo encontré
midiendo en la Tarea 5 y está escrito en `CLAUDE.md`.

## 3. Archivos y cambios

21 archivos, +2.169/−21 (la mayoría specs y los dos documentos del plan).

| Pieza | Dónde |
|---|---|
| El permiso: `ChallengePolicy#enter_any_group?` (= `administers?(record)`), predicado propio y no `builder?`/`curate_pool?` | `app/policies/challenge_policy.rb` |
| La mesa por id, segura por el scope **y** por el tipo `uuid`: `Workshop#group_named` | `app/models/workshop.rb` |
| La pregunta nueva, UNA vez: `acting_group(workshop, link)` = `own_group \|\| named_group`, con `own_group` memoizado | `app/controllers/concerns/acts_on_a_group.rb` |
| Los cinco consumidores: el GET de la sala (`@group`, `@mesa_propia`) y los cuatro que escriben | `workshop_rooms_controller.rb`, `workshop_ideas_controller.rb`, `workshop_proposals_controller.rb`, `workshop_drafts_controller.rb`, `workshop_recordings_controller.rb` |
| El audio: `alcanzables` pasa de `policy(@workshop).update?` (por TALLER) a `policy(@link.challenge).enter_any_group?` (por DESAFÍO) | `workshop_recordings_controller.rb` |
| Los textos: `de_la_mesa` (una variable por archivo) y el local `mesa_propia` con default `true` | `workshop_rooms/_ideation`, `_evolution`, `_referencia`, `show`, `workshops/_my_group` |
| El aviso de mesa ajena, escapado por el sufijo `_html` de la clave | `workshop_rooms/_aviso_mesa_ajena.html.haml`, `config/locales/es.yml` |
| El «Entrar» por mesa y por vínculo trabajable, `link_to` (no `button_to`: hay un form alrededor) | `app/views/workshops/_groups.html.haml` |
| Specs | `spec/models/workshop_acting_group_spec.rb` (6), `spec/requests/entrar_a_una_mesa_spec.rb` (18), `spec/requests/escribir_en_una_mesa_ajena_spec.rb` (18) |
| Los documentos (Tarea 5) | `CLAUDE.md`, este archivo |

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
- `||` invertido (`named_group(...) || own_group(...)`): cae **UNO**, siempre el
  mismo, el del asiento propio. Ver §5.2: es el único testigo que tiene.

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
  asiento **de rebote** y no por precedencia: con el `||` invertido el ejemplo
  pasa igual. Hizo falta un admin **sentado**, que es lo único que mide el orden
  del `||`.
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

### Lo que quedó parkeado a propósito

- **El setup de grabación duplicado** en `spec/requests/escribir_en_una_mesa_ajena_spec.rb`:
  dos veces las mismas seis líneas. Es setup de test y no un bloque de lógica, y
  son dos ocurrencias; una ronda de arreglo por eso cuesta más de lo que rinde.
- **El `include ActsOnAGroup` debajo de la constante `AUDIO_TYPES`** en
  `workshop_recordings_controller.rb`. Cosmético.
- **El ejemplo de «otra mesa de otro taller» no cruza empresas.** Esa mitad la
  cubre `spec/tenancy/`, y `group_named` queda excluida dos veces de todos modos.
- **El predicado `unless mesa_propia || group.nil?` repetido** en las dos caras de
  la sala. Son dos lugares que preguntan lo mismo, así que no pueden divergir;
  una variable de controller por dos usos es la abstracción prematura que el repo
  evita.
- **Un ejemplo del asiento propio por endpoint.** Es un mecanismo único en una
  línea del concern; cuatro ejemplos más no agregan. El costo de esa decisión
  está en §5.2 y escrito en `CLAUDE.md`.

## 5. Próximos pasos

1. **La mitad del cliente que falta, y es lo que decide si esto se mergea como
   está.** Los cuatro endpoints aceptan `mesa` en el cuerpo y
   `escribir_en_una_mesa_ajena_spec.rb` lo prueba con un bloque por endpoint,
   pero **lo manda a mano**. En la app, el único lugar que escribe el parámetro
   es el «Entrar» de `workshops/_groups`, y es un **GET**:

   ```bash
   grep -rn "mesa: group.id" app     # un solo hit: el link «Entrar»
   grep -rn "params\[:mesa\]" app    # dos hits, los dos en el concern
   ```

   Los dos `form_with` de la sala y los dos `fetch` del JS arman su URL con
   `workshop_sala_*_path(workshop, link)`, sin el parámetro, y no hay
   `default_url_options` que lo arrastre. O sea que hoy quien administra y **no**
   está sentado entra, lee la mesa ajena, y cada escritura cae a `own_group` →
   `nil` → 403 (borrador y grabación) o redirect con «no estás en ninguna de este
   taller» (ideas y propuestas): **un formulario que se dibuja y rebota**. Es un
   `hidden_field_tag :mesa` en los dos formularios y el parámetro en las dos URLs
   de `data-`, más un testigo que mire el HTML servido (los request specs no lo
   pueden ver: mandan el parámetro ellos). Es la misma mitad que
   `base_version_id` tuvo que cubrir con `spec/lint/sello_del_borrador_spec.rb`,
   y acá no hay ningún lint.
2. **«El asiento propio gana» tiene UN SOLO testigo y ninguna guarda del
   recorrido lo respalda.** Es el ejemplo de `entrar_a_una_mesa_spec.rb` con un
   admin **sentado** que nombra otra mesa. Los cuatro bloques de escritura
   seguirían verdes con el `||` invertido, y `[DRAFT]` y `[GRABAR]` tampoco lo
   cazarían, porque no mandan `mesa` y con el parámetro ausente el resultado es el
   mismo en cualquier orden. Si alguien borra ese ejemplo, la precedencia se queda
   sin nada.
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
7. **Y el efecto de borde de «el asiento propio gana»:** quien está sentado no
   puede entrar a otra mesa. Apretar «Entrar» en la Mesa 3 estando sentado en la
   Mesa 1 muestra la Mesa 1, sin decir por qué. Es deliberado —es lo que hace que
   nada cambie de comportamiento, el recorrido incluido— pero el «Entrar» se
   dibuja igual, así que para un admin sentado es un control que no hace lo que
   su rótulo promete. Esconderlo, o decirlo, es una decisión que nadie tomó.
