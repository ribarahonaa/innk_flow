# Rediseño Tailwind + DaisyUI · Fase 1 (fundaciones)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dejar la app corriendo sobre Tailwind 4 + DaisyUI 5, con el carácter «Producto» y el shell de tres regiones, sin haber migrado todavía pantalla por pantalla.

**Architecture:** Cinco tareas en orden estricto. Las dos primeras son mecánicas y se verifican por «no cambió nada»: primero se reemplaza la herramienta de build sin tocar una regla de CSS, después se mudan a helpers las clases que Tailwind descartaría. Recién entonces entra DaisyUI —resolviendo las dos únicas clases que colisionan—, cambia el tema, y se construye el shell. Cada tarea se mergea sola con la suite y las capturas en verde.

**Tech Stack:** Rails 7.1 · HAML · Turbo 8 (morphing) · esbuild · Vue 3 (3 islas) · Tailwind CSS 4.3.3 · DaisyUI 5.7.28

**Spec:** `docs/superpowers/specs/2026-09-08-rediseno-tailwind-daisyui-design.md`

## Global Constraints

- **Todo en español**: código, comentarios, mensajes de commit, texto de pantalla.
- **Todo corre en Docker.** Nunca `bundle exec` ni `yarn` en el host. Comandos: `make spec`, `make spec-file FILE=…`, `make screens`, `make yarn-build`, `make rebuild`.
- **Los specs corren en `app_test`**, vía `make spec*`. Usar `docker compose exec app bundle exec rspec` da 403 «Blocked hosts» en todos los request specs y parece que la app está rota.
- **`node_modules` es un volumen anónimo** instalado dentro de la imagen (`Dockerfile.dev` hace `COPY package.json yarn.lock` + `yarn install --check-files`). Agregar un paquete npm exige **`make rebuild`**; `make yarn-install` escribe en el volumen anónimo y se pierde al recrear el contenedor.
- **Versiones exactas:** `tailwindcss@4.3.3`, `@tailwindcss/cli@4.3.3`, `daisyui@5.7.28`.
- **Rama:** `rediseno-tailwind`. No se mergea a `master` hasta que las cinco tareas estén verdes.
- **`make screens` es la verificación end-to-end real.** Falla por error de JS, HTTP ≥ 400, isla sin montar, formulario anidado, plural en inglés y morphing roto. Correrlo después de cada tarea.
- **HAML no acepta bloques Ruby en una línea** (`- coll.each { |e| %li= e }`).
- **No se suma JavaScript.** Ni Stimulus, ni Alpine. DaisyUI es CSS puro.
- **Acento provisorio:** `#5b3df5`. Vive en `--color-primary`; cambiarlo es una línea.

---

## Estructura de archivos

| Archivo | Responsabilidad | Tarea |
|---|---|---|
| `package.json` | Dependencias y el script `build` que corre esbuild **y** Tailwind | 1, 3 |
| `esbuild.config.js` | Solo JS: las islas y `application.js`. Deja de construir CSS | 1 |
| `app/assets/stylesheets/application.css` | Entrada de Tailwind. Reemplaza a `application.scss` | 1, 3, 4 |
| `app/helpers/estilos_helper.rb` | **Nuevo.** Traduce estado de dominio → clase completa. Único lugar donde vive ese mapeo | 2 |
| `spec/lint/clases_interpoladas_spec.rb` | **Nuevo.** Falla si una vista arma una clase con `#{}` | 2 |
| `spec/helpers/estilos_helper_spec.rb` | **Nuevo.** Cubre el mapeo y el default | 2 |
| `script/capture_screens.js` | Suma la revisión de clases descartadas por el escaneo | 3 |
| `app/views/layouts/application.html.haml` | El shell de tres regiones | 5 |
| `app/views/layouts/_flow_drawer.html.haml` | **Nuevo.** La barra lateral con el flujo del desafío | 5 |
| `app/helpers/shell_helper.rb` | **Nuevo.** Decide si la pantalla lleva drawer y con qué desafío | 5 |

**Fuera de esta fase** (van al plan 2, que se escribe cuando la tarea 5 esté
mergeada, porque la forma que deben tomar los partials depende del shell):

- Los 18 partials compartidos y la migración pantalla por pantalla.
- Los 7 componentes Vue (119 clases).
- **El resto del mapeo a DaisyUI** del §4 del spec: `status-chip` → `badge`,
  `flow-strip` → `steps`, `flash` → `alert`, `step-table` → `table`. Acá solo se
  migran `btn` y `card`, y solo porque colisionan.
- **El gancho de `turbo_confirm` → `<dialog>`.** Es la única excepción a «no se
  suma JavaScript» que el spec autoriza, y depende de que los modales ya estén
  en uso: hacerlo antes sería escribir el gancho contra nada.
- **Mover las clases propias a `@layer components`.** En esta fase las 1.939
  líneas pasan tal cual y funcionan: Tailwind deja pasar el CSS plano. El
  reordenamiento en capas se hace cuando esas reglas empiecen a competir con
  las de DaisyUI, no antes.

---

## Task 0: La rama

- [ ] **Step 1: Confirmar que el árbol está limpio y la suite verde**

```bash
cd /home/ribarahonaa/innk_flow
git status --short          # esperado: vacío
git branch --show-current   # esperado: master
```

- [ ] **Step 2: Crear la rama**

```bash
git switch -c rediseno-tailwind
git branch --show-current   # esperado: rediseno-tailwind
```

No hay worktree a propósito: el stack de Docker, los puertos (3001/5434/6381) y la base sembrada cuelgan de este directorio.

---

## Task 1: Tailwind construye la CSS, Sass se jubila

**Objetivo declarado: la app se ve IDÉNTICA al terminar.** Es el punto de control. Si algo va a fallar con esbuild, el CLI o el escaneo, falla acá, con un diff reversible y con las 30 capturas todavía sirviendo de referencia.

DaisyUI **no** entra en esta tarea: entra en la 3, junto con la resolución de las clases que colisionan.

**Files:**
- Modify: `package.json`
- Modify: `esbuild.config.js:47-58` (el tercer `esBuild.build`)
- Rename: `app/assets/stylesheets/application.scss` → `app/assets/stylesheets/application.css`

**Interfaces:**
- Consumes: nada.
- Produces: `yarn build` genera `app/assets/builds/application-build-css.css` con Tailwind. El nombre del archivo de salida **no cambia**, así que `stylesheet_link_tag "application-build-css"` en los dos layouts sigue funcionando sin tocarse.

- [ ] **Step 1: Instalar Tailwind y sacar Sass**

```bash
docker compose exec app yarn add -D tailwindcss@4.3.3 @tailwindcss/cli@4.3.3
docker compose exec app yarn remove sass esbuild-sass-plugin
```

- [ ] **Step 2: Rebuild de la imagen**

Obligatorio: `node_modules` vive en un volumen anónimo que sale de la imagen.

```bash
make rebuild
docker compose exec app ls node_modules/@tailwindcss/cli
```
Esperado: el directorio existe.

- [ ] **Step 3: Convertir la hoja a CSS plano**

La hoja no usa ninguna función de Sass, así que la conversión es solo de comentarios.

```bash
git mv app/assets/stylesheets/application.scss app/assets/stylesheets/application.css
```

Convertir los comentarios `//` a `/* */`:

