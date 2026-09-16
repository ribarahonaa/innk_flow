# Handoff

## Objetivo

Los **cuatro puntos** que la sesión anterior dejó recomendados, en el orden en
que los dejó: un botón que no se le ofrecía a quien podía usarlo, un «Aplicar»
que no aplicaba nada, una cuenta de demo que mentía sobre su rol, y el camino
`_top` del popup de la IA sin ninguna captura que lo recorriera.

Los cuatro son el mismo defecto de la rama anterior en distintas formas: un
control que promete lo que no hace, o que no aparece donde tendría que
aparecer.

Se hizo inline con test primero, y dos rondas de revisión: la de rama entera y
una re-revisión de los arreglos.

## Estado actual

- **Rama `arreglos-de-permisos-y-demo`, ocho commits sobre `ad56dde`,
  `9a7fbaa` la punta. SIN PUSHEAR y sin mergear.** `master` quedó donde
  estaba.
- **Verificación sobre `9a7fbaa`:** `make spec` da 848 ejemplos, 0 fallas
  (eran 840). `make screens` saca 38 capturas sin errores de JS ni respuestas
  >= 400.
- **El seed se corrió contra la base de desarrollo** para verificar el
  renombre de la cuenta: conservó sus 2 ideas, la identidad viajó con ella y
  no quedó nada con el correo viejo. La base quedó sembrada.
- **Hechos del entorno que siguen valiendo** (de la sesión anterior, todos
  confirmados):
  - El push por SSH no anda: `~/.ssh` no tiene clave. Va por HTTPS con el
    token de `gh`:
    `git -c credential.helper= -c credential.helper='!gh auth git-credential' push https://github.com/ribarahonaa/innk_flow.git <ref>`.
  - Desarrollo usa el proveedor real (`FLOW_AI_PROVIDER=anthropic` en `.env`).
    El de **embeddings** no está declarado, así que cae al fixture: por eso
    «Detectar duplicados» compara local y las capturas lo pueden pedir dos
    veces sin gastar un peso.

## Archivos y cambios

Ocho commits: cuatro de los puntos, cuatro de lo que encontraron las
revisiones.

**Los cuatro puntos**

- `d89572c` — **el botón «Pedir la guía de la IA»**. La ficha de evaluación lo
  mostraba con `update_pipeline?`, pero `evaluate_idea` declara
  `actua_sobre = :assessment` y el pedido lo autoriza `AssessmentPolicy#create?`.
  Un evaluador asignado podía pedirlo y nunca lo veía. Es la misma expresión
  que `steps/evaluation.html.haml:23` ya usaba para el lote, escrita a mano en
  la otra pantalla. La tabla de alcances de `CLAUDE.md` no listaba
  `:assessment`.
- `2aec5e9` — **un solo «Listo» en las propuestas informativas**. Detectar
  duplicados no aplica nada, y ofrecía igual «Aplicar» y «Descartar». Quién lo
  decide es la tarea, vía `AiSuggestion#informativa?`.
- `2e5a3bb` — **`gestor@demo.test` → `admin2@demo.test`**. Estaba sembrada con
  rol `admin`; la única con rol `gestor` es Gina. Se renombra EN EL LUGAR
  (usuario e identidad), porque `upsert_user!` busca por correo y una base ya
  sembrada quedaría con las dos. Guarda nueva: `spec/lint/cuentas_de_demo_spec.rb`.
- `b3f4620` — **la captura del camino `_top`**, con contador de `turbo:morph`.

**Lo que encontraron las revisiones**

- `985acab` — el aviso `"Sugerencia aplicada."` quedó sin una sola aserción al
  bifurcarse. `Tasks::Base.informativa?` reemplaza dos resoluciones a mano del
  propósito. Los tres helpers del aviso bajan a `private`.
- `bbad996` — la captura `_top` pasa a ir por el **éxito** y no por un
  propósito inventado: así el popup trae la tarjeta, que es un `<form>` dentro
  del `<dialog>`. Y el wait espera al form concreto en vez de a que no quede
  ninguna `.ai-suggestion`.
