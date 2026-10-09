# Entrar a una mesa: quien administra trabaja sin estar sentado

## El problema

Quien administra un taller **ve** las mesas y **no puede entrar a ninguna**.

Las dos primeras mitades de eso ya funcionan, y conviene decirlo porque acota el
alcance: la lista completa de mesas se dibuja detrás de `can_assemble`
(`workshops/show.html.haml:6`, que es `policy(@workshop).update?`), y el reparto
**no** sienta a quien administra —el pool es `participant_ids |
seated_present_ids`, o sea `participant`s y gente convocada a mano—. Eso último
es deseado y no se toca: entrar no tiene que ocupar un asiento.

Lo que falta es la tercera, y hoy es un estado **documentado a propósito**.
`workshop_rooms_controller.rb:15` dice textual: «(`administers_any?`): entra, y
la cara le dice que no tiene mesa.» La sala resuelve su mesa siempre con
`group_of(current_user)`, así que quien administra entra y recibe «Sólo se
propone desde una mesa: no estás en ninguna de este taller».

## Alcance

Quien administra **trabaja la mesa como si fuera la suya**, sin sentarse: teclea
el borrador, propone cambios, graba, manda, y lee todo lo que esa mesa produjo.

Con **una excepción que no se abre**, y es la del gestor con las ideas. Se
explica abajo, en «Las dos reglas que no se tocan».

Lo que esto **no** es: no es un modo de sólo lectura, ni una vista de
supervisión, ni una pantalla nueva. Es la sala que ya existe, resolviendo otra
mesa.

## Lo que se midió antes de diseñar

| Pregunta | Respuesta medida |
|---|---|
| ¿Se ven las mesas hoy? | **sí**, detrás de `can_assemble` |
| ¿El reparto sienta a quien administra? | **no**: el pool es `participant_ids \| seated_present_ids` |
| ¿Se puede entrar a una mesa hoy? | **no**, y está documentado como intencional |
| ¿Cuántos lugares resuelven «mi mesa»? | **7**, en cinco controllers más la pantalla del taller |
| ¿Cuántos textos dicen «tu mesa»? | **10**, en cuatro vistas |
| ¿`administers_any?` sirve de permiso? | **no**: es «administra ALGUNO», y la sala ya gatea el brief por desafío |
| ¿El usuario del recorrido está sentado? | **sí**, el seed lo sienta explícito (`seeds.rb:857`, `:888`) |

**Las líneas que esta spec cita son una foto de hoy.** Se verificaron una por
una al escribirla, y se corren con la primera edición de esos archivos. La forma
grepeable es la autoridad:

```bash
grep -rn "group_of(current_user)" app     # los siete llamadores
grep -rni "tu mesa" app/views            # los diez textos
```

## La forma: una pregunta nueva, no una segunda fuente

### Lo que se descartó, y por qué

- **Que entrar siente a quien administra.** Resolvería todo sin tocar nada —el
  resto de la app ya funciona para alguien sentado— y está descartado por el
  pedido mismo: ocupar un asiento cambia el tamaño de la mesa, entra al reparto,
  aparece en «quién está sentado» y le mueve los racimos a evolución. Entrar a
  mirar no puede tener ese efecto.
- **Cambiar `group_of` para que acepte un parámetro.** Es la tentación obvia y
  es la peor: hay 7 llamadores y dos de ellos preguntan legítimamente por la
  mesa PROPIA (el panel «Mi mesa» del taller, y la lectura de grabaciones
  alcanzables). Un solo método con dos significados es cómo se abren las fugas
  que este repo ya documenta.
- **Una pantalla nueva de supervisión.** Duplicaría las dos caras de la sala con
  su borrador, sus propuestas, sus grabaciones y sus transcripciones. Dos copias
  del mismo markup divergen y nadie se entera — la razón por la que
  `workshops/_my_group` es UN partial para dos lugares.
- **Un selector de mesa dentro de la sala.** Cómodo para recorrer varias
  seguidas, y deja la sala con dos modos y un control que hay que esconder para
  quien no administra. Si hace falta, se suma después sobre este mecanismo.

### `acting_group_for`

`Workshop#group_of(user)` se queda tal cual y sigue significando **«mi mesa»**.
Al lado aparece un hermano que contesta otra pregunta: **«sobre qué mesa estoy
actuando»**.

```ruby
# El asiento propio si lo hay; si no, y sólo si administra ESE desafío, la mesa
# que nombra el parámetro; si no, nil.
def acting_group_for(user, group_id:, challenge:)
```

Un solo lugar decide y los llamadores lo consultan. Es la lección de `arrival?`,
que vive en una lista enumerada y no en un número repetido: una pregunta escrita
en cinco lugares es una que el día que cambie miente en cuatro.

