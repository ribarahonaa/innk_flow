# Popups de la IA — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** que pedirle algo a la IA muestre un popup modal mientras piensa y otro con la respuesta —incluida la propuesta por revisar y el error, que hoy no se ve.

**Architecture:** el servidor deja lo que pasó en `flash[:ia]` (un hash) y lo pinta como un `<template data-ia-respuesta>` en dos lugares: dentro del `turbo-frame#ai-suggestions` y en el layout. Un módulo JS nuevo (`app/javascript/ia_popups.js`) arma los dos `<dialog class="modal">` a partir de los eventos de Turbo. El flujo existente no cambia: el pedido sigue redirigiendo y `marco_para_pedido_de_ia` sigue decidiendo a dónde responde.

**Tech Stack:** Rails 7.1 + HAML · Turbo 8 (por npm, **sin** la gema `turbo-rails`) · Tailwind 4 + DaisyUI 5 (componente `modal`) · esbuild · RSpec request specs · Playwright (`make screens`).

**Spec:** `docs/superpowers/specs/2026-09-11-popups-de-ia-design.md`

## Global Constraints

- **Código, comentarios y mensajes de commit en español.**
- Todo corre en Docker. **Nunca `bundle exec` en el host.** Specs con `make spec*` (usan `app_test`); `docker compose exec app bundle exec rspec` da 403 «Blocked hosts».
- **Sin la gema `turbo-rails`:** Rails renderiza el layout completo también en los pedidos de marco, y Turbo recorta el marco de esa respuesta. Por eso el `<template>` va en el marco **y** en el layout.
- **El layout declara `turbo-refresh-method: morph`.** Ningún `<dialog>` puede existir durante un render: idiomorph se lleva puesto cualquier nodo que el cliente agregó y el servidor no manda.
- **Tailwind escanea texto, incluido `app/javascript`.** Las clases van escritas **enteras y literales** en el JS: nunca `` `modal-${x}` ``. Guarda: `spec/lint/clases_interpoladas_spec.rb`.
- **`card` de DaisyUI está excluida** (`exclude: card` en el `@plugin`). `modal` **no** lo está: se puede usar.
- Tokens de color existentes, con estos nombres exactos: `--ia`, `--ia-borde`, `--ia-panel`, `--danger`, `--danger-soft`, `--danger-borde`, `--muted`. El del borde es `--borde`, **no** `--border`.
- Las clases propias de la app van **sin capa** (`@layer`), que es lo que las hace ganarle a DaisyUI.
- Mezclas de color siempre `in oklab`, nunca `in oklch`.
- `make screens` **no puede llamar a la IA real**: desarrollo tiene `FLOW_AI_PROVIDER=anthropic` en `.env` y cada llamada cuesta plata.
- **Ninguna captura apunta a un desafío que también se use a mano.** El desafío nuevo (`recorrido-ia`) existe sólo para el recorrido.
- Rama: `popups-de-ia`. Commits con `ribarahonaa@gmail.com` (ya en el `git config` local).

---

## Estructura de archivos

| Archivo | Responsabilidad |
|---|---|
| `app/controllers/ai_requests_controller.rb` (modificar) | Registrar qué pasó en `flash[:ia]` en vez de `notice`/`alert` |
| `app/helpers/application_helper.rb` (modificar) | `respuesta_de_ia`: leer el flash y resolver la propuesta pendiente |
| `app/views/shared/_ia_respuesta.html.haml` (crear) | El `<template>` con el mensaje y, si hay, la propuesta |
| `app/views/shared/_ai_suggestion.html.haml` (crear) | Una propuesta: qué propone + Aplicar/Descartar. La usan el panel y el popup |
| `app/views/shared/_ai_suggestions.html.haml` (modificar) | Panel: usa el partial nuevo, pierde `.ai-waiting`, gana el `<template>` |
| `app/views/layouts/application.html.haml` (modificar) | Saltear `:ia` en el loop de flash; renderizar el `<template>` |
| `app/javascript/ia_popups.js` (crear) | Los dos popups, a partir de los eventos de Turbo |
| `app/javascript/application.js` (modificar) | Importar el módulo nuevo |
| `app/assets/stylesheets/application.css` (modificar) | Borrar el bloque `.ai-waiting`; sumar el de los popups |
| `db/seeds.rb` (modificar) | Sembrar `recorrido-ia`: en curso, Idear abierto asistido, dos ideas |
| `script/capture_screens.js` (modificar) | Dos capturas nuevas: el camino de error y el de éxito |
| `spec/requests/popups_de_ia_spec.rb` (crear) | `flash[:ia]` fila por fila, y el `<template>` en los dos lugares |
| `spec/requests/ai_spec.rb` (modificar) | Los ejemplos que miraban `flash[:notice]`/`[:alert]` pasan a `flash[:ia]` |

---

## Task 1: `flash[:ia]`, lo que registra el pedido

**Files:**
- Modify: `app/controllers/ai_requests_controller.rb:8-27` (la acción `create` y `success_message`)
- Modify: `app/views/layouts/application.html.haml` (el loop de flash dentro de `%main.app-main`)
- Modify: `spec/requests/ai_spec.rb:37`, `:49`, `:303`
- Test: `spec/requests/popups_de_ia_spec.rb` (crear)

**Interfaces:**
- Consumes: `Flow::AI::Runner::Result` (`ok?`, `run`, `suggestion`, `errors`, `reused?`, `error_sentence`), ya existente.
- Produces: `flash[:ia]`, un hash con **claves en string**: `{"tipo" => "ok"|"error", "mensaje" => String, "sugerencia_id" => String|nil}`. Las Tasks 2 y 3 dependen de esas tres claves exactas. `sugerencia_id` se llena **sólo** cuando la propuesta quedó pendiente de revisión.

La tabla que este task implementa, del spec §1:

| Qué pasó | tipo | mensaje | sugerencia_id |
|---|---|---|---|
| Propuesta para revisar | ok | «La IA respondió. Revisá la propuesta antes de aplicarla.» | sí |
| Ya había una igual pendiente (`reused?`) | ok | «Ya había una propuesta esperando tu revisión.» | sí |
| Se aplicó sola (`ai_auto`) | ok | «La IA respondió y se aplicó automáticamente.» | no |
| Evaluación de la IA (aditiva) | ok | «Listo: la evaluación de la IA ya está en la lista.» | no |
| Respondió, pero no se pudo aplicar (`ai_auto`) | error | «La IA respondió, pero no se pudo aplicar: …» | sí |
| Falló | error | «La IA no pudo responder: …» | no |
| Propósito desconocido (`ArgumentError`) | error | el mensaje de la excepción | no |

- [ ] **Step 1: Escribir el spec que falla**

