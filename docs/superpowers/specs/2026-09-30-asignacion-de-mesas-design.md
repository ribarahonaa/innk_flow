# Asignación de mesas en el taller

Diseño acordado el 2026-09-30. Reemplaza el armado de mesas de a una por un
reparto automático, con dos formas de armar la entrada según la fase del taller.

## Qué resuelve

Hoy una mesa se crea vacía y con nombre (`WorkshopGroupsController#create`), y
se puebla convocando de a una persona (`Flow::Workshops::Convoke`). Con veinte
personas y seis mesas eso son veintiséis clics y ninguna ayuda para decidir
quién va con quién.

Lo que se pide: **que el taller arme las mesas**, con dos criterios distintos
según la fase que están corriendo sus desafíos.

- **En idear**, por cabeza: se dice cuántas personas por mesa y se reparte.
  No hay nada de qué deducir agrupaciones, porque todavía no hay ideas.
- **En evolución**, por trabajo compartido: las mesas salen de quién trabaja en
  qué idea, tratando de dejar juntos a los que trabajan juntos.

## Lo que NO entra

**Cómo trabajan las mesas una vez armadas** —qué hace la sala, cómo se propone,
cómo se reparte el trabajo adentro— es una segunda tanda. Este diseño termina
cuando la gente quedó sentada.

Tampoco entra registrar de dónde salió cada mesa: el aviso de qué se partió es
de una sola vez, por flash, y no se persiste.

## Las seis decisiones

1. **El pool son los participantes de los desafíos vinculados.** En idear, los
   miembros con rol `participant` de la empresa; los roles `admin`, `gestor` y
   `evaluator` no entran al reparto automático y se convocan a mano como hoy.
2. **La asistencia se persiste**, y es lo que acota el pool a quienes de verdad
   fueron. Rearmar reparte sobre los presentes.
3. **En evolución el pool es más angosto:** sólo quienes trabajan en las ideas
   que están en esa etapa.
4. **Un taller es de una sola fase.** Mixto no abre.
5. **El tamaño de mesa manda.** Un racimo que no entra se parte, y se avisa.
6. **No rearma si ya hay propuestas.** El primer reparto es libre; después se
   mueve a mano.

## El modelo: una columna y un invariante

### `workshop_group_members.attended`

Boolean, `NOT NULL`, default `true`.

**El nombre no es `present`**: en Rails una columna `present` genera `present?`,
que **choca con `Object#present?` de ActiveSupport**. El choque no da error —
devuelve otra cosa—, que es la peor forma de romperse.

Default `true` es lo que evita un paso extra: el reparto inicial sienta al pool
completo y marcar ausentes es la excepción. Un ausente **no desaparece**: queda
en su mesa con `attended: false`, y rearmar reparte sólo sobre los `attended`.

La asistencia cuelga de la membresía de la mesa y **no** de un padrón aparte,
para no crear la segunda fuente de «quién está en este taller» que `Convoke`
advierte: «dos fuentes divergen, y la primera vez que difieran una de las dos
estaría mintiendo».

### La fase única, en `Open`

`Flow::Workshops::Open` es el único lugar que conoce todas las fases a la vez, y
ya lo dice su comentario: «la fase se verifica ACÁ y no al sumar el desafío:
entre que el taller se arma y se abre, el desafío pudo avanzar».

Secuencia: resolver el módulo activo de cada vínculo → cerrar los que no están
en idear ni evolución, como hoy → **contar los `kind` distintos entre los que
quedaron abiertos**. Si son dos, `raise ActiveRecord::Rollback` y un `Result`
con el error nombrando qué desafío está en cuál fase.

**No va como validación de modelo**: en borrador `challenge_step` es `nil`, así
que la fase todavía no existe.

**La fase se deriva, no se guarda.** `Workshop#phase` lee el `kind` de sus
vínculos abiertos, homogéneos por la regla de arriba. Una columna sería la
segunda fuente que este repo evita por regla.

## El servicio

`Flow::Workshops::AssignGroups`, con la forma de los otros cuatro: `Result` con
`ok?`.

**Guardas**, en orden:

1. taller **abierto** — en borrador no hay fase con la que elegir el criterio
2. **ninguna mesa con propuestas** — `workshop_proposals.workshop_group_id` es
   `ON DELETE CASCADE`, así que rearmar borrando mesas se llevaría propuestas
   aceptadas, que son la procedencia de versiones publicadas
3. pool no vacío

**Una sola estrategia, no dos.** Idear no es otro algoritmo: es el mismo con
grupos de una persona. El módulo ya piensa así — «en modo individual también
existe: es una mesa de una persona. Un mecanismo y un gancho, en vez de dos
caminos en el código».

El servicio arma la **entrada** según la fase y delega en un colaborador puro:

| Fase | Un grupo indivisible es… |
|---|---|
| idear | una persona presente del pool |
| evolución | la gente de una idea de los `step_entries` (autor + `IdeaContributor`) |

`Flow::Workshops::Seating` recibe grupos y un tamaño, y devuelve mesas y qué
partió. No toca la base: se prueba con arreglos.

## El algoritmo

1. **Racimos**: componentes conexos sobre «comparten una persona». En idear no
   hay ninguno, por construcción.
