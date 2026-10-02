# La lista de la mesa de llegada en vivo — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que quien administra un taller vea aparecer sola, sin recargar, a la
gente que va entrando a la Mesa de llegada.

**Architecture:** Un `turbo-frame` alrededor del encabezado y la lista de asientos
de la Mesa de llegada, con un endpoint de lectura que devuelve ese mismo frame, y
unas líneas de JS que lo recargan cada 5 segundos mientras el check-in esté
abierto. Sin websockets, sin ActionCable y sin la gema `turbo-rails` —que no está
instalada—: el porqué está medido en el spec.

**Tech Stack:** Rails 7.1, Turbo 8 (sólo el paquete npm), HAML, RSpec, Playwright
para `make screens`.

**Spec:** `docs/superpowers/specs/2026-10-02-lista-de-llegada-en-vivo-design.md`

## Global Constraints

- **El código va en inglés; los comentarios y los mensajes de commit, en
  español.** Los identificadores en español que ya están no se renombran.
- **Todo corre en Docker.** Nunca `bundle exec` en el host. Los specs corren con
  `make spec` / `make spec-file FILE=…`, que usan el perfil `app_test`.
  `docker compose exec app bundle exec rspec` deja `RAILS_ENV=development` y
  **todos los request specs devuelven 403 «Blocked hosts: www.example.com»** — se
  ve como si la app estuviera rota.
- **`make seed`, `make screens`, `make migrate`, `make rebuild` y `make yarn-build`
  los corre la sesión principal**, no los subagentes: tocan la base de desarrollo
  y la app corriendo.
- **Si tocás clases de Tailwind nuevas, hay que correr `make yarn-build`**, o la
  app sirve la hoja anterior y `make screens` valida una pantalla distinta de la
  que escribiste. Este plan **no** agrega clases nuevas: usa las que ya existen.
- **En los specs, toda lectura del dominio va dentro de `as_company(company) { … }`**,
  incluido un `.new`. Para montar datos cross-tenant, `without_tenant { … }`.
- **Los mensajes de commit de este repo no llevan trailers**: ni `Co-Authored-By`
  ni `Claude-Session`. El harness los inyecta; hay que cortarlos a mano.
- **Lo que no se ve da 404, no 403.** Un 403 es un oráculo de existencia.
- **Nunca una clase de Tailwind interpolada** (`"badge-#{x}"`). Hay guarda
  (`spec/lint/clases_interpoladas_spec.rb`) y mira HAML, `.vue` y `.js`.
- **`button_to` es un `<form>`:** nunca uno dentro de otro. En HAML esto es puro
  sangrado.
- **HAML no acepta bloques Ruby en una línea** (`- coll.each { |e| %li= e }`).
- **No hay linter.** Lo que cuida el estilo son los specs de `spec/lint/`.
- `make screens` tarda ~2 minutos y `make spec` ~2; las dos corren bien en
  background.

## Review Focus

Cinco entradas que el spec implica y que ningún test obvio ejercita. Cada línea
tiene su test asignado a la tarea dueña del código.

1. **El taller se cierra, o se apaga el check-in, con la pantalla abierta.** El
   temporizador quedaría pidiendo sobre un taller que ya no recibe a nadie. El
   endpoint tiene que seguir respondiendo bien —la lista sigue existiendo— pero la
   pantalla recién cargada en ese estado no tiene que arrancar el temporizador.
   Test en la Tarea 3.
2. **A quien mira le sacan la membresía con la pantalla abierta.** Lo que pasa —
   MEDIDO, porque mi primera versión de esta línea decía 404 y era falsa— es un
   **302 a `select_company_path`**: `TenantResolution#require_company`
   (`tenant_resolution.rb:70-76`) corta antes de llegar a la acción, y ya está
   cubierto por `spec/tenancy/sin_membresia_spec.rb`. Lo que importa acá es que
   **no** devuelve la lista. Consecuencia para la Tarea 3: un refresco del frame
   en ese estado recibe un 302 a una página SIN el frame, así que Turbo deja la
   región con su «content missing» en vez de datos de otra empresa. Feo, pero no
   es una fuga. Test en la Tarea 2.
3. **La mesa de llegada deja de existir entre dos refrescos**, porque el reparto
   la vació y la barrió. El frame tiene que devolver el estado vacío, no reventar
   ni crear una mesa de la nada. Test en la Tarea 2.
4. **El id del frame no coincide entre la pantalla y la respuesta.** Turbo no
   reemplaza nada y la pantalla se queda quieta **sin un solo error**: el fallo más
   caro de todos, porque es mudo. Test en la Tarea 2.
