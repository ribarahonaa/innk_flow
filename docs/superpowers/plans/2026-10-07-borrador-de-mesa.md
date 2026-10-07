# El borrador de la mesa — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lo que una mesa teclea en la sala de un taller sobrevive a un refresh, a una pestaña cerrada y a una batería muerta, sin publicar nada.

**Architecture:** Una tabla `workshop_drafts` con un borrador por `(mesa, sala[, idea])`, escrita por un `PATCH` que responde 204 y disparada por un debounce de 2 s en el navegador. Los dos formularios de la sala se prellenan con el borrador si existe; mandarlo lo borra en la misma transacción. Publicar sigue siendo un acto explícito: B no toca `WorkshopProposal`.

**Tech Stack:** Rails 7.1, Postgres (índices UNIQUE parciales, FK compuestas por `Flow::MigrationHelpers`), HAML, JavaScript plano con esbuild (sin isla Vue, sin `turbo-rails` del lado de Rails), RSpec, Playwright (`make screens`).

**Spec:** `docs/superpowers/specs/2026-10-07-borrador-de-mesa-design.md`

## Global Constraints

- **El código va en inglés; los comentarios y los mensajes de commit, en español.** Rige para todo lo que se escriba acá, sin excepción.
- **Toda tabla y toda columna nueva va en inglés**, sin excepción.
- **Todo corre en Docker. Nunca `bundle exec` en el host.** Los specs corren en `app_test`: `make spec`, `make spec-file FILE=…`, `make spec-line FILE=… LINE=…`. Correr `docker compose exec app bundle exec rspec` da 403 «Blocked hosts» en todos los request specs.
- **`make yarn-build` ANTES de `make screens`**, siempre que se toque `app/javascript/` o se agreguen utilidades de Tailwind. `app/assets/builds/*` está gitignoreado: sin compilar, el navegador sirve el bundle anterior.
- **Migraciones: `schema_format = :sql`.** Después de migrar, commitear `db/structure.sql`.
- **Toda lectura del dominio en un spec va dentro de `as_company(company) { … }`**, incluido un `.new` (toca el `default_scope`) y cualquier asociación leída después de salir del bloque. Lo de afuera del tenant va en `without_tenant { … }`.
- **No hay linter configurado.** No buscar uno.
- **Los commits van con `ribarahonaa@gmail.com`** (ya está en el `git config` local; no pisarlo).
- **Nunca `bundle exec rspec` directo; nunca `docker compose --profile test down`** (se lleva el stack entero). Para bajar el contenedor de test: `docker compose --profile test stop app_test`.

## Review Focus

Cinco cosas que la spec implica y que ningún test obvio ejercita. Cada una tiene su test asignado a la tarea que es dueña del código.

1. **Un `PATCH` sin `payload` NO puede vaciar el borrador.** `params.fetch(:payload, {})` devolvería `{}` y pisaría el texto de la mesa con nada: pérdida silenciosa de datos, y la puede causar el propio JS si alguna vez manda un cuerpo mal armado. **Decisión: un `PATCH` sin la clave `payload` es un no-op — responde 204 y no escribe.** Test en la Tarea 2.
2. **Un `idea_id` mandado a una sala de IDEAR lo ignora el servidor.** La fase la decide la sala (`@link.kind`), no el cliente; si no, un cliente crea una fila con `idea_id` en una sala de idear, que escapa al índice de unicidad pensado para esa cara. Test en la Tarea 2.
3. **Un `idea_id` ausente o ajeno en una sala de EVOLUCIÓN da 404, no 403 ni 500.** `find_by!` sobre `workable_ideas` ya lo hace; hay que pinnearlo para que nadie lo cambie por un `find_by` con `rescue`. Test en la Tarea 2.
4. **Un payload grande viaja entero, sin truncar.** No se agrega tope: `WorkshopProposal.payload` ya acepta el mismo contenido del mismo formulario, así que un tope acá rechazaría un borrador cuya propuesta sí entraría. El test existe para que nadie meta un truncado silencioso después. Test en la Tarea 2.
5. **Una idea sin versión vigente deja `based_on_version_id` en NULL y el aviso NO aparece.** Es correcto —no hay contra qué comparar— pero sin test, el día que `based_on_version` se vuelva NOT NULL el borrador de una idea sin versión revienta al guardar. Test en la Tarea 4.

---

## Estructura de archivos

| Archivo | Responsabilidad |
|---|---|
| `db/migrate/20261007120000_create_workshop_drafts.rb` | la tabla, los dos índices parciales, las cuatro FK compuestas |
| `app/models/workshop_draft.rb` | las asociaciones y las dos invariantes |
| `app/models/workshop_group.rb` | `has_many :workshop_drafts, dependent: :destroy` |
| `app/lib/flow/workshops/assign_groups.rb` | la cláusula del barrido de mesas vacías |
| `app/controllers/workshop_drafts_controller.rb` | el único escritor del borrador |
| `config/routes.rb` | `resource :draft, only: %i[update]` dentro de la sala |
| `app/controllers/workshop_rooms_controller.rb` | carga `@draft` en las dos caras |
| `app/views/workshop_rooms/_ideation.html.haml` | prellenado, sello, `data-*` del autoguardado |
| `app/views/workshop_rooms/_evolution.html.haml` | prellenado, aviso de base vieja, sello, `data-*` |
| `app/views/workshop_rooms/_draft_stamp.html.haml` | el sello, UN partial para las dos caras |
| `app/controllers/workshop_ideas_controller.rb` | borra el borrador al crear la idea |
| `app/controllers/workshop_proposals_controller.rb` | borra el borrador al mandar la propuesta, en transacción |
| `app/javascript/workshop_draft.js` | el debounce y el `fetch` |
| `app/javascript/application.js` | el import |
| `config/locales/es.yml` | las cuatro cadenas del borrador |
| `spec/models/workshop_draft_spec.rb` | las dos invariantes |
| `spec/requests/workshop_drafts_spec.rb` | el endpoint: guardas, no-op, 404, tamaño |
| `spec/requests/workshop_draft_prefill_spec.rb` | prellenado, borrado al mandar, aviso, sello |
| `spec/lib/flow/workshops/assign_groups_spec.rb` | el barrido no se lleva un borrador |
| `script/capture_screens.js` | la guarda `[DRAFT]` con contador y piso |

---

## Task 1: La tabla, el modelo y la mesa que no se borra sola

**Files:**
- Create: `db/migrate/20261007120000_create_workshop_drafts.rb`
- Create: `app/models/workshop_draft.rb`
- Create: `spec/models/workshop_draft_spec.rb`
- Modify: `app/models/workshop_group.rb` (sumar `has_many`)
- Modify: `app/lib/flow/workshops/assign_groups.rb` (la cláusula del barrido)
- Modify: `spec/lib/flow/workshops/assign_groups_spec.rb`
- Modify: `spec/factories/` (factoría nueva)
- Commit: `db/structure.sql`

**Interfaces:**
- Consumes: `Flow::MigrationHelpers#tenant_table` y `#add_tenant_fk` (ya existen en `lib/flow/migration_helpers.rb`).
- Produces: `WorkshopDraft` con `workshop_group`, `workshop_challenge`, `idea` (opcional), `based_on_version` (opcional, clase `IdeaVersion`), `updated_by` (clase `User`), `payload` (jsonb). `WorkshopGroup#workshop_drafts`. La Tarea 2 escribe por `group.workshop_drafts.find_or_initialize_by(workshop_challenge:, idea_id:)`.

- [ ] **Step 1: Escribir la migración**

```ruby
# frozen_string_literal: true

# El borrador de trabajo de una mesa: lo que teclea y todavía no mandó.
#
# NO es una versión ni una propuesta. Una versión es contenido inmutable con su
# `embedding`, y una propuesta es algo que la mesa YA mandó para que el autor
# decida. Esto es mutable y se pisa: por eso no acumula filas ni encola un
# `EmbedVersionJob` por tanda de tecleo, que es lo que haría un autoguardado que
# publicara.
#
# No reusa `workshop_proposals` porque ahí `idea_id` es NOT NULL y en la cara de
# idear la idea todavía no existe: cubriría media función.
class CreateWorkshopDrafts < ActiveRecord::Migration[7.1]
  include Flow::MigrationHelpers

  def change
    tenant_table :workshop_drafts do |t|
      t.uuid :workshop_group_id,     null: false
      t.uuid :workshop_challenge_id, null: false
      # NULL en idear: el borrador es de la mesa y de la sala, y todavía no hay
      # idea a la que colgarse.
      t.uuid :idea_id
      # Contra qué versión se tecleó. Es lo que deja avisar que la vigente
      # avanzó mientras la mesa escribía.
      t.uuid :based_on_version_id
      t.jsonb :payload, null: false, default: {}
      # Quién tocó último. Funcional y no auditoría: es la única señal de
      # colisión que se puede dar sin websockets —el sello la nombra—.
      t.references :updated_by, type: :uuid, null: false,
                   foreign_key: { to_table: :users }
      t.timestamps
    end

    # DOS índices parciales y no uno: Postgres trata los NULL como distintos,
    # así que un UNIQUE(group, link, idea) a secas dejaría a una mesa acumular
    # un borrador de idear POR AUTOGUARDADO. Mismo patrón que
    # `index_workshop_groups_on_workshop_id_arrival ... WHERE arrival`.
    add_index :workshop_drafts, %i[workshop_group_id workshop_challenge_id],
              unique: true, where: "idea_id IS NULL",
              name: "index_workshop_drafts_ideation_uniq"
    add_index :workshop_drafts, %i[workshop_group_id workshop_challenge_id idea_id],
              unique: true, where: "idea_id IS NOT NULL",
              name: "index_workshop_drafts_evolution_uniq"

    add_tenant_fk :workshop_drafts, :workshop_groups,     column: :workshop_group_id
    add_tenant_fk :workshop_drafts, :workshop_challenges, column: :workshop_challenge_id
    add_tenant_fk :workshop_drafts, :ideas,               column: :idea_id
    # `nullify` y no `cascade`: si se borrara una versión, el cascade se
    # llevaría el texto de la mesa por un evento ajeno a ella. Nulificando se
    # pierde sólo el marcador de «contra qué se tecleó» y el texto queda. El
    # helper acota el SET NULL a la columna para no nulear `company_id`, que es
    # NOT NULL.
    add_tenant_fk :workshop_drafts, :idea_versions, column: :based_on_version_id,
                                                   on_delete: :nullify
  end
end
```

