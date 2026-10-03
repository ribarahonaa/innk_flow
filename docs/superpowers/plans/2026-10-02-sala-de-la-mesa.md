# La sala de la mesa — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que una mesa ya repartida entre a una pantalla propia por desafío, vea con quiénes está sentada y de qué trata el desafío, y recién ahí reciba el formulario (idear) o el selector de ideas de su mesa con su contenido (evolución).

**Architecture:** Una ruta nueva (`GET /workshops/:workshop_id/salas/:id` → `WorkshopRoomsController#show`) que reusa el anidado de `workshop_challenges` que ya existía con `only: []`. `workshops/show` deja de apilar salas y pasa a ser selector con el `brief` de cada desafío; con una sola sala trabajable y sin bloque de armado, redirige a ella. La pregunta «¿hay una sola sala y el taller no tiene nada más que ofrecer?» vive una vez, en `Flow::Workshops::Rooms`, y la consultan el redirect y el breadcrumb. No se agrega ningún camino de escritura: en evolución el formulario sigue creando una `WorkshopProposal` pendiente.

**Tech Stack:** Rails 8, HAML, Turbo 8 (morph), Pundit, Postgres, RSpec + factory_bot, Playwright (`make screens`). Todo en Docker.

**Spec:** `docs/superpowers/specs/2026-10-02-sala-de-la-mesa-design.md`

## Global Constraints

- **El código va en inglés; los comentarios y los mensajes de commit, en español.** Los identificadores en español que ya existen (`chip_de_estado`, los specs enteros) no se renombran.
- **Nada de `bundle exec` en el host.** Los specs corren con `make spec-file FILE=…` / `make spec-line FILE=… LINE=…`, que usan el contenedor `app_test`. Correr `docker compose exec app bundle exec rspec` deja `RAILS_ENV=development` y **todos** los request specs vuelven 403 «Blocked hosts: www.example.com».
- **Toda lectura del dominio en un spec va dentro de `as_company(company) { … }`**, incluido un `.new` y cualquier asociación leída después de salir del bloque.
- **Lo que no se ve da 404, no 403.** Los desafíos y las ideas se buscan por `policy_scope`; el taller también (`policy_scope(Workshop).find_by!`).
- **La consulta de ideas va en el controller y por `policy_scope(Idea)`**: `spec/lint/ideas_por_policy_scope_spec.rb` sólo mira controllers.
- **Ninguna clase de Tailwind interpolada.** Los chips se piden por helper (`chip_de_estado`, `chip("version")`); un `"badge-#{x}"` no llega a la hoja. Lo cuida `spec/lint/clases_interpoladas_spec.rb`.
- **Sin CSS nuevo.** Se reusan `card` + `card-body`, `.field-list` / `.field-list__item` (densidad de `.app-aside`), `.people-list` / `__item` / `__name` / `__role`, `.empty-state`, `.form-actions`, `.answer-list`, `.section-head`, `.page-head`, `.breadcrumb`. Si se agrega una clase nueva, `spec/lint/reglas_sin_elemento_spec.rb` y `[CLASES]` de `make screens` la cazan.
- **Ninguna tabla ni columna nueva** en este plan. Si apareciera una, va en inglés sin excepción.
- **`make yarn-build` antes de `make screens`**, siempre que se toquen vistas o `app/javascript/`: la hoja y el bundle viven sólo en el contenedor y están gitignoreados.
- **En las capturas se navega por link, nunca con `goto`**, y después de un clic se espera `waitForURL` o un selector — `networkidle` se calma antes de que Turbo ponga el body nuevo.
- **Los commits no llevan la línea `Co-Authored-By`.** Sí la línea `Claude-Session:`.
- Migraciones: no hay. Si hubiera, `schema_format = :sql` y se commitea `db/structure.sql`.

## Review Focus

Cinco clases de entrada que la spec implica y que ningún test de la app ejercita hoy, la más probable primero. Cada una tiene su test agregado en la tarea que es dueña del código.

1. **`?idea=` con un id que no es del conjunto trabajable** (de otra mesa, eliminado, de otra empresa, inventado): tiene que quedar sin selección y seguir mostrando el selector, no 403 ni 500. → Task 5.
2. **Un taller con DOS salas trabajables y la persona sin mesa en ninguna**: el selector se muestra, cada sala dice «sólo se crea un borrador desde una mesa», y **no** redirige (el redirect sólo con una sola sala). → Task 3.
3. **La URL de la sala de un vínculo `:unopened`** (taller en borrador, `challenge_step_id` nulo): motivo propio, sin formulario, sin 404 y sin pantalla en blanco — el estado que ya reventó una vez en este repo. → Task 2.
4. **Taller en modo `individual`**: la mesa es de una persona y no hay mesa de llegada (`arrival_group!` devuelve `nil`), así que el panel de la mesa tiene que decirlo en vez de desaparecer. → Task 6.
5. **Una idea trabajable sin `current_version`**: el bloque de contenido muestra `—` por campo y no revienta. `Idea#payload` ya devuelve `{}` sin versión y `Idea#title` ya cae en `"(sin título)"`, así que el modelo protege — lo que el test fija es que la VISTA no lea `current_version.label` sin el `&.`. → Task 5.

---

### Task 1: `Flow::Workshops::Rooms`, la pregunta única

El redirect del taller y el breadcrumb de la sala tienen que preguntar lo mismo. Escrito dos veces, el día que uno cambie aparece un bucle de navegación o un link muerto.

**Files:**
- Create: `app/lib/flow/workshops/rooms.rb`
- Test: `spec/lib/flow/workshops/rooms_spec.rb`

**Interfaces:**
- Consumes: `WorkshopChallenge#room_state` (devuelve `:ideation`, `:evolution`, `:closed`, `:unopened`, `:stale`), `WorkshopChallenge::WORKABLE_KINDS` (`%w[ideation evolution]`).
- Produces: `Flow::Workshops::Rooms.new(workshop)` con `#links` (todos los vínculos, precargados), `#workable` (los de `room_state` trabajable), `#only_room` (el único trabajable o `nil`), `#redirects?(can_assemble:)` (booleano).

- [ ] **Step 1: Escribir el spec que falla**

Crear `spec/lib/flow/workshops/rooms_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# El redirect del taller y el breadcrumb de la sala preguntan lo MISMO. Si la
# pregunta viviera en dos lugares, el día que uno cambie aparece un bucle:
# el taller manda a la sala y la sala ofrece volver al taller.
RSpec.describe Flow::Workshops::Rooms do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def room(workshop, kind:, step_status: "active", link_status: "open")
    challenge = create(:challenge)
    step = create(:challenge_step, challenge: challenge, kind: kind, status: step_status)
    create(:workshop_challenge, workshop: workshop, challenge: challenge,
                                challenge_step: step, status: link_status)
  end

  it "con una sola sala trabajable la nombra, y redirige a quien no arma el taller" do
    as_company(company) do
      workshop = create(:workshop, status: "open")
      sala = room(workshop, kind: "ideation")
      room(workshop, kind: "evaluation") # no es trabajable: un taller no trabaja ahí

      rooms = described_class.new(workshop)

      expect(rooms.workable.map(&:id)).to eq([ sala.id ])
      expect(rooms.only_room.id).to eq(sala.id)
      expect(rooms.redirects?(can_assemble: false)).to be(true)
    end
  end

  it "a quien arma el taller NO lo redirige: ahí está el bloque de armado" do
    as_company(company) do
      workshop = create(:workshop, status: "open")
      room(workshop, kind: "ideation")

      expect(described_class.new(workshop).redirects?(can_assemble: true)).to be(false)
    end
  end

  it "con dos salas trabajables no hay a dónde redirigir" do
    as_company(company) do
      workshop = create(:workshop, status: "open")
      room(workshop, kind: "ideation")
      room(workshop, kind: "evolution")

      rooms = described_class.new(workshop)

      expect(rooms.workable.size).to eq(2)
      expect(rooms.only_room).to be_nil
      expect(rooms.redirects?(can_assemble: false)).to be(false)
    end
  end

  # Un taller en BORRADOR no tiene salas: `Open` todavía no resolvió el módulo
  # de cada vínculo, así que `room_state` es `:unopened`. Sin esto, un borrador
  # recién armado redirigía a una sala que no existe.
  it "un taller en borrador no tiene ninguna sala trabajable" do
    as_company(company) do
      workshop = create(:workshop, status: "draft")
      challenge = create(:challenge)
      create(:workshop_challenge, workshop: workshop, challenge: challenge, challenge_step: nil)

      rooms = described_class.new(workshop)

      expect(rooms.workable).to be_empty
      expect(rooms.redirects?(can_assemble: false)).to be(false)
    end
  end

  it "el vínculo cerrado y el que venció no cuentan" do
    as_company(company) do
      workshop = create(:workshop, status: "open")
      room(workshop, kind: "ideation", link_status: "closed")
      room(workshop, kind: "ideation", step_status: "completed")

      expect(described_class.new(workshop).workable).to be_empty
    end
  end
end
```

- [ ] **Step 2: Correrlo y verlo fallar**

```bash
make spec-file FILE=spec/lib/flow/workshops/rooms_spec.rb
```

Esperado: FALLA con `uninitialized constant Flow::Workshops::Rooms`.

- [ ] **Step 3: Escribir la clase**

Crear `app/lib/flow/workshops/rooms.rb`:

```ruby
# frozen_string_literal: true

module Flow
  module Workshops
    # Qué salas tiene un taller y si hay UNA sola a la que mandar a alguien.
    #
    # Existe por una sola razón: el redirect de `workshops#show` y el breadcrumb
    # de la sala tienen que preguntar lo mismo. Si el taller redirige a la sala,
    # un link «volver al taller» rebota en bucle; el breadcrumb lo evita
    # preguntando por `redirects?`, y una copia de esa condición escrita a mano
    # en la vista mentiría el día que una de las dos cambie.
    class Rooms
      def initialize(workshop)
        @workshop = workshop
      end

      # Precargado: el selector dibuja el nombre y el brief de cada desafío, y
      # `room_state` pregunta por el módulo de cada vínculo.
      def links
        @links ||= @workshop.workshop_challenges.includes(:challenge, :challenge_step).to_a
      end

      # `WORKABLE_KINDS` y no una lista nueva: las dos únicas fases sobre las
      # que un taller tiene algo que hacer ya están declaradas en el modelo.
      def workable
        @workable ||= links.select { |link| WorkshopChallenge::WORKABLE_KINDS.include?(link.room_state.to_s) }
      end

      def only_room = workable.size == 1 ? workable.first : nil

      # `can_assemble` entra como argumento y no se resuelve acá: es una
      # pregunta de Pundit sobre quien mira (`WorkshopPolicy#update?`), y esta
      # clase no conoce la membresía. Quien administra nunca se redirige
      # —el bloque de armado es lo que tiene que ver—.
      def redirects?(can_assemble:) = !can_assemble && !only_room.nil?
    end
  end
