# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Lee primero el `README.md`: tiene los seis módulos, la regla de mutación del
pipeline y las decisiones de infraestructura. Los `docs/*.md` (`tenancy`, `ai`,
`criteria`, `pipeline`) tienen el detalle. Esto es lo que no está ahí.

**El código va en inglés; los comentarios y los mensajes de commit, en
español.** Nombres de método, de variable, de clase y de archivo en inglés; lo
que explica el porqué, en español.

Ojo: hasta el 2026-09-23 esta línea decía que **el código** también iba en
español, y buena parte del repo se escribió así. Quedaron identificadores en
español repartidos —`chip_de_estado`, `paso_actual_del_setup`,
`marco_para_pedido_de_ia`, `estado_de`, una veintena de partials, los specs
enteros— y hasta una tabla (`challenge_gestores`) y un valor de rol
(`"gestor"`).

**Se quedan como están y no se renombran al pasar.** Está decidido: migrarlos
es mucho trabajo para lo que rinde, y hacerlo de a pedazos deja un mix peor que
el actual. La regla nueva rige para lo que se escribe de ahora en más, y nada
más que para eso.

**Lo que ya está en la base se queda, y lo nuevo va en inglés.**
`challenge_gestores` y el valor `"gestor"` de `memberships.role` no se tocan:
renombrarlos es una migración con cambio de datos que toca modelo, rutas,
policies, seeds, el CHECK de Postgres y las capturas, y no vale la pena por
prolijidad. Pero **toda tabla y toda columna nueva va en inglés**, sin
excepción — es donde el costo de arrepentirse es más alto.

## Comandos

Todo corre en Docker. Nunca `bundle exec` en el host.

```bash
make setup                                  # primera vez
make up / down / reup / rebuild             # stack (rebuild al agregar una gema)
make spec                                   # suite completa
make spec-file FILE=spec/requests/x_spec.rb
make spec-line FILE=spec/requests/x_spec.rb LINE=42
make screens                                # recorrido E2E con Playwright
make embeddings                             # calcula los vectores que falten
make yarn-build                             # recompilar JS/CSS
make rails / psql / logs-app / logs-sidekiq
```

**Los specs corren en `app_test`, no en `app`.** `make spec` usa
`docker compose --profile test run --rm app_test`. Correr `docker compose exec
app bundle exec rspec` usa el contenedor de **desarrollo**: `RAILS_ENV` queda en
`development`, `config.hosts` trae los defaults de dev y **todos los request
specs devuelven 403 «Blocked hosts: www.example.com»**. Se ve como si la app
estuviera rota. Usá siempre `make spec*`.

Para bajar el contenedor de test: `docker compose --profile test stop app_test`.
`docker compose --profile test down` se lleva puesto el stack entero, base
incluida.

No hay linter configurado.

## Verificación

**`make screens` es la verificación end-to-end real**, no un extra. Recorre la
app corriendo con un navegador y falla si hay error de JS, HTTP >= 400, si
queda un `.island-placeholder` sin montar o si un elemento se quedó **sin
ninguna regla detrás** (`[CLASES]`) —una clase que Tailwind no vio al escanear,
pero también un `.card` o el punto del drawer que perdió la regla que lo
pintaba por un renombre o por un token roto, o un `.panel` reintroducido: la
clase ya no tiene ninguna regla en la hoja, así que un elemento con esa clase
sola queda sin fondo, sin relleno y sin borde, y eso es justo lo que esto
caza; eso se revisa en todas las pantallas del recorrido, no en algunas: vive
en `capturar()`—.

**Pero `[CLASES]` mira una lista FIJA de familias de componentes**
—`[class*="badge"]`, `[class*="btn"]`, `[class*="alert"]`, el punto del drawer,
`.steps`, `.panel`, `.card`, `.page-banner`, `.app-rail__item` y las celdas de
`.table`—, así que **un elemento hecho sólo de utilidades de Tailwind es
invisible para ella**. Las dos últimas las sumó la ronda de arreglos de la
revisión final: sin `.page-banner` ahí, perder la regla entera de la banda dejaba
al `h1` heredando `--text` sobre `--surface` —unos 17:1—, así que `[BANDA]`
seguía verde, el conteo seguía en 71 y nadie se enteraba. `.theme-switch__btn` no
hace falta: ya entra por la subcadena de `[class*="btn"]`. La tarjeta del QR del
check-in (`.bg-white.p-4.rounded-box.w-60`) no matchea ninguna, y por eso
sobrevivió a SEIS corridas verdes sin que ninguna de sus cuatro clases existiera
en la hoja: el QR salía sin ancho —llenaba la tarjeta entera—, sin fondo blanco,
sin relleno y sin bordes. No des una pantalla por cubierta porque `[CLASES]` esté
en verde.

**Ni porque exista la captura: un bloque que sólo se dibuja con datos se
fotografía AUSENTE y da verde.** La sala de idear lista «Las ideas de tu mesa»
sólo si la mesa tiene alguna, y `taller-idear` no tenía ninguna idea sembrada,
así que la captura `25` retrataba el formulario y nada más — mientras la lista
de participación de cada idea salía al costado del título en vez de debajo
(`.field-list__item` es flex con `space-between` y, fuera de `.app-aside`, sin
`flex-wrap`: las cajitas de los nombres se pegan al borde derecho y aprietan el
título). Las cuatro clases de `people-list` sí tienen regla en la hoja, así que
`[CLASES]` no tenía nada que decir. Hoy el seed siembra ese borrador y la
captura mira además que ninguna `ul.people-list` cuelgue directo del
`li.field-list__item`.

**Y la causa de fondo de aquello: la hoja compilada vive SÓLO en el contenedor y
está gitignoreada** (`/app/assets/builds/*`; el layout linkea
`application-build-css`, que produce `yarn build:css`). **Si agregás clases de
Tailwind nuevas y no corrés `make yarn-build`, la app sirve la hoja anterior y
`make screens` valida en verde una pantalla distinta de la que escribiste.**
Medido: antes de compilar, `w-60`, `bg-white`, `p-4` y `rounded-box` aparecían
cero veces en la hoja. De rebote, «negro sobre blanco en los dos temas» —de lo
que depende que un QR se escanee en tema oscuro— nunca fue cierto en la app
servida. Después de tocar vistas con utilidades nuevas: `make yarn-build` y recién
ahí `make screens`.

**Y lo mismo vale para el JavaScript, que es la mitad que esta nota no decía y
costó caer dos veces en la misma sesión.** `app/assets/builds/*` está gitignoreado
entero: ahí viven la hoja Y el bundle (`application-build.js`, que arma esbuild
con `yarn build`). **Un archivo `.js` nuevo importado desde `application.js` no
existe para el navegador hasta que corras `make yarn-build`.** Pasó con
`llegada_en_vivo.js`: la suite daba 1558 ejemplos en verde, el bundle no tenía una
sola referencia al archivo, y el recorrido reportó que la lista NO se refrescaba —
la guarda `[LIVE]` cazó una feature que no funcionaba mientras catorce ejemplos
decían que sí. La regla corta: **tocaste `app/javascript/` o agregaste utilidades
de Tailwind → `make yarn-build` ANTES de `make screens`.** Si no, el recorrido
valida una app que no es la que escribiste, y lo hace en verde.

Dos cosas más de esa corrida, para leer bien su salida. La línea final dice «N
errores de página» pero imprime el contador GLOBAL de fallas
(`capture_screens.js:3125`), así que una guarda que falla aparece ahí aunque no
haya ningún error de JS ni respuesta >= 400: no busques un error de página que no
existe. Y una guarda nueva **se prueba contra un baseline que funciona**: la
primera mutación de `[LIVE]` corrió sobre el bundle viejo, donde el estado sano y
el mutado daban el MISMO `{"n":0}`, así que no probó nada — una mutación sólo
discrimina si la corrida limpia pasa. También falla si un `.badge` o un `.alert` mide menos de
4,5:1 de contraste en claro o en oscuro (`[CONTRASTE]`, en cada pantalla y en
el muestrario), si un punto de estado del drawer mide menos de 3:1 —el piso de
WCAG 1.4.11 para lo que no es texto— (`[PUNTOS]`, en los dos temas), si el chip
de estado del desafío no llega a 4,5:1 sobre el panel del drawer
(`[ESTADO-DRAWER]`): ahí el estado también es un chip, y su color lo tiene que
corregir la hoja a mano porque `badge-soft` neutro pinta con `base-content`,
que en tema claro es casi el mismo casi-negro que el panel —sin corregir mide
1:1—. La guarda le pone cada variante al chip que ya está en el panel, porque
toda la validez de esa medición está en la superficie y el muestrario inyecta
en una tarjeta; qué variantes existen lo ata al enum un spec de Ruby. O si
aparece un `card` sin `card-body` (`[PANEL]`): las tarjetas de la app son
`card` + `card-body` en todas partes, y un `card` sin su `card-body` es un
error de maquetado. O si un `card-body` no tiene el relleno que fija la hoja
(`[RELLENO]`): DaisyUI sirve `padding: var(--card-p, 1.5rem)`, así que perder
la regla `.card` le devuelve sus 24px por default sin dejar rastro en el DOM;
los `empty-state` se exceptúan por selector, porque ahí los 44px/20px los
declara la hoja.

**Cinco guardas más llegaron con el rediseño INNK.** `[TEMA]` prueba que elegir
el tema a mano no mató el automático: con el sistema en oscuro elige «Claro»
—tiene que ganar— y después «Auto» —tiene que devolver el oscuro del sistema—,
midiendo el fondo computado del `<body>` y no el atributo, que es la causa y no
el efecto. Corre en dos pantallas y la que importa es la CON sesión: el login
no carga Turbo, así que ahí el POST es una recarga entera y el atributo se
aplica solo; en la app, en cambio, Turbo morfea el body y del `<html>` sólo
sincroniza `lang` y `dir`, así que el `data-theme` se quedaría con el valor
viejo —el botón se ilumina, porque está en el body, y los colores no se mueven
hasta recargar—. **Lo que contesta eso es el `form: { data: { turbo: false } }`
de los tres botones** (`shared/_theme_switch`): con él el PATCH es una recarga
completa y el servidor sigue siendo quien escribe el atributo, sin parpadeo.
Parece prolijidad y es lo único que hace andar el control adentro de la app, así
que **no lo «limpies»** — y si se pierde, `[TEMA]` es lo único que se entera.
Los specs de request no pueden: piden el atributo en el HTML servido, o sea la
causa, y lo que se rompe es el efecto en el navegador. No tiene piso: falla si
no midió las dos.
`[RIEL]` mira el riel de navegación global —la columna de íconos que vive
afuera de `.app-shell`—: que exista, que tenga al menos dos entradas (todo rol
ve Desafíos y Talleres), que marque **exactamente una** activa y, sobre todo, que
abajo de 1024px se vuelva fila en vez de esconderse. Lo de «exactamente una» es
de la ronda de arreglos de la revisión final: antes sólo fallaba con más de una,
así que **cero activas daba verde**, que es justo lo que pasaba en `step_tests` y
`previews` —dos pantallas que están adentro de Desafíos y faltaban en la lista de
`controller_name`—: cinco iconos grises y nadie avisando. Hay **una** excepción
declarada por nombre de captura (`SIN_ENTRADA_ACTIVA`, hoy sólo `09-13-avisos`):
`/notifications` es global y no es ninguna de las cinco secciones del riel, así
que no tiene qué marcar. Sumar una pantalla a esa lista es una decisión, no un
arreglo. Eso último se mide a **1000px** y no a 1100, porque el corte
de la hoja es `max-width: 1023px` y a 1100 el riel todavía es vertical por
diseño.
`[BANDA]` caza la vista que se olvidó el `content_for :banda` en una mudanza de
veintiséis vistas, que es donde más fácil se cuela una, y de paso mide el
contraste del título sobre la banda (6,06:1 hoy; `[CONTRASTE]` sólo mira
`.badge` y `.alert`, así que nadie más lo vigila).
`[SOMBRA]` falla si una `card` o un campo visible y sin foco se quedó sin
`box-shadow`, y mide en los DOS esquemas, porque `capturar()` corre también en
las pantallas oscuras. Existe porque la sombra dejó de ser decorativa: en tema
claro el borde de la tarjeta es transparente y la sombra es lo único que la
define.
`[CAMPO]` compone el borde en reposo de un campo sobre el primer fondo opaco
que tenga detrás —y **sólo si ese borde tiene ancho**: con `border-style: none`
el ancho computa 0 pero `borderTopColor` sigue devolviendo `currentColor`, o sea
`--text`, que sobre blanco mide ~17:1, y la guarda daba VERDE con el campo sin
ningún contorno, que es exactamente la regresión para la que existe; sin ancho el
borde ES el fondo y mide 1,00:1— y exige 3:1 —el 1.4.11 de WCAG, el mismo piso de `[PUNTOS]`—,
**sólo en claro**, y no porque en oscuro no importe: ahí el campo conserva el
`--borde` de siempre, que mide 1,13:1, y eso es deuda anterior a esta rama y
fuera de su alcance (queda anotada abajo, con las superficies). Extender
`[CAMPO]` a oscuro «total allá es cosmético» pone en rojo todas las pantallas el
primer día. Lo cosmético en oscuro es perder la SOMBRA, que es el motivo de
`[SOMBRA]` y no el de éste.

**Once de las guardas cuentan cuánto midieron y fallan si midieron de menos**
—en cuántas pantallas `[RITMO]` encontró dos tarjetas que comparar, cuántos
`card-body` vio `[RELLENO]`, cuántos chips y avisos midió `[PASTILLA]`, cuántos
nombres de criterio `[CRITERIO]`, en cuántas pantallas vio `[LIVE]` refrescarse
sola la mesa de llegada, en cuántas hubo riel (`[RIEL]`) y banda (`[BANDA]`),
cuántas tarjetas (`[SOMBRA]`) y cuántos campos (`[CAMPO]`) midió, y cuántas
caras de la sala (`[DRAFT]`) vio recuperar lo tecleado y en cuántas (`[GRABAR]`)
vio grabar, subir y transcribir—, porque una
guarda que mide cero da verde y es indistinguible de una que funciona: es el
mismo motivo por el que `[MONO]` tiene autotest y por el que el muestrario falla
si mide menos muestras de las que declara. La corrida imprime los once números
en una sola línea al terminar, y los pisos de hoy son 36, 250, 300, 100, «al
menos una», 66, 71, 275, 270, 2 y 2, en ese orden.
**`PISO_DE_BANDAS` es EXACTO y los demás van con holgura** —con dos excepciones
más, `[DRAFT]` y `[GRABAR]`, que siguen más abajo—, y la diferencia tiene motivo. Los
demás cuentan cosas que se mueven —tarjetas, chips y campos con los datos; el
riel, con las pantallas que podrían sumarse— y necesitan margen; `[BANDA]`
cuenta VISTAS que publican `content_for :banda`, que es un número fijo, y
lo único que esa guarda existe para cazar es la vista olvidada.
Con un piso flojo no la caza: borrar el `content_for` de una sola bajaba el
conteo (63 → 60, medido) y un piso al 92% no se enteraba. El precio es que
sumar una pantalla con banda obliga a subir el piso con ella.
**El piso de `[DRAFT]` también es EXACTO (2), por un motivo del mismo tipo pero
no el mismo:** `[BANDA]` cuenta vistas, un número fijo; `[DRAFT]` cuenta las dos
caras de la sala —idear y evolución— y no hay una tercera, así que un piso flojo
no cazaría que una dejó de medirse.
**El piso de `[GRABAR]` también es EXACTO (2), por el mismo motivo que el de
`[DRAFT]`:** cuenta las dos caras de la sala que graban —idear y evolución— y no
hay una tercera, así que un piso flojo no cazaría que una dejó de medirse (medido
en la mutación que comenta una de las dos llamadas: cae de 2 a 1 y falla).
**Y `[PASTILLA]` crece sola entre corridas sobre la misma siembra** —unos 4
chips por vez (medido: 677 → 689 en cuatro corridas), y vuelve a bajar al
resembrar—, porque el recorrido le pide cosas a la IA de verdad y después
fotografía `/admin/ai_runs`: cada corrida deja runs nuevos con su chip. Hoy es
inofensivo porque `PISO_DE_PASTILLAS` es un **piso** y no un techo. Es el mismo
patrón que Lucía Llegada en el seed: el recorrido deja datos que ninguna siembra
produce.
Falla si la mesa de llegada de un taller con el check-in abierto no se
refresca sola en el tiempo que declara su intervalo (`[LIVE]`): el frame, el
temporizador y el endpoint pueden estar cada uno en verde y la lista quedarse
quieta, y sólo un navegador corriendo lo ve.
Falla si lo que la mesa teclea en la sala no vuelve tras recargar (`[DRAFT]`):
tipea en las dos caras, espera el debounce del autoguardado, **recarga** y mira
que el texto esté. La recarga es el punto: sin ella la guarda probaría que el
navegador conserva lo que acabás de escribir, que es cierto sin autoguardado. Es
lo único que ve el camino completo —el bundle, el temporizador y el endpoint
pueden estar los tres en verde y el texto no volver—. **Mide todos los campos
del formulario y no el primero**, con un piso de 2 campos por cara: con uno solo
no podría cazar que el JS mande sólo el campo que cambió, que es la invariante
que todo el borrador protege: sin ese piso, bajar el seed a un campo tipeable
dejaría la verificación midiendo uno y en silencio; con él, falla a los
gritos. Está probada con dos mutaciones que fallan
distinto: rompiendo el JS fallan las dos caras; rompiendo el prellenado del
servidor de UNA sola cara falla esa y no la otra, que es lo que prueba que mide
cada una por separado.
**Y mide una TERCERA fase, que es lo único del repo que mira el camino de FALLO
del autoguardado.** Después de la ida y vuelta intercepta el PATCH, lo contesta
con un **200 pelado** y exige que el sello diga el texto de fallo. El 200 es el
punto: el endpoint sólo contesta 204, y el JS exige exactamente eso y no
`res.ok`, porque un `before_action` que redirige —sesión caída, membresía
revocada— le llega al `fetch` como 200: el `fetch` sigue el 302 y convierte el
PATCH en GET, así que la pantalla de login satisface `res.ok`. Con `!res.ok` el
sello diría «Guardado ahora.» cada dos segundos sobre un guardado que nunca
ocurrió, y la mesa pierde todo al mandar. Ese bug es **silencioso por
construcción**, así que no alcanza con que el servidor conteste bien —eso ya lo
fijan los request specs—: hace falta un navegador que lea la respuesta, y no hay
infra de test de JavaScript en el repo. Medido: con `!res.ok` fallan las dos
caras y `[DRAFT]` cae de 2 a **0**. La fase va al final a propósito —la de éxito
ya dejó el borrador escrito y un guardado que falla no escribe nada, y
`guardar()` no restaura `sucio`, así que el texto de la fase de fallo no se va
después en el `keepalive` de `descargar()`—. Y **no suma un contador nuevo**:
una cara cuenta como medida sólo si pasaron las tres fases, porque
`PISO_DE_BORRADORES` es exacto en 2 por contar CARAS, y un contador aparte lo
volvería 4 y rompería esa semántica.