- [ ] **Step 2: Correr la migración y ver el schema**

```bash
make rails c_args="db:migrate"   # si el Makefile no expone un target, usar:
docker compose exec app bin/rails db:migrate
git diff --stat db/structure.sql
```

Esperado: `db/structure.sql` cambia con la tabla, los dos índices parciales (`WHERE idea_id IS NULL` y `WHERE idea_id IS NOT NULL`) y las cuatro constraints `workshop_drafts_*_same_company`.

- [ ] **Step 3: Escribir la factoría**

En `spec/factories/` (seguir el archivo donde viven las otras del taller):

```ruby
factory :workshop_draft do
  workshop_group
  workshop_challenge
  payload { {} }
  updated_by factory: :user
end
```

- [ ] **Step 4: Escribir el spec de las dos invariantes, que tiene que fallar**

`spec/models/workshop_draft_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# Las dos invariantes que Postgres no puede cuidar.
RSpec.describe WorkshopDraft do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }
  let!(:autora) do
    without_tenant do
      u = create(:user, email: "ana@test.dev")
      create(:membership, :participant, company: company, user: u)
      u
    end
  end

  # `kind` sale de `challenge_step&.kind`, así que la fase de la sala la fija el
  # módulo al que apunta el vínculo.
  def sala(kind)
    challenge = create(:challenge)
    step = create(:challenge_step, challenge: challenge, kind: kind, status: "active")
    workshop = create(:workshop, status: "open")
    link = create(:workshop_challenge, workshop: workshop, challenge: challenge, challenge_step: step)
    group = create(:workshop_group, workshop: workshop)
    [ link, group, challenge ]
  end

  it "en una sala de evolución exige la idea" do
    as_company(company) do
      link, group, = sala("evolution")
      draft = WorkshopDraft.new(workshop_group: group, workshop_challenge: link,
                                idea: nil, updated_by: autora, payload: {})
      expect(draft).not_to be_valid
      expect(draft.errors[:idea_id].join).to include("evolución")
    end
  end

  it "en una sala de idear rechaza la idea" do
    as_company(company) do
      link, group, challenge = sala("ideation")
      idea = create(:idea, challenge: challenge, author: autora)
      draft = WorkshopDraft.new(workshop_group: group, workshop_challenge: link,
                                idea: idea, updated_by: autora, payload: {})
      expect(draft).not_to be_valid
    end
  end

  # El vínculo de un taller en borrador todavía no tiene módulo resuelto, así
  # que no hay fase contra la que comparar. La validación NO opina: lo que cierra
  # ese camino es el guarda `workable?` del controller, y hacer fallar acá la
  # convertiría en el segundo lugar que decide si una sala admite trabajo.
  it "sin módulo resuelto no opina" do
    as_company(company) do
      challenge = create(:challenge)
      workshop = create(:workshop, status: "draft")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge,
                                         challenge_step: nil)
      group = create(:workshop_group, workshop: workshop)
      draft = WorkshopDraft.new(workshop_group: group, workshop_challenge: link,
                                idea: nil, updated_by: autora, payload: {})
      expect(draft).to be_valid
    end
  end

  it "rechaza una versión que es de otra idea" do
    as_company(company) do
      link, group, challenge = sala("evolution")
      mia = create(:idea, challenge: challenge, author: autora)
      ajena = create(:idea, challenge: challenge, author: autora)
      version = create(:idea_version, idea: ajena, number: 1)
      draft = WorkshopDraft.new(workshop_group: group, workshop_challenge: link,
                                idea: mia, based_on_version: version,
                                updated_by: autora, payload: {})
      expect(draft).not_to be_valid
      expect(draft.errors[:based_on_version_id].join).to include("otra idea")
    end
  end
end
```

- [ ] **Step 5: Correrlo y ver que falla**

```bash
make spec-file FILE=spec/models/workshop_draft_spec.rb
```

Esperado: FALLA con `uninitialized constant WorkshopDraft`.

- [ ] **Step 6: Escribir el modelo**

```ruby
# frozen_string_literal: true

# El borrador de trabajo de una mesa: lo tecleado que todavía no se mandó.
#
# Es de la MESA y no de cada persona, que es lo que la pantalla ya promete («es
# de la mesa, no solo tuyo») y lo único que sobrevive al caso que esto existe
# para prevenir: al escribiente se le muere la máquina o se va, y el texto sigue
# ahí para el resto. El precio es última-escritura-gana, y la señal de colisión
# es `updated_by` en el sello.
class WorkshopDraft < ApplicationRecord
  include TenantScoped

  belongs_to :workshop_group
  belongs_to :workshop_challenge
  belongs_to :idea, optional: true
  belongs_to :based_on_version, class_name: "IdeaVersion", optional: true
  belongs_to :updated_by, class_name: "User"

  validate :idea_matches_room
  validate :version_belongs_to_idea

  private

  # No puede ser un CHECK de Postgres: el `kind` está tres tablas más allá
  # (`workshop_challenges` → `challenge_steps` → `kind`).
  #
  # Con `kind` nil —el vínculo de un taller en borrador, que todavía no resolvió
  # su módulo— NO opina: no hay fase contra la que comparar, y rechazar ahí
  # inventaría una regla sobre un estado que no existe. Lo que cierra ese camino
  # es el guarda `workable?` del controller.
  def idea_matches_room
    kind = workshop_challenge&.kind
    return if kind.nil?

    if kind == "evolution" && idea_id.blank?
      errors.add(:idea_id, "una sala de evolución trabaja sobre una idea")
    elsif kind != "evolution" && idea_id.present?
      errors.add(:idea_id, "sólo una sala de evolución trabaja sobre una idea")
    end
  end

  # Un borrador que dice basarse en la versión de OTRA idea vuelve absurdo el
  # aviso de base vieja. Hoy sólo el servidor puede romperlo, y por eso mismo es
  # lo que un copy-paste rompe sin que nada se queje.
  def version_belongs_to_idea
    return if based_on_version.nil?
    return if based_on_version.idea_id == idea_id

    errors.add(:based_on_version_id, "esa versión es de otra idea")
  end
end
```

- [ ] **Step 7: Sumar el `has_many` a `WorkshopGroup`**

En `app/models/workshop_group.rb`, junto a `has_many :workshop_proposals`:

```ruby
  # `dependent: :destroy` crea un peligro que `AssignGroups` tiene que conocer:
  # su barrido de mesas vacías se llevaría el texto de la mesa. Ver la cláusula
  # de `seat!`.
  has_many :workshop_drafts, dependent: :destroy
```

- [ ] **Step 8: Correr el spec del modelo y ver que pasa**

```bash
make spec-file FILE=spec/models/workshop_draft_spec.rb
```

Esperado: PASS, 4 ejemplos.

- [ ] **Step 9: Escribir el ejemplo de que el barrido no se lleva un borrador**

En `spec/lib/flow/workshops/assign_groups_spec.rb`, siguiendo el idioma de los ejemplos que ya hay ahí:

```ruby
  # El barrido de mesas vacías borra con `mesa.destroy!`, y `dependent: :destroy`
  # se llevaría el borrador. Una mesa que sobrevive sólo por tenerlo es un
  # sobrante inocuo —el mismo razonamiento que el comentario ya da para las
  # propuestas, donde la segunda cláusula es LA CARRERA y no prolijidad—;
  # perder el texto de la mesa, no.
  it "no borra una mesa vacía que tiene un borrador" do
    as_company(company) do
      vacia = create(:workshop_group, workshop: workshop)
      create(:workshop_draft, workshop_group: vacia, workshop_challenge: link,
                              updated_by: ana, payload: { "resumen" => "a medio escribir" })

      described_class.new(workshop, size: 4).call

      expect(WorkshopGroup.exists?(vacia.id)).to be(true)
      expect(vacia.reload.workshop_drafts.count).to eq(1)
    end
  end
```

- [ ] **Step 10: Correrlo y ver que falla**

```bash
make spec-file FILE=spec/lib/flow/workshops/assign_groups_spec.rb
```

Esperado: FALLA — la mesa vacía se borra y el borrador se va con ella.

- [ ] **Step 11: Sumar la cláusula al barrido**

En `app/lib/flow/workshops/assign_groups.rb`, dentro de `seat!`, donde el barrido pregunta `workshop_proposals.empty?`, sumar `&& mesa.workshop_drafts.empty?` y extender el comentario que ya está ahí:

```ruby
      # La segunda cláusula del barrido es LA CARRERA y no cinturón y tirantes:
      # el guarda de propuestas corrió FUERA del lock, contra un escritor
      # (`WorkshopProposalsController#create`) que no toma ninguno. Si una
      # propuesta entra a mitad del reparto y deja a su mesa vacía, borrarla se
      # llevaría la propuesta por el CASCADE.
      #
      # El borrador se suma por lo mismo y con una diferencia: su escritor
      # (`WorkshopDraftsController#update`) no sólo no toma lock, además se
      # dispara SOLO cada dos segundos, así que la ventana es mucho más ancha.
      # Lo que NO se toca es el guarda de arriba: negarse a repartir porque
      # alguien tecleó una palabra bloquearía una operación común por texto sin
      # mandar. Ese guarda existe por la procedencia de versiones publicadas, y
      # un borrador no la tiene.
```

- [ ] **Step 12: Correr los dos specs y la suite de taller**

```bash
make spec-file FILE=spec/lib/flow/workshops/assign_groups_spec.rb
make spec-file FILE=spec/models/workshop_draft_spec.rb
```

Esperado: los dos en PASS.

- [ ] **Step 12b: Correr las guardas de tenencia, que es lo que cubre las cuatro FK compuestas**

```bash
make spec-file FILE=spec/tenancy/schema_spec.rb
make spec-file FILE=spec/tenancy/sin_membresia_spec.rb
```

Esperado: PASS. `schema_spec.rb` introspecciona `pg_constraint` y **falla si aparece
una FK simple entre dos tablas con `company_id`**, así que las cuatro FK de la
tabla nueva quedan cubiertas sin escribir un ejemplo. Esto es la verificación de
esa afirmación, no su repetición: si falla, alguna FK se escribió con
`add_foreign_key` en vez de `add_tenant_fk`.

- [ ] **Step 13: Commit**

```bash
git add db/migrate/20261007120000_create_workshop_drafts.rb db/structure.sql \
        app/models/workshop_draft.rb app/models/workshop_group.rb \
        app/lib/flow/workshops/assign_groups.rb \
        spec/models/workshop_draft_spec.rb \
        spec/lib/flow/workshops/assign_groups_spec.rb spec/factories
git commit -m "El borrador de la mesa tiene tabla, y el reparto no se lo lleva"
```

---

## Task 2: El endpoint que escribe el borrador

**Files:**
- Create: `app/controllers/workshop_drafts_controller.rb`
- Create: `spec/requests/workshop_drafts_spec.rb`
- Modify: `config/routes.rb` (dentro del bloque `resources :workshop_challenges … as: :sala`)

**Interfaces:**
- Consumes: `WorkshopDraft` y `WorkshopGroup#workshop_drafts` de la Tarea 1. `Workshop#group_of(user)`, `WorkshopChallenge#workable?`, `WorkshopChallenge#kind`, `WorkshopGroup#workable_ideas(challenge)`, `WorkshopGroup#arrival?` — todos ya existen.
- Produces: la ruta `workshop_sala_draft_path(workshop, link)` con verbo `PATCH`. Responde **204** en el camino feliz, **409** si la sala no admite trabajo, **403** sin mesa o desde la llegada, **404** si la idea no es del conjunto trabajable. La Tarea 5 la consume desde `data-draft-url`.

- [ ] **Step 1: Sumar la ruta**

En `config/routes.rb`, dentro del bloque de la sala, debajo de `resources :proposals`:

```ruby
      # Singular: una mesa tiene UN borrador por sala. El id de la idea viaja en
      # el CUERPO y no en la ruta —igual que el `hidden_field_tag :idea_id` del
      # formulario de propuesta—, porque el cliente no conoce el id del
      # borrador: la identidad de la fila la arma el servidor.
      resource :draft, only: %i[update], controller: "workshop_drafts"
```

- [ ] **Step 2: Escribir el spec del endpoint, que tiene que fallar**

`spec/requests/workshop_drafts_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# El autoguardado de la mesa. Lo dispara un temporizador y no una persona, así
# que responde con códigos pelados: un `redirect_to` haría que el `fetch` siga
# la redirección y traiga la pantalla entera cada dos segundos.
RSpec.describe "sala del taller: el borrador de la mesa", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, :participant, company: company, user: u)
      u
    end
  end

  let!(:ana) { member("ana@test.dev") }
  let!(:beto) { member("beto@test.dev") }
  let!(:carla) { member("carla@test.dev") }

  # Una sala de IDEAR con ana y beto sentados. Carla queda afuera a propósito.
  let!(:idear) do
    as_company(company) do
      challenge = create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: "ideation", status: "active")
      field = create(:form_field, challenge_step: step, label: "Resumen", field_type: "text")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge, challenge_step: step)
      group = create(:workshop_group, workshop: workshop)
      [ ana, beto ].each { |u| create(:workshop_group_member, workshop_group: group, user: u) }
      { workshop: workshop, link: link, group: group, field: field, challenge: challenge }
    end
  end

  def patch_draft(setup, params)
    patch workshop_sala_draft_path(setup[:workshop], setup[:link]), params: params
  end

  def drafts
    as_company(company) { WorkshopDraft.all.to_a }
  end

  describe "las cuatro guardas, en el mismo orden que los otros dos POST de la sala" do
    it "sin sesión no entra" do
      patch_draft(idear, payload: { idear[:field].key => "x" })
      expect(response).to have_http_status(:found)
    end

    it "quien no está en ninguna mesa del taller: 403" do
      sign_in(carla, company: company)
      patch_draft(idear, payload: { idear[:field].key => "x" })
      expect(response).to have_http_status(:forbidden)
      expect(drafts).to be_empty
    end

    it "desde la mesa de llegada: 403" do
      as_company(company) do
        idear[:group].workshop_group_members.destroy_all
        llegada = create(:workshop_group, workshop: idear[:workshop], arrival: true)
        create(:workshop_group_member, workshop_group: llegada, user: ana)
      end
      sign_in(ana, company: company)
      patch_draft(idear, payload: { idear[:field].key => "x" })
      expect(response).to have_http_status(:forbidden)
      expect(drafts).to be_empty
    end

    it "una sala que ya no admite trabajo: 409" do
      as_company(company) do
        idear[:link].challenge_step.update!(status: "completed")
      end
      sign_in(ana, company: company)
      patch_draft(idear, payload: { idear[:field].key => "x" })
      expect(response).to have_http_status(:conflict)
      expect(drafts).to be_empty
    end
  end

  describe "el camino feliz" do
    it "escribe el borrador y responde 204" do
      sign_in(ana, company: company)
      patch_draft(idear, payload: { idear[:field].key => "a medio escribir" })

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_empty
      draft = drafts.sole
      expect(draft.payload).to eq(idear[:field].key => "a medio escribir")
      expect(draft.idea_id).to be_nil
      expect(draft.updated_by_id).to eq(ana.id)
    end

    # Esto es lo que prueba el índice parcial, y no la intención de que haya uno
    # solo: sin el `WHERE idea_id IS NULL`, Postgres trata los NULL como
    # distintos y cada autoguardado deja una fila nueva.
    it "dos personas de la misma mesa dejan UNA fila, y gana la última" do
      sign_in(ana, company: company)
      patch_draft(idear, payload: { idear[:field].key => "lo de ana" })
      sign_in(beto, company: company)
      patch_draft(idear, payload: { idear[:field].key => "lo de beto" })

      draft = drafts.sole
      expect(draft.payload[idear[:field].key]).to eq("lo de beto")
      expect(draft.updated_by_id).to eq(beto.id)
    end

    it "una clave que no es de un campo se descarta" do
      sign_in(ana, company: company)
      patch_draft(idear, payload: { idear[:field].key => "ok", "inventada" => "no" })
      expect(drafts.sole.payload.keys).to contain_exactly(idear[:field].key)
    end
  end

  # ── Review Focus ─────────────────────────────────────────────────────────
  #
  # Cuatro cosas que ningún test obvio ejercita y que son pérdida de datos o
  # cambio de código de estado si alguien las toca.

  # Lo peor que podía hacer este endpoint: `params.fetch(:payload, {})` devuelve
  # `{}` y pisa el texto de la mesa con nada. Un cuerpo mal armado del JS lo
  # causaría sin que nadie se enterara.
  it "un PATCH sin `payload` es un no-op: no pisa el borrador con nada" do
    sign_in(ana, company: company)
    patch_draft(idear, payload: { idear[:field].key => "lo que la mesa escribió" })
    patch_draft(idear, {})

    expect(response).to have_http_status(:no_content)
    expect(drafts.sole.payload[idear[:field].key]).to eq("lo que la mesa escribió")
  end

  # La fase la decide la SALA y no el cliente. Si el servidor aceptara el
  # `idea_id`, un cliente crearía una fila con idea en una sala de idear, que
  # escapa al índice de unicidad pensado para esa cara.
  it "un `idea_id` mandado a una sala de idear se ignora" do
    idea = as_company(company) { create(:idea, challenge: idear[:challenge], author: ana) }
    sign_in(ana, company: company)
    patch_draft(idear, payload: { idear[:field].key => "x" }, idea_id: idea.id)

    expect(response).to have_http_status(:no_content)
    expect(drafts.sole.idea_id).to be_nil
  end

  context "en una sala de evolución" do
    let!(:evolucion) do
      as_company(company) do
        challenge = create(:challenge)
        ideation = create(:challenge_step, challenge: challenge, kind: "ideation", status: "completed")
        field = create(:form_field, challenge_step: ideation, label: "Resumen", field_type: "text")
        step = create(:challenge_step, challenge: challenge, kind: "evolution", status: "active")
        workshop = create(:workshop, status: "open")
        link = create(:workshop_challenge, workshop: workshop, challenge: challenge, challenge_step: step)
        group = create(:workshop_group, workshop: workshop)
        create(:workshop_group_member, workshop_group: group, user: ana)
        # `workable_ideas` es `Idea.alive`, o sea `status: "active"`.
        idea = create(:idea, challenge: challenge, author: ana, status: "active")
        version = create(:idea_version, idea: idea, number: 1, title: "La mía")
        idea.update!(current_version: version)
        { workshop: workshop, link: link, field: field, idea: idea, version: version,
          challenge: challenge }
      end
    end

    it "escribe el borrador con la idea y la versión vigente" do
      sign_in(ana, company: company)
      patch_draft(evolucion, payload: { evolucion[:field].key => "mejor así" },
                             idea_id: evolucion[:idea].id)

      draft = drafts.sole
      expect(draft.idea_id).to eq(evolucion[:idea].id)
      # Lo escribe el SERVIDOR desde `idea.current_version_id`, nunca el cliente:
      # es el dato del que depende el aviso de base vieja, y un cliente que lo
      # manda puede mentirlo.
      expect(draft.based_on_version_id).to eq(evolucion[:version].id)
    end

    it "sin `idea_id`: 404, no 403 ni 500" do
      sign_in(ana, company: company)
      patch_draft(evolucion, payload: { evolucion[:field].key => "x" })
      expect(response).to have_http_status(:not_found)
      expect(drafts).to be_empty
    end

    # Una idea que no es de nadie de la mesa no se distingue de una inexistente:
    # el 404 es lo que impide que el código de estado confirme que existe.
    it "con una idea ajena al conjunto trabajable: 404" do
      ajena = as_company(company) do
        create(:idea, challenge: evolucion[:challenge], author: carla, status: "active")
      end
      sign_in(ana, company: company)
      patch_draft(evolucion, payload: { evolucion[:field].key => "x" }, idea_id: ajena.id)
      expect(response).to have_http_status(:not_found)
      expect(drafts).to be_empty
    end

    # No se agrega tope: `WorkshopProposal.payload` ya acepta el mismo contenido
    # del mismo formulario, así que un tope acá rechazaría un borrador cuya
    # propuesta sí entraría. Este ejemplo existe para que nadie meta un truncado
    # silencioso después.
    it "un payload largo viaja entero, sin truncar" do
      largo = "a" * 50_000
      sign_in(ana, company: company)
      patch_draft(evolucion, payload: { evolucion[:field].key => largo },
                             idea_id: evolucion[:idea].id)
      expect(drafts.sole.payload[evolucion[:field].key].length).to eq(50_000)
    end
  end
end
```

