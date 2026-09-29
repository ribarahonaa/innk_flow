# El taller — plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un taller es un evento que abarca N desafíos en fase de idear o de evolución, donde la gente trabaja en mesas: en idear postula ideas nuevas, en evolución propone versiones que su autor publica.

**Architecture:** Aditivo. El taller NO es un `kind` del pipeline: el motor tiene un módulo activo por construcción y no se toca. Cinco tablas nuevas y un valor más en `IdeaVersion::ACTOR_TYPES`. La visibilidad por mesa no se programa: crear un borrador crea la `Idea` con el resto de la mesa como `idea_contributors`, y `IdeaPolicy::Scope` hace el resto.

**Tech Stack:** Rails 7.1, Postgres (uuid v7, FKs compuestas), Pundit, HAML, RSpec, Playwright. Todo en Docker.

**Spec:** `docs/superpowers/specs/2026-09-28-modulo-de-taller-design.md`

## Global Constraints

- **El código va en inglés; los comentarios y los mensajes de commit, en español.**
  **Y este plan se contradice a sí mismo:** varios de sus bloques de código de
  ejemplo usan variables y métodos privados en español (`hermanas`, `taller`,
  `mesa`, `persona`, `resultado`, `motivo`, `mesa_de`, `aceptar`…). Es un
  defecto del plan, no una excepción. **Al implementar, traducí todo
  identificador nuevo al inglés** —variables locales, métodos, helpers de
  spec— y dejá los **comentarios y los strings en español**, que es donde van.
  La regla de `CLAUDE.md` rige para lo que se escribe de ahora en más; lo que
  ya existe en el repo en español no se toca ni se renombra al pasar.
- **Toda tabla y toda columna nueva va en inglés, sin excepción.**
- Todo corre en Docker. **Nunca `bundle exec` en el host.**
- **Los specs corren con `make spec*`**, que usa `app_test`. `docker compose exec app bundle exec rspec` deja `RAILS_ENV=development` y **todos los request specs dan 403 «Blocked hosts»**.
- `schema_format = :sql`: después de migrar, **commiteá `db/structure.sql`**.
- Las FKs entre tablas con `company_id` van por **`add_tenant_fk`**, nunca `add_foreign_key` simple. `spec/tenancy/schema_spec.rb` introspecciona el catálogo y falla si aparece una simple.
- **Pundit, no CanCanCan.** Cada policy declara su `Scope` explícitamente (`class Scope < ApplicationPolicy::Scope; end`): Pundit usa `const_get(:Scope, false)` y no la hereda.
- **Zeitwerk: una constante por archivo.**
- En los specs, **toda lectura del dominio va dentro de `as_company(company) { ... }`**, incluido un `.new` (toca el `default_scope`).
- **Lo que no se ve da 404, no 403.** Se busca por `policy_scope(...).find_by!`, nunca `Model.find_by!`.
- Las factories viven todas en `spec/factories/core.rb`.
- **Los commits NO llevan línea `Co-Authored-By`.**
- No hay linter configurado.

## Review Focus

Cinco cosas que el spec implica y que ninguna tarea ejercita por su cuenta. Cada línea tiene su test agregado a la tarea que es dueña del código.

1. **Una persona en dos mesas del mismo taller** debe rechazarse — hoy nada lo impide y partiría la visibilidad en dos. → Task 1.
2. **Abrir un taller cuyo desafío avanzó entre el armado y la apertura**: ese desafío se rechaza con motivo y el taller no se abre a medias. → Task 4.
3. **Aceptar una propuesta cuya ronda de evolución ya cerró**: no se puede; escribiría una versión dentro de una conversación terminada. → Task 9.
4. **Un gestor suma al taller un desafío que no le asignaron**: 404, no 403 — un 403 es un oráculo de existencia. → Task 3.
5. **Quien participa de un desafío vinculado pero no está en ninguna mesa**: el taller le da 404. Participar del desafío no es una invitación. → Task 3.

---

### Task 1: Las cinco tablas y los cinco modelos

**Files:**
- Create: `db/migrate/<ts>_create_workshops.rb`
- Create: `app/models/workshop.rb`, `app/models/workshop_challenge.rb`, `app/models/workshop_group.rb`, `app/models/workshop_group_member.rb`, `app/models/workshop_proposal.rb`
- Modify: `spec/factories/core.rb`
- Test: `spec/tenancy/workshop_spec.rb`
- Modify: `db/structure.sql` (generado)

**Interfaces:**
- Produces: `Workshop` (`name`, `mode`, `status`, `scheduled_at`, `created_by`, `has_many :workshop_challenges`, `has_many :workshop_groups`), `WorkshopChallenge` (`workshop`, `challenge`, `challenge_step` opcional, `status`, `closed_reason`, `closed_at`), `WorkshopGroup` (`workshop`, `name`, `has_many :members`), `WorkshopGroupMember` (`workshop_group`, `user`), `WorkshopProposal` (`workshop_group`, `idea`, `challenge_step`, `payload`, `status`, `reviewed_by`, `reviewed_at`).
- Consumes: `Flow::MigrationHelpers#tenant_table` y `#add_tenant_fk`, `TenantScoped`.

- [ ] **Step 1: Escribir el spec de tenencia que falla**

Crear `spec/tenancy/workshop_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# Las cinco tablas del taller, contra las mismas reglas que el resto del
# dominio: sin tenant la query revienta, y una persona no puede estar en dos
# mesas del mismo taller.
RSpec.describe "tenencia del taller" do
  let!(:acme) { without_tenant { create(:company, slug: "acme") } }
  let!(:otra) { without_tenant { create(:company, slug: "otra") } }

  it "revienta sin tenant en contexto" do
    expect { Workshop.count }.to raise_error(TenantScoped::MissingTenant)
  end

  it "no deja a una persona en dos mesas del mismo taller" do
    as_company(acme) do
      taller = create(:workshop)
      persona = Flow::Tenant.bypass! { create(:user) }
      create(:workshop_group_member, workshop_group: create(:workshop_group, workshop: taller), user: persona)

      segunda = create(:workshop_group, workshop: taller)
      repetida = WorkshopGroupMember.new(workshop_group: segunda, user: persona)

      expect(repetida).not_to be_valid
      expect(repetida.errors[:user_id].join).to include("ya está en otra mesa")
    end
  end

  it "deja a la misma persona en mesas de talleres distintos" do
    as_company(acme) do
      persona = Flow::Tenant.bypass! { create(:user) }
      create(:workshop_group_member, workshop_group: create(:workshop_group), user: persona)
      otra_mesa = create(:workshop_group, workshop: create(:workshop))

      expect(WorkshopGroupMember.new(workshop_group: otra_mesa, user: persona)).to be_valid
    end
  end

  it "rechaza atar una mesa a un taller de otra empresa" do
    ajeno = as_company(otra) { create(:workshop) }

    as_company(acme) do
      mesa = WorkshopGroup.new(workshop_id: ajeno.id, name: "Mesa 1")
      expect(mesa).not_to be_valid
    end
  end
end
```

- [ ] **Step 2: Correr y verlo fallar**

Run: `make spec-file FILE=spec/tenancy/workshop_spec.rb`
Expected: FAIL — `NameError: uninitialized constant Workshop`.

- [ ] **Step 3: Escribir la migración**

