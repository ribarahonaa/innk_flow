# Handoff

## Objetivo

Esta sesión implementó los **popups de la IA** que la sesión anterior dejó
diseñados: mientras la IA piensa aparece un modal con spinner que no se puede
cerrar y bloquea la pantalla, y la respuesta llega en otro modal, con la
propuesta entera y sus botones. De paso arregla el error que en modo asistido
**no se veía nunca**.

El plan se ejecutó con subagentes: uno por task, revisión después de cada una,
y una revisión de rama entera al final.

## Estado actual

- **Rama `popups-de-ia`, en `335635b`, con nueve commits sobre `master`
  (`df20fc9`).** `master` no se tocó.
- **La rama está pusheada a `origin/popups-de-ia`, y eso no estaba
  autorizado.** La pusheó el subagente de la ola de arreglo final a las
  11:57 del 14/9 (`update by push` en el reflog de la ref remota), cinco
  minutos después de su commit. El encargo no se lo prohibía. Local y remoto
  están idénticos, así que no hay divergencia; queda a decisión de Raúl
  dejarla o borrarla del remoto.
- **Verificación sobre `335635b`:** `make spec` da 799 ejemplos, 0 fallas,
  0 warnings (corrido por mí, no sólo por los subagentes). `make screens` saca
  37 capturas sin errores de JS ni respuestas >= 400, y se corrió **dos veces
  seguidas** para probar que el «Descartar» del final deja la base limpia.
- **Hechos del entorno que muerden** (siguen valiendo):
  - **El push por SSH no anda desde esta shell:** `~/.ssh` no tiene clave.
    `git ls-remote` por SSH da `Permission denied (publickey)`. Se pushea por
    HTTPS con el token de `gh`:
    `git -c credential.helper= -c credential.helper='!gh auth git-credential' push https://github.com/ribarahonaa/innk_flow.git <ref>`.
  - **Desarrollo usa el proveedor real:** `FLOW_AI_PROVIDER=anthropic` en
    `.env`. El de **embeddings** es el fixture, y por eso «Detectar duplicados»
    compara local y no cuesta plata — eso es lo que hace posible la captura del
    camino de éxito, y se verificó al arrancar la Task 4.

## Archivos y cambios

Nueve commits. El primero es el plan; los ocho siguientes, el trabajo.

1. **`7875788`** el plan: `docs/superpowers/plans/2026-09-14-popups-de-ia.md`.
2. **`227187f`** el pedido a la IA registra qué pasó en `flash[:ia]`.
   Un hash con claves **string** (`tipo`, `mensaje`, `sugerencia_id`), porque el
   flash viaja en la cookie como JSON. `sugerencia_id` sólo cuando la propuesta
   quedó pendiente. El layout saltea `:ia` en su loop de flash.
3. **`853d3e2`** dos aserciones que habían quedado siempre verdaderas
   (`duplicados_spec.rb:110`, `gestor_spec.rb:255`) pasan a mirar `flash[:ia]`.
4. **`97219d2`** la respuesta viaja en un `<template data-ia-respuesta>`, que se
   renderiza **dos veces**: adentro del `turbo-frame#ai-suggestions` y en el
   layout. Hacen falta las dos porque sin la gema `turbo-rails` Rails pinta el
   layout completo y Turbo se queda sólo con el marco. La tarjeta de una
   propuesta salió a `shared/_ai_suggestion`, que ahora usan el panel y el popup.
5. **`b7f481d`** `ApplicationHelper#respuesta_de_ia` no consulta `AiSuggestion`
   sin tenant. Ver «Intentos fallidos».
6. **`7c8885e`** `app/javascript/ia_popups.js`: los dos popups, armados por JS
   desde los eventos de Turbo. Se fue `.ai-waiting` con todo su CSS.
7. **`4ae9685`** se acotan los dos listeners globales y se arregla el handler de
   `close`, que cerraba sobre la variable del módulo en vez del elemento.
8. **`7c38ae5`** `recorrido-ia` en `db/seeds.rb` y las dos capturas nuevas
   (`09-13-ia-espera`, `09-14-ia-respuesta`).
9. **`335635b`** los hallazgos de la revisión de rama entera.

`CLAUDE.md` ganó la regla de que un `<dialog>` abierto no puede existir durante
un morph, y la frase de la guarda de clases interpoladas ahora dice «HAML,
`.vue` y `.js`» — porque el lint se amplió a los `.js`, que es donde vive la
primera clase de Tailwind escrita desde JavaScript.

## Intentos fallidos

- **El layout nuevo rompía la pantalla de 404 en bucle.**
  `respuesta_de_ia` consultaba `AiSuggestion`, que es `TenantScoped`, y
  `rescue_from` corre **afuera** del `around_action`: `render_not_found` pinta
  `layout: "application"` con `Current` ya reseteado → `MissingTenant` → lo
  atrapa el mismo `rescue_from` → vuelve a pintar. Es la misma trampa que
  `ShellHelper#desafio_del_shell` ya documentaba. Guarda:
  `return nil if Current.company.nil?`.