- [ ] **Step 3: Correrlo y ver que falla**

```bash
make spec-file FILE=spec/requests/workshop_drafts_spec.rb
```

Esperado: FALLA — `workshop_sala_draft_path` no existe todavía si el Step 1 no se corrió, o `uninitialized constant WorkshopDraftsController`.

- [ ] **Step 4: Escribir el controller**

```ruby
# frozen_string_literal: true

# El autoguardado de lo que la mesa teclea en la sala: el ÚNICO escritor de
# `WorkshopDraft`.
#
# No publica nada. Una propuesta y una versión siguen naciendo donde nacían; esto
# sólo hace que el texto sobreviva a un refresh.
#
# Responde con códigos pelados y NUNCA con un redirect. Los otros dos POST de la
# sala redirigen con flash porque los dispara una persona apretando un botón;
# esto lo dispara un temporizador cada dos segundos, y un `redirect_to` haría que
# el `fetch` siga la redirección y traiga la pantalla entera cada vez.
class WorkshopDraftsController < ApplicationController
  before_action :set_link

  def update
    authorize @workshop, :work?
    # Las mismas cuatro guardas que `WorkshopIdeasController` y
    # `WorkshopProposalsController`, en el mismo orden. Repetidas y no
    # reescritas: divergir es cómo se abrió la fuga que esos dos documentan
    # —`work?` da true por `administers_any?` SIN mesa—.
    return head :conflict unless @link.workable?

    group = @workshop.group_of(current_user)
    return head :forbidden unless group
    # La mesa de llegada no trabaja. Misma pregunta que los otros seis lugares.
    return head :forbidden if group.arrival?

    # Un PATCH sin la clave `payload` es un NO-OP. Con `fetch(:payload, {})` a
    # secas devolvería `{}` y pisaría el texto de la mesa con nada: pérdida
    # silenciosa de datos, y la puede causar el propio JS con un cuerpo mal
    # armado. No hay nada que guardar, así que no se guarda.
    return head :no_content unless params.key?(:payload)

    # La fase la decide la SALA y no el cliente: un `idea_id` mandado a una sala
    # de idear se ignora. Si se aceptara, el cliente crearía una fila con idea en
    # esa cara y escaparía al índice de unicidad pensado para ella.
    idea = @link.kind == "evolution" ? workable_idea : nil

    write!(group, idea)
    head :no_content
  end

  private

  def set_link
    @workshop = policy_scope(Workshop).find_by!(id: params[:workshop_id])
    @link = @workshop.workshop_challenges.find_by!(id: params[:sala_id])
  end

  # El mismo idioma que `WorkshopProposalsController`, y por la razón escrita
  # ahí: `policy_scope(Idea)` deja ver a quien participa sólo lo que creó o
  # comparte, y la mesa trabaja la idea de CUALQUIERA de sus integrantes. El 404
  # se conserva: una idea fuera del conjunto no se distingue de una inexistente,
  # así que no confirma que exista.
  def workable_idea
    @workshop.group_of(current_user)
             .workable_ideas(@link.challenge)
             .find_by!(id: params[:idea_id])
  end

  # Contra el formulario declarado: una clave que no es de un campo se descarta.
  # Los `file` quedan afuera —un borrador no guarda archivos, y un `<input
  # type=file>` no sobrevive una recarga en ningún navegador—.
  def payload_params
    step = @link.challenge.pipeline.ideation_step
    keys = step ? step.form_fields.reject { |f| f.field_type == "file" }.map(&:key) : []
    params.require(:payload).permit!.to_h.slice(*keys)
  end

  # La carrera es real: dos personas de la mesa guardando a la vez no encuentran
  # fila, las dos insertan, y el índice parcial levanta `RecordNotUnique`. Se
  # reintenta una vez y ahí la fila ya existe. Un `upsert` sería una sentencia
  # sola, pero saltea las dos validaciones del modelo, que es justo lo que no se
  # quiere saltear.
  def write!(group, idea, intento: 1)
    draft = group.workshop_drafts.find_or_initialize_by(
      workshop_challenge: @link, idea_id: idea&.id
    )
    draft.update!(payload: payload_params, updated_by: current_user,
                  based_on_version_id: idea&.current_version_id)
  rescue ActiveRecord::RecordNotUnique
    raise if intento > 1

    write!(group, idea, intento: 2)
  end
end
```

- [ ] **Step 5: Correr el spec y ver que pasa**

```bash
make spec-file FILE=spec/requests/workshop_drafts_spec.rb
```

Esperado: PASS, 13 ejemplos.

**Un camino que NINGÚN ejemplo de arriba ejercita, dicho para que nadie lo dé por
cubierto:** el `rescue ActiveRecord::RecordNotUnique` de `write!`. El ejemplo «dos
personas dejan UNA fila» es SECUENCIAL —el segundo `find_or_initialize_by`
encuentra la fila y la actualiza—, así que nunca llega al rescate. Probar la
carrera de verdad pide dos conexiones escribiendo a la vez, y los system specs con
navegador se cuelgan contra el pool compartido de Rails (anotado en
`spec/system/smoke_spec.rb`). Queda sin test a propósito: es tres líneas y el
costo de probarlo es desproporcionado — pero **no se afirma que esté cubierto.**

- [ ] **Step 6: Correr el lint de ideas, que es donde este controller podía nacer mal**

```bash
make spec-file FILE=spec/lint/ideas_por_policy_scope_spec.rb
```

Esperado: PASS. El detector pide `\.ideas\b` con punto literal, y en `workable_ideas` el carácter previo a `ideas` es `_`, así que `group.workable_ideas(...)` no lo dispara — igual que en `WorkshopProposalsController`. Si FALLA, **no sumar una excepción**: significa que el controller busca una idea de otra forma, y la forma correcta es la de arriba.

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/workshop_drafts_controller.rb \
        spec/requests/workshop_drafts_spec.rb
git commit -m "La mesa autoguarda lo que teclea, y el endpoint no redirige"
```

---

## Task 3: El texto vuelve al recargar, y se va al mandarlo

**Files:**
- Modify: `app/controllers/workshop_rooms_controller.rb` (`load_ideation`, `load_evolution`)
- Modify: `app/views/workshop_rooms/show.html.haml` (pasar `draft:` a los dos partials)
- Modify: `app/views/workshop_rooms/_ideation.html.haml` (una línea del prellenado)
- Modify: `app/views/workshop_rooms/_evolution.html.haml` (una línea del prellenado)
- Modify: `app/controllers/workshop_ideas_controller.rb` (borrar el borrador)
- Modify: `app/controllers/workshop_proposals_controller.rb` (borrar el borrador, en transacción)
- Create: `spec/requests/workshop_draft_prefill_spec.rb`

**Interfaces:**
- Consumes: `WorkshopDraft` y `WorkshopGroup#workshop_drafts` (Tarea 1); la ruta y el controller de escritura (Tarea 2).
- Produces: `@draft` en `WorkshopRoomsController#show`, pasado a los partials como el local `draft` (puede ser `nil`). La Tarea 4 lo usa para el aviso y el sello.

- [ ] **Step 1: Escribir el spec, que tiene que fallar**