```ruby
# frozen_string_literal: true

class CreateWorkshops < ActiveRecord::Migration[7.1]
  include Flow::MigrationHelpers

  def change
    tenant_table :workshops do |t|
      t.string :name, null: false
      t.string :mode, null: false, default: "group"
      t.string :status, null: false, default: "draft"
      t.datetime :scheduled_at
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_check_constraint :workshops, "mode IN ('individual','group')", name: "workshops_mode_check"
    add_check_constraint :workshops, "status IN ('draft','open','closed')", name: "workshops_status_check"

    tenant_table :workshop_challenges do |t|
      t.uuid :workshop_id, null: false
      t.uuid :challenge_id, null: false
      # Nulo mientras el taller es borrador: se resuelve al abrir, contra el
      # módulo que esté activo en ese momento.
      t.uuid :challenge_step_id
      t.string :status, null: false, default: "open"
      t.string :closed_reason
      t.datetime :closed_at
      t.timestamps
    end
    add_index :workshop_challenges, %i[workshop_id challenge_id], unique: true
    add_check_constraint :workshop_challenges, "status IN ('open','closed')",
                         name: "workshop_challenges_status_check"

    tenant_table :workshop_groups do |t|
      t.uuid :workshop_id, null: false
      t.string :name, null: false
      t.timestamps
    end
    add_index :workshop_groups, :workshop_id

    tenant_table :workshop_group_members do |t|
      t.uuid :workshop_group_id, null: false
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.timestamps
    end
    add_index :workshop_group_members, %i[workshop_group_id user_id], unique: true

    tenant_table :workshop_proposals do |t|
      t.uuid :workshop_group_id, null: false
      t.uuid :idea_id, null: false
      t.uuid :challenge_step_id, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :status, null: false, default: "pending"
      t.references :reviewed_by, type: :uuid, foreign_key: { to_table: :users }
      t.datetime :reviewed_at
      t.timestamps
    end
    add_index :workshop_proposals, :idea_id
    add_check_constraint :workshop_proposals, "status IN ('pending','accepted','rejected')",
                         name: "workshop_proposals_status_check"

    # Todas compuestas: Postgres rechaza atar una fila de la empresa A a un
    # padre de la B. `add_foreign_key` simple acá haría fallar
    # spec/tenancy/schema_spec.rb, y con razón.
    add_tenant_fk :workshop_challenges,    :workshops,       column: :workshop_id
    add_tenant_fk :workshop_challenges,    :challenges,      column: :challenge_id
    add_tenant_fk :workshop_challenges,    :challenge_steps, column: :challenge_step_id, on_delete: :nullify
    add_tenant_fk :workshop_groups,        :workshops,       column: :workshop_id
    add_tenant_fk :workshop_group_members, :workshop_groups, column: :workshop_group_id
    add_tenant_fk :workshop_proposals,     :workshop_groups, column: :workshop_group_id
    add_tenant_fk :workshop_proposals,     :ideas,           column: :idea_id
    add_tenant_fk :workshop_proposals,     :challenge_steps, column: :challenge_step_id
  end
end
```

**Ojo con `on_delete: :nullify`:** el helper acota a `SET NULL (challenge_step_id)` porque sin acotar nulea también `company_id`, que es NOT NULL. Es el bug que se arregló en `37bb173`; el helper ya lo hace, pero no lo cambies.

- [ ] **Step 4: Escribir los cinco modelos**

`app/models/workshop.rb`:

```ruby
# frozen_string_literal: true

# Un taller: una sesión de trabajo que abarca N desafíos.
#
# NO es un módulo del flujo. El motor tiene un módulo activo por construcción
# (`Flow::Pipeline#active_step`), y un taller es un evento que se monta sobre
# la fase que cada desafío ya está corriendo.
class Workshop < ApplicationRecord
  include TenantScoped

  MODES = %w[individual group].freeze
  STATUSES = %w[draft open closed].freeze

  belongs_to :created_by, class_name: "User", optional: true
  has_many :workshop_challenges, dependent: :destroy
  has_many :challenges, through: :workshop_challenges
  has_many :workshop_groups, dependent: :destroy

  validates :name, presence: true
  validates :mode, inclusion: { in: MODES }
  validates :status, inclusion: { in: STATUSES }

  STATUSES.each { |s| define_method("#{s}?") { status == s } }

  def individual? = mode == "individual"
end
```

`app/models/workshop_challenge.rb`:

```ruby
# frozen_string_literal: true

# El vínculo de un taller con UN desafío, y con el módulo concreto contra el
# que trabaja.
#
# Apunta al módulo y no a la fase: de ahí salen el modo de la sala (el `kind`),
# el cierre automático (el módulo dejó de estar activo) y el
# `challenge_step_id` correcto para las propuestas —que es lo que evita
# mezclar dos rondas de evolución—.
class WorkshopChallenge < ApplicationRecord
  include TenantScoped

  STATUSES = %w[open closed].freeze
  # Las dos únicas fases sobre las que un taller tiene algo que hacer.
  WORKABLE_KINDS = %w[ideation evolution].freeze

  belongs_to :workshop
  belongs_to :challenge
  belongs_to :challenge_step, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :challenge_id, uniqueness: { scope: :workshop_id }

  STATUSES.each { |s| define_method("#{s}?") { status == s } }

  # Perezoso a propósito: nada se engancha en `advance!`. El taller se entera
  # de que el desafío avanzó; no interviene.
  def workable? = status == "open" && challenge_step.present? && challenge_step.active?

  def kind = challenge_step&.kind
end
```

`app/models/workshop_group.rb`:

```ruby
# frozen_string_literal: true

# Una mesa. En modo individual también existe: es una mesa de una persona.
# Un mecanismo y un gancho, en vez de dos caminos en el código.
class WorkshopGroup < ApplicationRecord
  include TenantScoped

  belongs_to :workshop
  has_many :workshop_group_members, dependent: :destroy
  has_many :members, through: :workshop_group_members, source: :user

  validates :name, presence: true
end
```

`app/models/workshop_group_member.rb`:

```ruby
# frozen_string_literal: true

# Estar convocado ES estar en una mesa: no hay una lista aparte. Dos fuentes
# para «quién está en este taller» divergen, y la primera vez que difieran una
# de las dos estaría mintiendo.
class WorkshopGroupMember < ApplicationRecord
  include TenantScoped

  belongs_to :workshop_group
  belongs_to :user

  validates :user_id, uniqueness: { scope: :workshop_group_id }
  validate :one_group_per_workshop

  private

  # La mesa es la unidad de visibilidad. Alguien en dos mesas del mismo taller
  # la partiría en dos, y dejaría sin respuesta «¿de qué mesa es esta idea?».
  def one_group_per_workshop
    return if workshop_group.nil? || user_id.blank?

    hermanas = WorkshopGroup.where(workshop_id: workshop_group.workshop_id).where.not(id: workshop_group_id)
    return unless WorkshopGroupMember.where(workshop_group_id: hermanas, user_id: user_id).exists?

    errors.add(:user_id, "ya está en otra mesa de este taller")
  end
end
```

`app/models/workshop_proposal.rb`:

```ruby
# frozen_string_literal: true

# Lo que una mesa propone sobre una idea que ya existe, en un módulo de
# evolución. El autor la acepta y ahí se publica la versión.
class WorkshopProposal < ApplicationRecord
  include TenantScoped

  STATUSES = %w[pending accepted rejected].freeze

  belongs_to :workshop_group
  belongs_to :idea
  belongs_to :challenge_step
  belongs_to :reviewed_by, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :pending_review, -> { where(status: "pending") }

  STATUSES.each { |s| define_method("#{s}?") { status == s } }

  # Aceptar publica una versión con `source_step` de ESTA ronda. Publicar
  # dentro de una ronda cerrada escribiría en una conversación terminada, así
  # que una propuesta se vence con su ronda. Mismo predicado perezoso que
  # `WorkshopChallenge#workable?`: no hay estado `expired` que alguien tenga
  # que escribir.
  def actionable? = pending? && challenge_step.active?
end
```

- [ ] **Step 5: Sumar las factories**

Al final de `spec/factories/core.rb`, antes del `end`:

```ruby
  factory :workshop do
    sequence(:name) { |n| "Taller #{n}" }
    mode { "group" }
    status { "draft" }
  end

  factory :workshop_challenge do
    workshop
    challenge
  end

  factory :workshop_group do
    workshop
    sequence(:name) { |n| "Mesa #{n}" }
  end

  factory :workshop_group_member do
    workshop_group
    user { Flow::Tenant.bypass! { create(:user) } }
  end

  factory :workshop_proposal do
    workshop_group
    idea
    challenge_step
    payload { {} }
    status { "pending" }
  end
