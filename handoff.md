# Handoff

## Objetivo

Esta sesión cerró los pendientes del handoff anterior, integró
`rediseno-tailwind` en `master` y diseñó los **popups de la IA**. El diseño
pide dos cosas: que mientras la IA piensa aparezca un modal con spinner, que no
se puede cerrar y bloquea la pantalla, y que la respuesta también llegue en un
modal, con la propuesta completa. Lo que sigue es implementar esos popups.

## Estado actual

- **`master` está en `df20fc9`, pusheado, 0/0 con `origin`.**
  - `rediseno-tailwind` entró por fast-forward (74 commits) y se borró la rama
    local. `origin/rediseno-tailwind` sigue en GitHub en `beb9a50` y está
    entera en `master`.
  - `origin/configurar-vs-ejecutar` se borró.
- **Rama actual: `popups-de-ia`, que sale de `master`.** Tiene el commit del
  spec (`56bfc76`) y el de este handoff, ninguno pusheado. No tiene código.
- **El diseño de los popups** lo aprobó Raúl sección por sección en el chat. El
  archivo del spec escrito **todavía no lo revisó**: es el último paso del
  brainstorming y quedó pendiente.
- **Verificación sobre `df20fc9`:** `make spec` dio 786 ejemplos, 0 fallas y
  0 warnings (eran 21 por corrida). `make screens` sacó las 35 capturas sin
  errores de JS ni respuestas >= 400.
- **Hechos del entorno que muerden:**
  - **El push por SSH no anda desde esta shell:** `~/.ssh` no tiene clave y no
    hay agente. Se pushea por HTTPS con el token de `gh`, sin tocar la
    configuración:
    `git -c credential.helper= -c credential.helper='!gh auth git-credential' push https://github.com/ribarahonaa/innk_flow.git <ref>`.
    Raúl autorizó los pushes de esta sesión. Para la próxima, preguntar.
  - **Desarrollo usa el proveedor real:** `FLOW_AI_PROVIDER=anthropic` en
    `.env`, así que cada pedido a la IA cuesta plata. Los vectores, en cambio,
    son del fixture, y por eso `detect_duplicates` compara local y no llama a
    nadie.

## Archivos y cambios

Esta sesión dejó siete commits. Los seis primeros están en `master` y el
último, en `popups-de-ia`:

1. **`b87c781` Los cuatro minors de la revisión final.**
   - El comentario de `StepSettings.filtrar` ahora describe la lectura real,
     que se hace desde `config`.
   - Se fue el `id:` sin uso del form de biblioteca en `_criterios_editor`.
     `form_with` no genera id en Rails 7.1: lo verifiqué renderizando.
   - Barrido de `PipelinePresenter`: del módulo salieron `slug`, `status` y
     `removable`; de la raíz, `insertionFloor`; y del desafío, seis claves.
     Del desafío quedan solo `slug`, `aiDefaultMode` y `lockVersion`.
   - La regla «con criterios propios no hay vuelta a la biblioteca» quedó en
     `CLAUDE.md`.
2. **`1329d99` `:unprocessable_entity` → `:unprocessable_content`**, en cinco
   controllers y cuatro specs.
3. **`85fa023` `ProposePipeline`.**
   - Filtra el `config` con `StepSettings.filtrar`.
   - Método nuevo, `StepSettings.json_schema(kind)`: el schema de la propuesta
     es un `anyOf` con una variante por kind. Antes era `config: object`, y el
     adapter de Anthropic lo cerraba, así que el modelo real no podía proponer
     ninguna configuración.
   - Se arregló el fixture: mandaba `cut_mode` plano y la clave es `cut.mode`.
     La guarda está en `fixtures_spec`.
4. **`695d37e` `shared/_ai_suggestions` filtra cada propuesta con
   `AiSuggestionPolicy#accept?`.** Spec: `spec/requests/panel_de_propuestas_spec.rb`.
5. **`beb9a50` Pedir y aceptar son el mismo método.** `AiRequestsController#autorizar!`
   arma una propuesta de mentira y pregunta `request?`, que es `accept?`. La
   policy perdió el atajo `return true if manager?`, que dejaba aplicar
   propuestas sobre desafíos cerrados.
6. **`df20fc9` Duplicados.**
   - Alcance nuevo, `:pool`, resuelto por `ChallengePolicy#curate_pool?`: quien
     administra, o el gestor asignado. El botón de `ideas/show` pregunta lo
     mismo.
   - Hook nuevo, `Tasks::Base#informativa?`: el Runner corre esas tareas
     asistidas en cualquier modo, y `marco_para_pedido_de_ia` las manda al
     marco de propuestas.
   - Specs: `spec/requests/duplicados_spec.rb` y `runner_spec`.