`spec/requests/workshop_draft_prefill_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# El borrador vuelve al recargar, y se va cuando la mesa lo manda. Lo segundo no
# es prolijidad: si el formulario sigue prellenado con lo ya mandado, la mesa lo
# manda de nuevo, que es el defecto que la sala de la mesa existe para arreglar.
RSpec.describe "sala del taller: el borrador se prellena", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, :participant, company: company, user: u)
      u
    end
  end

  let!(:ana) { member("ana@test.dev") }
  let!(:beto) { member("beto@test.dev") }

  let!(:idear) do
    as_company(company) do
      challenge = create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: "ideation", status: "active")
      field = create(:form_field, challenge_step: step, label: "Resumen", field_type: "text")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge, challenge_step: step)
      group = create(:workshop_group, workshop: workshop)
      [ ana, beto ].each { |u| create(:workshop_group_member, workshop_group: group, user: u) }
      { workshop: workshop, link: link, group: group, field: field, challenge: challenge }
    end
  end

  let!(:evolucion) do
    as_company(company) do
      challenge = create(:challenge)
      ideation = create(:challenge_step, challenge: challenge, kind: "ideation", status: "completed")
      field = create(:form_field, challenge_step: ideation, label: "Resumen", field_type: "text")
      step = create(:challenge_step, challenge: challenge, kind: "evolution", status: "active")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge, challenge_step: step)
      group = create(:workshop_group, workshop: workshop)
      create(:workshop_group_member, workshop_group: group, user: ana)
      idea = create(:idea, challenge: challenge, author: ana, status: "active")
      version = create(:idea_version, idea: idea, number: 1, title: "La mía",
                                      payload: { field.key => "lo publicado" })
      idea.update!(current_version: version)
      { workshop: workshop, link: link, group: group, field: field, idea: idea,
        version: version, challenge: challenge }
    end
  end

  describe "en idear" do
    it "sin borrador el formulario arranca vacío" do
      sign_in(ana, company: company)
      get workshop_sala_path(idear[:workshop], idear[:link])

      expect(response.body).to include('name="payload[')
      expect(response.body).not_to include("a medio escribir")
    end

    # Lo que B existe para resolver: la mesa escribió y alguien recargó.
    it "con borrador de la mesa, el formulario trae el texto — aunque lo haya escrito otra persona" do
      as_company(company) do
        create(:workshop_draft, workshop_group: idear[:group], workshop_challenge: idear[:link],
                                updated_by: beto,
                                payload: { idear[:field].key => "a medio escribir" })
      end
      sign_in(ana, company: company)
      get workshop_sala_path(idear[:workshop], idear[:link])

      expect(response.body).to include("a medio escribir")
    end

    it "al crear la idea el borrador se va" do
      as_company(company) do
        create(:workshop_draft, workshop_group: idear[:group], workshop_challenge: idear[:link],
                                updated_by: ana, payload: { idear[:field].key => "a medio escribir" })
      end
      sign_in(ana, company: company)
      post workshop_sala_ideas_path(idear[:workshop], idear[:link]),
           params: { payload: { idear[:field].key => "ya está" } }

      expect(as_company(company) { WorkshopDraft.count }).to eq(0)
    end
  end

  describe "en evolución" do
    it "sin borrador el formulario trae el contenido de la versión vigente" do
      sign_in(ana, company: company)
      get workshop_sala_path(evolucion[:workshop], evolucion[:link], idea: evolucion[:idea].id)

      expect(response.body).to include("lo publicado")
    end

    # El borrador GANA sobre la versión: es el texto que la mesa escribió.
    it "con borrador, el borrador le gana a la versión vigente" do
      as_company(company) do
        create(:workshop_draft, workshop_group: evolucion[:group],
                                workshop_challenge: evolucion[:link], idea: evolucion[:idea],
                                based_on_version: evolucion[:version], updated_by: ana,
                                payload: { evolucion[:field].key => "lo de la mesa" })
      end
      sign_in(ana, company: company)
      get workshop_sala_path(evolucion[:workshop], evolucion[:link], idea: evolucion[:idea].id)

      expect(response.body).to include("lo de la mesa")
      expect(response.body).not_to include('value="lo publicado"')
    end

    it "al mandar la propuesta el borrador se va" do
      as_company(company) do
        create(:workshop_draft, workshop_group: evolucion[:group],
                                workshop_challenge: evolucion[:link], idea: evolucion[:idea],
                                based_on_version: evolucion[:version], updated_by: ana,
                                payload: { evolucion[:field].key => "lo de la mesa" })
      end
      sign_in(ana, company: company)
      post workshop_sala_proposals_path(evolucion[:workshop], evolucion[:link]),
           params: { idea_id: evolucion[:idea].id,
                     payload: { evolucion[:field].key => "lo de la mesa" } }

      as_company(company) do
        expect(WorkshopDraft.count).to eq(0)
        expect(WorkshopProposal.count).to eq(1)
      end
    end

    # El borrador de la idea A no puede prellenar el formulario de la idea B.
    it "el borrador de otra idea no se mezcla" do
      otra = as_company(company) do
        i = create(:idea, challenge: evolucion[:challenge], author: ana, status: "active")
        v = create(:idea_version, idea: i, number: 1, title: "La otra",
                                  payload: { evolucion[:field].key => "contenido de la otra" })
        i.update!(current_version: v)
        create(:workshop_draft, workshop_group: evolucion[:group],
                                workshop_challenge: evolucion[:link], idea: i,
                                based_on_version: v, updated_by: ana,
                                payload: { evolucion[:field].key => "borrador de la otra" })
        i
      end
      sign_in(ana, company: company)
      get workshop_sala_path(evolucion[:workshop], evolucion[:link], idea: evolucion[:idea].id)

      expect(response.body).not_to include("borrador de la otra")
      expect(response.body).to include("lo publicado")
      expect(otra).to be_present
    end
  end
end
```

- [ ] **Step 2: Correrlo y ver que falla**

```bash
make spec-file FILE=spec/requests/workshop_draft_prefill_spec.rb
```

Esperado: FALLAN los cuatro ejemplos de borrador (los dos de «sin borrador» pasan ya, porque describen el comportamiento de hoy).

- [ ] **Step 3: Cargar `@draft` en el controller de la sala**

En `app/controllers/workshop_rooms_controller.rb`, al final de `load_ideation`:

```ruby
    # El borrador es de la MESA: se lee por `@group.workshop_drafts` y no por una
    # búsqueda global. Así la mesa lo ata por construcción, igual que
    # `@group.workshop_proposals`, y no hace falta una policy para el borrador.
    @draft = @group.workshop_drafts.find_by(workshop_challenge: @link, idea_id: nil) if @group && !@group.arrival?
```

Y al final de `load_evolution`:

```ruby
    @draft =
      if @group && !@group.arrival? && @selected_idea
        @group.workshop_drafts.includes(:updated_by, :based_on_version)
              .find_by(workshop_challenge: @link, idea: @selected_idea)
      end
```

La precarga de `updated_by` y `based_on_version` va acá, en el punto de uso: el sello nombra a quien tocó último y el aviso compara la versión.

- [ ] **Step 4: Pasar `draft:` a los dos partials**

En `app/views/workshop_rooms/show.html.haml`, sumar `draft: @draft` a las dos llamadas:

```haml
- when :ideation
  = render "workshop_rooms/ideation", workshop: @workshop, link: @link, group: @group,
                                      mesa_ideas: @mesa_ideas, draft: @draft
- when :evolution
  = render "workshop_rooms/evolution", workshop: @workshop, link: @link, group: @group,
                                       ideas: @workable_ideas, selected: @selected_idea,
                                       proposals: @mesa_proposals, draft: @draft
```

- [ ] **Step 5: Cambiar el prellenado, una línea en cada partial**

En `_ideation.html.haml`, en el `render "ideas/form_fields"`:

```haml
        -# El borrador de la mesa le gana al formulario vacío: es lo que alguien
        -# ya escribió y todavía no mandó.
        = render "ideas/form_fields", fields: link.challenge_step.form_fields, payload: draft&.payload || {}
```

En `_evolution.html.haml`:

```haml
          -# El borrador le gana a la versión vigente: es el texto de la mesa. Si
          -# la versión avanzó desde que se guardó, el aviso de arriba lo dice.
          = render "ideas/form_fields", fields: fields, payload: draft&.payload || selected.payload
```

- [ ] **Step 6: Borrar el borrador al crear la idea**

En `app/controllers/workshop_ideas_controller.rb`, **dentro** del `ActiveRecord::Base.transaction` que ya existe, después del `result = publish.call` y su `raise ActiveRecord::Rollback unless result.ok?`:

```ruby
      # Mandado el borrador, el borrador se va. Si sigue prellenando el
      # formulario, la mesa lo manda de nuevo. Va DENTRO de esta transacción: si
      # la publicación falla y hace rollback, el texto no puede haberse ido.
      group.workshop_drafts.where(workshop_challenge: @link, idea_id: nil).delete_all
```

- [ ] **Step 7: Borrar el borrador al mandar la propuesta, envolviendo en transacción**

En `app/controllers/workshop_proposals_controller.rb`, reemplazar el `WorkshopProposal.create!` suelto por:

```ruby
    # En transacción, que antes no hacía falta: borrar el borrador y crear la
    # propuesta tienen que ser atómicos. Si la creación falla, el texto de la
    # mesa no puede haberse ido.
    ActiveRecord::Base.transaction do
      WorkshopProposal.create!(
        workshop_group: group, idea: idea, challenge_step: @link.challenge_step,
        payload: payload || {}, status: "pending"
      )
      group.workshop_drafts.where(workshop_challenge: @link, idea_id: idea.id).delete_all
    end
```