```bash
docker compose exec app ruby -e '
  ruta = "app/assets/stylesheets/application.css"
  texto = File.read(ruta).lines.map do |linea|
    linea =~ %r{\A(\s*)//\s?(.*)$} ? "#{$1}/* #{$2} */\n" : linea
  end.join
  File.write(ruta, texto)
'
grep -c "^\s*//" app/assets/stylesheets/application.css
```
Esperado: `0`.

- [ ] **Step 4: Poner la directiva de Tailwind al principio**

Al tope de `app/assets/stylesheets/application.css`, **antes** del comentario que ya existe:

```css
@import "tailwindcss";

/* Dónde buscar clases. Tailwind 4 descubre fuentes solo, saltando lo que
   ignora git, pero acá se declaran explícitas: si mañana alguien agrega un
   .gitignore que tape app/views, las clases desaparecen de la hoja sin que
   ninguna prueba lo diga. */
@source "../../views";
@source "../../helpers";
@source "../../javascript";
```

- [ ] **Step 5: Sacar el build de CSS de esbuild**

Borrar entero el tercer `esBuild.build({...})` de `esbuild.config.js` (el que tiene `entryPoints: ['./app/assets/stylesheets/application.scss']`), y quitar `plugins: [sassPlugin()]` y la línea `const { sassPlugin } = require('esbuild-sass-plugin');` del build de `application.js` — ahí nunca hizo falta, porque no importa ninguna hoja.

- [ ] **Step 6: Que `yarn build` corra los dos**

En `package.json`:

```json
  "scripts": {
    "build": "node esbuild.config.js && yarn build:css",
    "build:css": "tailwindcss -i app/assets/stylesheets/application.css -o app/assets/builds/application-build-css.css --minify"
  },
```

- [ ] **Step 7: Construir y comprobar que la hoja salió**

```bash
make yarn-build
docker compose exec app wc -c app/assets/builds/application-build-css.css
```
Esperado: un archivo de decenas de KB, no vacío.

- [ ] **Step 8: Comprobar que Tailwind SÍ está viendo los .haml**

Es la trampa que el spec pide verificar y no asumir. Agregar una clase de Tailwind que hoy no existe en ningún lado, a una vista, y ver si aparece en la salida.

`underline` es una utilidad de Tailwind que hoy no usa ninguna vista, así que
si aparece en la hoja es porque el escáner leyó el `.haml`.

```bash
grep -c "underline" app/assets/builds/application-build-css.css   # esperado: 0
printf '%%p.underline sonda\n' >> app/views/challenges/index.html.haml
make yarn-build
grep -c "\.underline" app/assets/builds/application-build-css.css
```
Esperado: ≥ 1. **Si da `0`, los `@source` del paso 4 están mal** y hay que
corregirlos antes de seguir — todo lo que viene depende de esto.

Deshacer la sonda:

```bash
git checkout app/views/challenges/index.html.haml
make yarn-build
```

- [ ] **Step 9: Verificar que no cambió nada**

```bash
make spec
```
Esperado: `650 examples, 0 failures`.

```bash
make screens
```
Esperado: `30 capturas` y `Sin errores de JS ni respuestas >= 400.`

Además, mirar dos capturas a ojo y confirmar que se ven como antes: `tmp/screenshots/04-challenge.png` y `tmp/screenshots/09-3-step-evaluaci-n-t-cnica.png`.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "Tailwind construye la CSS; Sass se jubila

La hoja no usaba ninguna función de Sass —cero @use, @mixin, @extend, cero
variables—, así que la conversión fue de comentarios y nada más. Salen \`sass\`
y \`esbuild-sass-plugin\`; el build de CSS sale de esbuild y lo hace el CLI de
Tailwind.

Sin cambio visual a propósito: es el punto de control de la migración. El
archivo de salida conserva el nombre, así que los dos layouts no se tocan.

Los \`@source\` van explícitos aunque Tailwind los descubra solo: si alguien
tapara app/views con un .gitignore, las clases desaparecerían de la hoja sin
que ninguna prueba lo dijera."
```

---

## Task 2: Las clases interpoladas se mudan a helpers

**La app se sigue viendo idéntica.** Tailwind escanea texto: `class: "status-chip--#{step.status}"` no la ve y la descartaría en cuanto la clase deje de estar escrita a mano en la hoja.

**ENMENDADA: son 24 casos, no 48.** El conteo original incluía ids y nombres de
campo —`payload_`, `peso_`, `count_`, `scores_`, `corte-`, `advance_`,
`report-`— que Tailwind nunca escanea como clases. El inventario real:

| Prefijo | Casos |
|---|---|
| `status-chip--` | 14 |
| `source-chip--` | 3 |
| `flash--` | 2 |
| `setup__step--` | 1 |
| `result--` | 1 |
| `flow-strip__node--` | 1 |
| `feedback-kind--` | 1 |
| `diff-kind--` | 1 |

Aparte, los 4 `class: "app-nav__link#{' is-active' if …}"` de
`layouts/application.html.haml` **no son un defecto** —`is-active` está escrito
literal y Tailwind lo ve— pero darían falso positivo en el lint. Se convierten a
forma de arreglo, que es la que ya usa `_setup_progress.html.haml` en este repo:

```haml
= link_to "Desafíos", challenges_path,
          class: ["app-nav__link", ("is-active" if controller_name.in?(%w[challenges steps ideas assessments]))]
```

Así el lint nace estricto en vez de con excepciones.

Se resuelve con helpers, no con un safelist, porque además mata duplicación: hoy el ternario `run.succeeded? ? 'completed' : (run.failed? ? 'skipped' : 'pending')` está repetido en cinco vistas.

**Files:**
- Create: `app/helpers/estilos_helper.rb`
- Create: `spec/helpers/estilos_helper_spec.rb`
- Create: `spec/lint/clases_interpoladas_spec.rb`
- Modify: los 24 archivos de `app/views/` con interpolación de clase

**Interfaces:**
- Consumes: nada de la tarea 1.
- Produces: `EstilosHelper#chip_de_estado(estado)`, `#chip_de_origen(source)`, `#clase_de_flash(tipo)`, `#clase_de_feedback(kind)`, `#clase_de_diff(kind)`, `#clase_de_resultado(status)` — todos devuelven un `String` con el nombre **completo** de las clases. La tarea 3 cambia los valores de las constantes y ninguna vista se entera.

- [ ] **Step 1: Escribir el spec de lint que falla**

Es la guarda real: prohíbe volver a interpolar una clase. Sigue el patrón de `spec/lint/tenant_bypass_spec.rb`.

```ruby
# spec/lint/clases_interpoladas_spec.rb
# frozen_string_literal: true

require "rails_helper"

# Tailwind escanea TEXTO. Una clase construida así:
#
#     %span{ class: "status-chip--#{step.status}" }
#
# no existe para el escáner: no la ve, no la genera, y la pantalla queda con
# un elemento sin estilos. En el DOM se ve bien; en pantalla, no.
#
# La regla es que el nombre completo esté escrito en algún lado. Los helpers
# de EstilosHelper lo hacen, y de paso dejan la traducción estado -> estilo en
# un solo lugar en vez de repartida en ternarios por 24 archivos.
RSpec.describe "clases CSS interpoladas", type: :lint do
  VISTAS = Rails.root.glob("app/views/**/*.haml")

  it "ninguna vista arma una clase con interpolación" do
    culpables = VISTAS.filter_map do |ruta|
      lineas = ruta.read.lines.each_with_index.filter_map do |linea, i|
        "#{ruta.relative_path_from(Rails.root)}:#{i + 1}  #{linea.strip}" if
          linea =~ /class[:=][^,)]*"[^"]*\#\{/
      end
      lineas.presence
    end.flatten

    expect(culpables).to be_empty, <<~TXT
      Estas líneas arman una clase con #{'#'}{}: Tailwind no las ve y las descarta.
      Usá un helper de EstilosHelper que devuelva el nombre completo.

      #{culpables.join("\n")}
    TXT
  end
end
```