Crear `spec/requests/popups_de_ia_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# Pedirle algo a la IA tiene dos momentos y ninguno se veía. El de la
# respuesta se perdía por una razón concreta: el mensaje viajaba en `notice` /
# `alert`, que el layout pinta ARRIBA de `.app-main` —afuera del
# `turbo-frame#ai-suggestions`—, así que en un pedido que responde al marco
# Turbo lo descartaba. La confirmación no se veía y el error tampoco.
#
# Ahora lo que pasó se registra en `flash[:ia]`, con la forma que el popup
# necesita: si salió bien o mal, qué decir, y cuál es la propuesta cuando
# quedó una por revisar.
RSpec.describe "lo que registra un pedido a la IA", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def miembro(email, rol)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, company: company, user: u, role: rol)
      u
    end
  end

  let!(:admin) { miembro("admin@test.dev", "admin") }

  let!(:challenge) do
    as_company(company) { create(:challenge, name: "Merma", brief: "Reducir merma.", ai_default_mode: "ai_assisted") }
  end

  before { sign_in(admin, company: company) }

  def pedir!(purpose, **params)
    post challenge_ai_requests_path(challenge, purpose: purpose, **params)
  end

  describe "en modo asistido" do
    it "deja la propuesta por revisar, con su id" do
      pedir!("propose_pipeline")

      expect(flash[:ia]["tipo"]).to eq("ok")
      expect(flash[:ia]["mensaje"]).to match(/Revisá la propuesta/)
      expect(flash[:ia]["sugerencia_id"]).to eq(as_company(company) { AiSuggestion.first.id })
    end

    # Un pedido repetido mientras la anterior sigue sin revisar no llama de
    # nuevo al proveedor. El mensaje perdió el «más abajo»: la propuesta ya no
    # está más abajo, está en el popup.
    it "avisa cuando ya había una esperando, y la vuelve a ofrecer" do
      pedir!("propose_pipeline")
      pedir!("propose_pipeline")

      expect(flash[:ia]["tipo"]).to eq("ok")
      expect(flash[:ia]["mensaje"]).to match(/Ya había una propuesta esperando/)
      expect(flash[:ia]["mensaje"]).not_to include("más abajo")
      expect(flash[:ia]["sugerencia_id"]).to be_present
    end
  end

  describe "en modo automático" do
    before { as_company(company) { challenge.update!(ai_default_mode: "ai_auto") } }

    it "dice que se aplicó sola y no ofrece nada que revisar" do
      pedir!("propose_pipeline")

      expect(flash[:ia]["tipo"]).to eq("ok")
      expect(flash[:ia]["mensaje"]).to match(/aplicó automáticamente/)
      expect(flash[:ia]["sugerencia_id"]).to be_nil
    end

    # La IA respondió y el dominio rechazó lo que propuso. Decir «no pudo
    # responder» sería falso, y además queda una propuesta pendiente que
    # alguien tiene que mirar: el popup la trae.
    it "cuando el dominio la rechaza, lo dice sin culpar a la IA, y trae la propuesta" do
      allow_any_instance_of(Flow::AI::Tasks::ProposePipeline)
        .to receive(:apply!).and_return([false, ["el flujo ya arrancó"]])

      pedir!("propose_pipeline")

      expect(flash[:ia]["tipo"]).to eq("error")
      expect(flash[:ia]["mensaje"]).to eq("La IA respondió, pero no se pudo aplicar: el flujo ya arrancó")
      expect(flash[:ia]["sugerencia_id"]).to be_present
    end
  end

  describe "cuando algo falla" do
    it "el proveedor caído se cuenta como tal" do
      allow_any_instance_of(Flow::AI::Providers::Fixture)
        .to receive(:complete).and_raise(StandardError, "se cayó")

      pedir!("propose_pipeline")

      expect(flash[:ia]["tipo"]).to eq("error")
      expect(flash[:ia]["mensaje"]).to eq("La IA no pudo responder: se cayó")
      expect(flash[:ia]["sugerencia_id"]).to be_nil
    end

    # Un propósito que no existe se rechaza ANTES de llamar a nadie: es el
    # único camino de error que `make screens` puede recorrer gratis.
    it "un propósito desconocido no llama al proveedor" do
      pedir!("propósito-inexistente")

      expect(flash[:ia]["tipo"]).to eq("error")
      expect(flash[:ia]["mensaje"]).to match(/propósito desconocido/)
      expect(as_company(company) { AiRun.count }).to be_zero
    end
  end

  # El flash de la IA ya no es una franja: es el popup. Pintarlo además arriba
  # de `.app-main` sería decir dos veces lo mismo, y encima escupiendo el hash.
  it "no se pinta como franja de flash" do
    pedir!("propose_pipeline")
    follow_redirect!

    expect(response.body).not_to include("flash--notice")
    expect(response.body).not_to include("tipo&quot;=&gt;")
  end
end
```

- [ ] **Step 2: Correr el spec y ver que falla**

```bash
make spec-file FILE=spec/requests/popups_de_ia_spec.rb
```

Esperado: FAIL. `flash[:ia]` es `nil`, así que los ejemplos revientan con `NoMethodError: undefined method '[]' for nil`.

- [ ] **Step 3: Reescribir la acción `create`**

En `app/controllers/ai_requests_controller.rb`, reemplazar el `redirect_back` y el `rescue` de `create`:

```ruby
    flash[:ia] = respuesta_de_ia(result)
    redirect_back fallback_location: challenge_path(@challenge)
  rescue ArgumentError => e
    flash[:ia] = { "tipo" => "error", "mensaje" => e.message, "sugerencia_id" => nil }
    redirect_back fallback_location: challenge_path(@challenge)
  end
```

Y agregar, en la sección `private`, arriba de `success_message`:

```ruby
  # Lo que el popup de respuesta va a decir.
  #
  # Un hash y no un `notice`: el popup necesita saber si salió bien o mal y,
  # cuando quedó algo por revisar, cuál es la propuesta. Además el `notice` se
  # perdía en los pedidos que responden al marco, porque el layout lo pinta
  # AFUERA del marco y Turbo se queda sólo con el marco.
  #
  # Las claves van en STRING a propósito: el flash viaja en la cookie de
  # sesión serializado a JSON, así que un símbolo vuelve como string y
  # `flash[:ia][:tipo]` sería `nil` del otro lado del redirect.
  #
  # `sugerencia_id` sólo cuando la propuesta quedó PENDIENTE: una ya aceptada
  # no tiene nada que revisar, y ofrecerle «Aplicar» a lo que ya se aplicó es
  # el control fantasma que estamos sacando.
  def respuesta_de_ia(result)
    {
      "tipo" => result.ok? ? "ok" : "error",
      "mensaje" => result.ok? ? success_message(result) : error_message(result),
      "sugerencia_id" => (result.suggestion&.id if result.suggestion&.pending?)
    }
  end

  # La IA respondió y el dominio rechazó lo que propuso: son dos cosas
  # distintas y antes se decían igual. «No pudo responder» era falso, y encima
  # escondía que había una propuesta pendiente esperando a una persona.
  def error_message(result)
    return "La IA respondió, pero no se pudo aplicar: #{result.error_sentence}" if result.suggestion

    "La IA no pudo responder: #{result.error_sentence}"
  end