**La otra mitad de ese arreglo no la puede ver un navegador, y vive en un lint.**
El sello se sella con la versión que dice el CLIENTE —`_evolution.html.haml`
publica `draft_base`, `workshop_draft.js` lo lee de `dataset.draftBase` y lo
manda como `base_version_id`—, y de esos tres eslabones sólo el del servidor
tiene cobertura en runtime: los request specs mandan `base_version_id` a mano y
`[DRAFT]` no publica ninguna versión entre el render y el tipeo, así que con el
atributo o el envío borrados el sello cae a `current_version_id` y las dos
verificaciones siguen verdes. Lo cuida `spec/lint/sello_del_borrador_spec.rb`,
que compara contra el código SIN comentarios —los tres nombres aparecen también
en prosa— y tiene autotest del stripper, no de los patrones: de los patrones ya
se encargan los tres ejemplos, pero un stripper que devolviera el archivo entero
los dejaría pasando sobre la prosa, en silencio. **Caza la borradura de un
eslabón y no un cambio de lógica**; el discriminador de lógica es un ejemplo de
request —una versión real de OTRA idea de la misma empresa, que separa
`idea.versions.find_by` de `IdeaVersion.find_by`— y es el único de los 24 del
archivo que lo hace.
Ese piso de 2 campos mide hoy **2 de 2, sin margen**: el seed crea exactamente
dos (`titulo` y `descripcion`), así que la rama que falla por «pocos campos»
nunca corrió y su mensaje no está probado. Es un piso exacto contra una
degradación concreta —bajarle el seed a un campo tipeable, o cambiarle el
`field_type` a `titulo`, dejaría la verificación de «todos los campos» midiendo
uno y en silencio—, no cobertura.
Falla también si aparece monoespaciada donde no hay código
ni un identificador (`[MONO]`): el texto propio de un elemento mono tiene que
ser un identificador pelado —«v3», «reduccion_merma»—, y «veredicto por idea» o
«40%» no lo son; las superficies de código se exceptúan por selector, y el
detector tiene autotest porque después del arreglo no reporta nada en ninguna
pantalla, que es indistinguible de una guarda que quedó midiendo cero. Y falla
si una pantalla de módulo pierde su forma: sin
columna de referencia o sin los ajustes plegados (`[ZONAS]`), con el plegable
cerrándose solo al morfear (`[PLEGABLE]`), sin la fila desplegable del desglose
de evaluación (`[DESGLOSE]`) o sin el módulo salteado en el drawer y el mapa
del flujo (`[SALTEADO]`), o si la pantalla del taller no dibuja el QR del
check-in —medido: un código más chico que 150px, o que no salga cuadrado, no se
escanea—, no muestra su link, si falta el formulario público, o si quien escanea
no termina en la SALA con el aviso de espera de la mesa de llegada y el acuse
del escaneo (`[CHECKIN]`). Corrélo después de tocar vistas,
islas o CSS — un bug de Vue no lo atrapa ningún spec de Ruby (un
`__VUE_OPTIONS_API__` mal puesto dejó el builder en blanco y la suite en
verde).

**«Falla si hay HTTP >= 400» tiene una excepción, angosta a propósito.** Dos
pantallas se fotografían con un error encima aposta —el 403 de `19-forbidden`
y el 404 de `20-not-found`—, y sin una excepción declarada eso reventaría la
corrida. `shotConEstado` fija `estadoEsperado` antes de navegar; mientras está
puesto, sólo se perdona el DOCUMENTO PRINCIPAL de ESA navegación, y sólo si
responde exactamente con el estado declarado. Un asset o un `fetch` que
devuelva >= 400 en el medio no se perdona nunca, y si el documento principal
responde con otra cosa —un 200 donde se esperaba un 403, por ejemplo— sigue
fallando, con su propia guarda (`[ESTADO]`). Lo angosto es lo que sostiene la
regla: perdonar «>= 400» a secas la dejaría ciega para siempre.

Al escribir capturas nuevas en `script/capture_screens.js`:

- Navegá **por link**, no con `goto`. Turbo no dispara `DOMContentLoaded` al
  navegar por link; un `goto` monta la isla igual y esconde el bug.
- Después de un clic, esperá `waitForURL` o un selector — `networkidle` se
  calma antes de que Turbo ponga el body nuevo, y la captura sale de la
  pantalla anterior.
- Las islas exponen `data-island-mounted="true"` como señal determinista.
- **Una guarda que cuenta eventos tiene que arrancar con el paso anterior ya
  pintado, y hay que verla fallar.** La captura del camino `_top` cuenta
  `turbo:morph` para probar que el pedido refrescó la pantalla entera y no el
  marco. El clic anterior —«Listo»— también sale a `_top`, y su diálogo se
  saca en `turbo:submit-start`, o sea ANTES del morph: esperar a que el
  diálogo se detache deja esa navegación en vuelo y el contador registra ESE
  morph. La guarda pasaba igual apuntando el pedido al marco; se descubrió
  apuntándolo al marco a propósito, no leyéndola. Se espera una señal que
  sólo puede existir con la pantalla nueva pintada (que la propuesta aceptada
  se haya ido del panel).
- **Nunca apuntes una captura a un desafío que también se usa a mano.**
  `optimizacion-de-la-experiencia-de-onboarding` ni siquiera vive en
  `db/seeds.rb` —es dato real armado a mano—, así que un `goto` ahí revienta
  en cualquier entorno recién sembrado. `onboarding-remoto` sí está en el
  seed, y aun así compartirlo con pruebas manuales rompió la corrida dos
  veces en cuanto alguien le tocaba algo (`3e437d6`). `sin-formulario` existe
  **solo** para el recorrido —y esta rama reintrodujo el antipatrón de todas
  formas, dos veces (`04f2d00`, y de nuevo en la Task 11 antes de que la
  revisión lo cortara)—. Hoy siembra los seis `kind` pendientes y un set de
  criterios inline en su módulo de selección (`db/seeds.rb:360` en
  adelante), del que dependen varias capturas de las dos caras.
  `con-salteado` existe sólo para la captura del módulo salteado
  (`02b-salteado`). `comite-abierto` existe sólo para `21-evaluar-idea`: es
  el único desafío sembrado que deja un módulo de evaluación **activo** —en
  `merma-bodega` el flujo corre entero y sus dos evaluaciones quedan
  `completed`, y en `con-salteado` lo activo es el módulo salteado, no uno
  de evaluación—, y sin uno activo ninguna fila ofrece «Evaluar».

**Los system specs con navegador no cubren el recorrido.** Los servicios usan
`with_lock` (SELECT FOR UPDATE) y eso deadlockea contra el pool compartido de
Rails: el spec se **cuelga sin dar error**. Anotado en
`spec/system/smoke_spec.rb`. Los system specs existentes borran todo en un
`after`; si agregás uno, hacé lo mismo o dejás datos que ensucian corridas
posteriores.

`spec/system_support/driver.rb` se requiere **solo desde los system specs**:
cargar Capybara globalmente cuelga la suite entera.

**Nunca `click_link` a secas en un system spec.** Turbo pinta la copia cacheada
de una página mientras pide la definitiva; si el clic cae en esa ventana,
Capybara toma un elemento que Turbo está por reemplazar y Playwright falla con
«Element is not attached to the DOM». Usá `click_link_settled`
(`spec/system_support/turbo.rb`), que espera a que se vaya
`<html data-turbo-preview>`. El síntoma es una falla de una cada tres corridas
**solo con la suite completa** — en aislamiento pasa siempre.

## Arquitectura: lo que hay que leer junto

### El motor del pipeline

`app/lib/flow/pipeline.rb` es el corazón. `insertion_floor` implementa la regla
dura del producto (con el flujo en curso solo se inserta después del último
módulo tocado; `skipped` cuenta como tocado). La regla vive acá **y** replicada
como validación de modelo, y el builder solo la dibuja.

`Flow::Handlers::Base.for(step)` despacha por `kind` a los seis handlers.
`activate!` y `complete!` son idempotentes; toda mutación va con
`challenge.with_lock` + `lock_version` optimista.

**La razón dice el porqué; el nombre del módulo lo pone `activate!`.** Las
razones de `can_activate?` no se nombran a sí mismas: `Base#activate!` es el
único lugar donde una negativa se vuelve excepción y arma «‹nombre› no está
listo para arrancar: ‹razones›». Nombrarse en la razón lo duplicaba, y
`Evaluation` —cuyos motivos salen de `CriteriaSet#validation_errors` y no
saben de módulos— no lo decía con dos evaluaciones en el flujo.

**Late binding:** `step.config` guarda la intención, `resolved_config` se
escribe una sola vez en `activate!` con ids concretos. Leé siempre
`step.settings` — es el único accesor público y devuelve el resuelto si el
módulo ya arrancó.

**Qué se congela al arrancar** (`ChallengeStep::FROZEN_ATTRIBUTES`): `kind`,
`slug`, `position`, `config`, `source_step_id` y los criterios.
**Qué sigue ajustable** (`ADJUSTABLE_ATTRIBUTES`): `name` y `ai_mode`. Cambiar
el modo de IA de un módulo en curso es una política operativa, no una reescritura
del pasado.

Las referencias entre módulos van **por `slug`**, no por posición: la posición
es mutable por diseño (`decimal(20,10)`, insertar entre A y B es `(a+b)/2`).

### Los tres esquemas de configuración

Son fuente única: la UI los renderiza, no declara campos propios. Agregar una
opción es agregar una línea al esquema, sin tocar Vue.

| Archivo | Qué declara | Quién lo consume |
|---|---|---|
| `Flow::StepSettings` | Qué configura cada `kind` de módulo | la cara de configuración (isla `step-settings`), el resumen congelado de la cara de ejecución (`_config_congelada`, `steps/selection`) y el schema con el que la IA propone un flujo (`json_schema`, en `ProposePipeline`) |
| `Flow::CriterionSettings` | Qué parámetros pide cada verificación y cada escala | editor de criterios |
| `Flow::FlowTemplates` | Puntos de partida del flujo | creación del desafío y builder vacío |

**En `config` un hueco no es «sin valor»: es el default del esquema.** Sólo
`Api::V1::PipelinesController#create_added` siembra `StepSettings.defaults`;
`Flow::FlowTemplates` manda configs PARCIALES y `db/seeds.rb` no manda ninguna,
así que los dos caminos normales dejan claves ausentes — y los handlers leen
con `fetch(clave, default)`, o sea que el módulo corre con el default igual.
Mostrar la ausencia como ausencia dejaba la tarjeta «Cómo quedó configurado» de
evolución y de reportería **entera vacía**: encabezado, aviso del candado y un
`<ul>` sin una sola fila, que es el mismo control fantasma que esta rama existe
para sacar. Se lee con `StepSettings.efectivo(kind, settings)` y se filtra con
`StepSettings.visible?`, que espeja el `depends_on` de `config_field.vue` (con
la regla de corte en «manual», «Valor del corte» no describe nada). Ojo con la
suite: el fixture que probaba esa tarjeta ponía `config:` a mano en los seis
kinds, que es justo el caso que no ocurre en la práctica.

**Todo `config` que llega de afuera pasa por `StepSettings.filtrar`**, venga
de un formulario (`steps#update`) o de un modelo (`ProposePipeline#apply!`).
El JSON Schema de la tarea no alcanza: localmente no cierra los objetos, y una
sugerencia editada a mano o un fixture pueden traer cualquier clave. Y el
filtro no avisa: una clave mal escrita se descarta y el módulo corre con el
default. El fixture de `propose_pipeline` mandaba `cut_mode` plano —nadie lo
lee, la clave es `cut.mode`— y «Corte a top 10» nacía con el corte en manual;
la guarda está en `spec/lib/flow/ai/fixtures_spec.rb`.

**Y el modelo sólo puede proponer las claves que el schema declara.** El
adapter de Anthropic cierra todo objeto con `additionalProperties: false`, así
que un `config` declarado `object` a secas le llegaba a la API como un objeto
donde no entra ninguna clave: con el proveedor real la propuesta nunca traía
configuración. `StepSettings.json_schema(kind)` arma una variante por kind (un
`anyOf` con `kind` como `const`), sin los campos `column:` ni los `source:`
—eligen módulos que al proponer todavía no existen—, y pone en la descripción
el rango y lo que significa cada valor: es lo único que el modelo ve, porque
la API poda `minimum`/`maximum`.

### Criterios: dos ejes independientes

`source` (quién produce el valor: `manual` / `automatic` / `ai` / `formula`) y
`scale_type` (qué forma tiene: `numeric` / `letter` / `rubric` / `boolean`).
**El origen manda cuando determina la forma**: `align_scale_with_source` fuerza
`boolean` para automático y `numeric` para fórmula, así que el editor ni ofrece
la opción.

Toda escala aterriza en `[0,1]`. Las fórmulas van por dentaku, **nunca** `eval`.

Un `criteria_set` con `scope: "library"` se comparte entre desafíos; uno
`inline` es de un módulo. Editar un set de biblioteca desde un módulo tocaría
todos los desafíos que lo usan — por eso se copia (`StepCriteriaController`).

**La biblioteca no se pisa: se versiona.** Guardar un set de biblioteca que ya
usa algún módulo crea la versión siguiente (`family_id`, `version`,
`superseded_at`) y deja la anterior intacta; los módulos que la usaban siguen
con ella hasta que alguien los pase a la nueva **desde la pantalla del
módulo**. Un set que no usa nadie se edita en el lugar: versionar lo que nadie
tiene asignado no protege a nadie.

**Elegir un set de la biblioteca y pasar un módulo a la versión nueva son dos
controles de la cara de configuración**, en el bloque de criterios
(`steps/_criterios_editor.html.haml`, detrás del mismo `configure?` que el
resto). Ninguno tiene endpoint propio: los dos escriben `criteria_set_id` por
`PATCH steps#update`, que es el único camino de escritura de la configuración
de un módulo. `CriteriaSet.asignables_para` arma las opciones (la vigente de
cada familia, más la que el módulo tenga puesta aunque ya no lo sea) y
`CriteriaSet#newer_version` dice si hay una más nueva. Los dos vivían en el
panel del builder (`step_config.vue`) y se perdieron al borrarlo (`58bd076`):
durante esa ventana **nada** podía apuntar un módulo a la biblioteca —el único
escritor era la copia `inline` de `StepCriteriaController#create`— mientras dos
textos de la app seguían instruyendo a hacerlo (`Flow::Pipeline#validate`,
`CriteriaSetPresenter#version_notice`). Volvieron en HAML y no en la isla: el
builder es dueño del armado, no de la configuración.

**Con criterios propios no hay vuelta a la biblioteca.** Los dos controles
aparecen solo mientras el módulo no tiene un set `inline` (el `set.nil?` del
partial): en cuanto copia uno o empieza en blanco, desaparecen. «Guardarlos
también en la biblioteca» (`promote_to_library!`) no es el camino de vuelta:
crea una copia en la biblioteca y deja al módulo con la suya. Es paridad
exacta con el panel del builder que se borró, no una regresión. La regla es de
la pantalla y no del modelo —`criteria_set_belongs_to_challenge` acepta
cualquier set de biblioteca—, así que abrir la vuelta sería solo de vista.

Esto reemplaza al candado por evaluaciones **solo en la biblioteca**: sobre una
versión nueva nadie puntuó nada, así que peso y escala vuelven a ser editables.
En un set `inline` no hay a quién proteger copiando, y el candado sigue siendo
la respuesta (`locked?` en `Api::V1::CriteriaSetsController`).

Dos trampas: el fork va **dentro** de la transacción del guardado (si falla, no
queda una versión huérfana), y los criterios que llegan traen los ids de la
versión anterior — `fork_version!` los traduce por `key` a los de la copia, o
la reconciliación borraría todo y lo crearía de nuevo.

### Los cuatro roles

`admin` administra · `gestor` administra los desafíos que le asignaron ·
`evaluator` evalúa lo que se le asigna · `participant` postula y comenta.
`owner` **no existe**: daba los mismos permisos que `admin`.

Dos reglas que no viven en el rol:

- **Evaluar depende de la asignación**, no del rol (`step_assignments`). Y
  **nadie evalúa una idea de la que participa**, ni siquiera quien administra.
  Por eso el mínimo de evaluaciones baja por idea cuando su autor está entre
  quienes evalúan: esperar el mínimo entero trabaría el módulo esperando una
  evaluación imposible. El link «Evaluar» de cada fila pregunta la misma policy
  que autoriza el controller —`policy(Assessment.new(challenge_step:, idea:))`—
  y no `step.active?` a secas: con eso lo veía en todas las filas quien evalúa
  sin asignación en ese módulo, y quien acompaña el desafío, que no es
  `manager?`. Los dos se comían un 403 al apretarlo.
- **No todas las voces pesan igual.** `step_assignments.weight` entra en el
  agregado, en la dispersión y en el promedio por criterio. Dos reglas que no
  se ven en el código si no se buscan: los pesos **solo** entran cuando alguien
  puso pesos distintos (con todos iguales la mediana ponderada no devuelve lo
  mismo que la mediana de siempre, y asignar gente sin tocar pesos no puede
  mover un puntaje ya calculado); y **cambiar un peso recalcula todas las
  entries del módulo**, porque si no la tabla sigue mostrando el número viejo.
  Quien ya evaluó no se desasigna —su nota quedaría sin respaldo—, y con el
  módulo cerrado no se toca nada.
- **Quien participa ve solo las ideas en las que participa** —las que creó y
  aquellas en las que colabora—: compite por el mismo corte que las demás. La
  regla vive UNA vez, en `IdeaPolicy::Scope`, y las pantallas la aplican:
  `StepsController#show` publica `@ideas_visibles` y los módulos filtran con
  eso lo que listan. Idear se lo olvidó hasta el plan 2b —listaba todas las
  postuladas—, que es exactamente lo que advertía `e3787a3`. Lo que no se ve
  da **404**, no 403. Quien administra, acompaña o evalúa las ve todas: las
  tres cosas se hacen sobre el pool entero. En reportería, quien participa ve
  lo agregado —embudo, distribución, participación— y el ranking y la matriz
  filtrados a sus ideas; el resumen narrativo no, porque nombra ideas ajenas.
  Hasta el plan 2b veía el tablero entero. Y en selección **son dos listas, no
  una**: el ranking y el registro de decisiones; el registro se olvidó del
  filtro hasta la revisión final del 2b y listaba título, veredicto y puesto de
  cada idea ajena. Lo que ahí NO se filtra es quién decidió, cuándo y el motivo
  de la tanda: es lo que explica por qué la idea de uno avanzó o no.
- **Pedirle a la IA que evalúe no es evaluar.** El botón —y el lote «evaluar
  todas con IA»— es de quien evalúa en el módulo, por asignación o por
  administrarlo, no de `update_pipeline?`. Y va **sin idea**: quien participa
  de una idea no la puntúa, pero sí puede pedir que la IA la evalúe, porque la
  nota es de la IA. Bloquearlo trabaría el módulo, ya que `min_assessments_for`
  baja el mínimo contando a la IA justamente como quien evalúa lo que su autor
  no puede. La regla está en un solo lugar y las tres puertas la consultan
  (`AiSuggestionPolicy#evaluacion`, `AiRequestsController#autorizar!`,
  `StepsController#evaluate_all`).
  **Y por eso no se edita al aceptarla** (`Tasks::EvaluateIdea#editable?`):
  aceptar una propuesta pendiente admitía un payload editado, y quien evaluaba
  se ponía puntaje en su propia idea con el nombre de la IA encima. Ninguna
  pantalla edita un payload antes de aceptar; era una capacidad del dominio
  sin interfaz.
- **El puntaje y el desglose son cosas distintas.** Quien participa de una idea
  ve su resultado agregado cuando el módulo cierra; **quién puso qué** lo ven
  solo quien administra y quien evaluó esa idea. Por eso hay dos predicados en
  el handler (`score_visible_for?` y `breakdown_visible_for?`) y no uno.
- **El gestor es interempresa**: una membresía con rol `gestor` por cada
  empresa, igual que cualquiera que esté en más de una. Lo nuevo es que tener
  membresía dejó de significar ver todo: un gestor solo ve los desafíos de
  `challenge_gestores`. Se **asigna desde el módulo de evolución**, que es donde
  tiene algo que hacer —igual que los evaluadores se asignan desde el módulo de
  evaluación—, aunque el acceso que otorga es al desafío entero y la pantalla lo
  dice. La ficha del desafío solo lo ofrece si quedaron gestores sin módulo de
  evolución donde administrarlos. Por eso **los controllers buscan el desafío con
  `policy_scope(Challenge).find_by!`** y no con `Challenge.find_by!` — así lo
  no asignado da 404 y no 403, que sería un oráculo de existencia.