```

- [ ] **Step 6: Migrar y verificar**

```bash
docker compose exec app bin/rails db:migrate
```

Run: `make spec-file FILE=spec/tenancy/workshop_spec.rb`
Expected: PASS (4 ejemplos).

Run: `make spec-file FILE=spec/tenancy/schema_spec.rb`
Expected: PASS — introspecciona el catálogo, así que las ocho FKs nuevas entran solas. Si falla nombrando una tabla de taller, es que quedó una FK simple.

- [ ] **Step 7: Commit**

```bash
git add db/migrate db/structure.sql app/models spec/tenancy/workshop_spec.rb spec/factories/core.rb
git commit -m "Las cinco tablas del taller, con tenencia y FKs compuestas"
```

---

### Task 2: `IdeaVersion` acepta el actor `workshop`

**Files:**
- Create: `db/migrate/<ts>_allow_workshop_actor_on_idea_versions.rb`
- Modify: `app/models/idea_version.rb:11`
- Test: `spec/models/idea_version_spec.rb`

**Interfaces:**
- Produces: `IdeaVersion::ACTOR_TYPES == %w[human ai workshop]`.

- [ ] **Step 1: Escribir el test que falla**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe IdeaVersion do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  # El CHECK de Postgres es una segunda puerta: sin la migración, el modelo
  # valida y la base rechaza igual, con un error truncado.
  it "acepta una versión escrita por un taller" do
    as_company(company) do
      idea = create(:idea)
      version = idea.versions.new(number: 1, title: "T", payload: {}, actor_type: "workshop")

      expect(version).to be_valid
      expect { version.save! }.not_to raise_error
    end
  end
end
```

- [ ] **Step 2: Correr y verlo fallar**

Run: `make spec-file FILE=spec/models/idea_version_spec.rb`
Expected: FAIL — el modelo lo rechaza por `inclusion`.

- [ ] **Step 3: La migración del CHECK**

```ruby
# frozen_string_literal: true

# Sumar un valor a un enum que tiene CHECK de Postgres son DOS lugares. Sin
# este cambio la fila revienta con PG::CheckViolation antes de crearse, y el
# error llega truncado — es lo que pasó con `ai_runs.purpose`.
class AllowWorkshopActorOnIdeaVersions < ActiveRecord::Migration[7.1]
  def up
    remove_check_constraint :idea_versions, name: "idea_versions_actor_type_check"
    add_check_constraint :idea_versions,
                         "actor_type IN ('human','ai','workshop')",
                         name: "idea_versions_actor_type_check"
  end

  def down
    remove_check_constraint :idea_versions, name: "idea_versions_actor_type_check"
    add_check_constraint :idea_versions,
                         "actor_type IN ('human','ai')",
                         name: "idea_versions_actor_type_check"
  end
end
```

- [ ] **Step 4: El modelo**

En `app/models/idea_version.rb`, línea 11:

```ruby
  ACTOR_TYPES = %w[human ai workshop].freeze
```

- [ ] **Step 5: Migrar, correr, verificar el `down`**

```bash
docker compose exec app bin/rails db:migrate
docker compose exec app bin/rails db:rollback   # el down tiene que correr limpio
docker compose exec app bin/rails db:migrate
```

Run: `make spec-file FILE=spec/models/idea_version_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add db/migrate db/structure.sql app/models/idea_version.rb spec/models/idea_version_spec.rb
git commit -m "Una versión puede venir de un taller"
```

---

### Task 3: `WorkshopPolicy` y su `Scope`

**Files:**
- Create: `app/policies/workshop_policy.rb`
- Test: `spec/policies/workshop_policy_spec.rb`

**Interfaces:**
- Consumes: `Workshop`, `WorkshopGroupMember` (Task 1); `ApplicationPolicy#administers?`, `#manager?`, `Scope#resolve`.
- Produces: `WorkshopPolicy#show?`, `#create?`, `#update?`, `#add_challenge?(challenge)`, `#manage_groups?`, `#work?`; `WorkshopPolicy::Scope`.

- [ ] **Step 1: Escribir el spec que falla**

```ruby
# frozen_string_literal: true

require "rails_helper"

# El reparto completo. Existe porque abrir un permiso de más no rompe ningún
# otro test: es el mismo motivo de `spec/policies/gestor_administra_spec.rb`.
RSpec.describe WorkshopPolicy do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(role)
    without_tenant do
      u = create(:user)
      create(:membership, role.to_sym, company: company, user: u)
    end
  end

  let(:admin) { member(:admin) }
  let(:gestor) { member(:gestor) }
  let(:participante) { member(:participant) }

  it "sin membresía, el scope no devuelve nada" do
    as_company(company) do
      create(:workshop)
      expect(WorkshopPolicy::Scope.new(nil, Workshop).resolve.count).to eq(0)
    end
  end

  it "quien administra la empresa ve y arma talleres" do
    as_company(company) do
      taller = create(:workshop)
      expect(WorkshopPolicy.new(admin, taller).show?).to be(true)
      expect(WorkshopPolicy.new(admin, taller).update?).to be(true)
    end
  end

  it "quien está en una mesa ve el taller pero no lo arma" do
    as_company(company) do
      taller = create(:workshop)
      create(:workshop_group_member, workshop_group: create(:workshop_group, workshop: taller),
                                     user: participante.user)

      expect(WorkshopPolicy.new(participante, taller).show?).to be(true)
      expect(WorkshopPolicy.new(participante, taller).update?).to be(false)
    end
  end

  # Review Focus 5: participar del desafío NO es una invitación.
  it "quien participa de un desafío vinculado, sin mesa, NO ve el taller" do
    as_company(company) do
      desafio = create(:challenge)
      taller = create(:workshop)
      create(:workshop_challenge, workshop: taller, challenge: desafio)

      expect(WorkshopPolicy.new(participante, taller).show?).to be(false)
      expect(WorkshopPolicy::Scope.new(participante, Workshop).resolve).not_to include(taller)
    end
  end

  # Review Focus 4: el gestor sólo suma los desafíos que le asignaron.
  it "el gestor suma al taller sólo sus desafíos" do
    as_company(company) do
      mio = create(:challenge)
      ajeno = create(:challenge)
      ChallengeGestor.create!(challenge: mio, user: gestor.user)
      taller = create(:workshop)

      expect(WorkshopPolicy.new(gestor, taller).add_challenge?(mio)).to be(true)
      expect(WorkshopPolicy.new(gestor, taller).add_challenge?(ajeno)).to be(false)
    end
  end
end
```

- [ ] **Step 2: Correr y verlo fallar**

Run: `make spec-file FILE=spec/policies/workshop_policy_spec.rb`
Expected: FAIL — `uninitialized constant WorkshopPolicy`.

- [ ] **Step 3: Escribir la policy**

```ruby
# frozen_string_literal: true

# NO nace vacía. Una policy sin nada propio hereda `show? = membership.present?`,
# o sea «cualquiera de la empresa lee esto»: es exactamente la fuga que tenía
# `CriteriaSetPolicy`, y la encontró una auditoría, no un test.
class WorkshopPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if membership.nil?
      return scope.all if membership.manages_challenges?

      # Estar convocado es estar en una mesa. Participar de un desafío
      # vinculado no alcanza: un taller es por convocatoria.
      mesas = WorkshopGroup.joins(:workshop_group_members)
                           .where(workshop_group_members: { user_id: membership.user_id })
                           .select(:workshop_id)
      suyos = scope.where(id: mesas)

      return suyos unless membership.gestor?

      # El gestor además ve los talleres que tocan sus desafíos: los lleva.
      asignados = ChallengeGestor.where(user_id: membership.user_id).select(:challenge_id)
      porque_administra = WorkshopChallenge.where(challenge_id: asignados).select(:workshop_id)

      scope.where(id: mesas).or(scope.where(id: porque_administra))
    end
  end

  def show? = Scope.new(membership, Workshop).resolve.exists?(id: record.id)

  def create? = membership.present? && membership.manages_challenges?
  def update? = administra_alguno?
  def destroy? = update?
  def manage_groups? = update?

  # Sumar un desafío se pregunta por el DESAFÍO, no por el taller: un gestor
  # arma un taller con los suyos y no puede colar uno ajeno.
  def add_challenge?(challenge) = administers?(challenge)

  # Trabajar en la sala es de quien está en una mesa. Quien administra entra
  # igual: lleva el taller y ve todas las mesas.
  def work?
    return false if membership.nil?
    return true if administra_alguno?

    WorkshopGroupMember.joins(:workshop_group)
                       .where(workshop_groups: { workshop_id: record.id }, user_id: membership.user_id)
                       .exists?
  end

  private

  def administra_alguno?
    return false if membership.nil?
    return true if manager?

    record.workshop_challenges.any? { |wc| administers?(wc.challenge) }
  end
end
```