```

Y en `success_message`, el mensaje de `reused?` pierde el «más abajo», que dejó de ser cierto:

```ruby
    return "Ya había una propuesta esperando tu revisión." if result.reused?
```

- [ ] **Step 4: Saltear `:ia` en el loop de flash del layout**

En `app/views/layouts/application.html.haml`, dentro de `%main.app-main`:

```haml
        - flash.each do |type, message|
          -# `:ia` no se pinta acá: es el popup de respuesta y lo arma
          -# `shared/_ia_respuesta`. Su valor además es un hash, así que
          -# pintarlo como franja escupiría el hash entero en la pantalla.
          - next if type.to_s == "ia"
          %div{ class: clase_de_flash(type) }= message
```

- [ ] **Step 5: Correr el spec nuevo y verificar que pasa**

```bash
make spec-file FILE=spec/requests/popups_de_ia_spec.rb
```

Esperado: PASS, 7 ejemplos.

- [ ] **Step 6: Actualizar los ejemplos de `ai_spec.rb` que miraban el flash viejo**

Tres lugares, `spec/requests/ai_spec.rb`:

```ruby
      expect(flash[:ia]["mensaje"]).to match(/Revisá la propuesta/)   # línea 37
```

```ruby
      expect(flash[:ia]["mensaje"]).to match(/aplicó automáticamente/) # línea 49
```

```ruby
      expect(flash[:ia]["tipo"]).to eq("ok")                           # línea 303, reemplaza el `flash[:alert]` nil
```

- [ ] **Step 7: Correr la suite entera**

```bash
make spec
```

Esperado: PASS, 0 fallas, 0 warnings. Si aparece alguna falla de otro spec que mire `flash[:notice]` después de un pedido a la IA, actualizarla igual que las tres de arriba —el pedido ya no deja `notice`.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/ai_requests_controller.rb app/views/layouts/application.html.haml \
        spec/requests/popups_de_ia_spec.rb spec/requests/ai_spec.rb
git commit -m "El pedido a la IA registra qué pasó en flash[:ia]"
```

---

## Task 2: el `<template>` con la respuesta, en el marco y en el layout

**Files:**
- Modify: `app/helpers/application_helper.rb` (agregar `respuesta_de_ia`)
- Create: `app/views/shared/_ai_suggestion.html.haml`
- Create: `app/views/shared/_ia_respuesta.html.haml`
- Modify: `app/views/shared/_ai_suggestions.html.haml`
- Modify: `app/views/layouts/application.html.haml`
- Test: `spec/requests/popups_de_ia_spec.rb` (ampliar)

**Interfaces:**
- Consumes: `flash[:ia]` con las tres claves de la Task 1.
- Produces: en el HTML servido, `<template data-ia-respuesta="true" data-tipo="ok|error">` con el mensaje y, cuando hay propuesta pendiente **y quien mira puede revisarla**, la tarjeta `.ai-suggestion` con sus dos `button_to`. La Task 3 lee **exactamente** el selector `template[data-ia-respuesta]` y el atributo `data-tipo`.
- Produces: `ApplicationHelper#respuesta_de_ia` → `{tipo:, mensaje:, sugerencia:}` o `nil`. **Ojo:** mismo nombre que el método privado del controller de la Task 1, y son dos cosas distintas —uno arma el hash, el otro lo lee—. No hay colisión (el del controller es privado y no es un helper), pero el nombre se elige a propósito para que se lean como las dos puntas del mismo dato.
- Produces: partial `shared/_ai_suggestion`, que recibe `suggestion:` y **no** filtra permisos: quien lo renderiza ya decidió que se puede ver.

- [ ] **Step 1: Escribir los specs que fallan**

Agregar a `spec/requests/popups_de_ia_spec.rb`, antes del `end` final:

```ruby
  describe "el <template> que el popup va a leer" do
    # Hacen falta LOS DOS renders. Este repo no tiene la gema `turbo-rails`,
    # así que Rails pinta el layout completo también cuando el pedido es de un
    # marco, y Turbo recorta el marco de esa respuesta: lo que está afuera del
    # marco se pierde. Y al revés, hay pantallas que ni siquiera tienen marco.
    it "aparece dentro del marco y en el layout, con la propuesta y sus botones" do
      pedir!("propose_pipeline")
      follow_redirect!

      expect(response.body.scan(/<template[^>]*data-ia-respuesta/).size).to eq(2)
      expect(response.body).to include('data-tipo="ok"')
      expect(response.body).to include("Revisá la propuesta")
      expect(response.body).to include("Aplicar")
      expect(response.body).to include("Descartar")
    end

    # Este es el caso que hoy se pierde entero: en modo asistido el pedido
    # responde al marco, y el error viajaba en un `alert` que el layout pinta
    # afuera del marco.
    it "el error en modo asistido llega adentro del marco" do
      allow_any_instance_of(Flow::AI::Providers::Fixture)
        .to receive(:complete).and_raise(StandardError, "se cayó")

      pedir!("propose_pipeline")
      follow_redirect!

      marco = response.body[/<turbo-frame id="ai-suggestions".*?<\/turbo-frame>/m]
      expect(marco).to include("data-ia-respuesta")
      expect(marco).to include('data-tipo="error"')
      expect(marco).to include("La IA no pudo responder: se cayó")
    end

    it "sin pedido de por medio no hay ningún template" do
      get challenge_path(challenge)

      expect(response.body).not_to include("data-ia-respuesta")
    end
  end

  # La ficha de evaluación —donde vive «Pedir la guía de la IA»— no tiene
  # `turbo-frame#ai-suggestions`, y hasta ahora no mostraba absolutamente nada.
  # Lo único que la cubre es el render del LAYOUT, que es incondicional: basta
  # con probar que esa copia vive afuera del marco. Montar la ficha entera acá
  # ataría el ejemplo a que el módulo de evaluación esté activo y a que haya
  # asignación, que no es lo que se está probando.
  it "el del layout vive afuera del marco, que es lo que cubre a una pantalla sin marco" do
    pedir!("propose_pipeline")
    follow_redirect!

    afuera = response.body.sub(/<turbo-frame id="ai-suggestions".*?<\/turbo-frame>/m, "")
    expect(afuera).to include("data-ia-respuesta")
    expect(afuera).to include("Revisá la propuesta")
  end