- **El gestor administra los desafíos que le asignaron.** Dentro de uno, puede
  lo mismo que quien administra la empresa: armarlo, arrancarlo, configurarlo,
  testear, avanzar, reportar, asignar, y trabajar sus ideas sin esperar una
  ronda de evolución. La regla es `ApplicationPolicy#administers?(challenge)`,
  que es `manager? || (gestor? && le asignaron ESE desafío)`.
  **`manager?` quedó significando «administra la empresa»** y es lo que protege
  lo que no cuelga de ningún desafío: las membresías, la auditoría de IA y la
  biblioteca de criterios. De rebote, una puerta nueva escrita con `manager?`
  nace cerrada para el gestor, que es el lado seguro; abrirla es una decisión
  que se toma, no un default.
  Dos cosas no se abrieron, y son de otro eje: **no postula ideas propias** ni
  **postula por el autor** (`IdeaPolicy#create?` y `#submit?`). Son conflicto
  de interés, no permisos. `submit?` es `update? && !assigned_gestor?`, así que sigue
  cerrado aunque `update?` se haya abierto — por eso `assigned_gestor?` se quedó
  aunque su otra rama murió.
  Y **crear** es la única puerta que no pregunta por la asignación: el desafío
  todavía no existe. Lo que la acota es que `ChallengesController#create`
  auto-asigna al gestor que lo crea, en la misma transacción que el `save`.
  El reparto entero se lee en `spec/policies/gestor_administra_spec.rb`, que
  existe porque **abrir un permiso de más no rompe ningún test**.

### El feedback pertenece a su ronda

`feedback_items.challenge_step_id` no es un dato de auditoría: es a qué
conversación pertenece el comentario. Un desafío puede tener varias rondas de
evolución, y mezclarlas hace que lo viejo se lea como lo que hay que atender
ahora.

- El tablero del módulo ya filtraba por su paso (`feedback_index`).
- La **ficha de la idea** agrupa por ronda: la que está en curso, abierta; las
  cerradas, en un `details` plegado —la historia no se esconde, pero plegada no
  se confunde—. Solo la ronda abierta ofrece cerrar comentarios, porque
  `puede_resolver` mira `step.active?`.
- **`evolve_idea` toma solo el feedback abierto de SU ronda.** Arrastrar lo que
  quedó sin atender en una ronda anterior mezcla dos conversaciones.

- El criterio automático **`feedback_addressed` mira solo la última ronda**. Un
  check no sabe en qué módulo lo están corriendo —solo tiene su `criterion`—,
  así que «la última» es la ronda más reciente que LE DIO feedback a esa idea:
  no se puede tener sin atender lo que nadie comentó. Mirando todas, lo que
  quedó abierto en una ronda vieja bloqueaba a la idea para siempre, porque
  nadie vuelve a cerrar comentarios de una conversación que ya terminó.

### El taller

Un taller es un **evento que abarca N desafíos**, no un módulo más del flujo.
El motor tiene un módulo activo por construcción (`Flow::Pipeline#active_step`)
y el taller se monta encima de la fase que cada desafío ya está corriendo: no
lo hace avanzar ni lo traba —nada se engancha en `advance!`—. Lo que ata el
taller al desafío es el MÓDULO (`workshop_challenges.challenge_step_id`),
resuelto al abrir con el mismo late binding del pipeline.

**La pantalla del taller ELIGE; la sala trabaja.** `workshops#show` es el
selector —una fila por vínculo con el nombre del desafío, su `brief` truncado y
«Entrar»— y el trabajo vive en una pantalla por vínculo:
`GET /workshops/:workshop_id/salas/:id` → `WorkshopRoomsController#show`
(`workshop_sala_path`). Antes apilaba un formulario por desafío, uno debajo del
otro y sin decir de qué trataba ninguno. Los dos POST no se movieron: el id de
esa ruta siempre fue el del VÍNCULO y no el del desafío, porque es el vínculo el
que sabe contra qué módulo se trabaja. Los vínculos no trabajables se listan
**con su motivo y sin botón**: una sala escondida no se distingue de una que
nunca existió, y entrar a una por URL renderiza el motivo y **no** 404 —el
vínculo existe y el selector lo lista, esconderlo ahí sería el oráculo al revés—.

**`Flow::Workshops::MaterializeClosures` corre en las DOS entradas**
—`workshops#show` y la sala—, en las dos **antes** de leer los vínculos. El
cierre es perezoso (nada se engancha en `advance!`) y entrar es justo lo que
hace que el taller se entere de que el desafío avanzó; sin eso la sala dibuja
trabajo sobre un módulo que ya cerró.

**Con una sola sala el taller redirige, y el breadcrumb de la sala pregunta lo
MISMO.** Si el taller manda a la sala, un link «volver al taller» rebota en
bucle: por eso la pregunta vive UNA vez, en
`Flow::Workshops::Rooms#redirects?`, y la consultan el redirect y el breadcrumb
(`spec/lib/flow/workshops/rooms_spec.rb`). Son **dos** condiciones y la segunda
no es la obvia: que quien mira no pueda armar el taller **y** que el taller
tenga un solo vínculo EN TOTAL (`links.one?`), no una sola sala trabajable. Con
dos vínculos donde uno cerró, redirigir dejaba la sala cerrada y su motivo sin
ningún camino —el breadcrumb, correctamente, no ofrece volver—, así que quien no
administra nunca se enteraba de que ese desafío estuvo en el taller: exactamente
lo que el selector existe para no hacer. `Rooms` expone sólo `links`,
`workable`, `only_room` y `redirects?`, y nada más a propósito, para que no se
vuelva el cajón de todo lo del taller.

**`workshops#show` conserva el flash al redirigir** (`flash.keep`), y es una
línea defensiva: medido, el aviso llega a la sala sin ella, porque esa rama no
instancia el flash —un `redirect_to` sin `notice:` no lo toca y no se renderiza
ninguna vista— y Rails sólo descarta las claves que se CARGARON. O sea que
sobrevive por accidente. Importa porque es la única cadena de DOS redirects de
la app (`POST /checkin/:token` → `workshops#show` → la sala) y un `flash.now`
agregado ahí mañana se llevaría puesto, en silencio, el único acuse del único
camino público que escribe datos del dominio. Ningún ejemplo puede distinguir
esa línea hoy: lo que fijan el spec del check-in y la captura `30b` es que el
aviso recorre la cadena entera.

**Las dos listas de ideas de la sala salen de fuentes distintas, y es lo primero
que un lector va a equivocar.** La cara de **idear** va por
`policy_scope(Idea)` —`status` en `draft` o `active`— con el filtro por
integrantes de la mesa **adentro** del scope, no en vez de él: el scope hace la
fuga imposible por construcción (un borrador creado en la sala nace con la mesa
entera como `idea_contributors`, así que cada integrante lo ve por
`IdeaPolicy::Scope`, y el borrador privado de alguien de afuera lo sigue viendo
sólo él), y el filtro es lo que impide que a quien el scope le devuelve `all`
—todo rol que no sea `participant`— le liste las ideas de OTRAS mesas bajo un
título que dice que son de ésta. La cara de **evolución** va por
`WorkshopGroup#workable_ideas`, que es la unión sobre los integrantes —«traé tu
idea y la mejoramos entre todos»— y ya excluye la llegada, lo eliminado y lo
retirado, y no trae borradores (`Idea.alive` es `status: "active"`). Y la
consulta de idear vive en el CONTROLLER a propósito:
`spec/lint/ideas_por_policy_scope_spec.rb` sólo mira controllers, así que
escondida en un presenter o en el HAML no la ve nadie.

**La sala no describe un desafío que quien mira no alcanza.** `work?` abre la
sala de CUALQUIER vínculo del taller, y a un gestor se la abre por
`administers_any?` —alcanza con que administre ALGUNO de los desafíos—, mientras
el vínculo se busca sin filtrar por asignación: entra a la sala de un desafío
que `GET /challenges/:id` le devuelve 404. El NOMBRE se muestra igual —ya se
mostraba, la pantalla vieja listaba uno por vínculo, y es lo que dice de qué
sala es ésta—; el link, el módulo con su fase y el `brief` van detrás de
`alcanza = policy(link.challenge).show?`, UNA variable calculada arriba del
partial y no el predicado repetido por bloque, en los dos lugares que lo dibujan
(`workshop_rooms/_referencia` y `workshops/_room_picker`). Lo que **no** se
gateó, a propósito: el `closed_reason` del selector, que nombra la fase del
desafío (`Flow::Workshops::Open.reason_for`). Es el motivo por el que esa sala
no se puede trabajar —información del taller, no sólo del desafío— y esconderlo
volvería muda la pantalla justo en lo que el selector existe para decir. En este
GET el 403 es inalcanzable: todo rol que `WorkshopPolicy::Scope` admite pasa
también `work?`, y quien no pasa el scope ya tuvo 404.

**Entrar a una mesa es un permiso por DESAFÍO, y es consecuencia directa del
párrafo de arriba.** `ChallengePolicy#enter_any_group?` —que es
`administers?(record)`— es lo que deja a quien administra un desafío trabajar
**cualquier** mesa de un taller que lo trabaja, sin ocupar un asiento. Por
desafío y **no** por taller (`WorkshopPolicy#update?` y `#work?`, que son los
dos `administers_any?`): si la sala ya le esconde a un gestor el `brief` de un
desafío que no le asignaron, dejarlo ESCRIBIR ahí sería abrir escritura sobre
algo que no puede leer.

**Y `alcanzables`, en las grabaciones, lo contradecía** —desde antes de la rama
que sumó esto—: abría el audio de la mesa con `policy(@workshop).update?`, o sea
`administers_any?`, un permiso por TALLER sobre contenido de UN desafío. Un
gestor del desafío A podía pedir por URL el audio grabado en la sala del desafío
B, con las voces de esa mesa adentro. Hoy pregunta `enter_any_group?` del
desafío del vínculo. **La otra línea de ese mismo método sigue con
`group_of(current_user)` a propósito**: a ese camino sólo llega quien no
administra, y quien no administra siempre está sentado.

**El predicado es NUEVO y no reusa `builder?` ni `curate_pool?`**, que hoy son
los dos exactamente `administers?(record)`. Reusar uno ahorra una línea y ata el
acceso a las mesas al significado de otra cosa: el día que alguien mueva
`curate_pool?`, esto se movería con él sin que nadie lo decida. Un nombre
prestado es cómo un permiso se ensancha en silencio.

**Las dos reglas del gestor con las ideas NO se abrieron, y no hizo falta
escribir nada para que se cumplan adentro de la sala.** `IdeaPolicy#create?` es
`membership.present? && !membership.gestor?`, y `submit?` es
`update? && !assigned_gestor?`: son conflicto de interés y no permisos —«Crear
borrador» deja a quien aprieta como AUTOR de una `Idea` que compite en un
proceso que el gestor administra, y el motivo pesa MÁS adentro de la sala que
afuera—. El formulario de idear ya vive detrás de `puede_crear`, que ES
`IdeaPolicy#create?`, así que un gestor que entra a una mesa ve las ideas, el
borrador, las propuestas, la grabación y las transcripciones, y **no** ve el
formulario. Un admin no toca ninguna de las dos: `create?` sólo excluye al
gestor y `submit?` sólo al gestor asignado.

**Un taller trabaja sobre una sola fase.** Se verifica en
`Flow::Workshops::Open` y no como validación de modelo: en borrador el vínculo
todavía no tiene `challenge_step`, así que la fase no existe y no hay con qué
comparar. La verificación cuenta los `kind` distintos entre los vínculos que
van a quedar abiertos y, si hay dos, **nombra qué desafío está en cuál fase**
—«el taller mezcla fases» sin los nombres deja a quien lo lee abriendo los
desafíos de a uno—. Y va **antes de escribir nada**: rechazar después de cerrar
vínculos dejaría el taller a medio abrir hasta que el rollback lo deshaga, y el
motivo se leería sobre un estado que ya no existe.

**`Workshop#phase` se deriva de los vínculos abiertos, no se guarda.** Una
columna sería la segunda fuente que el día que difiera de los vínculos miente.

**Y un taller abierto puede no tener NINGUNA fase: ahí está la trampa.**
`Flow::Workshops::MaterializeClosures` cierra los vínculos vencidos de a uno y
**nunca** cierra el taller —`Close` sí cierra los dos—, así que «abierto con
todos sus vínculos cerrados» es un estado que la app produce sola.
`Flow::Workshops::AssignGroups` lo rechaza con su propio mensaje y
`puede_repartir` pregunta lo mismo. Sin esa guarda el ternario caía en la rama
de idear y `participant_ids` sentaba a **todos los `participant` de la
empresa**, a ninguno de los cuales convocó nadie.

**Idear no es otro algoritmo: es el mismo con grupos de una persona.**
`AssignGroups` arma la entrada según la fase —en evolución un grupo por idea
con su gente, en idear uno por persona— y `Flow::Workshops::Seating` hace el
reparto sin tocar la base: recibe grupos indivisibles y un tamaño, y devuelve
mesas más lo que tuvo que desprender. «Indivisibles» tiene una excepción, y es
la única: un grupo más grande que el tamaño no tiene frontera por donde
cortar, así que se parte su gente y el aviso sale con `inside: true`.

**La columna se llama `attended` y no `present`.** En Rails una columna
`present` genera `present?`, que choca con `Object#present?` de ActiveSupport,
y el choque no revienta: devuelve otra cosa, que es la peor forma de romperse.
El default es `true` porque el primer reparto sienta al pool completo y marcar
ausentes es la excepción. Cuelga de la membresía de la mesa y no de un padrón
aparte: estar convocado ES estar en una mesa, y dos fuentes para «quién está en
este taller» divergen.

**La presencia se escribe de dos formas, y el taller declara cuál vale.**
`workshops.attendance_mode` es `presumed` —lo de siempre: el reparto sienta al
pool completo y marcar ausentes es la excepción— o `registered`, y ahí la
presencia la escribe alguien: el check-in por link (`WorkshopCheckinsController`,
la ÚNICA ruta pública que escribe datos del dominio sin que nadie haya probado
quién es: el login también se sirve sin sesión, pero elige la empresa entre las
membresías de alguien que ya se autenticó con su clave, mientras que ésta la
resuelve desde un token que cualquiera con el link tiene) o el toggle de cada
integrante (`WorkshopAttendancesController`). Con `registered`, convocar a mano
deja el asiento AUSENTE y el pool de idear deja de incluir a los `participant`
de la empresa — sin eso el escaneo es decorativo, porque el pool automático
sienta igual a quien no vino.

**El token y el modo son dos cosas.** `checkin_token` es la credencial y
`attendance_mode` la semántica: si el modo se derivara del token, rotarlo para
revocar un link filtrado devolvería la asistencia a presumida en medio de la
sesión. Rotar revoca; apagar el modo cambia cómo se cuenta.

**La «Mesa de llegada» (`workshop_groups.arrival`, con índice UNIQUE parcial)
es sala de espera, y todo lugar que se negaría a dejar trabajar desde ella
pregunta `arrival?`** —el bloque de armado la pregunta además por otras razones:
no se borra a mano, y se sirve en el frame que se refresca solo—. No hay un
número acá a propósito: una lista se verifica con un `grep -rn "arrival?" app` y
un número no, y éste ya se desactualizó dos veces. Los lugares, agrupados por lo
que el chequeo HACE:

- **Los controllers que rechazan una escritura** (`403` o rechazo con aviso):
  `WorkshopIdeasController`, `WorkshopProposalsController`,
  `WorkshopDraftsController` y `WorkshopRecordingsController`.
- **Las dos caras de la sala**, que en vez del trabajo dicen que la mesa todavía
  no se armó: `workshop_rooms/_ideation` y `workshop_rooms/_evolution`.
- **La negativa a BORRAR la llegada** —no a trabajar desde ella—:
  `WorkshopGroupsController#destroy` (`workshop_groups_controller.rb:25`, redirige
  con aviso: la llegada se va sola cuando el reparto la vacía).
- **El panel «Tu mesa»**: `workshops/_my_group`.
- **Las lecturas que devuelven nada**: `WorkshopGroup#workable_ideas`
  (`Idea.none`) y, en `WorkshopRoomsController`, `load_ideation`,
  `load_recordings` y las dos cargas del borrador (la de idear y la de evolución).

`load_ideation` es **load-bearing** y no prolijidad: `policy_scope(Idea)` devuelve
`all` a todo rol que no sea `participant`, así que sin ella quien administra y
está sentado en la llegada vería las ideas de los treinta que esperan, bajo el
título «Las ideas de tu mesa». Del lado de la escritura,
`WorkshopIdeasController` escribe `idea_contributors` para toda la mesa, así que
un borrador creado desde una llegada de treinta personas nace con las treinta
ESCRITAS y repartir no lo deshace. Y `AssignGroups#seat!` la excluye de las
mesas reusables: es la primera creada, así que la habría convertido en «Mesa 1»
con `arrival: true` puesto y su sala habría quedado muda para siempre.

**Ojo: hasta el 2026-10-08 esta línea decía «siete», y la lista no nombraba al
autoguardado del borrador** (`WorkshopDraftsController`), que ya preguntaba lo
mismo: el conteo estaba corto antes de que la grabación sumara el suyo, y es la
evidencia de por qué no hay número. Dos comentarios del código repiten un número
viejo —«los otros seis lugares» en `workshop_drafts_controller.rb` y en
`workshop_rooms/_ideation`, más «el octavo lugar» en
`spec/requests/pantalla_de_la_sala_grabacion_spec.rb`—, y la revisión final de
la rama los pasó a remitir acá, que es lo que ya hacía el controller de
grabaciones: **en el código no queda ningún número.** Quien agregue un lugar
nuevo lo suma a la lista del grupo que corresponda a lo que su chequeo hace.

**«Mi mesa en este taller» vive en `Workshop#group_of`, y en ningún otro lado.**
Estaba escrito tres veces —el `group_of` privado de los dos controllers que
escriben y el `@my_group` de `workshops#show`— y la sala habría sido la cuarta
copia. La trampa, que es el arreglo que cualquiera va a intentar:
**`includes(workshop_group_members: :user)` NO puede ir adentro de ese
método.** Su `find_by` filtra por `workshop_group_members.user_id`, así que
Rails pasa de `joins` a `eager_load` y la asociación queda cargada con SÓLO el
asiento de quien mira: el panel listaría una persona en vez de la mesa, y todos
los specs del panel seguirían verdes porque miran a quien está logueado. La
precarga va en el punto de uso (`workshops/_my_group`).

**«Mi mesa» y «la mesa sobre la que ACTÚO» son dos preguntas distintas, y por
eso `group_of` no se tocó.** Darle un parámetro era la tentación obvia y es la
peor salida: dos de sus llamadores preguntan legítimamente por la propia —el
`@my_group` de `workshops#show`, que es literalmente el panel «Tu mesa», y el
camino sin administrar de `alcanzables` en las grabaciones—, y un método con dos
significados es cómo se abren las fugas que este archivo ya documenta. La
pregunta nueva vive UNA vez, en el concern `ActsOnAGroup`
(`acting_group(workshop, link)`), y la consultan los cinco caminos de la sala:
el GET que decide qué dibuja y los cuatro que escriben. Se verifica con
`grep -rn "group_of(current_user)" app`, que tiene que devolver esos dos
llamadores y nada más —los otros dos hits son del concern mismo: un comentario y
el `own_group` memoizado—. Un número no se verifica; el grep sí.