- [ ] **Step 8: Correr el spec y ver que pasa**

```bash
make spec-file FILE=spec/requests/workshop_draft_prefill_spec.rb
```

Esperado: PASS, 7 ejemplos.

- [ ] **Step 9: Correr los specs de la sala que ya existían, que es donde esto puede romper algo ajeno**

```bash
make spec-file FILE=spec/requests/workshop_sala_idear_spec.rb
make spec-file FILE=spec/requests/workshop_room_spec.rb
make spec-file FILE=spec/requests/workshops_spec.rb
```

Esperado: los tres en PASS. **Ojo con `workshop_room_spec.rb:143`:** ordena la columna de referencia comparando `response.body.index("El desafío")` contra `index("Tu mesa")`, así que cualquier texto nuevo en la columna central que contenga una de esas dos cadenas lo rompe por colisión y no por un defecto real. Si falla ahí, el problema es el copy nuevo, no el orden.

- [ ] **Step 10: Commit**

```bash
git add app/controllers/workshop_rooms_controller.rb \
        app/views/workshop_rooms/show.html.haml \
        app/views/workshop_rooms/_ideation.html.haml \
        app/views/workshop_rooms/_evolution.html.haml \
        app/controllers/workshop_ideas_controller.rb \
        app/controllers/workshop_proposals_controller.rb \
        spec/requests/workshop_draft_prefill_spec.rb
git commit -m "El texto de la mesa vuelve al recargar, y se va al mandarlo"
```

---

## Task 4: El aviso de base vieja y el sello

**Files:**
- Create: `app/views/workshop_rooms/_draft_stamp.html.haml`
- Modify: `app/views/workshop_rooms/_evolution.html.haml` (el aviso, y el sello en `.form-actions`)
- Modify: `app/views/workshop_rooms/_ideation.html.haml` (el sello en `.form-actions`)
- Modify: `config/locales/es.yml`
- Modify: `spec/requests/workshop_draft_prefill_spec.rb` (ejemplos nuevos)

**Interfaces:**
- Consumes: el local `draft` de la Tarea 3.
- Produces: `workshop_rooms/_draft_stamp`, que recibe `draft:` y renderiza un `%p.field-hint#draft-stamp` con los `data-*` que la Tarea 5 lee: `data-saved-text` y `data-failed-text`. UN partial para las dos caras.

- [ ] **Step 1: Escribir los ejemplos, que tienen que fallar**

Al final de `spec/requests/workshop_draft_prefill_spec.rb`, dentro del `describe "en evolución"`:

```ruby
    # La trampa que el handoff no tenía: la mesa teclea sobre v1, el autor acepta
    # otra propuesta y la idea pasa a v2, y alguien de la mesa recarga. Gana el
    # borrador, pero el aviso lo dice: en silencio, la mesa mandaría una
    # propuesta que revierte v2 sin saberlo.
    it "avisa cuando la versión vigente avanzó desde que la mesa guardó" do
      as_company(company) do
        create(:workshop_draft, workshop_group: evolucion[:group],
                                workshop_challenge: evolucion[:link], idea: evolucion[:idea],
                                based_on_version: evolucion[:version], updated_by: ana,
                                payload: { evolucion[:field].key => "lo de la mesa" })
        v2 = create(:idea_version, idea: evolucion[:idea], number: 2, title: "La mía",
                                   payload: { evolucion[:field].key => "lo nuevo" })
        evolucion[:idea].update!(current_version: v2)
      end
      sign_in(ana, company: company)
      get workshop_sala_path(evolucion[:workshop], evolucion[:link], idea: evolucion[:idea].id)

      expect(response.body).to include("v1")
      expect(response.body).to include("v2")
      # Lo que hace útil al aviso: decir CUÁL de los dos se está viendo.
      expect(response.body).to include("lo que tecleó tu mesa")
      # Y el formulario sigue trayendo el texto de la mesa.
      expect(response.body).to include("lo de la mesa")
    end

    # La otra mitad: una guarda que siempre dispara no discrimina.
    it "no avisa cuando la versión no se movió" do
      as_company(company) do
        create(:workshop_draft, workshop_group: evolucion[:group],
                                workshop_challenge: evolucion[:link], idea: evolucion[:idea],
                                based_on_version: evolucion[:version], updated_by: ana,
                                payload: { evolucion[:field].key => "lo de la mesa" })
      end
      sign_in(ana, company: company)
      get workshop_sala_path(evolucion[:workshop], evolucion[:link], idea: evolucion[:idea].id)

      expect(response.body).not_to include("lo que tecleó tu mesa")
    end

    # Review Focus: una idea sin versión vigente deja `based_on_version_id` en
    # NULL. El aviso no aparece —no hay contra qué comparar— y nada revienta.
    # Sin este ejemplo, el día que alguien vuelva `based_on_version` NOT NULL, el
    # borrador de una idea sin versión falla al guardar.
    it "una idea sin versión vigente no avisa y no revienta" do
      sin_version = as_company(company) do
        i = create(:idea, challenge: evolucion[:challenge], author: ana, status: "active")
        create(:workshop_draft, workshop_group: evolucion[:group],
                                workshop_challenge: evolucion[:link], idea: i,
                                based_on_version: nil, updated_by: ana,
                                payload: { evolucion[:field].key => "sobre nada" })
        i
      end
      sign_in(ana, company: company)
      get workshop_sala_path(evolucion[:workshop], evolucion[:link], idea: sin_version.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("sobre nada")
      expect(response.body).not_to include("lo que tecleó tu mesa")
    end

    it "el sello nombra a quien guardó último" do
      as_company(company) do
        create(:workshop_draft, workshop_group: evolucion[:group],
                                workshop_challenge: evolucion[:link], idea: evolucion[:idea],
                                based_on_version: evolucion[:version], updated_by: ana,
                                payload: { evolucion[:field].key => "lo de la mesa" })
      end
      sign_in(ana, company: company)
      get workshop_sala_path(evolucion[:workshop], evolucion[:link], idea: evolucion[:idea].id)

      expect(response.body).to include(ana.name)
      expect(response.body).to include("Guardado por")
    end
```

- [ ] **Step 2: Correrlos y ver que fallan**

```bash
make spec-file FILE=spec/requests/workshop_draft_prefill_spec.rb
```

Esperado: FALLAN los cuatro nuevos.

- [ ] **Step 3: Sumar las cadenas al locale**

En `config/locales/es.yml`, bajo `flow:`, al lado de `workshop_proposal_statuses`:

```yaml
    workshop_draft:
      saved: "Guardado ahora."
      failed: "No se pudo guardar: copiá el texto antes de salir."
      stamp: "Guardado por %{name} hace %{ago}."
```

- [ ] **Step 4: Escribir el partial del sello**

`app/views/workshop_rooms/_draft_stamp.html.haml`:

```haml
-# El sello del autoguardado: al lado del botón, porque es donde se mira antes de
-# mandar.
-#
-# UN partial para las dos caras: dos copias del mismo markup divergen y nadie se
-# entera. El nombre de quien tocó último es lo que hace honesto el caso de dos
-# personas tecleando: sin websockets no hay aviso en vivo, pero quien recarga ve
-# que no está solo.
-#
-# Los dos `data-*` son lo que el JS escribe cuando guarda o cuando falla. Van en
-# la VISTA y no en el JS, igual que `data-live` en `arrival_live.js`: las
-# palabras viven en el locale y el JS no sabe de talleres.
%p.field-hint#draft-stamp{ data: { saved_text: t("flow.workshop_draft.saved"),
                                   failed_text: t("flow.workshop_draft.failed") } }
  - if draft
    = t("flow.workshop_draft.stamp", name: draft.updated_by.name,
                                     ago: time_ago_in_words(draft.updated_at))
```

- [ ] **Step 5: Sumar el aviso de base vieja y el sello en `_evolution.html.haml`**

El aviso va **arriba** de la tarjeta «Proponer cambios», después del bloque de `file_fields`:

```haml
    -# Gana el borrador, y el aviso lo dice. Que ganara la versión tiraría trabajo
    -# de la mesa sin preguntar —el autor aceptando algo desde su teléfono le
    -# borraría el texto en medio de la sesión—, y que ganara en silencio haría
    -# que la mesa mande una propuesta que revierte la versión nueva sin saberlo.
    - if draft&.based_on_version && draft.based_on_version_id != selected.current_version_id
      -# `alert` es display:grid con grid-auto-flow:column: todo dentro de UN
      -# `%div`, o los hijos se reparten en columnas.
      .alert.alert-soft.alert-warning
        %div
          = "El formulario muestra lo que tecleó tu mesa sobre #{draft.based_on_version.label}, pero la versión vigente ya es #{selected.current_version.label}: "
          = link_to "mirá el contenido nuevo", challenge_idea_path(link.challenge, selected)
          = " antes de proponer."
```

Y el sello dentro de `.form-actions`, antes del `submit_tag`:

```haml
          .form-actions
            = render "workshop_rooms/draft_stamp", draft: draft
            = submit_tag "Proponer", class: "btn btn-primary"
```

- [ ] **Step 6: Sumar el sello en `_ideation.html.haml`**

```haml
        .form-actions
          = render "workshop_rooms/draft_stamp", draft: draft
          = submit_tag "Crear borrador", class: "btn btn-primary"
```

- [ ] **Step 7: Correr el spec y ver que pasa**

```bash
make spec-file FILE=spec/requests/workshop_draft_prefill_spec.rb
```

Esperado: PASS, 11 ejemplos.