5. **Se navega a otra pantalla y se vuelve.** El temporizador no tiene que
   duplicarse ni quedar pidiendo desde una pantalla que ya no está. Test en la
   Tarea 4.

---

## File Structure

**Se crean:**

| Archivo | Responsabilidad |
|---|---|
| `app/views/workshops/_mesa_cuerpo.html.haml` | El encabezado de una mesa y su lista de asientos. UN markup, dos lugares que lo renderizan. |
| `app/javascript/llegada_en_vivo.js` | El temporizador y su ciclo de vida. |
| `spec/requests/workshop_llegada_en_vivo_spec.rb` | El endpoint: qué devuelve y a quién. |

**Se modifican:**

| Archivo | Qué cambia |
|---|---|
| `app/views/workshops/_groups.html.haml` | Extrae el cuerpo al partial y envuelve el de la llegada en un `turbo-frame`. |
| `app/controllers/workshops_controller.rb` | La acción `arrival` y su `before_action`. |
| `config/routes.rb` | La member `get :arrival`. |
| `app/javascript/application.js` | Importa el archivo nuevo. |
| `script/capture_screens.js` | La guarda `[LIVE]` y su contador. |

---

### Task 1: El partial compartido y el frame en la pantalla

**Files:**
- Create: `app/views/workshops/_mesa_cuerpo.html.haml`
- Create: `app/views/workshops/_llegada_frame.html.haml`
- Modify: `app/views/workshops/_groups.html.haml:60-100`
- Test: `spec/requests/workshop_mesas_spec.rb`

**Interfaces:**
- Consumes: nada de tareas anteriores.
- Produces: el partial `workshops/mesa_cuerpo` con locals `workshop`, `group`,
  `can_edit`; y el partial `workshops/llegada_frame` con locals `workshop`,
  `group` (puede ser `nil`) y `can_edit`, que es **el único lugar donde vive el
  id del frame**. La Tarea 2 lo renderiza desde el endpoint sin volver a
  escribirlo.

- [ ] **Step 1: Escribir el test que falla**

En `spec/requests/workshop_mesas_spec.rb`, dentro del describe que ya existe:

```ruby
  describe "el frame de la mesa de llegada" do
    it "envuelve la llegada y deja las otras mesas sin frame" do
      taller = as_company(company) { create(:workshop, status: "open") }
      otra_persona = member("otra@test.dev", :participant)
      as_company(company) do
        llegada = create(:workshop_group, :arrival, workshop: taller)
        WorkshopGroupMember.create!(workshop_group: llegada, user_id: paula.id)
        normal = create(:workshop_group, workshop: taller, name: "Mesa A")
        WorkshopGroupMember.create!(workshop_group: normal, user_id: otra_persona.id)
      end
      sign_in(admin, company: company)

      get workshop_path(taller)

      expect(response).to have_http_status(:ok)
      # El id tiene que ser exactamente éste: el endpoint de la Tarea 2 devuelve
      # el mismo, y si no coinciden Turbo no reemplaza nada y la pantalla se
      # queda quieta SIN un solo error.
      expect(response.body).to include('id="llegada"')
      # Las dos mesas se siguen dibujando con su gente: el frame no se comió nada.
      expect(response.body).to include(paula.name)
      expect(response.body).to include(otra_persona.name)
      expect(response.body).to include("Mesa A")
    end

    it "dibuja el frame aunque no haya mesa de llegada, y dice que no llegó nadie" do
      taller = as_company(company) { create(:workshop, status: "open") }
      sign_in(admin, company: company)

      get workshop_path(taller)

      expect(response.body).to include('id="llegada"')
      expect(response.body).to include("Todavía no llegó nadie")
    end
  end
```

El archivo ya tiene el helper `member(email, role)` (línea 10) y a `admin` y
`paula` como `let!` (líneas 18-19); `otra_persona` se arma con ese mismo helper
dentro del ejemplo.

- [ ] **Step 2: Correr y verificar que falla**

Run: `make spec-file FILE=spec/requests/workshop_mesas_spec.rb`
Expected: FAIL — hoy no existe ningún `id="llegada"` ni el texto del vacío.

- [ ] **Step 3: Crear el partial**

`app/views/workshops/_mesa_cuerpo.html.haml`, con el markup que hoy está inline
en `_groups` (el `.assignment-row` y la lista de asientos), tal cual:

```haml
-# El encabezado de una mesa y su lista de asientos. UN markup para los dos
-# lugares que lo renderizan: la pantalla del taller y el endpoint que recarga
-# la mesa de llegada. Si fueran dos copias, el día que una cambie la otra
-# dibujaría otra cosa y nadie se enteraría.
.assignment-row
  %span
    = group.name
    %span.muted= " · #{Flow::Texto.contar(group.workshop_group_members.size, 'persona')}"
  -# La llegada no se ofrece: es la sala de espera y se va sola cuando el
  -# reparto la vacía (`WorkshopGroupsController#destroy` la rechazaría igual).
  - if can_edit && !group.arrival?
    .assignment-row__actions
      -# El aviso dice a dónde va la gente. Las propuestas no entran: con
      -# alguna, el controller rechaza el borrado, y prometer que se borran
      -# sería un aviso falso. En modo individual no hay mesa de llegada y se
      -# saca a la persona, así que ahí el aviso dice eso.
      - aviso = workshop.individual? ? "¿Eliminar esta mesa? Se saca a quien esté en ella." : "¿Eliminar esta mesa? Quien esté en ella pasa a la mesa de llegada, con su asistencia como estaba, hasta el próximo reparto."
      = button_to "Eliminar mesa", workshop_workshop_group_path(workshop, group), method: :delete,
                  class: "btn btn-ghost btn-sm",
                  form: { data: { turbo_confirm: aviso } }

- if group.workshop_group_members.any?
  %ul.field-list
    -# Los ASIENTOS y no `group.members`: `attended` vive en el asiento, y
    -# `members` es un `has_many through` que devuelve los `User`.
    - group.workshop_group_members.each do |seat|
      %li.field-list__item
        %span
          = seat.user.name
          - unless seat.attended
            %span.muted= " · ausente"
        - if can_edit
          .assignment-row__actions
            -# Hermanos del form de convocar y NO adentro: un `button_to` es un
            -# `<form>`, y uno dentro de otro es HTML inválido que el navegador
            -# aplana sin dejar rastro en el DOM.
            = button_to seat.attended ? "Marcar ausente" : "Marcar presente",
                        attendance_workshop_path(workshop), method: :patch,
                        params: { user_id: seat.user_id, attended: !seat.attended },
                        class: "btn btn-ghost btn-sm"
            = button_to "Sacar", dismiss_workshop_path(workshop), method: :delete,
                        params: { user_id: seat.user_id }, class: "btn btn-ghost btn-sm"
```

- [ ] **Step 4: El partial del frame, que es donde vive el id**

`app/views/workshops/_llegada_frame.html.haml`. **El id del frame existe en este
archivo y en ningún otro**: la pantalla completa y el endpoint de la Tarea 2 lo
renderizan los dos, así que no pueden dejar de coincidir. Si coincidieran mal,
Turbo no reemplazaría nada y la pantalla se quedaría quieta sin un solo error.

```haml
-# El frame de la mesa de llegada: lo único de la pantalla que cambia solo.
-# Lo renderizan la pantalla completa y `WorkshopsController#arrival`, y el id
-# vive acá para que no puedan divergir.
-#
-# Se dibuja SIEMPRE, aunque todavía no haya llegado nadie: un frame que a veces
-# no está es un destino que a veces no existe. Y el vacío se dice con una línea
-# en vez de no dibujar nada, para que la pantalla no se mueva cuando entra la
-# primera persona.
-# No hay `turbo_frame_tag`: la app NO trae la gema turbo-rails, sólo el paquete
-# npm. El elemento va a mano, igual que `shared/_ai_suggestions.html.haml:23`.
-# Y el atributo se agrega SÓLO si hay valor: HAML 7 escribe `src=""` con un nil,
-# no lo omite —está medido—, y un `src` vacío en la respuesta del endpoint es
-# justo el frame apuntándose a sí mismo que esto quiere evitar.
- src = local_assigns[:src]
%turbo-frame#llegada{ **(src ? { src: src } : {}) }
  - if group
    = render "workshops/mesa_cuerpo", workshop: workshop, group: group, can_edit: can_edit
  - else
    %p.muted Todavía no llegó nadie.
```

- [ ] **Step 5: Usarlo desde `_groups`**

En `app/views/workshops/_groups.html.haml`, reemplazar el bloque que va desde
`.assignment-row` hasta el final de la lista de asientos (dentro del `%div`) por:

```haml
            %div
              -# Sólo la llegada va envuelta en un frame: es lo único que cambia
              -# solo. El `select` de convocar queda AFUERA a propósito — ahí
              -# está el estado que no se puede perder si la región se repinta.
              - if group.arrival?
                = render "workshops/llegada_frame", workshop: workshop, group: group, can_edit: can_edit
              - else
                = render "workshops/mesa_cuerpo", workshop: workshop, group: group, can_edit: can_edit