```

- [ ] **Step 2: Correr y ver que fallan**

```bash
make spec-file FILE=spec/requests/popups_de_ia_spec.rb
```

Esperado: los cuatro ejemplos nuevos en FAIL (`expected ... to include "data-ia-respuesta"`); los siete de la Task 1 siguen en PASS.

- [ ] **Step 3: El helper que lee el flash**

Agregar a `app/helpers/application_helper.rb`, arriba de `marco_para_pedido_de_ia`:

```ruby
  # Lo que dejó el último pedido a la IA, listo para el popup de respuesta.
  #
  # La propuesta se busca ACÁ y no en un controller porque el partial se
  # renderiza también desde el layout, donde no hay ivar que valga: el layout
  # lo sirven las treinta pantallas y ninguna sabe de esto.
  #
  # Por `find_by` y no `find`: entre el redirect y este render alguien pudo
  # descartarla desde otra pestaña, y el popup igual tiene que poder decir qué
  # pasó en vez de tirar un 404 sobre una pantalla que está bien.
  def respuesta_de_ia
    datos = flash[:ia]
    return nil if datos.blank?

    id = datos["sugerencia_id"]
    { tipo: datos["tipo"], mensaje: datos["mensaje"],
      sugerencia: id.present? ? AiSuggestion.find_by(id: id) : nil }
  end
```

- [ ] **Step 4: Sacar la tarjeta de una propuesta a su propio partial**

Crear `app/views/shared/_ai_suggestion.html.haml` con lo que hoy está adentro del `suggestions.each` de `shared/_ai_suggestions.html.haml`:

```haml
-# Una propuesta de la IA: qué propone, y los dos botones para decidir.
-#
-# Vive en un partial propio porque la usan DOS lugares: el panel de revisión
-# (`shared/_ai_suggestions`) y el popup de respuesta (`shared/_ia_respuesta`).
-#
-# NO filtra permisos: quien lo renderiza ya decidió que esta persona puede
-# revisarla —el panel filtra la lista, el popup pregunta por la única que
-# muestra—. Poner la guarda acá además la haría por partida doble.
- task = Flow::AI::Tasks::Base.for(suggestion.purpose, challenge: suggestion.ai_run.challenge, step: suggestion.ai_run.challenge_step, idea: suggestion.ai_run.idea) rescue nil

.ai-suggestion
  .ai-suggestion__head
    %span.ai-suggestion__purpose= t("flow.ai_purposes.#{suggestion.purpose}", default: suggestion.purpose.humanize)
    %span.muted= l(suggestion.created_at, format: :short)
  .ai-suggestion__body
    - if task
      = task.preview(suggestion.payload)
    - else
      %code= suggestion.payload.to_json.truncate(240)
  .ai-suggestion__actions
    -# Aplicar y descartar SÍ recargan: cambian el dominio, y lo que se ve
    -# alrededor (los campos, el flujo, las ideas) deja de ser cierto.
    = button_to "Aplicar", accept_ai_suggestion_path(suggestion),
                class: "btn btn-primary btn-sm", form: { data: { turbo_frame: "_top" } }
    = button_to "Descartar", reject_ai_suggestion_path(suggestion),
                class: "btn btn-ghost btn-sm", form: { data: { turbo_frame: "_top" } }
```

- [ ] **Step 5: El partial del `<template>`**

Crear `app/views/shared/_ia_respuesta.html.haml`:

```haml
-# La respuesta del último pedido a la IA, esperando a que `ia_popups.js` la
-# ponga en un popup.
-#
-# Va en un `<template>` y no en un div escondido: el contenido de un template
-# es INERTE —no se ve, sus formularios no se envían, y el parser ni siquiera
-# aplana un form dentro de otro, porque se parsea en un fragmento aparte—.
-# Por eso renderizarlo dos veces no hace daño.
-#
-# Y hacen falta las dos veces. Sin la gema `turbo-rails` Rails pinta el layout
-# completo también cuando el pedido es de un marco, y Turbo se queda SÓLO con
-# el marco: lo de afuera se descarta. Al revés, un pedido que responde a la
-# pantalla entera puede venir de una pantalla que no tiene marco (la ficha de
-# evaluación, donde vive «Pedir la guía de la IA»). Cuando llegan los dos, el
-# JS abre uno solo y borra los dos.
- respuesta = respuesta_de_ia
- return if respuesta.nil?

%template{ data: { ia_respuesta: true, tipo: respuesta[:tipo] } }
  %h2.section-title{ id: "ia-respuesta-titulo" }= respuesta[:tipo] == "error" ? "La IA no pudo" : "La IA respondió"
  %p.ia-respuesta__mensaje= respuesta[:mensaje]
  -# La misma pregunta que hace el panel, y la misma que hizo el controller al
  -# aceptar el pedido: pedir y aceptar son el mismo método.
  - if respuesta[:sugerencia] && policy(respuesta[:sugerencia]).accept?
    = render "shared/ai_suggestion", suggestion: respuesta[:sugerencia]
```

- [ ] **Step 6: El panel usa el partial nuevo y pierde el aviso de espera**

Reemplazar el cuerpo de `app/views/shared/_ai_suggestions.html.haml` desde `%turbo-frame#ai-suggestions` hasta el final (los comentarios de cabecera y la línea del `select` quedan como están, salvo el párrafo que describe `.ai-waiting`, que se va):

```haml
%turbo-frame#ai-suggestions
  = render "shared/ia_respuesta"

  - if suggestions.any?
    .card.ai-panel
      %h2.section-title
        Propuestas de la IA
        %span.ai-chip= suggestions.size
      - suggestions.each do |suggestion|
        = render "shared/ai_suggestion", suggestion: suggestion
```

Y en los comentarios de cabecera del mismo archivo, borrar el párrafo que arranca con «Mientras espera, Turbo le pone `aria-busy` al marco…» y poner en su lugar:

```haml
-# La espera dejó de vivir acá: era una franja más en la pantalla, no bloqueaba
-# nada y sólo existía cuando el pedido respondía a este marco. Ahora es un
-# popup modal que arma `app/javascript/ia_popups.js`.
```

- [ ] **Step 7: El layout renderiza el template**

En `app/views/layouts/application.html.haml`, justo después del loop de flash y antes del `= yield`:

```haml
        -# El popup de respuesta, para los pedidos que responden a la pantalla
        -# entera y para las pantallas que no tienen marco de propuestas.
        = render "shared/ia_respuesta"
```

- [ ] **Step 8: Correr el spec y verificar que pasa**

```bash
make spec-file FILE=spec/requests/popups_de_ia_spec.rb
```

Esperado: PASS, 11 ejemplos.

- [ ] **Step 9: Correr la suite entera**

```bash
make spec
```

Esperado: PASS, 0 fallas, 0 warnings. `spec/requests/panel_de_propuestas_spec.rb` es el que más de cerca mira este partial: tiene que seguir verde sin tocarlo, porque el filtro por propuesta no se movió.

- [ ] **Step 10: Commit**