**El asiento propio GANA SIEMPRE** (`own_group(workshop) ||
named_group(workshop, link)`), y no es un detalle de implementación: es lo que
hace que nada de lo que ya funciona cambie de comportamiento. El seed sienta al
admin del recorrido en las mesas de los dos talleres que el recorrido trabaja, y
`[DRAFT]` y `[GRABAR]` —con piso EXACTO en 2— lo miden de rebote. De paso
significa que quien está sentado **no** puede entrar a otra mesa: nombre lo que
nombre, le sigue saliendo la suya.

**Para quien no administra ese desafío el parámetro se IGNORA, no se rechaza.**
Cae a su propio asiento, sin 403. Un 403 confirmaría que esa mesa existe, o sea
el oráculo de existencia que este archivo persigue en todas partes.

**`Workshop#group_named` es segura por dos vías independientes, y sólo una se
lee del código.** La que se lee: cuelga de `workshop_groups`, que filtra por
taller y —vía `TenantScoped`— por `company_id`, así que una mesa de otro taller
o de otra empresa queda excluida dos veces. La que no: la columna es **`uuid`**,
así que `OID::Uuid` castea a `nil` antes de llegar al SQL. Medido el 2026-10-08:
el hash de `?mesa[a]=1` (`ActionController::Parameters`), un array, una cadena
basura, `""` y `nil` castean los cinco a `nil`, y `group_named` devuelve `nil` en
los cinco; sólo el id real resuelve. Es el mismo par portante que este archivo
documenta para `base_version_id`, y las dos se pierden por caminos distintos:
si la columna cambiara de tipo se va el casteo, y si el `find_by` se moviera a
`WorkshopGroup.find_by` se va el filtro por TALLER y queda sólo el de empresa
—una mesa de otro taller de la misma empresa pasaría a resolver—.

**«El asiento propio gana» tiene UN SOLO testigo, y ninguna guarda del recorrido
lo respalda.** Es un ejemplo de `spec/requests/entrar_a_una_mesa_spec.rb` con un
admin **sentado** que nombra otra mesa. Tiene que ser alguien con asiento **y**
permiso de nombrar: con un `participant` el ejemplo pasa igual con el `||`
invertido, porque `named_group` le devuelve `nil` por permiso y cae al asiento
**de rebote** y no por precedencia. Los cuatro bloques de los endpoints de
escritura seguirían verdes con el `||` al revés —medido: con esa inversión cae
ese ejemplo y nada más—, y `[DRAFT]` y `[GRABAR]` **tampoco lo cazarían**: no
mandan `mesa`, así que con el parámetro ausente `named_group` devuelve `nil` y el
resultado es el mismo en cualquier orden. Un ejemplo por endpoint sería caro y no
agregaría nada —es un mecanismo único en una línea—, pero que nadie lea «está
cubierto»: borrar ese ejemplo deja la precedencia sin testigo.

**Y el límite que hay que saber antes de creer que la feature está entera: el
`mesa` del cuerpo no lo manda NADIE.** Lo escribe un solo lugar
—`grep -rn "mesa: group.id" app` devuelve el «Entrar» de `workshops/_groups` y
nada más— y ese link es un **GET**. Los dos formularios de la sala
(`_ideation`, `_evolution`) y los dos `fetch` del JS (`workshop_draft.js`,
`workshop_recording.js`) arman su URL con `workshop_sala_*_path(workshop,
link)`, sin el parámetro, y no hay `default_url_options` que lo arrastre. O sea
que hoy, desde un navegador, quien administra y **no** está sentado ENTRA y LEE
la mesa ajena, y después cada escritura cae a `own_group` → `nil` → 403 (el
borrador y la grabación) o redirect con «no estás en ninguna de este taller»
(las ideas y las propuestas): un formulario que se dibuja y rebota, que es el
control-que-no-responde de siempre. Los cuatro endpoints SÍ aceptan el parámetro
y `spec/requests/escribir_en_una_mesa_ajena_spec.rb` los prueba con un bloque
por endpoint, porque **manda el parámetro a mano** —es exactamente la mitad que
`base_version_id` tuvo que cubrir con un lint, y acá no hay ninguno—. Completar
el camino es un `hidden_field_tag :mesa` en los dos formularios y el parámetro
en las dos URLs de `data-`, más un testigo que mire el HTML servido; **no está
hecho**.

**Con quién estás sentado ya se ve, y sin controles.** `workshops/_my_group`
—nombre de la mesa, integrantes, «(vos)» y «· ausente»— se sirve a cualquiera
con `work?`, en la pantalla del taller y en la columna de referencia de la sala:
UN partial para los dos lugares, porque dos copias del mismo markup divergen y
nadie se entera. Sin controles a propósito: marcar presente y sacar gente son de
quien administra y viven en el bloque de armado, que sigue dibujando el asiento
con su propio markup (`workshops/_group_body`). La lista COMPLETA de mesas sigue
detrás del permiso de armar (`can_assemble`, que es `WorkshopPolicy#update?`).

**Y los textos que decían «tu mesa» salen de UNA variable por archivo, no de un
`if` por frase.** `de_la_mesa` en `workshop_rooms/_ideation` y en `_evolution`, y
el local `mesa_propia` —con default `true`— en `workshops/_my_group`, que es el
partial compartido: en la pantalla del taller la mesa es siempre la propia y sólo
la sala puede mostrar una ajena. Con una mesa ajena cada frase dice el NOMBRE.
**Si alguien agrega un texto nuevo con «tu mesa» fijo, miente en cuanto la mesa
es ajena**, que es la misma fuga que este archivo nombra para la lista de ideas:
contenido de otra mesa bajo un título que dice que es de ésta. El grep es
`grep -rni "tu mesa" app/views` —varias de sus líneas son comentarios y no
textos—, y **no los encuentra todos**: «Trabajás sola o solo en este taller» no
contiene «tu mesa» y también mentía sobre una mesa ajena; se arregló, pero el
grep no la habría encontrado. **No hay ninguna guarda**: ni un spec de lint ni
`make screens` cazarían un texto fijo nuevo. Lo único que cubre esto son los
ejemplos de `spec/requests/entrar_a_una_mesa_spec.rb`, y cubren las frases que
existen hoy, y cubren las DOS caras por separado —medido: con `@mesa_propia`
fijo en `true` caen ejemplos de idear **y** de evolución, no de una sola—.

**El aviso de mesa ajena se escapa con el sufijo `_html` de la clave de
traducción, y con NADA más.** El nombre de la mesa es texto libre que escribe
quien la crea, y el aviso lo interpola adentro de un `<strong>`. Medido: con la
clave `flow.rooms.foreign_group_html` el valor interpolado sale **ya escapado**,
y un `ERB::Util.html_escape` explícito encima da una salida byte por byte
idéntica —no hay doble escape, y no hacía falta—. Pero el control —la misma
clave **sin** el sufijo más un `.html_safe` encima— sí deja pasar un `<script>`
ejecutable. Por eso la línea **no lleva `.html_safe`**: sería un no-op hoy y
volvería explotable un renombre de la clave mañana. Sin él, el mismo renombre
sólo mostraría el `<strong>` como texto, que falla hacia el lado seguro.

**Del «Entrar» de cada mesa, `make screens` cubre casi nada, y conviene saber
exactamente qué.** El link es un `a.btn.btn-ghost.btn-sm` dentro de un wrapper de
utilidades sueltas (`.flex.flex-wrap.gap-2.mt-2`). `[CLASES]` lo ve **sólo por la
familia `btn`** y **sólo salta si pierde toda regla** —y `btn`, `btn-ghost` y
`btn-sm` ya existen por el «Convocar» de la misma mesa, así que en la práctica no
puede quedarse sin ninguna—. El **wrapper**, hecho sólo de utilidades, es
**invisible** para `[CLASES]`, que mira una lista fija de familias: es la familia
de la tarjeta del QR que sobrevivió seis corridas verdes. **Nada mide** que el
link esté, que lleve el `mesa=` correcto, su rótulo, el colapso a «Entrar» pelado
con un solo vínculo trabajable, ni su maquetación. Lo primero lo cubren los
ejemplos de request, que aseveran sobre el HTML servido; la maquetación **sólo la
vio una persona abriendo `tmp/screenshots/25a-taller-salas.png`**, y ahí
apareció el defecto que la ronda de arreglo cerró —el control contra el borde
derecho de la caja de integrantes mientras el «Convocar» de la misma mesa iba a
la izquierda—.

**El reparto se niega a correr en cuanto hay propuestas.** Rearmar borra las
mesas que queden vacías, y eso se llevaría las propuestas aceptadas, que son la
procedencia de versiones ya publicadas. El borrado que lo haría va por Rails
—`WorkshopGroup` declara `has_many :workshop_proposals, dependent: :destroy` y
`AssignGroups` llama `mesa.destroy!`—, y debajo está el piso:
`workshop_proposals.workshop_group_id` es `ON DELETE CASCADE`. Los dos, porque
sacar la cascada de la FK no quitaría el riesgo: el que está en el camino es el
`dependent:`. Con trabajo hecho, las mesas se mueven a mano.

**Nunca evicta, y borra sólo las mesas que quedan vacías.** Quien está sentado
por una convocatoria a mano entra al reparto aunque su rol no esté en el pool
automático: sacarlo desharía una decisión que alguien tomó a propósito. Un
ausente conserva su asiento, así que su mesa no queda vacía y no se borra — y
de rebote una mesa reusada puede terminar con MÁS gente que el tamaño pedido.
Es a propósito: el tamaño habla de quién está presente. Los ausentes se
descuentan en las **dos** fases: en evolución, si alguien no vino su idea
pierde a esa persona y eso cambia los racimos.

**En evolución sólo se vuelve grupo de una persona quien está sentado y no
está en ninguna idea.** Sumar un grupo de una persona que YA está en una idea
no cambia las mesas —el racimo las une y la deduplicación lo absorbe—, pero sí
agrega una clave que el reparto puede elegir para desprender, y ahí el aviso
anuncia un corte que no movió a nadie.

**El seed tiene cuatro talleres, y no por una sola razón.** La regla de una
sola fase explica los tres primeros —sin ella serían dos—: uno sobre idear
—que además lleva el desafío que se rechaza al abrirse, y es de donde sale el
vínculo cerrado con motivo de `28`—, uno sobre evolución —que lleva la
propuesta pendiente— y el borrador. `25a`, `25` y `28` salen del primero;
`26`, `26b` y `27` del segundo; `24` del borrador. El de idear lleva además un
borrador de Mesa Bodega que existe **sólo** para que `25` dibuje «Las ideas de
tu mesa», y va **sin postular** a propósito: el editor de campos del formulario
tiene un candado más fino que `touched?` (`ideas.submitted.exists?`), así que
postularlo trabaría ese editor de `taller-idear` por una idea que nadie
postuló. Y ojo con `goToWorkshop` al escribir una captura: espera
`/workshops/<id>$`, o sea que sólo sirve para quien el taller **no** redirige
—hoy, el recorrido entra a los cuatro talleres como quien administra—. El
cuarto, «Taller con check-in», no sale de esa regla: existe SÓLO para `29`,
`30` y `30b`, y va **sin nadie sentado**,
porque `29` tiene que mostrar la llegada vacía. A Lucía Llegada
(`llegada@taller.example`, con una membresía `participant` real de la empresa
demo) la siembra `30b` al correr, así que un segundo `make screens` sin
resembrar la muestra sentada — y por eso el seed la BORRA, al lado de los
talleres: si no, `12-miembros` la lista en toda corrida posterior a la primera.
Sentar a alguien a mano en ese taller rompe `29`; reusarlo para otra cosa,
también.

**Lo que la mesa teclea se autoguarda en el SERVIDOR dos segundos después de
la última tecla, sin publicar nada**: vive en `workshop_drafts` y mandarlo sigue siendo apretar el
botón. Lo que decidió la spec y no se lee del código:

- **El borrador es de la MESA y no de cada persona** (último que escribe gana,
  del lado del servidor). Concuerda con cómo la pantalla ya trata el
  trabajo de la mesa, pero no es una promesa que ella hiciera: la línea «el
  borrador se comparte con…: es de la mesa, no solo tuyo» es preexistente y habla
  de la `Idea` que crea «Crear borrador», no del autoguardado. En ese card
  «borrador» significa ahora TRES cosas (esa `Idea` en `draft`, el
  `WorkshopDraft` y `Workshop#draft?`) y nada anuncia el autoguardado: el
  `#draft-stamp` nace vacío. Es lo único que sobrevive al
  caso que esto existe para evitar: que al que escribe se le muera la máquina o
  se vaya, y el texto quede para el resto.
- **Gana el borrador sobre la versión vigente, CON aviso.** Las otras dos
  opciones estaban mal: que ganara la versión tira el trabajo de la mesa sin
  preguntar —el autor aceptando algo desde su teléfono le borraría el texto en
  medio de la sesión—, y que ganara en silencio hace que la mesa mande una
  propuesta que revierte la versión nueva sin enterarse.
- **El sello de la versión se escribe SÓLO al crear la fila**
  (`based_on_version_id`). Si se reescribiera en cada autoguardado, el aviso de
  base vieja no podría dispararse nunca. De la condición
  (`if draft.new_record?`) depende toda la feature del aviso, y la cubren DOS
  ejemplos que prueban mitades distintas: el request spec «el sello de la
  versión no se reescribe en el autoguardado siguiente»
  (`spec/requests/workshop_drafts_spec.rb`) hace dos `PATCH` con una versión
  publicada en el medio y asevera que el sello sigue siendo el de la primera; y
  el de extremo a extremo
  (`spec/requests/workshop_draft_prefill_spec.rb`), que ese sello llega al
  markup del aviso. Sacar la condición pone en rojo **los dos** — medido; esta
  línea decía «el primero» y era quedarse corta.
- **Y esa versión la dice el CLIENTE, no la base.** Es el único lugar de la app
  donde un dato del navegador entra a una columna con FK. Va así: la vista
  publica `draft_base` en el form, el JS lo lee de `dataset.draftBase` y lo
  manda como `base_version_id`, y el servidor lo busca en `idea.versions`. El
  motivo es que el formulario se prellena al RENDERIZAR y la mesa puede tardar
  en teclear: entre el render y la primera tecla la versión puede avanzar, y
  sellar la nueva sobre contenido de la vieja apagaba el aviso para siempre.
  **Lo que lo hace seguro son tres cosas, y sólo una está escrita en el
  código.** El `find_by` cuelga de `idea.versions`, que filtra por `idea_id` y
  —por `TenantScoped`— por `company_id`, así que una versión de otra idea o de
  otra empresa queda excluida dos veces, independientemente, y cae a
  `current_version_id`. La columna es **`uuid`**, así que `OID::Uuid#cast_value`
  convierte basura, un no-entero, un array o la clave ausente en `nil` antes de
  llegar al SQL: la consulta queda `id IS NULL` y cae al mismo lado. Y lo peor
  que logra un cliente que miente con una versión vieja de SU idea es que el
  aviso dispare de más, que es el lado seguro. **Ojo con las dos últimas: son
  portantes y no se leen del código.** Si la columna cambiara de tipo, o si el
  `find_by` se moviera a `IdeaVersion`, se irían a la vez la seguridad de tipo y
  el scope — y ahí `version_belongs_to_idea`, que en el camino real no se
  ejecuta nunca porque el scope ya excluyó la versión ajena, pasaría de cinturón
  a único freno, levantando un 500 en vez de caer a la vigente. Hay un ejemplo
  por eje, y los ejes son distintos. Por NOMBRE y no por número de línea, que se
  corre con cada edición: «el sello usa la versión con la que se prellenó» caza
  que el servidor ignore al cliente **y** que la vista pierda el atributo; «una
  versión de otra idea de la misma empresa», que el `find_by` deje de colgar de
  `idea.versions`. Que el JS deje de leerlo o le cambie la clave no lo caza
  ningún request spec —mandan `base_version_id` a mano— ni `[DRAFT]`: eso es
  `spec/lint/sello_del_borrador_spec.rb`. Y el aviso de base vieja sigue
  dependiendo de `if draft.new_record?`: el del prellenado **no** lo cubre,
  porque hace un solo `PATCH` y resellar da el mismo valor; lo cubren los otros
  dos.
- **Un `PATCH` sin `payload` es un no-op a propósito**, y lo mismo si después de
  filtrar no sobrevive ninguna clave: con `fetch(:payload, {})` un bug del
  cliente pisaría el texto de la mesa con nada. Los tres caminos responden 204,
  así que el endpoint manda la cabecera `X-Draft-Saved: "0"` en los dos que NO
  escriben — sin eso el sello diría «Guardado ahora.» sobre un guardado que no
  ocurrió.
- **La fase la decide la SALA**: un `idea_id` mandado a la cara de idear se
  ignora.
- **La cláusula nueva del barrido de mesas vacías de
  `Flow::Workshops::AssignGroups#seat!` acompaña a la de propuestas por la MISMA
  razón de carrera**, mientras el guarda de arriba —el que se niega a repartir
  si ya hay propuestas— **no** se extendió a borradores a propósito: negarse
  a repartir porque alguien tecleó una palabra bloquearía una operación común
  por texto sin mandar, y ese guarda existe por la procedencia de versiones
  publicadas, que un borrador no tiene. Borrar una mesa a mano es otra decisión
  y tampoco se niega (`WorkshopGroupsController`): ninguna pantalla borra un
  borrador, así que una mesa con texto tecleado quedaría imposible de borrar
  para siempre. Por eso borrar una mesa a mano se lleva el borrador, y el aviso
  lo dice.

**La mesa graba su conversación, y lo que sigue no se lee del código.** El
audio sube de una vez, al parar (`WorkshopRecordingsController`), un job lo
transcribe con `Flow::AI.speech_provider` y la tarjeta muestra las utterances
con sus hablantes. Cada punto de abajo existe porque algo salió mal o estuvo a
punto.

**La línea de sonido va en barras del DOM y NUNCA en un `<canvas>`.** No hay un
solo canvas en el repo, y el motivo de que siga así es que un canvas es una caja
negra para todas las guardas —`[CLASES]`, `[CONTRASTE]` y `[SOMBRA]` no ven
adentro— y una guarda que no puede ver **da permiso**. Las 40 barras nacen en el
MARKUP y el JS sólo escribe su `height`: así Tailwind ve las clases, y un morph
que borre los `style` en línea se arregla en el frame siguiente. El color sale de
`--dato` / `--dato-fuerte` por la hoja —tinta de DATOS y no el acento: una barra
pintada del color del botón de al lado se lee como un control—.

**Lo que hace medible a la onda es `data-level`, y sin eso no habría testigo.**
El bucle de dibujo publica ahí el RMS crudo, y `[GRABAR]` lo muestrea cada 100 ms
para exigir dos cosas: un pico durante la voz, **y una corrida de muestras cerca
de cero**. Sólo la segunda discrimina: una onda decorativa hecha con
`Math.random()` pasa el umbral del pico de sobra y no produce nunca la corrida.
Por eso `script/fake_audio.wav` está armado voz → SILENCIO → voz. Medido el
2026-10-08: el hueco da 17 muestras seguidas bajo 0,01 contra un piso de 8, y la
ventana de muestreo termina ADENTRO de la segunda voz, así que la corrida sale
del hueco interior y no de una cola muda. Si alguien «simplifica» ese wav a una
sola voz corrida, la guarda queda midiendo que algo se mueve y nada más.