end
```

- [ ] **Step 4: Correrlo y verlo pasar**

```bash
make spec-file FILE=spec/lib/flow/workshops/rooms_spec.rb
```

Esperado: 5 ejemplos, 0 fallas.

- [ ] **Step 5: Commit**

```bash
git add app/lib/flow/workshops/rooms.rb spec/lib/flow/workshops/rooms_spec.rb
git commit -m "$(cat <<'MSG'
Una pregunta sola para «¿hay una única sala?»

El redirect del taller y el breadcrumb de la sala tienen que decir lo
mismo: si el taller manda a la sala, un link de vuelta al taller rebota
en bucle. Escrita dos veces, la condición miente el día que una cambie.

Claude-Session: https://claude.ai/code/session_01KajVAKcwc9zMj6qGWVYai2
MSG
)"
```

---

### Task 2: la ruta y `WorkshopRoomsController#show`

La sala existe como pantalla propia y renderiza las caras que YA existen (`workshops/_sala_idear`, `_sala_evolucion`). `workshops/show` sigue apilándolas igual: así esta tarea deja las dos pantallas funcionando y nada se rompe en el medio. El selector llega en la Task 3.

**Files:**
- Modify: `config/routes.rb:124-127`
- Modify: `app/models/workshop.rb` (sumar `#group_of`)
- Modify: `app/controllers/workshops_controller.rb:52-56` (usar `#group_of`)
- Modify: `app/controllers/workshop_ideas_controller.rb` (borrar el `group_of` privado)
- Modify: `app/controllers/workshop_proposals_controller.rb` (borrar el `group_of` privado)
- Create: `app/controllers/workshop_rooms_controller.rb`
- Create: `app/views/workshop_rooms/show.html.haml`
- Test: `spec/requests/workshop_room_spec.rb`

**Interfaces:**
- Consumes: `Flow::Workshops::Rooms` (Task 1), `WorkshopPolicy#work?`, `WorkshopPolicy#update?`, `Flow::Workshops::MaterializeClosures`.
- Produces: la ruta `workshop_sala_path(workshop, link)`; `Workshop#group_of(user)` → `WorkshopGroup` o `nil`; las variables de instancia que consumen las vistas de las Tasks 4–6: `@workshop`, `@link`, `@group`, `@rooms`.

- [ ] **Step 1: Escribir el spec que falla**

Crear `spec/requests/workshop_room_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# La sala como pantalla propia. Lo que se prueba acá es la PUERTA: quién
# entra, qué devuelve lo que no se ve, y que un vínculo no trabajable diga su
# motivo en vez de quedarse mudo o dar 404.
RSpec.describe "la sala del taller", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email, role = :participant)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, role, company: company, user: u)
      u
    end
  end

  let!(:ana) { member("ana@test.dev") }
  let!(:carla) { member("carla@test.dev") }
  let!(:admin) { member("admin@test.dev", :admin) }

  let!(:scene) do
    as_company(company) do
      challenge = create(:challenge, brief: "Bajar la merma de bodega sin tocar el stock de seguridad.")
      step = create(:challenge_step, challenge: challenge, kind: "ideation", status: "active")
      create(:form_field, challenge_step: step, label: "Resumen", field_type: "text")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge, challenge_step: step)
      group = create(:workshop_group, workshop: workshop)
      create(:workshop_group_member, workshop_group: group, user: ana)
      { challenge: challenge, step: step, workshop: workshop, link: link, group: group }
    end
  end

  it "quien está en la mesa entra y ve el nombre del desafío" do
    sign_in(ana, company: company)
    get workshop_sala_path(scene[:workshop], scene[:link])

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(scene[:challenge].name)
  end

  # `work?` da true por `administers_any?` sin mesa: entra y la sala se lo dice.
  it "quien administra entra sin estar sentado" do
    sign_in(admin, company: company)
    get workshop_sala_path(scene[:workshop], scene[:link])

    expect(response).to have_http_status(:ok)
  end

  it "quien no fue convocado no la ve: 404, no 403" do
    sign_in(carla, company: company)
    get workshop_sala_path(scene[:workshop], scene[:link])

    expect(response).to have_http_status(:not_found)
  end

  it "un vínculo de otro taller da 404 aunque el taller propio se vea" do
    otro_link = as_company(company) do
      otro = create(:workshop, status: "open")
      create(:workshop_challenge, workshop: otro, challenge: scene[:challenge])
    end
    sign_in(ana, company: company)
    get workshop_sala_path(scene[:workshop], otro_link)

    expect(response).to have_http_status(:not_found)
  end

  # Review Focus 3. `:unopened` es el vínculo de un taller que todavía no se
  # abrió: `challenge_step_id` es nulo a propósito. Es el estado que una vez
  # cayó en la rama equivocada y anunció «el desafío avanzó de fase», que es
  # falso, y antes de eso dejó la sala EN BLANCO.
  it "la sala de un taller en borrador dice que todavía no empezó, sin 404 ni pantalla vacía" do
    draft = as_company(company) do
      w = create(:workshop, status: "draft")
      g = create(:workshop_group, workshop: w)
      create(:workshop_group_member, workshop_group: g, user: ana)
      create(:workshop_challenge, workshop: w, challenge: scene[:challenge], challenge_step: nil)
    end
    sign_in(ana, company: company)
    get workshop_sala_path(draft.workshop, draft)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("todavía no se abrió")
    expect(response.body).not_to include(%(name="payload[))
  end

  it "la sala de un vínculo cerrado muestra su motivo y ningún formulario" do
    as_company(company) do
      scene[:link].update!(status: "closed", closed_at: Time.current,
                           closed_reason: "El desafío está en Evaluación.")
    end
    sign_in(ana, company: company)
    get workshop_sala_path(scene[:workshop], scene[:link])

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("El desafío está en Evaluación.")
    expect(response.body).not_to include(%(name="payload[))
  end

  # El cierre es PEREZOSO: nada se engancha en `advance!`. Entrar a la sala es
  # lo que hace que el taller se entere, así que materializar va ANTES de leer
  # el vínculo o la sala dibuja trabajo sobre un módulo ya cerrado.
  it "materializa el cierre al entrar, y lo dice" do
    as_company(company) do
      scene[:step].update!(status: "completed")
      create(:challenge_step, challenge: scene[:challenge], kind: "evolution", status: "active")
    end
    sign_in(ana, company: company)
    get workshop_sala_path(scene[:workshop], scene[:link])

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Evolución")
    as_company(company) { expect(scene[:link].reload).to be_closed }
  end
end
```

- [ ] **Step 2: Correrlo y verlo fallar**

```bash
make spec-file FILE=spec/requests/workshop_room_spec.rb
```

Esperado: FALLA con `undefined method 'workshop_sala_path'` (la ruta de `show` no existe).

- [ ] **Step 3: Abrir la ruta**

En `config/routes.rb`, cambiar el bloque de las salas:

```ruby
    # La sala de UN desafío dentro del taller. El id es el del VÍNCULO, no el
    # del desafío: el vínculo es el que sabe contra qué módulo se trabaja.
    #
    # `show` es la pantalla donde la mesa trabaja: el formulario de idear o el
    # selector de ideas de evolución, con el brief del desafío y la mesa al
    # costado. `workshops#show` ya no apila las salas — es el selector.
    resources :workshop_challenges, only: %i[show], path: "salas", as: :sala,
                                    controller: "workshop_rooms" do
      resources :ideas, only: %i[create], controller: "workshop_ideas"
      resources :proposals, only: %i[create], controller: "workshop_proposals"
    end
```

- [ ] **Step 4: Sumar `Workshop#group_of`**

En `app/models/workshop.rb`, debajo de `arrival_group!`:

```ruby
  # La mesa de alguien en ESTE taller, o `nil`. Vive en el taller por lo mismo
  # que `arrival_group!`: es SU mesa. Estaba escrito tres veces —el `group_of`
  # privado de los dos controllers que escriben y el `@my_group` de
  # `workshops#show`—, y la sala habría sido la cuarta copia.
  def group_of(user)
    return nil if user.nil?

    workshop_groups.joins(:workshop_group_members)
                   .find_by(workshop_group_members: { user_id: user.id })
  end
```

Y reemplazar las tres copias:

- `app/controllers/workshops_controller.rb`, en `show`: `@my_group = @workshop.group_of(current_user)`.
- `app/controllers/workshop_ideas_controller.rb`: borrar el método privado `group_of` y usar `@workshop.group_of(current_user)` en `create`.
- `app/controllers/workshop_proposals_controller.rb`: lo mismo.

- [ ] **Step 5: Escribir el controller**

Crear `app/controllers/workshop_rooms_controller.rb`:

```ruby
# frozen_string_literal: true

# La sala de UN desafío del taller: la pantalla donde la mesa trabaja.
#
# `workshops#show` es el selector —qué desafíos hay y de qué tratan— y esto es
# el trabajo. Antes las dos cosas vivían en la misma pantalla, con un
# formulario por desafío apilado y sin nada que dijera de qué trataba cada uno.
class WorkshopRoomsController < ApplicationController
  def show
    # `policy_scope(...).find_by!` y no `Workshop.find_by!`: lo que no se ve da
    # 404 y no 403, que sería un oráculo de existencia.
    @workshop = policy_scope(Workshop).find_by!(id: params[:workshop_id])
    # El mismo predicado que los dos POST de la sala, no uno nuevo. Incluye a
    # quien administra sin estar sentado (`work?` da true por
    # `administers_any?`): entra, y la cara le dice que no tiene mesa.
    authorize @workshop, :work?

    # ANTES de leer el vínculo. El cierre es perezoso —nada se engancha en
    # `advance!`— y entrar a la sala es justo lo que hace que el taller se
    # entere de que el desafío avanzó. Sin esto la sala dibuja trabajo sobre un
    # módulo que ya cerró.
    Flow::Workshops::MaterializeClosures.new(@workshop).call

    @link = @workshop.workshop_challenges.find_by!(id: params[:id])
    @group = @workshop.group_of(current_user)
    @rooms = Flow::Workshops::Rooms.new(@workshop)
  end