```

Y **debajo del `%ul.field-list` de las mesas**, cuando no hay ninguna mesa de
llegada, el mismo partial con `group: nil`:

```haml
      - if groups.none?(&:arrival?)
        = render "workshops/llegada_frame", workshop: workshop, group: nil, can_edit: can_edit
```

- [ ] **Step 6: Correr y verificar que pasa**

Run: `make spec-file FILE=spec/requests/workshop_mesas_spec.rb`
Expected: PASS.

Run: `make spec-file FILE=spec/requests/pantalla_del_modulo_spec.rb`
Run: `make spec-file FILE=spec/requests/workshop_convocation_spec.rb`
Run: `make spec-file FILE=spec/requests/workshop_attendances_spec.rb`
Expected: PASS las tres — son las que ya miraban este partial.

- [ ] **Step 7: Probar que el test puede fallar**

Mutar de a una, con backup por `cp` y restaurando con `cp` (nunca
`git checkout <archivo>`: en una rama sin commit eso restaura del índice, o sea
deshace el ARREGLO y no la mutación):

1. Cambiar el id del frame de `"llegada"` a `"llegada2"` en `_llegada_frame`.
   Tiene que fallar «envuelve la llegada».
2. Sacar el bloque `- if groups.none?(&:arrival?)` de `_groups`. Tiene que fallar
   «dibuja el frame aunque no haya mesa de llegada».

Decir de cada rojo POR QUÉ es el rojo buscado: un verde puede venir de un 500, de
una guarda hermana o de datos que no distinguen las dos ramas.

- [ ] **Step 8: Commit**

```bash
git add app/views/workshops/_mesa_cuerpo.html.haml app/views/workshops/_llegada_frame.html.haml app/views/workshops/_groups.html.haml spec/requests/workshop_mesas_spec.rb
git commit -F - <<'MSG'
El cuerpo de una mesa es un partial, y el de la llegada va en un frame

Un solo markup para los dos lugares que lo van a renderizar: la pantalla del
taller y el endpoint que recarga la mesa de llegada. Dos copias dibujarían cosas
distintas en cuanto una cambie, y nadie se enteraría.

El frame envuelve el encabezado y los asientos, y deja AFUERA el select de
convocar: ahí está el estado que se perdería si la región se repinta sola. Y se
dibuja siempre, aunque todavía no haya llegado nadie, porque un destino que a
veces no existe no es un destino.
MSG
```

---

### Task 2: El endpoint que devuelve el frame

**Files:**
- Modify: `config/routes.rb:95-112` (el `member do` de `workshops`)
- Modify: `app/controllers/workshops_controller.rb:4-5`
- Create: `spec/requests/workshop_llegada_en_vivo_spec.rb`

**No se toca `_llegada_frame.html.haml`:** ya existe desde la Tarea 1 y es el
único lugar donde vive el id. Esta tarea sólo lo renderiza desde el controller.

**Interfaces:**
- Consumes: el partial `workshops/llegada_frame` de la Tarea 1, con sus locals
  `workshop`, `group` (puede ser `nil`) y `can_edit`.
- Produces: `arrival_workshop_path(workshop)` (GET), que la Tarea 3 pone en el
  `src` del frame.

- [ ] **Step 1: Escribir los tests que fallan**

`spec/requests/workshop_llegada_en_vivo_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# El endpoint que recarga la mesa de llegada. Devuelve el MISMO frame que la
# pantalla completa, con el mismo id: si no coincidieran, Turbo no reemplazaría
# nada y la pantalla se quedaría quieta sin un solo error.
RSpec.describe "la llegada en vivo", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }
  let!(:otra) { without_tenant { create(:company, slug: "otra") } }

  def member(email, role, empresa = company)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, role.to_sym, company: empresa, user: u)
      u
    end
  end

  let!(:admin) { member("admin@test.dev", :admin) }
  let!(:paula) { member("paula@test.dev", :participant) }
  let!(:taller) { as_company(company) { create(:workshop, status: "open") } }

  it "lista a quien está en la mesa de llegada, dentro del frame" do
    as_company(company) do
      llegada = create(:workshop_group, :arrival, workshop: taller)
      WorkshopGroupMember.create!(workshop_group: llegada, user_id: paula.id)
    end
    sign_in(admin, company: company)

    get arrival_workshop_path(taller)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="llegada"')
    expect(response.body).to include(paula.name)
  end

  # Review Focus 3: el reparto puede haber vaciado y barrido la llegada entre dos
  # refrescos. El frame devuelve el vacío; no revienta ni crea una mesa.
  it "sin mesa de llegada devuelve el vacío y no la crea" do
    sign_in(admin, company: company)

    expect do
      get arrival_workshop_path(taller)
    end.not_to change { as_company(company) { WorkshopGroup.count } }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Todavía no llegó nadie")
  end

  it "a quien participa le da 404" do
    sign_in(paula, company: company)

    get arrival_workshop_path(taller)

    expect(response).to have_http_status(:not_found)
  end

  # Review Focus 2: la sesión guarda la empresa y no vuelve a pedir la membresía.
  # A quien se la sacaron le queda el tenant puesto y `current_membership` en
  # nil: tiene que dar 404, no 200 con la lista ni un 500.
  it "a quien perdió la membresía le da 404" do
    sign_in(admin, company: company)
    without_tenant { Membership.where(user_id: admin.id, company_id: company.id).destroy_all }

    get arrival_workshop_path(taller)

    expect(response).to have_http_status(:not_found)
  end

  it "a un taller de otra empresa le da 404" do
    ajeno = as_company(otra) { create(:workshop, status: "open") }
    sign_in(admin, company: company)

    get arrival_workshop_path(ajeno)

    expect(response).to have_http_status(:not_found)
  end