- [ ] **Step 4: Correr y verificar**

Run: `make spec-file FILE=spec/policies/workshop_policy_spec.rb`
Expected: PASS (5 ejemplos).

- [ ] **Step 5: Commit**

```bash
git add app/policies/workshop_policy.rb spec/policies/workshop_policy_spec.rb
git commit -m "WorkshopPolicy: el taller es por convocatoria, no por desafío"
```

---

### Task 4: El ciclo de vida — abrir, resolver el módulo, cerrar

**Files:**
- Create: `app/lib/flow/workshops/open.rb`
- Create: `app/lib/flow/workshops/close.rb`
- Test: `spec/lib/flow/workshops/open_spec.rb`

**Interfaces:**
- Consumes: `Workshop`, `WorkshopChallenge` (Task 1); `Flow::Pipeline#active_step`.
- Produces: `Flow::Workshops::Open.new(workshop).call → Result(ok:, rejected:, errors:)` donde `rejected` son los `WorkshopChallenge` que no se pudieron abrir; `Flow::Workshops::Close.new(workshop).call`.

- [ ] **Step 1: Escribir el spec que falla**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flow::Workshops::Open do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def desafio_con(kind)
    challenge = create(:challenge)
    step = create(:challenge_step, challenge: challenge, kind: kind, status: "active")
    [challenge, step]
  end

  it "resuelve el módulo activo de cada desafío al abrir" do
    as_company(company) do
      challenge, step = desafio_con("ideation")
      taller = create(:workshop)
      vinculo = create(:workshop_challenge, workshop: taller, challenge: challenge)

      resultado = described_class.new(taller).call

      expect(resultado.ok).to be(true)
      expect(taller.reload).to be_open
      expect(vinculo.reload.challenge_step_id).to eq(step.id)
    end
  end

  # Review Focus 2: entre el armado y la apertura, el desafío pudo avanzar.
  it "rechaza el desafío cuyo módulo activo no es idear ni evolución, y abre igual el resto" do
    as_company(company) do
      bueno, = desafio_con("evolution")
      malo, = desafio_con("evaluation")
      taller = create(:workshop)
      v_bueno = create(:workshop_challenge, workshop: taller, challenge: bueno)
      v_malo = create(:workshop_challenge, workshop: taller, challenge: malo)

      resultado = described_class.new(taller).call

      expect(resultado.ok).to be(true)
      expect(resultado.rejected.map(&:id)).to eq([v_malo.id])
      expect(v_malo.reload).to be_closed
      expect(v_malo.closed_reason).to include("Evaluación")
      expect(v_bueno.reload).to be_open
      expect(taller.reload).to be_open
    end
  end

  it "no abre un taller sin ningún desafío trabajable" do
    as_company(company) do
      malo, = desafio_con("reporting")
      taller = create(:workshop)
      create(:workshop_challenge, workshop: taller, challenge: malo)

      resultado = described_class.new(taller).call

      expect(resultado.ok).to be(false)
      expect(taller.reload).to be_draft
    end
  end
end
```

- [ ] **Step 2: Correr y verlo fallar**

Run: `make spec-file FILE=spec/lib/flow/workshops/open_spec.rb`
Expected: FAIL — `uninitialized constant Flow::Workshops`.

- [ ] **Step 3: Escribir `Flow::Workshops::Open`**

```ruby
# frozen_string_literal: true

module Flow
  module Workshops
    # Abrir un taller resuelve, de una vez, contra qué módulo trabaja en cada
    # desafío. Es el mismo late binding del pipeline: `config` guarda la
    # intención y `resolved_config` se escribe una vez al arrancar.
    #
    # La fase se verifica ACÁ y no al sumar el desafío: entre que el taller se
    # arma y se abre, el desafío pudo avanzar.
    class Open
      Result = Data.define(:ok, :rejected, :errors) do
        def ok? = ok
      end

      def initialize(workshop)
        @workshop = workshop
      end

      def call
        return Result.new(ok: false, rejected: [], errors: ["El taller ya no está en borrador."]) unless @workshop.draft?

        rejected = []

        @workshop.with_lock do
          @workshop.workshop_challenges.includes(:challenge).each do |link|
            step = Flow::Pipeline.new(link.challenge).active_step

            if step && WorkshopChallenge::WORKABLE_KINDS.include?(step.kind)
              link.update!(challenge_step: step, status: "open")
            else
              link.update!(status: "closed", closed_at: Time.current, closed_reason: motivo(step))
              rejected << link
            end
          end

          # Un taller sin una sola sala no es un taller: abrirlo dejaría una
          # pantalla vacía con estado «abierto», que es peor que el error.
          if @workshop.workshop_challenges.reload.none?(&:open?)
            raise ActiveRecord::Rollback
          end

          @workshop.update!(status: "open")
        end

        return Result.new(ok: false, rejected: rejected, errors: [sin_salas]) unless @workshop.reload.open?

        Result.new(ok: true, rejected: rejected, errors: [])
      end

      private

      def motivo(step)
        return "El desafío no tiene ningún módulo en curso." if step.nil?

        "El desafío está en #{I18n.t("flow.kinds.#{step.kind}")}, " \
          "y un taller sólo trabaja sobre idear o evolución."
      end

      def sin_salas = "Ningún desafío del taller está en idear ni en evolución."
    end
  end
end
```

- [ ] **Step 4: Escribir `Flow::Workshops::Close`**

```ruby
# frozen_string_literal: true

module Flow
  module Workshops
    # Cerrar el taller cierra todos sus vínculos. Lo que quedó sin postular
    # sigue siendo borrador de su mesa: los `idea_contributors` persisten.
    class Close
      def initialize(workshop, reason: "El taller se cerró.")
        @workshop = workshop
        @reason = reason
      end

      def call
        @workshop.with_lock do
          @workshop.workshop_challenges.where(status: "open").find_each do |link|
            link.update!(status: "closed", closed_at: Time.current, closed_reason: @reason)
          end
          @workshop.update!(status: "closed")
        end
        true
      end
    end
  end
end
```

- [ ] **Step 5: Correr y verificar**

Run: `make spec-file FILE=spec/lib/flow/workshops/open_spec.rb`
Expected: PASS (3 ejemplos).

- [ ] **Step 6: Commit**

```bash
git add app/lib/flow/workshops spec/lib/flow/workshops
git commit -m "Abrir un taller resuelve contra qué módulo trabaja en cada desafío"
```

---

### Task 5: Rutas, controller y las pantallas de armado

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/workshops_controller.rb`
- Create: `app/controllers/workshop_groups_controller.rb`
- Create: `app/views/workshops/index.html.haml`, `new.html.haml`, `show.html.haml`
- Create: `app/views/workshops/_armado.html.haml`
- Modify: `config/locales/es.yml`
- Test: `spec/requests/workshops_spec.rb`

**Interfaces:**
- Consumes: `WorkshopPolicy` (Task 3), `Flow::Workshops::Open` y `::Close` (Task 4).
- Produces: rutas `workshops_path`, `workshop_path(w)`, `open_workshop_path(w)`, `close_workshop_path(w)`, `workshop_workshop_groups_path(w)`; `WorkshopsController#show` publica `@links`, `@groups` y `@my_group`.

- [ ] **Step 1: Escribir el request spec que falla**