end
```

- [ ] **Step 6: Escribir la vista**

Crear `app/views/workshop_rooms/show.html.haml`:

```haml
-# La sala de un desafío. El `case` sobre `room_state` tiene rama por defecto a
-# propósito: el vínculo que avanzó —`open` con su módulo ya `completed`— no
-# caía en ninguna y la sala salía EN BLANCO, sin un solo mensaje. Con `else`,
-# el estado que alguien agregue mañana se ve.
- content_for :title, @link.challenge.name

.page-head
  %div
    %p.breadcrumb
      -# Sin condición todavía: la vuelve condicional la tarea que introduce el
      -# redirect del taller, que es la dueña de esa pregunta.
      = link_to "Talleres", workshops_path
      = " › "
      = link_to @workshop.name, workshop_path(@workshop)
    %h1.page-title= @link.challenge.name

- case @link.room_state
- when :ideation
  = render "workshops/sala_idear", workshop: @workshop, link: @link, group: @group
- when :evolution
  = render "workshops/sala_evolucion", workshop: @workshop, link: @link, group: @group
- when :unopened
  .card
    .card-body
      %p.muted Este taller todavía no se abrió: la sala arranca cuando alguien lo abra.
- else
  .card
    .card-body
      %p.muted= @link.closed_reason.presence || "Esta sala ya no admite trabajo: el desafío avanzó de fase."
```

- [ ] **Step 7: Correr el spec nuevo y la suite del taller**

```bash
make spec-file FILE=spec/requests/workshop_room_spec.rb
make spec-file FILE=spec/requests/workshops_spec.rb
make spec-file FILE=spec/requests/workshop_sala_idear_spec.rb
make spec-file FILE=spec/requests/workshop_sala_evolucion_spec.rb
```

Esperado: los cuatro en verde. Los tres últimos siguen asertando sobre `workshops/show`, que en esta tarea no cambió.

- [ ] **Step 8: Commit**

```bash
git add config/routes.rb app/models/workshop.rb app/controllers/workshop_rooms_controller.rb \
        app/controllers/workshops_controller.rb app/controllers/workshop_ideas_controller.rb \
        app/controllers/workshop_proposals_controller.rb app/views/workshop_rooms/show.html.haml \
        spec/requests/workshop_room_spec.rb
git commit -m "$(cat <<'MSG'
La sala de un desafío es una pantalla propia

La ruta reusa el anidado que ya existía con `only: []`, así que los dos
POST no se mueven. Por ahora renderiza las mismas caras que la pantalla
del taller, que sigue apilándolas: el selector llega después y nada queda
roto en el medio.

«Mi mesa en este taller» estaba escrito tres veces y la sala habría sido
la cuarta: pasa a ser `Workshop#group_of`.

Claude-Session: https://claude.ai/code/session_01KajVAKcwc9zMj6qGWVYai2
MSG
)"
```

---

### Task 3: `workshops/show` pasa a ser selector, con redirect

**Files:**
- Modify: `app/views/workshops/show.html.haml`
- Create: `app/views/workshops/_room_picker.html.haml`
- Modify: `app/controllers/workshops_controller.rb` (`show`)
- Test: `spec/requests/workshops_spec.rb` (agregar), `spec/requests/workshop_room_spec.rb` (agregar)

**Interfaces:**
- Consumes: `Flow::Workshops::Rooms#links`, `#workable`, `#only_room`, `#redirects?(can_assemble:)` (Task 1); `workshop_sala_path` (Task 2).
- Produces: `@rooms` en `workshops#show`, consumido por `workshops/_room_picker`.

- [ ] **Step 1: Mover los dos spec de sala a la URL de la sala**

Esta tarea es la que rompe las aserciones de pantalla de `workshop_sala_idear_spec.rb` y `workshop_sala_evolucion_spec.rb`: sacarle los formularios a `workshops/show` las deja mirando una pantalla que ya no los tiene. Es su dueña, así que las mueve ella y no deja la suite en rojo para la tarea siguiente —si no, el revisor de esta tarea no puede distinguir el rojo esperado de uno nuevo—.

En los DOS archivos, todo `get workshop_path(setup[:workshop])` / `get workshop_path(scene[:workshop])` pasa a `get workshop_sala_path(…, …[:link])`. Son **todos**, incluido el del `describe "un gestor convocado a la mesa"` del spec de idear, que está fuera del describe de la pantalla. Los `redirect_to(workshop_path(...))` de los rechazos NO se tocan acá: los controllers todavía redirigen al taller y los cambian las tareas que los tocan.

Y se **borra** del spec de idear el ejemplo «con dos salas de idear no repite ids de DOM»: existía porque dos salas compartían pantalla, y esta tarea abole exactamente eso.

```bash
make spec-file FILE=spec/requests/workshop_sala_idear_spec.rb
make spec-file FILE=spec/requests/workshop_sala_evolucion_spec.rb
```

Esperado: los dos en verde. La sala todavía renderiza los mismos partials, así que apuntar a su URL alcanza.

- [ ] **Step 2: Escribir los tests que fallan**

Agregar a `spec/requests/workshops_spec.rb`, dentro del describe de más afuera:

```ruby
  describe "el selector de salas" do
    let!(:ana) do
      without_tenant do
        u = create(:user, email: "ana-selector@test.dev")
        create(:membership, :participant, company: company, user: u)
        u
      end
    end

    def taller_con(kinds, brief: "De qué trata este desafío.")
      as_company(company) do
        workshop = create(:workshop, status: "open")
        group = create(:workshop_group, workshop: workshop)
        create(:workshop_group_member, workshop_group: group, user: ana)
        links = kinds.map do |kind|
          challenge = create(:challenge, brief: brief)
          step = create(:challenge_step, challenge: challenge, kind: kind, status: "active")
          create(:form_field, challenge_step: step, label: "Resumen", field_type: "text")
          create(:workshop_challenge, workshop: workshop, challenge: challenge, challenge_step: step)
        end
        { workshop: workshop, links: links }
      end
    end

    it "con dos salas lista cada desafío con su brief y no apila formularios" do
      escena = taller_con(%w[ideation ideation])
      sign_in(ana, company: company)
      get workshop_path(escena[:workshop])

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("De qué trata este desafío.")
      escena[:links].each do |link|
        expect(response.body).to include(workshop_sala_path(escena[:workshop], link))
      end
      # El formulario vive en la sala, no acá: era lo que hacía de la pantalla
      # del taller una pila de formularios sin contexto.
      expect(response.body).not_to include(%(name="payload[))
    end

    it "con una sola sala redirige a ella" do
      escena = taller_con(%w[ideation])
      sign_in(ana, company: company)
      get workshop_path(escena[:workshop])

      expect(response).to redirect_to(workshop_sala_path(escena[:workshop], escena[:links].first))
    end

    it "a quien administra no lo redirige: ahí está el bloque de armado" do
      escena = taller_con(%w[ideation])
      admin = without_tenant do
        u = create(:user, email: "admin-selector@test.dev")
        create(:membership, :admin, company: company, user: u)
        u
      end
      sign_in(admin, company: company)
      get workshop_path(escena[:workshop])

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Abrir taller").or include("Cerrar taller")
    end

    # Review Focus 2: a quien no tiene mesa el selector se le SIRVE igual.
    #
    # Lo que este ejemplo NO puede aislar: que con dos salas no se redirija.
    # Quien no tiene mesa y aun así ve el taller sólo puede ser quien
    # administra o un gestor, y para ellos `can_assemble` ya es true. La
    # discriminación de «con dos salas no redirige» la aporta el primer
    # ejemplo de este describe, con un participante CON mesa.
    it "con dos salas y sin mesa se sirve el selector" do
      escena = taller_con(%w[ideation evolution])
      sin_mesa = without_tenant do
        u = create(:user, email: "sin-mesa@test.dev")
        create(:membership, :admin, company: company, user: u)
        u
      end
      sign_in(sin_mesa, company: company)
      get workshop_path(escena[:workshop])

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(workshop_sala_path(escena[:workshop], escena[:links].first))
    end

    it "el vínculo no trabajable se lista con su motivo y sin «Entrar»" do
      escena = taller_con(%w[ideation])
      as_company(company) do
        escena[:links].first.update!(status: "closed", closed_at: Time.current,
                                     closed_reason: "El desafío está en Evaluación.")
      end
      sign_in(ana, company: company)
      get workshop_path(escena[:workshop])

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("El desafío está en Evaluación.")
      expect(response.body).not_to include(workshop_sala_path(escena[:workshop], escena[:links].first))
    end
  end
```

Agregar a `spec/requests/workshop_room_spec.rb`:

```ruby
  # El breadcrumb pregunta lo mismo que el redirect. Si divergen, el taller
  # manda a la sala y la sala ofrece volver al taller: bucle.
  describe "el breadcrumb" do
    it "con una sola sala no ofrece volver al taller, que redirigiría de nuevo" do
      sign_in(ana, company: company)
      get workshop_sala_path(scene[:workshop], scene[:link])

      expect(response.body).not_to include(%(href="#{workshop_path(scene[:workshop])}"))
      expect(response.body).to include(%(href="#{workshops_path}"))
    end

    it "con dos salas sí ofrece volver al taller" do
      as_company(company) do
        otro = create(:challenge)
        paso = create(:challenge_step, challenge: otro, kind: "ideation", status: "active")
        create(:workshop_challenge, workshop: scene[:workshop], challenge: otro, challenge_step: paso)
      end
      sign_in(ana, company: company)
      get workshop_sala_path(scene[:workshop], scene[:link])

      expect(response.body).to include(%(href="#{workshop_path(scene[:workshop])}"))
    end
  end
```

- [ ] **Step 3: Correrlos y verlos fallar**

```bash
make spec-file FILE=spec/requests/workshops_spec.rb
make spec-file FILE=spec/requests/workshop_room_spec.rb
```

Esperado: el selector falla porque `workshops/show` todavía apila formularios (`name="payload[` presente) y no redirige; el breadcrumb falla porque hoy siempre linkea al taller.

- [ ] **Step 4: Escribir el selector**

Crear `app/views/workshops/_room_picker.html.haml`:

```haml
-# Qué desafíos tiene este taller y de qué trata cada uno. El formulario vive
-# en la sala: apilar uno por desafío era pedirle a la mesa que eligiera
-# leyendo nombres.
-#
-# Los vínculos NO trabajables se listan con su motivo y sin botón. No
-# desaparecen: una sala escondida no se distingue de una que nunca existió, y
-# ese silencio es el defecto que `room_state` se escribió para cerrar.
.card
  .card-body
    .section-head
      %h2.section-title Salas
    - if rooms.links.empty?
      %p.muted Este taller todavía no tiene desafíos.
    - else
      %ul.field-list
        - rooms.links.each do |link|
          %li.field-list__item
            %div
              %strong= link.challenge.name
              - if link.challenge.brief.present?
                %p.muted= truncate(link.challenge.brief, length: 180)
              - case link.room_state
              - when :unopened
                %p.field-hint Este taller todavía no se abrió.
              - when :ideation, :evolution
                -# sin nota: el botón ya dice qué hacer
              - else
                %p.field-hint= link.closed_reason.presence || "Esta sala ya no admite trabajo: el desafío avanzó de fase."
            - if WorkshopChallenge::WORKABLE_KINDS.include?(link.room_state.to_s)
              .assignment-row__actions
                = link_to "Entrar", workshop_sala_path(workshop, link), class: "btn btn-ghost btn-sm"
```

- [ ] **Step 5: Reemplazar el cuerpo de `workshops/show`**

En `app/views/workshops/show.html.haml`, reemplazar el bloque `- if can_work` (el `@links.each` con el `case`) por el selector:

```haml
- if can_work
  = render "workshops/room_picker", workshop: @workshop, rooms: @rooms
```

El resto de la pantalla (el `.card` del encabezado y el `- if can_assemble` con `workshops/assembly`) no se toca.

- [ ] **Step 6: Redirigir cuando hay una sola sala**

En `app/controllers/workshops_controller.rb#show`, después de `MaterializeClosures` y antes de leer `@links`:

```ruby
  def show
    authorize @workshop, :show?
    # El cierre del vínculo es perezoso: nada se engancha en `advance!`, y
    # entrar acá es lo que hace que el taller se entere de que el desafío
    # avanzó. Va ANTES de leer las salas, para que el selector vea lo cerrado.
    Flow::Workshops::MaterializeClosures.new(@workshop).call
    @rooms = Flow::Workshops::Rooms.new(@workshop)

    # Con UNA sola sala trabajable y sin bloque de armado, esta pantalla no
    # tiene nada que ofrecer: se va derecho a la sala. Quien administra nunca
    # se redirige. La condición vive en `Rooms` porque el breadcrumb de la sala
    # pregunta lo mismo: si divergieran, volver al taller sería un bucle.
    if @rooms.redirects?(can_assemble: policy(@workshop).update?)
      return redirect_to workshop_sala_path(@workshop, @rooms.only_room)
    end

    @links = @rooms.links
    @groups = @workshop.workshop_groups.includes(workshop_group_members: :user)
    @my_group = @workshop.group_of(current_user)
  end
```

- [ ] **Step 7: Escribir el breadcrumb condicional**

La Task 2 lo dejó sin condición a propósito: la condición es de esta tarea, que es la que introduce el redirect. En `app/views/workshop_rooms/show.html.haml`:

```haml
    %p.breadcrumb
      -# La misma pregunta que hace el redirect de `workshops#show`: si el
      -# taller manda acá, ofrecer «volver al taller» sería un bucle. Por eso
      -# la pregunta vive UNA vez, en `Rooms`.
      = link_to "Talleres", workshops_path
      - unless @rooms.redirects?(can_assemble: policy(@workshop).update?)
        = " › "
        = link_to @workshop.name, workshop_path(@workshop)
```

- [ ] **Step 8: Correr y verlos pasar**

```bash
make spec-file FILE=spec/requests/workshops_spec.rb
make spec-file FILE=spec/requests/workshop_room_spec.rb
```

Esperado: los cuatro en verde — los dos de arriba y además los dos spec de sala, que el Step 1 ya movió a la URL de la sala:

```bash
make spec-file FILE=spec/requests/workshop_sala_idear_spec.rb
make spec-file FILE=spec/requests/workshop_sala_evolucion_spec.rb
```

Ninguna tarea deja la suite en rojo.

- [ ] **Step 9: Commit**

```bash
git add app/views/workshops/show.html.haml app/views/workshops/_room_picker.html.haml \
        app/views/workshop_rooms/show.html.haml app/controllers/workshops_controller.rb \
        spec/requests/workshops_spec.rb spec/requests/workshop_room_spec.rb \
        spec/requests/workshop_sala_idear_spec.rb spec/requests/workshop_sala_evolucion_spec.rb
git commit -m "$(cat <<'MSG'
La pantalla del taller elige desafío, no apila formularios

Cada desafío se lista con su brief y un «Entrar»; el formulario vive en
la sala. Con una sola sala trabajable y sin bloque de armado, el taller
redirige derecho a ella.

El breadcrumb de la sala pregunta lo mismo que el redirect: ofrecer
«volver al taller» ahí donde el taller redirige sería un bucle.

Claude-Session: https://claude.ai/code/session_01KajVAKcwc9zMj6qGWVYai2
MSG
)"
```

---

### Task 4: la sala de idear, con lo que la mesa ya creó

**Files:**
- Create: `app/views/workshop_rooms/_ideation.html.haml`
- Delete: `app/views/workshops/_sala_idear.html.haml`
- Modify: `app/views/workshop_rooms/show.html.haml` (apuntar al partial nuevo)
- Modify: `app/controllers/workshop_rooms_controller.rb` (cargar `@mesa_ideas`)
- Modify: `app/controllers/workshop_ideas_controller.rb` (redirigir a la sala)
- Test: `spec/requests/workshop_sala_idear_spec.rb`

**Interfaces:**
- Consumes: `@workshop`, `@link`, `@group` (Task 2); `policy_scope(Idea)`; `IdeaPolicy#create?`; `chip_de_estado`, `chip("version")`; `t("flow.idea_statuses.…")`, `t("flow.contributor_roles.…")`.
- Produces: `@mesa_ideas` (Array de `Idea`, con `author`, `current_version` e `idea_contributors.user` precargados), consumido por `workshop_rooms/_ideation`.

- [ ] **Step 1: Escribir los tests que fallan**

En `spec/requests/workshop_sala_idear_spec.rb` las URLs ya apuntan a la sala (lo hizo la Task 3). Acá queda: renombrar el `describe "la pantalla del taller"` a `describe "la sala"`, y pasar los `redirect_to(workshop_path(...))` de los rechazos a `workshop_sala_path(setup[:workshop], setup[:link])` — son los redirects de los controllers, que esta tarea cambia.

Agregar estos ejemplos:

```ruby
  describe "lo que ya creó la mesa" do
    def sala = get workshop_sala_path(setup[:workshop], setup[:link])

    it "lista el borrador que la mesa creó, con estado y versión" do
      sign_in(ana, company: company)
      post_draft("Idea de la mesa")
      # `ideas` NO tiene columna `title`: `Idea#title` sale de la versión
      # vigente y sin versión es «(sin título)» para TODAS. Se lee del registro
      # en vez de escribirlo a mano, así la aserción no depende de cómo se
      # derive.
      idea = as_company(company) { Idea.order(:created_at).last }

      sala
      expect(response.body).to include(idea.title)
      expect(response.body).to include(challenge_idea_path(setup[:challenge], idea))
      expect(response.body).to include("Borrador")
    end

    # Lo ve cada integrante porque el borrador nace con la mesa entera como
    # `idea_contributors`: la visibilidad la resuelve `IdeaPolicy::Scope`, no
    # una excepción nueva.
    it "lo ve también el resto de la mesa" do
      sign_in(ana, company: company)
      post_draft("Idea compartida")
      idea = as_company(company) { Idea.order(:created_at).last }

      sign_in(beto, company: company)
      sala
      expect(response.body).to include(challenge_idea_path(setup[:challenge], idea))
      expect(response.body).to include(idea.title)
    end

    # La razón por la que la consulta NO sale de `workable_ideas`: su comentario
    # documenta que exponer a toda la mesa el borrador que alguien creó AFUERA
    # fue una fuga ya arreglada. `policy_scope(Idea)` la hace imposible.
    it "no muestra el borrador que un compañero creó fuera del taller" do
      ajena = as_company(company) do
        idea = create(:idea, challenge: setup[:challenge], author: beto, status: "draft")
        # Con título propio: sin versión publicada toda idea se llama
        # «(sin título)», y una aserción sobre ese texto no distingue nada.
        result = Flow::Ideas::PublishVersion.new(
          idea, payload: {}, author: beto, title: "Borrador privado de Beto"
        ).call
        expect(result).to be_ok
        idea
      end
      sign_in(ana, company: company)
      sala

      expect(response.body).not_to include("Borrador privado de Beto")
      expect(response.body).not_to include(challenge_idea_path(setup[:challenge], ajena))
    end

    it "sin nada creado dice que no hay nada y ofrece el formulario igual" do
      sign_in(ana, company: company)
      sala

      expect(response.body).to include("Crear un borrador")
      expect(response.body).to include(%(name="payload[#{setup[:field].key}]"))
    end

    it "con algo creado el formulario dice «Crear otro borrador»" do
      sign_in(ana, company: company)
      post_draft
      sala

      expect(response.body).to include("Crear otro borrador")
    end
  end

  it "crear el borrador vuelve a la sala, no al taller: ahí se ve lo que se creó" do
    sign_in(ana, company: company)
    post_draft

    expect(response).to redirect_to(workshop_sala_path(setup[:workshop], setup[:link]))
  end
```

- [ ] **Step 2: Correrlos y verlos fallar**

```bash
make spec-file FILE=spec/requests/workshop_sala_idear_spec.rb
```

Esperado: los nuevos fallan (no hay lista de borradores, el redirect va al taller) y los movidos pasan ya, porque la Task 2 dejó la sala renderizando `workshops/_sala_idear`.

- [ ] **Step 3: Cargar las ideas en el controller**

En `app/controllers/workshop_rooms_controller.rb#show`, al final:

```ruby
    # Las ideas de la mesa, según la cara. En idear es lo que la mesa YA creó;
    # en evolución llega en la Task 5.
    #
    # `policy_scope(Idea)` y NO `group.workable_ideas`, por dos razones: ese
    # método filtra con `Idea.alive` (o sea `active`) y no trae borradores, y su
    # comentario documenta que exponer a toda la mesa el borrador que un
    # integrante creó AFUERA del taller fue una fuga ya arreglada. Con
    # `policy_scope` la fuga es imposible: el borrador creado en la sala lleva a
    # la mesa entera como `idea_contributors`, así que cada integrante lo ve por
    # `IdeaPolicy::Scope`, y el privado de alguien sigue siendo sólo suyo.
    #
    # Va en el CONTROLLER a propósito: `spec/lint/ideas_por_policy_scope_spec.rb`
    # sólo mira controllers. Escondida en un presenter no la ve nadie.
    @mesa_ideas =
      if @link.room_state == :ideation
        policy_scope(Idea).where(challenge_id: @link.challenge_id, status: %w[draft active])
                          .includes(:author, :current_version, idea_contributors: :user)
                          .order(created_at: :desc).to_a
      else
        []
      end
```

- [ ] **Step 4: Escribir el partial**

Crear `app/views/workshop_rooms/_ideation.html.haml`:

```haml
-# La sala de idear: lo que la mesa ya creó, y el formulario para uno nuevo.
-# Se renderiza desde `workshop_rooms/show`, detrás del `work?` del controller;
-# acá no se vuelve a preguntar el permiso del taller.
-#
-# UNA variable, la misma pregunta que hace el controller del POST: quien no
-# puede firmar una idea (el gestor, por conflicto de interés) no recibe un
-# formulario que rebotaría en un 403.
- puede_crear = policy(link.challenge.ideas.new).create?

- if group.nil?
  -# Sin mesa el POST rechaza (`reject_without_group`): ofrecer el formulario
  -# igual sería un control que no responde.
  .card
    .card-body
      %p.muted Sólo se crea un borrador desde una mesa: no estás en ninguna de este taller.
- elsif group.arrival?
  -# Misma pregunta (`arrival?`) que las otras tres puertas, para que no puedan
  -# divergir.
  .card
    .card-body
      %p.muted Tu mesa todavía no se armó: en cuanto se reparta, acá aparece el formulario.
- elsif !puede_crear
  .card
    .card-body
      %p.muted Podés acompañar a la mesa, pero no proponer ideas propias: es conflicto de interés.
- else
  - if mesa_ideas.any?
    .card
      .card-body
        .section-head
          %h2.section-title Lo que ya creó la mesa
        %ul.field-list
          - mesa_ideas.each do |idea|
            %li.field-list__item
              %div
                = link_to idea.title, challenge_idea_path(link.challenge, idea)
                %p.muted
                  %span{ class: chip_de_estado(idea.draft? ? "pending" : "active") }
                    = t("flow.idea_statuses.#{idea.status}")
                  - if idea.current_version
                    %span{ class: chip("version") }= idea.current_version.label
              %ul.people-list
                %li.people-list__item
                  %span.people-list__name= idea.author.name
                  %span.people-list__role creó la idea
                - idea.idea_contributors.each do |contributor|
                  %li.people-list__item
                    %span.people-list__name= contributor.user.name
                    %span.people-list__role= t("flow.contributor_roles.#{contributor.role}")

  .card
    .card-body
      .section-head
        %h2.section-title= mesa_ideas.any? ? "Crear otro borrador" : "Crear un borrador"
      - mates = group.members.reject { |person| person.id == current_user.id }
      - if mates.any?
        %p.muted= "El borrador se comparte con #{mates.map(&:name).to_sentence}: es de la mesa, no solo tuyo."
      = form_with url: workshop_sala_ideas_path(workshop, link), multipart: true do
        -# Sin `id_prefix`: existía porque dos salas se renderizaban en la misma
        -# pantalla y las dos emitían `id="payload_<clave>"`, así que el
        -# `<label for>` de la segunda enfocaba el campo de la primera. Con una
        -# sala por pantalla la colisión no puede existir.
        = render "ideas/form_fields", fields: link.challenge_step.form_fields, payload: {}
        .form-actions
          = submit_tag "Crear borrador", class: "btn btn-primary"
```

- [ ] **Step 5: Apuntar la vista al partial nuevo y borrar el viejo**

En `app/views/workshop_rooms/show.html.haml`:

```haml
- when :ideation
  = render "workshop_rooms/ideation", workshop: @workshop, link: @link, group: @group,
                                      mesa_ideas: @mesa_ideas
```

```bash
git rm app/views/workshops/_sala_idear.html.haml
```

- [ ] **Step 6: Redirigir el POST a la sala**

En `app/controllers/workshop_ideas_controller.rb`, reemplazar los cinco `workshop_path(@workshop)` por `workshop_sala_path(@workshop, @link)`, y sumar el comentario sobre el `create` exitoso:

```ruby
    if result.ok?
      # A la SALA y no al taller: la sala es donde se ve lo que la mesa acaba
      # de crear. Volviendo al taller el borrador no aparecía en ninguna
      # pantalla, así que la mesa no sabía que ya lo había creado y lo creaba
      # de nuevo.
      redirect_to workshop_sala_path(@workshop, @link), notice: "Borrador creado en la sala."
    else
      redirect_to workshop_sala_path(@workshop, @link), alert: result.error_sentence
    end
```

Los rechazos (`reject_room`, `reject_without_group`, `reject_arrival`) también van a la sala: es la pantalla que muestra cada uno de esos mensajes.

- [ ] **Step 7: Correr y verlos pasar**

```bash
make spec-file FILE=spec/requests/workshop_sala_idear_spec.rb
make spec-file FILE=spec/requests/workshop_room_spec.rb
make spec-file FILE=spec/lint/ideas_por_policy_scope_spec.rb
```

Esperado: los tres en verde. El de lint importa: la consulta nueva de ideas tiene que estar dentro de un `policy_scope(...)`.

- [ ] **Step 8: Commit**

El `git rm` del Step 5 ya dejó preparada la baja del partial viejo.

```bash
git add -A app/views/workshop_rooms app/views/workshops \
        app/controllers/workshop_rooms_controller.rb \
        app/controllers/workshop_ideas_controller.rb spec/requests/workshop_sala_idear_spec.rb
git commit -m "$(cat <<'MSG'
La sala de idear muestra lo que la mesa ya creó

Crear volvía al taller y el borrador no aparecía en ninguna pantalla, así
que la mesa no sabía que ya lo había creado. Ahora vuelve a la sala, que
lista lo creado con su estado, su versión y quiénes participan.

La lista sale de `policy_scope(Idea)` y no de `workable_ideas`: ese método
no trae borradores, y su comentario documenta que exponer a la mesa el
borrador que alguien creó afuera fue una fuga ya arreglada.

Se cae el `id_prefix`: existía porque dos salas compartían pantalla.

Claude-Session: https://claude.ai/code/session_01KajVAKcwc9zMj6qGWVYai2
MSG
)"
```

---

### Task 5: la sala de evolución, con selector de idea y su contenido

**Files:**
- Create: `app/views/workshop_rooms/_evolution.html.haml`
- Delete: `app/views/workshops/_sala_evolucion.html.haml`
- Modify: `app/views/workshop_rooms/show.html.haml`
- Modify: `app/controllers/workshop_rooms_controller.rb`
- Modify: `app/controllers/workshop_proposals_controller.rb` (redirigir a la sala)
- Test: `spec/requests/workshop_sala_evolucion_spec.rb`

**Interfaces:**
- Consumes: `WorkshopGroup#workable_ideas(challenge)`; `WorkshopProposal#actionable?`, `#status`; `Flow::Pipeline#ideation_step`; `@group`, `@link` (Task 2).
- Produces: `@workable_ideas` (Array de `Idea`), `@selected_idea` (`Idea` o `nil`), `@mesa_proposals` (Array de `WorkshopProposal` de esta mesa sobre `@selected_idea`), consumidos por `workshop_rooms/_evolution`.

- [ ] **Step 1: Escribir los tests que fallan**

En `spec/requests/workshop_sala_evolucion_spec.rb` las URLs ya apuntan a la sala (lo hizo la Task 3). Acá queda: renombrar el `describe "la pantalla del taller"` a `describe "la sala"`, pasar los `redirect_to(workshop_path(...))` a `workshop_sala_path(scene[:workshop], scene[:link])`, y reescribir el ejemplo «precarga cada formulario … y no repite ids de DOM»: ahora hay UN formulario, el de la idea seleccionada.

Agregar:

```ruby
  describe "el selector de ideas" do
    def sala(params = {}) = get workshop_sala_path(scene[:workshop], scene[:link], params)

    # Por la URL de selección y NO por el título: `ideas` no tiene columna
    # `title` —sale de la versión vigente— y en esta escena ninguna idea
    # publicó versión, así que las cinco se llaman «(sin título)» y una
    # aserción sobre el texto no distinguiría la propia de la ajena.
    def link_a(idea) = workshop_sala_path(scene[:workshop], scene[:link], idea: idea.id)

    it "lista las ideas de la mesa con la participación de cada uno, y ninguna ajena" do
      sign_in(beto, company: company)
      sala

      expect(response.body).to include(link_a(scene[:ana_idea]))
      expect(response.body).to include(link_a(scene[:dani_idea]))
      expect(response.body).not_to include(link_a(scene[:carla_idea]))
      expect(response.body).not_to include(link_a(scene[:ana_eliminada]))
      expect(response.body).not_to include(link_a(scene[:beto_borrador]))
      # Quién la creó y quién colabora: es lo que deja ver a la mesa por qué
      # la idea de dani entra (beto colabora en ella).
      expect(response.body).to include("creó la idea")
      expect(response.body).to include(t("flow.contributor_roles.contributor"))
      expect(response.body).to include(beto.name)
    end

    it "con dos ideas no preselecciona ninguna y no ofrece formulario todavía" do
      sign_in(beto, company: company)
      sala

      expect(response.body).not_to include(%(name="payload[#{scene[:field].key}]"))
    end

    it "al elegir una idea muestra su contenido y un solo formulario" do
      as_company(company) do
        result = Flow::Ideas::PublishVersion.new(
          scene[:ana_idea], payload: { scene[:field].key => "Texto de ana" }, author: ana,
                            source_step: scene[:round], change_note: "Inicial"
        ).call
        expect(result).to be_ok
      end
      sign_in(beto, company: company)
      sala(idea: scene[:ana_idea].id)

      expect(response.body).to include("Texto de ana")
      expect(response.body).to include(%(value="#{scene[:ana_idea].id}"))
      expect(response.body.scan(/value="Proponer"/).size).to eq(1)
    end

    # Review Focus 1. Fuera del conjunto trabajable, `nil`: igual que un id
    # inexistente, así que no confirma que exista. Ni 403 ni 500.
    it "un id que no es de la mesa queda sin selección, no en 403" do
      sign_in(beto, company: company)
      sala(idea: scene[:carla_idea].id)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(%(name="payload[#{scene[:field].key}]"))
    end

    it "un id inventado tampoco revienta" do
      sign_in(beto, company: company)
      sala(idea: SecureRandom.uuid)

      expect(response).to have_http_status(:ok)
    end

    it "con una sola idea trabajable la preselecciona" do
      as_company(company) { scene[:dani_idea].update!(status: "eliminated") }
      sign_in(beto, company: company)
      sala

      expect(response.body).to include(%(value="#{scene[:ana_idea].id}"))
      expect(response.body).to include(%(name="payload[#{scene[:field].key}]"))
    end

    # Review Focus 5: una idea sin versión publicada. El contenido se dibuja
    # con `—` por campo y no revienta sobre `nil.payload`.
    it "una idea sin versión vigente muestra el contenido vacío, sin 500" do
      as_company(company) { scene[:dani_idea].update!(status: "eliminated") }
      sign_in(beto, company: company)
      sala

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("—")
    end
  end

  describe "lo que esta mesa propuso" do
    it "lista la propuesta pendiente de la mesa sobre la idea elegida" do
      # Nada de títulos acá tampoco: lo que se mide es el bloque y el chip.
      sign_in(beto, company: company)
      propose(scene[:ana_idea])

      get workshop_sala_path(scene[:workshop], scene[:link], idea: scene[:ana_idea].id)
      expect(response.body).to include("Lo que esta mesa propuso")
      expect(response.body).to include(t("flow.workshop_proposal_statuses.pending"))
    end

    it "la propuesta vencida dice que la ronda cerró" do
      sign_in(beto, company: company)
      propose(scene[:ana_idea])
      as_company(company) { scene[:round].update!(status: "completed") }

      get workshop_sala_path(scene[:workshop], scene[:link], idea: scene[:ana_idea].id)
      expect(response.body).to include("venció")
    end

    it "no lista la propuesta de otra mesa" do
      otra = as_company(company) do
        mesa = create(:workshop_group, workshop: scene[:workshop], name: "Mesa 9")
        WorkshopProposal.create!(workshop_group: mesa, idea: scene[:ana_idea],
                                 challenge_step: scene[:round], payload: { scene[:field].key => "De otra mesa" },
                                 status: "pending")
      end
      sign_in(beto, company: company)
      get workshop_sala_path(scene[:workshop], scene[:link], idea: scene[:ana_idea].id)

      expect(response.body).not_to include("De otra mesa")
      expect(otra).to be_pending
    end
  end

  it "proponer vuelve a la sala con la idea elegida" do
    sign_in(beto, company: company)
    propose(scene[:ana_idea])

    expect(response).to redirect_to(
      workshop_sala_path(scene[:workshop], scene[:link], idea: scene[:ana_idea].id)
    )
  end
```

- [ ] **Step 2: Sumar las etiquetas de estado de propuesta**

`flow.workshop_proposal_statuses` no existe todavía. Sin la clave, el estado sale en inglés por el fallback. En `config/locales/es.yml`, al lado de `flow.workshop_statuses`:

```yaml
    workshop_proposal_statuses:
      pending: "Pendiente"
      accepted: "Aceptada"
      rejected: "Descartada"
```

- [ ] **Step 3: Correrlos y verlos fallar**

```bash
make spec-file FILE=spec/requests/workshop_sala_evolucion_spec.rb
```

Esperado: fallan los del selector (hoy se renderiza un formulario por idea, sin selector ni contenido) y el del redirect.

- [ ] **Step 4: Cargar las ideas y la selección en el controller**

En `app/controllers/workshop_rooms_controller.rb#show`, reemplazar el bloque de `@mesa_ideas` por un despacho por cara:

```ruby
    case @link.room_state
    when :ideation then load_ideation
    when :evolution then load_evolution
    end
  end

  private

  # Ver comentario largo en la Task 4: `policy_scope(Idea)` y no
  # `workable_ideas`, porque ese método no trae borradores y la fuga que
  # documenta su comentario sería fácil de reintroducir acá.
  def load_ideation
    @mesa_ideas = policy_scope(Idea).where(challenge_id: @link.challenge_id, status: %w[draft active])
                                    .includes(:author, :current_version, idea_contributors: :user)
                                    .order(created_at: :desc).to_a
  end

  # Acá SÍ es `workable_ideas`: es el método que existe para esto —la unión
  # sobre los integrantes de la mesa— y ya excluye la mesa de llegada, lo
  # eliminado y lo retirado.
  def load_evolution
    @workable_ideas =
      if @group
        @group.workable_ideas(@link.challenge)
              .includes(:author, :current_version, idea_contributors: :user).to_a
      else
        []
      end

    # Fuera del conjunto trabajable es `nil`, igual que un id inexistente: no
    # confirma que exista. Se busca en el array ya cargado y no con otra
    # consulta. Con una sola idea se preselecciona: es un DEFAULT, no un
    # redirect, así que no hay bucle posible.
    @selected_idea = @workable_ideas.detect { |idea| idea.id == params[:idea] }
    @selected_idea ||= @workable_ideas.first if @workable_ideas.one?

    @mesa_proposals =
      if @group && @selected_idea
        @group.workshop_proposals.where(idea_id: @selected_idea.id)
              .includes(:challenge_step).order(created_at: :desc).to_a
      else
        []
      end
  end
```

- [ ] **Step 5: Escribir el partial**

Crear `app/views/workshop_rooms/_evolution.html.haml`:

```haml
-# La sala de evolución: las ideas que la mesa puede trabajar, el contenido de
-# la elegida, el formulario de propuesta y lo que la mesa ya propuso.
-#
-# Los formularios son hermanos, nunca anidados: un `button_to` es un `<form>`
-# y uno dentro de otro es HTML inválido que el navegador aplana sin dejar
-# rastro en el DOM.
- ideation = link.challenge.pipeline.ideation_step
- all_fields = ideation ? ideation.form_fields.ordered.to_a : []
-# Un archivo no viaja en una propuesta: sólo campos de valor.
- fields = all_fields.reject { |field| field.field_type == "file" }
- file_fields = all_fields.select { |field| field.field_type == "file" }

- if group.nil?
  .card
    .card-body
      %p.muted Sólo se propone desde una mesa: no estás en ninguna de este taller.
- elsif group.arrival?
  .card
    .card-body
      %p.muted Tu mesa todavía no se armó: en cuanto se reparta, acá aparecen las ideas para proponer.
- elsif ideas.empty?
  .card
    .card-body.empty-state
      %h2 Ninguna idea para trabajar
      %p.muted Ninguna persona de tu mesa tiene ideas postuladas en este desafío todavía.
- else
  .card
    .card-body
      .section-head
        %h2.section-title Las ideas de tu mesa
      %p.muted Proponé cambios sobre ellas: quien es autor decide si los acepta.
      %ul.field-list
        - ideas.each do |idea|
          - elegida = selected && selected.id == idea.id
          %li.field-list__item
            %div
              - if elegida
                %strong= idea.title
              - else
                = link_to idea.title, workshop_sala_path(workshop, link, idea: idea.id)
              - if idea.current_version
                %span{ class: chip("version") }= idea.current_version.label
              %ul.people-list
                %li.people-list__item
                  %span.people-list__name= idea.author.name
                  %span.people-list__role creó la idea
                - idea.idea_contributors.each do |contributor|
                  %li.people-list__item
                    %span.people-list__name= contributor.user.name
                    %span.people-list__role= t("flow.contributor_roles.#{contributor.role}")

  - if selected
    .card
      .card-body
        .section-head
          %h2.section-title Contenido
        %p.muted= "Versión vigente: #{selected.current_version&.label || '—'}"
        %dl.answer-list
          - fields.each do |field|
            -# `selected.payload` puede ser `{}` cuando la idea no tiene
            -# versión publicada: se dibuja `—` y no se revienta.
            - value = selected.payload[field.key]
            %dt.answer-list__label= field.label
            %dd{ class: ("is-empty" if value.blank?) }
              = value.is_a?(Array) ? value.join(", ") : (value.presence || "—")

    - if file_fields.any?
      -# `alert` es display:grid con grid-auto-flow:column: todo dentro de UN
      -# `%div`, o los hijos se reparten en columnas.
      .alert.alert-soft.alert-warning
        - una = file_fields.size == 1
        %div= "#{una ? 'El campo de archivo' : 'Los campos de archivo'} #{file_fields.map(&:label).to_sentence} #{una ? 'no se propone' : 'no se proponen'} desde el taller, por eso #{una ? 'no está' : 'no están'} en el formulario."

    .card
      .card-body
        .section-head
          %h2.section-title Proponer cambios
        = form_with url: workshop_sala_proposals_path(workshop, link) do
          = hidden_field_tag :idea_id, selected.id
          = render "ideas/form_fields", fields: fields, payload: selected.payload
          .form-actions
            = submit_tag "Proponer", class: "btn btn-primary"

    - if proposals.any?
      .card
        .card-body
          .section-head
            %h2.section-title Lo que esta mesa propuso
          %p.muted Aceptarla o descartarla es de quien es autor, en la ficha de la idea.
          %ul.field-list
            - proposals.each do |proposal|
              %li.field-list__item
                %div
                  %span{ class: chip_de_estado(proposal.pending? ? "pending" : (proposal.accepted? ? "completed" : "skipped")) }
                    = t("flow.workshop_proposal_statuses.#{proposal.status}")
                  %span.muted= " · #{l(proposal.created_at, format: :short)}"
                  - unless proposal.actionable?
                    - if proposal.pending?
                      %p.field-hint= "La ronda «#{proposal.challenge_step.name}» ya cerró: esta propuesta venció."
```

- [ ] **Step 6: Apuntar la vista y borrar el partial viejo**

En `app/views/workshop_rooms/show.html.haml`:

```haml
- when :evolution
  = render "workshop_rooms/evolution", workshop: @workshop, link: @link, group: @group,
                                       ideas: @workable_ideas, selected: @selected_idea,
                                       proposals: @mesa_proposals
```

```bash
git rm app/views/workshops/_sala_evolucion.html.haml
```

- [ ] **Step 7: Redirigir el POST a la sala, con la idea elegida**

En `app/controllers/workshop_proposals_controller.rb`, el éxito y los rechazos:

```ruby
    redirect_to workshop_sala_path(@workshop, @link, idea: idea.id),
                notice: "Propuesta enviada a quien es autor."
```

```ruby
  # A la sala y no al taller: es la pantalla que muestra cada uno de estos
  # mensajes, y volver al taller perdía la idea que la mesa estaba trabajando.
  def reject_room
    redirect_to workshop_sala_path(@workshop, @link),
                alert: "Esta sala ya no admite trabajo: el desafío avanzó de fase."
  end
```

Lo mismo en `reject_payload`, `reject_without_group` y `reject_arrival`.

- [ ] **Step 8: Correr y verlos pasar**

```bash
make spec-file FILE=spec/requests/workshop_sala_evolucion_spec.rb
make spec-file FILE=spec/requests/workshop_proposal_accept_spec.rb
make spec-file FILE=spec/lint/clases_interpoladas_spec.rb
make spec-file FILE=spec/lint/reglas_sin_elemento_spec.rb
```

Esperado: los cuatro en verde. Los dos de lint importan: el chip del estado de la propuesta se arma con `chip_de_estado` (nombre completo, nunca interpolado) y no se agregó ninguna clase sin regla.

- [ ] **Step 9: Commit**

```bash
git add app/views/workshop_rooms app/controllers/workshop_rooms_controller.rb \
        app/controllers/workshop_proposals_controller.rb config/locales/es.yml \
        spec/requests/workshop_sala_evolucion_spec.rb
git commit -a -m "$(cat <<'MSG'
La sala de evolución elige una idea y muestra su contenido

Antes era un formulario por idea apilado, sin el contenido de ninguna. Ahora
lista las ideas de la mesa con la participación de cada integrante, y al
elegir una muestra su contenido, un solo formulario, y lo que la mesa ya
propuso sobre ella.

La propuesta se mandaba y desaparecía —el redirect volvía al taller—, así
que la mesa proponía de nuevo sin saberlo.

Claude-Session: https://claude.ai/code/session_01KajVAKcwc9zMj6qGWVYai2
MSG
)"
```

---

### Task 6: la columna de referencia

**Files:**
- Create: `app/views/workshops/_my_group.html.haml`
- Create: `app/views/workshop_rooms/_referencia.html.haml`
- Modify: `app/views/workshop_rooms/show.html.haml` (llenar `content_for :referencia`)
- Modify: `app/views/workshops/show.html.haml` (sumar el panel de la mesa)
- Test: `spec/requests/workshop_room_spec.rb`

**Interfaces:**
- Consumes: `@group` (Task 2), `WorkshopGroup#workshop_group_members` (tienen `attended` y `user`), `Workshop#individual?`, `@link.challenge.brief`, `@link.challenge_step`.
- Produces: nada que otra tarea consuma.

- [ ] **Step 1: Escribir los tests que fallan**

Agregar a `spec/requests/workshop_room_spec.rb`:

```ruby
  describe "la columna de referencia" do
    it "muestra el brief del desafío y la mesa, en ese orden" do
      as_company(company) { create(:workshop_group_member, workshop_group: scene[:group], user: admin) }
      sign_in(ana, company: company)
      get workshop_sala_path(scene[:workshop], scene[:link])

      expect(response.body).to include("Bajar la merma de bodega sin tocar el stock de seguridad.")
      expect(response.body).to include(admin.name)
      # El orden es el que ya fijaron las pantallas de módulo: lo propio del
      # módulo, y después quién participa. Invertirlo enseñaría dos órdenes
      # para la misma columna.
      expect(response.body.index("El desafío")).to be < response.body.index("Tu mesa")
    end

    it "marca a quien mira y a quien no vino" do
      as_company(company) do
        seat = create(:workshop_group_member, workshop_group: scene[:group], user: admin)
        seat.update!(attended: false)
      end
      sign_in(ana, company: company)
      get workshop_sala_path(scene[:workshop], scene[:link])

      expect(response.body).to include("(vos)")
      expect(response.body).to include("ausente")
    end

    # Marcar presente y sacar gente son de quien administra, y viven en el
    # bloque de armado. En la referencia la mesa se LEE.
    it "no ofrece controles de asistencia" do
      sign_in(ana, company: company)
      get workshop_sala_path(scene[:workshop], scene[:link])

      expect(response.body).not_to include(attendance_workshop_path(scene[:workshop]))
      expect(response.body).not_to include(dismiss_workshop_path(scene[:workshop]))
    end

    # Review Focus 4: en modo individual la mesa es de una persona y NO hay
    # mesa de llegada (`arrival_group!` devuelve nil). El panel lo dice en vez
    # de desaparecer: un panel que no está no se distingue de uno roto.
    it "en modo individual dice que la mesa es de una persona" do
      escena = as_company(company) do
        w = create(:workshop, status: "open", mode: "individual")
        g = create(:workshop_group, workshop: w, name: "Mesa de Ana")
        create(:workshop_group_member, workshop_group: g, user: ana)
        create(:workshop_challenge, workshop: w, challenge: scene[:challenge], challenge_step: scene[:step])
      end
      sign_in(ana, company: company)
      get workshop_sala_path(escena.workshop, escena)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Trabajás sola o solo en este taller")
    end

    it "sin mesa la referencia lo dice y no finge una" do
      sign_in(admin, company: company)
      get workshop_sala_path(scene[:workshop], scene[:link])

      expect(response.body).to include("No estás en ninguna mesa de este taller")
    end
  end
```

- [ ] **Step 2: Correrlos y verlos fallar**

```bash
make spec-file FILE=spec/requests/workshop_room_spec.rb
```

Esperado: fallan los cinco — no hay columna de referencia todavía.

- [ ] **Step 3: Escribir el panel de la mesa**

Crear `app/views/workshops/_my_group.html.haml`:

```haml
-# Con quiénes estás sentado. Lo renderizan la sala (en la referencia) y la
-# pantalla del taller: UN markup, porque dos copias divergen y nadie se
-# entera.
-#
-# Sin controles: marcar presente y sacar gente son de quien administra y viven
-# en el bloque de armado. Acá la mesa se LEE.
.card
  .card-body
    .section-head
      %h2.section-title Tu mesa
    - if group.nil?
      %p.muted No estás en ninguna mesa de este taller.
    - elsif group.arrival?
      %p.muted Estás en la mesa de llegada: en cuanto alguien reparta, acá aparece tu mesa.
    - else
      %p.muted= group.name
      -# Los ASIENTOS y no `group.members`: `attended` vive en el asiento, y
      -# `members` es un `has_many through` que devuelve los `User`.
      %ul.field-list
        - group.workshop_group_members.each do |seat|
          %li.field-list__item
            %span
              = seat.user.name
              - if seat.user_id == current_user.id
                %span.muted= " (vos)"
              - unless seat.attended
                %span.muted= " · ausente"
      - if workshop.individual?
        %p.field-hint Trabajás sola o solo en este taller: en modo individual cada persona es su mesa.
```

- [ ] **Step 4: Escribir el panel del desafío**

Crear `app/views/workshop_rooms/_referencia.html.haml`:

```haml
-# Lo que se consulta y no se edita. Orden fijo: primero el desafío, después
-# quién participa — el mismo orden que ya fijaron las pantallas de módulo.
.card
  .card-body
    .section-head
      %h2.section-title El desafío
    %ul.field-list
      %li.field-list__item
        %span= link_to link.challenge.name, challenge_path(link.challenge)
      - if link.challenge_step
        %li.field-list__item
          %span= link.challenge_step.name
          -# `display_kind` y no `t(...)` a mano: la clave es `flow.kinds`, no
          -# `flow.step_kinds`, y el modelo ya es dueño de esa traducción
          -# (`ChallengeStep#display_kind`). Escribirla acá sería un segundo
          -# lugar que el día que la clave se mueva muestra el kind en inglés
          -# por el fallback `humanize`.
          %span.muted= " · #{link.challenge_step.display_kind}"
    - if link.challenge.brief.present?
      %p.muted= link.challenge.brief

= render "workshops/my_group", workshop: workshop, group: group
```

- [ ] **Step 5: Llenar la referencia en la sala**

Al final de `app/views/workshop_rooms/show.html.haml`:

```haml
-# El layout la lee DESPUÉS del `yield`: es el template el que la llena.
-# `.app-shell` se acomoda con `:has()`, así que la sala no declara layout. En
-# el taller no hay drawer —`desafio_del_shell` devuelve nil, porque el taller
-# no cuelga de un desafío—, así que la grilla queda centro + referencia.
- content_for :referencia do
  = render "workshop_rooms/referencia", workshop: @workshop, link: @link, group: @group
```

Y en `app/views/workshops/show.html.haml`, debajo del `- if can_work` del selector:

```haml
- if can_work
  = render "workshops/room_picker", workshop: @workshop, rooms: @rooms
  -# Quien cae en el selector ya ve con quién está sentado. Mismo partial que
  -# la referencia de la sala.
  = render "workshops/my_group", workshop: @workshop, group: @my_group
```

- [ ] **Step 6: Correr y verlos pasar**

```bash
make spec-file FILE=spec/requests/workshop_room_spec.rb
make spec-file FILE=spec/requests/workshops_spec.rb
```

Esperado: los dos en verde.

- [ ] **Step 7: Correr la suite completa**

```bash
make spec
```

Esperado: todo verde. Es la primera corrida completa de la rama: acá aparecen los specs de otras pantallas que tocaban las salas viejas.

- [ ] **Step 8: Commit**

```bash
git add app/views/workshops/_my_group.html.haml app/views/workshop_rooms/_referencia.html.haml \
        app/views/workshop_rooms/show.html.haml app/views/workshops/show.html.haml \
        spec/requests/workshop_room_spec.rb
git commit -a -m "$(cat <<'MSG'
La mesa y el brief del desafío, en la columna de referencia

