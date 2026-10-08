# Handoff — la re-revisión acotada del borrador de mesa, y diez mutaciones (2026-10-08)

## 1. Objetivo

Correr la **re-revisión acotada** que la sesión anterior dejó pendiente como
próximo paso número uno: el diff de `f53594e..93a6d95` —la última ronda del
borrador de mesa, la que cerró el bloqueante de la revisión final y dos
Important más—, que estaba verificado en lo que el ejecutor pudo medir pero
**nadie había mirado con ojos frescos**.

No era construir nada nuevo. Era contestar tres preguntas abiertas y cerrar lo
que apareciera.

## 2. Estado actual

Rama **`borrador-de-mesa`**, 20 commits sobre `master`, **pusheada y en
sincronía**: `origin/borrador-de-mesa` está en el commit de este handoff.
`master` sigue en `acda95a`, así que la rama está publicada y sin mergear.

Verificado preguntando **por la rama** y no por `master`, que es el error que
esta cadena de handoffs ya pagó dos veces:

```bash
git branch -vv                                                   # ahead/behind
gh api repos/ribarahonaa/innk_flow/branches/borrador-de-mesa --jq .commit.sha
```

Tres commits nuevos: `50741b6` (los dos testigos), `85cd1c3` (los documentos),
`dbaa378` (la pasada de comentarios y el atributo honesto).

- `make spec`: **1694 ejemplos, 0 fallas**. Venía de 1685: +7 en `50741b6` (6 del
  lint nuevo, 1 del ejemplo discriminador) y +2 en `dbaa378`.
- `make screens`: verde. Cuatro corridas, todas con `FLOW_AI_PROVIDER=fixture`,
  o sea **cero costo de IA**. Última línea:
  `[RITMO] 39 · [RELLENO] 296 · [PASTILLA] 813 · [CRITERIO] 195 · [LIVE] 1 ·
  [RIEL] 71 · [BANDA] 71 · [SOMBRA] 299 · [CAMPO] 291 · [DRAFT] 2`.
- **Diez mutaciones**, cada una pegando en el ejemplo que le toca. Están abajo
  como tabla, porque es lo que más cuesta reconstruir.

**OJO con el proveedor, y al revés de lo que decía el handoff anterior.** Ese
decía «la app quedó en `fixture`»; al empezar esta sesión el stack llevaba dos
horas arriba y `FLOW_AI_PROVIDER` decía **`anthropic`**. O sea que esa línea era
falsa y se le habría creído. **Hoy queda en `anthropic`** —verificado en `app` y
en `sidekiq`—, así que una corrida de `make screens` cuesta plata. Para bajarlo
a fixture y devolverlo:

```bash
FLOW_AI_PROVIDER=fixture docker compose up -d --force-recreate app sidekiq
docker compose up -d --force-recreate app sidekiq   # vuelve al .env
```

El recreate tiene que incluir `sidekiq` (`Flow::AI.provider` memoiza por
proceso), y **no** sirve `make reup`: hace `down` del stack entero.

### El veredicto de la revisión

**Con arreglos, cero Critical.** Tres Important y nueve Minor, todos cerrados o
descartados con motivo. Las nueve líneas de «declined to judge» quedaron
revisadas: las dos decisiones ya aceptadas —el borrador que cambia de dueños al
repartir, y el envío fallido que pierde lo tecleado— se verificaron contra
`assign_groups.rb:160` y `:174-176` y siguen como estaban.

Las tres preguntas abiertas, contestadas:

1. **`base_version_id` del cliente: seguro**, y por un motivo que no estaba
   escrito en ninguna parte. El `find_by` cuelga de `idea.versions`, que filtra
   por `idea_id` **y** —vía `TenantScoped`— por `company_id`, así que una versión
   de otra idea o de otra empresa queda excluida dos veces, independientemente. Y
   la columna es **`uuid`** (`db/structure.sql:739`), así que `OID::Uuid#cast_value`
   convierte basura, un no-entero, un array o la clave ausente en `nil` antes del
   SQL. **Las dos últimas son portantes y no se leen del código**: si el tipo de
   la columna cambiara, o si el `find_by` se mudara a `IdeaVersion`, se irían a la
   vez la seguridad de tipo y el scope. Está escrito en `CLAUDE.md`.