- [ ] **Step 8: Correr los specs de pantalla que miran títulos y orden**

```bash
make spec-file FILE=spec/requests/workshop_room_spec.rb
make spec-file FILE=spec/requests/pantalla_del_modulo_spec.rb
```

Esperado: PASS. El sello y el aviso son texto nuevo en la columna CENTRAL de la sala, así que acá es donde `workshop_room_spec.rb:143` puede colisionar: compara `response.body.index("El desafío")` contra `index("Tu mesa")`. Ninguna cadena nueva de esta tarea contiene «El desafío» ni «Tu mesa» —se eligieron así—, pero si falla, **el arreglo es el copy, no el ejemplo**.

- [ ] **Step 9: Commit**

```bash
git add app/views/workshop_rooms/_draft_stamp.html.haml \
        app/views/workshop_rooms/_evolution.html.haml \
        app/views/workshop_rooms/_ideation.html.haml \
        config/locales/es.yml spec/requests/workshop_draft_prefill_spec.rb
git commit -m "El borrador dice de cuándo es, y avisa si la version avanzo"
```

---

## Task 5: El autoguardado en el navegador, y la guarda que lo ve

**Files:**
- Create: `app/javascript/workshop_draft.js`
- Modify: `app/javascript/application.js` (el import)
- Modify: `app/views/workshop_rooms/_ideation.html.haml` (los `data-*` del form)
- Modify: `app/views/workshop_rooms/_evolution.html.haml` (los `data-*` del form)
- Modify: `script/capture_screens.js` (la guarda `[DRAFT]`, su contador y su piso)

**Interfaces:**
- Consumes: la ruta `workshop_sala_draft_path` (Tarea 2) y el `#draft-stamp` con sus dos `data-*` (Tarea 4).
- Produces: nada que otra tarea consuma. Es la última pieza funcional.

- [ ] **Step 1: Poner los `data-*` en el form de idear**

En `_ideation.html.haml`:

```haml
      -# `data-draft-url` es lo que enciende el autoguardado: el JS no sabe ni
      -# tiene que saber si esta sala admite trabajo. Mismo principio que
      -# `data-live` en `arrival_live.js`.
      = form_with url: workshop_sala_ideas_path(workshop, link), multipart: true,
                  data: { draft_url: workshop_sala_draft_path(workshop, link), debounce: 2000 } do
```

- [ ] **Step 2: Poner los `data-*` en el form de evolución**

En `_evolution.html.haml`. Acá viaja además el id de la idea, porque la identidad del borrador la incluye:

```haml
        = form_with url: workshop_sala_proposals_path(workshop, link),
                    data: { draft_url: workshop_sala_draft_path(workshop, link),
                            draft_idea: selected.id, debounce: 2000 } do
```

- [ ] **Step 3: Escribir el JS**

`app/javascript/workshop_draft.js`:

```javascript
// Lo que la mesa teclea en la sala se guarda solo, para que un refresh no se lo
// lleve. NO publica nada: el borrador vive en `workshop_drafts` y mandarlo sigue
// siendo apretar el botón.
//
// El ciclo de vida es el mismo par que `arrival_live.js` e `islands.js`
// —`turbo:load` para arrancar, `turbo:before-render` para limpiar—: un
// mecanismo, no tres. Sin el limpiado, navegar a otra pantalla deja un
// temporizador pidiendo contra una pantalla que ya no está.
//
// Sin `setInterval`, a diferencia de `arrival_live.js`: ahí el dato cambia en el
// servidor y hay que ir a buscarlo; acá cambia en el navegador y lo que hace
// falta es esperar a que pare de cambiar.
let timer = null;
let form = null;
let sucio = false;

// Sólo hay timeouts acá, nunca un interval: `alTeclear` reinicia la espera en
// cada tecla. Un `clearInterval` haría creer que hay un ciclo que no existe.
function stop() {
  if (timer === null) return;
  clearTimeout(timer);
  timer = null;
}

function sello() {
  return document.getElementById('draft-stamp');
}

// El cuerpo se arma a mano y NO con `new FormData(form)`: un FormData crudo
// incluye el `<input type=file>`, así que subiría el archivo elegido cada dos
// segundos. Un borrador no guarda archivos —y un file input no sobrevive una
// recarga en ningún navegador—.
function cuerpo() {
  const datos = new URLSearchParams();
  const idea = form.dataset.draftIdea;
  if (idea) datos.append('idea_id', idea);
  for (const campo of form.querySelectorAll('[name^="payload["]')) {
    if (campo.type === 'file') continue;
    if ((campo.type === 'checkbox' || campo.type === 'radio') && !campo.checked) continue;
    if (campo.multiple && campo.tagName === 'SELECT') {
      for (const opcion of campo.selectedOptions) datos.append(campo.name, opcion.value);
      continue;
    }
    datos.append(campo.name, campo.value);
  }
  return datos;
}

async function guardar({ keepalive = false } = {}) {
  if (!form || !sucio) return;
  sucio = false;
  const token = document.querySelector('meta[name="csrf-token"]')?.content;
  try {
    const res = await fetch(form.dataset.draftUrl, {
      method: 'PATCH',
      headers: { 'X-CSRF-Token': token, 'Content-Type': 'application/x-www-form-urlencoded' },
      body: cuerpo(),
      keepalive
    });
    // Un fallo se DICE, no se traga. Un autoguardado que falla en silencio es
    // peor que no tenerlo: la mesa confía y pierde todo.
    if (!res.ok) throw new Error(res.status);
    const s = sello();
    if (s) s.textContent = s.dataset.savedText;
  } catch {
    const s = sello();
    if (s) s.textContent = s.dataset.failedText;
    stop();
    form = null;
  }
}

function alTeclear() {
  sucio = true;
  stop();
  timer = setTimeout(guardar, Number(form.dataset.debounce) || 2000);
}

function start() {
  stop();
  form = document.querySelector('form[data-draft-url]');
  if (!form) return;
  form.addEventListener('input', alTeclear);
  // Mandar es publicar: el borrador lo borra el servidor en la misma
  // transacción, así que un guardado en vuelo no tiene que pisarlo después.
  form.addEventListener('submit', () => { sucio = false; stop(); });
}

// Irse de la pantalla no puede llevarse los últimos dos segundos. `keepalive`
// deja el pedido en vuelo aunque el documento se vaya.
function descargar() {
  stop();
  guardar({ keepalive: true });
}

addEventListener('turbo:load', start);
addEventListener('turbo:before-render', descargar);
addEventListener('visibilitychange', () => { if (document.hidden) descargar(); });
```

- [ ] **Step 4: Importarlo**

En `app/javascript/application.js`, debajo del import de `arrival_live`:

```javascript
// Lo que la mesa teclea en la sala de un taller se guarda solo.
import './workshop_draft';
```

- [ ] **Step 5: COMPILAR, antes de cualquier verificación en navegador**

```bash
make yarn-build
grep -c "draftUrl" app/assets/builds/application-build.js
```

Esperado: el `grep` devuelve **al menos 1**. Si devuelve 0, el bundle no tiene el archivo y todo lo que siga valida una app distinta de la que se escribió — es exactamente lo que pasó con `llegada_en_vivo.js`, donde la suite daba 1558 ejemplos en verde y el bundle no tenía una sola referencia.

- [ ] **Step 6: Correr `make screens` LIMPIO, antes de escribir la guarda**

```bash
make screens
```

Esperado: verde. **Esto no es opcional:** una guarda nueva se prueba contra un baseline que funciona. La primera mutación de `[LIVE]` corrió sobre el bundle viejo, donde el estado sano y el mutado daban el MISMO resultado, así que no probó nada.

- [ ] **Step 7: Escribir la guarda `[DRAFT]`**

En `script/capture_screens.js`. Declarar el contador arriba, junto a `liveMeasurements`:

```javascript
// En cuántas de las dos caras de la sala `[DRAFT]` midió que el texto vuelve
// después de recargar. Las dos, o la guarda dejó de ver una.
let draftMeasurements = 0;
```

Y el piso, junto a los otros:

```javascript
// EXACTO y no flojo: son las dos caras de la sala, idear y evolución, y no hay
// una tercera. Un piso flojo no cazaría que una dejó de medirse.
const PISO_DE_BORRADORES = 2;
```

La función, al lado de las otras guardas:

```javascript
// Lo único que un spec de Ruby no puede ver: el bundle, el temporizador y el
// endpoint pueden estar los tres en verde y el texto no volver.
//
// Tipea, espera el debounce, RECARGA, y mira que el texto esté. La recarga es el
// punto: sin ella se estaría probando que el navegador conserva lo que acabás de
// escribir, que es cierto sin autoguardado.
async function revisarBorrador(page, nombre) {
  const campo = page.locator('form[data-draft-url] input[name^="payload["], form[data-draft-url] textarea[name^="payload["]').first();
  if (!(await campo.count())) {
    failures++;
    console.error(`[DRAFT] ${nombre}: el formulario de la sala no tiene campo con autoguardado`);
    return;
  }
  const marca = `borrador-${Date.now()}`;
  const previo = await campo.inputValue();
  await campo.fill(marca);
  const espera = Number(await page.locator('form[data-draft-url]').first().getAttribute('data-debounce')) || 2000;
  await page.waitForTimeout(espera + 1500);

  // El sello tiene que haber cambiado: es el acuse de que el PATCH respondió.
  const sello = (await page.locator('#draft-stamp').first().innerText()).trim();
  if (!sello) {
    failures++;
    console.error(`[DRAFT] ${nombre}: el sello quedó vacío, así que el autoguardado no acusó nada`);
  }

  await page.reload({ waitUntil: 'domcontentloaded' });
  const vuelto = await page.locator('form[data-draft-url] input[name^="payload["], form[data-draft-url] textarea[name^="payload["]').first().inputValue();
  if (vuelto !== marca) {
    failures++;
    console.error(`[DRAFT] ${nombre}: después de recargar el campo dice «${vuelto}» y la mesa había escrito «${marca}» (antes decía «${previo}»)`);
    return;
  }
  draftMeasurements++;
}
```