- [ ] **Step 2: Correrlo y ver que falla**

```bash
make spec-file FILE=spec/lint/clases_interpoladas_spec.rb
```
Esperado: FAIL, listando 48 líneas en 24 archivos.

- [ ] **Step 3: Escribir el helper**

```ruby
# app/helpers/estilos_helper.rb
# frozen_string_literal: true

# Traduce un estado del dominio a la clase que lo pinta.
#
# POR QUÉ EXISTE: Tailwind escanea texto, así que una clase armada con
# interpolación no la ve y la descarta. Todo lo de acá devuelve el nombre
# COMPLETO, escrito literal, y nunca lo arma con #{}.
#
# El efecto de rebote es el que importa a largo plazo: la traducción estado ->
# estilo queda en UN lugar. Antes el ternario
# `run.succeeded? ? 'completed' : ...` estaba repetido en cinco vistas, y
# cambiar el estilo de «falló» significaba encontrarlas todas.
module EstilosHelper
  CHIP_DE_ESTADO = {
    "pending" => "status-chip status-chip--pending",
    "active" => "status-chip status-chip--active",
    "activating" => "status-chip status-chip--activating",
    "completed" => "status-chip status-chip--completed",
    "skipped" => "status-chip status-chip--skipped",
    "archived" => "status-chip status-chip--archived"
  }.freeze

  CHIP_DE_ORIGEN = {
    "manual" => "source-chip source-chip--manual",
    "automatic" => "source-chip source-chip--automatic",
    "ai" => "source-chip source-chip--ai",
    "formula" => "source-chip source-chip--formula"
  }.freeze

  CLASE_DE_FLASH = {
    "notice" => "flash flash--notice",
    "alert" => "flash flash--alert"
  }.freeze

  CLASE_DE_FEEDBACK = {
    "comment" => "feedback-kind feedback-kind--comment",
    "question" => "feedback-kind feedback-kind--question",
    "suggestion" => "feedback-kind feedback-kind--suggestion",
    "risk" => "feedback-kind feedback-kind--risk"
  }.freeze

  CLASE_DE_DIFF = {
    "added" => "diff-kind diff-kind--added",
    "removed" => "diff-kind diff-kind--removed",
    "changed" => "diff-kind diff-kind--changed"
  }.freeze

  # El paso a paso de configuración y el mapa compacto del flujo pintan el
  # MISMO conjunto de estados que los chips, con otra forma. Comparten la clave
  # y no el nombre de clase.
  CLASE_DE_PASO_DE_SETUP = {
    "pending" => "setup__step setup__step--pending",
    "active" => "setup__step setup__step--active",
    "completed" => "setup__step setup__step--completed",
    "skipped" => "setup__step setup__step--skipped",
    "blocked" => "setup__step setup__step--blocked",
    "done" => "setup__step setup__step--done",
    "current" => "setup__step setup__step--current",
    "outline" => "setup__step setup__step--outline"
  }.freeze

  CLASE_DE_NODO_DE_FLUJO = {
    "pending" => "flow-strip__node flow-strip__node--pending",
    "active" => "flow-strip__node flow-strip__node--active",
    "activating" => "flow-strip__node flow-strip__node--activating",
    "completed" => "flow-strip__node flow-strip__node--completed",
    "skipped" => "flow-strip__node flow-strip__node--skipped"
  }.freeze

  CLASE_DE_RESULTADO = {
    "pending" => "result result--pending",
    "in_progress" => "result result--in_progress",
    "done" => "result result--done",
    "skipped" => "result result--skipped"
  }.freeze

  # Un estado desconocido no puede dejar el elemento sin ninguna clase: se cae
  # al neutro, que es visible y no miente.
  def chip_de_estado(estado) = CHIP_DE_ESTADO.fetch(estado.to_s, CHIP_DE_ESTADO.fetch("pending"))
  def chip_de_origen(source) = CHIP_DE_ORIGEN.fetch(source.to_s, CHIP_DE_ORIGEN.fetch("manual"))
  def clase_de_flash(tipo) = CLASE_DE_FLASH.fetch(tipo.to_s, CLASE_DE_FLASH.fetch("notice"))
  def clase_de_feedback(kind) = CLASE_DE_FEEDBACK.fetch(kind.to_s, CLASE_DE_FEEDBACK.fetch("comment"))
  def clase_de_diff(kind) = CLASE_DE_DIFF.fetch(kind.to_s, CLASE_DE_DIFF.fetch("changed"))
  def clase_de_resultado(status) = CLASE_DE_RESULTADO.fetch(status.to_s, CLASE_DE_RESULTADO.fetch("pending"))
  def clase_de_nodo_de_flujo(estado) = CLASE_DE_NODO_DE_FLUJO.fetch(estado.to_s, CLASE_DE_NODO_DE_FLUJO.fetch("pending"))

  # `_setup_progress.html.haml` ya arma su clase como ARREGLO y le suma otras
  # condicionales. Este helper devuelve solo la de estado; el arreglo se
  # conserva tal como está.
  def clase_de_paso_de_setup(estado) = CLASE_DE_PASO_DE_SETUP.fetch(estado.to_s, CLASE_DE_PASO_DE_SETUP.fetch("pending"))

  # Los ternarios que estaban repartidos por las vistas, en un solo lugar.
  def chip_de_corrida_de_ia(run)
    return chip_de_estado("completed") if run.succeeded?
    return chip_de_estado("skipped") if run.failed?

    chip_de_estado("pending")
  end

  def chip_de_decision(decision)
    return chip_de_estado("completed") if decision.advance?
    return chip_de_estado("active") if decision.reinstate?

    chip_de_estado("skipped")
  end

  def chip_de_validez(valido) = chip_de_estado(valido ? "completed" : "skipped")
end
```

- [ ] **Step 4: Escribir el spec del helper**

```ruby
# spec/helpers/estilos_helper_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EstilosHelper, type: :helper do
  it "devuelve el nombre completo, no un fragmento" do
    expect(helper.chip_de_estado("completed")).to eq("status-chip status-chip--completed")
  end

  # Sin esto, un estado nuevo dejaría el elemento sin ninguna clase y el
  # síntoma sería un chip invisible en vez de un error.
  it "cae al neutro con un estado que no conoce" do
    expect(helper.chip_de_estado("inventado")).to eq("status-chip status-chip--pending")
    expect(helper.chip_de_estado(nil)).to eq("status-chip status-chip--pending")
  end

  it "acepta símbolos igual que strings" do
    expect(helper.chip_de_estado(:active)).to eq(helper.chip_de_estado("active"))
  end

  it "traduce una corrida de IA sin que la vista sepa el ternario" do
    ok = instance_double("AiRun", succeeded?: true, failed?: false)
    mal = instance_double("AiRun", succeeded?: false, failed?: true)
    curso = instance_double("AiRun", succeeded?: false, failed?: false)

    expect(helper.chip_de_corrida_de_ia(ok)).to include("--completed")
    expect(helper.chip_de_corrida_de_ia(mal)).to include("--skipped")
    expect(helper.chip_de_corrida_de_ia(curso)).to include("--pending")
  end
end
```

