# Handoff

## Objetivo

Ejecutar el plan de **asignación automática de mesas en el taller** —el punto 1
de los próximos pasos del handoff anterior— por subagentes: un implementador por
tarea, un revisor fresco después de cada una, y una revisión de rama entera al
final.

Se ejecutó completo: **6 de 6 tareas**, mergeado a `master` local. **No se
pusheó nada.**

La razón de elegir subagentes se sostuvo: las tareas se encadenan por interfaces
que una sola persona inventó, y el revisor fresco encontró en cada eslabón lo que
el que lo escribió no veía. Cuatro de los seis hallazgos más caros de la sesión
salieron de una revisión, no de la implementación.

## Estado actual

- **`master` está en `af825a3`** — el merge `--no-ff` es `415a7b9`, con la
  convención «Merge: …» del repo, y encima va este handoff. **12 commits adelante
  de `origin/master` y sin pushear.**
- `make spec` **1468/0** —corrida sobre el árbol mergeado, no sólo sobre la
  rama— contra los 1418 de antes. `make screens` **71 capturas / 0 errores**.
  `make seed` abre los dos talleres.
- La rama `asignacion-de-mesas` se borró después del merge (era `676758d`).
- **La feature:** un taller arma sus mesas solo. Por cabeza en idear, por trabajo
  compartido en evolución. El control vive en el bloque de armado de la pantalla
  del taller, detrás de cuatro condiciones que espejan las del servicio.

### Lo que el plan no decía, y hubo que decidir

Fueron 31 decisiones, cada una anotada con qué costaba si me equivocaba. **Ese
ledger vivía en `.superpowers/sdd/` y se borró con el workspace al cerrar la
rama**, así que lo que sobrevive es lo que está escrito acá: los cinco que
cambian cómo se lee el código (abajo), los tres residuales parqueados y los
cuatro diferidos (en «Próximos pasos»). El resto eran decisiones de proceso
—qué modelo para cada tarea, qué mutación pedir, qué minor meter en qué ronda—
cuyo resultado ya está en el código y en los diez mensajes de commit.

Los cinco que cambian cómo se lee el código:

1. **El reparto del seed que proponía el plan rompía `25-taller-sala-idear`.**
   Mandaba a admin al taller de evolución, y el texto «El borrador se comparte
   con Paula Participante» sale de `@my_group` —la mesa del que mira EN ESE
   taller—, así que la sala de idear quedaba sin mesa y sin formulario. El
   reparto que quedó: «Taller de mejora continua» igual que antes menos el
   vínculo de evolución, y «Taller de evolución» con su propia «Mesa Bodega».
2. **`groups_by_idea` producía cortes fantasma.** El plan metía un grupo de una
   persona por CADA sentado, incluidos los que ya están dentro de una idea. Esos
   singletons se desprenden antes que las ideas —solapan 1 contra 2— y emiten un
   corte que no mueve a nadie. El flash habría dicho «4 grupos partidos» por un
   corte. Ahora sólo entra como grupo de uno quien NO está en ninguna idea, que
   es literalmente lo que dice el spec.
3. **Un taller ABIERTO puede no tener fase**, porque `MaterializeClosures` cierra
   los vínculos vencidos de a uno y **no** cierra el taller (a diferencia de
   `Close`). Ahí `phase` es `nil`, el ternario caía a la rama de idear y
   repartía sobre una ronda ya terminada. El servicio ahora exige fase con
   mensaje propio, y `puede_repartir` pregunta lo mismo para no ofrecer un botón
   que rebota.
4. **`phase` y `open_step_ids` preguntaban `open?` y no `workable?`.** Un vínculo
   con el módulo ya `completed` —el estado en que queda TODO vínculo tras un
   `advance!`, hasta que alguien abre la pantalla— pasaba. `MaterializeClosures`
   usa `link.open? && !link.workable?` justamente para encontrarlos.
5. **CLAUDE.md no documentaba el taller en absoluto.** Cero menciones ahí, en el
   README y en los cuatro `docs/*.md`: el módulo entero —cinco modelos, cinco
   servicios, las dos salas, las capturas 24 a 28— estaba sólo en una tarjeta de
   diagrama. El plan decía «en la sección del taller, sumar», y esa sección no
   existía. Ahora existe (`CLAUDE.md:420`).

## Archivos y cambios

29 archivos, +1120/−64 en diez commits.

- **El dominio nuevo:** `app/lib/flow/workshops/seating.rb` (el reparto puro, sin
  base) y `app/lib/flow/workshops/assign_groups.rb` (las cinco guardas, el pool
  por fase y la persistencia). `Flow::Workshops::Open` ahora verifica la fase
  única antes de escribir nada; `Workshop#phase` la deriva y se niega si hay
  mezcla en vez de adivinar.
- **Esquema:** `db/migrate/20260930140000_add_attended_to_workshop_group_members.rb`
  y `db/structure.sql`. `attended` y **no** `present`: una columna `present`
  genera `present?`, que choca con `Object#present?` y el choque no da error,
  devuelve otra cosa.