**`workshop_recording.js` no tiene NINGÚN manejo de `prefers-reduced-motion`, y
no agregarlo es deliberado y no un descuido.** La onda se mueve porque el JS
escribe las alturas, con o sin la preferencia. La hoja ya registra el motivo para
el spinner de la IA, que sigue girando bajo la preferencia porque es la ÚNICA
señal de que el trabajo continúa y uno quieto se lee como colgado: la onda es
exactamente eso para el micrófono. Quieta se lee como un micrófono tapado, que es
justo el estado que tiene que poder distinguir. No es una decisión implementada
con una guarda: es la ausencia de una, y quien la «arregle» agregándola la rompe.
Un micrófono que entrega silencio (tapado, en mute por
hardware, el equipo equivocado) deja la onda plana mientras el cronómetro sigue
corriendo.

**`workshop_recording.js` NO para ni descarga en `turbo:before-render`, y es a
propósito, al revés de sus dos hermanos.** `arrival_live.js` para ahí y
`workshop_draft.js` descarga ahí, pero ese evento dispara también en un morph, y
un morph ocurre con cualquier POST a la misma URL: alguien apretando «Crear
borrador» cortaría la reunión. Lo que lo permite es que el `MediaRecorder` y los
trozos son variables de MÓDULO, así que un morph que reemplaza el botón y las
barras no los toca. **Y `start()` tiene que REPINTAR en un morph, no sólo
recablear:** el servidor renderiza el botón diciendo «Grabar» y el sello vacío,
y con un retorno temprano el micrófono seguía abierto mientras el botón mentía;
quien veía una onda moverse al lado de un «Grabar» lo apretaba y cortaba la
grabación. Si alguien «arregla» el archivo copiando a los hermanos, se cortan
grabaciones y ninguna suite se entera: el único testigo es `[GRABAR]`.

**Y «el estado vive en el módulo» incluye A DÓNDE va lo grabado, que es la mitad
que al principio no estaba.** `urlDeSubida` e `ideaDeSubida` se leen del DOM en
`arrancar()`, en el clic, y `subir()` usa ésos y no `caja.dataset`. Parece
redundancia hasta que se ve el camino: `start()` hace `caja = encontrado`
**antes** del `rec.stop()`, así que en una navegación real el handler de parada
corría contra el contenedor de la pantalla NUEVA. Repro de dos clics: grabando
en la sala A, al selector del taller (sin contenedor, así que `caja` queda en
null y el grabador sigue, porque Turbo no dispara `pagehide`), «Entrar» a la
sala B, y la conversación de la mesa A se guardaba como grabación de la mesa B,
con su link de descarga. De un clic: en evolución, elegir otra idea paraba la
grabación y la etiquetaba con la idea nueva, contra la regla de que `idea_id` es
«qué idea tenía la sala elegida AL APRETAR GRABAR». Ningún spec de request lo
ve —el destino lo elige el cliente— y `[GRABAR]` tampoco, porque no navega entre
salas mientras graba.

**Una navegación en medio de la grabación PIERDE el audio, y `keepalive` no lo
salva.** La despedida del borrador no se traslada: la spec de Fetch topa el
cuerpo de un `keepalive` en 64 KB y el audio son megabytes. Sin subida
progresiva lo único posible es avisar, que es lo que hace el `beforeunload`
mientras graba. Si alguien lo saca por «limpieza», se pierden reuniones en
silencio.

**La tarjeta de grabaciones NO se refresca sola.** No hay frame, ni `data-live`,
ni poller: el único intervalo es el cronómetro. La mesa sube, ve «en cola», y la
tarjeta no se mueve hasta que navegue o recargue. La spec lleva una nota fechada
porque antes afirmaba lo contrario. `[GRABAR]` pasa igual porque **re-visita a
propósito** (su comentario lo dice): un `[GRABAR]` verde no es evidencia de que la
tarjeta se actualice sola. El arreglo barato está descartado por una razón dura:
Turbo 8 morfea llamando a `morphElements` sin `ignoreActiveValue`, así que
`syncInputValue` le devuelve al campo enfocado el valor del servidor, y un poller
de página completa le pisaría a la mesa lo que está tecleando en el borrador.

**Y el riesgo de despliegue que ninguna guarda puede ver:** `getUserMedia` no
existe fuera de un contexto seguro, y `docker-compose` publica el puerto en
HTTP plano. Desde la máquina que corre Docker es `localhost` y anda; desde un
teléfono de la red en `http://<ip>:3001`, `navigator.mediaDevices` es
`undefined` y no hay grabación. La pantalla lo detecta y lo dice en vez de dejar
un botón mudo. **`make screens` corre en `localhost`, que es contexto seguro
SIEMPRE**: ninguna corrida verde dice nada sobre esto, y borrar la detección
tampoco pone nada en rojo (medido: la mutación quedó verde, la rama es
inalcanzable para el recorrido).

**Los hablantes no están verificados con voces reales.** Las dos pruebas que hay
usan voces sintéticas y las dos dieron un solo hablante; el español no se midió
nunca. La spec lo detalla en «La diarización, sin verificar». Nada de C1 depende
de eso —la tarjeta avisa cuando la mesa es de dos y la transcripción trae uno
solo (`collapsed_diarization?`)—, pero C2 sí.

### Multi-tenancy: cuatro capas

1. `Flow::Tenant.with(company)` para entrar. `bypass!` es la única válvula de
   escape: explícita y greppable (jobs, seeds, tasks).
2. `TenantScoped` tiene un `default_scope` que **revienta** con `MissingTenant`
   sin tenant en contexto, en vez de devolver todo.
3. **Lo que no se ve da 404, no 403**: un 403 es un oráculo de existencia.
   El 403 existe —`Pundit::NotAuthorizedError` lo devuelve— y es correcto
   para lo que SÍ se ve pero no se puede hacer: ver un desafío y no poder
   editarlo no confirma nada que no supieras. Esta línea decía «404, nunca
   403», y el código nunca hizo eso.

   **La trampa es el orden, no el `authorize`.** Buscar con el scope de
   tenencia y autorizar DESPUÉS devuelve 403 sobre algo que no se debería
   ver: a quien participa, una idea ajena le daba 403 y un id inexistente
   404, y esa diferencia confirma que existe. Pasó en cuatro de los seis
   controllers que buscaban una idea —cada uno con su `authorize` escrito—.
   Por eso las ideas se buscan por `policy_scope`, y los desafíos también.
   `spec/lint/ideas_por_policy_scope_spec.rb` cuida **sólo las ideas y sólo
   en controllers**, y es texto: su comentario dice qué no ve. Lo que prueba
   el comportamiento son los `[404, 404]` ruta por ruta de
   `spec/requests/participant_rules_spec.rb`. La guarda marca los usos de
   `Idea` o `.ideas` que queden fuera de un `policy_scope(...)` y prueba su
   propio detector; las dos revisiones la evadieron, y lo que todavía no ve
   —ideas a las que se llega por otro registro, `public_send`, heredocs— está
   listado en su comentario. No le creas más que eso.

   **Y lo que cuelga de una idea hereda su visibilidad.** Comentarios y
   propuestas de la IA se buscaban por id en toda la empresa, con el mismo
   403-contra-404. Un comentario se busca dentro del paso de la URL y sobre
   una idea visible (`FeedbackItemsController#comentario`). Una propuesta la
   ve (`AiSuggestionPolicy#visible?`) quien administra, y cualquier otra
   persona si **le aparece en un panel Y ve aquello sobre lo que actúa**: el
   panel filtra por `accept?`, pero vive en pantallas que ya filtraron por
   desafío e idea, y la regla tiene que filtrar igual. Tres intentos fallaron
   por una mitad cada uno: `accept?` a secas volvía 404 el 403 legítimo de
   quien administra un desafío cerrado; «se ve si se ve su objetivo» le dejaba
   403 a quien participa por una propuesta del flujo; y `manager? || accept?`
   dejaba a un gestor dado de baja —con la asignación intacta— **aplicar una
   evaluación** sobre un desafío que le da 404, porque `accept?` de una
   evaluación sólo miraba la asignación. `AssessmentPolicy#create?` ahora
   pregunta si llega al desafío (`spec/policies/assessment_policy_spec.rb`,
   el único spec de policy directo: por request, esa línea la tapan otros).
   La guarda de lint no cubre comentarios ni propuestas.

   **Una policy sin nada propio hereda `show? = membership.present?`**, o sea
   «cualquiera de la empresa lee esto». `CriteriaSetPolicy` estaba vacía, y
   un gestor abría por id —200, con los criterios adentro— el set `inline` de
   un desafío que no le asignaron. No era un oráculo: era una fuga de lectura,
   y la auditoría del 403 la encontró de casualidad. Ahora su `Scope` deja la
   biblioteca a la vista de la empresa y cada set `inline` a la de su
   desafío. Antes de dejar una policy vacía, preguntate de qué desafío cuelga
   lo que protege.

   **Sin membresía, `none`.** La sesión guarda la empresa elegida y no
   vuelve a pedir la membresía: a quien se la sacaron le queda el tenant
   puesto y `current_membership` en `nil`. `ChallengePolicy::Scope` hacía
   `scope.all unless gestor?`, y quien acababa de perder el acceso listaba
   todos los desafíos —un gestor removido, más que antes—. El default de
   `ApplicationPolicy::Scope#resolve` devuelve `none` sin membresía, y todo
   `Scope` que lo sobreescriba tiene que hacer la misma pregunta primero
   (`spec/tenancy/sin_membresia_spec.rb`). **La sesión sigue viva igual**:
   esto cierra lo que se ve, no la puerta.
4. FKs compuestas `(x_id, company_id)`: Postgres rechaza atar una fila de la
   empresa A a un padre de la B.

En los specs esto muerde: **toda lectura del dominio va dentro de
`as_company(company) { ... }`**, incluido un `.new` (toca el `default_scope`) y
cualquier asociación leída después de salir del bloque. Los specs de guardia
están en `spec/tenancy/`; los tres principales están probados por mutación (un
modelo sin `TenantScoped`, un `.unscoped`, una FK simple: cada uno pone la suite
en rojo).

`lib/flow/migration_helpers.rb` tiene `tenant_table` y `add_tenant_fk`. Trampa:
`ON DELETE SET NULL` sobre una FK compuesta nulea **todas** las columnas,
incluida `company_id` que es NOT NULL — el helper usa `SET NULL (columna)`
(PG 15+).

### La capa de IA

`Flow::AI::Runner` es el único camino para los tres modos. `ai_auto` **no**
saltea la sugerencia: la auto-acepta, para que haya un solo code path y el mismo
rastro de auditoría. Un run se reutiliza solo mientras está "vivo" (en curso, o
con sugerencia pendiente de revisión): pedir de nuevo algo ya descartado tiene
que generar un run nuevo, no devolver la sugerencia muerta.

El proveedor se resuelve en `Flow::AI.provider` desde `FLOW_AI_PROVIDER`.
`fixture` es el default (determinista, sin red ni credenciales); `anthropic` es
el adapter real y **cada llamada cuesta plata**, así que nunca es el default.
Los JSON Schema validan en los dos caminos, así que no hay drift.

El adapter real tiene dos cosas no obvias: poda del schema las palabras que la
API rechaza con 400 (`minItems`, `pattern`, …) pero valida la respuesta contra
el schema **original**; y trata `stop_reason: :refusal` y `:max_tokens` como
fallas explicadas, porque llegan con HTTP 200 y no como excepción.

**Un 500 de Voyage en TODO pedido no es el pedido.** Con la credencial
autenticando (sin ella da 401), la validación funcionando (cuerpo vacío da 400)
y el ruteo bien (GET da 405), que embeddings, rerank y contextual devuelvan los
tres 500 —incluso con un modelo inexistente, que debería dar 400— significa que
la cuenta autentica pero no tiene inferencia habilitada. Voyage contesta 500 en
vez de un 402 que lo diga. La pista está en el mensaje del adapter para no
volver a sondear.

**Hay TRES proveedores, no uno.** `FLOW_AI_PROVIDER` (chat),
`FLOW_EMBEDDINGS_PROVIDER` (vectores) y `FLOW_SPEECH_PROVIDER` (voz: transcribir
la grabación de la mesa) son capacidades distintas, y ningún proveedor tiene las
tres: Anthropic no expone embeddings ni transcripción, Voyage sólo vectoriza y
Deepgram sólo transcribe —su `complete` levanta `ProviderUnsupported`, igual que
el de los adapters de embeddings—. Con una sola variable no se podía tener chat
real y vectores reales a la vez, y con dos tampoco voz real. Sin declarar el
segundo o el tercero se usa el de chat si sabe hacer lo que se le pide
(`Provider#embeddings?`, `Provider#transcription?`), y si no el fixture.

**`FLOW_SPEECH_PROVIDER` se deja VACÍA a propósito**, y es lo que hace que
`make spec` y `make screens` no facturen: Anthropic no sabe transcribir, la
cascada cae al fixture y el recorrido de la grabación corre sin red. Declararla
es elegir que cada corrida cueste plata.

**Y encenderla es tocar `docker-compose.yml`, no sólo el `.env`.** El compose
enumera el entorno de cada contenedor con `${VAR:-default}` y **no tiene
`env_file:`**, así que el `.env` sirve nada más que para INTERPOLAR: una
variable que el compose no nombra no llega a ningún proceso, por más que esté
escrita en el `.env`. Medido el 2026-10-08: las tres de voz no estaban en el
anchor, y en `sidekiq` —que es el proceso que corre el job de transcripción—
`env | grep -cE "FLOW_SPEECH|DEEPGRAM"` daba **0**, o sea que el eje era
imposible de encender. Ahora las tres van en `&app_env` con default vacío, y
`app_test` fija `FLOW_SPEECH_PROVIDER: fixture` con la credencial en `""`, igual
que los otros dos ejes: el contenedor de test no puede llegar a un proveedor
real ni depender de una key. De `DEEPGRAM_API_KEY` lo que está medido es que
**autentica desde el host** —un `curl` a `/v1/listen` con un clip devolvió
200—; lo que el compose agrega es que ahora el contenedor la recibe.

Los adapters de embeddings (`Providers::Openai`, `Providers::Voyage`) heredan
de `HttpEmbeddings`, que trae lo que es fácil hacer mal —respetar el índice de
cada fila, partir en lotes, validar la dimensión, llevar el código HTTP al
error— y deja a cada uno su URL, su cuerpo y dónde pone el mensaje de error.
Solo hacen `embed`: su `complete` levanta `ProviderUnsupported`.

**Ojo con a quién se le piden los vectores.** El runner le pasa a la tarea el
proveedor de CHAT. `DetectDuplicates` usa `Flow::AI.embeddings_provider`, que es
otro objeto: preguntarle al de chat dejaba al de embeddings sin usarse nunca,
con la credencial puesta y todo. Y si el de embeddings falla, `run_locally`
devuelve `nil` y el runner cae a `#complete` — un proveedor caído no puede
romper una tarea que sabe arreglárselas sin él.

**Detectar duplicados tiene dos caminos, y elige el proveedor.**
`Provider#embeddings?` decide: con vectores se compara por coseno local
(determinista y barato, es lo que hace el fixture); sin ellos se le pregunta al
modelo por `#complete`, que además **explica** el parecido —que es lo que una
persona necesita para decidir si fusiona—. El runner no sabe de embeddings:
pregunta `task.local?(provider)`. Dos detalles que se pagan si se olvidan: los
ids posibles viajan como `enum` en el schema (el modelo no puede señalar una
idea inexistente ni de otro desafío), y sin candidatas la tarea se resuelve
local para no gastar una llamada preguntando por una lista vacía.

Se compara contra **todas** las ideas del desafío, borradores y eliminadas
incluidas: «esto ya se propuso y no avanzó» es de las cosas más útiles que el
chequeo puede decir. El estado lo pone la app en el preview, no el modelo.

### pgvector

Los vectores viven en `idea_versions.embedding vector(1024)` con índice HNSW
(`vector_cosine_ops`). En la **versión** y no en la idea porque la versión es
contenido inmutable: el vector se calcula una vez y nunca queda viejo. Junto al
vector se guarda `embedding_model` — dos modelos distintos no producen vectores
comparables, y sin ese dato no habría forma de saber cuáles rehacer.

Cuatro trampas, las cuatro ya pagadas:

- **`add_column … :vector, limit: N` no sirve.** Rails no conoce el tipo,
  ignora el `limit` y deja una columna sin dimensión que después no se puede
  indexar. Va en SQL: `ADD COLUMN embedding vector(1024)`.
- El tipo desconocido hace que cada proceso escupa «unknown OID». Se registra
  como string en `config/initializers/pgvector.rb`; nunca se lee como número
  en Ruby.
- **La dimensión ata el modelo.** 1024 deja abiertos Voyage (nativa) y OpenAI
  (truncable por parámetro). Cambiarla es recrear la columna.
- El atajo por vector entra **solo arriba de `DetectDuplicates::NEIGHBOURS`**.
  Buscar entre diez no ahorra nada, y con vectores sin semántica real (el
  fixture) podría dejar afuera justo la duplicada. Es un mecanismo de escala,
  no de calidad.

Publicar una versión encola `EmbedVersionJob`: calcular el vector llama a un
servicio externo y publicar una idea no puede depender de que responda.
`make embeddings` completa lo que falte (`FORCE=1` rehace lo de otro modelo).

Qué se aplica al pedirlo y qué no lo decide `applies_on_request?`. Una
evaluación de IA es **aditiva** —una opinión más en el promedio— así que pedirla
ya es aceptarla. Un **veredicto de selección no**: es LA respuesta del filtro y
decide quién queda afuera, así que en `ai_assisted` se propone y alguien la
acepta. Y la IA **nunca pisa un veredicto que puso una persona**, ni con el
módulo en automático: quien lo puso ya miró la idea (`pending_gates` en
`Tasks::DecideVerdicts`).

El caso opuesto es `informativa?`: lo que la tarea produce es para **leer**,
no para aplicar (hoy, `detect_duplicates`). Su `apply!` no hace nada, así que
en «IA automática» auto-aceptarla no aplicaba nada y además la sacaba del
panel, el único lugar donde se lee: quien la pedía leía «se aplicó
automáticamente» y ninguna coincidencia. El runner la corre asistida en
cualquier modo —y el run lo registra así— y el botón responde al marco de las
propuestas, porque no cambió nada más de la pantalla.

**Y su tarjeta no se aplica ni se descarta: se lee.** Un solo «Listo»
(`shared/_ai_suggestion`, detrás de `AiSuggestion#informativa?`), que la da
por recibida y la saca del panel. «Aplicar» prometía lo que el `apply!` no
hace —el mismo control fantasma de siempre— y «Descartar» decía que la IA se
equivocó, que de una observación es falso. El aviso va con el botón:
`aviso_de_exito` dice «Listo.» y no «Sugerencia aplicada.», porque no se
aplicó nada.

**Quién puede pedirle algo a la IA —y aceptarlo— depende de sobre qué actúa, y
eso lo declara la tarea** con `self.actua_sobre`:

| Alcance | Tareas | Lo autoriza |
|---|---|---|
| `:idea` | `coauthor_field`, `evolve_idea` | `IdeaPolicy#update?` |
| `:feedback` | `suggest_feedback` | `FeedbackItemPolicy#create?` |
| `:pool` | `detect_duplicates` | `ChallengePolicy#curate_pool?` |
| `:assessment` | `evaluate_idea` | `AssessmentPolicy#create?` |
| `:challenge` (default) | el resto | `ChallengePolicy#update_pipeline?` |

`detect_duplicates` actúa sobre el **pool**, no sobre la idea: lo que devuelve
son títulos y resúmenes de las OTRAS ideas del desafío, que quien participa no
ve. Lo piden y lo leen quien administra y quien acompaña ese desafío, haya o no
una ronda abierta —comparar no edita nada—. Mientras colgó de `IdeaPolicy#update?`
el autor lo pedía sobre su propio borrador y leía el pool entero.