end
```

- [ ] **Step 2: Correr y verificar que falla**

Run: `make spec-file FILE=spec/requests/workshop_llegada_en_vivo_spec.rb`
Expected: FAIL con `undefined method 'arrival_workshop_path'`.

- [ ] **Step 3: La ruta**

En `config/routes.rb`, dentro del `member do` de `resources :workshops`, junto a
`enable_checkin`:

```ruby
      # La mesa de llegada sola, para recargarla sin tocar el resto de la
      # pantalla. Es de LECTURA: por eso es GET y por eso no hay `to:` —mapea a
      # `workshops#arrival`, que sí existe—.
      get :arrival
```

- [ ] **Step 4: La acción**

En `app/controllers/workshops_controller.rb`, sumar `arrival` al `only:` del
`before_action :set_workshop` y definir:

```ruby
  # La mesa de llegada sola, en el mismo frame que dibuja la pantalla completa.
  #
  # Misma puerta que el resto del armado y no una nueva: `update?` es el
  # predicado detrás del que `workshops/show` esconde el bloque entero
  # (`can_assemble`). Si esto usara su propio criterio habría dos puertas para lo
  # mismo, y el día que una cambie la otra miente.
  def arrival
    authorize @workshop, :update?
    @group = @workshop.workshop_groups.find_by(arrival: true)
    render partial: "workshops/llegada_frame",
           locals: { workshop: @workshop, group: @group, can_edit: !@workshop.closed? }
  end
```

El partial que renderiza es el que la Tarea 1 ya creó: el id del frame no se
vuelve a escribir en ningún lado.

- [ ] **Step 5: Correr y verificar que pasa**

Run: `make spec-file FILE=spec/requests/workshop_llegada_en_vivo_spec.rb`
Expected: PASS, 5 ejemplos.

Run: `make spec-file FILE=spec/requests/workshop_mesas_spec.rb`
Expected: PASS — los de la Tarea 1 siguen verdes con el partial nuevo.

- [ ] **Step 6: Probar que los tests pueden fallar**

Con backup y restauración por `cp`:

1. ~~Cambiar `authorize @workshop, :update?` por `:show?` y esperar que falle «a
   quien participa le da 404».~~ **Medido: no discrimina.** Con `:show?` pasan los
   cinco ejemplos, porque ese 404 lo da el `policy_scope` de `set_workshop` y
   nunca se llega al `authorize`. Lo que sí ejercita `update?` es el ejemplo de
   quien está sentada en la llegada pero no administra (403): mutar a `:show?`
   tiene que ponerlo en rojo.
2. ~~Cambiar `policy_scope(Workshop).find_by!` por `Workshop.find_by!` y esperar
   que falle «a un taller de otra empresa le da 404».~~ **Medido: no discrimina.**
   Ese 404 lo da el `default_scope` de `TenantScoped`, que también filtra con
   `Workshop.find_by!`. No hay mutación útil sobre esa línea: el aislamiento entre empresas
   lo cubren los specs de `spec/tenancy/`.
3. Cambiar el id del frame en `_llegada_frame` a `"llegada2"`. Tienen que fallar
   a la vez «lista a quien está» (Tarea 2) y «envuelve la llegada» (Tarea 1) —
   **ésta es la mutación que prueba que el fallo mudo está cubierto**, y que los
   dos lados salen del mismo archivo: si saliera de dos, una sola mutación
   rompería uno solo de los dos ejemplos.

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/workshops_controller.rb spec/requests/workshop_llegada_en_vivo_spec.rb
git commit -F - <<'MSG'
La mesa de llegada se puede pedir sola

Un GET que devuelve el mismo frame que dibuja la pantalla completa, desde el
mismo partial: el id vive en un solo archivo y por eso no puede divergir. Si
divergiera, Turbo no reemplazaría nada y la pantalla se quedaría quieta sin un
solo error, que es el fallo más caro porque es mudo.

La puerta es `update?`, la misma detrás de la que `workshops/show` esconde el
bloque de armado entero. Dos puertas para lo mismo terminan diciendo cosas
distintas.
MSG
```