- [ ] **Step 5: Correrlo y verlo pasar**

```bash
make spec-file FILE=spec/helpers/estilos_helper_spec.rb
```
Esperado: PASS.

- [ ] **Step 6: Reemplazar los sitios**

Listarlos primero:

```bash
grep -rn 'class[:=][^,)]*"[^"]*#{' app/views --include=*.haml
```

Esperado: 24 de clase real, más los 4 de `app-nav__link` que van a forma de
arreglo. Reemplazar cada uno. Ejemplos textuales de las formas que aparecen:

```haml
-# app/views/steps/_header.html.haml:10
-# antes: %span{ class: "status-chip--#{step.status}" }
%span{ class: chip_de_estado(step.status) }

-# app/views/layouts/application.html.haml:50
-# antes: .flash{ class: "flash--#{type}" }
%div{ class: clase_de_flash(type) }

-# app/views/ai_runs/index.html.haml:43
-# antes: %span{ class: "status-chip--#{run.succeeded? ? 'completed' : (run.failed? ? 'skipped' : 'pending')}" }
%span{ class: chip_de_corrida_de_ia(run) }

-# app/views/criteria_sets/index.html.haml:22
-# antes: %span{ class: "status-chip--#{set.status == 'valid' ? 'completed' : 'skipped'}" }
%span{ class: chip_de_validez(set.status == "valid") }
```

**Ojo con la forma abreviada de HAML.** `.flash{ class: "flash--#{type}" }` pone DOS clases: la del punto y la interpolada. Al pasar al helper, el nombre completo ya trae las dos, así que el punto sale — si no, la clase queda duplicada.

- [ ] **Step 7: El lint pasa**

```bash
make spec-file FILE=spec/lint/clases_interpoladas_spec.rb
```
Esperado: PASS.

- [ ] **Step 8: Nada cambió en pantalla**

```bash
make spec
make screens
```
Esperado: `650 examples, 0 failures` (más los nuevos: 655) y `30 capturas`, sin errores.

Mirar `tmp/screenshots/11-ai-runs.png` y `tmp/screenshots/04-challenge.png`: los chips tienen que verse igual que antes.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Las clases de estado salen de las vistas y entran a un helper

Tailwind escanea texto: \`class: \"status-chip--#{'#'}{step.status}\"\` no existe para
el escáner. Eran 24 casos, y se resuelven con helpers en vez de
un safelist porque además matan duplicación: el ternario
\`run.succeeded? ? 'completed' : ...\` estaba repetido en cinco vistas.

Queda una guarda de lint que falla si alguien vuelve a interpolar una clase,
con el mismo patrón que spec/lint/tenant_bypass_spec.rb.

Sin cambio visual."
```

---

## Task 3: DaisyUI entra; `btn` y `card` dejan de colisionar

DaisyUI trae 722 clases. Contra las 406 de esta app **colisionan tres**: `btn`,
`card` y `btn-link`. Verificado por intersección de conjuntos sobre el paquete
entero de DaisyUI y la hoja entera de la app —no solo `components/` ni solo los
selectores a inicio de línea, que fue el error de la primera medición y dejó
`btn-link` afuera—.

| Clase | Qué se hace | Por qué |
|---|---|---|
| `btn` | **Migrar** | Autocontenida, mapeo directo. 223 usos |
| `card` | **Conservar** | El `card` de DaisyUI deja el padding en `card-body`: borrarla dejaría 101 usos sin relleno |
| `btn-link` | **Conservar** | El de la app es «una acción en medio de una frase» —sin padding ni borde, hereda la fuente—; el de DaisyUI es una variante de botón con la altura de `btn`. Se usa en `step_config.vue:76` |

Las dos que se conservan ganan por **orden de fuente**: van después del
`@plugin`, con la misma especificidad. No hace falta `!important` ni renombrar.

Un cuarto caso, `is-hidden`, aparece en la intersección pero **no es colisión**:
la app la usa siempre compuesta (`.step-card__handle.is-hidden`, especificidad
0-2-0), que le gana a la de DaisyUI. Se deja como está.

Y `css` en la intersección es un falso positivo: sale de
`@import "tailwindcss/theme.css"`, no es una clase.

**ENMENDADA tras el escaneo previo y la tarea 1.** Tres cambios respecto de lo
que decía antes, cada uno con su razón:

1. **Se migra solo `btn`, no `card`.** El `.card` de DaisyUI es un contenedor
   flex y el padding lo pone `.card-body`: borrar el `.card` propio dejaría 101
   usos sin relleno de golpe. `btn` no tiene ese problema porque es
   autocontenido. El `.card` propio se queda —va después del `@plugin`, así que
   gana la cascada por orden de fuente— y su migración pasa al plan 2, pantalla
   por pantalla, que es donde se puede envolver el contenido en `card-body`.
2. **Vuelve el Preflight, medido y compensado.** La tarea 1 lo dejó afuera para
   no cambiar el render, y midió que traerlo bajaba `h1.page-title` de 700 a
   400. Pero DaisyUI está construido asumiendo Preflight, y correrlo sin él es
   salirse del contrato de la librería. Este es el mejor momento para absorberlo:
   la paleta no cambia, así que **toda** diferencia visual es atribuible al
   Preflight y a nada más.
3. **Se re-apunta el `:root` heredado a los tokens de DaisyUI.** Sin esto, la
   tarea 4 repintaría los botones y dejaría tarjetas, chips y tablas en azul y
   gris: las 1.939 líneas heredadas leen `var(--accent)`, `var(--surface)` y
   `var(--border)`, no los tokens nuevos. Se hace acá y no en la 4 porque acá
   tiene que ser **invisible**, y esa invisibilidad es la prueba de que el
   cableado quedó bien.

El tema de esta tarea reproduce **la paleta de hoy**. El carácter nuevo entra en la tarea 4.

**Files:**
- Modify: `package.json`
- Modify: `app/assets/stylesheets/application.css`
- Modify: `app/views/**/*.haml` (modificadores de `btn`)
- Modify: `app/javascript/components/**/*.vue` (ídem)
- Modify: `script/capture_screens.js`

**Interfaces:**
- Consumes: la salida de Tailwind de la tarea 1.
- Produces: los tokens `--color-*` y `--radius-*` de DaisyUI disponibles para la tarea 4; los nombres `btn-primary` / `btn-ghost` / `btn-sm` / `btn-block` en uso en todas las vistas.

- [ ] **Step 1: Instalar DaisyUI y rebuild**

```bash
docker compose exec app yarn add -D daisyui@5.7.28
make rebuild
```

- [ ] **Step 2: Cargar el plugin con la paleta de HOY**

En `app/assets/stylesheets/application.css`, debajo del `@import`:

```css
@plugin "daisyui" {
  themes: false;
}

/* El tema arranca replicando la paleta actual, en oklch. El objetivo de esta
   tarea sigue siendo que nada cambie en pantalla: el carácter nuevo entra en
   la tarea 4, y entonces solo cambian estos valores. */
@plugin "daisyui/theme" {
  name: "flow";
  default: true;
  color-scheme: light;

  --color-base-100: oklch(100% 0 0);          /* era --surface #ffffff */
  --color-base-200: oklch(97.3% 0.003 247.9); /* era --bg      #f6f7f9 */
  --color-base-300: oklch(92.3% 0.005 247.9); /* era --border  #e3e6ea */
  --color-base-content: oklch(23.7% 0.011 254.1); /* era --text #1c2024 */

  --color-primary: oklch(54.6% 0.215 262.9);  /* era --accent  #2563eb */
  --color-primary-content: oklch(100% 0 0);

  --color-error: oklch(58.4% 0.201 27.3);     /* era --danger  #d92d20 */
  --color-success: oklch(62.6% 0.161 156.4);  /* era --ok      #12a150 */
  --color-warning: oklch(72.9% 0.152 82.4);   /* era --warn    #d99a06 */

  --radius-box: 0.625rem;   /* era --radius 10px */
  --radius-field: 0.375rem;
  --radius-selector: 0.375rem;
}
```

- [ ] **Step 3: Traer el Preflight y medir qué rompe**

La tarea 1 lo dejó afuera a propósito. Acá vuelve, porque DaisyUI lo asume.

Reemplazar los dos `@import` sueltos que dejó la tarea 1 por el import completo:

```css
@import "tailwindcss";
```

Antes de reconstruir, capturar los estilos computados de referencia. Escribir
`script/probe_estilos.js` (temporal, **no se commitea**):

```javascript
// Mide estilos computados de elementos representativos, para poder comparar
// antes y después de un cambio de base. No es una prueba: es un instrumento.
const { chromium } = require('playwright');
const BASE = process.env.BASE_URL || 'http://localhost:3001';
const SELECTORES = [
  '.page-title', '.section-title', '.card', '.btn', '.status-chip',
  '.step-table th', '.step-table td', '.muted', '.field-hint', 'a', 'ul', 'li'
];
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  await p.goto(`${BASE}/login`);
  await p.fill('input[name="email"]', 'admin@demo.test');
  await p.fill('input[name="password"]', 'Test1234');
  await Promise.all([p.waitForURL((u) => !/login/.test(u.href)),
                     p.click('button[type="submit"], input[type="submit"]')]);
  await p.goto(`${BASE}${process.env.RUTA || '/challenges/merma-bodega'}`);
  const out = await p.evaluate((sels) => sels.map((sel) => {
    const el = document.querySelector(sel);
    if (!el) return `${sel}: (ausente)`;
    const cs = getComputedStyle(el);
    return `${sel}: size=${cs.fontSize} weight=${cs.fontWeight} ` +
           `color=${cs.color} bg=${cs.backgroundColor} ` +
           `pad=${cs.padding} margin=${cs.margin} border=${cs.borderTopWidth} ` +
           `list=${cs.listStyleType}`;
  }), sels = SELECTORES);
  console.log(out.join('\n'));
  await b.close();
})();
```

Correrlo **antes** (con el estado actual, sin Preflight) y guardar:

```bash
docker run --rm --network host -v "$PWD/script:/script:ro" -w /run \
  mcr.microsoft.com/playwright:v1.62.0-noble \
  bash -c "cd /run && npm i -s playwright@1.62.0 >/dev/null 2>&1 && NODE_PATH=/run/node_modules node /script/probe_estilos.js" \
  > /tmp/estilos-sin-preflight.txt
cat /tmp/estilos-sin-preflight.txt
```

- [ ] **Step 4: Compensar lo que el Preflight resetea**

Reconstruir con Preflight puesto y volver a medir:

```bash
make yarn-build
docker run --rm --network host -v "$PWD/script:/script:ro" -w /run \
  mcr.microsoft.com/playwright:v1.62.0-noble \
  bash -c "cd /run && npm i -s playwright@1.62.0 >/dev/null 2>&1 && NODE_PATH=/run/node_modules node /script/probe_estilos.js" \
  > /tmp/estilos-con-preflight.txt
diff /tmp/estilos-sin-preflight.txt /tmp/estilos-con-preflight.txt
```

Cada línea que aparezca en el `diff` es una regla que la hoja daba por sentada y
nunca declaró. Declararla explícita en `application.css`. Lo esperable —el
Preflight resetea encabezados, listas, botones y bordes— es algo así:

```css
/* Lo que la hoja heredaba de los defaults del navegador y el Preflight de
   Tailwind resetea. Se declara explícito en vez de sacar el Preflight, porque
   DaisyUI está construido asumiéndolo. Cada regla de acá salió de comparar
   estilos computados antes y después, no de adivinar. */
h1, h2, h3, h4 { font-weight: 700; }
.page-title { font-size: 22px; }
.section-title { font-size: 15px; }
```

**No copies ese bloque a ciegas: escribí el que salga de TU `diff`.** Repetir
la medición hasta que el `diff` quede vacío.

Borrar `script/probe_estilos.js` antes de commitear.

- [ ] **Step 5: Re-apuntar el `:root` heredado a los tokens de DaisyUI**

Las 1.939 líneas heredadas leen `var(--accent)`, `var(--surface)`, `var(--border)`.
Si siguen apuntando a sus propios hex, la tarea 4 cambia el tema y no se entera
nadie más que los botones.

Reemplazar el bloque `:root { … }` original por:

```css
/* Los tokens heredados dejan de tener valor propio y pasan a ser alias de los
   de DaisyUI. Es lo que hace que un cambio de tema alcance a las 1.939 líneas
   que todavía no se migraron —y que el modo oscuro las alcance también—.
   Acá tiene que ser invisible: el tema replica la paleta de hoy, así que si
   algo cambia de color, el alias está mal. */
:root {
  --bg: var(--color-base-200);
  --surface: var(--color-base-100);
  --border: var(--color-base-300);
  --text: var(--color-base-content);
  --accent: var(--color-primary);
  --danger: var(--color-error);
  --ok: var(--color-success);
  --warn: var(--color-warning);
  --radius: var(--radius-box);

  /* Estos dos NO se aliasan acá. `--muted` es un gris azulado sin equivalente
     exacto en la paleta de DaisyUI, y `--accent-soft` es un tinte del acento
     sobre blanco: derivarlos ahora movería el color y rompería el «diff
     vacío», que es justo la prueba que este paso necesita. Se resuelven en la
     tarea 4, donde cambiar de color es el objetivo. */
  --muted: #58627a;
  --accent-soft: #eef4ff;
  --shadow: 0 1px 2px rgba(16, 24, 40, .06), 0 1px 3px rgba(16, 24, 40, .08);
}
```

Volver a correr la medición del paso 3 y confirmar que el `diff` sigue vacío.
Si aparece una diferencia de color, un alias está mal apuntado.

- [ ] **Step 6: Migrar los modificadores de `btn`**

```bash
grep -rl 'btn--' app/views app/javascript/components | \
  xargs sed -i 's/btn--primary/btn-primary/g; s/btn--ghost/btn-ghost/g; s/btn--sm/btn-sm/g; s/btn--block/btn-block/g'
grep -rc 'btn--' app/views app/javascript/components | grep -v ':0' || echo "sin restos de btn--"
```
Esperado: `sin restos de btn--`.

- [ ] **Step 7: Borrar las reglas propias de `.btn` — y NO las de `.card`**