2. **`res.status !== 204`: no hay cuarto camino de éxito.** Se enumeraron los seis
   del action más la capa de framework, y la ruta es `resource :draft, only:
   %i[update]`, así que no hay otro verbo. El único 2xx no-204 alcanzable es el
   200 del redirect seguido, que es el bug que se arregló.
3. **El ejemplo del fallback no distingue el arreglo, confirmado — y ninguno
   podría.** El fallback *es* el comportamiento viejo, así que sólo discrimina un
   caso donde el valor del cliente y el de la base difieran.

### Lo que queda sin verificar

Nada de esta re-revisión. Lo que sigue abierto es lo de antes, y está anotado en
`CLAUDE.md` con su tamaño real: el **camino concurrente** del autoguardado
(`AbortController`, `enVuelo`, los dos `form !== enviadoDesde`, `descargar()` con
su `keepalive`) no lo mide nada y borrarlo deja la suite y `[DRAFT] 2` en verde;
el **borrador de idear puede cambiar de dueños** al repartir; un **envío fallido**
pierde lo tecleado desde la última pausa de dos segundos; y
`MINIMO_DE_CAMPOS_POR_CARA` mide **2 de 2 sin margen**, así que la rama que falla
por «pocos campos» nunca corrió y su mensaje no está probado.

Y una cosa de proceso: **los asientos de revisión de esta rama están gastados.**
Hubo revisión final de rama entera, esta re-revisión acotada, y las dos están
cerradas. Un tercer pase sobre lo mismo rinde poco.

## 3. Archivos y cambios

| Pieza | Dónde | Commit |
|---|---|---|
| La tercera fase de `[DRAFT]`: intercepta el PATCH, contesta 200 y exige el texto de fallo | `script/capture_screens.js` | `50741b6` |
| El lint de los tres eslabones del sello, con autotest del stripper | `spec/lint/sello_del_borrador_spec.rb` (nuevo) | `50741b6` |
| El ejemplo que separa `idea.versions` de `IdeaVersion` | `spec/requests/workshop_drafts_spec.rb` | `50741b6` |
| La spec de diseño: el bloque de código y la línea en negrita, corregidos con un `Ojo:` fechado | `docs/superpowers/specs/2026-10-07-borrador-de-mesa-design.md` | `85cd1c3` |
| El bullet del sello y uno nuevo sobre el dato del cliente | `CLAUDE.md` | `50741b6`, `85cd1c3` |
| El atributo `draft_base` honesto, con su ejemplo | `app/views/workshop_rooms/_evolution.html.haml`, `spec/requests/workshop_draft_prefill_spec.rb` | `dbaa378` |
| `base_version_id` por argumento; tres comentarios que prometían cotas falsas | `app/controllers/workshop_drafts_controller.rb`, `db/migrate/20261007120000_create_workshop_drafts.rb` | `dbaa378` |

### El mapa de cobertura, medido

Esto es lo que más cuesta reconstruir y lo que ninguna lectura del código da.
Qué eje caza qué:

| Mutación | Rojo en |
|---|---|
| se saca `if draft.new_record?` | «el sello de la versión no se reescribe en el autoguardado siguiente» **y** «de extremo a extremo» |
| la vista pierde `draft_base` | «el sello usa la versión con la que se prellenó» + el lint |
| el servidor ignora al cliente y lee de la base | «el sello usa la versión con la que se prellenó» |
| el JS deja de leer `dataset.draftBase`, o le cambia la clave | **sólo** el lint |
| `IdeaVersion.find_by` en vez de `idea.versions.find_by` | el ejemplo de «otra idea de la misma empresa» |
| `res.status !== 204` → `!res.ok` | las dos caras de `[DRAFT]`; cae de 2 a **0** |
| el atributo vuelve a `selected.current_version_id` | el ejemplo de `data-draft-base` con borrador |
| el stripper del lint deja de sacar los `//` | el autotest del stripper |

Tres decisiones de diseño de esta sesión que no se leen del código:

- **La fase de fallo de `[DRAFT]` no suma un contador nuevo.** Una cara cuenta
  como medida sólo si pasaron las tres fases. `PISO_DE_BORRADORES` es exacto en 2
  porque cuenta CARAS y no hay una tercera; un contador aparte lo volvería 4,
  rompería esa semántica y sumaría un onceavo número a una línea que el doc dice
  que tiene diez.