---

### Task 3: El refresco en el navegador

**Files:**
- Create: `app/javascript/llegada_en_vivo.js`
- Modify: `app/javascript/application.js` (el import)
- Modify: `app/views/workshops/_llegada_frame.html.haml` (el `src` y los datos)
- Test: `spec/requests/workshop_llegada_en_vivo_spec.rb`

**Interfaces:**
- Consumes: `arrival_workshop_path` de la Tarea 2 y el frame `"llegada"`.
- Produces: el atributo `data-vivo` en el frame, que la guarda de la Tarea 4 usa
  para encontrarlo.

- [ ] **Step 1: Escribir el test que falla**

En `spec/requests/workshop_llegada_en_vivo_spec.rb`:

```ruby
  # Review Focus 1: con el taller cerrado o el check-in apagado no entra nadie
  # solo, así que la pantalla no arranca el temporizador. Lo decide la VISTA con
  # un atributo: el JS no adivina estado del dominio.
  describe "cuándo se refresca solo" do
    it "con el check-in abierto el frame pide refrescarse" do
      as_company(company) { taller.update!(attendance_mode: "registered") }
      sign_in(admin, company: company)

      get workshop_path(taller)

      expect(response.body).to include('data-vivo="true"')
      expect(response.body).to include(arrival_workshop_path(taller))
    end

    it "con el check-in apagado no lo pide" do
      sign_in(admin, company: company)

      get workshop_path(taller)

      expect(response.body).to include('id="llegada"')
      expect(response.body).not_to include('data-vivo="true"')
    end

    it "con el taller cerrado tampoco" do
      as_company(company) { taller.update!(attendance_mode: "registered", status: "closed") }
      sign_in(admin, company: company)

      get workshop_path(taller)

      expect(response.body).not_to include('data-vivo="true"')
    end
  end
```

- [ ] **Step 2: Correr y verificar que falla**

Run: `make spec-file FILE=spec/requests/workshop_llegada_en_vivo_spec.rb`
Expected: FAIL — todavía no existe `data-vivo`.

- [ ] **Step 3: El frame declara si hay algo que esperar**

En `app/views/workshops/_llegada_frame.html.haml`, el elemento pasa a llevar los
datos (y recordá: **no hay `turbo_frame_tag`**, la app no trae la gema
turbo-rails):

```haml
-# El splat condicional se mantiene: con `src` nil HAML escribiría `src=""`, y el
-# endpoint devolvería un frame apuntándose a sí mismo. `data` sí va siempre.
%turbo-frame#llegada{ **(src ? { src: src } : {}), data: { vivo: vivo.to_s, intervalo: 5000 } }
```

**`vivo.to_s`, no `vivo` a secas** (medido): HAML escribe un `true` como atributo
sin valor (`data-vivo`) y omite un `false`, y el JS compara contra el texto
«true».

con `vivo` como local nuevo. **Y hay que actualizar la llamada que la Tarea 2
escribió en el controller**, que todavía no pasa `vivo:`: el endpoint pasa
`vivo: false` y `src: nil`, la pantalla pasa
`src: arrival_workshop_path(workshop)` y `vivo: workshop.checkin_open?`.

`checkin_open?` ya existe en `Workshop` y es `checkin_state == :open`, o sea
modo `registered` + taller abierto: las dos condiciones del Review Focus 1 en un
solo predicado que ya está probado.

**El `src` hace que Turbo pida el frame una vez al cargar la pantalla**, además
del contenido que ya viene renderizado. Es un pedido de más por carga y se acepta
a cambio de que `reload()` quede bien definido: sin `src`, recargar un frame
depende de reasignarlo a mano y hay dos caminos para lo mismo.