Pedir y aceptar son **el mismo método**: `AiRequestsController` arma una
propuesta de mentira con lo que trae el pedido y pregunta
`AiSuggestionPolicy#request?`, que es `accept?`. Divergieron dos veces
mientras la tabla estuvo copiada en los dos lados. Primero era todo
`update_pipeline?` para pedir y «admin o autor» para aceptar, así que quien
participa no podía usar ninguna función de IA sobre su propia idea y quien
acompaña no podía aplicar el feedback que es su trabajo. Después, con las dos
copias ya alineadas por `Tasks::Base.scope_of`, la policy seguía arrancando con
`return true if manager?`, y quien administra aplicaba sobre un desafío cerrado
una propuesta que ya no podía pedir.

Sumar una tarea es tocar **cuatro** lugares: la clase, `AiRun::PURPOSES`, el
CHECK de Postgres sobre `ai_runs.purpose` (hace falta una migración; si no, el
run revienta con `PG::CheckViolation` antes de crearse y el error llega
truncado) y `flow.ai_purposes` en `config/locales/es.yml` — sin esa clave el
chip de la propuesta, `ai_runs/index` y `ai_runs/show` muestran el propósito en
inglés por el fallback `humanize` (`test_idea` se quedó así hasta que se
sumó).

**A dónde responde un pedido a la IA depende de si ya cambió algo.** Por
defecto al `turbo-frame` de las propuestas: así pedir no recarga la pantalla ni
pierde lo que estuvieras editando. Pero en **`ai_auto`** la sugerencia se
auto-acepta, y las tareas **aditivas** se aplican al pedirlas: ahí refrescar
solo el marco deja el resto de la pantalla mostrando lo viejo —una idea
reescrita se seguía viendo como estaba hasta recargar a mano—. Lo decide
`marco_para_pedido_de_ia` en `ApplicationHelper`.

Las tareas de **autoría** (armar el flujo, proponer los campos del formulario)
se ofrecen aunque el módulo esté en «Solo personas»: ese modo define cómo se
trabaja *dentro* del desafío, no si su dueño puede pedir una mano para
diseñarlo. Es el `always: true` del partial `shared/_ai_actions`.

### Las pantallas se actualizan, no se recargan

El layout declara `turbo-refresh-method: morph`. Turbo 8 trata como *page
refresh* cualquier POST que redirija a la misma URL —que es lo que hace casi
todo acá, empezando por los pedidos a la IA— y con esa meta morfea el DOM en
vez de repintar la página. No hace falta `data-turbo-action` en los
formularios: Turbo ya elige `replace` solo cuando el redirect vuelve a donde
estabas.

Tres cosas que no son obvias:

- **`turbo-refresh-scroll: preserve` no conserva el scroll.** Solo le dice a
  Turbo que no scrollee él. El scroll se pierde *durante* el morph: mientras
  idiomorph tiene nodos afuera la página se acorta y el navegador recorta
  `scrollY`. Lo devuelve el bloque de `app/javascript/application.js`, que lo
  guarda en `turbo:before-render` y lo repone en `turbo:render` **solo si hubo
  `turbo:morph`**.
- **Después de un POST, Turbo NO cachea la página**
  (`shouldCacheSnapshot = formSubmission.isSafe`), así que `turbo:before-cache`
  no se dispara y no sirve para desmontar nada en el camino que importa.
  `islands.js` también escucha `turbo:before-render`.
- **Un `<dialog>` abierto no puede existir durante un morph.** Idiomorph
  compara contra el HTML del servidor, y un diálogo que agregó el cliente es
  un nodo de más: se lo lleva puesto, o le saca el `open` y lo deja en el DOM
  sin verse. Por eso los dos popups de la IA los arma el JS y ninguno existe
  durante un render: la espera se cierra y se saca en
  `turbo:before-frame-render`, `turbo:before-render` y `turbo:submit-end`
  (este último solo si no hubo éxito), y la de respuesta se arma recién
  después de pintar, en `turbo:frame-render`, `turbo:render` y `turbo:load`
  —el primero es el más frecuente, porque el modo asistido responde al
  marco— (`ia_popups.js`).
- **El morph no rompe las islas**, medido en la cara de configuración de
  Idear —la pantalla del módulo que hoy monta el editor de formulario,
  destino del redirect 301 que dejó `/challenges/:id/form`—: reemplaza el
  contenedor entero y `turbo:load` vuelve a montar con las props nuevas.
  `make screens` lo verifica sin gastar una llamada al proveedor
  (`revisarMorphing` en `script/capture_screens.js`), pidiendo a mano la misma
  navegación.
- **Un `<details>` abierto sobrevive al morph.** El `open` lo pone el
  cliente, y un POST que vuelve a la misma URL morfea contra el HTML del
  servidor, que no lo trae: guardar algo adentro de un plegable lo cerraba.
  `application.js` cancela en `turbo:before-morph-attribute` la REMOCIÓN de
  `open` en un `DETAILS` (un `open` que agrega el servidor sigue entrando).
  Por eso todo lo plegable de la app es un `<details>`: un mecanismo, un
  gancho. Lo prueba `revisarPlegableTrasMorph` en `make screens`.

### Configurar y ejecutar son dos caras de la misma pantalla

`StepsController#show` despacha por `step.touched?`: pendiente renderiza
`steps/config/<kind>` —la configuración entera del módulo—, tocado renderiza
`steps/<kind>` —el trabajo, con la configuración como resumen con candado—.

La cara la decide el MÓDULO y no el desafío: uno en curso sigue teniendo
módulos pendientes más adelante, y ésos son configurables. Es la misma regla
que `insertion_floor`.

**Un módulo se configura en UN solo lugar.** Estuvo repartido en seis
pantallas que se sumaron de a una, cada una razonable por su cuenta, y
configurar exigía rebotar entre todas. Hay guarda:
`spec/lint/una_vista_de_configuracion_spec.rb` cuenta declaraciones de isla.

**El builder es dueño del ARMADO, no de la configuración.** Manda kind, orden,
alta y baja; no manda `settings`, `criteria_set_id` ni `source_step_id`. Si los
mandara, guardar el flujo con props cargadas antes revertiría lo configurado, y
`lock_version` no lo ataja: es del desafío, y un PATCH al módulo no lo
incrementa. El payload del PUT es literalmente `{ id, kind }` por módulo, y
`create_added` lee sólo `kind`: ni `name` ni `ai_mode`, que el builder no tiene
cómo escribir. `update_existing` no existe — de un módulo que ya existe no se
escribe ningún atributo.

**Y tampoco manda para el otro lado.** `PipelinePresenter` publica sólo lo que
la tarjeta dibuja. Cuando la configuración se mudó a la pantalla del módulo
quedaron 6,4 KB de 10,4 KB de props que ningún `.vue` leía —el resumen de
criterios y el del formulario enteros, `settingsSchema`, `criteriaSets`,
`position`, `touched`, `effectiveAiMode`, tres URLs—, y no era sólo peso: el
resumen de criterios corría `newer_version_for` (una consulta por módulo que
puntúa) y el del formulario cargaba `form_fields.ordered` en **cada** render
del builder. Además `createApp(component, props)` convierte toda prop no
declarada en atributo del elemento raíz, así que lo que sobra se serializa al
DOM. Antes de sumar una clave, buscá quién la lee.

Tres cosas NO se congelan al arrancar y la cara B las muestra como vivas:
el nombre, el modo de IA (`ADJUSTABLE_ATTRIBUTES`) y las asignaciones.

El formulario de postulación tiene un candado más fino que `touched?`:
`ideas.submitted.exists?`. Con el módulo abierto pero sin postulaciones,
corregir el label de un campo es sano. Por eso su editor aparece en las dos
caras.

**La guarda de permiso vive en la VISTA, no en el controller.** Un editor o un
bloque de controles que antes vivía en pantalla propia —con su propio
controller pidiendo `manage_criteria?`, `manage_form?`— pasa a embeberse en la
pantalla del módulo, que sirve `ChallengeStepPolicy#show?`: cualquiera de la
empresa. Heredar ese permiso amplio sin poner uno más estricto en el partial
deja la isla y los botones montados para quien no puede usarlos, y apretarlos
rebota en un 403 — el mismo control-que-no-responde que esta rama entera
existe para arreglar, ahora adentro de la pantalla que se supone lo soluciona.
El mismo defecto apareció así de repetido: primero el form completo de
`steps/config/_modulo` se servía sin ninguna policy; después, en
`_criterios_editor`, el panel de sugerencias de IA quedó afuera de la guarda
que sí envolvía el resto. La forma que quedó, en `_criterios_editor.html.haml`
y `_campos_editor.html.haml`: **nada que no sea el encabezado se sirve sin la
guarda**, y la guarda es UNA variable (`puede_configurar`, calculada una vez
arriba) y no un predicado escrito en cada bloque. Son dos `if` sobre esa
variable y no uno, porque la tarjeta se cierra antes de las propuestas de la
IA y de la isla, que van después de ella; al preguntar las dos lo mismo no
pueden divergir, que es lo que el «un solo `if`» compraba. Cuál predicado
según qué bloque:
`configure?` para los ajustes del módulo y para sus criterios, `manage_form?`
para los campos del formulario, `manage_assignments?` para quién evalúa y
cuánto pesa, `update_pipeline?` para quién acompaña la evolución
(`_asignaciones_gestores.html.haml`, que sólo envuelve `challenges/_gestores`
con esa guarda y no tiene policy propia).

El panel de propuestas de la IA (`shared/_ai_suggestions`) es la excepción a
esa guarda única: filtra propuesta por propuesta con `AiSuggestionPolicy#accept?`,
porque quién revisa depende de sobre qué actúa cada tarea. Se sirve en diez
pantallas, y sin ese filtro les mandaba a quien participa y a quien evalúa
propuestas que no podían revisar, con la vista previa incluida.

**Los pasos del paso a paso son los MÓDULOS del flujo**, no una lista fija:
el desafío, el flujo, un paso por cada módulo —con su nombre, en el orden del
flujo, identificado por el id del módulo— y «Revisar y arrancar». Es la misma
lista que dibuja el drawer de la izquierda, que es de dónde salió el cambio:
eran dos listas de cosas distintas y había que traducir de una a la otra.
Qué necesita cada módulo para contarse configurado lo decide `estado_de` por
`kind`: idear pide campos de formulario **y es el único que traba el
arranque**; una evaluación pide criterios propios y una selección, que la
regla de corte esté decidida, pero ninguna de las dos traba —sin set propio
se usan los genéricos, y los criterios de una selección son FILTROS
opcionales, no calificaciones—; evolución y reportería nacen hechas.
En una selección eso se lee de `config` y no de `settings`: ahí el hueco vale,
porque una clave ausente no es «manual», es «nadie lo decidió todavía».

**El camino se dibuja en UN solo lugar: el flujo de la izquierda.** Estuvo en
dos —esa barra y una tarjeta arriba del contenido (`shared/_setup_progress`,
borrada)— que mostraban lo mismo con distinto vocabulario; con siete módulos
la tarjeta se partía en dos filas y se comía la pantalla. El drawer tiene dos
caras: **en borrador** es el camino de configurar (con el ✓ y la pista de cada
paso, y el «N de M» al lado del estado) y **arrancado** vuelve a ser el mapa de
lo que corre, con el chip de estado de ejecución.

**Dónde estoy lo decide `ShellHelper#paso_actual_del_setup`, y sólo él.** Lo
consultan el drawer —para resaltar— y `setup_nav` —que por eso ya no necesita
que le pasen `current:`—. Antes cada pantalla escribía su clave a mano, y con
cuatro claves fijas para las cinco pantallas de módulo de entonces era
imposible de acertar: evolución y reportería decían ser «El flujo», y los dos
módulos que puntúan, «Los criterios».

**Borrar o mudar una pantalla de configuración le puede sacar el sonido a
`Flow::Setup`.** El paso a paso apunta cada paso a una URL
(`Flow::Setup::Step#path`). `setup_nav` es lo ÚNICO que avanza: sin su render
en una pantalla, ahí se corta el recorrido — y el paso sigue apareciendo en el
drawer igual, así que no se nota mirando. Pasó de verdad con el paso
`:form` al mudarlo a la cara del módulo: **`make spec` y `make screens`
quedaron en verde igual**, porque ninguna aserción existente miraba el pie
del paso a paso en la pantalla que se había quedado sin su render (`2029528`,
recién notado en la ronda de revisión de Task 7). Con `:criteria` estuvo por
repetirse al borrar su índice, y se atajó antes de embarcarse: `711ed9b`
borra el índice y suma los dos renders de `setup_nav` en el mismo commit, así
que nunca corrió huérfano. La ceguera de la suite es igual de real ahí, por
otra vía: el test del pie sólo pasaba por `evaluation`, y sacar nada más que
el render de `selection` (el otro kind que embebe el bloque de criterios)
dejaba `make spec` y `make screens` en verde igual (`df0681d`). Quien borre o
mude una pantalla de configuración tiene que revisar `Flow::Setup` y los
renders de `setup_nav` a mano —desde que `shared/_setup_progress` se borró es
el único—, no confiar en la suite para que avise.

### Islas Vue

Cuatro: `pipeline_builder`, `form_editor`, `criteria_editor`, `step_settings`.
Se montan con `app/javascript/islands.js`, que cubre `DOMContentLoaded`,
`turbo:load` y el script que llega tarde, y desmonta en `turbo:before-cache`.

Las props las serializa el **server** (`PipelinePresenter`,
`CriteriaSetPresenter`, `StepSettingsPresenter`) y viajan en un `data-props`:
una vuelta de red menos y la tenencia la garantiza el scope de Ruby, no una
ruta JSON que alguien podría olvidar scopear.

**Las props son el estado INICIAL, no el estado.** Vue no hace reactivas las
props de la raíz: mutarlas cambia los datos y **no redibuja nada**. Copiá a
`data()` una vez y trabajá sobre la copia. El builder
mutaba sus props (`steps.push`, `steps.splice`) y por eso agregar, quitar y
reordenar módulos no se veían — y el segundo clic en una tarjeta fantasma
reventaba con «Cannot read properties of undefined».

Las primeras tres guardan la **lista completa** contra su API (`PUT`), y el
server reconcilia. No agregues un segundo camino de escritura (nested
attributes, endpoints por fila): la pantalla de criterios los tenía y se
sacó. `step-settings` es la excepción: no tiene guardado propio, renderiza sus
campos DENTRO del `form_with` de Rails de `steps/config/_modulo` y viaja en el
mismo PATCH que el nombre y el modo de IA — un solo botón, un solo endpoint
(`steps#update`).

Cuidado con `.compact` sobre el hash de un step en el presenter: se lleva puesto
`aiMode: nil`, que significa «heredá el modo del desafío» y no es lo mismo que
la clave ausente.

### El sistema visual

**Tailwind 4 + DaisyUI 5.** La hoja propia («sin framework CSS: la maqueta
define sus propios tokens») se revirtió a propósito; el porqué y el orden de
migración están en
`docs/superpowers/specs/2026-09-08-rediseno-tailwind-daisyui-design.md`.

La configuración vive **en el CSS** —Tailwind 4 es config-por-CSS, no hay
`tailwind.config.js`—: `app/assets/stylesheets/application.css` abre con
`@import "tailwindcss"`, `@plugin "daisyui"` y los dos temas, y declara con
`@source` dónde buscar clases (`views`, `helpers`, `javascript`). La compila el
**CLI de Tailwind** (`yarn build:css`), no esbuild, que ya solo ve JavaScript;
Sass se jubiló entero. El archivo de salida conserva el nombre, así que el
`stylesheet_link_tag` del layout nunca cambió.

La fase 1 migró la plomería, las clases dinámicas, el tema y el shell. El plan
2a pasó el vocabulario que se repite a componentes: las tablas son `table`, los
avisos `alert alert-soft`, las cuatro familias de chips (estado, origen, tipo
de feedback e IA) y los nodos del mapa del flujo son `badge`, y las tarjetas de
la app se renombraron a `.panel`, a la espera de `card` + `card-body`. Las
marcas sueltas —versión, desactualizada, «acá está el flujo», no pasa un
filtro, filtros sin responder, derivado, las iniciales de quien evaluó— son
`badge` vía `EstilosHelper::CHIPS`, y se piden por nombre con
`chip("version")`: un nombre que no existe revienta, porque es un error de
código y no un estado nuevo del dominio. El plan **2b** hizo las cinco
pantallas de módulo: las tres zonas del shell —trabajo al centro, referencia a
la derecha, «Ajustes del módulo» plegados al final—, la cara de configuración
junta en la misma pantalla, y `.panel` → `card` + `card-body` **ahí**. El plan
**2b-bis** se llevó el resto: las 23 vistas HAML que quedaban y el markup de
tarjeta de las dos islas Vue (`pipeline_builder`, `criteria_editor`) —cuatro
lugares que el spec del 2b no había contado—, y con eso **`.panel` no existe
más**: la regla se borró de la hoja.

El plan **2c cerró, y más chico de lo que estaba fichado.** Decía «el resto de
las islas: su comportamiento, el CSS muerto del editor de criterios y
`.btn-link`», y medido: **las islas no necesitaban nada**. Ya usan `btn`,
`btn-ghost`, `btn-primary`, `alert`, `alert-soft`, `card` y `card-body` de
DaisyUI, y lo que les queda propio —`criterion-edit__*`, `criteria-edit-list`,
`builder__*`, `code-input`, `levels`, `weight-meter`— es vocabulario de esta app,
que es justo lo que la regla de las tres capas dice que tiene que seguir siendo
propio. Lo que sí había era **CSS muerto**: de 402 clases declaradas, 7 sin un
solo uso —los cuatro `criterion-row__*` del markup anterior del editor,
`checks-help`, `inline-label` y `btn-link`—, y se borraron.

**Y el hueco de fondo, que es lo que queda de esa tanda:** `[CLASES]` en
`make screens` caza un ELEMENTO que se quedó sin regla, y nada cazaba lo
contrario —una REGLA que se quedó sin elemento—, que es por lo que se juntaron
siete en silencio. Ahora lo cuida
`spec/lint/reglas_sin_elemento_spec.rb`, con dos excepciones declaradas y con
autotest del detector: el primero que se escribió reportó 267 de 402 «sin uso»
porque HAML escribe `.x` y no `class="x"`, y un detector mal acotado reporta cero
y da verde.

`.step-card`, `.flow-strip` y `.empty-state` siguen siendo clases propias a
propósito: son vocabulario de esta app.

#### Lo que más fácil se rompe

- **`data-theme` va en el `<html>`, pero SÓLO si hay cookie.** El tema oscuro
  es `@plugin "daisyui/theme" { name: "flow-oscuro"; prefersdark: true; }`, y
  `prefersdark` engancha
  `@media (prefers-color-scheme: dark) { :root:not([data-theme]) }`: con el
  atributo presente —**aunque sea con el nombre del tema claro**— ese selector
  no matchea NUNCA y el modo oscuro automático queda muerto. Eso no cambió; lo
  que cambió es que ahora hay una elección a mano, y lo que la sostiene es que
  el atributo se **omite** cuando no hay elección — `tema_elegido` devuelve
  `nil` sin cookie y HAML omite un atributo `nil`. De ahí salen las dos cosas
  que es fácil escribir al revés: «Auto» **borra** la cookie en vez de escribir
  `"flow"` —escribirla dejaría pasar los dos casos obvios, «elegir oscuro
  funciona» y «elegir claro funciona», y mataría el automático en silencio—, y
  lo escribe el **servidor** y no el cliente, así no hay parpadeo en la primera
  pintura y el morph no se lo lleva. Lo mide `[TEMA]`, que es lo único que
  prueba el tercer caso.
- **Son DOS layouts, no uno.** `auth.html.haml` tiene su propio `%html` y no
  pasa por `application.html.haml`: lo usan el login y el check-in público.
  Todo lo que se agregue al `<html>` o al `<head>` va en los dos —el
  `data-theme` está escrito dos veces por eso, y el control de tema se
  renderiza en los dos—, y el login es donde más se nota, porque es lo único
  que ve quien todavía no entró.