2. **El que entra, entra**: racimo con ≤ tamaño personas distintas → una mesa.
3. **El que no entra se desprende por la idea de menor solape.** Se desprende la
   idea que comparte menos gente con el resto; empate → la de menos gente;
   empate → orden de id, para que dos corridas den lo mismo.

   **La gente compartida se queda**; se mueve sólo la exclusiva de esa idea.
   Porque una persona se sienta en una sola mesa: si Paula trabaja en las dos,
   desprender su idea no puede llevársela. De ahí sale el aviso legible:
   *«Turnos rotativos» se sentó aparte; Paula se quedó en la otra mesa porque
   también trabaja en «Pesaje»*.

   Cada conjunto desprendido se vuelve a medir: puede exceder el tamaño él mismo.
4. **Se empaquetan las mesas chicas.** Dos racimos independientes de 2, con
   tamaño 6, van a una mesa: juntar gente que no trabaja junta no parte ningún
   grupo, y es lo que respeta el tamaño pedido. Primero los racimos grandes.

### El caso extremo

**Una sola idea con más gente que el tamaño.** No hay frontera de idea por donde
cortar, así que ahí se parte gente de una misma idea —el tamaño manda— por orden
fijo y **con un aviso propio y distinto del resto**, porque es el único caso en
que el resultado no respeta la regla y quien lo lea tiene que saberlo.

## Tres cosas que el diseño se podía leer de dos formas

Salieron de releer este documento, y cada una tenía dos lecturas razonables.

### A quién puede evictar el reparto: a nadie

El pool automático es el rol `participant`, pero convocar a mano ofrece toda la
empresa: puede haber alguien sentado que el pool no contiene —quien administra,
un evaluador invitado—. **El reparto no lo saca.** La entrada real es

> el pool automático **más** quien ya esté sentado y presente

Sacar a alguien que fue convocado a propósito, porque su rol no entra en un
criterio automático, sería que la función deshaga una decisión que alguien tomó.

### Qué pasa con las mesas que sobran: se borran sólo si quedan vacías

El reparto **nunca borra una mesa con gente**. Crea las que falten, mueve a los
presentes, y borra únicamente las que quedaron completamente vacías. Es seguro
porque el guarda de propuestas ya corrió: sin propuestas, una mesa vacía no
arrastra nada.

Los ausentes conservan su asiento, así que su mesa no queda vacía y no se borra.

### La asistencia vale en las dos fases

El reacomodo por ausentes se pidió para idear, y la asistencia se aplica igual en
evolución. No es una extensión gratuita: si alguien no vino, su idea pierde a esa
persona, y eso **cambia los racimos**. Ignorar la asistencia en evolución dejaría
mesas armadas alrededor de gente que no está.

## Qué se ve

El control va en `workshops/_groups`, detrás del `can_assemble` que ya existe
(`WorkshopPolicy#update?`, que es lo mismo que `manage_groups?`, calculado una
vez en `show.html.haml` y reusado en toda la cadena).

**Con su propia variable de estado, más angosta que la de alrededor.** El bloque
actual vive con `can_edit = !workshop.closed?`, o sea que también está vivo en
borrador; el servicio necesita el taller abierto y sin propuestas. Ofrecerlo con
la condición ancha sería un control que rebota. Una variable calculada una vez,
y el controller preguntando lo mismo.

**Una asimetría deliberada:** convocar a mano sigue ofreciendo toda la empresa
menos quien ya está sentado —«participar de un desafío vinculado no es estar
convocado», dice el partial hoy— mientras el pool automático se acota al rol
`participant`. El reparto automático elige por vos y por eso se acota; la
convocatoria manual no elige y por eso no.

**Lo que informa** va en el flash: qué hizo, y si partió algo, cada corte con su
frase. El error de fase mixta sale por el camino de alerta que `Open` ya tiene.

## Cómo se prueba

- **`Seating` con arreglos pelados**, sin base de datos, y es el grueso: los
  cuatro pasos, los desempates, el caso extremo con su aviso propio, y un
  ejemplo de **determinismo** — mismo input dos veces, mismo output. Ese existe
  porque los desempates están justamente para eso y, sin medirlo, se pueden
  romper sin que nada se queje.
- **`AssignGroups`**: los tres guardas y las dos formas de armar la entrada.
- **`Open`**: fase mixta no abre, **nada cambió** (el rollback), y el error
  nombra los dos desafíos.
- **Request spec con las dos polaridades del control**: aparece para quien puede
  y cuando funciona; no aparece si no. Un control sin su ejemplo negativo deja
  sacarle la guarda sin que nada se ponga rojo.
- **Cada guarda vista fallar**, rompiéndola a mano.

## Lo que esto cuesta

**El taller sembrado deja de poder abrirse.** «Taller de mejora continua» tiene
`ideation` y `evolution` abiertos a la vez. Hay que partirlo en dos talleres en
`db/seeds.rb` y volver a correr `make screens`, porque de ahí salen
`24-taller-armado` y las guardas `[TALLER]`, que cuentan los títulos de sala.

**Y hay que revisar los dos diagramas.** La tarjeta del proceso dice «Un evento
que abarca N desafíos» y «Sólo entra un desafío cuyo módulo activo sea idear o
evolución», las dos ciertas pero ahora incompletas: falta que sean de la misma
fase. Y «la mesa no se programa: sus integrantes nacen colaboradores de la idea»
deja de ser cierto tal cual está escrito.