```bash
git add app/helpers/application_helper.rb app/views/shared/_ai_suggestion.html.haml \
        app/views/shared/_ia_respuesta.html.haml app/views/shared/_ai_suggestions.html.haml \
        app/views/layouts/application.html.haml spec/requests/popups_de_ia_spec.rb
git commit -m "La respuesta de la IA viaja en un template, en el marco y en el layout"
```

---

## Task 3: los dos popups

**Files:**
- Create: `app/javascript/ia_popups.js`
- Modify: `app/javascript/application.js` (importar el módulo)
- Modify: `app/assets/stylesheets/application.css:2255-2295` (borrar el bloque `.ai-waiting`) y sumar el bloque de los popups
- Modify: `CLAUDE.md` (la sección «Las pantallas se actualizan, no se recargan»)

**Interfaces:**
- Consumes: `template[data-ia-respuesta]` con `data-tipo="ok|error"` (Task 2); el endpoint `/challenges/:challenge_id/ai_requests`.
- Produces: `dialog[data-ia="espera"]` y `dialog[data-ia="respuesta"]`, que la Task 4 busca desde Playwright por esos selectores exactos.

- [ ] **Step 1: Escribir el módulo**

Crear `app/javascript/ia_popups.js`:

```js
// Los dos popups de la IA: el de esperar y el de responder.
//
// Pedirle algo a la IA tiene dos momentos y ninguno se veía. Mientras piensa
// —de 10 a 70 segundos con un proveedor real— el único aviso era una franja
// dentro del marco de propuestas: no bloqueaba nada, se podía navegar a otra
// pantalla con el pedido en vuelo, y ni siquiera existía en los pedidos que
// responden a la pantalla entera. Cuando respondía, el mensaje viajaba en el
// flash que el layout pinta AFUERA del marco, así que Turbo lo descartaba.
//
// El servidor deja la respuesta en un `<template data-ia-respuesta>` —dentro
// del marco y en el layout, ver `shared/_ia_respuesta`— y acá se arman los
// popups a partir de los eventos de Turbo.
//
// LOS DIÁLOGOS LOS ARMA EL JS Y NUNCA EXISTEN DURANTE UN RENDER. El layout
// declara `turbo-refresh-method: morph`: un `<dialog open>` que el cliente
// agregó y el servidor no manda es un nodo de más, y idiomorph se lo lleva
// puesto a mitad de camino —o peor, le saca el `open` y deja el popup en el
// DOM sin verse—. Por eso el de espera se cierra y se saca en
// `turbo:before-render`, y el de respuesta se arma recién después de pintar.
//
// Las clases van escritas ENTERAS y literales: Tailwind escanea
// `app/javascript` igual que las vistas, y una clase armada con interpolación
// no llega a la hoja. El elemento queda sin ninguna regla detrás y en el DOM
// se ve perfecto mientras en pantalla no se ve nada.

const ENDPOINT = '/ai_requests';

let espera = null;
let respuesta = null;

// El único endpoint que hace pensar a la IA de forma síncrona. Un solo
// listener cubre TODOS los botones —las acciones del panel, «Mejorar con IA»,
// el «IA» de la evaluación, «Pedir la guía de la IA»— sin tocar ninguno.
function esPedidoDeIa(form) {
  if (!(form instanceof HTMLFormElement)) return false;
  try {
    return new URL(form.action, location.href).pathname.endsWith(ENDPOINT);
  } catch {
    return false;
  }
}

function nuevoDialogo(cual) {
  const el = document.createElement('dialog');
  el.className = 'modal';
  el.dataset.ia = cual;
  return el;
}

// Irse de la página con un pedido en vuelo pierde la respuesta que ya se está
// pagando. El navegador pide confirmación; Chrome ignora el texto y muestra
// el suyo, y `returnValue` es lo que todavía exigen los demás.
function avisarAntesDeSalir(e) {
  e.preventDefault();
  e.returnValue = '';
}

function abrirEspera() {
  if (espera) return;

  espera = nuevoDialogo('espera');
  espera.setAttribute('aria-labelledby', 'ia-espera-titulo');
  espera.innerHTML = `
    <div class="modal-box ia-espera" role="status" aria-live="polite" aria-busy="true">
      <span class="loading loading-spinner loading-lg ia-espera__spinner"></span>
      <h2 class="section-title" id="ia-espera-titulo">La IA está pensando</h2>
      <p class="muted">Puede tardar un minuto. No cierres ni recargues la página.</p>
    </div>
  `;
  // No se puede cerrar: `cancel` es Escape, no hay botón de cerrar, y no se
  // agrega `modal-backdrop` —que es el form que DaisyUI usa para el clic
  // afuera—, así que un clic afuera no hace nada.
  espera.addEventListener('cancel', (e) => e.preventDefault());

  document.body.appendChild(espera);
  espera.showModal(); // deja el resto de la página inerte: ni clics ni Tab.
  addEventListener('beforeunload', avisarAntesDeSalir);
}

function cerrarEspera() {
  removeEventListener('beforeunload', avisarAntesDeSalir);
  if (!espera) return;
  espera.close();
  espera.remove();
  espera = null;
}

function cerrarRespuesta() {
  if (!respuesta) return;
  respuesta.close();
  respuesta.remove();
  respuesta = null;
}

// El cuerpo puede venir de un `<template>` del servidor o armado acá (los
// errores que el servidor nunca llegó a contar).
function abrirRespuesta(cuerpo, tipo) {
  cerrarEspera();
  cerrarRespuesta();

  respuesta = nuevoDialogo('respuesta');
  respuesta.setAttribute('aria-labelledby', 'ia-respuesta-titulo');

  const caja = document.createElement('div');
  caja.className = tipo === 'error' ? 'modal-box ia-respuesta ia-respuesta--error' : 'modal-box ia-respuesta';

  const cerrar = document.createElement('button');
  cerrar.type = 'button';
  cerrar.className = 'btn btn-sm btn-circle btn-ghost ia-respuesta__cerrar';
  cerrar.setAttribute('aria-label', 'Cerrar');
  cerrar.textContent = '✕';
  cerrar.addEventListener('click', cerrarRespuesta);

  caja.append(cerrar, cuerpo);

  // El clic afuera. Es el `modal-backdrop` de DaisyUI: un form con un botón
  // que ocupa lo que queda del diálogo.
  const fondo = document.createElement('form');
  fondo.method = 'dialog';
  fondo.className = 'modal-backdrop';
  fondo.innerHTML = '<button aria-label="Cerrar">cerrar</button>';

  respuesta.append(caja, fondo);
  // Escape y el clic afuera cierran el `<dialog>` pero no lo sacan del DOM, y
  // un nodo de más sobrevive hasta el próximo morph.
  respuesta.addEventListener('close', () => { respuesta?.remove(); respuesta = null; });

  document.body.appendChild(respuesta);
  respuesta.showModal();
}

function mensajeSuelto(texto, extra) {
  const cuerpo = document.createElement('div');
  const titulo = document.createElement('h2');
  titulo.className = 'section-title';
  titulo.id = 'ia-respuesta-titulo';
  titulo.textContent = 'La IA no pudo';
  const parrafo = document.createElement('p');
  parrafo.className = 'ia-respuesta__mensaje';
  parrafo.textContent = texto;
  cuerpo.append(titulo, parrafo);
  if (extra) cuerpo.append(extra);
  return cuerpo;
}

// Después de pintar: si el servidor dejó una respuesta, se abre. Los templates
// se borran TODOS —llegan hasta dos, el del marco y el del layout— para que la
// próxima navegación no vuelva a abrir lo mismo.
function mostrarLoQueDejoElServidor() {
  const plantillas = document.querySelectorAll('template[data-ia-respuesta]');
  if (!plantillas.length) return;

  const primera = plantillas[0];
  const cuerpo = primera.content.cloneNode(true);
  const tipo = primera.dataset.tipo;
  plantillas.forEach((t) => t.remove());

  abrirRespuesta(cuerpo, tipo);
}

// ── Los eventos de Turbo ────────────────────────────────────────────────────

addEventListener('turbo:submit-start', (e) => {
  if (esPedidoDeIa(e.target)) {
    abrirEspera();
    return;
  }
  // Aplicar y Descartar salen del popup con `data-turbo-frame: "_top"`: se
  // cierra acá, antes de que el morph llegue y se encuentre el diálogo puesto.
  if (respuesta && respuesta.contains(e.target)) cerrarRespuesta();
});

// Red de seguridad: ningún camino puede dejar la espera abierta. Sólo cuando
// NO hubo éxito —si lo hubo, la cierra `turbo:before-render` justo antes de
// pintar, que es cuando corresponde: cerrarla acá deja la pantalla vieja
// interactiva unos milisegundos antes de que llegue la nueva.
addEventListener('turbo:submit-end', (e) => { if (!e.detail?.success) cerrarEspera(); });

// Justo antes de pintar, en los dos caminos: el marco y la pantalla entera.
addEventListener('turbo:before-frame-render', cerrarEspera);
addEventListener('turbo:before-render', () => { cerrarEspera(); cerrarRespuesta(); });

// Después de pintar, en los tres caminos: marco, morph/render y carga normal.
addEventListener('turbo:frame-render', mostrarLoQueDejoElServidor);
addEventListener('turbo:render', mostrarLoQueDejoElServidor);
addEventListener('turbo:load', mostrarLoQueDejoElServidor);

// Se cayó la red: el servidor no contestó nada, así que el mensaje lo arma el
// cliente. Sin esto la espera queda girando para siempre.
addEventListener('turbo:fetch-request-error', () => {
  abrirRespuesta(mensajeSuelto('No se pudo hablar con el servidor. Revisá tu conexión y probá de nuevo.'), 'error');
});

// La respuesta no trae el marco que se pidió: un 403, un 500, o la sesión
// vencida que devuelve el login. Turbo escribiría «Content missing» adentro
// del marco y nada más.
addEventListener('turbo:frame-missing', (e) => {
  e.preventDefault();
  const recargar = document.createElement('button');
  recargar.type = 'button';
  recargar.className = 'btn btn-primary btn-sm';
  recargar.textContent = 'Recargar la página';
  // Sin el aviso de salida de por medio: recargar acá es lo que pedimos.
  recargar.addEventListener('click', () => { removeEventListener('beforeunload', avisarAntesDeSalir); location.reload(); });
  abrirRespuesta(mensajeSuelto('La respuesta no llegó como se esperaba.', recargar), 'error');
});

// Volver atrás no puede mostrar un popup viejo: los diálogos no entran al
// caché de Turbo.
addEventListener('turbo:before-cache', () => { cerrarEspera(); cerrarRespuesta(); });
```