En `app/assets/stylesheets/application.css`, borrar el bloque `.btn { … }` con
sus modificadores `.btn--*` (líneas ~119-138 del original). Las de DaisyUI toman
su lugar.

**Los bloques `.card { … }` y `.btn-link { … }` se quedan.** Dejar en su lugar este comentario:

```css
/* Tres clases de esta app colisionan con DaisyUI —medido por intersección de
   conjuntos sobre el paquete entero—: `btn`, `card` y `btn-link`.

   `btn` se migró: es autocontenida y el mapeo es directo.

   `card` y `btn-link` NO, y es deliberado. El `card` de DaisyUI es un
   contenedor flex y el padding lo pone `card-body`: borrar esta regla dejaría
   101 usos sin relleno de golpe. Y su `btn-link` es una variante de botón con
   la altura de `btn`, mientras que el de acá es una acción en medio de una
   frase, sin padding ni borde.

   Las dos ganan por orden de fuente: van DESPUÉS del @plugin, con la misma
   especificidad. Se migran en el plan 2, pantalla por pantalla, que es donde
   se puede envolver el contenido en un card-body. */
```

- [ ] **Step 8: Sumar la revisión de clases descartadas a `make screens`**

En `script/capture_screens.js`, junto a las otras revisiones:

```javascript
// Una clase que Tailwind no vio al escanear existe en el HTML y no tiene
// ninguna regla detrás: en el DOM se ve perfecta y en pantalla no se ve nada.
// Ninguna otra prueba lo atrapa — ni un request spec, que solo mira el body.
//
// Se detecta por el estilo COMPUTADO: un badge sin fondo, un botón sin
// padding, son clases que no llegaron a la hoja.
async function revisarClasesDescartadas(page, name) {
  const huerfanas = await page.evaluate(() => {
    const sospechosas = [];
    for (const el of document.querySelectorAll('[class*="badge"],[class*="btn"],[class*="alert"],.steps,.card')) {
      const cs = getComputedStyle(el);
      const sinFondo = cs.backgroundColor === 'rgba(0, 0, 0, 0)' || cs.backgroundColor === 'transparent';
      const sinRelleno = parseFloat(cs.paddingLeft) === 0 && parseFloat(cs.paddingTop) === 0;
      if (sinFondo && sinRelleno && parseFloat(cs.borderTopWidth) === 0) {
        sospechosas.push(el.className);
      }
    }
    return [...new Set(sospechosas)].slice(0, 6);
  });

  if (huerfanas.length) {
    failures++;
    console.error(`[CLASES] ${name} tiene clases sin ninguna regla detrás: ${JSON.stringify(huerfanas)}`);
  }
}
```

Llamarla en tres pantallas de distinta forma, después de cada `shot`: `04-challenge`, `09-3-step-evaluaci-n-t-cnica` y `11-ai-runs`.

- [ ] **Step 9: Construir y verificar**

```bash
make yarn-build
make spec
make screens
```
Esperado: suite verde, `30 capturas`, sin `[CLASES]` ni `[MORPH]`.

- [ ] **Step 10: Verificar la revisión por mutación**

Sacar temporalmente `@source "../../views";` del CSS, reconstruir y correr las capturas: tiene que aparecer `[CLASES]`. Devolverlo después.

```bash
sed -i 's|^@source "../../views";|/* MUTACION */|' app/assets/stylesheets/application.css
make yarn-build && make screens 2>&1 | grep -c "\[CLASES\]"
sed -i 's|^/\* MUTACION \*/|@source "../../views";|' app/assets/stylesheets/application.css
make yarn-build
```
Esperado: el `grep -c` da ≥ 1. Si da `0`, la revisión no muerde y hay que arreglarla antes de seguir.

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "DaisyUI entra, y el tema heredado pasa a colgar de sus tokens

DaisyUI trae 615 clases y contra el vocabulario de esta app colisionan
exactamente dos: card y btn. Medido por intersección de conjuntos. Se migra btn
—autocontenido, mapeo directo, 223 usos— y card NO: el card de DaisyUI deja el
padding en card-body, así que borrar el propio dejaría 101 tarjetas sin relleno.
Se queda, después del plugin, ganando por orden de fuente.

Vuelve el Preflight, que la tarea 1 había dejado afuera: DaisyUI está construido
asumiéndolo. Lo que reseteaba y la hoja daba por sentado quedó declarado
explícito, y cada una de esas reglas salió de comparar estilos computados antes
y después, no de adivinar.

Y los tokens heredados dejan de tener valor propio: pasan a ser alias de los de
DaisyUI. Es lo que hace que el cambio de tema del commit siguiente alcance a las
1.939 líneas que todavía no se migraron, y que el modo oscuro las alcance
también. Acá es invisible a propósito —el tema replica la paleta de hoy—, y esa
invisibilidad es la prueba de que el cableado quedó bien.

Y \`make screens\` suma una revisión que ninguna otra prueba puede hacer: una
clase que el escáner no vio existe en el HTML y no tiene ninguna regla detrás.
En el DOM se ve perfecta; en pantalla no se ve nada. Se detecta por el estilo
computado, y está probada por mutación."
```

---

## Task 4: El carácter «Producto»

Recién acá cambia algo en pantalla, y cambia todo junto: es lo que hace que el resultado sea coherente en lugar de un rejunte.

**Files:**
- Modify: `app/assets/stylesheets/application.css`
- Modify: `app/views/layouts/application.html.haml`, `app/views/layouts/auth.html.haml` (las fuentes)

**Interfaces:**
- Consumes: los tokens del tema de la tarea 3.
- Produces: el tema `flow` (claro) y `flow-oscuro`; las familias `--font-display` y `--font-sans`.

- [ ] **Step 1: Cargar las fuentes en los dos layouts**

En el `%head` de `app/views/layouts/application.html.haml` y `app/views/layouts/auth.html.haml`, antes del `stylesheet_link_tag`:

```haml
%link{ rel: "preconnect", href: "https://fonts.googleapis.com" }
%link{ rel: "preconnect", href: "https://fonts.gstatic.com", crossorigin: true }
%link{ rel: "stylesheet", href: "https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,600;12..96,700&family=Inter:wght@400;500;600&display=swap" }
```

`display=swap` y pila de respaldo: si Google Fonts no responde, la app se ve con la fuente del sistema y no se rompe.

- [ ] **Step 2: Declarar las familias y cambiar los valores del tema**

En `app/assets/stylesheets/application.css`, sumar el bloque de tipografía y **reemplazar** los valores del tema `flow`:

```css
@theme {
  --font-display: "Bricolage Grotesque", "Helvetica Neue", system-ui, sans-serif;
  --font-sans: "Inter", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
}

@plugin "daisyui/theme" {
  name: "flow";
  default: true;
  color-scheme: light;

  --color-base-100: oklch(100% 0 0);
  --color-base-200: oklch(96.5% 0.004 286.3);
  --color-base-300: oklch(92.4% 0.006 286.3);
  --color-base-content: oklch(21.5% 0.028 285.9);

  --color-primary: oklch(52.8% 0.253 288.1);   /* #5b3df5 */
  --color-primary-content: oklch(100% 0 0);
  --color-neutral: oklch(21.5% 0.028 285.9);   /* el shell oscuro */
  --color-neutral-content: oklch(78.5% 0.024 286.3);

  --color-error: oklch(58.4% 0.201 27.3);
  --color-success: oklch(62.6% 0.161 156.4);
  --color-warning: oklch(72.9% 0.152 82.4);

  --radius-box: 0.8125rem;   /* 13px */
  --radius-field: 0.5625rem;
  --radius-selector: 0.5rem;
  --depth: 1;
}

@plugin "daisyui/theme" {
  name: "flow-oscuro";
  prefersdark: true;
  color-scheme: dark;

  --color-base-100: oklch(21.5% 0.028 285.9);
  --color-base-200: oklch(18.2% 0.026 285.9);
  --color-base-300: oklch(26.4% 0.030 285.9);
  --color-base-content: oklch(92.8% 0.012 286.3);

  --color-primary: oklch(66.5% 0.208 288.1);
  --color-primary-content: oklch(15% 0.03 285.9);
  --color-neutral: oklch(15.5% 0.024 285.9);
  --color-neutral-content: oklch(78.5% 0.024 286.3);

  --color-error: oklch(66% 0.19 25);
  --color-success: oklch(70% 0.15 156);
  --color-warning: oklch(78% 0.15 82);

  --radius-box: 0.8125rem;
  --radius-field: 0.5625rem;
  --radius-selector: 0.5rem;
}
```

- [ ] **Step 3: Aplicar las familias, y cerrar los dos alias que faltaban**

La tarea 3 dejó `--bg`, `--surface`, `--border`, `--text` y `--accent` colgando
de los tokens de DaisyUI, así que el color del `body` ya sigue al tema y no hay
que tocarlo. Lo que sí cambia es la tipografía.

En el `:root`, cerrar los dos alias que la tarea 3 dejó literales a propósito
—acá cambiar de color es el objetivo, así que ya no rompen nada—:

```css
  --muted: color-mix(in oklch, var(--color-base-content) 62%, transparent);
  --accent-soft: color-mix(in oklch, var(--color-primary) 12%, var(--color-base-100));
```

Y la regla de `body`, que hoy fija `font: 14px/1.5 system-ui, …`:

```css
body {
  margin: 0;
  background: var(--bg);
  color: var(--text);
  font-family: var(--font-sans);
  font-size: 14px;
  line-height: 1.5;
}

/* Los títulos son lo que le da carácter: la display solo acá, nunca en texto
   corrido. */
h1, h2, h3, .page-title, .section-title, .auth-title {
  font-family: var(--font-display);
  letter-spacing: -0.02em;
}

/* Las columnas de números se leen mal si cada dígito tiene su ancho. */
.step-table td, .step-table th { font-variant-numeric: tabular-nums; }
```

- [ ] **Step 4: Declarar el tema en el `<html>`**

En los dos layouts, la etiqueta raíz pasa a llevar el tema:

```haml
%html{ lang: I18n.locale, "data-theme": "flow" }
```

- [ ] **Step 5: Construir y mirar**

```bash
make yarn-build
make screens
```
Esperado: `30 capturas`, sin errores. **Acá SÍ cambian todas las capturas**, es el objetivo.

Mirar a ojo `tmp/screenshots/04-challenge.png` y `09-3-step-evaluaci-n-t-cnica.png`: tipografía nueva, violeta, y nada ilegible.

- [ ] **Step 6: Comprobar que el tema oscuro no deja texto invisible**

Esto es revisión a ojo: no hay prueba automática que juzgue contraste.
Abrir `http://localhost:3001` con el sistema en modo oscuro (o cambiar `data-theme` a `flow-oscuro` a mano en el inspector) y confirmar que el texto se lee sobre el fondo en la ficha de un desafío y en la pantalla de un módulo.

- [ ] **Step 7: La suite**

```bash
make spec
```
Esperado: verde. Si `spec/requests/previews_spec.rb:55` o `spec/requests/ai_spec.rb:396` fallan, es porque tocaron `preview-surface` o `scale-radio--suggested`: esas dos clases son propias y **no** debían cambiar en esta tarea. Revisar antes de tocar el spec.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "El carácter: Bricolage Grotesque, Inter y violeta

Elegido sobre dos alternativas —una «Herramienta» densa con IBM Plex y una
«Documento» cálida con Source Serif—. Acá cambia todo junto a propósito: un
tema que se migra de a pedazos se ve como un rejunte.

La display va solo en títulos, nunca en texto corrido, y las columnas de
números pasan a tabular-nums, que es lo que hace legible una tabla de puntajes.

Y aparece el modo oscuro, que la app no tenía: es la segunda lista de los
mismos tokens, no una reescritura de componentes.

El violeta es provisorio hasta saber si innk tiene marca propia. Vive en
--color-primary: cambiarlo es una línea."
```

---

## Task 5: El shell de tres regiones

**Files:**
- Create: `app/views/layouts/_flow_drawer.html.haml`
- Create: `app/helpers/shell_helper.rb`
- Create: `spec/helpers/shell_helper_spec.rb`
- Create: `spec/requests/shell_spec.rb`
- Modify: `app/views/layouts/application.html.haml`
- Modify: `app/assets/stylesheets/application.css` (`.app-main` pasa a la grilla de tres regiones)

**Interfaces:**
- Consumes: los componentes `drawer` y `menu` de DaisyUI (tarea 3), el tema (tarea 4).
- Produces: `ShellHelper#desafio_del_shell` → `Challenge | nil`; `content_for :referencia` como el mecanismo por el que cada pantalla llena la columna derecha.

- [ ] **Step 1: Escribir el spec de request que falla**

```ruby
# spec/requests/shell_spec.rb
# frozen_string_literal: true

require "rails_helper"

# El shell de tres regiones. La regla que decide qué se dibuja no es «qué
# controller es» sino «hay un desafío en contexto»: el flujo solo tiene sentido
# adentro de uno.
RSpec.describe "el shell", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }
  let!(:admin) do
    without_tenant do
      u = create(:user, email: "admin@test.dev")
      create(:membership, :admin, company: company, user: u)
      u
    end
  end

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma")
      seed_form!(c.steps.create!(kind: "ideation", position: 1))
      c.steps.create!(kind: "evaluation", position: 2, name: "Comité")
      c
    end
  end

  before { sign_in(admin, company: company) }

  it "dibuja el flujo del desafío en la pantalla del desafío" do
    get challenge_path(challenge)

    expect(response.body).to include("flow-drawer")
    expect(response.body).to include("Comité")
  end

  it "y también dentro de un módulo" do
    paso = as_company(company) { challenge.steps.find_by(kind: "evaluation") }
    get challenge_step_path(challenge, paso)

    expect(response.body).to include("flow-drawer")
  end

  # Sin desafío no hay flujo que mostrar, y una barra lateral vacía es peor que
  # ninguna: ocupa un cuarto de la pantalla para no decir nada.
  it "NO lo dibuja fuera de un desafío" do
    get criteria_sets_path
    expect(response.body).not_to include("flow-drawer")

    get members_path
    expect(response.body).not_to include("flow-drawer")
  end
end
```

- [ ] **Step 2: Correrlo y ver que falla**

```bash
make spec-file FILE=spec/requests/shell_spec.rb
```
Esperado: FAIL, `flow-drawer` no aparece.

- [ ] **Step 3: El helper que decide**