```ruby
# frozen_string_literal: true

require "rails_helper"

# Lo que no se ve da 404, NUNCA 403: un 403 confirma que existe.
RSpec.describe "talleres", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email, role)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, role.to_sym, company: company, user: u)
      u
    end
  end

  let!(:admin) { member("admin@test.dev", :admin) }
  let!(:paula) { member("paula@test.dev", :participant) }
  let!(:taller) { as_company(company) { create(:workshop) } }

  it "a quien no está convocado le da 404, no 403" do
    sign_in(paula, company: company)
    get workshop_path(taller)
    expect(response).to have_http_status(:not_found)
  end

  it "quien administra lo abre" do
    sign_in(admin, company: company)
    get workshop_path(taller)
    expect(response).to have_http_status(:ok)
  end
end
```

- [ ] **Step 2: Correr y verlo fallar**

Run: `make spec-file FILE=spec/requests/workshops_spec.rb`
Expected: FAIL — ruta indefinida.

- [ ] **Step 3: Las rutas**

En `config/routes.rb`, al nivel de `resources :challenges`:

```ruby
  # El taller NO cuelga de un desafío: abarca varios. Por eso es de primer
  # nivel y no está anidado.
  resources :workshops, only: %i[index new create show update destroy] do
    member do
      post :open
      post :close
    end
    resources :workshop_groups, only: %i[create destroy], path: "mesas"
  end
```

- [ ] **Step 4: El controller**

```ruby
# frozen_string_literal: true

class WorkshopsController < ApplicationController
  before_action :set_workshop, only: %i[show update destroy open close]

  def index
    @workshops = policy_scope(Workshop).order(scheduled_at: :desc, created_at: :desc)
  end

  def new
    @workshop = Workshop.new
    authorize @workshop, :create?
    @challenges = policy_scope(Challenge)
  end

  def create
    @workshop = Workshop.new(workshop_params.merge(created_by: current_user))
    authorize @workshop, :create?

    if @workshop.save
      redirect_to workshop_path(@workshop), notice: "Taller creado."
    else
      @challenges = policy_scope(Challenge)
      flash.now[:alert] = @workshop.errors.full_messages.to_sentence
      render :new, status: :unprocessable_content
    end
  end

  def show
    authorize @workshop, :show?
    @links = @workshop.workshop_challenges.includes(:challenge, :challenge_step)
    @groups = @workshop.workshop_groups.includes(:members)
    @my_group = @workshop.workshop_groups.joins(:workshop_group_members)
                         .find_by(workshop_group_members: { user_id: current_user.id })
  end

  def open
    authorize @workshop, :update?
    resultado = Flow::Workshops::Open.new(@workshop).call

    if resultado.ok?
      aviso = "Taller abierto."
      aviso += " #{Flow::Texto.contar(resultado.rejected.size, 'desafío')} quedaron afuera." if resultado.rejected.any?
      redirect_to workshop_path(@workshop), notice: aviso
    else
      redirect_to workshop_path(@workshop), alert: resultado.errors.to_sentence
    end
  end

  def close
    authorize @workshop, :update?
    Flow::Workshops::Close.new(@workshop).call
    redirect_to workshop_path(@workshop), notice: "Taller cerrado."
  end

  def update
    authorize @workshop, :update?
    # Sumar un desafío se pregunta por el DESAFÍO, no por el taller.
    Array(params[:challenge_ids]).each do |id|
      challenge = policy_scope(Challenge).find_by(id: id)
      next if challenge.nil? || !policy(@workshop).add_challenge?(challenge)

      @workshop.workshop_challenges.find_or_create_by!(challenge: challenge)
    end
    redirect_to workshop_path(@workshop), notice: "Taller actualizado."
  end

  def destroy
    authorize @workshop, :destroy?
    @workshop.destroy!
    redirect_to workshops_path, notice: "Taller eliminado."
  end

  private

  # `policy_scope(...).find_by!` y no `Workshop.find_by!`: así lo que no se ve
  # da 404 y no 403, que sería un oráculo de existencia.
  def set_workshop = @workshop = policy_scope(Workshop).find_by!(id: params[:id])

  def workshop_params = params.require(:workshop).permit(:name, :mode, :scheduled_at)
end
```

- [ ] **Step 5: Las vistas de armado**

`app/views/workshops/show.html.haml` arranca con el encabezado y, **detrás de UNA variable calculada arriba**, el bloque de armado. La forma es la que el repo ya fijó (`steps/_criterios_editor.html.haml`): nada que no sea el encabezado se sirve sin la guarda, y la guarda es una variable, no un predicado escrito en cada bloque.

```haml
- puede_armar = policy(@workshop).update?
- content_for :title, @workshop.name

.card
  .card-body
    %h1.page-title= @workshop.name
    %p.muted= t("flow.workshop_statuses.#{@workshop.status}")

- if puede_armar
  = render "workshops/armado", workshop: @workshop, links: @links, groups: @groups
```

- [ ] **Step 6: Las claves de `es.yml`**

Bajo `flow:`, en `config/locales/es.yml`. **Sin estas claves los rótulos salen en inglés** por el fallback `humanize`, que es como `test_idea` se quedó sin traducir:

```yaml
    workshop_statuses:
      draft: "Borrador"
      open: "Abierto"
      closed: "Cerrado"
    workshop_modes:
      individual: "Individual"
      group: "Por mesas"
```

- [ ] **Step 7: Correr y verificar**

Run: `make spec-file FILE=spec/requests/workshops_spec.rb`
Expected: PASS (2 ejemplos).

- [ ] **Step 8: Commit**

```bash
git add config/routes.rb app/controllers/workshops_controller.rb app/views/workshops config/locales/es.yml spec/requests/workshops_spec.rb
git commit -m "El taller se arma: rutas, pantalla y el 404 por policy_scope"
```

---

### Task 6: Las mesas y la convocatoria

**Files:**
- Create: `app/lib/flow/workshops/convoke.rb`
- Create: `app/controllers/workshop_groups_controller.rb`
- Create: `app/controllers/workshop_convocations_controller.rb`
- Create: `app/views/workshops/_mesas.html.haml`
- Modify: `config/routes.rb`
- Test: `spec/lib/flow/workshops/convoke_spec.rb`

**Interfaces:**
- Consumes: `Workshop#individual?`, `WorkshopGroup`, `WorkshopGroupMember` (Task 1); `WorkshopPolicy#manage_groups?` (Task 3).
- Produces: `Flow::Workshops::Convoke.new(workshop, user, group: nil).call → Result(ok:, member:, errors:)`; rutas `workshop_workshop_groups_path(w)` y `convoke_workshop_path(w)`.

Sin esta tarea nadie puede entrar a una sala: `WorkshopPolicy#work?` pregunta
por la mesa, y las mesas no existirían.

- [ ] **Step 1: Escribir el spec que falla**

```ruby
# frozen_string_literal: true

require "rails_helper"

# Convocar ES sumar a una mesa: no hay lista aparte. En modo individual no hay
# mesa que elegir, así que se crea la de esa persona en el acto — y por eso el
# resto del código nunca tiene dos caminos.
RSpec.describe Flow::Workshops::Convoke do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }
  let(:ana) { without_tenant { create(:user, email: "ana@test.dev") } }

  it "en modo individual crea la mesa de esa persona" do
    as_company(company) do
      taller = create(:workshop, mode: "individual")

      resultado = described_class.new(taller, ana).call

      expect(resultado.ok).to be(true)
      expect(taller.workshop_groups.count).to eq(1)
      expect(taller.workshop_groups.first.members).to eq([ana])
    end
  end

  it "en modo por mesas exige una mesa" do
    as_company(company) do
      taller = create(:workshop, mode: "group")

      resultado = described_class.new(taller, ana).call

      expect(resultado.ok).to be(false)
      expect(resultado.errors.join).to include("mesa")
      expect(taller.workshop_groups.count).to eq(0)
    end
  end

  it "convocar dos veces no crea una mesa huérfana" do
    as_company(company) do
      taller = create(:workshop, mode: "individual")
      described_class.new(taller, ana).call

      resultado = described_class.new(taller, ana).call

      expect(resultado.ok).to be(false)
      expect(taller.workshop_groups.count).to eq(1)
    end
  end
end
```

- [ ] **Step 2: Correr y verlo fallar**

Run: `make spec-file FILE=spec/lib/flow/workshops/convoke_spec.rb`
Expected: FAIL — `uninitialized constant Flow::Workshops::Convoke`.