- **La fase de fallo va al FINAL.** La de éxito ya dejó el borrador escrito y un
  guardado que falla no escribe nada, así que no contamina lo medido; y
  `guardar()` no restaura `sucio`, de modo que el texto de esa fase no se va
  después en el `keepalive` de `descargar()`.
- **El lint tiene autotest del STRIPPER y no de los patrones.** De los patrones
  ya se encargan los tres ejemplos, que comparan contra el código sin
  comentarios; lo que puede fallar en silencio es el stripper, porque uno que
  devolviera el archivo entero los dejaría pasando sobre la prosa que explica
  cada línea.

## 4. Intentos fallidos

**Una mutación mía no probaba nada y dio verde.** Para el autotest del stripper
mutué el `gsub` de `/* */` — que el JS no usa, o sea un no-op— y la guarda siguió
en verde. El trabajo real lo hace el `sub(%r{//.*})` de cada línea. Lo delató el
propio verde: una mutación que no pone nada en rojo es sospechosa antes de ser
tranquilizadora. Es la trampa exacta que esta rama lleva catorce casos cazando, y
la pisé escribiendo la guarda que existe para eso.

**Un `cp` de restauración me deshizo el arreglo, no la mutación.** El backup de
`_evolution.html.haml` se había tomado al EMPEZAR la tanda C, o sea antes de
aplicar el ítem 4; al restaurar la mutación, el `cp` devolvió el archivo a la
versión pre-arreglo. Lo cazó un `grep -c` del arreglo que dio **0**. Sin eso, el
commit habría salido sin el cambio que su ejemplo nuevo justifica. Es la misma
familia que el `git checkout` ya anotado: **el backup va después del arreglo, y
se verifica grepeando lo ARREGLADO y no lo mutado** —lo mutado ausente no
distingue «restaurado» de «restaurado de más»—.

**Escribí un autotest redundante y lo saqué.** El primer lint tenía un ejemplo
«mira el código y no el comentario que lo explica», que no agregaba nada: como la
guarda real ya compara contra el código sin comentarios, no puede vivir de su
propio comentario, y el único efecto era que cada mutación diera dos fallas en
vez de una. Lo reemplacé por el del stripper.

**Una preocupación que resultó ya resuelta.** Al diseñar la fase de fallo noté
que comparar `innerText` contra `data-failed-text` es el mismo agujero
autorreferencial que la ronda anterior había cerrado para el texto de guardado:
los dos lados salen del mismo lookup de locale. Resultó que **ya estaba cubierto
para los dos textos** —`workshop_draft_prefill_spec.rb` asevera los dos literales
desde afuera—, así que no hizo falta nada. Lo que faltaba era la RAMA, no el
string.

**El reviewer se equivocó en un punto, medido.** Afirmó que el ejemplo del sello
(«el sello usa la versión con la que se prellenó») se pone rojo al sacar
`if draft.new_record?`. No:
hace un solo `PATCH`, así que resellar escribe el mismo valor. Los que sí caen son
otros dos. Yo relayé esa afirmación sin medirla antes de corregirla; la lección es
la de siempre en este repo, aplicada a un revisor en vez de a un test.

**Lo que NO falló, para no buscarlo:** el `base_version_id` del cliente aguantó
todo lo que le tiré —cadena basura, no-entero, versión de otra idea, versión de
otra empresa, clave ausente— y ninguno llega a un 500, a una violación de FK ni a
una lectura cruzada.

## 5. Próximos pasos

1. **Quedan C y D** de la división de cuatro partes del taller. Nada de esta rama
   los bloquea, y la rama está lista para mergear en lo que a esta revisión
   respecta.
2. Si se toca el borrador otra vez, el candidato con mejor relación
   valor/esfuerzo es el **envío fallido**: hoy pierde lo tecleado desde la última
   pausa de dos segundos, y la salida está escrita en `CLAUDE.md` —el
   discriminador no es el código de estado sino **si el borrador sobrevivió**:
   capturar el cuerpo en el `submit` y, en el render siguiente, mirar si
   `#draft-stamp` volvió NO vacío—. Cuesta un write por envío rechazado y le da
   significado semántico a «el sello está vacío», que hoy es sólo presentación.
3. Antes de cualquier `make screens`, decidir el proveedor a conciencia: el stack
   queda en **`anthropic`** y cada corrida factura. Los comandos están en la
   sección 2.