- [ ] **Step 2: Importarlo desde `application.js`**

En `app/javascript/application.js`, debajo del import de Turbo:

```js
import '@hotwired/turbo-rails';
// Los dos popups de la IA: el de esperar y el de responder. Chrome compartido
// porque los botones de IA viven en diez pantallas.
import './ia_popups';
```

- [ ] **Step 3: Borrar el aviso de espera viejo de la hoja**

En `app/assets/stylesheets/application.css`, borrar el bloque entero que va desde el comentario `/* ── Espera de la IA ──…` hasta el `@media (prefers-reduced-motion: reduce) { .ai-waiting__dot … }` inclusive (hoy líneas 2255-2295): `.ai-waiting`, `turbo-frame[aria-busy="true"] .ai-waiting`, `turbo-frame[aria-busy="true"] .ai-panel`, `.ai-waiting__dot`, `@keyframes ai-pulse` y su regla de movimiento reducido.

En su lugar, el bloque de los popups:

```css
/* ── Los dos popups de la IA ───────────────────────────────────────────────── */
/*  */
/* El armazón es el `modal` de DaisyUI (que NO está excluido: sólo `card` lo */
/* está) sobre un `<dialog>` de verdad: `showModal()` deja el resto de la */
/* página inerte, que es lo que el aviso viejo no hacía. */
.ia-espera { text-align: center; }

/* El spinner sigue girando aunque esté activado `prefers-reduced-motion`, a */
/* propósito: es la ÚNICA señal de que la IA sigue trabajando, y quieto se lee */
/* como colgado. El aviso viejo podía quedarse quieto porque además decía el */
/* texto; acá el texto está, pero la espera dura hasta un minuto. */
.ia-espera__spinner { color: var(--ia); margin-bottom: 12px; }

.ia-respuesta { position: relative; }
.ia-respuesta__cerrar { position: absolute; top: 8px; right: 8px; }
.ia-respuesta__mensaje { margin: 0 0 12px; font-size: 14px; line-height: 1.55; }
.ia-respuesta--error .ia-respuesta__mensaje { color: var(--danger); }
/* La propuesta dentro del popup es la última fila: la línea de abajo que la */
/* separa de la siguiente en el panel acá no separa de nada. */
.ia-respuesta .ai-suggestion { border-bottom: 0; padding-bottom: 0; }
```

- [ ] **Step 4: Compilar y verificar que la hoja trae las clases**

```bash
make yarn-build
docker compose exec app grep -c "ia-espera__spinner\|ia-respuesta__mensaje" app/assets/builds/application-build-css.css
docker compose exec app grep -c "modal-box" app/assets/builds/application-build-css.css
```

Esperado: los dos `grep` devuelven un número > 0. Si `modal-box` da 0, Tailwind no vio las clases del JS — revisar que `@source` en `application.css` incluya `javascript`.

- [ ] **Step 5: Verificar que nada del aviso viejo quedó suelto**

```bash
grep -rn "ai-waiting\|ai-pulse" app/ script/ spec/
```