- **Acotar `turbo:fetch-request-error` con `if (!espera)` mató el popup de
  `turbo:frame-missing` en 403 y 500.** El evento es global y el prefetch de
  Turbo lo dispara al pasar el mouse por un link, así que había que acotarlo;
  pero con una respuesta 4xx/5xx `turbo:submit-end` llega con `success:false`,
  cierra la espera y pone `espera` en `null` **antes** de que se dispare
  `frame-missing`. El caso 200-sin-marco (sesión vencida) sí andaba, y la
  re-revisión miró sólo ése. Lo encontró la revisión de rama entera. Se
  reemplazó por una bandera de pedido en vuelo.
- **Tres pedazos del código del plan estaban mal y se corrigieron al
  ejecutarlo:** `Flow::Pipeline#insert` devuelve un `Result`, no el
  `ChallengeStep`; el selector `a[href*="/ideas/"]` agarraba «Postular una idea»
  (`/ideas/new`) y no una idea, así que va `a.idea-list__link`; y faltaba el
  clic por link hasta la pantalla del módulo, porque el resumen del desafío no
  tiene ni los formularios de IA ni links a ideas.
- **`make screens` no prueba los popups hasta la Task 4.** Las corridas de las
  tasks 1 a 3 pasaron en verde sin haberlos abierto una sola vez. Si algo de
  `ia_popups.js` estuviera roto, esas tres corridas no lo hubieran dicho.
- **`revisarClasesDescartadas` no mira las clases del modal.** Su selector es
  `[class*="badge"],[class*="btn"],[class*="alert"],.steps,.card`, así que de lo
  que arma el JS alcanza sólo al ✕ y a Aplicar/Descartar. El comentario de la
  captura decía lo contrario y se corrigió.

## Próximos pasos

1. **Decidir qué pasa con la rama**, que es lo único abierto: mergear a
   `master`, abrir un PR, o dejarla. Y decidir si `origin/popups-de-ia` se
   queda o se borra, dado que se pusheó sin autorización.
2. **Lo que la rama deja sin verificar**, por si vale cerrarlo:
   - **El camino `_top` no lo recorre ninguna captura.** Las dos nuevas
     responden al marco (el propósito inexistente cae ahí por el rescue, y
     «Detectar duplicados» es informativa). El camino de «Mejorar con IA», el
     «IA» de la evaluación y cualquier módulo en `ai_auto` —que es donde el
     popup convive con el morph, el riesgo central del diseño— no se fotografía.
     Una tercera captura con el pedido retenido lo cerraría, y sigue siendo
     gratis.
   - **El `beforeunload` no lo cubre nada** y no lo va a cubrir: Playwright no
     muestra el diálogo nativo en headless.
   - **La espera larga de verdad (10 a 70 segundos) nunca se vio**, porque
     cuesta plata. Es decisión de Raúl.
3. **Menores que se decidió no arreglar**, con su razón:
   - `layouts/auth.html.haml` no saltea `:ia` en su loop de flash. Inalcanzable:
     el flash se barre antes de llegar al login, y esa pantalla no carga JS.
   - `esPedidoDeIa` usa `form.action`, que un control `name="action"`
     sombrearía. Ningún formulario de la app tiene uno, y el resultado `false`
     sería el correcto igual.
   - El `waitForSelector(state:'detached')` tras «Descartar» se resuelve por el
     cierre del cliente, no por la confirmación del servidor. La propiedad que
     importa la prueba la segunda corrida de `make screens`.
   - El filtro por permiso del popup (`policy(sugerencia).accept?`) no tiene
     test propio. No se puede violar: `AiSuggestionPolicy#request?` **es**
     `accept?`, así que quien pidió siempre puede revisar.
   - `pedidoEnVuelo` no tiene red de seguridad en `turbo:submit-end` como sí la
     tiene `espera`. Sólo importaría con un pedido abortado a mitad de camino, y
     el `showModal()` deja la página inerte, así que no hay cómo dispararlo.
4. **Anotados de antes, sin decidir:**
   - Borrar `origin/rediseno-tailwind`.
   - Cambiar «Aplicar/Descartar» por un solo «Listo» en las propuestas
     informativas: en duplicados, «Aplicar» no aplica nada.
   - `gestor@demo.test` está sembrado como admin (`db/seeds.rb:38`).
   - `CLAUDE.md` dice «404, nunca 403», pero un `authorize` rechazado devuelve
     403 (`tenant_resolution.rb:18,70`).
   - **Sin verificar:** en `assessments/new`, el botón «Pedir la guía de la IA»
     se muestra con `update_pipeline?`, pero el pedido lo autoriza
     `AssessmentPolicy#create?`. Un evaluador asignado podría pedirlo y no ve el
     botón.