- [ ] **Step 8: Llamarla en las dos caras**

En el bloque de `25-taller-sala-idear`, después del `await capturar(page, '25-taller-sala-idear');`:

```javascript
      await revisarBorrador(page, 'sala de idear');
```

Y en el bloque de `26b-taller-idea-elegida`, después del `await capturar(page, '26b-taller-idea-elegida');`:

```javascript
        await revisarBorrador(page, 'sala de evolución');
```

Las dos **después** de la captura: `revisarBorrador` escribe en el campo y recarga, así que antes le cambiaría la foto.

- [ ] **Step 9: Sumar el contador a la línea final y su piso**

En el `console.log` del resumen, sumar ` · [DRAFT] ${draftMeasurements} caras medidas` al final. Y el chequeo del piso, junto a los otros:

```javascript
  if (draftMeasurements < PISO_DE_BORRADORES) {
    failures++;
    console.error(`[DRAFT] sólo ${draftMeasurements} de ${PISO_DE_BORRADORES} caras de la sala midieron el autoguardado: la guarda dejó de ver una`);
  }
```

- [ ] **Step 10: Correr `make screens` y ver la guarda en verde**

```bash
make yarn-build && make screens
```

Esperado: verde, y la línea final con `[DRAFT] 2 caras medidas`. Si dice 1 o 0, la guarda no está viendo una de las caras: **no bajar el piso**, averiguar por qué.

- [ ] **Step 11: Mutar y VER FALLAR — la guarda no vale nada sin esto**

```bash
cp app/javascript/workshop_draft.js /tmp/workshop_draft.js.bak
# Romper el debounce: que nunca mande.
sed -i 's/if (!form || !sucio) return;/if (true) return;/' app/javascript/workshop_draft.js
make yarn-build && make screens
```

Esperado: **FALLA** con `[DRAFT] … después de recargar el campo dice …`, en las dos caras.

Restaurar **con `cp` del backup y no con `git checkout`** —`git checkout` desharía el arreglo entero y no la mutación—:

```bash
cp /tmp/workshop_draft.js.bak app/javascript/workshop_draft.js
make yarn-build && make screens
```

Esperado: verde otra vez, `[DRAFT] 2`.

- [ ] **Step 12: Segunda mutación: romper el prellenado del servidor**

La primera mutación prueba el camino de escritura. Esta prueba el de lectura, que es otra mitad:

```bash
cp app/views/workshop_rooms/_ideation.html.haml /tmp/_ideation.html.haml.bak
sed -i 's/payload: draft&.payload || {}/payload: {}/' app/views/workshop_rooms/_ideation.html.haml
make screens
```

Esperado: **FALLA** en `sala de idear` y **no** en `sala de evolución` — que es lo que prueba que la guarda mide cada cara por separado.

```bash
cp /tmp/_ideation.html.haml.bak app/views/workshop_rooms/_ideation.html.haml
make screens
```

- [ ] **Step 13: La suite completa**

```bash
make spec
```

Esperado: verde. El número de ejemplos sube respecto de los 1633 de la base.

- [ ] **Step 14: Commit**

```bash
git add app/javascript/workshop_draft.js app/javascript/application.js \
        app/views/workshop_rooms/_ideation.html.haml \
        app/views/workshop_rooms/_evolution.html.haml \
        script/capture_screens.js
git commit -m "El autoguardado corre en el navegador, y una guarda lo ve recargar"
```

---

## Task 6: El seed no arrastra el borrador del recorrido, y la documentación lo dice

**Files:**
- Modify: `db/seeds.rb` (borrar los borradores sembrados por el recorrido)
- Modify: `CLAUDE.md` (la guarda nueva, el contador, lo que no cubre)
- Create: `handoff.md` (reemplaza el de la sesión anterior)

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: nada de código.

- [ ] **Step 1: El seed borra los borradores que dejó el recorrido**

Esto cierra un efecto de la Tarea 5 que **su propia verificación no puede ver**: `revisarBorrador` corre DESPUÉS de `capturar`, así que la corrida que lo introduce saca fotos limpias. En la corrida SIGUIENTE, la captura se toma antes de la guarda y retrata el formulario con el texto que dejó la corrida anterior. Es el mismo patrón que Lucía Llegada, que el seed borra al lado de los talleres por el mismo motivo.

En `db/seeds.rb`, junto al borrado de Lucía Llegada:

```ruby
  # El recorrido de `make screens` teclea en las dos salas para probar el
  # autoguardado (`[DRAFT]`), y eso deja un `workshop_draft` por cara. La guarda
  # usa una marca distinta cada vez, así que no le molesta — pero las capturas
  # `25` y `26b` se toman ANTES de la guarda, así que en la segunda corrida
  # retratarían el texto de la primera. Mismo motivo por el que se borra a Lucía
  # Llegada.
  WorkshopDraft.delete_all
```

- [ ] **Step 2: Resembrar y correr el recorrido dos veces seguidas**

```bash
docker compose exec app bin/rails db:seed
make yarn-build && make screens
make screens
```

Esperado: las dos corridas en verde con `[DRAFT] 2`. Es la única forma de ver el efecto del Step 1: una sola corrida no lo muestra.

- [ ] **Step 3: Documentar en `CLAUDE.md`**

Tres lugares, y nada más:

1. **En la lista de guardas de `make screens`**, sumar `[DRAFT]`: tipea en las dos caras de la sala, espera el debounce, recarga y mira que el texto vuelva. Decir que es lo único que ve el camino completo —el bundle, el temporizador y el endpoint pueden estar los tres en verde y el texto no volver—, y que está probada con dos mutaciones: una del lado del JS y otra del prellenado del servidor, porque son dos mitades distintas.
2. **En «Nueve de las guardas cuentan cuánto midieron»**, que pasan a ser **diez**: sumar `[DRAFT]` a la enumeración y su piso a la lista de números, diciendo que es **EXACTO** como `PISO_DE_BANDAS` y por qué —son las dos caras de la sala y no hay una tercera, así que un piso flojo no cazaría que una dejó de medirse—. Actualizar el conteo en la frase y en la línea del resumen.
3. **En la sección del taller**, un párrafo nuevo con lo que la spec decidió y que no se lee del código: que el borrador es de la MESA y no de cada persona —y que es lo único que sobrevive a que al escribiente se le muera la máquina—; que gana el borrador sobre la versión vigente CON aviso, y por qué las otras dos opciones estaban mal; que un `PATCH` sin `payload` es un no-op a propósito, porque con `fetch(:payload, {})` pisaría el texto con nada; que la fase la decide la sala y un `idea_id` mandado a idear se ignora; y que la cláusula nueva del barrido de `AssignGroups` acompaña a la de propuestas por LA MISMA razón de carrera, mientras el guarda de arriba NO se extendió a borradores a propósito.

Y sumar a la lista de lo que **no** tiene vigilancia: **el autoguardado no tiene aviso en vivo de que otra persona de la mesa está escribiendo.** Lo más cercano es el sello al recargar. Es a propósito —el push pediría el canal autenticado y scopeado por empresa que la spec de la lista de llegada ya descartó— pero que nadie lo dé por cubierto.

- [ ] **Step 4: Verificación final completa**

```bash
make spec
make yarn-build && make screens
```

Esperado: suite verde con más ejemplos que los 1633 de la base; recorrido verde con los diez contadores sobre su piso.

- [ ] **Step 5: Escribir el handoff**

`handoff.md`, cinco secciones: objetivo, estado actual (con el número de ejemplos y los diez contadores copiados de la salida, no de memoria), archivos y cambios, intentos fallidos (incluidos los de verdad, no una lista limpia), próximos pasos. **Verificar el estado del remoto con `gh api repos/ribarahonaa/innk_flow/commits/master`** y no con `git rev-parse origin/master`, que lee una foto local.

- [ ] **Step 6: Commit**

```bash
git add db/seeds.rb CLAUDE.md handoff.md
git commit -m "Handoff: el borrador de la mesa, y la guarda que lo ve recargar"
```

---

## Notas de ejecución

**Correr en rama, no en `master`.** Las ramas van en el directorio del proyecto y **no en un worktree**: Docker está atado a él.

```bash
git checkout -b borrador-de-mesa
```

**El push va por HTTPS con el helper de `gh`.** No hay clave SSH en este entorno.

**Al terminar cada tarea, PARAR y pedir permiso antes de la siguiente.**

**Dos trampas de este repo que muerden en este plan concretamente:**

- **La indentación de un comentario HAML puede romper el bloque de abajo.** Al insertar varias líneas de `-#` arriba de un `each` o de un `if`, la primera y las siguientes tienen que quedar al MISMO nivel, o el cuerpo deja de estar adentro. Pasó de verdad y se llevó dos ejemplos que estaban en verde. **Leer el archivo con `sed -n` o `cat -A` después de insertar un bloque de comentarios, no confiar en que el reemplazo preservó el nivel.**
- **`ideas` no tiene columna `title`.** `Idea#title` sale de `current_version&.title` y sin versión publicada devuelve `"(sin título)"` para TODAS. Los specs de este plan publican versión con título propio donde comparan, o asevera sobre la URL.