- [ ] **Step 3: El servicio**

```ruby
# frozen_string_literal: true

module Flow
  module Workshops
    # Convocar es sumar a una mesa. No hay una lista de convocados aparte:
    # dos fuentes para «quién está en este taller» divergen, y la primera vez
    # que difieran una de las dos estaría mintiendo.
    class Convoke
      Result = Data.define(:ok, :member, :errors) do
        def ok? = ok
      end

      def initialize(workshop, user, group: nil)
        @workshop = workshop
        @user = user
        @group = group
      end

      def call
        # Antes de crear nada: en modo individual, crear la mesa y recién
        # después chocar con la validación dejaría una mesa vacía colgada.
        return ya_convocada if convocada?

        grupo = @group
        grupo ||= @workshop.individual? ? mesa_propia : nil
        return sin_mesa if grupo.nil?

        member = WorkshopGroupMember.new(workshop_group: grupo, user: @user)
        return Result.new(ok: true, member: member, errors: []) if member.save

        Result.new(ok: false, member: nil, errors: member.errors.full_messages)
      end

      private

      def convocada?
        WorkshopGroupMember.joins(:workshop_group)
                           .where(workshop_groups: { workshop_id: @workshop.id }, user_id: @user.id)
                           .exists?
      end

      # `users.name` es NOT NULL, así que siempre hay con qué nombrarla.
      def mesa_propia = @workshop.workshop_groups.create!(name: @user.name)

      def ya_convocada = Result.new(ok: false, member: nil, errors: ["Ya está en una mesa de este taller."])
      def sin_mesa = Result.new(ok: false, member: nil, errors: ["Hay que elegir una mesa."])
    end
  end
end
```

- [ ] **Step 4: Rutas y controllers**

En `config/routes.rb`, **dentro del `member do` que ya creó Task 5**. El `to:`
explícito es obligatorio: `post :convoke` a secas mapea a `workshops#convoke`,
no al controller que esta tarea escribe.

```ruby
      post   :convoke, to: "workshop_convocations#create"
      delete :dismiss, to: "workshop_convocations#destroy"
```

```ruby
# frozen_string_literal: true

class WorkshopConvocationsController < ApplicationController
  before_action :set_workshop

  def create
    authorize @workshop, :manage_groups?
    user = User.find_by(id: params[:user_id])
    grupo = @workshop.workshop_groups.find_by(id: params[:workshop_group_id])
    resultado = Flow::Workshops::Convoke.new(@workshop, user, group: grupo).call

    if resultado.ok?
      redirect_to workshop_path(@workshop), notice: "Convocada a la mesa."
    else
      redirect_to workshop_path(@workshop), alert: resultado.errors.to_sentence
    end
  end

  def destroy
    authorize @workshop, :manage_groups?
    WorkshopGroupMember.joins(:workshop_group)
                       .where(workshop_groups: { workshop_id: @workshop.id }, user_id: params[:user_id])
                       .destroy_all
    redirect_to workshop_path(@workshop), notice: "Ya no está convocada."
  end

  private

  def set_workshop = @workshop = policy_scope(Workshop).find_by!(id: params[:id])
end
```

```ruby
# frozen_string_literal: true

class WorkshopGroupsController < ApplicationController
  before_action :set_workshop

  def create
    authorize @workshop, :manage_groups?
    @workshop.workshop_groups.create!(name: params[:name].presence || siguiente_nombre)
    redirect_to workshop_path(@workshop), notice: "Mesa creada."
  end

  def destroy
    authorize @workshop, :manage_groups?
    @workshop.workshop_groups.find_by!(id: params[:id]).destroy!
    redirect_to workshop_path(@workshop), notice: "Mesa eliminada."
  end

  private

  def set_workshop = @workshop = policy_scope(Workshop).find_by!(id: params[:workshop_id])

  def siguiente_nombre = "Mesa #{@workshop.workshop_groups.count + 1}"
end
```

**Ojo:** las acciones `convoke`/`dismiss` son miembro de `workshops`, así que
el controller las toma por `params[:id]`; las de `workshop_groups` están
anidadas y las toman por `params[:workshop_id]`. Son distintos a propósito.

- [ ] **Step 5: Correr y verificar**

Run: `make spec-file FILE=spec/lib/flow/workshops/convoke_spec.rb`
Expected: PASS (3 ejemplos).

- [ ] **Step 6: Commit**

```bash
git add app/lib/flow/workshops/convoke.rb app/controllers/workshop_groups_controller.rb app/controllers/workshop_convocations_controller.rb app/views/workshops config/routes.rb spec/lib/flow/workshops/convoke_spec.rb
git commit -m "Convocar es sumar a una mesa, y en individual la mesa es de uno"
```

---

### Task 7: La sala, cara «idear»

**Files:**
- Create: `app/controllers/workshop_ideas_controller.rb`
- Create: `app/views/workshops/_sala_idear.html.haml`
- Modify: `config/routes.rb`
- Test: `spec/requests/workshop_sala_idear_spec.rb`

**Interfaces:**
- Consumes: `WorkshopChallenge#workable?`, `WorkshopGroup#members` (Task 1), `WorkshopGroup` poblado por Task 6; `Flow::Ideas::PublishVersion`.
- Produces: `POST /workshops/:workshop_id/salas/:workshop_challenge_id/ideas` → crea la `Idea` en `draft` con la mesa como contribuyentes.

- [ ] **Step 1: Escribir el spec que falla**

```ruby
# frozen_string_literal: true

require "rails_helper"

# El truco que hace barato todo lo demás: la visibilidad por mesa NO se
# programa. Crear el borrador con la mesa como idea_contributors hace que
# IdeaPolicy::Scope responda sola.
RSpec.describe "sala del taller: idear", type: :request do
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

  # Un solo armado para los tres ejemplos: taller abierto sobre un desafío en
  # idear, con una mesa de ana y beto. Carla queda afuera a propósito.
  let!(:escenario) do
    as_company(company) do
      challenge = create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: "ideation", status: "active")
      campo = create(:form_field, challenge_step: step, label: "Resumen", field_type: "text")
      taller = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: taller, challenge: challenge, challenge_step: step)
      mesa = create(:workshop_group, workshop: taller)
      [ana, beto].each { |u| create(:workshop_group_member, workshop_group: mesa, user: u) }
      { challenge: challenge, step: step, campo: campo, taller: taller, link: link }
    end
  end

  def postear_borrador(texto = "Una idea")
    post workshop_sala_ideas_path(escenario[:taller], escenario[:link]),
         params: { payload: { escenario[:campo].key => texto } }
  end

  it "el borrador nace con el resto de la mesa como contribuyentes" do
    sign_in(ana, company: company)
    postear_borrador

    as_company(company) do
      idea = Idea.order(:created_at).last
      expect(idea.author_id).to eq(ana.id)
      expect(idea).to be_draft
      expect(idea.contributors.map(&:id)).to contain_exactly(beto.id)
    end
  end

  # La regla NO es nueva: es `IdeaPolicy::Scope`. Este ejemplo prueba que
  # sembrar los contribuyentes en el momento de crear alcanza para que la
  # visibilidad por mesa funcione sin escribir una excepción.
  it "quien no está en la mesa no ve el borrador de esa mesa" do
    sign_in(ana, company: company)
    postear_borrador
    idea = as_company(company) { Idea.order(:created_at).last }

    sign_in(carla, company: company)
    get challenge_idea_path(escenario[:challenge], idea)

    expect(response).to have_http_status(:not_found)
  end

  it "no deja crear si el vínculo dejó de ser trabajable" do
    as_company(company) { escenario[:step].update!(status: "completed") }
    sign_in(ana, company: company)

    expect { postear_borrador }.not_to(change { as_company(company) { Idea.count } })
    expect(flash[:alert]).to include("avanzó de fase")
  end
end
```

- [ ] **Step 2: Correr y verlo fallar**

Run: `make spec-file FILE=spec/requests/workshop_sala_idear_spec.rb`
Expected: FAIL — ruta indefinida.

- [ ] **Step 3: Ruta**