Con quiénes estás sentado no se veía: el bloque que lista las mesas está
detrás del permiso de armar el taller, así que quien participa leía una
sola frase dentro del formulario. Y el brief del desafío no se mostraba en
ninguna parte: la mesa elegía leyendo nombres.

Orden fijo —el desafío y después quién participa—, el mismo que ya fijaron
las pantallas de módulo. Un solo partial para la mesa: lo usan la sala y
la pantalla del taller.

Claude-Session: https://claude.ai/code/session_01KajVAKcwc9zMj6qGWVYai2
MSG
)"
```

---

### Task 7: las capturas

`make screens` es la verificación end-to-end real. Cuatro capturas existentes miran la pantalla del taller y ahora el trabajo vive en la sala.

**Files:**
- Modify: `script/capture_screens.js` (bloque del taller, ~líneas 2672–2810; bloque del check-in, ~3000–3030)

**Interfaces:**
- Consumes: las rutas y pantallas de las Tasks 2–6.
- Produces: nada que otra tarea consuma.

- [ ] **Step 1: Compilar la hoja y el bundle**

```bash
make yarn-build
```

La hoja y el bundle viven **sólo** en el contenedor y están gitignoreados. Sin esto, `make screens` valida en verde una pantalla distinta de la que escribimos.

- [ ] **Step 2: Correr las capturas y ver qué se rompe**

```bash
make screens
```

Esperado: FALLA. La línea final dice «N errores de página» pero imprime el contador GLOBAL de fallas, así que no hay que buscar un error de página que no existe: lo que falla son las guardas `[TALLER]` de 25 y 26, y la de 30b.

- [ ] **Step 3: Sumar un helper que entra a la sala por link**

En `script/capture_screens.js`, junto a `goToWorkshop`:

```javascript
  // Entrar a la sala de un desafío POR LINK, desde el selector del taller.
  // Nunca `goto`: Turbo no dispara `DOMContentLoaded` al navegar por link, y un
  // `goto` monta la pantalla igual y esconde el bug.
  const goToRoom = async (challengeName) => {
    const entrar = page.locator('li.field-list__item', { hasText: challengeName })
      .locator('a:has-text("Entrar")');
    if (!(await entrar.count())) {
      failures++;
      console.error(`[TALLER] el selector del taller no ofrece entrar a «${challengeName}»`);
      return false;
    }
    await Promise.all([
      page.waitForURL(/\/workshops\/[^/]+\/salas\/[^/?]+/, { timeout: 15000 }),
      entrar.first().click()
    ]);
    // Señal determinista de que la sala pintó: su propio título.
    await page.waitForSelector(`h1.page-title:has-text("${challengeName}")`, { timeout: 10000 });
    return true;
  };
```

- [ ] **Step 4: Reescribir 25 y sumar la captura del selector**

Reemplazar el bloque de 25 por:

```javascript
  if (await goToWorkshop('Taller de mejora continua')) {
    // El selector: cada desafío con su brief y su «Entrar». Es la pantalla que
    // antes apilaba un formulario por desafío sin decir de qué trataba ninguno.
    const conBrief = await page.locator('li.field-list__item p.muted').count();
    if (!conBrief) {
      failures++;
      console.error('[TALLER] el selector del taller no muestra el brief de ningún desafío');
    }
    await capturar(page, '25a-taller-salas');

    // 25: la sala de idear ofrece el formulario del módulo de ideación y dice
    // con quién se comparte el borrador.
    if (await goToRoom('Ideas para la sala de descanso')) {
      if (!(await page.locator('form[action$="/ideas"] input[value="Crear borrador"]').count())) {
        failures++;
        console.error('[TALLER] la sala de idear no ofrece «Crear borrador»');
      }
      if (!(await page.locator('p.muted', { hasText: 'El borrador se comparte con Paula Participante' }).count())) {
        failures++;
        console.error('[TALLER] la sala de idear no dice con quién se comparte el borrador');
      }
      // La referencia: el brief y la mesa. Sin esto, la sala podría perder la
      // columna entera y las capturas seguirían en verde.
      if (!(await page.locator('.app-aside h2.section-title:has-text("Tu mesa")').count())) {
        failures++;
        console.error('[TALLER] la sala no dibuja «Tu mesa» en la referencia');
      }
      await capturar(page, '25-taller-sala-idear');
      await goToWorkshop('Taller de mejora continua');
    }

    // 28: el desafío que avanzó de fase se ve cerrado, y DICE POR QUÉ. Vive en
    // el selector, que lista los vínculos no trabajables con su motivo.
    const closedRoom = page.locator('li.field-list__item', {
      hasText: 'Ideas para el manual de seguridad'
    }).locator('p.field-hint');
    const closedReason = (await closedRoom.count()) ? await closedRoom.first().innerText() : '';
    if (!/El desafío está en Evaluación, y un taller sólo trabaja sobre idear o evolución/.test(closedReason)) {
      failures++;
      console.error(`[TALLER] el vínculo cerrado no dice su motivo: «${closedReason}»`);
    }
    await capturar(page, '28-taller-vinculo-cerrado');
  }
```

**Ojo:** el nombre del desafío de idear y el del cerrado salen del seed del recorrido. Confirmarlos antes de escribirlos:

```bash
docker compose exec -T app grep -n "taller-idear\|taller-avanzado" -B 3 -A 3 db/seeds.rb
```

- [ ] **Step 5: Reescribir 26 y sumar la captura de la idea elegida**

```javascript
  if (await goToWorkshop('Taller de evolución')) {
    if (await goToRoom('Evolución de las ideas del taller')) {
      // 26: el selector de ideas de la mesa. Las dos de Paula; la de Pedro no,
      // porque su autor no está en esta mesa.
      const filas = await page.locator('li.field-list__item a[href*="?idea="]').count();
      const elegidas = await page.locator('li.field-list__item strong').count();
      if (filas + elegidas !== 2) {
        failures++;
        console.error(`[TALLER] el selector de la sala de evolución lista ${filas + elegidas} ideas y se esperaban 2`);
      }
      // Y la participación de cada uno, que es lo que explica por qué una idea
      // ajena entra: alguien de la mesa colabora en ella.
      if (!(await page.locator('.people-list__role:has-text("creó la idea")').count())) {
        failures++;
        console.error('[TALLER] el selector no dice quién creó cada idea');
      }
      await capturar(page, '26-taller-sala-evolucion');

      // 26b: con una idea elegida, su contenido y UN formulario. Por link.
      const primera = page.locator('li.field-list__item a[href*="?idea="]').first();
      if (await primera.count()) {
        await Promise.all([
          page.waitForURL(/\?idea=/, { timeout: 15000 }),
          primera.click()
        ]);
        await page.waitForSelector('h2.section-title:has-text("Contenido")', { timeout: 10000 });
        const forms = await page.locator('form[action$="/proposals"] input[value="Proponer"]').count();
        if (forms !== 1) {
          failures++;
          console.error(`[TALLER] con una idea elegida hay ${forms} formularios de propuesta y se esperaba 1`);
        }
        await capturar(page, '26b-taller-idea-elegida');
      } else {
        failures++;
        console.error('[TALLER] ninguna idea del selector se puede elegir');
      }
      await goToWorkshop('Taller de evolución');
    }
```

El resto del bloque de evolución (27: la propuesta en la ficha de la idea) no cambia.

- [ ] **Step 6: Arreglar 30b**

El «Taller con check-in» tiene **un solo** desafío, y Lucía Llegada no administra: el taller la redirige a la sala. Donde hoy el bloque de 30b espera la pantalla del taller:

```javascript
      // El taller tiene UN solo desafío y ella no lo administra, así que el
      // taller redirige derecho a la sala. El mensaje de la mesa de llegada
      // vive ahí: es la única cara que puede decirlo.
      await Promise.all([
        page.waitForURL(/\/workshops\/[^/]+\/salas\/[^/?]+/, { timeout: 15000 }),
        page.click('button[type="submit"], input[type="submit"]')
      ]);
      if (!(await page.locator('p.muted', { hasText: 'Tu mesa todavía no se armó' }).count())) {
        failures++;
        console.error('[CHECKIN] entró, pero la sala no anuncia la espera de la mesa de llegada');
      }
      await capturar(page, '30b-taller-llegada');
```

El selector exacto del submit del check-in sale del archivo: leer el bloque alrededor de `page.fill('input[name="email"]', 'llegada@taller.example')` y conservar el que ya usa, cambiando sólo el `waitForURL` y el locator del mensaje.

- [ ] **Step 7: Verificar que la guarda nueva puede fallar**

Una guarda que no se ve fallar no prueba nada. Mutar el partial de la referencia para que no renderice la mesa, correr, y confirmar que `[TALLER]` lo caza. **Restaurar con `cp` desde un backup, no con `git checkout`**: un checkout deshace el arreglo y no la mutación.

```bash
cp app/views/workshop_rooms/_referencia.html.haml /tmp/referencia.bak
docker compose exec -T app sh -c 'sed -i "s|^= render \"workshops/my_group\".*|-# mutado|" app/views/workshop_rooms/_referencia.html.haml'
make yarn-build && make screens
# Esperado: FALLA con «[TALLER] la sala no dibuja «Tu mesa» en la referencia»
cp /tmp/referencia.bak app/views/workshop_rooms/_referencia.html.haml
```

Si la corrida mutada da verde, la guarda está midiendo cero y hay que arreglarla antes de seguir.

- [ ] **Step 8: Correr limpio**

```bash
make yarn-build && make screens
```

Esperado: 0 fallas, y los cinco contadores del final (`[RITMO]`, `[RELLENO]`, `[PASTILLA]`, `[CRITERIO]`, `[LIVE]`) con números distintos de cero.

- [ ] **Step 9: Correr la suite entera una última vez**

```bash
make spec
```

Esperado: todo verde.

- [ ] **Step 10: Commit**

```bash
git add script/capture_screens.js
git commit -m "$(cat <<'MSG'
Las capturas entran a la sala por link

25 y 26 miraban la pantalla del taller, donde ya no está el trabajo: ahora
entran al selector, sacan su foto, y de ahí a la sala. Se suman la foto del
selector con los briefs y la de una idea elegida con su contenido.

30b sigue el redirect: el taller del check-in tiene un solo desafío, así
que a quien no lo administra lo manda derecho a la sala, que es la única
cara que puede anunciar la espera de la mesa de llegada.

Claude-Session: https://claude.ai/code/session_01KajVAKcwc9zMj6qGWVYai2
MSG
)"
```