- **`light-dark()` es una función de COLOR, y cuando se la usa mal falla hacia
  `none`.** CSS Color 5 la define `light-dark( <color>, <color> )`, y un
  `box-shadow` entero no es un color. Una custom property acepta cualquier
  flujo de tokens, así que `--shadow: light-dark(0 2px 20px …, 0 1px 3px …)`
  declara sin un solo error; lo que revienta es la sustitución —
  `box-shadow: var(--shadow)` queda inválida al computar y cae en **`none` en
  los DOS temas**, medido en el Chromium del recorrido. El token de color de al
  lado, `--borde-superficie: light-dark(transparent, var(--borde))`, **sí**
  anda, porque ése es un color, y es justo lo que hace al error difícil de ver.
  Lo que quedó es declarar los dos tokens **adentro de cada bloque
  `@plugin "daisyui/theme"`**, con sus dos valores planos: DaisyUI pasa a la
  hoja compilada una custom property que no conoce —verificado con una
  propiedad sonda, después borrada—, y el bloque oscuro se emite bajo
  `@media (prefers-color-scheme: dark) { :root:not([data-theme]) }` **y** bajo
  `:root[data-theme=flow-oscuro]`, así que el token sigue a `prefersdark` y al
  camino de la cookie por igual. Y una trampa que casi se lleva el cambio
  puesto: hubo que **borrar el `--shadow` viejo del `:root` propio de la app**.
  DaisyUI emite su tema default en `:where(:root)` —especificidad cero y sin
  capa—, así que un `--shadow` sobreviviente en (0,1,0) le ganaba al valor
  claro nuevo y todo habría dado verde sobre la sombra anterior.
  La moraleja vale más que el bug: el paso de verificación del plan probaba
  `background: light-dark(#fff, #000)`, o sea el caso de color. Una guarda que
  mide una forma distinta de la que gobierna no es que no ayude — **da
  permiso**.
- **El token del color de borde es `--borde`, no `--border`.** DaisyUI usa
  `--border` para el **ancho** de los bordes de sus componentes
  (`border-width: var(--border)`): con el nombre en inglés el color se colaba
  ahí, el ancho quedaba inválido y todos los botones salían con los 3px del
  `medium` por default. No se ve leyendo el CSS; se ve midiendo.
- **Las mezclas van `in oklab`, nunca `in oklch`.** En oklch el tono interpola
  por el arco corto: mezclar el ámbar (82°) con el texto (286°) da la vuelta
  por el rojo y el «amarillo oscuro» sale marrón anaranjado. En oklab no hay
  tono que rotar.
- **Un color con alfa se compone sobre su fondo antes de medir su contraste.**
  `--muted` es `color-mix(… 70%, transparent)`, y medirlo sin componer da un
  número que en pantalla no existe. Si el fondo también es translúcido, se
  compone la cadena hasta el primer opaco.
- **Un tema propio emite SOLO lo que declara**: no hereda nada de los que trae
  la librería. Los 20 colores y los tres escalares van completos **en los dos**
  temas — sin `--depth`, el `color-mix()` del borde de `.btn` queda inválido y
  `border-color` cae en `currentColor`.
- **Lo declarado tiene que ser lo que pinta.** Varios oklch del plan estaban
  fuera del gamut sRGB: el navegador los recorta, y entonces ajustar el croma
  no hace nada hasta cruzar el límite. Los valores de la hoja son la conversión
  exacta del hex y el croma máximo que entra.
- **`badge-soft` y `alert-soft` pintan el texto con el color PURO del tema.**
  La hoja tuvo que oscurecer `success`, `warning` y `error` para el texto de un
  chip (`--ok`, `--warn`, `--danger`), y las variantes suaves no usan esos
  tokens: en tema claro las tres variantes de aviso y de chip quedaban entre
  2,3 y 4,2:1. Se ajustan con una regla de dos clases. `make screens` lo mide
  de dos formas: en cada pantalla (`revisarContraste`) y con un **muestrario**
  que inyecta cada variante en una pantalla real y la mide en claro y en
  oscuro (`revisarMuestrario`). El muestrario existe porque la pasada oscura,
  sola, midió CERO avisos y dio verde: sus pantallas no tienen ninguno. Falla
  si mide menos muestras de las que declara, y un spec exige que cada chip del
  helper esté en el arreglo.
- **Atenuar un contenedor con `opacity` baja el contraste de todo lo de
  adentro**, chips incluidos: un comentario atendido a `.72` los dejaba en
  3:1. La hoja ya lo dice dos veces (`.criterion-edit--off`,
  `.setup__step--outline`): que pese menos —sin superficie, contorno
  punteado, texto en gris—, no que se lea peor. El muestrario mide los chips
  adentro de un comentario atendido de una ronda cerrada, así que volver a
  poner la opacidad lo hace fallar.
- **`alert` es `display: grid` con `grid-auto-flow: column`.** Un aviso con
  varios hijos —un `%strong` y un texto, una lista y un título— los reparte en
  columnas. Envolvé el contenido en un solo `%div`.
- **Renombrar una clase deja muertas en silencio las reglas que la usaban
  desde AFUERA de su bloque.** Al pasar los chips a `badge`,
  `.flow-drawer .status-chip` (los puntos de estado del drawer) y
  `.feedback-item:has(.feedback-kind--issue)` (el borde por tipo) dejaron de
  aplicar, y ni `make spec` ni `make screens` lo notaron: el elemento seguía
  teniendo reglas, sólo que otras. Antes de renombrar, buscá la clase en
  selectores compuestos, descendientes y `:has()`, y en los localizadores de
  `script/capture_screens.js`.
  Esas dos ya no cuelgan del chip: el borde va por `data-kind` y los puntos
  del drawer son `flow-drawer__punto` (`EstilosHelper::PUNTO_DE_ESTADO`).

#### Las tres capas, y de quién es cada regla

Componentes de DaisyUI donde existan · clases propias con nombre semántico para
el vocabulario que es de esta app y se repite (`.flow-strip`, `.step-card`,
`.empty-state`) · utilidades sueltas solo para lo irrepetible. **Si una clase
aparece en más de dos vistas, es un componente, no doce utilidades.**

`card` de DaisyUI está **habilitada**, y el aspecto lo pone la hoja: una
regla `.card` le da superficie, borde, radio y sombra, y fija `--card-p` y
`--card-fs` a lo que medía `.panel` —20px de relleno, la letra del `body`—.
En las vistas se escribe `.card` > `.card-body` y nada más. Estuvo excluida
porque declara `display: flex`, y habilitarla convertía de golpe todas las
tarjetas en columnas flex; por eso las tarjetas de la app se llamaron
**`.panel`** hasta que cada pantalla pasó a `card` (planes 2b y 2b-bis) —ya no
queda ninguna, la regla se borró—. `make screens` falla si aparece un `card`
sin `card-body` (`[PANEL]`): una `card` sin su `card-body` es un error de
maquetado, no una tarjeta sin migrar. Y si aparece un `.panel` reintroducido
—sin ninguna regla detrás, así que queda sin fondo, sin relleno y sin
borde— lo caza `[CLASES]`.

**La superficie se define con una SOMBRA y no con un borde, y eso son tres
tokens.** Es como lo dibuja INNK. `--shadow` tiene **seis** consumidores
—`.card`, `.auth-card`, `.builder__actions`, `.editor-actions`, `.setup-nav` y
el bloque de campos (`input`, `textarea`, `select`)—, y ese censo es lo que
justifica redefinir el token compartido en vez de agregar uno nuevo: quien lo
retoque mueve cada campo de la app junto con las cinco superficies.
`--borde-superficie` alimenta **sólo** a `.card` —`transparent` en claro,
`--borde` en oscuro—. Los radios son `--radius-box: 1rem` (16px, las tarjetas)
y `--radius-field: 0.625rem` (10px, campos y botones), en los dos bloques de
tema; `--radius-selector` se quedó en `0.5rem`.

**`--borde-campo` es nuevo, y es el único lugar donde esta rama se aparta del
diseño de INNK a propósito.** El Figma no le dibuja borde al campo: sólo
sombra. Medido en `/challenges/new` en claro, el contorno en reposo de un campo
sin borde contra la tarjeta que lo contiene daba **1,09–1,12:1** — su fondo es
`var(--surface)`, el MISMO token que el de la tarjeta, los dos blanco puro, y el
borde transparente. El 1.4.11 de WCAG pide 3:1 para el límite de un control, y
este repo ya hace valer ese piso para los puntos del drawer; una sombra blanda
no llega a 3:1 sobre blanco. Así que el campo conserva un hilo: `--borde-campo`
es `--tenue` (3,36:1 medido en el campo de `/challenges/new`) en claro y
`--borde` en oscuro. Lo único en discusión fue el reposo — `input:focus` le
devuelve el borde del acento más un anillo de 3px. De paso ese fallo no sólo
evitó una regresión: el borde del campo claro medía **1,25:1 ANTES** de esta
rama y mide **3,36:1** ahora, así que arregló algo que ya estaba mal.

**`--color-accent` está declarado y NO pinta un pixel.** Es el morado `#8520BD`
de INNK, y es lo que el Figma usa para la pestaña activa, pero nada lo lee: no
hay un `btn-accent`, `badge-accent`, `alert-accent`, `text-accent` ni `bg-accent`
en toda la app, y la hoja no lo referencia fuera de su propia declaración. Lo que
pinta es el `--accent` de la app, que sigue siendo `var(--color-primary)` —el
índigo— en 35 usos directos más 16 de su escalera, `a { color: … }` incluido.
Está declarado porque un tema propio de DaisyUI emite sólo lo que declara y los
20 colores van completos en los dos temas; borrarlo rompe el tema. **Adoptar el
morado es una decisión abierta que nadie tomó**, no un pendiente: repuntar
`--accent` repinta el producto entero. El comentario al lado del token lo dice
igual; la spec del rediseño, en cambio, afirma que el acento «gana un color
propio», que es cierto del token y falso de lo que se ve.

**Deuda medida y deliberadamente NO arreglada acá:** en tema OSCURO el campo
mide **1,13:1** contra su ancestro. Ese borde es `--borde`, o sea `base-300`, el
mismo que tenía antes del rediseño, y la pregunta que quedaba abierta —la paleta
nueva le corrió el TONO a `base-100` y a `base-300` del oscuro, a la misma
luminosidad y croma— ya está contestada: **no es una regresión**. En flotante el
par daba 1,1395 con el tono viejo (285,9°) y da 1,1420 con el nuevo (247,88°),
o sea +0,0025 a favor. El número que se mide en el navegador es 1,134, más bajo
que el flotante porque el canvas cuantiza a 8 bits y estos dos colores están
pegados; con dos decimales, **1,13:1**. Lo que NO es, y lo dijo este archivo
hasta la ronda de arreglos de la revisión final, es 1,05:1: ese número no lo
reprodujo nadie.

**`[CARD]` se retiró, y `[RELLENO]` y `[SOMBRA]` ocupan DOS TERCERAS PARTES de
su lugar: la que queda sin cubrir es `--card-fs`.**
`[CARD]` medía el ASPECTO de una `card` contra `.panel` —los 20px de
`--card-p`, los 14px de `--card-fs` y la sombra— y se borró con ella, porque
sin `.panel` no quedaba contra qué comparar. `[CLASES]` no cubre ese hueco:
marca un elemento sólo si no tiene fondo Y no tiene relleno Y no tiene borde, y
en una `card` el relleno vive en `card-body` —en la `card` misma siempre es 0—,
así que ahí el chequeo se reduce a «tiene fondo o tiene borde».
`[RELLENO]` mide **sólo el relleno**, y no contra otra clase: contra los
números que declara la hoja, escritos a mano en el script (20px, y 16px adentro
de `.app-aside`), con `.card-body.empty-state` exceptuada por selector porque
ahí la hoja declara 44px/20px a propósito. Tiene que ser a mano — DaisyUI sirve
`padding: var(--card-p, 1.5rem)`, así que si la regla `.card` se pierde el
relleno cae solo a 24px y leer `--card-p` del elemento devolvería ese mismo
1.5rem: la comparación se cumpliría sola. Si la hoja cambia esos números, el
script cambia con ella.
**La sombra la mide `[SOMBRA]`** desde que pasó a ser portante, así que de los
tres tercios del viejo `[CARD]` queda **`--card-fs`**, la letra de 14px, que no
la mira nadie —`[CLASES]` mira fondo, relleno y borde; `[RELLENO]`, relleno;
`[CONTRASTE]`, color—: una `card` puede perder su tamaño de letra y las 76
capturas seguir en verde.

**Y hay siete cosas más que ninguna guarda ve, anotadas acá para que nadie
las dé por cubiertas:**

- **`[REFERENCIA]` no mide la sala de la mesa.** `revisarReferencia` se llama
  desde la rama de `[ZONAS]` y desde la de testing, o sea sólo en las pantallas
  de módulo, y la sala es la única otra pantalla que llena
  `content_for :referencia`. Su límite declarado es ése: una mesa muy grande
  queda detrás de su propio scroll.
- **El riel a 414px no lo mira ninguna captura.** `[RIEL]` prueba el cambio de
  columna a fila a 1000px, que es lo que la hoja declara, pero el recorrido no
  fotografía anchos de teléfono: lo que la fila horizontal haga a 414px —si
  desborda, si se corta, si tapa el contenido— no está medido.
- **La regla de la etiqueta a la izquierda tampoco.** Ninguna guarda la ve:
  `[CLASES]` mira una lista fija de familias y además sólo salta si el elemento
  no tiene ninguna regla detrás; `[CAMPO]` mide el borde del campo, no en qué
  columna cayó; y `spec/lint/reglas_sin_elemento_spec.rb` compara NOMBRES de
  clase, no selectores. Si `.field-check` quedara mal escrita en la hoja,
  `make screens` y los 1.682 ejemplos seguirían en verde y el único testigo
  sería alguien abriendo `05e-config-evolucion.png`.
- **El PDF de reportería no lo ejercita NINGÚN test.** Su layout
  (`layouts/pdf.html.haml`) tiene un solo consumidor,
  `Flow::Reports::GenerateJob#render_pdf`, y no hay spec que lo renderice;
  `make screens` tampoco lo abre, porque el archivo lo arma un job y no una
  pantalla. O sea que el único lugar donde la paleta llega a un usuario en algo
  que se descarga es justo el que nadie mira: un error ahí sale impreso y no
  sale en ningún rojo.
- **El autoguardado no avisa en vivo que otra persona de la mesa está
  escribiendo.** Lo más cercano es el sello al recargar. Es a propósito —un push
  pediría el canal autenticado y scopeado por empresa que la spec de la lista de
  llegada ya descartó—, pero que nadie lo dé por cubierto.
- **El camino CONCURRENTE del autoguardado no lo mide nada, y es más de lo que
  parece.** `[DRAFT]` llena los campos seguidos —cada `fill` reinicia el
  debounce— y recién después espera, así que dispara **un solo** `guardar()` por
  cara y nunca hay dos en vuelo. Por lo tanto nada ejercita el `AbortController`
  ni `enVuelo`, ni los dos `form !== enviadoDesde` que impiden que un acuse
  aterrice en el sello de otra idea, ni el `finally` que limpia, ni
  `descargar()`, el `keepalive` y el `visibilitychange` —que cubren «la mesa
  escribe la última frase y medio segundo después cambia de pestaña»—. O sea:
  **todo lo que las dos rondas de arreglo de esa tarea agregaron al camino
  concurrente es exactamente lo que ninguna verificación toca**; borrarlo deja
  la suite y `[DRAFT] 2` en verde. No se le puso guarda a propósito: medirlo
  pide tipear y navegar inmediatamente, y una guarda que depende de ganarle a
  una carrera cuesta más en fallas intermitentes de lo que ahorra.
- **En idear el borrador cuelga de la FILA de la mesa, y el reparto REUSA esas
  filas por índice**, así que puede cambiar de dueños. `seat!` toma
  `workshop_groups.where(arrival: false).order(:created_at)` y le asigna el
  reparto nuevo, de modo que «Mesa 1» puede quedar con gente completamente
  distinta — y en idear el borrador no tiene idea a la cual colgarse: su única
  llave es esa fila. Quien escribió entra a su mesa nueva y no encuentra su
  texto; quien cae en la fila vieja lo recibe prellenado, y si aprieta «Crear
  borrador» se publica una versión con ese texto **a su nombre**. El sello, que
  nombra a quien escribió, mitiga y no arregla. Está **aceptado a propósito**:
  es el precio de «nunca perder el borrador», y las alternativas se miraron —
  borrarlo al repartir pierde texto, y negar el reparto bloquearía una operación
  común por texto sin mandar—. Las propuestas no tienen este problema porque ahí
  el guarda de arriba SÍ se niega a repartir; el borrador es el primer artefacto
  por fila de mesa sin ese guarda.
- **Y la grabación hereda eso mismo, con voces de personas adentro: repartir de
  nuevo le entrega a los ocupantes NUEVOS el audio de los anteriores.** Es el
  mismo mecanismo —`workshop_recordings.workshop_group_id` cuelga de la fila, y
  `seat!` reusa las filas por índice—, pero el cálculo no es el mismo que para
  el texto: lo que cambia de dueños es una conversación grabada, identificable
  por la voz, y la tarjeta de la mesa nueva le ofrece el link para
  **descargarla**. Un borrador se lee y se puede tirar; una grabación se baja.
  Queda **aceptado como límite** y escrito acá porque las dos salidas son
  peores: borrar las grabaciones al repartir destruye lo único irrecuperable
  —«sin el audio una transcripción mala es definitiva»— y negar el reparto
  bloquea una operación común, que es la misma asimetría que el borrador ya
  tiene documentada. Lo que la revisión final SÍ arregló es lo otro: el barrido
  de mesas vacías de `seat!` se las llevaba (ver la cláusula, que ahora también
  pregunta `workshop_recordings.empty?`). Mover mesas a mano, con trabajo
  hecho, sigue siendo lo que la pantalla recomienda.
- **Un envío FALLIDO pierde lo tecleado desde la última pausa de dos
  segundos.** El listener de `submit` pone `sucio = false` —tiene que hacerlo:
  si no, cada envío exitoso recrearía el borrador con lo que el servidor acaba
  de publicar y borrar en la misma transacción, y la mesa lo mandaría de
  nuevo—, y los caminos de rechazo de la sala redirigen con un `alert:`, o sea
  302 → 200, así que `turbo:submit-end` informa `success: true`. Encima el morph
  pisa lo tecleado: Turbo 8 llama a `morphElements` sin `ignoreActiveValue`, así
  que `syncInputValue` le devuelve al campo el valor del servidor, incluso al
  que tiene el foco — o sea que cuando el cliente se entera, el valor del DOM ya
  se fue.
  **No es que no haya salida: no hay salida barata.** El discriminador no es el
  código de estado sino **si el borrador sobrevivió**: capturar el cuerpo en el
  `submit`, y en el render siguiente mirar si `#draft-stamp` volvió NO vacío —el
  servidor no lo borró, o sea que el envío fue rechazado— y recién ahí
  reenviarlo. Cuesta un write por envío rechazado, le da significado semántico a
  «el sello está vacío», que hoy es sólo presentación, y sólo recupera si ya
  había borrador. No se hizo; que no se descarte creyendo que es imposible.

**Dos grillas con el mismo aspecto y mecánica distinta.** En
`challenges/index` las tarjetas son `.challenge-card`, que declara
`display: block` **sin capa** —y una regla sin capa le gana al `display: flex`
de DaisyUI, que vive en un `@layer`—: el `<a>` nunca es contenedor flex, así
que su `card-body` no hereda el alto sobrante de la fila. En
`criteria_sets/index` son `.card` a secas: ahí sí es flex, el sobrante se
reparte ADENTRO y el botón «Editar» queda pegado abajo. Se ven igual; el
motivo no es el mismo.