**El asiento propio gana siempre.** No es un detalle de implementación: es lo
que hace que nada de lo que ya funciona cambie de comportamiento, incluido el
recorrido, cuyo admin está sentado a propósito en el seed.

### Lo que hace seguro al parámetro, y son tres cosas

1. **La búsqueda cuelga de `workshop_groups`** del taller, que ya filtra por
   taller y —vía `TenantScoped`— por empresa. Una mesa de otro taller o de otra
   empresa queda excluida **dos veces, independientemente**.
2. **La columna es `uuid`**, así que basura, un no-entero, un array o la clave
   ausente castean a `nil` antes del SQL. Es el mismo par de propiedades que
   `CLAUDE.md` documenta como portante para `base_version_id`, el otro lugar
   donde un dato del navegador entra a una columna con FK.
3. **Para quien no administra el parámetro se IGNORA, no se rechaza.** Cae a su
   propio asiento. Rechazar con 403 confirmaría que esa mesa existe, que es el
   oráculo de existencia que este repo persigue en todas partes.

### El permiso es por DESAFÍO, no por taller

`administers?(@link.challenge)` —`manager? || (gestor? && le asignaron ESE
desafío)`— y **no** `administers_any?`.

Medido: `WorkshopPolicy#work?` y `#update?` usan `administers_any?`, que es
«administra alguno del taller». Y la sala **ya** gatea el brief, el link y el
módulo del desafío detrás de `policy(link.challenge).show?`, precisamente porque
un gestor puede entrar a una sala cuyo desafío le devuelve **404**. Dejarlo
*escribir* ahí con `administers_any?` sería abrir escritura sobre algo que no
puede ni leer.

## Las dos reglas que no se tocan

`IdeaPolicy` excluye al gestor de dos cosas, con el motivo escrito:

- `create? = membership.present? && !membership.gestor?` — «el gestor no:
  acompaña la evolución de las ideas de otros, y proponer las propias lo pondría
  a guiar su competencia».
- `submit? = update? && !assigned_gestor?` — «postular la idea es del autor:
  quien acompaña la trabaja, no la presenta por él».

**El motivo pesa MÁS dentro de la sala que afuera**, y es la razón de no
abrirlas: «Crear borrador» deja a quien aprieta como **autor** de la `Idea`, y
esa idea compite en un proceso que el gestor administra.

**Y no hay que escribir nada para que se cumplan.** El formulario de idear vive
detrás de `puede_crear`, que ES `IdeaPolicy#create?`. Así que un gestor que entra
a una mesa ve la lista de ideas, el borrador, las propuestas, la grabación y las
transcripciones, y **no** ve el formulario de crear. La forma ya existe: el
arreglo de la rama anterior sacó el render de grabación de detrás de
`puede_crear` **sin** mover el formulario.

Un **admin** no toca ninguna de las dos: `create?` sólo excluye al gestor y
`submit?` sólo al gestor asignado.

## La pantalla

### El «Entrar», y la matriz que nadie nota

Las mesas son del **taller**; las salas son por **vínculo de desafío**. Es una
matriz: con 3 vínculos y 4 mesas hay 12 salas. El `groups.each` de
`workshops/_groups.html.haml:50` gana un «Entrar» **por vínculo trabajable,
rotulado con el nombre del desafío**, que colapsa a un «Entrar» pelado cuando
hay un solo vínculo trabajable — la misma forma que ya tiene el selector de
`workshops#show`.

Dónde **no** aparece: en la mesa de llegada, y en los vínculos de desafíos que
quien mira no administra.

### Una variable, no diez condicionales

**Diez textos dicen «tu mesa»**, en `workshops/_my_group`,
`workshop_rooms/_ideation` y `_evolution`. En el momento en que alguien actúa
sobre la Mesa 3, las diez mienten — y es exactamente la fuga que `CLAUDE.md`
nombra para la lista de ideas: «las ideas de OTRAS mesas bajo un título que dice
que son de ésta».

El nombre se resuelve **una vez arriba** y las diez frases lo usan: «tu mesa»
cuando es la propia, el nombre de la mesa cuando es ajena. Un `if` repetido diez
veces es diez lugares donde el día que cambie uno se olvida; es la misma forma
que ya usan `puede_configurar` y el `alcanza` de la sala — **una variable
calculada arriba, no un predicado por bloque**.

### Y un aviso, porque el título solo no alcanza

Arriba de la columna de trabajo, un `alert` cuando la mesa es ajena: que estás
trabajando esa mesa **sin estar sentado en ella**, y que lo que escribas queda a
tu nombre. Dos motivos para que sea un aviso y no sólo el título cambiado:

- **El título dice de quién es el contenido; el aviso dice qué estás haciendo.**
  La segunda es la que previene tipear creyendo que estás en la propia.