- [ ] **Step 4: El temporizador**

`app/javascript/llegada_en_vivo.js`:

```js
// La mesa de llegada se refresca sola mientras el check-in está abierto: quien
// proyecta el QR ve entrar gente sin tocar nada.
//
// Recarga un `turbo-frame` en vez de empujar por websocket. El porqué está en
// `docs/superpowers/specs/2026-10-02-lista-de-llegada-en-vivo-design.md`: la
// gema `turbo-rails` no está instalada, no hay un solo canal en la app, y el
// push pediría una conexión autenticada y scopeada por empresa en la parte que
// más se audita, para ganar unos segundos sobre gente que entra caminando.
//
// El ciclo de vida es el mismo par que usa `islands.js` —`turbo:load` para
// arrancar, `turbo:before-render` para limpiar—: un mecanismo, no dos. Sin el
// limpiado, navegar a otra pantalla deja un temporizador pidiendo contra una
// pantalla que ya no está.
let timer = null;

function detener() {
  if (timer === null) return;
  clearInterval(timer);
  timer = null;
}

function arrancar() {
  detener();
  const frame = document.getElementById('llegada');
  // `data-vivo` lo pone la VISTA: el JS no sabe ni tiene que saber si el taller
  // está abierto o el check-in encendido.
  if (!frame || frame.dataset.vivo !== 'true') return;
  // Con la pestaña oculta no se pide nada: una pantalla proyectada está
  // visible, una pestaña de fondo no tiene por qué consultar.
  if (document.hidden) return;

  const intervalo = Number(frame.dataset.intervalo) || 5000;
  timer = setInterval(() => {
    const vivo = document.getElementById('llegada');
    if (!vivo) return detener();
    vivo.reload();
  }, intervalo);
}

addEventListener('turbo:load', arrancar);
addEventListener('turbo:before-render', detener);
addEventListener('visibilitychange', () => (document.hidden ? detener() : arrancar()));
```

En `app/javascript/application.js`, sumar el import junto a los que ya están:

```js
import './llegada_en_vivo';
```

- [ ] **Step 5: Correr y verificar que pasa**

Run: `make spec-file FILE=spec/requests/workshop_llegada_en_vivo_spec.rb`
Expected: PASS, 8 ejemplos.

Run: `node --check app/javascript/llegada_en_vivo.js`
Expected: sin salida.

- [ ] **Step 6: Probar que los tests pueden fallar**

1. Cambiar `workshop.checkin_open?` por `true` en el frame. Tiene que fallar «con
   el check-in apagado no lo pide» y «con el taller cerrado tampoco».
2. Cambiar `workshop.checkin_open?` por `false`. Tiene que fallar «con el check-in
   abierto el frame pide refrescarse».

Las dos mutaciones juntas son la prueba CRUZADA de que los tres ejemplos no son el
mismo test.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/llegada_en_vivo.js app/javascript/application.js app/views/workshops/_llegada_frame.html.haml spec/requests/workshop_llegada_en_vivo_spec.rb
git commit -F - <<'MSG'
La mesa de llegada se refresca sola cada cinco segundos

Mientras el check-in está abierto, que es cuando hay alguien entrando. Lo declara
la VISTA con `data-vivo`: el JS no adivina estado del dominio, y con el taller
cerrado o el modo apagado el temporizador no arranca.