```ruby
    # La sala de UN desafío dentro del taller. El id es el del VÍNCULO, no el
    # del desafío: el vínculo es el que sabe contra qué módulo se trabaja.
    resources :workshop_challenges, only: [], path: "salas", as: :sala do
      resources :ideas, only: %i[create], controller: "workshop_ideas"
    end
```

- [ ] **Step 4: El controller**

```ruby
# frozen_string_literal: true

# Crear una idea desde la sala de un taller.
#
# ÚNICA diferencia con postular desde el desafío: la mesa entera queda como
# `idea_contributors` desde el minuto cero. Eso es lo que hace que «veo las
# ideas de mi mesa y no las de las otras» sea `IdeaPolicy::Scope` tal como
# está, sin una excepción nueva a la regla que este repo más audita.
class WorkshopIdeasController < ApplicationController
  before_action :set_link

  def create
    authorize @workshop, :work?
    return rechazar unless @link.workable? && @link.kind == "ideation"

    idea = nil
    ActiveRecord::Base.transaction do
      idea = @link.challenge.ideas.create!(author: current_user, status: "draft", origin: "human")
      mesa_de(current_user)&.members&.each do |persona|
        next if persona.id == current_user.id

        idea.idea_contributors.create!(user: persona)
      end
      Flow::Ideas::PublishVersion.new(
        idea, payload: params[:payload], author: current_user,
              source_step: @link.challenge_step, change_note: "Creada en el taller «#{@workshop.name}»"
      ).call
    end

    redirect_to workshop_path(@workshop), notice: "Borrador creado en la sala."
  end

  private

  def set_link
    @workshop = policy_scope(Workshop).find_by!(id: params[:workshop_id])
    @link = @workshop.workshop_challenges.find_by!(id: params[:sala_id])
  end

  def mesa_de(user)
    @workshop.workshop_groups.joins(:workshop_group_members)
             .find_by(workshop_group_members: { user_id: user.id })
  end

  def rechazar
    redirect_to workshop_path(@workshop),
                alert: "Esta sala ya no admite trabajo: el desafío avanzó de fase."
  end
end
```

- [ ] **Step 5: Correr y verificar**

Run: `make spec-file FILE=spec/requests/workshop_sala_idear_spec.rb`
Expected: PASS (3 ejemplos).

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/workshop_ideas_controller.rb app/views/workshops spec/requests/workshop_sala_idear_spec.rb
git commit -m "Sala de idear: el borrador nace con su mesa, y la visibilidad cae sola"
```

---

### Task 8: La sala, cara «evolución» — crear la propuesta

**Files:**
- Create: `app/controllers/workshop_proposals_controller.rb`
- Create: `app/views/workshops/_sala_evolucion.html.haml`
- Modify: `config/routes.rb`
- Test: `spec/requests/workshop_sala_evolucion_spec.rb`

**Interfaces:**
- Consumes: `WorkshopProposal` (Task 1), `WorkshopChallenge#workable?`.
- Produces: `POST /workshops/:workshop_id/salas/:sala_id/proposals` → `WorkshopProposal` en `pending` con el `challenge_step_id` de la ronda.

- [ ] **Step 1: El spec que falla**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "sala del taller: evolución", type: :request do
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

  # Desafío con una ronda de evolución ACTIVA, taller abierto contra esa
  # ronda, mesa de ana y beto. La idea de ana la trabaja su mesa; la de carla
  # no, porque carla no está en ella.
  let!(:escenario) do
    as_company(company) do
      challenge = create(:challenge)
      ronda = create(:challenge_step, challenge: challenge, kind: "evolution", status: "active")
      taller = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: taller, challenge: challenge, challenge_step: ronda)
      mesa = create(:workshop_group, workshop: taller)
      [ana, beto].each { |u| create(:workshop_group_member, workshop_group: mesa, user: u) }
      { challenge: challenge, ronda: ronda, taller: taller, link: link, mesa: mesa,
        de_ana: create(:idea, challenge: challenge, author: ana, status: "active"),
        de_carla: create(:idea, challenge: challenge, author: carla, status: "active") }
    end
  end

  def proponer(idea)
    post workshop_sala_proposals_path(escenario[:taller], escenario[:link]),
         params: { idea_id: idea.id, payload: { "resumen" => "Mejor así" } }
  end

  it "la propuesta nace pendiente y con el step de ESA ronda" do
    sign_in(beto, company: company)
    proponer(escenario[:de_ana])

    as_company(company) do
      propuesta = WorkshopProposal.order(:created_at).last
      expect(propuesta).to be_pending
      expect(propuesta.challenge_step_id).to eq(escenario[:ronda].id)
      expect(propuesta.workshop_group_id).to eq(escenario[:mesa].id)
    end
  end

  # Decisión 3.5 del spec: sin polinización cruzada. Y sale de `policy_scope`,
  # no de una condición escrita aparte — por eso es 404 y no 403.
  it "no deja proponer sobre una idea de alguien que no está en la mesa" do
    sign_in(beto, company: company)

    expect { proponer(escenario[:de_carla]) }
      .not_to(change { as_company(company) { WorkshopProposal.count } })
    expect(response).to have_http_status(:not_found)
  end
end
```

- [ ] **Step 2: Correr y verlo fallar**

Run: `make spec-file FILE=spec/requests/workshop_sala_evolucion_spec.rb`
Expected: FAIL.

- [ ] **Step 3: La ruta**

Dentro del bloque `salas` que creó Task 7, al lado de `resources :ideas`:

```ruby
      resources :proposals, only: %i[create], controller: "workshop_proposals"
```

Con eso el helper es `workshop_sala_proposals_path(workshop, sala)`, que es el
que usa el spec de arriba.

- [ ] **Step 4: El controller**

```ruby
# frozen_string_literal: true

class WorkshopProposalsController < ApplicationController
  before_action :set_link

  def create
    authorize @workshop, :work?
    return rechazar unless @link.workable? && @link.kind == "evolution"

    # `policy_scope(Idea)` y no `Idea.find_by!`: una idea que la mesa no ve
    # tiene que dar 404. Es la regla, y acá además es la que implementa «sin
    # polinización cruzada» sin escribir una condición aparte.
    idea = policy_scope(Idea).find_by!(id: params[:idea_id], challenge_id: @link.challenge_id)

    WorkshopProposal.create!(
      workshop_group: mesa_de(current_user), idea: idea,
      challenge_step: @link.challenge_step, payload: params[:payload].to_unsafe_h, status: "pending"
    )

    redirect_to workshop_path(@workshop), notice: "Propuesta enviada a quien es autor."
  end

  private

  def set_link
    @workshop = policy_scope(Workshop).find_by!(id: params[:workshop_id])
    @link = @workshop.workshop_challenges.find_by!(id: params[:sala_id])
  end

  def mesa_de(user)
    @workshop.workshop_groups.joins(:workshop_group_members)
             .find_by!(workshop_group_members: { user_id: user.id })
  end

  def rechazar
    redirect_to workshop_path(@workshop),
                alert: "Esta sala ya no admite trabajo: el desafío avanzó de fase."
  end
end
```

- [ ] **Step 5: Correr, verificar, commitear**

Run: `make spec-file FILE=spec/requests/workshop_sala_evolucion_spec.rb`
Expected: PASS.

```bash
git add config/routes.rb app/controllers/workshop_proposals_controller.rb app/views/workshops spec/requests/workshop_sala_evolucion_spec.rb
git commit -m "Sala de evolución: la mesa propone sobre las ideas de sus integrantes"
```

---

### Task 9: Aceptar o descartar la propuesta, desde la ficha de la idea

**Files:**
- Create: `app/controllers/idea_workshop_proposals_controller.rb`
- Create: `app/views/shared/_workshop_proposal.html.haml`
- Modify: `app/views/ideas/show.html.haml`, `app/controllers/ideas_controller.rb:41`
- Modify: `config/routes.rb`
- Test: `spec/requests/workshop_proposal_accept_spec.rb`

**Interfaces:**
- Consumes: `WorkshopProposal#actionable?` (Task 1), `WorkshopProposal` creada en Task 8, `Flow::Ideas::PublishVersion`, `IdeaVersion::ACTOR_TYPES` con `workshop` (Task 2).
- Produces: rutas `accept_idea_workshop_proposal_path(idea, proposal)` y `reject_idea_workshop_proposal_path(...)`, declaradas al nivel de `resources :ideas` como:

```ruby
  # La propuesta se acepta desde la ficha de la idea, que es donde la ve su
  # autor: no cuelga del taller.
  resources :ideas, only: [] do
    resources :workshop_proposals, only: [], controller: "idea_workshop_proposals" do
      member do
        post :accept
        post :reject
      end
    end
  end
```

- [ ] **Step 1: El spec que falla**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "aceptar una propuesta de taller", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email, role)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, role.to_sym, company: company, user: u)
      u
    end
  end

  let!(:ana) { member("ana@test.dev", :participant) }
  let!(:beto) { member("beto@test.dev", :participant) }
  let!(:admin) { member("admin@test.dev", :admin) }

  let!(:escenario) do
    as_company(company) do
      challenge = create(:challenge)
      idear = create(:challenge_step, challenge: challenge, kind: "ideation", status: "completed")
      create(:form_field, challenge_step: idear, label: "Resumen", field_type: "text")
      ronda = create(:challenge_step, challenge: challenge, kind: "evolution", status: "active")
      idea = create(:idea, challenge: challenge, author: ana, status: "active")
      taller = create(:workshop, status: "open")
      mesa = create(:workshop_group, workshop: taller)
      [ana, beto].each { |u| create(:workshop_group_member, workshop_group: mesa, user: u) }
      propuesta = create(:workshop_proposal, workshop_group: mesa, idea: idea,
                                             challenge_step: ronda, payload: { "resumen" => "Mejor así" })
      { challenge: challenge, ronda: ronda, idea: idea, propuesta: propuesta }
    end
  end

  def aceptar = post accept_idea_workshop_proposal_path(escenario[:idea], escenario[:propuesta])

  it "publica la versión con actor_type workshop y suma la mesa como contribuyentes" do
    sign_in(ana, company: company)
    aceptar

    as_company(company) do
      idea = escenario[:idea].reload
      expect(idea.current_version.actor_type).to eq("workshop")
      expect(idea.current_version.source_step_id).to eq(escenario[:ronda].id)
      expect(idea.contributors.map(&:id)).to include(beto.id)
      expect(escenario[:propuesta].reload).to be_accepted
    end
  end

  # El sentido del paso es que a nadie le reescriban la idea sin que
  # participe. Un atajo para quien administra lo borraría.
  it "sólo el autor acepta: a quien administra le da 403" do
    sign_in(admin, company: company)

    expect { aceptar }.not_to(change { as_company(company) { escenario[:idea].versions.count } })
    expect(response).to have_http_status(:forbidden)
  end

  # Review Focus 3: publicar dentro de una ronda cerrada escribiría en una
  # conversación terminada.
  it "una propuesta cuya ronda ya cerró no se puede aceptar" do
    as_company(company) { escenario[:ronda].update!(status: "completed") }
    sign_in(ana, company: company)

    expect { aceptar }.not_to(change { as_company(company) { escenario[:idea].versions.count } })
    expect(flash[:alert]).to include("ya cerró")
    expect(as_company(company) { escenario[:propuesta].reload }).to be_pending
  end
end
```

- [ ] **Step 2: Correr y verlo fallar**

Run: `make spec-file FILE=spec/requests/workshop_proposal_accept_spec.rb`
Expected: FAIL.

- [ ] **Step 3: El controller**

```ruby
# frozen_string_literal: true

# Aceptar es de QUIEN ES AUTOR, ni siquiera de quien administra: el sentido
# del paso es que a nadie le reescriban la idea sin que participe.
#
# Y no se edita al aceptar. Precedente: `Tasks::EvaluateIdea#editable?` se
# borró porque aceptar admitiendo un payload editado era una capacidad del
# dominio sin interfaz.
class IdeaWorkshopProposalsController < ApplicationController
  before_action :set_proposal

  def accept
    return head :forbidden unless @idea.author_id == current_user.id
    return vencida unless @proposal.actionable?

    ActiveRecord::Base.transaction do
      Flow::Ideas::PublishVersion.new(
        @idea, payload: @proposal.payload, author: current_user, actor_type: "workshop",
               source_step: @proposal.challenge_step,
               change_note: "Propuesta de la mesa «#{@proposal.workshop_group.name}»"
      ).call
      @proposal.workshop_group.members.each do |persona|
        next if persona.id == @idea.author_id

        @idea.idea_contributors.find_or_create_by!(user: persona)
      end
      @proposal.update!(status: "accepted", reviewed_by: current_user, reviewed_at: Time.current)
    end

    redirect_to challenge_idea_path(@idea.challenge, @idea), notice: "Propuesta aplicada."
  end

  def reject
    return head :forbidden unless @idea.author_id == current_user.id

    @proposal.update!(status: "rejected", reviewed_by: current_user, reviewed_at: Time.current)
    redirect_to challenge_idea_path(@idea.challenge, @idea), notice: "Propuesta descartada."
  end

  private

  def set_proposal
    @idea = policy_scope(Idea).find_by!(id: params[:idea_id])
    @proposal = WorkshopProposal.find_by!(id: params[:id], idea_id: @idea.id)
  end

  def vencida
    redirect_to challenge_idea_path(@idea.challenge, @idea),
                alert: "La ronda de evolución de esta propuesta ya cerró."
  end
end
```

- [ ] **Step 4: Publicarlas en la ficha de la idea**

En `IdeasController#show`, al lado de `@pending_suggestions`:

```ruby
    @workshop_proposals = WorkshopProposal.pending_review.where(idea_id: @idea.id)
                                          .includes(:workshop_group, :challenge_step)
```

Y en `ideas/show.html.haml`, al lado del panel de propuestas de la IA. Una propuesta **vencida** se muestra vencida y sin botones; no desaparece.

- [ ] **Step 5: Correr, verificar, commitear**

Run: `make spec-file FILE=spec/requests/workshop_proposal_accept_spec.rb`
Expected: PASS (3 ejemplos).

```bash
git add config/routes.rb app/controllers app/views spec/requests/workshop_proposal_accept_spec.rb
git commit -m "El taller propone y el autor publica, con la ronda como límite"
```

---

### Task 10: Seeds propios, capturas y la suite entera

**Files:**
- Modify: `db/seeds.rb`
- Modify: `script/capture_screens.js`

- [ ] **Step 1: Sembrar desafíos PROPIOS del taller**

**Nunca apuntes una captura a un desafío que también se usa a mano.** `onboarding-remoto` rompió la corrida dos veces por compartirse (`3e437d6`), y esta regla se reintrodujo igual dos veces más. Sembrá `taller-idear` (con su módulo de idear activo) y `taller-evolucion` (con una ronda de evolución activa y una idea con feedback), **usados sólo por el recorrido**, más un taller abierto que vincule los dos con dos mesas.

- [ ] **Step 2: Las capturas**

En `script/capture_screens.js`, **navegando por link y no con `goto`** —Turbo no dispara `DOMContentLoaded` al navegar por link, y un `goto` esconde el bug—:

- `24-taller-armado` (borrador, con el bloque de armado)
- `25-taller-sala-idear`
- `26-taller-sala-evolucion`
- `27-taller-propuesta-en-la-idea`
- `28-taller-vinculo-cerrado` (un desafío que avanzó: se ve cerrado **con el motivo**)

Recordá que `[FORMS]`, `[TEXTO]`, `[RITMO]`, `[CLASES]`, `[PANEL]`, `[CONTRASTE]`, `[PASTILLA]` y `[MONO]` corren solas en `capturar()`: no las llames a mano.

- [ ] **Step 3: La suite entera y el recorrido**

```bash
make spec
make screens
```

Expected: `make spec` sin fallas; `make screens` 71 capturas, 0 errores.

- [ ] **Step 4: Commit**

```bash
git add db/seeds.rb script/capture_screens.js tmp/screenshots
git commit -m "Seeds y capturas propias del taller"
```