- **La atribución es la mitad del contrato.** El sello del borrador ya dice quién
  tecleó y `recorded_by` ya dice quién grabó; el aviso es lo que hace que eso no
  sea una sorpresa después.

### La columna de referencia

`workshop_rooms/_referencia.html.haml:39` renderiza `workshops/_my_group`, cuyo
título es «Tu mesa»: pasa a decir el nombre cuando es ajena, con la misma
variable. **Sigue sin controles**: marcar presente y sacar gente viven en el
bloque de armado, que es de quien administra pero está en otra pantalla.

## Los caminos de escritura

Cinco de los siete llamadores cambian de pregunta; dos ya contestaban la
correcta, y eso es el punto —no es un reemplazo mecánico—:

| Dónde | Qué pasa |
|---|---|
| `workshop_rooms_controller:25` (`@group`) | → `acting_group_for`: decide qué dibuja la sala |
| `workshop_drafts_controller:33` | → `acting_group_for` |
| `workshop_proposals_controller:15` | → `acting_group_for` |
| `workshop_recordings_controller:24` (`create`) | → `acting_group_for` |
| `workshop_ideas_controller:23` | → `acting_group_for`, y el gestor igual no llega |
| `workshop_recordings_controller:72` (`alcanzables`) | **no cambia**: ya resuelve el caso de quien administra; sólo pasa de `update?` a `administers?(@link.challenge)` |
| `workshops_controller:84` (`@my_group`) | **no cambia**: ahí «Mi mesa» es literalmente la propia, y sigue vacía |

**El id de la mesa viaja en el CUERPO y no en la ruta**, con el precedente
explícito del borrador —«el id de la idea viaja en el cuerpo y no en la ruta,
porque el cliente no conoce el id del borrador»—. Y **cada endpoint lo
re-resuelve** con `acting_group_for`: el servidor nunca toma la mesa del cliente
sin volver a preguntar quién es.

**`arrival?` sigue negando, para todos.** Trabajar desde la mesa de llegada no se
abre para nadie: la llegada es sala de espera y eso no depende de quién mira.

## Verificación

**Por endpoint y no una vez.** El riesgo de esta feature es escribir un ejemplo
que demuestre el mecanismo y declarar cubierto el resto: son cinco caminos y cada
uno resuelve la mesa por su cuenta. Para cada uno:

- un admin **no sentado** actúa sobre una mesa nombrada, y la fila queda de **esa
  mesa**, con la atribución a su nombre;
- un `participant` que manda el mismo parámetro nombrando otra mesa escribe en
  **la suya** — el parámetro se ignora, **no** se rechaza;
- un gestor que **no administra ese desafío**, idem;
- desde la **llegada**, 403;
- un id de mesa de **otro taller** o de **otra empresa** cae al asiento propio,
  sin 403.

Más, en la pantalla: que el «Entrar» no aparezca en la llegada ni en un vínculo
que quien mira no administra; que el aviso de mesa ajena esté; y que los títulos
digan el nombre de la mesa y no «tu mesa».

**El recorrido no cambia, y está medido:** el seed sienta al admin
(`seeds.rb:857`, `:888`) y `acting_group_for` prefiere el asiento propio. Si
alguien saca ese asiento del seed, `[DRAFT]` y `[GRABAR]` caen a 0 — y ahora
además habría que enterarse de que la sala empezó a resolver otra mesa.

## Lo que NO cubre, declarado

- **Que el aviso de «mesa ajena» se lea.** Es texto en una vista; se puede medir
  que esté, no que alguien lo note.
- **Que la atribución alcance como auditoría.** Cada fila dice quién actuó, pero
  **ninguna pantalla lista «lo que hizo quien administra desde afuera»**. Si eso
  hace falta, es otra feature.
- **La carrera entre quien administra y la mesa tecleando el mismo borrador.** Es
  último-que-escribe-gana por diseño y el sello nombra a quien tecleó — pero
  ahora los dos pueden ser personas que no se ven entre sí.
- **Avisarle a la mesa en vivo** que alguien entró desde afuera. Un push pediría
  el canal autenticado y scopeado por empresa que la spec de la lista de llegada
  ya descartó.
- **El selector dentro de la sala.** Se descartó para esta spec y se puede sumar
  encima de este mecanismo.

## Riesgos

1. **Diez textos que pueden mentir.** Si la variable del nombre se olvida en uno,
   ese título dice «tu mesa» sobre contenido ajeno. Es el riesgo principal y lo
   acota que sea UNA variable y no diez condicionales.
2. **Cinco caminos de escritura que resuelven la mesa por separado.** Si uno
   queda con `group_of(current_user)`, no falla: **escribe en la mesa
   equivocada**, en silencio. Por eso la verificación es por endpoint.
3. **El permiso por desafío.** Usar `administers_any?` por comodidad abriría
   escritura sobre salas cuyo desafío le da 404 al gestor.