Esperado: sin resultados. Si aparece alguno, sacarlo: una clase sin regla detrás se ve perfecta en el DOM y no se ve en pantalla, y `make screens` la marcaría.

- [ ] **Step 6: Correr la suite y el recorrido**

```bash
make spec
make screens
```

Esperado: `make spec` en PASS, 0 fallas. `make screens` con las 35 capturas, «Sin errores de JS ni respuestas >= 400». Este paso no prueba los popups todavía —eso es la Task 4—: prueba que agregarlos no rompió ninguna de las pantallas que ya andaban.

- [ ] **Step 7: Anotar la regla en `CLAUDE.md`**

En la sección «Las pantallas se actualizan, no se recargan», después del ítem de `turbo:before-cache`, agregar un cuarto:

```markdown
- **Un `<dialog>` abierto no puede existir durante un morph.** Idiomorph
  compara contra el HTML del servidor, y un diálogo que agregó el cliente es
  un nodo de más: se lo lleva puesto, o le saca el `open` y lo deja en el DOM
  sin verse. Por eso los dos popups de la IA los arma el JS y ninguno existe
  durante un render: el de espera se cierra y se saca en `turbo:before-render`
  y el de respuesta se arma recién en `turbo:render` (`ia_popups.js`).
```

- [ ] **Step 8: Commit**

```bash
git add app/javascript/ia_popups.js app/javascript/application.js \
        app/assets/stylesheets/application.css CLAUDE.md
git commit -m "Los dos popups de la IA: esperar y responder"
```

---

## Task 4: el recorrido en el navegador

**Files:**
- Modify: `db/seeds.rb` (sembrar `recorrido-ia`, junto a `sin-armar`)
- Modify: `script/capture_screens.js` (dos capturas nuevas, antes de `11-ai-runs`)

**Interfaces:**
- Consumes: `dialog[data-ia="espera"]` y `dialog[data-ia="respuesta"]` (Task 3); el desafío `recorrido-ia` del seed.
- Produces: dos capturas nuevas, `09-13-ia-espera` y `09-14-ia-respuesta`.

**Por qué estos dos caminos y no otros:** desarrollo usa el proveedor real (`FLOW_AI_PROVIDER=anthropic` en `.env`), así que ninguna captura puede disparar un pedido que llame a la IA. Quedan dos caminos que pasan por el servidor de verdad y no cuestan nada: un **propósito que no existe**, que `Flow::AI::Tasks::Base.for` rechaza con `ArgumentError` después de autorizar y antes de llamar a nadie; y **«Detectar duplicados»**, que con el proveedor de vectores en fixture compara local (`task.local?(provider)` → `run_locally`).

- [ ] **Step 1: Verificar a mano que «Detectar duplicados» no llama al proveedor**

Antes de escribir la captura, comprobar el supuesto. Con el stack arriba:

```bash
make rails
```

y adentro:

```ruby
Flow::Tenant.bypass! { puts Flow::AI.provider.name; puts Flow::AI.embeddings_provider.name }
```

Esperado: el primero `anthropic`, el segundo `fixture`. Si el segundo dice `anthropic`, **parar acá**: el camino de éxito costaría plata y hay que elegir otro. Anotarlo y consultar antes de seguir.

- [ ] **Step 2: Sembrar `recorrido-ia`**

En `db/seeds.rb`, justo antes del bloque de `Challenge.where(slug: "sin-armar")`:

```ruby
    # Un desafío EN CURSO que existe sólo para `make screens`, donde se
    # fotografían los dos popups de la IA.
    #
    # Propio y no compartido, como manda CLAUDE.md: cuando las capturas
    # dependieron de un desafío que además se usa a mano, bastó con que alguien
    # le aplicara una propuesta para que la corrida fallara por datos. Pasó dos
    # veces. `sin-formulario` tampoco sirve: está en borrador y sin ideas, y
    # darle ideas le cambiaría lo que fotografían sus otras capturas.
    #
    # Idear ABIERTO y en modo asistido, con dos ideas postuladas: hace falta
    # que haya al menos dos para que «Detectar duplicados» tenga contra qué
    # comparar.
    Challenge.where(slug: "recorrido-ia").destroy_all
    recorrido = Challenge.create!(
      slug: "recorrido-ia",
      name: "Menos papel en la operación",
      brief: "Cada despacho se imprime tres veces y nadie vuelve a mirar esas copias. " \
             "Buscamos ideas para sacar el papel del circuito sin perder la trazabilidad.",
      ai_default_mode: "ai_assisted"
    )
    recorrido_ideacion = recorrido.pipeline.insert(kind: "ideation", after: :end, name: "Postulación")
    recorrido.pipeline.insert(kind: "evolution", after: :end, name: "Ronda de feedback")
    [
      ["titulo", "Título", "text", { "is_title" => true }, "Una frase que identifique la idea."],
      ["problema", "¿Qué problema resuelve?", "textarea", {}, "La situación actual y su costo."],
      ["solucion", "¿Cómo funcionaría?", "textarea", {}, "Qué se hace y quién lo hace."]
    ].each_with_index do |(key, label, type, config, hint), index|
      recorrido_ideacion.form_fields.create!(key: key, label: label, field_type: type, hint: hint,
                                             required: true, position: index, config: config)
    end
    recorrido.pipeline.start!
    recorrido_ideacion.reload

    [
      ["Guía de despacho digital",
       "Cada despacho se imprime tres veces y las copias terminan en una caja que nadie revisa.",
       "Firmar la guía en el celular del chofer y guardar el PDF contra el número de despacho."],
      ["Firma en el celular del transportista",
       "El papel sale de bodega sólo para que alguien firme, y después vuelve para archivarse.",
       "Que el transportista firme en una app y que el sistema cierre el despacho con esa firma."]
    ].each do |titulo, problema, solucion|
      idea = Idea.create!(challenge: recorrido, author: User.find_by!(email: "part1@demo.test"),
                          status: "draft", origin: "human")
      Flow::Ideas::PublishVersion.new(
        idea, payload: { "titulo" => titulo, "problema" => problema, "solucion" => solucion },
        author: idea.author, actor_type: "human", source_step: recorrido_ideacion,
        change_note: "Creación de la idea"
      ).call
      idea.update!(submitted_at: Time.current)
    end
```

Y en el bloque de `puts` del final, después de la línea del desafío en borrador:

```ruby
    puts "Desafío del recorrido: #{recorrido.name} (#{recorrido.ideas.count} ideas)"
```

- [ ] **Step 3: Correr el seed y verificar**

```bash
make seed
```

Esperado: la línea `Desafío del recorrido: Menos papel en la operación (2 ideas)`. Después, abrir a mano `http://localhost:3001/challenges/recorrido-ia` con `admin@demo.test` y comprobar que el módulo Idear está abierto y que las dos ideas aparecen en la lista.