7. **`56bfc76` (en `popups-de-ia`): el spec**
   `docs/superpowers/specs/2026-09-11-popups-de-ia-design.md`.

Fuera de git: se borró `.superpowers/sdd/2026-09-09-configurar-vs-ejecutar/`,
que estaba en `.gitignore`. Queda `.superpowers/sdd/2026-09-08-rediseno-tailwind-fase-1/`
sin tocar.

## Intentos fallidos

- **Diagnostiqué mal el panel de propuestas.** Supuse que `challenges/show`
  mostraba propuestas sobre ideas ajenas, y el primer spec falló incluso para
  el admin. Pero cada `AiSuggestion` cuelga de **un** objetivo (el
  `target_attributes` de la tarea: desafío, módulo o idea), y cada pantalla
  filtra por esa columna. Antes de suponer dónde aparece una propuesta, hay
  que mirar el `target_attributes` de la tarea.
- **`AiSuggestion.new(purpose: …)` revienta** con `UnknownAttributeError`,
  porque `purpose` se delega al `ai_run`, y la suite dio 26 fallas hasta
  arreglarlo. Se arma así: `AiSuggestion.new(ai_run: AiRun.new(purpose: …), …)`.
- **La regla de `informativa?` estuvo primero en `resolved_mode` del
  controller.** Funcionaba, pero dejaba afuera a cualquier otro que llamara al
  Runner, así que se movió a `Runner#initialize`.
- **`git fetch`/`push` por SSH dan `Permission denied (publickey)`.** Ver el
  comando HTTPS en «Estado actual».
- **`git branch -d rediseno-tailwind` se negó antes del push,** porque el
  upstream no tenía los últimos commits. Después del push pasó. No se forzó.
- **`bin/rails runner '…'` con código Ruby inline se rompe por las comillas.**
  Hay que pasar un script por stdin: `bin/rails runner - < script.rb`.
- **Dos afirmaciones del handoff anterior eran falsas:**
  - que el `id:` del form de biblioteca «sigue siendo necesario»;
  - que el próximo paso literal era `finishing-a-development-branch`, que era un
    resto del orden del ledger.
- **La salida estructurada de Anthropic no documenta topes de complejidad.**
  El schema por kind de `ProposePipeline` (3,4 KB) no se probó contra la API
  real.

## Próximos pasos

1. **Que Raúl revise el spec escrito:**
   `docs/superpowers/specs/2026-09-11-popups-de-ia-design.md`.
2. **Con el spec aprobado, `superpowers:writing-plans`** para armar el plan de
   implementación, en la rama `popups-de-ia`.
3. **Ejecutar el plan** con test primero. En cada transición, avisar «task N en
   ejecución» y pedir permiso antes de pasar a la siguiente. Lo que ya sabemos
   y el plan tiene que respetar:
   - Sembrar el desafío `recorrido-ia` en `db/seeds.rb`: en curso, Idear
     abierto en modo asistido y dos ideas postuladas. No usar `sin-formulario`,
     `onboarding-remoto` ni `optimizacion-de-la-experiencia-de-onboarding`.
   - `make screens` no puede llamar a la IA real. Para el camino de error, un
     pedido con un propósito inexistente, que se rechaza antes del proveedor.
     Para el de éxito, «Detectar duplicados», que compara local. Al final del
     recorrido hay que apretar Descartar para no dejar la propuesta pendiente.
   - Rails renderiza el layout completo también en los pedidos de marco (no
     está la gema `turbo-rails`): por eso el `<template>` va en el marco **y**
     en el layout.
4. **Anotados, sin decidir:**
   - Borrar `origin/rediseno-tailwind`.
   - Cambiar «Aplicar/Descartar» por un solo «Listo» en las propuestas
     informativas: en duplicados, «Aplicar» no aplica nada.
   - `gestor@demo.test` está sembrado como admin (`db/seeds.rb:38`).
   - `CLAUDE.md` dice «404, nunca 403», pero un `authorize` rechazado devuelve
     403 (`tenant_resolution.rb:18,70`).
   - **Visto de pasada, sin verificar:** en `assessments/new`, el botón «Pedir la
     guía de la IA» se muestra con `update_pipeline?`, pero el pedido lo
     autoriza `AssessmentPolicy#create?`. Un evaluador asignado podría pedirlo
     y no ve el botón.