- `ab52780` — `puede_pedir` inline y último en el `&&`; `FILA_DE_CUENTA`; la
  nota de que el renombre del seed es una migración de datos.
- `9a7fbaa` — el accept final de la captura no se esperaba y el `goto` de
  `shot()` lo cancelaba; el mensaje de la guarda mentía sobre lo que prueba;
  `marco_para_pedido_de_ia` y `_ai_suggestion` seguían con rescues anchos; los
  tres conteos.

`CLAUDE.md` ganó tres cosas: la fila `:assessment`, el párrafo del «Listo» de
las informativas, y la lección de la guarda que cuenta eventos.

## Intentos fallidos

- **La guarda del morph pasaba por la razón equivocada.** Cuenta
  `turbo:morph` para probar que el pedido refrescó la pantalla entera, pero el
  clic anterior —«Listo»— también sale a `_top` y su diálogo se saca en
  `turbo:submit-start`, o sea ANTES del morph: esperar a que el diálogo se
  detache dejaba esa navegación en vuelo y el contador registraba ÉSE. **No se
  descubrió leyendo la guarda: se descubrió apuntando el pedido al marco a
  propósito y viendo que pasaba igual.** Está en `CLAUDE.md`.
- **El `private` dentro de `class << self` de `Tasks::Base` se llevó puesto
  `.for`**, que venía después. 50 specs en rojo de una. El método privado va
  al final del bloque, no en el medio.
- **Un `begin/rescue/end` no entra en HAML**: «You don't need to use "- end"».
  Intentar acotar ahí el `rescue nil` del partial puso 50 specs en rojo. El
  lugar del rescue acotado es el modelo (`AiSuggestion#tarea`).
- **Puse 39 capturas antes de contarlas**, cuando eran 38. Y el conteo de
  `capturar()` decía «nueve de las treinta»: son 25 de 38, contadas con `comm`
  contra los nombres que pasan por `shot()`.
- **La primera revisión no vio dos de los tres conteos desactualizados**,
  incluido el `make spec # 743 ejemplos` de la línea de arriba de la que sí
  arregló. Los encontró la re-revisión.

## Próximos pasos

1. **Pushear y mergear la rama.** Las dos revisiones dan «listo para
   mergear»; no quedó ningún hallazgo sin atender.
2. **`CLAUDE.md` dice «404, nunca 403», y un `authorize` rechazado devuelve
   403** (`tenant_resolution.rb:70`). Sigue sin decidir desde la sesión
   anterior: o la doc no describe el código, o el código no cumple la regla.
   Vale mirarlo con la tabla de alcances a mano, porque esta rama movió
   justamente quién puede pedir qué.
3. **El conteo de pantallas vive en tres lugares** (`README.md:137`,
   `CLAUDE.md:45`, `script/capture_screens.js:151`) y se desactualizó en los
   tres. Se pueden derivar del propio script, o aceptar que envejecen.
4. **La espera larga real de 10 a 70 segundos sigue sin verse de punta a
   punta**, porque cuesta plata. Decisión de Raúl, de la sesión anterior.
5. **El `beforeunload` sigue sin cubrir nada** y no lo va a cubrir: Playwright
   no muestra el diálogo nativo en headless.

**Ruido documentado, se decidió dejarlo:** `puede_pedir` en
`assessments/new.html.haml` no puede dar `false` —el controller ya autorizó
`create?` con la idea real, y sin idea la policy es más permisiva—, se
pregunta igual porque la vista no puede depender de lo que autorizó el
controller; el renombre del seed es una migración de datos que corre en cada
`make setup` sin hacer nada (dice cuándo se puede borrar); y `FILA_DE_CUENTA`
sigue siendo una constante en el namespace global, que es lo que pasa con
cualquier constante dentro de un bloque de RSpec y la convención del
directorio.