```ruby
# app/helpers/shell_helper.rb
# frozen_string_literal: true

# Qué desafío manda en la pantalla, si es que hay alguno.
#
# La regla no es «qué controller es» sino «hay un desafío en contexto»: el
# flujo solo tiene sentido adentro de uno, y una barra lateral vacía sería un
# cuarto de pantalla que no dice nada.
module ShellHelper
  def desafio_del_shell
    return @challenge if @challenge.is_a?(Challenge)
    return @step.challenge if @step.respond_to?(:challenge)
    return @idea.challenge if @idea.respond_to?(:challenge)

    nil
  end
end
```

- [ ] **Step 4: El partial del drawer**

```haml
-# app/views/layouts/_flow_drawer.html.haml
-#
-# La barra lateral con el flujo del desafío. Responde «dónde estoy y qué
-# sigue», que es la pregunta que la app no contestaba en ninguna pantalla.
-#
-# Es el componente `drawer` de DaisyUI: abajo de 1024px se vuelve superposición
-# solo, sin una línea de JS.
- pasos = desafio.steps.order(:position)
%aside.flow-drawer.bg-neutral.text-neutral-content
  .flow-drawer__head
    = link_to desafio.name, challenge_path(desafio), class: "flow-drawer__title"
    %span.flow-drawer__meta= t("flow.challenge_statuses.#{desafio.status}")
  %ul.menu.flow-drawer__steps
    - pasos.each_with_index do |paso, i|
      - actual = defined?(@step) && @step&.id == paso.id
      %li
        = link_to challenge_step_path(desafio, paso), class: ("menu-active" if actual) do
          %span.flow-drawer__num= i + 1
          %span.flow-drawer__name= paso.name
          %span{ class: chip_de_estado(paso.status) }
```

- [ ] **Step 5: Las tres regiones en el layout**

Reemplazar el `%main.app-main` de `app/views/layouts/application.html.haml`:

```haml
- desafio = desafio_del_shell
%div{ class: desafio ? "app-shell app-shell--con-flujo" : "app-shell" }
  - if desafio
    = render "layouts/flow_drawer", desafio: desafio
  %main.app-main
    - flash.each do |type, message|
      %div{ class: clase_de_flash(type) }= message
    = yield
  - if content_for?(:referencia)
    %aside.app-aside= yield :referencia
```

- [ ] **Step 6: La grilla**

En `app/assets/stylesheets/application.css`, reemplazar la regla de `.app-main` por:

```css
/* Tres regiones. La del medio es lo que se hace; la de la derecha, lo que se
   consulta y no se edita. El drawer solo existe dentro de un desafío. */
.app-shell { display: grid; grid-template-columns: 1fr; min-height: 100vh; }
.app-shell--con-flujo { grid-template-columns: 232px minmax(0, 1fr); }
.app-shell:has(.app-aside) { grid-template-columns: 232px minmax(0, 1fr) 280px; }

.app-main { display: flex; flex-direction: column; gap: 16px; padding: 24px; min-width: 0; }
.app-aside { display: flex; flex-direction: column; gap: 12px; padding: 24px 20px; border-left: 1px solid var(--color-base-300); }

/* Debajo de 1280px la referencia baja; debajo de 1024px el drawer se
   superpone y lo maneja DaisyUI. */
@media (max-width: 1280px) {
  .app-shell:has(.app-aside) { grid-template-columns: 232px minmax(0, 1fr); }
  .app-aside { grid-column: 2; border-left: 0; border-top: 1px solid var(--color-base-300); }
}
@media (max-width: 1024px) {
  .app-shell--con-flujo, .app-shell:has(.app-aside) { grid-template-columns: 1fr; }
  .flow-drawer { display: none; }
}
```

- [ ] **Step 7: El spec pasa**

```bash
make spec-file FILE=spec/requests/shell_spec.rb
```
Esperado: PASS.

- [ ] **Step 8: Poblar la referencia en UNA pantalla, como prueba del mecanismo**

Crear `app/views/steps/_referencia_evaluacion.html.haml` moviendo ahí las
tarjetas que hoy compiten con el trabajo. **Es una mudanza, no una
reescritura:** el markup sale tal cual de `steps/evaluation.html.haml`, solo
cambia dónde vive.

```haml
-# app/views/steps/_referencia_evaluacion.html.haml
-#
-# Lo que se consulta y no se edita en el curso normal del trabajo. Hasta acá
-# eran cuatro tarjetas del mismo peso que el trabajo, apiladas encima de él.
- criterios = handler.criteria_snapshot
.card
  %h3.section-title Progreso
  %p.muted= handler.progress.label

.card
  %h3.section-title Criterios
  %ul.menu
    - criterios.each do |criterio|
      %li
        %span= criterio["name"]
        %span.muted= number_to_percentage(criterio["weight"].to_f * 100, precision: 0)

.card
  %h3.section-title Quién evalúa
  %ul.menu
    - step.step_assignments.includes(:user).each do |asignacion|
      %li= asignacion.user.name

.card
  %h3.section-title Modo de IA
  %p.muted= t("flow.ai_modes.#{step.effective_ai_mode}")
```

Y en `app/views/steps/evaluation.html.haml`, **borrar** esas cuatro tarjetas de
la pila principal y declarar la referencia arriba del todo:

```haml
- content_for :referencia do
  = render "steps/referencia_evaluacion", step: @step, handler: @handler
```

Los formularios que vivían dentro de esas tarjetas —cambiar el modo de IA,
asignar evaluadores, tocar pesos— **se quedan en la columna principal**: son
trabajo, no referencia. La regla del spec es la que decide, y ahí la de la
derecha solo muestra.

Las demás pantallas se migran en el plan 2. Esta sola alcanza para probar que
el mecanismo anda de punta a punta.

- [ ] **Step 9: Verificar**

```bash
make spec
make screens
```
Esperado: suite verde (los system specs de `builder_island_spec.rb` usan `.step-card` y `.step-table`, que son propias y no cambiaron), `30 capturas`, sin `[CLASES]` ni `[MORPH]`.

Mirar `tmp/screenshots/09-3-step-evaluaci-n-t-cnica.png`: tiene que verse el drawer a la izquierda, el trabajo al centro y la referencia a la derecha.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "El shell de tres regiones

El flujo del desafío pasa a estar siempre a la vista, que es la pregunta que la
app no contestaba en ninguna pantalla: dónde estoy y qué sigue.

Qué va dónde lo decide una regla y no el gusto: la columna del medio es lo que
se hace, la de la derecha lo que se consulta y no se edita. Eso saca de la
pila principal las cuatro tarjetas que hoy compiten con el trabajo.

Y el drawer aparece solo si hay un desafío en contexto. La regla mira el
contexto, no el controller: una barra lateral vacía en /criteria_sets sería un
cuarto de pantalla que no dice nada.

Solo la pantalla de evaluación llena la referencia por ahora — alcanza para
probar el mecanismo de punta a punta; el resto va en el plan siguiente."
```

---

## Cierre de la fase

- [ ] **Correr todo una vez más y mergear**

```bash
make spec && make screens
git switch master && git merge --no-ff rediseno-tailwind
```

- [ ] **Escribir el plan 2** (los 18 partials, pantalla por pantalla, los 7 componentes Vue), ahora que el shell existe y define qué forma tienen que tomar.

- [ ] **Actualizar `CLAUDE.md`**: la sección «El sistema visual» y la primera línea de la hoja de estilos —que hoy dice «Sin framework CSS»— quedaron falsas.