- **La pantalla:** `POST /workshops/:id/mesas/assign`, `workshop_groups#assign`
  y el bloque en `app/views/workshops/_groups.html.haml`. `WorkshopGroup` ganó
  `has_many :workshop_proposals, dependent: :destroy`, que no tenía y la vista
  asume.
- **El seed partido en tres talleres** y el recorrido de capturas visitando dos
  (`25`/`28` del de idear, `26`/`27` del de evolución, `24` del borrador).
- **Specs nuevos:** `seating_spec.rb` (11 ejemplos, sin base de datos),
  `assign_groups_spec.rb` (19), `workshop_mesas_spec.rb` (13),
  `spec/models/workshop_spec.rb` (nuevo, 4).
- **Docs:** la sección `### El taller` en `CLAUDE.md`, y un ítem reescrito en
  cada uno de los dos diagramas —los dos tenían la misma línea falsa palabra por
  palabra, y el plan sólo mandaba revisar el de proceso—.

## Intentos fallidos

### Cinco tests que no podían fallar, y dos eran míos

Es el hallazgo de la sesión. Los cinco están arreglados y **los cinco se vieron
fallar**.

1. **El ejemplo de determinismo se comparaba consigo mismo.** `repartir(x) ==
   repartir(x)` no puede fallar nunca sobre una función pura, y el desempate por
   clave que decía medir es redundante con un `sort_by` que vive en otro método.
   Lo encontró el implementador corriendo la mutación que el plan pedía. Ahora
   assertea la salida concreta, y el desempate por tamaño se fija donde **sí** se
   observa: en `splits`, no en `tables` —las mesas salen iguales en los dos
   casos—.
2. **El ejemplo de grupo vacío, que escribí yo**, tenía el mismo defecto por otra
   vía: `pack` absorbe un bloque vacío dentro de cualquier mesa existente, así
   que el grupo sin nadie sólo se ve cuando es el ÚNICO grupo. Mi ejemplo probaba
   el caso en que el defecto es invisible.
3. **Los cortes fantasma** (arriba).
4. **El ejemplo de `phase`** pasaba contra la implementación rota: con
   open/open/closed y kinds evolution/evolution/ideation, sacarle el
   `select(&:open?)` deja `.uniq.first` dando «evolution» igual, y para qué lado
   cae depende del orden de filas.
5. **El ejemplo de permiso del control daba 404 antes de renderizar.** Paula no
   está en ninguna mesa, así que `WorkshopPolicy::Scope` le devuelve scope vacío
   y `find_by!` revienta: el ejemplo asserteaba que una página 404 no contiene el
   path. Borrar `can_assemble` de la vista lo dejaba verde. Ahora se la sienta
   primero y se exige **200**.

**Lección: pedir la mutación no alcanza; hay que preguntar qué tendría que
romperse.** Tres los cazó una mutación, dos un trazado a mano que pedí
explícitamente. Y el pedido funciona: a la revisión de Task 3 le pedí buscar una
segunda guarda incapaz de fallar y la encontró —la mía—.

### Un ejemplo del plan no podía pasar contra el código del mismo plan

El de «desprende la idea de menor solape» pedía `size: 3` donde quería decir 4:
con 3, después de desprender i3 el resto son cuatro personas y tampoco entra, así
que se desprende i1 también y `pack` junta c con e. Tres de sus cinco aserciones
fallaban. **Lo encontré simulando los nueve ejemplos a mano antes de despachar**,
no leyéndolos.

### Mi expectativa de un test estaba incompleta, y el implementador la corrigió

Predije que los `splits` del ejemplo del desempate por tamaño serían `["i2"]`.
Son `[["i2", false], ["i1", true]]`: con i2 desprendida, i1 queda sola con tres
personas y tamaño 2, así que `fit` la parte otra vez. La derivó a mano y no la
copió de la salida, que es la diferencia entre un test y una tautología.

### «El +16px es inevitable» era falso, y lo desmintió una medición

El implementador de Task 6 reportó que la tarjeta no podía volver a 1688px sin
tirar un hecho, con una tabla de siete redacciones. El revisor midió nueve sobre
una copia del HTML commiteado y encontró **tres** que vuelven a 1688 conservando
los dos hechos: lo que costaba la línea era **nombrar las dos fases**, que ni el
spec ni el ruling pedían. La búsqueda había saltado la banda de 69-70 caracteres.
El conteo de caracteres solo no decide (73 → 1704, 70 → 1688), que es por lo que
hubo que medir y no razonar.

### El aviso de cortes decía «2 grupos quedaron partido»

`Flow::Texto.agree` conjuga el verbo y `"partido"` quedó como adjetivo fijo. Es
la **tercera** repetición del defecto que ese módulo existe para terminar
—«condicións», «Faltan 1 idea», «1 desafío quedaron afuera»—, y sobrevivió seis
revisiones por una razón sola: **ningún test ejecutaba esa rama**. El ejemplo de
éxito sólo miraba que el aviso dijera «mesa».

### `git checkout` para restaurar una mutación, otra vez no