- [ ] **Step 4: Escribir las dos capturas**

En `script/capture_screens.js`, antes de `await shot(page, '11-ai-runs', '/admin/ai_runs');`:

```js
  // ── Los dos popups de la IA ────────────────────────────────────────────────
  //
  // Desarrollo usa el proveedor REAL (FLOW_AI_PROVIDER=anthropic): ninguna
  // captura puede disparar un pedido que llame a la IA. Los dos caminos de acá
  // pasan por el servidor de verdad y no cuestan un peso: un propósito que no
  // existe se rechaza antes de llamar a nadie, y «Detectar duplicados» compara
  // local porque el proveedor de VECTORES es el fixture.
  //
  // Sobre `recorrido-ia`, que existe sólo para esto: las capturas que
  // dependieron de un desafío que también se usa a mano fallaron por datos dos
  // veces.
  await page.goto(BASE + '/challenges/recorrido-ia', { waitUntil: 'networkidle' });

  // 1 · La espera. El pedido se RETIENE para fotografiar el popup girando y
  // comprobar que Escape no lo cierra; después se suelta y tiene que irse solo.
  let soltar = null;
  await page.route('**/ai_requests*', async (route) => {
    await new Promise((resolve) => { soltar = resolve; });
    await route.continue();
  });

  // Se reescribe la acción de un formulario de IA que ya está en la pantalla:
  // así el pedido va con su token CSRF y por el mismo camino que un clic real.
  const hayForm = await page.evaluate(() => {
    const form = document.querySelector('form[action*="/ai_requests"]');
    if (!form) return false;
    const url = new URL(form.action);
    url.searchParams.set('purpose', 'proposito-inexistente');
    form.action = url.toString();
    form.requestSubmit();
    return true;
  });
  if (!hayForm) {
    failures++;
    console.error('[IA] recorrido-ia no ofrece ningún pedido a la IA');
  }

  await page.waitForSelector('dialog[data-ia="espera"][open]', { timeout: 5000 });
  await capturar(page, '09-13-ia-espera');

  // No se puede cerrar: es la razón de ser del popup.
  await page.keyboard.press('Escape');
  if (!(await page.locator('dialog[data-ia="espera"][open]').count())) {
    failures++;
    console.error('[IA] la espera se cerró con Escape');
  }

  if (soltar) soltar();
  await page.waitForSelector('dialog[data-ia="respuesta"][open]', { timeout: 15000 });
  if (await page.locator('dialog[data-ia="espera"]').count()) {
    failures++;
    console.error('[IA] la espera quedó puesta después de la respuesta');
  }
  const rojo = await page.locator('dialog[data-ia="respuesta"] .ia-respuesta--error').count();
  if (!rojo) {
    failures++;
    console.error('[IA] un pedido rechazado no muestra el popup de error');
  }
  await page.click('dialog[data-ia="respuesta"] .ia-respuesta__cerrar');
  await page.unroute('**/ai_requests*');

  // 2 · El éxito, con la propuesta adentro del popup. «Detectar duplicados»
  // vive en la ficha de una idea, y se llega por link: un `goto` monta la
  // pantalla igual y esconde los bugs de Turbo.
  const aIdea = page.locator('a[href*="/ideas/"]').first();
  if (!(await aIdea.count())) {
    failures++;
    console.error('[IA] recorrido-ia no ofrece ningún link a una idea');
  }
  await aIdea.click();
  await page.waitForURL(/\/ideas\//);
  await page.click('form[action*="detect_duplicates"] button');
  await page.waitForSelector('dialog[data-ia="respuesta"][open]', { timeout: 30000 });

  for (const texto of ['Aplicar', 'Descartar']) {
    if (!(await page.locator(`dialog[data-ia="respuesta"] button:has-text("${texto}")`).count())) {
      failures++;
      console.error(`[IA] el popup de respuesta no ofrece «${texto}»`);
    }
  }
  // Se captura CON el popup abierto: así la guarda de clases sin regla detrás
  // que corre en `capturar()` revisa también las del modal.
  await capturar(page, '09-14-ia-respuesta');

  // Descartar, para no dejar una propuesta pendiente: la corrida siguiente la
  // encontraría como «ya había una» y el camino de éxito dejaría de probarse.
  await page.click('dialog[data-ia="respuesta"] button:has-text("Descartar")');
  await page.waitForSelector('dialog[data-ia="respuesta"]', { state: 'detached', timeout: 10000 });

```

- [ ] **Step 5: Correr el recorrido**

```bash
make screens
```

Esperado: 37 capturas (las 35 de antes más las dos nuevas) y «Sin errores de JS ni respuestas >= 400». Mirar a ojo `tmp/screenshots/09-13-ia-espera.png` y `09-14-ia-respuesta.png`: la primera con el spinner violeta sobre la pantalla atenuada, la segunda con el mensaje y la propuesta con sus dos botones.

- [ ] **Step 6: Correr el recorrido una segunda vez**

```bash
make screens
```

Esperado: el mismo resultado. Es la prueba de que el «Descartar» del final deja la base como la encontró — si la segunda corrida muestra «Ya había una propuesta esperando», el descarte no llegó a aplicarse antes de cerrar.

- [ ] **Step 7: Suite completa**

```bash
make spec
```

Esperado: PASS, 0 fallas, 0 warnings.

- [ ] **Step 8: Commit**

```bash
git add db/seeds.rb script/capture_screens.js
git commit -m "El recorrido fotografía los dos popups de la IA"
```

---

## Verificación final de la rama

Antes de dar la rama por terminada, las tres cosas juntas y con la salida a la vista:

```bash
make spec      # 0 fallas, 0 warnings
make screens   # 37 capturas, sin errores de JS ni respuestas >= 400
grep -rn "ai-waiting\|ai-pulse" app/ script/ spec/   # sin resultados
```

Y a mano, porque ninguna de las tres lo cubre: **`Flow::Setup` no se toca en esta rama** —no se borra ni se muda ninguna pantalla de configuración—, así que no hay `setup_nav` que pueda quedar huérfano. Si durante la ejecución aparece la necesidad de mover una pantalla, revisar `Flow::Setup::Step#path` y los renders de `setup_nav`/`setup_progress` **a mano**: la suite queda en verde igual cuando un paso pierde su pie.

Opcional y decisión de Raúl, porque cuesta plata: un pedido de verdad con el proveedor real para ver la espera larga (10 a 70 segundos) de punta a punta.

## Fuera de alcance (del spec, se repite acá para que no se cuele)

- «Evaluar todas con IA»: encola trabajos en segundo plano, no hay espera síncrona que mostrar.
- Aplicar y Descartar: siguen con su flash de siempre.
- Los botones de una propuesta informativa: «Detectar duplicados» sigue mostrando «Aplicar» aunque no aplique nada. Queda anotado.
- Un tope de tiempo para la espera.
