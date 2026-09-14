# Handoff

## Objetivo

Implementar los **popups de la IA** que la sesión anterior dejó diseñados: un
modal con spinner mientras la IA piensa —no se cierra, bloquea la pantalla— y
otro con la respuesta y la propuesta. De paso arregla el error que en modo
asistido **no se veía nunca**.

Sobre la marcha aparecieron tres cosas más, todas pedidas por Raúl mirando la
app corriendo: que crear un desafío con «Que lo proponga la IA» no mostraba
nada, que una selección necesitaba un mínimo de ideas que pasan, y que el
camino de configuración estaba dibujado en dos lugares a la vez.

El plan de los popups se ejecutó con subagentes: uno por task, revisión después
de cada una, revisión de rama entera al final. Lo demás se hizo inline con test
primero.

## Estado actual

- **`master` en `ff6aa29`, pusheado, 0/0 con `origin`.** Dieciocho commits
  sobre `df20fc9`.
- **No quedan ramas.** `popups-de-ia` se mergeó por fast-forward y se borró
  local y remota (estaba en `cef3c74`); `origin/rediseno-tailwind` también se
  borró (estaba en `beb9a50`). Las dos estaban enteras en `master` —verificado
  con `git rev-list --count master..rama` = 0 antes de borrar—.
- **Verificación sobre `ff6aa29`:** `make spec` da 840 ejemplos, 0 fallas,
  0 warnings. `make screens` saca 37 capturas sin errores de JS ni respuestas
  >= 400.
- **Los dos últimos commits se hicieron directo sobre `master`**, sin ramear.
  Está dicho, no se repitió a escondidas.
- **Hechos del entorno que muerden:**
  - **El push por SSH no anda desde esta shell:** `~/.ssh` no tiene clave.
    Se pushea por HTTPS con el token de `gh`:
    `git -c credential.helper= -c credential.helper='!gh auth git-credential' push https://github.com/ribarahonaa/innk_flow.git <ref>`.
  - **Desarrollo usa el proveedor real:** `FLOW_AI_PROVIDER=anthropic` en
    `.env`. El de **embeddings** es el fixture, y por eso «Detectar duplicados»
    compara local y no cuesta plata — eso es lo que hace posible la captura del
    camino de éxito.
  - **Crear un desafío con «Que lo proponga la IA» ahora bloquea el request
    de 10 a 70 segundos** con el proveedor real, y cuesta plata. Es el
    trade-off elegido; el popup de espera es lo que lo hace tolerable.

## Archivos y cambios

Dieciocho commits. Los dos primeros son de la sesión anterior (el spec y su
handoff).

**Los popups** (`227187f` … `335635b`)

- `flash[:ia]`, un hash con claves **string** (`tipo`, `mensaje`,
  `sugerencia_id`), porque el flash viaja en la cookie como JSON.
  `sugerencia_id` sólo cuando la propuesta quedó pendiente.
- La respuesta viaja en un `<template data-ia-respuesta>` que se renderiza
  **dos veces**: dentro del `turbo-frame#ai-suggestions` y en el layout. Hacen
  falta las dos porque sin la gema `turbo-rails` Rails pinta el layout completo
  y Turbo se queda sólo con el marco. La tarjeta de una propuesta salió a
  `shared/_ai_suggestion`, que usan el panel y el popup.
- `app/javascript/ia_popups.js` arma los dos `<dialog class="modal">` desde los
  eventos de Turbo. Se fue `.ai-waiting` con todo su CSS.
- `recorrido-ia` en `db/seeds.rb` y dos capturas nuevas.

**Lo que salió de usar la app**

- `6d0b67e` — crear un desafío con «Que lo proponga la IA» corre **síncrono**.
  Era el primer pedido a la IA que hace cualquiera y el único que no mostraba
  ninguno de los dos popups. La tabla de qué decir en cada desenlace se mudó a
  `app/controllers/concerns/respuesta_de_ia.rb`, compartida por los dos
  controllers que corren IA de forma síncrona.
- `1f2a81d` — `cut.min`, un **mínimo de ideas que pasan** el corte. Con la
  regla «puntaje mínimo» el corte podía dar CERO y en IA automática dejaba el
  desafío sin finalistas. El piso **gana** sobre la regla, topeado por las
  ideas evaluadas. Default 0.
- `69c884d` — **el paso a paso de configuración son los módulos del flujo**, no
  seis casilleros fijos.
- `ff6aa29` — **el camino se dibuja sólo en el flujo de la izquierda**. La
  tarjeta de arriba se fue de las ocho pantallas y el drawer absorbió lo que
  sabía. Los `current:` escritos a mano se fueron: los infiere
  `ShellHelper#paso_actual_del_setup`, la misma fuente que lee el pie.

`CLAUDE.md` ganó tres reglas: que un `<dialog>` abierto no puede existir
durante un morph, que el camino vive en un solo lugar y quién decide dónde
estás, y qué necesita cada `kind` para contarse configurado.

## Intentos fallidos