No pasó esta sesión porque estaba en memoria y se puso en cada dispatch: el
backup va con `cp` al scratchpad. En una rama sin commit, `git checkout <archivo>`
restaura del índice, o sea deshace el ARREGLO y no la mutación.

## Próximos pasos

1. **Pushear `master`.** Son 12 commits y el remote es SSH sin clave acá: va con
   la URL HTTPS explícita y después el ref de seguimiento se mueve a mano.
2. **El escritor de `attended`.** Decisión tomada en esta sesión: se difiere. La
   asistencia está código-completa —la columna, el scope, el descuento en las dos
   fases, el asiento que se conserva, el overflow deliberado— y **no hay forma de
   marcar a nadie ausente desde la app**: sólo la escriben los specs. `CLAUDE.md`
   lo dice con la forma de frase del repo. El control sería un toggle por
   integrante detrás del mismo `can_assemble`, con su endpoint y su par de
   ejemplos.
3. **La frase por corte que pide el spec.** Hoy el aviso cuenta los cortes y
   distingue el caso extremo con su propio texto, pero no dice CUÁL grupo se
   partió ni quién se quedó —«*Turnos rotativos* se sentó aparte; Paula se quedó
   en la otra mesa porque también trabaja en *Pesaje*»—. Necesita títulos de idea
   y nombres en el controller. `Split#shared_user_ids` ya trae lo que hace falta y
   hoy no lo lee nadie fuera del spec.
4. **Tres residuales parqueados con ruling:** `open_step_ids` no lo fija ningún
   test (el ejemplo pasa por `phase`, cuyo guarda rechaza primero, así que
   revertir media línea deja la suite verde); el ejemplo del barrido stubea el
   privado `proposals?` con `allow_any_instance_of` y hay alternativa sin stub
   (`send(:seat!, …)`); y con un corte ordinario Y uno `inside` juntos el aviso
   pierde la cuenta de los ordinarios.
5. **Cuatro diferidos del review de rama, triados como «se va así»:** el N+1 de
   `people_of` (una consulta de `IdeaContributor` por idea), la falta de
   `rescue RecordNotUnique` alrededor de `seat!` (un `Convoke` concurrente sale
   500 en vez de `Result`, aunque el `with_lock` rollbackea limpio), que
   `workshop_proposals_controller.rb:25` no toma el lock del taller, y que
   ninguna guarda de capturas busque el control nuevo.
6. **Lo que sigue abierto de handoffs anteriores, sin tocar:** el desborde
   vertical de los dos diagramas (arquitectura 1345px, proceso 1688px en un
   viewport de 900 — medido de nuevo esta sesión; `visual-check` sale
   `status: "fail"`, no `skipped`); que `make screens` no vea violaciones de CSP
   porque sólo escucha `pageerror`; el nodo salteado del mapa a 1,96:1; el flake
   horario de `spec/requests/selection_screen_spec.rb:138`; la actualización de
   `archify` (2.17.0-dev.1 instalada, 3.0.1 disponible — no se tocó a propósito,
   un upgrade a mitad de plan puede cambiar el formato de salida); y
   `challenge_gestores` huérfano re-otorgando acceso.

## Cosas del entorno

- **En desarrollo `FLOW_AI_PROVIDER=anthropic`: un pedido a la IA cuesta plata
  real.** En cada dispatch de subagente fue explícito: ni la app corriendo, ni la
  base de desarrollo, ni `make seed`, ni `make screens`. **Esas dos las corrí yo**
  desde la sesión principal, cuatro veces, y es lo que midió que el cambio a
  `workable?` no rompiera los vínculos sembrados en vez de asumirlo.
- **Probar una guarda es romperla a mano y correrla**, con el backup por `cp` al
  scratchpad. Nunca `git checkout <archivo>`. Y correrla **no alcanza**: quedó en
  memoria (`mutacion-verde-no-prueba-nada`) que de cada test hay que preguntar
  qué tendría que romperse para que se ponga rojo, porque una mutación puede dar
  verde por culpa del test y no del código. Las cinco de esta sesión son el
  ejemplo.
- **`visual-check` de archify necesita que se le diga dónde está Chrome:**
  `export ARCHIFY_CHROME=~/.cache/ms-playwright/chromium-1223/chrome-linux64/chrome`.
  Sin eso se saltea y sale `ok: false` con `status: "skipped"`, que se lee igual
  que un fallo descartable — así fue como los dos diagramas siguieron fallando
  sin que nadie lo notara.
- **Un `visual-check` deja recibos commiteados** (`*.visual-check.json` y PNGs),
  y el comando los reescribe. Van en el commit: si no, el recibo afirma un sha256
  y un alto de un archivo que ya cambió.
- Los merges de este repo van `--no-ff` con mensaje «Merge: …».
- `make screens` tarda ~2 minutos y `make spec` ~6. Las dos corren bien en
  background.
- El harness sigue inyectando `Co-Authored-By` por system-reminder; hay que
  cortarla a mano. En los once commits de esta sesión no quedó ninguna.