**La capa decide quién gana, y no es la especificidad.** Las clases propias de
la app van **sin capa**, y una regla sin capa le gana a cualquier `@layer` —o
sea a todo Tailwind y todo DaisyUI—: es lo que sostiene las 1.939 líneas
heredadas sin tener que tocarlas. El precio es que un selector genérico sin
capa pisa un componente: `a { color: … }` suelto le ganaba al `.btn` de DaisyUI
y dejaba un `<a class="btn btn-primary">` con el texto del color del fondo. Los
defaults del navegador que el Preflight borra —y ese color de enlace— van en
`@layer base`, desde donde le ganan al Preflight, pierden contra el componente
y pierden contra las utilidades: si estuvieran sin capa, un `<p class="m-0">`
saldría con el default y la utilidad parecería no haber compilado.

#### Tailwind escanea texto: una clase interpolada no existe

`app/helpers/estilos_helper.rb` traduce estado del dominio → clase y devuelve
siempre el nombre **completo**, escrito literal. Nunca `"badge-#{x}"`: esa
clase no llega a la hoja, el elemento queda sin ninguna regla detrás y en el
DOM se ve perfecto mientras en pantalla no se ve nada. De rebote, la
traducción estado → estilo queda en un solo lugar.

La guarda es `spec/lint/clases_interpoladas_spec.rb` y mira **HAML, `.vue` y
`.js`**: las islas son fuente de Tailwind igual que las vistas, y un `.js`
plano como `ia_popups.js` arma sus diálogos con el mismo template literal que
una isla. En una isla el nombre lo manda el **presenter** en las props
—`PipelinePresenter` resuelve el chip con el mismo `chip_de_estado` que el
HAML— y el componente solo lo liga.

Cada mapeo se prueba **contra su enum**, preguntando si cada estado es clave
del hash (`spec/helpers/estilos_helper_spec.rb`). Antes se comparaba el sufijo
de la clase con `end_with`; con `badge` varios estados comparten la misma clase
—`draft`, `pending`, `closed` y `archived` son el neutro— y el sufijo dejó de
decir qué estado la pidió. Y todo chip empieza con `badge `: un valor que quedó
con el nombre viejo se ve bien hasta que se borra su regla.

Un mapeo escrito como **ternario en la vista** queda afuera de ese spec. El
estado de una propuesta de la mesa (`WorkshopProposal::STATUSES`) vivía así en
`workshop_rooms/_evolution`, de modo que un cuarto estado se habría pintado con
la rama de «descartada» —ámbar, o sea «mirá esta fila»— y con el texto de
traducción faltante al lado, sin que nada se pusiera rojo. Hoy es
`CHIP_DE_PROPUESTA` + `chip_de_propuesta`, con su caso en el spec.

#### El shell de tres regiones

`.app-shell` es una grilla: el flujo del desafío a la izquierda (232px), el
trabajo en el medio y la referencia a la derecha (`--referencia`, 320px).
**Las dos laterales son opcionales y la grilla se acomoda sola con `:has()`**,
así que ninguna pantalla declara su layout.

**Y el shell entero vive adentro de OTRA grilla.** `.app-frame` es la de
afuera, de dos columnas: el riel de navegación global en 80px a la izquierda y
todo lo demás —barra oscura incluida— a la derecha. Por eso el riel arranca
arriba de todo y abarca la barra, y por eso `.app-shell` ni se entera de que
existe. Sólo se dibuja con sesión Y empresa elegida
(`.app-frame--con-riel`): sin eso no hay a dónde navegar y una columna de 80px
vacía se lee como un error. Abajo de 1024px vuelve a una sola columna y el riel
pasa a ser una fila horizontal arriba del contenido — **no se esconde**, que es
lo que `[RIEL]` existe para cuidar.

- La regla de qué va dónde: **el centro es lo que se hace; la derecha es lo que
  se consulta y no se edita** en el curso normal del trabajo. En la cara de
  ejecución de un módulo hay una tercera zona: **«Ajustes del módulo»**, una
  tarjeta plegada al final del centro (`steps/_ajustes`) con lo que se edita
  pero casi nunca —nombre, modo de IA, quién participa—. La referencia va en
  orden fijo: progreso, lo propio del módulo, quién participa, configuración
  congelada —reportería lo tuvo al revés hasta que hubo guarda—. Lo que se lee
  a la derecha y se edita abajo aparece dos veces a propósito, **con la misma
  guarda en los dos lugares**. Las dos cosas las prueba
  `spec/requests/pantalla_del_modulo_spec.rb`: los bloques por rol, y el orden
  con la secuencia de títulos de cada pantalla. Un título que esa lista no
  conoce vuelve marcado con `¿?` en vez de desaparecer, así que sumar una
  tarjeta a la columna obliga a decir dónde va. Un bloque
  que va suelto o adentro de los ajustes toma su forma de `steps/_bloque`.
  **Selección es la única cara de ejecución sin referencia**: su tabla de
  ranking no entra en el centro angosto (plan 2b, Tarea 5). Los ajustes
  plegados sí los tiene, y `make screens` lo espera así
  (`MODULOS_SOLO_AJUSTES`).
- **La referencia tiene que entrar en una pantalla.** Pegada y con
  `max-height: 100vh`, lo que no entra queda tapado detrás de su propio
  scroll. Por eso la densidad la decide la zona: adentro de `.app-aside` una
  `.field-list` va sin recuadro por ítem, con una línea por fila. Debajo de
  1280px, donde sube arriba del trabajo, las tarjetas van en UNA fila que se
  desliza de costado (tope de 320px por tarjeta): en varias filas empujaban el
  título del módulo afuera de la primera pantalla. Lo mide `[REFERENCIA]` en
  `make screens`, a 1440×1000 y a 1100×900 — **pero sólo en las pantallas de
  módulo**: `revisarReferencia` se llama desde la rama de `[ZONAS]` y desde la
  de testing, y de ningún otro lado, así que la columna de la **sala de la
  mesa** —la única otra pantalla que llena `content_for :referencia`— no está
  medida en ninguna captura. Su límite declarado es justamente ése: una mesa muy
  grande queda detrás de su propio scroll.
- El drawer aparece solo si hay un desafío **guardado** en contexto
  (`ShellHelper#desafio_del_shell`). Dos guardas que parecen de más y no lo
  son: `/challenges/new` deja un `Challenge.new` sin slug y el `challenge_path`
  del drawer reventaba la pantalla entera; y sin tenant devuelve `nil`, porque
  un 404 se renderiza **después** del `Current.reset` y la consulta de los
  módulos moriría con `MissingTenant`.
- La referencia la llena el template con `content_for :referencia` y el layout
  la lee **después del `yield`**.
- **No es el componente `drawer` de DaisyUI**: es un `menu` dentro de una
  región de la grilla. El `drawer` pide un checkbox, dos labels y envolver el
  contenido entero. Abajo de 1024px el flujo pasa a ser una tira horizontal
  arriba del contenido, sin una línea de JS y sin que haya que abrir nada.
- La barra es oscura **en los dos temas** (`bg-neutral`): es el shell, no el
  modo oscuro.

#### Lo que carga la jerarquía

- **El ritmo lo pone `.app-main`**, que es `flex` en columna con `gap`. Las
  tarjetas tienen `margin: 0` a propósito: un margen por tarjeta rompería las
  grillas, donde son hermanas con su propio `gap`. Vale igual para `card`: ni
  la regla que le da el aspecto que tenía `.panel` ni `card-body` declaran
  margen, así que toda la app sigue el mismo ritmo y no hay dos reglas que
  mantener. Antes no había ninguno de los dos y las tarjetas se
  **tocaban** — la página era una columna blanca continua partida por
  hairlines. No se ve mirando (el borde doble parece una separación): se ve
  midiendo, y hay guarda en las capturas (`[RITMO]`).
- **`.section-title` es un encabezado, no una etiqueta.** Era 13px en
  mayúsculas y gris, o sea estilo de etiqueta usado en 54 lugares como título
  de sección: nada anunciaba nada. Las mayúsculas chiquitas quedan donde
  corresponden —encabezados de columna, chips—.
- **`--muted` se usa 178 veces**, así que casi todo el texto de la app es gris.
  Subir el contraste del token una vez lo levanta en todos lados; es más
  barato y más parejo que discutir usos.
- **El acento es de las ACCIONES.** Los gráficos van con `--dato` /
  `--dato-fuerte`, una rampa sacada del propio texto: pintar una barra con el
  violeta del botón de al lado la hace leer como un control.

Un `turbo-frame` que siempre se renderiza pero casi siempre está vacío —el de
sugerencias de IA— necesita `display: contents`, o como hijo flex se lleva dos
gaps y abre un hueco de la nada.

#### El formulario: la etiqueta a la izquierda

`.field` es una grilla de dos columnas —`minmax(120px, 190px)` para la etiqueta,
el resto para el control—, que es como lo dibuja INNK. La columna se fija **por
hijo** (`.field > label` a la 1, `.field > :not(label)` a la 2) y no con una
grilla de dos columnas a secas: un `.field` con etiqueta, control y
`.field-hint` mandaría el hint a la columna de la etiqueta. El alcance medido
son **29 `.field` en 12 vistas HAML**, más 3 en las islas — el plan decía «154
en 43 vistas», cinco veces de más, porque contaba también `.field-hint` y
`.field-list*`.

Cinco excepciones. Las tres últimas estaban previstas; las dos primeras
salieron de medir, y la primera además desmiente algo que estaba escrito:

1. **`label.field-check`.** Estaba escrito que «las islas Vue no usan `.field`».
   La usan: `step_settings/config_field.vue` y
   `criteria_editor/criteria_editor.vue`. Y `config_field.vue` pone un
   `label.field-check` como **hermana** de la etiqueta que lleva el nombre del
   campo, no como su rótulo: sin la excepción las dos etiquetas se apilan en la
   columna de 190px y la 2 queda vacía. `.field-check` no aparece en ningún
   HAML — es sólo de Vue.
2. **`fieldset.field { display: block }`.** `step_tests/new.html.haml` es el
   único `fieldset.field` del repo, y en grilla los `.field` de adentro caían en
   la columna 2 del agrupador, con sus etiquetas ~200px a la derecha de las
   demás.
3. **`.app-aside`**: dos columnas no entran en los 320px de la referencia
   (`--referencia`).
4. **Abajo de 1024px**: apilado, como lo dibujan los frames de teléfono del
   diseño.
5. **`.auth-card`**: mide 380px y con 32px de relleno a cada lado quedan 316,
   así que entre la columna de la etiqueta (190px) y el `column-gap` (16px) al
   control le sobraban 110px de cuenta —108 medidos en el navegador—, contra
   los 314px que mide apilado; el hint de la clave caía en seis líneas al lado
   de un canal vacío de 190px. Va por `.auth-card` y no por `.auth-form`,
   porque el formulario del check-in no tiene esa clase.

#### Las fuentes se auto-hospedan

**Open Sans, UNA familia donde había dos.** Vive en `public/fonts` y la declara
la hoja con `@font-face`. **No entra por Google Fonts**: una hoja de un tercero
bloquea el render y, medido, con la petición colgada `DOMContentLoaded` no llega
nunca y la pantalla queda **en blanco** —abortada rendía bien; colgada, no, y
`preconnect` no ayuda contra un agujero negro—. Esa razón no cambió.

Lo que cambió es que títulos y cuerpo son ahora la misma familia, que es lo que
hace el diseño de INNK: `--font-display` y `--font-sans` apuntan las dos a Open
Sans, y la primera se conserva como token nada más que por si alguna vez vuelve
a entrar una display. Es un archivo **variable** del subconjunto latin: un solo
`@font-face` con `font-weight: 300 800` y `font-stretch: 100%` cubre todos los
pesos, así que el rango no es una lista de archivos. Y pesa menos que lo que
reemplaza —48.320 B contra los 125.144 B de Bricolage Grotesque (76.888) más
Inter (48.256), un 61% menos—, con `font-display: swap` y la pila de respaldo
intacta. La licencia OFL acompaña al archivo, que es lo que pide.

El PDF de reportería es la excepción y **no** cuelga de los tokens: lo arma
wkhtmltopdf sin la hoja de la app y sin nadie que resuelva `var()`, así que
`app/views/layouts/pdf.html.haml` lleva los cinco colores como literales y la
fuente del sistema. Si el tema cambia, ese archivo se actualiza a mano — es el
único lugar donde la paleta llega a un usuario en algo que se descarga.

### Las cuentas de demo

`Flow::Demo` es la fuente única: la contraseña que usa el seed y la lista que
muestra el login. Sale de la base y no de una lista escrita a mano, así no se
desactualiza cuando el seed cambia. Se identifica lo sembrado por el sufijo
`.test`, que RFC 2606 reserva y ninguna cuenta real puede tener.

`available?` es `!Rails.env.production?` — con una base real esto sería un
tablón con las llaves puestas. Hay spec de eso.

Un clic precarga el correo por `?email=`, del lado del servidor: la pantalla de
login no carga ningún bundle de JS y no hace falta que empiece a cargarlo.

## Convenciones que se rompen fácil

- **`button_to` es un `<form>`.** Uno dentro de otro es HTML inválido y el
  navegador no lo deja pasar: descarta el interno y sus botones pasan a
  pertenecer al externo. Pasó en la pantalla del corte —los ✓/✗ de veredicto
  vivían dentro del formulario del ranking, así que apretarlos enviaba el
  corte—. No se ve en el DOM (el parser ya lo aplanó) ni en un request spec que
  postea directo: se mira el HTML **servido**. Hay guarda en las capturas y en
  `spec/requests/selection_screen_spec.rb`. Para atar un control a un
  formulario que no lo envuelve, `form: "id-del-form"`.
- **Pundit, no CanCanCan.** Cada policy declara su `Scope` explícitamente
  (`class Scope < ApplicationPolicy::Scope; end`): Pundit usa
  `const_get(:Scope, false)` y no la hereda.
- **Zeitwerk, una constante por archivo.** `AiRunPolicy` y `AssessmentPolicy`
  viven en archivos propios por esto.
- `Criterion` fija `self.table_name = "criteria"` explícitamente: un proceso que
  arranque antes del initializer de inflexiones busca `criterions`.
- HAML no acepta bloques Ruby en una línea (`- coll.each { |e| %li= e }`).
- **`ideas` no tiene columna `title`.** `Idea#title` sale de
  `current_version&.title` y sin versión publicada devuelve `"(sin título)"`
  para TODAS, así que una aserción que compara títulos entre ideas sin versión
  no distingue ninguna de otra — y pasa sola. Pasó de verdad en los specs de la
  sala de la mesa: se asevera sobre la URL de cada idea, o se le publica una
  versión con título propio.
- `submit_tag` usa el primer argumento **como value**: para mandar un valor
  distinto al texto visible, `button_tag`.
- Migraciones: `schema_format = :sql`. Después de migrar, commiteá
  `db/structure.sql`.
- Los commits de este repo van con `ribarahonaa@gmail.com` (ya está en el
  `git config` local; no lo pises).

## Estado y backlog

Maqueta funcional para validar modelo de datos e infraestructura, no un
reemplazo listo para producción.

Pendiente: nada del backlog original. Lo que sigue son decisiones abiertas, no
deuda: **pgvector está construido y espera un proveedor de embeddings con
crédito.** Lo embarcado es todo el camino —`idea_versions.embedding
vector(1024)`, el índice HNSW `index_idea_versions_on_embedding`,
`Flow::Ideas::EmbedVersionJob` encolado al publicar, `Providers::Voyage` y
`Providers::Openai` sobre `HttpEmbeddings`, y `make embeddings`—, y
`DetectDuplicates` ya elige el camino solo (`local?`): con vectores compara por
coseno local, sin ellos le pregunta al modelo por `#complete`. Lo que falta es
la cuenta: Voyage autentica y **no tiene inferencia habilitada** —500 en todo
pedido, está arriba en la capa de IA— y Anthropic no expone embeddings, que es
el motivo de que haya dos variables.

Hoy no hace falta: sin vectores los duplicados los juzga el modelo, y además
los **explica**, que es lo que una persona necesita para decidir si fusiona. El
atajo por vector es un mecanismo de **escala**, no de calidad: entra sólo
arriba de `DetectDuplicates::NEIGHBOURS` (10), y el techo del camino del modelo
es `MAX_CANDIDATES` (40).

Ojo: hasta el 2026-10-06 este párrafo —y el de `README.md`— decían que el orden
era «proveedor de embeddings primero, columna `vector` después» y que agregarla
antes sería guardar algo que nada puede llenar. La columna, el índice, el job y
los dos adapters ya estaban. Es la misma familia de defecto que la rama del
rediseño pagó dos veces, al revés: **un texto que da permiso a creer que algo
no está hecho.**

El plan vigente y el backlog completo están en
`~/.claude/plans/tu-ya-sabes-como-dazzling-cat.md`.

Dos diagramas, los dos con la skill `archify`:

| Fuente | Qué muestra |
|---|---|
| `docs/arquitectura.architecture.json` | Las piezas y por dónde pasa un pedido |
| `docs/proceso.workflow.json` | Cómo se arma y corre un desafío, con sus tres caminos |

```bash
node ~/.claude/skills/archify/bin/archify.mjs deliver architecture \
  docs/arquitectura.architecture.json docs/arquitectura.html --quality showcase
node ~/.claude/skills/archify/bin/archify.mjs deliver workflow \
  docs/proceso.workflow.json docs/proceso.html --quality showcase
```

Trampa del workflow: `mainPath` exige una espina CONTINUA de aristas
consecutivas, y este proceso se bifurca en tres — se saca. Y tres alternativas
no entran en un carril: comparten corredor y el validador las rechaza. Van en
carriles propios, que además es lo que las hace leer como paralelas.

Trampa: el ancho del lienzo está acotado por la legibilidad a 1440px. Sumar un
componente a la derecha hace fallar `composition/desktop-readability` aunque el
resto valide — es preferible ponerlo en una tarjeta antes que achicarle el texto
a todos los nodos.

**`deliver` NO prueba que el diagrama entre en una pantalla.** Sus nueve checks
son estáticos: validan la composición del JSON, no el HTML en un navegador. Eso
lo mide `visual-check`, y por default se SALTEA —«Chrome or Chromium is
unavailable»— así que sale con `ok: false`, `status: "skipped"` y es fácil leerlo
como aprobado. Hay chromium en esta máquina, el que usa `make screens`:

```bash
export ARCHIFY_CHROME=~/.cache/ms-playwright/chromium-1223/chrome-linux64/chrome
node ~/.claude/skills/archify/bin/archify.mjs visual-check docs/arquitectura.html --json
```

**Corrido con eso, los dos diagramas FALLAN el contenido vertical, y venían
fallando.** Medido el 2026-09-30 sobre el HTML de `master`, sin cambios encima:
arquitectura 1339px de alto en un viewport de 900, proceso 1688px. `overflowX` es
false en los dos: el desborde es sólo a lo alto. Re-medido el 2026-10-01 en la
rama `asignacion-de-mesas` con la misma archify: 1345px y 1688px. El 1339 de
arquitectura se quedó viejo por contenido que cambió desde entonces; el reparto
de mesas no movió ninguno de los dos. No lo arregló nadie porque nadie lo había
medido — `deliver` daba verde y `visual-check` se salteaba en silencio.
Arreglarlo es redistribuir el Y y subir el `viewBox`, o sacar contenido, y es
decisión de diseño: el skill prohíbe explícitamente taparlo con `overflow:
hidden` o con letra más chica.