El ciclo de vida usa el mismo par que `islands.js` —arrancar en turbo:load,
limpiar en turbo:before-render—, porque sin el limpiado navegar a otra pantalla
deja un temporizador pidiendo contra una pantalla que ya no está. Y con la
pestaña oculta no se pide nada.
MSG
```

---

### Task 4: La guarda del recorrido

**Files:**
- Modify: `script/capture_screens.js`
- Test: `make screens`

**Interfaces:**
- Consumes: el frame `"llegada"` con `data-vivo` de la Tarea 3, y el taller
  «Taller con check-in» que el seed ya siembra.
- Produces: la guarda `[LIVE]` y su contador en la línea final.

- [ ] **Step 1: La guarda**

En `script/capture_screens.js`, **en el bloque del taller con check-in, después de
la captura `29-taller-checkin`** (el `if (await goToWorkshop('Taller con
check-in'))` que ya existe):

```js
    // La lista de la llegada tiene que refrescarse SOLA. No hace falta una
    // segunda persona entrando: alcanza con contar los `turbo:frame-render` de
    // ese frame y exigir que el contador crezca sin que nadie toque nada.
    //
    // Probar «entró alguien nuevo mientras yo miraba» pediría dos sesiones
    // simultáneas, y un `browser.newContext()` trae una `page` SIN los listeners
    // de `pageerror` y de `response`, que se registran una sola vez: la captura
    // quedaría ciega justo a lo que esto existe para cazar. Qué devuelve el
    // endpoint lo prueba `spec/requests/workshop_llegada_en_vivo_spec.rb`.
    const refrescos = await page.evaluate(async () => {
      const frame = document.getElementById('llegada');
      if (!frame) return { error: 'sin frame' };
      if (frame.dataset.vivo !== 'true') return { error: 'el frame no está vivo' };
      let n = 0;
      const contar = (e) => { if (e.target.id === 'llegada') n++; };
      addEventListener('turbo:frame-render', contar);
      // Algo más que el intervalo declarado, para no depender del reloj.
      const espera = (Number(frame.dataset.intervalo) || 5000) + 1500;
      await new Promise((r) => setTimeout(r, espera));
      removeEventListener('turbo:frame-render', contar);
      return { n };
    });
    medidasEnVivo++;
    if (refrescos.error || !refrescos.n) {
      failures++;
      console.error(`[LIVE] la mesa de llegada no se refrescó sola: ${JSON.stringify(refrescos)}`);
    }
```

`let medidasEnVivo = 0;` va arriba, con las otras constantes del recorrido.

- [ ] **Step 2: El contador en la línea final**

Donde el recorrido imprime `[RITMO]` y `[RELLENO]`, sumar:

```js
` · [LIVE] ${medidasEnVivo} pantalla(s) medida(s)`
```

Y, junto a las otras guardas que fallan si midieron de menos:

```js
if (!medidasEnVivo) {
  failures++;
  console.error('[LIVE] no se midió ninguna pantalla con la llegada en vivo');
}
```

Una guarda que mide cero da verde y es indistinguible de una que funciona: es el
mismo motivo por el que `[RITMO]` y `[RELLENO]` cuentan.

- [ ] **Step 3: Correr el recorrido — lo corre la sesión principal**

`make screens` toca la base de desarrollo y la app corriendo. **No lo corre el
implementador.** Escribí el cambio, commiteá, devolvé `DONE` diciendo que falta la
corrida, y la sesión principal corre `make screens` y te reporta el output.

Expected: 74 capturas, 0 errores, y la línea final con `[LIVE] 1 pantalla(s)`.

- [ ] **Step 4: Probar que la guarda puede fallar — también la sesión principal**

Con backup por `cp`, una por vez, y restaurando con `cp`:

1. En `llegada_en_vivo.js`, comentar el `setInterval`. Expected: `[LIVE] la mesa
   de llegada no se refrescó sola: {"n":0}`.
2. En `_llegada_frame.html.haml`, poner `data: { vivo: false }`. Expected:
   `[LIVE] … {"error":"el frame no está vivo"}`.

**Review Focus 5** se verifica en la misma corrida sin trabajo extra: si el
temporizador no se limpiara al navegar, aparecerían pedidos a `/arrival` en
pantallas posteriores, y el listener de respuestas del recorrido los cuenta. Si la
corrida queda verde, no se filtró.

- [ ] **Step 5: Commit**

```bash
git add script/capture_screens.js
git commit -F - <<'MSG'
El recorrido exige que la mesa de llegada se refresque sola

Cuenta los turbo:frame-render de ese frame y falla si el contador no crece sin
que nadie toque nada. No simula a una segunda persona entrando: eso pediría dos
sesiones, y un browser.newContext() trae una page sin los listeners de pageerror
y de response, o sea una captura ciega justo a lo que esto existe para cazar.

Qué devuelve el endpoint lo prueba el request spec. Cada herramienta prueba lo
que puede probar, y ninguna finge la mitad de la otra.

La guarda imprime cuántas pantallas midió y falla si midió cero, por el mismo
motivo que [RITMO] y [RELLENO]: una guarda que mide cero da verde.
MSG
```

---

## Cierre de la rama

- [ ] **`make spec` y `make screens` en verde, con los números a la vista.** No se
  afirma nada sin el output.
- [ ] **Revisión de rama entera** con `superpowers:requesting-code-review`.
- [ ] **Merge `--no-ff` con mensaje «Merge: …»**, que es la convención del repo.
  El mensaje va en un ARCHIVO: `git merge -F -` no lee de stdin y falla con
  `error: could not read file '-'`.
- [ ] **Handoff** actualizado.