- **El layout nuevo rompía la pantalla de 404 en bucle.** `respuesta_de_ia`
  consultaba `AiSuggestion`, que es `TenantScoped`, y `rescue_from` corre
  **afuera** del `around_action`: `render_not_found` pinta el layout con
  `Current` ya reseteado → `MissingTenant` → lo atrapa el mismo `rescue_from` →
  vuelve a pintar. Es la trampa que `ShellHelper#desafio_del_shell` ya
  documentaba. Guarda: `return nil if Current.company.nil?`.
- **Acotar `turbo:fetch-request-error` con `if (!espera)` mató el popup de
  `turbo:frame-missing` en 403 y 500.** El evento es global y el prefetch de
  Turbo lo dispara al pasar el mouse por un link, así que había que acotarlo;
  pero con 4xx/5xx `turbo:submit-end` llega con `success:false` y cierra la
  espera **antes** de que se dispare `frame-missing`. La re-revisión miró sólo
  el caso 200-sin-marco, que sí andaba — **error mío al acotarle el foco**. Lo
  encontró la revisión de rama entera. Se reemplazó por una bandera de pedido
  en vuelo.
- **Tres pedazos del código del plan estaban mal** y se corrigieron al
  ejecutarlo: `Flow::Pipeline#insert` devuelve un `Result`, no el
  `ChallengeStep`; `a[href*="/ideas/"]` agarraba «Postular una idea»; y faltaba
  el clic por link hasta la pantalla del módulo.
- **El spec del congelado de `cut.min` estaba mal escrito.** Intentaba editar
  el `config` de un módulo arrancado, y el modelo rechaza esa escritura:
  `config` está en `FROZEN_ATTRIBUTES`. Lo que hay que probar es que
  `resolve_config!` ESCRIBE la clave.
- **`make screens` atrapó dos veces lo que `make spec` no.** La guarda del
  camino exigía SEIS casilleros fijos: al volverse la lista derivada del
  pipeline fallaron cinco pantallas de una, y al mudarse el camino al drawer
  hubo que repuntarla otra vez. Se actualizó a `2 + 5 + 1` con la aritmética
  escrita, no se aflojó a «más de cero».
- **Un `- if` quedó sin cuerpo** al sacar el render de `setup_progress` de
  `challenges/builder`, y reventó el HAML entero de esa pantalla.
- **Las corridas de `make screens` de las tasks 1 a 3 pasaron en verde sin
  haber abierto los popups ni una vez.** Recién la Task 4 los ejercitó.
- **Un subagente pusheó la rama sin autorización.** Mi encargo no se lo
  prohibía. Si se despachan subagentes que commitean, hay que decírselo.

## Próximos pasos

Las cuatro que recomendé, en una rama, en este orden:

1. **El botón «Pedir la guía de la IA» no se le ofrece a quien puede usarlo.**
   Bug **confirmado**: `assessments/new.html.haml:58` lo muestra con
   `policy(@challenge).update_pipeline?`, pero `evaluate_idea` declara
   `actua_sobre = :assessment` y el pedido lo autoriza
   `AssessmentPolicy#create?`, que dice que sí a quien está **asignado a
   evaluar ese módulo**. Un evaluador asignado puede pedirlo y nunca ve el
   botón. Es el defecto de esta rama dado vuelta: una capacidad que no se
   ofrece.
2. **«Aplicar» en una propuesta informativa no aplica nada.** En duplicados el
   botón promete algo que no hace; corresponde un solo «Listo».
3. **`gestor@demo.test` está sembrado con rol `admin`** (`db/seeds.rb:38`),
   mientras `guia@demo.test` es el que tiene rol `gestor`. La cuenta que se
   llama gestor no lo es, y el login lista esas cuentas.
4. **El camino `_top` no lo recorre ninguna captura.** Es el pedido que
   refresca la pantalla entera, donde el popup convive con el morph: el riesgo
   central del diseño y nada lo ejercita. Las dos capturas nuevas van al marco.
   Se cierra con una tercera, y sigue siendo gratis.

**Ruido documentado, se decidió dejarlo:** `layouts/auth.html.haml` sin el
`next if` de `:ia` (inalcanzable: el flash se barre antes del login y esa
pantalla no carga JS); `esPedidoDeIa` usa `form.action`, que un control
`name="action"` sombrearía (ningún form de la app tiene uno, y `false` sería la
respuesta correcta); el `waitForSelector(state:'detached')` tras «Descartar»
se resuelve por el cierre del cliente y no por la confirmación del servidor (la
propiedad la prueba la segunda corrida de `make screens`); el filtro de permiso
del popup sin test propio (no se puede violar: `request?` **es** `accept?`);
`pedidoEnVuelo` sin red de seguridad en `turbo:submit-end` (el `showModal()`
deja la página inerte, no hay cómo dispararlo); y que la guarda sea por
pedido-en-vuelo y no por correlación por request.

**Sin decidir:**

- `CLAUDE.md` dice «404, nunca 403», pero un `authorize` rechazado devuelve 403
  (`tenant_resolution.rb:70`). O la doc no describe el código, o el código no
  cumple la regla.
- **El `beforeunload` no lo cubre nada** y no lo va a cubrir: Playwright no
  muestra el diálogo nativo en headless.
- **La espera larga real de 10 a 70 segundos nunca se vio de punta a punta**,
  porque cuesta plata. Decisión de Raúl.
