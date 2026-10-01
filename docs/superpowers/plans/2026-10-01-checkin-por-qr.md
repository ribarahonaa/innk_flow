# Check-in por QR en el taller — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que un taller se proyecte un QR, que escanearlo sea la puerta de
entrada —convoca y marca presente— y que quien no tiene cuenta se la cree ahí
mismo.

**Architecture:** Un modo declarado por taller (`attendance_mode`:
`presumed`/`registered`) decide si la presencia se presume o se registra, y un
`checkin_token` por taller es la credencial. La única ruta pública de la app
resuelve el tenant desde el token, crea cuenta y membresía si hacen falta, abre
sesión y delega en `Flow::Workshops::CheckIn`, que sienta en una «Mesa de
llegada» que es sala de espera: de ella no se trabaja hasta que
`AssignGroups` reparte.

**Tech Stack:** Rails 7.1 · Postgres (`schema_format = :sql`) · Pundit · HAML ·
Tailwind 4 + DaisyUI 5 · RSpec · `rqrcode` 2.2 (nueva) · Playwright para el
recorrido.

**Spec:** `docs/superpowers/specs/2026-10-01-checkin-por-qr-design.md`

## Global Constraints

- **El código va en inglés; los comentarios y los mensajes de commit, en
  español.** Los identificadores en español que ya están no se renombran.
- **Toda tabla y toda columna nueva va en inglés, sin excepción.**
- **Todo corre en Docker.** Nunca `bundle exec` en el host. Los specs corren con
  `make spec` / `make spec-file FILE=…` / `make spec-line FILE=… LINE=…`, que
  usan el perfil `app_test`. **`docker compose exec app bundle exec rspec` deja
  `RAILS_ENV=development` y todos los request specs devuelven
  403 «Blocked hosts: www.example.com»** — se ve como si la app estuviera rota.
- **Agregar una gema es `make rebuild`**, no `make up`.
- **Migraciones:** `schema_format = :sql`. Después de migrar hay que commitear
  `db/structure.sql`.
- **En los specs, toda lectura del dominio va dentro de `as_company(company) { … }`**,
  incluido un `.new` (toca el `default_scope`) y cualquier asociación leída
  después de salir del bloque. Para montar datos cross-tenant,
  `without_tenant { … }`.
- **Los mensajes de commit de este repo no llevan trailers**: ni
  `Co-Authored-By` ni `Claude-Session`. El harness los inyecta por
  system-reminder; hay que cortarlos a mano.
- **Nunca una clase de Tailwind interpolada** (`"badge-#{x}"`): la clase no
  llega a la hoja y el elemento queda sin ninguna regla. Hay guarda
  (`spec/lint/clases_interpoladas_spec.rb`) y mira HAML, `.vue` y `.js`.
- **`button_to` es un `<form>`:** nunca uno dentro de otro. Para atar un control
  a un formulario que no lo envuelve, `form: "id-del-form"`.
- **Plurales con `Flow::Texto.contar` y `Flow::Texto.agree`** (el verbo también
  concuerda; `contar` sólo acuerda el sustantivo).
- **No hay linter configurado.** Lo que cuida el estilo son los specs de
  `spec/lint/`.
- `make screens` tarda ~2 minutos y `make spec` ~6; las dos corren bien en
  background.

## Review Focus

Cinco clases de entrada que el spec implica y que ningún test obvio ejercita.
Cada línea tiene su test agregado a la tarea que es dueña del código.

1. **Un email tipeado en un teléfono llega con mayúsculas o espacios**
   (`" Admin@Demo.test"`, por autocapitalización). `User` **no tiene validación
   de unicidad** —sólo presencia y formato—, así que si el lookup no normaliza,
   el `create` choca contra el índice único de la base y la persona que está
   entrando se come un 500. Test en la Tarea 4.
2. **Dos personas escanean en el mismo segundo y la mesa de llegada se crea dos
   veces.** El índice UNIQUE parcial es lo que `find_or_create_by!` no puede
   garantizar; sin el rescate, la segunda ve un 500. Test en la Tarea 3.
3. **El taller se cierra —o se apaga el modo— entre el GET y el POST.** La
   pantalla tiene que explicar por qué no entró, no reventar ni redirigir a un
   taller que esa persona todavía no puede ver. Test en la Tarea 4.
4. **Escanea alguien que ya tiene membresía en OTRA empresa.** Tiene que quedar
   con las dos membresías y la sesión en la empresa del taller, sin perder la
   otra. Test en la Tarea 4.
5. **`make seed` corre dos veces.** El cuarto taller tiene que entrar en el
   `destroy_all` por nombre de arriba del bloque, o la segunda siembra lo
   duplica y el recorrido encuentra dos. Verificación en la Tarea 8.

---

## File Structure

**Se crean:**

| Archivo | Responsabilidad |
|---|---|
| `db/migrate/20261001120000_add_checkin_to_workshops.rb` | Las tres columnas y el índice parcial |
| `app/lib/flow/workshops/check_in.rb` | Sentar y marcar presente, idempotente |
| `app/controllers/concerns/authentication.rb` | `sign_in!`: la política de la cookie, en un solo lugar |
| `app/controllers/workshop_checkins_controller.rb` | La ruta pública |
| `app/controllers/workshop_attendances_controller.rb` | El toggle de presencia |
| `app/views/workshop_checkins/show.html.haml` | La pantalla del escaneo |
| `app/views/workshops/_checkin.html.haml` | El QR y sus tres controles |
| `app/helpers/checkin_helper.rb` | El SVG del QR |
| `spec/lib/flow/workshops/check_in_spec.rb` | |
| `spec/requests/workshop_checkin_spec.rb` | |
| `spec/requests/workshop_arrival_spec.rb` | |
| `spec/requests/workshop_checkin_settings_spec.rb` | |
| `spec/requests/workshop_attendances_spec.rb` | |

**Se modifican:**

| Archivo | Qué cambia |
|---|---|
| `Gemfile` | `rqrcode` |
| `app/models/workshop.rb` | Modos, token, `checkin_state` |
| `app/models/workshop_group.rb` | `workable_ideas` devuelve `none` en la llegada |
| `app/lib/flow/workshops/convoke.rb` | Parámetro `attended:` |
| `app/lib/flow/workshops/assign_groups.rb` | Pool por modo; `seat!` no reusa la llegada |
| `app/controllers/application_controller.rb` | `skip_pundit?` y el include del concern |
| `app/controllers/sessions_controller.rb` | Usa `sign_in!` |
| `app/controllers/workshops_controller.rb` | `enable_checkin`, `disable_checkin`, `rotate_checkin_token` |
| `app/controllers/workshop_ideas_controller.rb` | Rechaza la mesa de llegada |
| `app/controllers/workshop_proposals_controller.rb` | Rechaza la mesa de llegada |
| `app/views/workshops/_assembly.html.haml` | Renderiza `_checkin` |
| `app/views/workshops/_groups.html.haml` | Itera los asientos, no los users; el toggle |
| `app/views/workshops/_sala_idear.html.haml` | Rama de la mesa de llegada |
| `app/views/workshops/_sala_evolucion.html.haml` | Rama de la mesa de llegada |
| `config/routes.rb` | La ruta pública y las cuatro member |
| `db/seeds.rb` | El cuarto taller |
| `script/capture_screens.js` | 29, 30 y 30b |
| `spec/lint/tenant_bypass_spec.rb` | El `ALLOWED` nuevo |
| `spec/factories/core.rb` | Traits del taller |
| `CLAUDE.md` | El check-in, en la sección del taller |

---

### Task 1: El esquema y el modelo

**Files:**
- Create: `db/migrate/20261001120000_add_checkin_to_workshops.rb`
- Modify: `app/models/workshop.rb`
- Modify: `db/structure.sql` (lo regenera `make rails db:migrate`)
- Modify: `spec/factories/core.rb`
- Test: `spec/models/workshop_spec.rb` (existe, 4 ejemplos)

**Interfaces:**
- Consumes: nada.
- Produces: `Workshop::ATTENDANCE_MODES` · `Workshop#presumed_attendance?` ·
  `Workshop#registered_attendance?` · `Workshop#checkin_state` (`:open`,
  `:draft`, `:closed`, `:off`) · `Workshop#checkin_open?` ·
  `Workshop#checkin_token` · `Workshop#regenerate_checkin_token` ·
  `WorkshopGroup#arrival?` (lo genera ActiveRecord desde la columna booleana) ·
  factory traits `:registered` (taller) y `:arrival` (mesa).

- [ ] **Step 1: Escribir los tests que fallan**

En `spec/models/workshop_spec.rb`, agregar:

```ruby
  describe "el modo de asistencia" do
    it "nace presumido y con token" do
      taller = as_company(company) { create(:workshop) }

      expect(taller.attendance_mode).to eq("presumed")
      expect(taller).to be_presumed_attendance
      expect(taller.checkin_token).to be_present
    end

    it "rechaza un modo que no existe" do
      taller = as_company(company) { build(:workshop, attendance_mode: "qr") }

      expect(taller).not_to be_valid
      expect(taller.errors[:attendance_mode]).to be_present
    end

    # El token es UNA de las dos cosas que el link necesita; la otra es el modo.
    # Separarlas es lo que deja rotar el token sin devolver la asistencia a
    # presumida en medio de la sesión.
    it "rota el token sin tocar el modo" do
      taller = as_company(company) { create(:workshop, :registered) }
      anterior = taller.checkin_token

      taller.regenerate_checkin_token

      expect(taller.checkin_token).not_to eq(anterior)
      expect(taller).to be_registered_attendance
    end
  end

  describe "#checkin_state" do
    it "es :off con el modo presumido, aunque esté abierto" do
      taller = as_company(company) { create(:workshop, status: "open") }

      expect(taller.checkin_state).to eq(:off)
      expect(taller).not_to be_checkin_open
    end

    it "distingue borrador de cerrado, para poder decir cuál es" do
      borrador = as_company(company) { create(:workshop, :registered, status: "draft") }
      cerrado  = as_company(company) { create(:workshop, :registered, status: "closed") }

      expect(borrador.checkin_state).to eq(:draft)
      expect(cerrado.checkin_state).to eq(:closed)
    end

    it "es :open con el modo puesto y el taller abierto" do
      taller = as_company(company) { create(:workshop, :registered, status: "open") }

      expect(taller.checkin_state).to eq(:open)
      expect(taller).to be_checkin_open
    end
  end

  describe "la mesa de llegada" do
    # La unicidad la tiene que dar la BASE: dos escaneos en el mismo segundo
    # atraviesan cualquier `find_or_create_by`.
    it "es una sola por taller" do
      taller = as_company(company) { create(:workshop) }
      as_company(company) { create(:workshop_group, :arrival, workshop: taller) }

      expect {
        as_company(company) { create(:workshop_group, :arrival, workshop: taller, name: "Otra") }
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "no impide una llegada en otro taller" do
      uno = as_company(company) { create(:workshop) }
      otro = as_company(company) { create(:workshop) }
      as_company(company) { create(:workshop_group, :arrival, workshop: uno) }

      expect {
        as_company(company) { create(:workshop_group, :arrival, workshop: otro) }
      }.not_to raise_error
    end
  end
```

Si el `describe` de arriba del archivo no define `company`, agregar
`let!(:company) { without_tenant { create(:company) } }` siguiendo lo que ya
tiene el archivo.

En `spec/factories/core.rb`, dentro de `factory :workshop`:

```ruby
    trait(:registered) { attendance_mode { "registered" } }
```

y dentro de `factory :workshop_group`:

```ruby
    trait(:arrival) do
      arrival { true }
      name { "Mesa de llegada" }
    end
```

- [ ] **Step 2: Correr y verificar que falla**

Run: `make spec-file FILE=spec/models/workshop_spec.rb`
Expected: FAIL con `unknown attribute 'attendance_mode'` (y `'arrival'`).

- [ ] **Step 3: La migración**

`db/migrate/20261001120000_add_checkin_to_workshops.rb`:

```ruby
# frozen_string_literal: true

# El check-in del taller: cómo se establece la presencia, con qué credencial se
# entra, y dónde espera quien llegó.
#
# `attendance_mode` declara la SEMÁNTICA y no el gadget: `registered` no dice
# «QR», dice que la presencia se registra en vez de presumirse. El QR es una
# forma de registrarla y el toggle de la pantalla es la otra.
#
# `checkin_token` va SEPARADO del modo a propósito. La tentación es derivar uno
# del otro —«hay token, entonces hay QR»— y ahorrar una columna: no se hace,
# porque rotar el token para revocar un link filtrado devolvería la asistencia a
# presumida EN MEDIO de la sesión, y `Flow::Workshops::AssignGroups` volvería a
# sentar a toda la empresa sin que nadie lo pidiera.
#
# El índice de `arrival` es UNIQUE PARCIAL: una mesa de llegada por taller, y lo
# garantiza la base porque dos personas que escanean en el mismo segundo
# atraviesan cualquier `find_or_create_by`.
class AddCheckinToWorkshops < ActiveRecord::Migration[7.1]
  def up
    add_column :workshops, :attendance_mode, :string, null: false, default: "presumed"
    add_check_constraint :workshops,
                         "attendance_mode IN ('presumed', 'registered')",
                         name: "workshops_attendance_mode_check"

    # Nullable, backfill, y recién después NOT NULL: `has_secure_token` sólo
    # llena en el `create`, así que las filas que ya están no tendrían token.
    add_column :workshops, :checkin_token, :string
    execute "UPDATE workshops SET checkin_token = replace(uuid_generate_v7()::text, '-', '')"
    change_column_null :workshops, :checkin_token, false
    add_index :workshops, :checkin_token, unique: true

    add_column :workshop_groups, :arrival, :boolean, null: false, default: false
    add_index :workshop_groups, :workshop_id, unique: true, where: "arrival",
              name: "index_workshop_groups_on_workshop_id_arrival"
  end

  def down
    remove_index :workshop_groups, name: "index_workshop_groups_on_workshop_id_arrival"
    remove_column :workshop_groups, :arrival
    remove_index :workshops, :checkin_token
    remove_column :workshops, :checkin_token
    remove_check_constraint :workshops, name: "workshops_attendance_mode_check"
    remove_column :workshops, :attendance_mode
  end
end
```

Run: `make rails db:migrate` (regenera `db/structure.sql`).

Si `uuid_generate_v7()` no estuviera disponible en el contexto de la migración,
usar `gen_random_uuid()` (Postgres 13+, built-in). Verificar en el output del
`UPDATE` antes de seguir.

- [ ] **Step 4: El modelo**

En `app/models/workshop.rb`, después de `STATUSES`:

```ruby
  # Cómo se establece la presencia. `presumed` es lo de siempre: el reparto
  # sienta al pool completo y marcar ausentes es la excepción. `registered` dice
  # que la presencia la ESCRIBE alguien —el escaneo, o el toggle de la pantalla—
  # y que quien no está marcado no está.
  ATTENDANCE_MODES = %w[presumed registered].freeze
```

y después de las validaciones:

```ruby
  validates :attendance_mode, inclusion: { in: ATTENDANCE_MODES }

  has_secure_token :checkin_token

  def presumed_attendance? = attendance_mode == "presumed"
  def registered_attendance? = attendance_mode == "registered"

  # Qué puede hacer el link, en UN valor. Misma forma que
  # `WorkshopChallenge#room_state`: con un valor cerrado y un `case` con `else`
  # la pantalla no puede quedarse muda cuando mañana haya un estado más, que es
  # justo cómo una sala se renderizó vacía sin un solo mensaje.
  #
  # Borrador y cerrado se distinguen porque la pantalla dice cosas distintas:
  # «volvé cuando empiece» sobre un taller que ya terminó es mentira.
  def checkin_state
    return :off unless registered_attendance?
    return :closed if closed?
    return :draft if draft?

    :open
  end

  def checkin_open? = checkin_state == :open
```

- [ ] **Step 5: Correr y verificar que pasa**

Run: `make spec-file FILE=spec/models/workshop_spec.rb`
Expected: PASS.

- [ ] **Step 6: Probar que los tests pueden fallar**

Esto no es opcional y no es «correr la mutación»: es preguntar de cada test qué
tendría que romperse. Con backup por `cp` al scratchpad, **nunca**
`git checkout <archivo>` —en una rama sin commit eso restaura del índice, o sea
deshace el ARREGLO y no la mutación—.

```bash
cp app/models/workshop.rb /tmp/claude-1000/workshop.rb.bak
```

Tres mutaciones, una por vez, corriendo el archivo de spec entre cada una:

1. En `checkin_state`, cambiar `return :draft if draft?` por `return :closed if draft?`.
   Tiene que fallar el ejemplo «distingue borrador de cerrado».
2. Sacar `validates :attendance_mode, inclusion: …`. Tiene que fallar «rechaza
   un modo que no existe».
3. En la migración, sacar el `where: "arrival"` del índice **no** se prueba
   mutando: se prueba con el segundo ejemplo de la mesa de llegada, que exige
   que dos talleres puedan tener la suya. Verificar que ese ejemplo existe y
   pasa.

Restaurar: `cp /tmp/claude-1000/workshop.rb.bak app/models/workshop.rb`

- [ ] **Step 7: Commit**

```bash
git add db/migrate db/structure.sql app/models/workshop.rb spec/models/workshop_spec.rb spec/factories/core.rb
git commit -F - <<'MSG'
El taller declara cómo se establece su asistencia

Tres columnas. `attendance_mode` dice si la presencia se presume —lo de hoy— o
se registra; el nombre no dice «QR» porque el QR es una forma de registrarla y
el toggle de la pantalla es la otra.

`checkin_token` va separado del modo y no derivado de él: rotarlo para revocar
un link filtrado devolvería la asistencia a presumida en medio de la sesión, y
el reparto volvería a sentar a toda la empresa sin que nadie lo pidiera.

Y `workshop_groups.arrival` con índice UNIQUE PARCIAL, porque la unicidad de la
mesa de llegada la tiene que dar la base: dos personas que escanean en el mismo
segundo atraviesan cualquier find_or_create_by.
MSG
```

---

### Task 2: Quién escribe la presencia

**Files:**
- Modify: `app/lib/flow/workshops/convoke.rb`
- Modify: `app/lib/flow/workshops/assign_groups.rb:120-150` (`seat!`,
  `groups_by_person`)
- Test: `spec/lib/flow/workshops/convoke_spec.rb`,
  `spec/lib/flow/workshops/assign_groups_spec.rb`

**Interfaces:**
- Consumes: `Workshop#presumed_attendance?`, `Workshop#registered_attendance?` (Tarea 1).
- Produces: `Flow::Workshops::Convoke.new(workshop, user, group: nil, attended: nil)`
  — `attended: nil` significa «el default del modo del taller», y un booleano
  explícito manda. Lo consume `CheckIn` (Tarea 3) con `attended: true`.

- [ ] **Step 1: Escribir los tests que fallan**

En `spec/lib/flow/workshops/convoke_spec.rb`:

```ruby
  describe "la asistencia con la que nace el asiento" do
    it "nace presente en un taller con la presencia presumida" do
      taller = as_company(company) { create(:workshop, status: "open") }
      mesa = as_company(company) { create(:workshop_group, workshop: taller) }

      result = as_company(company) { described_class.new(taller, User.find(paula.id), group: mesa).call }

      expect(result).to be_ok
      expect(result.member.attended).to be(true)
    end

    # Convocar a mano en un taller con la presencia registrada deja el asiento
    # AUSENTE: está invitado, no llegó.
    it "nace ausente en un taller con la presencia registrada" do
      taller = as_company(company) { create(:workshop, :registered, status: "open") }
      mesa = as_company(company) { create(:workshop_group, workshop: taller) }

      result = as_company(company) { described_class.new(taller, User.find(paula.id), group: mesa).call }

      expect(result).to be_ok
      expect(result.member.attended).to be(false)
    end

    it "un valor explícito le gana al default del modo" do
      taller = as_company(company) { create(:workshop, :registered, status: "open") }
      mesa = as_company(company) { create(:workshop_group, workshop: taller) }

      result = as_company(company) do
        described_class.new(taller, User.find(paula.id), group: mesa, attended: true).call
      end

      expect(result.member.attended).to be(true)
    end
  end
```

Usar los `let` que el archivo ya tiene para `company` y para la persona; si se
llaman distinto, adaptar los nombres y no agregar otros.

En `spec/lib/flow/workshops/assign_groups_spec.rb`:

```ruby
  describe "el pool en un taller con la presencia registrada" do
    # Sin esto el escaneo es DECORATIVO para idear: `participant_ids` son todos
    # los `participant` de la empresa, así que el reparto sienta igual a quien
    # no vino.
    it "son sólo los sentados y presentes, no toda la empresa" do
      taller = workshop_with(kind: "ideation", registered: true)
      mesa = as_company(company) { create(:workshop_group, workshop: taller) }
      as_company(company) do
        WorkshopGroupMember.create!(workshop_group: mesa, user_id: paula.id, attended: true)
      end

      result = as_company(company) { described_class.new(taller, size: 4).call }

      expect(result).to be_ok
      expect(result.tables.flatten).to contain_exactly(paula.id)
    end

    # La de llegada es la PRIMERA mesa creada, así que `seat!` la reusaría como
    # «Mesa 1» conservando `arrival: true` y el nombre, y la sala de la mesa 1
    # quedaría muda para siempre.
    it "no reusa la mesa de llegada, y la borra cuando queda vacía" do
      taller = workshop_with(kind: "ideation", registered: true)
      llegada = as_company(company) { create(:workshop_group, :arrival, workshop: taller) }
      as_company(company) do
        WorkshopGroupMember.create!(workshop_group: llegada, user_id: paula.id, attended: true)
      end

      as_company(company) { described_class.new(taller, size: 4).call }

      mesas = as_company(company) { taller.workshop_groups.reload.to_a }
      expect(mesas.map(&:arrival)).to all(be(false))
      expect(mesas.map(&:name)).to contain_exactly("Mesa 1")
    end
  end
```

El helper `workshop_with` del archivo tiene que aceptar `registered:`. Agregarle
el parámetro con default `false` y pasar `attendance_mode: registered ? "registered" : "presumed"`
al `create(:workshop, …)`.

- [ ] **Step 2: Correr y verificar que falla**

Run: `make spec-file FILE=spec/lib/flow/workshops/convoke_spec.rb`
Expected: FAIL — el asiento del taller registrado nace `true`.

Run: `make spec-file FILE=spec/lib/flow/workshops/assign_groups_spec.rb`
Expected: FAIL — el pool trae a toda la empresa, y la mesa de llegada queda
como «Mesa de llegada» con `arrival: true`.

- [ ] **Step 3: `Convoke` recibe la asistencia**

En `app/lib/flow/workshops/convoke.rb`, el `initialize`:

```ruby
      def initialize(workshop, user, group: nil, attended: nil)
        @workshop = workshop
        @user = user
        @group = group
        # Un taller con la presencia REGISTRADA convoca AUSENTE: está invitado,
        # no llegó. El `nil` es lo que deja al escaneo decir `true` sin que este
        # servicio pregunte por el modo en dos lugares.
        @attended = attended.nil? ? workshop.presumed_attendance? : attended
      end
```

y el `new` del asiento:

```ruby
        member = WorkshopGroupMember.new(workshop_group: group, user: @user, attended: @attended)
```

- [ ] **Step 4: `AssignGroups`, el pool y el barrido**

En `groups_by_person`:

```ruby
      # Idear: un grupo por persona. No hay ideas de las que deducir nada.
      def groups_by_person
        # Con la presencia REGISTRADA el pool automático sobra y además miente:
        # `participant_ids` son todos los `participant` de la empresa, así que
        # sentaría a quien no vino y dejaría al escaneo sin efecto. Acá no hace
        # falta restar `absent_ids` — `seated_present_ids` ya sale de
        # `presentes`, y una persona tiene UN asiento por taller (UNIQUE), así
        # que no puede estar en las dos listas.
        ids = if @workshop.registered_attendance?
                seated_present_ids
              else
                (participant_ids | seated_present_ids) - absent_ids
              end
        ids.to_h { |id| [id, [id]] }
      end
```

En `seat!`, la primera línea y el `create!`:

```ruby
      def seat!(tables)
        # La mesa de llegada NO es reusable: es la primera creada, así que
        # `existentes[0]` la convertiría en «Mesa 1» conservando `arrival: true`
        # y su nombre, y su sala quedaría muda para siempre. El barrido de
        # vacías de abajo la borra cuando se queda sin nadie.
        existentes = @workshop.workshop_groups.where(arrival: false).order(:created_at).to_a

        tables.each_with_index do |user_ids, i|
          mesa = existentes[i] || @workshop.workshop_groups.create!(name: "Mesa #{i + 1}")
          WorkshopGroupMember.presentes.joins(:workshop_group)
                              .where(workshop_groups: { workshop_id: @workshop.id }, user_id: user_ids)
                              .destroy_all
          # `attended: true` EXPLÍCITO y no heredado del default de la columna:
          # lo que se siembra acá viene de `seated_present_ids`, o sea gente
          # presente. Heredarlo acertaba por casualidad, y el default puede
          # querer lo contrario según el modo del taller.
          user_ids.each { |id| WorkshopGroupMember.create!(workshop_group: mesa, user_id: id, attended: true) }
        end
```

El resto del método queda igual.

- [ ] **Step 5: Correr y verificar que pasan los dos archivos**

Run: `make spec-file FILE=spec/lib/flow/workshops/convoke_spec.rb`
Run: `make spec-file FILE=spec/lib/flow/workshops/assign_groups_spec.rb`
Expected: PASS los dos, sin ejemplos nuevos rotos entre los 19 que ya estaban.

- [ ] **Step 6: Probar que los tests pueden fallar**

```bash
cp app/lib/flow/workshops/assign_groups.rb /tmp/claude-1000/assign_groups.rb.bak
cp app/lib/flow/workshops/convoke.rb /tmp/claude-1000/convoke.rb.bak
```

1. En `groups_by_person`, borrar la rama `if` y dejar sólo la vieja. Tiene que
   fallar «son sólo los sentados y presentes».
2. En `seat!`, sacar el `.where(arrival: false)`. Tiene que fallar «no reusa la
   mesa de llegada».
3. En `Convoke`, cambiar el default a `attended.nil? ? true : attended`. Tiene
   que fallar «nace ausente en un taller con la presencia registrada».

Restaurar los dos archivos con `cp`.

- [ ] **Step 7: Commit**

```bash
git add app/lib/flow/workshops spec/lib/flow/workshops
git commit -F - <<'MSG'
Cada escritor de presencia dice lo que quiere, y el pool sigue al modo

Convocar a mano en un taller con la presencia registrada deja el asiento
ausente: está invitado, no llegó. Y `seat!` pasa `attended: true` explícito en
vez de heredar el default de la columna, que acertaba por casualidad —siembra
gente que viene de `seated_present_ids`, o sea presente—.

El pool de idear deja de incluir a toda la empresa cuando la presencia se
registra. Sin esto el escaneo es decorativo: `participant_ids` sienta igual a
quien no vino, y da lo mismo haber escaneado.

Y la mesa de llegada sale de las reusables. Es la primera creada, así que
`existentes[0]` la convertía en «Mesa 1» con `arrival: true` y su nombre
puestos, y la sala de la mesa 1 quedaba muda para siempre.
MSG
```

---

### Task 3: `Flow::Workshops::CheckIn`

**Files:**
- Create: `app/lib/flow/workshops/check_in.rb`
- Test: `spec/lib/flow/workshops/check_in_spec.rb`

**Interfaces:**
- Consumes: `Convoke.new(…, attended:)` (Tarea 2), `Workshop#registered_attendance?` (Tarea 1).
- Produces: `Flow::Workshops::CheckIn.new(workshop, user).call` → `Result`
  con `ok?`, `member` (un `WorkshopGroupMember`) y `errors` (array de strings).
  `Flow::Workshops::CheckIn::ARRIVAL_NAME` == `"Mesa de llegada"`.
  Lo consume `WorkshopCheckinsController` (Tarea 4).

- [ ] **Step 1: Escribir los tests que fallan**

`spec/lib/flow/workshops/check_in_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# Entrar al taller escaneando. Idempotente a propósito: un link se escanea dos
# veces con los dedos fríos, y la segunda no puede mover a nadie de mesa.
RSpec.describe Flow::Workshops::CheckIn do
  let!(:company) { without_tenant { create(:company) } }

  def member(email, role = :participant)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, role, company: company, user: u)
      u
    end
  end

  let!(:paula) { member("paula@test.dev") }
  let!(:pedro) { member("pedro@test.dev") }

  def workshop(mode: "group", status: "open", registered: true)
    as_company(company) do
      create(:workshop, mode: mode, status: status,
                        attendance_mode: registered ? "registered" : "presumed")
    end
  end

  def call(taller, person)
    as_company(company) { described_class.new(taller, User.find(person.id)).call }
  end

  it "sienta en la mesa de llegada y marca presente" do
    taller = workshop
    result = call(taller, paula)

    expect(result).to be_ok
    expect(result.member.attended).to be(true)
    expect(result.member.workshop_group.arrival).to be(true)
    expect(result.member.workshop_group.name).to eq(described_class::ARRIVAL_NAME)
  end

  it "la mesa de llegada es la misma para todos" do
    taller = workshop
    call(taller, paula)
    call(taller, pedro)

    mesas = as_company(company) { taller.workshop_groups.reload.to_a }
    expect(mesas.size).to eq(1)
  end

  it "es idempotente: escanear dos veces no duplica el asiento" do
    taller = workshop
    call(taller, paula)

    expect { call(taller, paula) }.not_to raise_error
    asientos = as_company(company) do
      WorkshopGroupMember.joins(:workshop_group)
                         .where(workshop_groups: { workshop_id: taller.id }, user_id: paula.id).count
    end
    expect(asientos).to eq(1)
  end

  # Quien ya estaba convocado a la mesa 3 no termina en la llegada por escanear.
  it "a quien ya tiene mesa lo marca presente sin moverlo" do
    taller = workshop
    mesa = as_company(company) { create(:workshop_group, workshop: taller, name: "Mesa 3") }
    as_company(company) do
      WorkshopGroupMember.create!(workshop_group: mesa, user_id: paula.id, attended: false)
    end

    result = call(taller, paula)

    expect(result).to be_ok
    expect(result.member.workshop_group_id).to eq(mesa.id)
    expect(result.member.attended).to be(true)
  end

  # En modo individual una mesa ES una persona: `Convoke#own_group` ya la arma.
  it "en modo individual no usa mesa de llegada" do
    taller = workshop(mode: "individual")
    result = call(taller, paula)

    expect(result).to be_ok
    expect(result.member.workshop_group.arrival).to be(false)
    expect(result.member.workshop_group.name).to eq("Paula")
  end

  it "rechaza un taller que no está abierto" do
    result = call(workshop(status: "draft"), paula)

    expect(result).not_to be_ok
    expect(result.errors.to_sentence).to match(/no está abierto/i)
  end

  it "rechaza un taller con la presencia presumida" do
    result = call(workshop(registered: false), paula)

    expect(result).not_to be_ok
    expect(result.errors.to_sentence).to match(/no toma asistencia/i)
  end

  # Review Focus 2: dos escaneos en el mismo segundo. El índice UNIQUE parcial
  # es lo que `find_or_create_by!` no puede garantizar, y sin el rescate la
  # segunda persona —que está entrando— se come un 500.
  it "sobrevive a que otro escaneo cree la mesa de llegada en el medio" do
    taller = workshop
    llamadas = 0
    allow_any_instance_of(ActiveRecord::Associations::CollectionProxy)
      .to receive(:find_or_create_by!).and_wrap_original do |original, *args, &blk|
        llamadas += 1
        if llamadas == 1
          as_company(company) { create(:workshop_group, :arrival, workshop: taller) }
          raise ActiveRecord::RecordNotUnique, "index_workshop_groups_on_workshop_id_arrival"
        end
        original.call(*args, &blk)
      end

    result = call(taller, paula)

    expect(result).to be_ok
    expect(result.member.workshop_group.arrival).to be(true)
  end
```

El nombre `"Paula"` del ejemplo individual sale de `users.name`, que la factory
genera como `"Usuario N"`. Ajustar el `create(:user, …)` del helper `member`
para fijar `name: "Paula"` en Paula, o asertar contra `User.find(paula.id).name`
— lo segundo es preferible: no acopla el test a un literal.

- [ ] **Step 2: Correr y verificar que falla**

Run: `make spec-file FILE=spec/lib/flow/workshops/check_in_spec.rb`
Expected: FAIL con `uninitialized constant Flow::Workshops::CheckIn`.

- [ ] **Step 3: El servicio**

`app/lib/flow/workshops/check_in.rb`:

```ruby
# frozen_string_literal: true

module Flow
  module Workshops
    # Entrar al taller escaneando su link. Sienta y marca presente.
    #
    # Es IDEMPOTENTE, y no por prolijidad: un link se escanea dos veces con los
    # dedos fríos, y la pantalla se recarga. La segunda vez marca presente y no
    # mueve a nadie — quien ya estaba convocado a la mesa 3 no termina en la
    # llegada por haber escaneado.
    class CheckIn
      ARRIVAL_NAME = "Mesa de llegada"

      Result = Data.define(:ok, :member, :errors) do
        def ok? = ok
      end

      def initialize(workshop, user)
        @workshop = workshop
        @user = user
      end

      def call
        return failure("Hay que elegir una persona.") if @user.nil?
        # Las dos guardas se repiten aunque el controller ya preguntó: entre que
        # la pantalla se sirvió y el formulario se envió, alguien pudo cerrar el
        # taller o apagar el modo. El que escribe es este servicio.
        return failure("Este taller no está abierto.") unless @workshop.open?
        return failure("Este taller no toma asistencia por link.") unless @workshop.registered_attendance?

        seated = seat_of(@user)
        if seated
          seated.update!(attended: true)
          return Result.new(ok: true, member: seated, errors: [])
        end

        result = Convoke.new(@workshop, @user, group: landing, attended: true).call
        return Result.new(ok: true, member: result.member, errors: []) if result.ok?

        Result.new(ok: false, member: nil, errors: result.errors)
      end

      private

      def seat_of(user)
        WorkshopGroupMember.joins(:workshop_group)
                           .where(workshop_groups: { workshop_id: @workshop.id }, user_id: user.id)
                           .first
      end

      # En modo individual NO hay mesa de llegada: `Convoke#own_group` arma la
      # mesa de una persona, que es el diseño de ese modo. Devolver `nil` es
      # pedirle exactamente eso.
      def landing
        return nil if @workshop.individual?

        @workshop.workshop_groups.find_or_create_by!(arrival: true) { |g| g.name = ARRIVAL_NAME }
      rescue ActiveRecord::RecordNotUnique
        # El índice UNIQUE parcial es justamente lo que un `find_or_create_by!`
        # no puede garantizar: es un SELECT y después un INSERT, y dos escaneos
        # en el mismo segundo lo atraviesan. Que la base frene al segundo es
        # correcto; lo que no corresponde es que quien está entrando vea un 500.
        @workshop.workshop_groups.find_by!(arrival: true)
      end

      def failure(message) = Result.new(ok: false, member: nil, errors: [message])
    end
  end
end
```

- [ ] **Step 4: Correr y verificar que pasa**

Run: `make spec-file FILE=spec/lib/flow/workshops/check_in_spec.rb`
Expected: PASS, 9 ejemplos.

- [ ] **Step 5: Probar que los tests pueden fallar**

```bash
cp app/lib/flow/workshops/check_in.rb /tmp/claude-1000/check_in.rb.bak
```

1. Borrar el `rescue ActiveRecord::RecordNotUnique` y su cuerpo. Tiene que
   fallar «sobrevive a que otro escaneo cree la mesa de llegada».
2. Cambiar la rama de `seated` por `return Result.new(ok: true, member: seated, errors: [])`
   sin el `update!`. Tiene que fallar «lo marca presente sin moverlo».
3. Sacar `return nil if @workshop.individual?`. Tiene que fallar «en modo
   individual no usa mesa de llegada».

Restaurar con `cp`.

- [ ] **Step 6: Commit**

```bash
git add app/lib/flow/workshops/check_in.rb spec/lib/flow/workshops/check_in_spec.rb
git commit -F - <<'MSG'
Entrar al taller sienta en la mesa de llegada y marca presente

Idempotente, porque un link se escanea dos veces con los dedos fríos: la
segunda marca presente y no mueve a nadie. Quien ya estaba convocado a la mesa
3 no termina en la llegada por escanear.

El `find_or_create_by!` de la mesa de llegada rescata RecordNotUnique: es un
SELECT y después un INSERT, así que dos escaneos en el mismo segundo lo
atraviesan y el índice parcial frena al segundo. Que lo frene es correcto; que
quien está entrando vea un 500, no.

En modo individual no hay mesa de llegada: `Convoke#own_group` arma la mesa de
una persona, que es el diseño de ese modo.
MSG
```

---

### Task 4: La ruta pública

**Files:**
- Create: `app/controllers/concerns/authentication.rb`
- Create: `app/controllers/workshop_checkins_controller.rb`
- Create: `app/views/workshop_checkins/show.html.haml`
- Modify: `config/routes.rb` (arriba, al lado de `login`)
- Modify: `app/controllers/application_controller.rb` (`skip_pundit?`, include)
- Modify: `app/controllers/sessions_controller.rb` (usa `sign_in!`)
- Modify: `spec/lint/tenant_bypass_spec.rb` (`ALLOWED`)
- Test: `spec/requests/workshop_checkin_spec.rb`

**Interfaces:**
- Consumes: `Flow::Workshops::CheckIn` (Tarea 3), `Workshop#checkin_state` y
  `#checkin_token` (Tarea 1).
- Produces: `checkin_path(token)` (GET y POST) ·
  `Authentication#sign_in!(user, company:)` → el `Session` creado, con la cookie
  ya puesta. Lo consume `SessionsController#create` y esta tarea.

- [ ] **Step 1: Escribir los tests que fallan**

`spec/requests/workshop_checkin_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# La ÚNICA ruta pública de la app: se entra con el token y sin sesión.
#
# Lo que se fija acá es tanto que entre como que no sea un oráculo: con un
# formulario único para «ya tengo cuenta» y «no tengo», el mensaje de error no
# puede decir si el email existía.
RSpec.describe "check-in por link", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email, role)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, role.to_sym, company: company, user: u)
      u
    end
  end

  let!(:admin) { member("admin@test.dev", :admin) }

  # Sin desafíos vinculados a propósito: nada de lo que se prueba acá los
  # necesita. `CheckIn` pide taller abierto y modo puesto, y `workshops#show`
  # renderiza con `@links` vacío —`MaterializeClosures` sobre cero vínculos no
  # hace nada—. El estado se escribe directo porque lo que se prueba es el
  # check-in y no `Flow::Workshops::Open`.
  def workshop(status: "open", registered: true)
    as_company(company) do
      create(:workshop, status: status,
                        attendance_mode: registered ? "registered" : "presumed")
    end
  end

  let!(:taller) { workshop }
  let(:url) { checkin_path(taller.checkin_token) }

  describe "GET" do
    it "da 404 con un token que no existe" do
      get checkin_path("no-existe")

      expect(response).to have_http_status(:not_found)
    end

    it "sirve el formulario sin sesión" do
      get url

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Entrar al taller")
    end

    # Con el token en la mano ya se sabe que el taller existe, así que decir por
    # qué no se puede entrar no confirma nada. 200 y no 4xx: la pantalla
    # renderizó bien, y `make screens` falla con cualquier >= 400 no declarado.
    it "explica el borrador en vez de dar el formulario" do
      borrador = workshop(status: "draft")
      get checkin_path(borrador.checkin_token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("todavía no está abierto")
      expect(response.body).not_to include("Entrar al taller")
    end

    it "explica el modo apagado" do
      apagado = workshop(registered: false)
      get checkin_path(apagado.checkin_token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("no toma asistencia por link")
    end
  end

  describe "POST sin cuenta" do
    it "crea cuenta, identidad, membresía, asiento presente y sesión" do
      expect {
        post url, params: { email: "nueva@taller.example", name: "Nueva", password: "Test1234" }
      }.to change { without_tenant { User.count } }.by(1)

      user = without_tenant { User.find_by(email: "nueva@taller.example") }
      expect(without_tenant { Identity.exists?(provider: Identity::PASSWORD, uid: user.email) }).to be(true)
      expect(without_tenant { Membership.find_by(user_id: user.id, company_id: company.id).role }).to eq("participant")

      asiento = as_company(company) do
        WorkshopGroupMember.joins(:workshop_group)
                           .find_by(workshop_groups: { workshop_id: taller.id }, user_id: user.id)
      end
      expect(asiento.attended).to be(true)
      expect(response).to redirect_to(workshop_path(taller))

      # La sesión quedó abierta: el taller se puede ver sin volver a loguearse.
      follow_redirect!
      expect(response).to have_http_status(:ok)
    end

    it "rechaza una clave corta sin crear nada" do
      expect {
        post url, params: { email: "corta@taller.example", name: "Corta", password: "123" }
      }.not_to change { without_tenant { User.count } }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST con una cuenta que ya existe" do
    it "entra con la clave correcta sin crear otra cuenta" do
      expect {
        post url, params: { email: "admin@test.dev", name: "Ignorado", password: "Test1234" }
      }.not_to change { without_tenant { User.count } }

      expect(response).to redirect_to(workshop_path(taller))
    end

    # El mensaje es el MISMO del login: si dijera «esa cuenta ya existe» el
    # formulario sería un oráculo de cuentas de toda la instalación.
    it "con la clave mala no revela que el email existe" do
      post url, params: { email: "admin@test.dev", name: "X", password: "mala1234" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("auth.invalid_credentials"))
      expect(response.body).not_to match(/ya (existe|está)/i)
    end

    # Review Focus 1: el teléfono autocapitaliza y agrega un espacio. Sin
    # normalizar, `User` no tiene validación de unicidad y el create choca
    # contra el índice de la base: 500 en la cara de quien está entrando.
    it "normaliza el email tipeado con mayúsculas y espacios" do
      expect {
        post url, params: { email: " Admin@Test.DEV ", name: "X", password: "Test1234" }
      }.not_to change { without_tenant { User.count } }

      expect(response).to redirect_to(workshop_path(taller))
    end

    # Review Focus: escanear su propio QR no le puede bajar el rol a quien
    # administra, ni reventar contra el UNIQUE (user_id, company_id).
    it "no le baja el rol a quien ya es admin" do
      post url, params: { email: "admin@test.dev", name: "X", password: "Test1234" }

      expect(without_tenant { Membership.find_by(user_id: admin.id, company_id: company.id).role }).to eq("admin")
    end

    # Review Focus 4: alguien de otra empresa. Queda con las dos membresías y la
    # sesión en la empresa del taller.
    it "le suma la membresía sin sacarle la que tenía en otra empresa" do
      otra = without_tenant { create(:company, slug: "otra") }
      viajera = without_tenant do
        u = create(:user, email: "viajera@test.dev")
        create(:membership, :participant, company: otra, user: u)
        u
      end

      post url, params: { email: viajera.email, name: "X", password: "Test1234" }

      roles = without_tenant { Membership.where(user_id: viajera.id).pluck(:company_id) }
      expect(roles).to contain_exactly(otra.id, company.id)
      expect(response).to redirect_to(workshop_path(taller))
    end
  end

  describe "POST con sesión viva" do
    it "entra sin pedir el formulario" do
      sign_in(admin, company: company)

      post url

      expect(response).to redirect_to(workshop_path(taller))
      asiento = as_company(company) do
        WorkshopGroupMember.joins(:workshop_group)
                           .find_by(workshop_groups: { workshop_id: taller.id }, user_id: admin.id)
      end
      expect(asiento.attended).to be(true)
    end
  end

  # Review Focus 3: el taller se cierra entre el GET y el POST. Tiene que
  # explicar, no reventar ni redirigir a un taller que todavía no puede ver.
  describe "cuando el taller se cierra entre el GET y el POST" do
    it "explica en vez de entrar" do
      get url
      as_company(company) { taller.update!(status: "closed") }

      post url, params: { email: "tarde@taller.example", name: "Tarde", password: "Test1234" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("ya cerró")
      expect(without_tenant { User.exists?(email: "tarde@taller.example") }).to be(false)
    end
  end
end
```

- [ ] **Step 2: Correr y verificar que falla**

Run: `make spec-file FILE=spec/requests/workshop_checkin_spec.rb`
Expected: FAIL con `undefined method 'checkin_path'`.

- [ ] **Step 3: Las rutas**

En `config/routes.rb`, debajo del bloque de `login`/`logout`:

```ruby
  # La ÚNICA ruta pública de la app: se entra escaneando el QR de un taller, sin
  # sesión y sin empresa en contexto —el tenant sale del token—. Va acá y no
  # colgada de `workshops` porque quien la abre todavía no puede ver ningún
  # taller.
  get  "checkin/:token", to: "workshop_checkins#show", as: :checkin
  post "checkin/:token", to: "workshop_checkins#create"
```

- [ ] **Step 4: El concern de la sesión**

`app/controllers/concerns/authentication.rb`:

```ruby
# frozen_string_literal: true

# Abrir sesión: la fila en `sessions` y la cookie firmada.
#
# Vive acá y no en cada controller que lo hace porque las tres banderas de la
# cookie —permanente, httponly, same_site— tienen que decidirse UNA vez. Dos
# políticas de cookie que el día que difieran una de las dos está mal es peor
# que el concern.
module Authentication
  extend ActiveSupport::Concern

  private

  def sign_in!(user, company:)
    record = user.sessions.create!(
      company: company,
      ip_address: request.remote_ip,
      user_agent: request.user_agent.to_s.first(255),
      last_seen_at: Time.current
    )
    cookies.signed.permanent[:session_token] = { value: record.token, httponly: true, same_site: :lax }
    record
  end
end
```

En `app/controllers/application_controller.rb`, sumar el include y extender
`skip_pundit?`:

```ruby
  include Pundit::Authorization
  include TenantResolution
  include Authentication
```

```ruby
  # Ninguno de los dos tiene qué autorizar: en el login todavía no hay membresía
  # con la cual, y en el check-in por link la autorización ES el token.
  def skip_pundit?
    is_a?(SessionsController) || is_a?(WorkshopCheckinsController)
  end
```

En `app/controllers/sessions_controller.rb`, reemplazar el `create!` + cookie
por el concern:

```ruby
    if user&.authenticate(params[:password].to_s)
      session_record = sign_in!(user, company: default_company_for(user))
      redirect_to(session_record.company ? root_path : select_company_path)
```

- [ ] **Step 5: El controller público**

`app/controllers/workshop_checkins_controller.rb`:

```ruby
# frozen_string_literal: true

# Entrar a un taller escaneando su QR. La ÚNICA ruta pública de la app.
#
# El tenant sale del TOKEN y no de la sesión, porque quien abre esto todavía no
# tiene ninguna: es la misma razón por la que `SessionsController` ya levanta el
# scoping —el tenant es lo que estas pantallas ESTABLECEN, no algo que reciben—.
#
# Saltea las tres puertas de `ApplicationController`. La autorización es el
# token: es de UN taller, sirve sólo con el taller abierto y el modo puesto, y se
# revoca rotándolo.
class WorkshopCheckinsController < ApplicationController
  skip_before_action :require_authentication
  skip_before_action :require_company

  layout "auth"

  before_action :set_workshop

  # El GET NUNCA muta. El link viaja por cámara y por chat, y un prefetch del
  # navegador o de quien lo reenvía no puede sentar a nadie. Siempre renderiza;
  # el botón POSTea.
  def show; end

  def create
    # Entre el GET y el POST alguien pudo cerrar el taller o apagar el modo: se
    # explica sobre la misma pantalla y NO se crea ninguna cuenta.
    return render(:show) unless @workshop.checkin_open?

    user = signed_in? ? current_user : resolve_user
    return render(:show, status: :unprocessable_content) if user.nil?

    ensure_membership(user)
    sign_in!(user, company: @workshop.company) unless signed_in?

    result = Flow::Workshops::CheckIn.new(@workshop, user).call
    if result.ok?
      redirect_to workshop_path(@workshop), notice: "Listo: estás en el taller."
    else
      flash.now[:alert] = result.errors.to_sentence
      render :show, status: :unprocessable_content
    end
  end

  private

  def set_workshop
    # `Workshop` es `TenantScoped`: sin el bypass esta consulta revienta con
    # `MissingTenant` antes de encontrar nada. La excepción está declarada en
    # `spec/lint/tenant_bypass_spec.rb` con su razón.
    @workshop = Flow::Tenant.bypass! { Workshop.find_by(checkin_token: params[:token]) }
    raise ActiveRecord::RecordNotFound if @workshop.nil?

    # Desde acá el request corre dentro de la empresa del taller: es lo que
    # `require_company` haría si hubiera sesión.
    Current.company = @workshop.company
  end

  # Un solo formulario para «ya tengo cuenta» y «no tengo», y sin oráculo: un
  # email que existe se autentica, uno nuevo se crea, y cuando falla el mensaje
  # es el MISMO del login. Así la pantalla no dice si el email estaba.
  def resolve_user
    # Normalizar a mano, igual que `SessionsController#create`. `User` NO tiene
    # validación de unicidad —sólo presencia y formato—, así que un email
    # autocapitalizado por el teléfono no se encontraría y el `create` chocaría
    # contra el índice único de la base: 500 en la cara de quien está entrando.
    email = params[:email].to_s.strip.downcase
    existing = User.find_by(email: email)
    return authenticated(existing) if existing

    user = User.new(email: email, name: params[:name].to_s.strip, password: params[:password].to_s)
    unless user.save
      flash.now[:alert] = user.errors.full_messages.to_sentence
      return nil
    end

    Identity.create!(user: user, provider: Identity::PASSWORD, uid: user.email)
    user
  end

  def authenticated(user)
    return user if user.authenticate(params[:password].to_s)

    flash.now[:alert] = t("auth.invalid_credentials")
    nil
  end

  # El rol va SÓLO en el bloque de creación. Con `role: "participant"` en el
  # `where`, quien ya es admin no se encontraría, el `create` chocaría contra el
  # UNIQUE (user_id, company_id) y en el mejor de los casos le bajaría el rol a
  # quien lleva el taller por escanear su propio QR.
  def ensure_membership(user)
    Membership.find_or_create_by!(user_id: user.id) { |m| m.role = "participant" }
  end
end
```

`User`, `Identity` y `Session` **no** son `TenantScoped` —el email es único en
toda la instalación—, así que no necesitan bypass. `Membership` sí lo es, y por
eso `Current.company` ya está puesto cuando se la crea.

- [ ] **Step 6: La vista**

`app/views/workshop_checkins/show.html.haml`:

```haml
-# La pantalla del escaneo. Layout `auth`: sin bundle de JS, que es lo que se
-# quiere en un teléfono con la red del lugar.
-#
-# `case` sobre un valor cerrado y no una cadena de `elsif`: es la forma que
-# `WorkshopChallenge#room_state` ya fijó, y lo que hace que un estado nuevo se
-# vea en vez de dejar la pantalla muda.
- content_for :title, @workshop.name

%h1.page-title= @workshop.name

- case @workshop.checkin_state
- when :open
  %p.muted Registrate para entrar. Si ya tenés cuenta, entrá con tu clave.
  = form_with url: checkin_path(@workshop.checkin_token), method: :post do
    - if signed_in?
      %p.muted= "Vas a entrar como #{current_user.name}."
    - else
      %div
        = label_tag :email, "Correo"
        = email_field_tag :email, params[:email], required: true, autocomplete: "email"
      %div
        = label_tag :name, "Nombre"
        = text_field_tag :name, params[:name], autocomplete: "name"
      %div
        = label_tag :password, "Clave"
        = password_field_tag :password, nil, required: true, autocomplete: "current-password"
        %p.field-hint Si es tu primera vez, es la clave que vas a usar de ahora en más: ocho caracteres o más.
    = submit_tag "Entrar al taller", class: "btn btn-primary"
- when :draft
  %p.muted Este taller todavía no está abierto. Volvé a escanear cuando empiece.
- when :closed
  %p.muted Este taller ya cerró.
- else
  %p.muted Este taller no toma asistencia por link.
```

- [ ] **Step 7: El lint de bypass**

En `spec/lint/tenant_bypass_spec.rb`, dentro de `ALLOWED`:

```ruby
    "app/controllers/workshop_checkins_controller.rb" =>
      "el check-in por link entra sin sesión: el taller se busca POR TOKEN y el tenant sale de ahí",
```

- [ ] **Step 8: Correr y verificar que pasa**

Run: `make spec-file FILE=spec/requests/workshop_checkin_spec.rb`
Expected: PASS, 13 ejemplos.

Run: `make spec-file FILE=spec/lint/tenant_bypass_spec.rb`
Run: `make spec-file FILE=spec/requests/authentication_spec.rb`
Expected: PASS las dos — la segunda es la que cubre que el refactor de
`sign_in!` no cambió el login.

- [ ] **Step 9: Probar que los tests pueden fallar**

```bash
cp app/controllers/workshop_checkins_controller.rb /tmp/claude-1000/checkins.rb.bak
```

1. En `resolve_user`, cambiar `email = params[:email].to_s.strip.downcase` por
   `email = params[:email].to_s`. Tiene que fallar «normaliza el email tipeado
   con mayúsculas y espacios».
2. En `ensure_membership`, pasar el rol al `where`:
   `find_or_create_by!(user_id: user.id, role: "participant")`. Tiene que fallar
   «no le baja el rol a quien ya es admin».
3. En `create`, borrar el `return render(:show) unless @workshop.checkin_open?`.
   Tiene que fallar «explica en vez de entrar».
4. En `authenticated`, cambiar el mensaje por `"Esa cuenta ya existe."`. Tiene
   que fallar «no revela que el email existe».

Restaurar con `cp`.

- [ ] **Step 10: Commit**

```bash
git add app/controllers app/views/workshop_checkins config/routes.rb spec/requests/workshop_checkin_spec.rb spec/lint/tenant_bypass_spec.rb
git commit -F - <<'MSG'
Se entra al taller por link, sin sesión y sin empresa en contexto

La primera ruta pública de la app. El tenant sale del TOKEN, que es la misma
razón por la que el login ya levanta el scoping: el tenant es lo que estas
pantallas establecen, no algo que reciben. La excepción queda declarada en el
lint con su razón.

El GET nunca muta —el link viaja por cámara y por chat, y un prefetch no puede
sentar a nadie—, así que siempre renderiza y el botón POSTea. Eso es además lo
que hace funcionar el CSRF: el token viaja con el formulario servido.

Un solo formulario para «ya tengo cuenta» y «no tengo», y el mensaje de error es
el mismo del login: si dijera que el email ya existe, la pantalla sería un
oráculo de cuentas de toda la instalación. El email se normaliza a mano porque
User no valida unicidad, así que uno autocapitalizado por el teléfono chocaría
contra el índice de la base.

El rol de la membresía va sólo en el bloque de creación: con `role:` en el
`where`, quien administra se bajaba a participante por escanear su propio QR.

Y las cinco líneas de la cookie salen a un concern que usan los dos controllers.
Dos políticas de cookie que algún día difieren es peor que el refactor.
MSG
```

---

### Task 5: La mesa de llegada es sala de espera

**Files:**
- Modify: `app/models/workshop_group.rb` (`workable_ideas`)
- Modify: `app/views/workshops/_sala_idear.html.haml`
- Modify: `app/views/workshops/_sala_evolucion.html.haml`
- Modify: `app/controllers/workshop_ideas_controller.rb`
- Modify: `app/controllers/workshop_proposals_controller.rb`
- Test: `spec/requests/workshop_arrival_spec.rb`

**Interfaces:**
- Consumes: `WorkshopGroup#arrival?` (Tarea 1), `CheckIn` (Tarea 3).
- Produces: nada que otra tarea consuma.

- [ ] **Step 1: Escribir los tests que fallan**

`spec/requests/workshop_arrival_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# De la mesa de llegada NO se trabaja, y son cuatro puertas porque cada sala
# tiene lectura y escritura.
#
# No es prolijidad: `WorkshopIdeasController` escribe `idea_contributors` para
# TODA la mesa, así que el primer borrador creado desde una llegada compartida
# nacería con sus treinta integrantes ESCRITOS, y repartir no los borra.
RSpec.describe "la mesa de llegada no trabaja", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email, role)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, role.to_sym, company: company, user: u)
      u
    end
  end

  let!(:paula) { member("paula@test.dev", :participant) }

  # Un taller abierto con UN vínculo en `kind`, con Paula en la mesa de llegada.
  def taller_con_llegada(kind:)
    as_company(company) do
      taller = create(:workshop, :registered, status: "open")
      challenge = create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: kind, status: "active")
      create(:form_field, challenge_step: step, key: "titulo", label: "Título") if kind == "ideation"
      link = create(:workshop_challenge, workshop: taller, challenge: challenge,
                                         challenge_step: step, status: "open")
      Flow::Workshops::CheckIn.new(taller, User.find(paula.id)).call
      [taller, link, challenge, step]
    end
  end

  describe "idear" do
    it "la sala no ofrece el formulario" do
      taller, = taller_con_llegada(kind: "ideation")
      sign_in(paula, company: company)

      get workshop_path(taller)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("todavía no se armó")
      expect(response.body).not_to include("Crear borrador")
    end

    it "el POST rechaza y no crea la idea" do
      taller, link = taller_con_llegada(kind: "ideation")
      sign_in(paula, company: company)

      expect {
        post workshop_sala_ideas_path(taller, link), params: { payload: { titulo: "Desde la llegada" } }
      }.not_to change { as_company(company) { Idea.count } }

      expect(response).to redirect_to(workshop_path(taller))
      follow_redirect!
      expect(response.body).to include("todavía no se armó")
    end
  end

  describe "evolución" do
    it "no lista ninguna idea de los otros integrantes" do
      taller, link, challenge, step = taller_con_llegada(kind: "evolution")
      otra = member("otra@test.dev", :participant)
      as_company(company) do
        Flow::Workshops::CheckIn.new(taller, User.find(otra.id)).call
        idea = create(:idea, challenge: challenge, author_id: otra.id, status: "submitted")
        # No hay factory de `StepEntry`: se crea con el modelo, igual que ya lo
        # hacen `assign_groups_spec.rb:27` y `workshop_mesas_spec.rb:130`.
        StepEntry.create!(challenge_step: step, idea: idea)
      end
      sign_in(paula, company: company)

      get workshop_path(taller)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("todavía no se armó")
      expect(response.body).not_to include("Proponer")
    end

    it "el POST rechaza y no crea la propuesta" do
      taller, link, challenge = taller_con_llegada(kind: "evolution")
      idea = as_company(company) { create(:idea, challenge: challenge, author_id: paula.id, status: "submitted") }
      sign_in(paula, company: company)

      expect {
        post workshop_sala_proposals_path(taller, link),
             params: { idea_id: idea.id, payload: { titulo: "X" } }
      }.not_to change { as_company(company) { WorkshopProposal.count } }
    end
  end

  describe "#workable_ideas" do
    it "no devuelve nada desde la mesa de llegada" do
      taller, _link, challenge = taller_con_llegada(kind: "evolution")
      as_company(company) do
        create(:idea, challenge: challenge, author_id: paula.id, status: "submitted")
        llegada = taller.workshop_groups.find_by!(arrival: true)

        expect(llegada.workable_ideas(challenge)).to be_empty
      end
    end
  end
end
```

Las factories que esto usa existen en `spec/factories/core.rb`: `:idea`
(con `challenge`, `author`, `status`), `:form_field` (con `challenge_step`,
`label`, `field_type`, y acepta `key:` porque es columna) y `:challenge_step`
(con sus traits `:ideation`, `:evolution`, `:active`). **`StepEntry` no tiene
factory** y se crea con el modelo.

- [ ] **Step 2: Correr y verificar que falla**

Run: `make spec-file FILE=spec/requests/workshop_arrival_spec.rb`
Expected: FAIL — hoy la sala ofrece el formulario y el POST crea la idea con
toda la mesa como contribuyentes.

- [ ] **Step 3: La lectura de evolución**

En `app/models/workshop_group.rb`, al principio de `workable_ideas`:

```ruby
  def workable_ideas(challenge)
    # La mesa de llegada no trabaja: es la sala de espera hasta que alguien
    # reparte. Acá es donde más importa, porque esto es la UNIÓN sobre los
    # integrantes: con treinta recién llegados, cada uno vería y propondría
    # sobre las ideas de los otros veintinueve.
    return Idea.none if arrival?

    member_ids = workshop_group_members.select(:user_id)
```

- [ ] **Step 4: Las dos salas**

En `app/views/workshops/_sala_idear.html.haml`, después de la rama
`- if group.nil?`:

```haml
    - elsif group.arrival?
      -# Mismo mensaje y misma pregunta que las otras tres puertas, para que no
      -# puedan divergir.
      %p.muted Tu mesa todavía no se armó: en cuanto se reparta, acá aparece el formulario.
```

En `app/views/workshops/_sala_evolucion.html.haml`, igual, después de
`- if group.nil?`:

```haml
    - elsif group.arrival?
      %p.muted Tu mesa todavía no se armó: en cuanto se reparta, acá aparecen las ideas para proponer.
```

- [ ] **Step 5: Las dos escrituras**

En `app/controllers/workshop_ideas_controller.rb`, después de
`return reject_without_group unless group`:

```ruby
    return reject_arrival if group.arrival?
```

y el método privado:

```ruby
  # La mesa de llegada no trabaja. El rechazo es explícito y con su mensaje: un
  # 404 pelado en una sala que debería decir «tu mesa todavía no se armó» es el
  # control que no responde.
  def reject_arrival
    redirect_to workshop_path(@workshop),
                alert: "Tu mesa todavía no se armó: esperá el reparto para trabajar."
  end
```

En `app/controllers/workshop_proposals_controller.rb`, lo mismo, también después
de `return reject_without_group unless group` y con el mismo método privado.

- [ ] **Step 6: Correr y verificar que pasa**

Run: `make spec-file FILE=spec/requests/workshop_arrival_spec.rb`
Expected: PASS, 5 ejemplos.

- [ ] **Step 7: Probar que los tests pueden fallar**

Mutar de a una, con backup por `cp`, y correr el archivo entre cada una:

1. Sacar `return Idea.none if arrival?` de `workable_ideas`. Tiene que fallar
   «#workable_ideas no devuelve nada» y «no lista ninguna idea».
2. Sacar `return reject_arrival if group.arrival?` de
   `workshop_ideas_controller.rb`. Tiene que fallar «el POST rechaza y no crea
   la idea».
3. Sacar la rama `elsif group.arrival?` de `_sala_idear`. Tiene que fallar «la
   sala no ofrece el formulario».

**Cada una tiene que romper al menos un ejemplo.** Si alguna da verde, el test
que la cubría no la estaba cubriendo: es el defecto que esta rama ya vio cinco
veces.

- [ ] **Step 8: Commit**

```bash
git add app/models/workshop_group.rb app/views/workshops app/controllers/workshop_ideas_controller.rb app/controllers/workshop_proposals_controller.rb spec/requests/workshop_arrival_spec.rb
git commit -F - <<'MSG'
De la mesa de llegada no se trabaja, y son cuatro puertas

Cada sala tiene lectura y escritura, así que la regla se pregunta en cuatro
lugares y con la misma pregunta —`group.arrival?`— para que no puedan divergir.

No es prolijidad. `WorkshopIdeasController` escribe idea_contributors para toda
la mesa desde el minuto cero, que es lo que hace que «veo las ideas de mi mesa»
sea IdeaPolicy::Scope tal como está. Con una llegada compartida de treinta
personas, el primer borrador creado antes del reparto nace con las treinta
ESCRITAS: repartir después no lo deshace, y IdeaContributor alimenta el scope y
los racimos del reparto para siempre.

El rechazo del POST es explícito aunque workable_ideas ya devuelva none y el
find_by! dé 404: un 404 pelado en una sala que debería decir «tu mesa todavía no
se armó» es el control que no responde.
MSG
```

---

### Task 6: El QR y los tres controles

**Files:**
- Modify: `Gemfile`
- Create: `app/helpers/checkin_helper.rb`
- Create: `app/views/workshops/_checkin.html.haml`
- Modify: `app/views/workshops/_assembly.html.haml`
- Modify: `config/routes.rb` (tres member de `workshops`)
- Modify: `app/controllers/workshops_controller.rb`
- Test: `spec/requests/workshop_checkin_settings_spec.rb`

**Interfaces:**
- Consumes: `Workshop#checkin_state`, `#checkin_token`,
  `#regenerate_checkin_token` (Tarea 1), `checkin_url` (Tarea 4).
- Produces: `enable_checkin_workshop_path`, `disable_checkin_workshop_path`,
  `rotate_checkin_token_workshop_path` · `CheckinHelper#qr_svg(url)`.

- [ ] **Step 1: La gema**

En `Gemfile`, junto a las otras de presentación:

```ruby
# El QR del check-in del taller. Ruby puro y SIN red: el SVG se arma en el
# server, así que no hay que pedirle una imagen a un tercero ni montar una isla
# para dibujarla.
gem "rqrcode", "~> 2.2"
```

Run: `make rebuild`

Verificar que la gema quedó y que las opciones de `as_svg` son las que el helper
usa (los nombres cambiaron entre 1.x y 2.x):

```bash
docker compose exec app bin/rails runner 'puts RQRCode::QRCode.new("https://x.test/checkin/abc").as_svg(use_path: true, viewbox: true, color: "000000")[0, 200]'
```

Expected: un `<svg …><path …` y ningún error de keyword.

- [ ] **Step 2: Escribir el test que falla**

`spec/requests/workshop_checkin_settings_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# Activar el check-in, apagarlo y rotar el link. Los tres detrás de `update?`, y
# los tres con el taller ABIERTO: activarlo con la gente llegando es el caso.
RSpec.describe "los controles del check-in", type: :request do
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

  let!(:taller) do
    as_company(company) do
      t = create(:workshop, status: "draft")
      challenge = create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: "ideation", status: "active")
      create(:workshop_challenge, workshop: t, challenge: challenge, challenge_step: step, status: "open")
      t.update!(status: "open")
      t
    end
  end

  it "quien administra lo activa con el taller abierto" do
    sign_in(admin, company: company)

    post enable_checkin_workshop_path(taller)

    expect(as_company(company) { taller.reload.attendance_mode }).to eq("registered")
  end

  it "lo apaga" do
    as_company(company) { taller.update!(attendance_mode: "registered") }
    sign_in(admin, company: company)

    post disable_checkin_workshop_path(taller)

    expect(as_company(company) { taller.reload.attendance_mode }).to eq("presumed")
  end

  # Rotar es la revocación: el QR que alguien fotografió deja de servir.
  it "rotar invalida el link anterior" do
    as_company(company) { taller.update!(attendance_mode: "registered") }
    anterior = taller.checkin_token
    sign_in(admin, company: company)

    post rotate_checkin_token_workshop_path(taller)

    expect(as_company(company) { taller.reload.checkin_token }).not_to eq(anterior)
    get checkin_path(anterior)
    expect(response).to have_http_status(:not_found)
  end

  # Cambiar el modo NO reescribe la asistencia ya registrada: sería destruir
  # dato por un cambio de configuración. Para eso está el toggle.
  it "activar el modo no marca ausente a quien ya estaba presente" do
    mesa = as_company(company) { create(:workshop_group, workshop: taller) }
    asiento = as_company(company) do
      WorkshopGroupMember.create!(workshop_group: mesa, user_id: paula.id, attended: true)
    end
    sign_in(admin, company: company)

    post enable_checkin_workshop_path(taller)

    expect(as_company(company) { asiento.reload.attended }).to be(true)
  end

  it "quien participa no puede activarlo" do
    as_company(company) do
      mesa = create(:workshop_group, workshop: taller)
      WorkshopGroupMember.create!(workshop_group: mesa, user_id: paula.id)
    end
    sign_in(paula, company: company)

    post enable_checkin_workshop_path(taller)

    expect(response).to have_http_status(:forbidden)
  end

  describe "la pantalla" do
    it "ofrece activarlo, y con el modo puesto muestra el link" do
      sign_in(admin, company: company)
      get workshop_path(taller)
      expect(response.body).to include(enable_checkin_workshop_path(taller))

      as_company(company) { taller.update!(attendance_mode: "registered") }
      get workshop_path(taller)

      expect(response.body).to include(taller.checkin_token)
      expect(response.body).to include(rotate_checkin_token_workshop_path(taller))
      expect(response.body).to include("<svg")
    end

    it "no se lo ofrece a quien participa" do
      as_company(company) do
        mesa = create(:workshop_group, workshop: taller)
        WorkshopGroupMember.create!(workshop_group: mesa, user_id: paula.id)
      end
      sign_in(paula, company: company)

      get workshop_path(taller)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(enable_checkin_workshop_path(taller))
    end
  end
end
```

- [ ] **Step 3: Correr y verificar que falla**

Run: `make spec-file FILE=spec/requests/workshop_checkin_settings_spec.rb`
Expected: FAIL con `undefined method 'enable_checkin_workshop_path'`.

- [ ] **Step 4: Las rutas y las tres acciones**

En `config/routes.rb`, dentro del `member do` de `resources :workshops`:

```ruby
      # El check-in NO va por `workshops#update`, que es sólo de borrador:
      # activarlo tiene que poder hacerse con el taller ABIERTO, que es cuando
      # la gente está llegando.
      post :enable_checkin
      post :disable_checkin
      post :rotate_checkin_token
```

En `app/controllers/workshops_controller.rb`, sumar las tres al `before_action
:set_workshop` y definirlas:

```ruby
  # Activar y apagar el check-in por link, y rotar el link.
  #
  # Cambiar el modo NO reescribe la asistencia ya registrada: quien fue
  # convocado a mano antes de activarlo sigue presente sin haber escaneado.
  # Reescribirlo sería destruir dato por un cambio de configuración, y para eso
  # está el toggle de cada integrante.
  def enable_checkin
    authorize @workshop, :update?
    @workshop.update!(attendance_mode: "registered")
    redirect_to workshop_path(@workshop), notice: "Check-in por link activado."
  end

  def disable_checkin
    authorize @workshop, :update?
    @workshop.update!(attendance_mode: "presumed")
    redirect_to workshop_path(@workshop),
                notice: "Check-in por link apagado. El reparto vuelve a sentar a todo el pool."
  end

  def rotate_checkin_token
    authorize @workshop, :update?
    @workshop.regenerate_checkin_token
    redirect_to workshop_path(@workshop), notice: "Link nuevo. El QR anterior ya no sirve."
  end
```

Y en `set_workshop`, agregar las tres al `only:` del `before_action`.

- [ ] **Step 5: El helper**

`app/helpers/checkin_helper.rb`:

```ruby
# frozen_string_literal: true

module CheckinHelper
  # El QR del taller, como SVG servido por el server.
  #
  # Va NEGRO SOBRE BLANCO en los DOS temas, y el color es un literal y no un
  # token: un lector de QR no es un elemento de la hoja, y un QR invertido
  # —módulos claros sobre fondo oscuro— lo leen mal muchos teléfonos. El fondo
  # blanco lo pone el contenedor en la vista.
  #
  # `viewbox: true` es lo que deja que el tamaño lo decida el contenedor, así
  # que acá no hay medidas.
  def qr_svg(url)
    RQRCode::QRCode.new(url, level: :m)
                   .as_svg(use_path: true, viewbox: true, color: "000000")
                   .html_safe
  end
end
```

- [ ] **Step 6: El partial**

`app/views/workshops/_checkin.html.haml`:

```haml
-# El QR del taller. Se renderiza desde `_assembly`, detrás del mismo
-# `can_assemble`; acá no se vuelve a preguntar el permiso.
-#
-# `case` sobre `checkin_state` y no una cadena de `elsif`: es el mismo valor
-# cerrado que lee la pantalla pública, así que las dos dicen lo mismo.
.card
  .card-body
    .section-head
      %h2.section-title Check-in por link

    - if workshop.presumed_attendance?
      %p.muted Con el check-in activado, quien escanea entra solo: queda convocado y marcado presente. Quien no escanea queda ausente, y el reparto sienta sólo a los presentes.
      = button_to "Activar check-in por link", enable_checkin_workshop_path(workshop), method: :post,
                  class: "btn btn-primary btn-sm"
    - else
      - case workshop.checkin_state
      - when :open
        %p.muted Proyectá este código. Quien lo escanea entra al taller, y si no tiene cuenta la crea ahí mismo.
      - when :draft
        %p.muted El código ya está, pero recién sirve cuando abras el taller.
      - else
        %p.muted Este taller cerró: el código ya no deja entrar a nadie.

      -# Fondo blanco explícito y en los dos temas: lo de adentro es un lector,
      -# no un elemento temable.
      .bg-white.p-4.rounded-box.w-60
        = qr_svg(checkin_url(workshop.checkin_token))

      %p.field-hint= checkin_url(workshop.checkin_token)

      .assignment-row__actions
        = button_to "Rotar el link", rotate_checkin_token_workshop_path(workshop), method: :post,
                    class: "btn btn-ghost btn-sm",
                    form: { data: { turbo_confirm: "¿Rotar el link? El QR que ya se proyectó o se fotografió deja de servir." } }
        = button_to "Apagar el check-in", disable_checkin_workshop_path(workshop), method: :post,
                    class: "btn btn-ghost btn-sm",
                    form: { data: { turbo_confirm: "¿Apagar el check-in? El reparto vuelve a sentar a todo el pool de la empresa, no sólo a quien escaneó." } }
```

En `app/views/workshops/_assembly.html.haml`, debajo del render de los grupos:

```haml
= render "workshops/checkin", workshop: workshop
```

Los dos `button_to` del final son **hermanos** y no están dentro de ningún otro
formulario: un `button_to` es un `<form>`, y uno dentro de otro es HTML inválido
que el navegador aplana sin dejar rastro en el DOM.

- [ ] **Step 7: Correr y verificar que pasa**

Run: `make spec-file FILE=spec/requests/workshop_checkin_settings_spec.rb`
Expected: PASS, 7 ejemplos.

Run: `make spec-file FILE=spec/lint/clases_interpoladas_spec.rb`
Run: `make spec-file FILE=spec/lint/reglas_sin_elemento_spec.rb`
Expected: PASS las dos. Si la segunda se queja de una clase sin uso, es porque
`w-60` / `bg-white` son utilidades de Tailwind y no clases propias de la hoja —
ese spec mira las clases declaradas en `application.css`, así que no debería
tocarlo. Si lo toca, leer su comentario antes de agregar una excepción.

- [ ] **Step 8: Probar que los tests pueden fallar**

1. En `rotate_checkin_token`, cambiar `regenerate_checkin_token` por un
   `update!(updated_at: Time.current)`. Tiene que fallar «rotar invalida el link
   anterior».
2. En `enable_checkin`, agregar un
   `WorkshopGroupMember.where(workshop_id: @workshop.id).update_all(attended: false)`.
   Tiene que fallar «activar el modo no marca ausente».
3. Cambiar `authorize @workshop, :update?` por `authorize @workshop, :show?` en
   `enable_checkin`. Tiene que fallar «quien participa no puede activarlo».

Restaurar con `cp`.

- [ ] **Step 9: Commit**

```bash
git add Gemfile Gemfile.lock app/helpers/checkin_helper.rb app/views/workshops config/routes.rb app/controllers/workshops_controller.rb spec/requests/workshop_checkin_settings_spec.rb
git commit -F - <<'MSG'
El taller proyecta su QR, lo apaga y lo rota

El SVG lo arma el server con rqrcode: Ruby puro y sin red, así que no hay que
pedirle una imagen a un tercero ni montar una isla para dibujarla. Negro sobre
blanco en los dos temas y con el color literal: un lector de QR no es un
elemento temable, y uno invertido lo leen mal muchos teléfonos.

Las tres acciones no van por workshops#update, que es sólo de borrador:
activar el check-in tiene que poder hacerse con el taller ABIERTO, que es
cuando la gente está llegando.

Cambiar el modo no reescribe la asistencia ya registrada —sería destruir dato
por un cambio de configuración— y apagarlo devuelve el pool de idear a toda la
empresa, que es lo que dice el confirm.

El link va en texto debajo del código: la cámara falla y el lugar tiene mala luz.
MSG
```

---

### Task 7: El toggle de presencia

**Files:**
- Create: `app/controllers/workshop_attendances_controller.rb`
- Modify: `config/routes.rb`
- Modify: `app/views/workshops/_groups.html.haml`
- Modify: `app/controllers/workshops_controller.rb:40` (el `includes` de `@groups`)
- Test: `spec/requests/workshop_attendances_spec.rb`

**Interfaces:**
- Consumes: `WorkshopGroupMember#attended` (ya existía).
- Produces: `attendance_workshop_path(workshop)` (PATCH, con `user_id` y
  `attended`).

- [ ] **Step 1: Escribir el test que falla**

`spec/requests/workshop_attendances_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# Marcar presente o ausente a mano. Es el único escritor de presencia en un
# taller con la asistencia presumida, y el que cubre a quien vino sin teléfono.
RSpec.describe "la asistencia a mano", type: :request do
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

  let!(:taller) { as_company(company) { create(:workshop, status: "open") } }
  let!(:asiento) do
    as_company(company) do
      mesa = create(:workshop_group, workshop: taller)
      WorkshopGroupMember.create!(workshop_group: mesa, user_id: paula.id, attended: true)
    end
  end

  it "marca ausente" do
    sign_in(admin, company: company)

    patch attendance_workshop_path(taller), params: { user_id: paula.id, attended: "false" }

    expect(as_company(company) { asiento.reload.attended }).to be(false)
  end

  it "marca presente de vuelta" do
    as_company(company) { asiento.update!(attended: false) }
    sign_in(admin, company: company)

    patch attendance_workshop_path(taller), params: { user_id: paula.id, attended: "true" }

    expect(as_company(company) { asiento.reload.attended }).to be(true)
  end

  it "no lo puede hacer quien participa" do
    sign_in(paula, company: company)

    patch attendance_workshop_path(taller), params: { user_id: paula.id, attended: "false" }

    expect(response).to have_http_status(:forbidden)
    expect(as_company(company) { asiento.reload.attended }).to be(true)
  end

  # Con el taller cerrado no se toca nada, igual que convocar y desconvocar.
  it "no toca nada con el taller cerrado" do
    as_company(company) { taller.update!(status: "closed") }
    sign_in(admin, company: company)

    patch attendance_workshop_path(taller), params: { user_id: paula.id, attended: "false" }

    expect(as_company(company) { asiento.reload.attended }).to be(true)
  end

  it "da 404 por alguien que no está sentado" do
    pedro = member("pedro@test.dev", :participant)
    sign_in(admin, company: company)

    patch attendance_workshop_path(taller), params: { user_id: pedro.id, attended: "false" }

    expect(response).to have_http_status(:not_found)
  end

  describe "el control" do
    it "lo ve quien administra, con el estado actual" do
      sign_in(admin, company: company)

      get workshop_path(taller)

      expect(response.body).to include(attendance_workshop_path(taller))
      expect(response.body).to include("Marcar ausente")
    end

    it "no lo ve quien participa" do
      sign_in(paula, company: company)

      get workshop_path(taller)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(attendance_workshop_path(taller))
    end
  end
end
```

- [ ] **Step 2: Correr y verificar que falla**

Run: `make spec-file FILE=spec/requests/workshop_attendances_spec.rb`
Expected: FAIL con `undefined method 'attendance_workshop_path'`.

- [ ] **Step 3: La ruta y el controller**

En `config/routes.rb`, en el `member do` de `workshops`, al lado de `convoke` y
`dismiss`:

```ruby
      # Marcar presente o ausente. `to:` explícito por lo mismo que `convoke`:
      # sin él mapearía a `workshops#attendance`, que no existe.
      patch :attendance, to: "workshop_attendances#update"
```

`app/controllers/workshop_attendances_controller.rb`:

```ruby
# frozen_string_literal: true

# Marcar presente o ausente a mano.
#
# Es el único escritor de presencia en un taller con la asistencia PRESUMIDA, y
# el que cubre a quien vino sin teléfono en uno con check-in por link.
class WorkshopAttendancesController < ApplicationController
  before_action :set_workshop

  def update
    authorize @workshop, :manage_groups?
    # Con el taller cerrado no se toca nada, igual que convocar y desconvocar:
    # cambiar la asistencia de una sesión que terminó no arregla nada.
    return reject_closed if @workshop.closed?

    seat = WorkshopGroupMember.joins(:workshop_group)
                              .where(workshop_groups: { workshop_id: @workshop.id })
                              .find_by!(user_id: params[:user_id])
    seat.update!(attended: ActiveModel::Type::Boolean.new.cast(params[:attended]))

    redirect_to workshop_path(@workshop),
                notice: seat.attended? ? "Marcada presente." : "Marcada ausente."
  end

  private

  # `policy_scope(...).find_by!` y no `Workshop.find_by!`: así lo que no se ve
  # da 404 y no 403, que sería un oráculo de existencia.
  def set_workshop = @workshop = policy_scope(Workshop).find_by!(id: params[:id])

  def reject_closed
    redirect_to workshop_path(@workshop), alert: "Este taller ya cerró: la asistencia queda como está."
  end
end
```

- [ ] **Step 4: El control en la pantalla**

El partial hoy itera `group.members`, que son `User` y no traen `attended`. Hay
que iterar los ASIENTOS. En `app/views/workshops/_groups.html.haml`, reemplazar
el bloque de integrantes:

```haml
              - if group.workshop_group_members.any?
                %ul.field-list
                  -# Los ASIENTOS y no `group.members`: `attended` vive en el
                  -# asiento, y `members` es un `has_many through` que devuelve
                  -# los `User`.
                  - group.workshop_group_members.each do |seat|
                    %li.field-list__item
                      %span
                        = seat.user.name
                        - unless seat.attended
                          %span.muted= " · ausente"
                      - if can_edit
                        .assignment-row__actions
                          -# Hermanos del form de convocar y NO adentro: un
                          -# `button_to` es un `<form>`, y uno dentro de otro es
                          -# HTML inválido que el navegador aplana sin dejar
                          -# rastro en el DOM.
                          = button_to seat.attended ? "Marcar ausente" : "Marcar presente",
                                      attendance_workshop_path(workshop), method: :patch,
                                      params: { user_id: seat.user_id, attended: !seat.attended },
                                      class: "btn btn-ghost btn-sm"
                          = button_to "Sacar", dismiss_workshop_path(workshop), method: :delete,
                                      params: { user_id: seat.user_id }, class: "btn btn-ghost btn-sm"
```

Y el contador de la cabecera de la mesa, que hoy dice `group.members.size`, pasa
a `group.workshop_group_members.size`.

En `app/controllers/workshops_controller.rb#show`, el preload:

```ruby
    @groups = @workshop.workshop_groups.includes(workshop_group_members: :user)
```

- [ ] **Step 5: Correr y verificar que pasa**

Run: `make spec-file FILE=spec/requests/workshop_attendances_spec.rb`
Run: `make spec-file FILE=spec/requests/workshop_mesas_spec.rb`
Expected: PASS las dos — la segunda es la que ya cubría el partial y tiene que
seguir en verde después de cambiar la iteración.

- [ ] **Step 6: Probar que los tests pueden fallar**

1. Sacar `return reject_closed if @workshop.closed?`. Tiene que fallar «no toca
   nada con el taller cerrado».
2. Cambiar `:manage_groups?` por `:show?`. Tiene que fallar «no lo puede hacer
   quien participa».
3. Cambiar `find_by!` por `find_by`. Tiene que fallar «da 404 por alguien que no
   está sentado» (con un `NoMethodError` en vez de un 404, que también es rojo:
   arreglarlo volviendo al `find_by!`).

- [ ] **Step 7: Commit**

```bash
git add app/controllers/workshop_attendances_controller.rb app/controllers/workshops_controller.rb app/views/workshops/_groups.html.haml config/routes.rb spec/requests/workshop_attendances_spec.rb
git commit -F - <<'MSG'
La asistencia se marca a mano, y el partial itera los asientos

Es lo que faltaba del punto 1 del handoff: `attended` estaba código-completa y
no había ninguna ruta que la escribiera. Es el único escritor de presencia en un
taller con la asistencia presumida, y el que cubre a quien vino sin teléfono.

El partial iteraba `group.members`, que son User y no traen `attended`: ahora
itera los asientos, y el preload del controller los trae con su user para no
agregar una consulta por integrante.

Los dos botones son hermanos del form de convocar y no van adentro: un
button_to es un form, y uno dentro de otro lo aplana el navegador sin dejar
rastro en el DOM.
MSG
```

---

### Task 8: El seed, el recorrido y la documentación

**Files:**
- Modify: `db/seeds.rb:747-749` (el `destroy_all`) y `:811-855` (los talleres)
- Modify: `script/capture_screens.js`
- Modify: `CLAUDE.md` (la sección `### El taller`)
- Test: `make spec` completa y `make screens`

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: el taller «Taller con check-in» en el seed, y las capturas `29`,
  `30` y `30b`.

- [ ] **Step 1: El cuarto taller en el seed**

En el `destroy_all` por nombre de arriba del bloque del taller, sumar el nombre
nuevo. **Esto es Review Focus 5:** sin esto, la segunda siembra lo duplica y el
recorrido encuentra dos.

```ruby
    Workshop.where(company: demo, name: ["Taller de mejora continua", "Taller de evolución",
                                         "Taller de planificación (borrador)",
                                         "Taller con check-in"]).destroy_all
```

Después del taller de evolución, antes del borrador:

```ruby
    # El CUARTO taller existe SÓLO para las capturas del check-in por link
    # (`29`, `30`, `30b`), como manda CLAUDE.md: un taller compartido con
    # pruebas a mano rompió el recorrido dos veces.
    #
    # Va sobre el desafío de idear —el mismo que el primero, que se puede: el
    # vínculo es único por TALLER, y las mesas son de cada uno— y **sin nadie
    # sentado**, porque la captura tiene que mostrar el estado vacío de la
    # llegada: el que ve quien proyecta el QR antes de que llegue nadie.
    checkin_workshop = Workshop.create!(name: "Taller con check-in", mode: "group",
                                        created_by: workshop_admin,
                                        attendance_mode: "registered",
                                        scheduled_at: Time.zone.now.change(hour: 9, min: 0) + 3.days)
    checkin_workshop.workshop_challenges.create!(challenge: ideation_challenge)
    checking = Flow::Workshops::Open.new(checkin_workshop).call
    raise "El taller de check-in no abrió: #{checking.errors.to_sentence}" unless checking.ok?
```

Y al final del bloque, junto a los otros `puts`:

```ruby
    puts "Taller con check-in: #{checkin_workshop.reload.name} (token #{checkin_workshop.checkin_token})"
```

- [ ] **Step 2: Sembrar dos veces**

Run: `make seed`
Run: `make seed`

Expected: las dos corridas terminan bien, y la segunda **no** deja dos talleres
con el mismo nombre. Verificar:

```bash
docker compose exec app bin/rails runner 'Flow::Tenant.bypass! { puts Workshop.where(name: "Taller con check-in").count }'
```

Expected: `1`.

- [ ] **Step 3: Las capturas**

En `script/capture_screens.js`, en la sección del taller, después de
`28-taller-vinculo-cerrado`, declarar la variable del link **en el scope del
IIFE** (arriba, junto a las otras constantes del recorrido) y llenarla acá:

```js
  // El QR del check-in. El token es aleatorio por siembra, así que el link se
  // LEE de la pantalla —es para eso que el diseño lo pone en texto debajo del
  // código— y se usa más abajo, en la pasada sin sesión.
  {
    await goToWorkshop('Taller con check-in');
    const svg = page.locator('.card:has-text("Check-in por link") svg');
    if (!(await svg.count())) {
      failures++;
      console.error('[CHECKIN] la pantalla del taller no dibuja el QR');
    }
    const hint = page.locator('.card:has-text("Check-in por link") .field-hint');
    checkinUrl = (await hint.first().innerText()).trim();
    if (!/\/checkin\/[A-Za-z0-9]+$/.test(checkinUrl)) {
      failures++;
      console.error(`[CHECKIN] el link del QR no se pudo leer: «${checkinUrl}»`);
    }
    await capturar(page, '29-taller-checkin');
  }
```

Y en el bloque de «las que piden otra sesión», después de `20-not-found`:

```js
  // El check-in sin sesión. `salir()` y NO un `browser.newContext()`: un
  // contexto nuevo trae una `page` nueva SIN los listeners de `pageerror` y de
  // `response`, que se registran una sola vez sobre la del recorrido. La
  // captura quedaría ciega justo a lo que esto existe para cazar, y daría verde.
  //
  // Acá el `goto` es correcto: no hay link que seguir —el QR es una imagen— y
  // la pantalla pública no monta ninguna isla ni carga el bundle de JS, que es
  // lo que la regla de «navegá por link» protege.
  await salir();
  await page.goto(checkinUrl, { waitUntil: 'networkidle' });
  if (!(await page.locator('input[name="email"]').count())) {
    failures++;
    console.error('[CHECKIN] la pantalla pública no ofrece el formulario');
  }
  await capturar(page, '30-checkin-publico');

  // El registro, con un email FIJO: la primera corrida crea la cuenta, las
  // siguientes autentican con la misma clave y el check-in sólo re-marca
  // presente. Es idempotente por el mismo mecanismo que hace que el formulario
  // único no sea un oráculo de cuentas.
  //
  // `.example` y no `.test`: `Flow::Demo` identifica lo sembrado por el sufijo
  // `.test`, así que una cuenta `@demo.test` creada acá aparecería en la lista
  // de la pantalla de login y cambiaría esa captura.
  await page.fill('input[name="email"]', 'llegada@taller.example');
  await page.fill('input[name="name"]', 'Lucía Llegada');
  await page.fill('input[name="password"]', 'Test1234');
  await Promise.all([
    page.waitForURL(/\/workshops\/[^/]+$/, { timeout: 15000 }),
    page.click('input[type="submit"]')
  ]);
  // La sala tiene que decir que la mesa todavía no se armó: es la mesa de
  // llegada, y de ella no se trabaja. Si dijera otra cosa, el borrador que
  // alguien cree ahí nacería con toda la sala como contribuyentes.
  const espera = await page.locator('body').innerText();
  if (!/todavía no se armó/.test(espera)) {
    failures++;
    console.error('[CHECKIN] entró, pero la sala no anuncia la espera de la mesa de llegada');
  }
  await capturar(page, '30b-taller-llegada');
```

El `let checkinUrl = null;` va arriba, con las otras constantes del recorrido.

**Son tres capturas y no las dos que decía el spec**, a propósito: una captura
del formulario sola no prueba que el registro funcione, que es la feature
entera. `30b` es la que lo prueba.

Después de `30b`, el recorrido sigue con «vuelve el admin», que ya existe y hace
`salir()` + `entrar('admin@demo.test')`: no hay que agregar nada ahí.

- [ ] **Step 4: Correr el recorrido**

Run: `make screens`
Expected: 74 capturas, 0 errores. Si `[RELLENO]` o `[RITMO]` reportan haber
medido menos que antes, leer su número: una guarda que mide de menos da verde y
es indistinguible de una que funciona.

- [ ] **Step 5: La documentación**

En `CLAUDE.md`, en la sección `### El taller`, después del párrafo de
`attended`, reemplazar el que dice «**Pero marcar a alguien ausente todavía no
se puede desde la app**» —que dejó de ser cierto— por:

```markdown
**La presencia se escribe de dos formas, y el taller declara cuál vale.**
`workshops.attendance_mode` es `presumed` —lo de siempre: el reparto sienta al
pool completo y marcar ausentes es la excepción— o `registered`, y ahí la
presencia la escribe alguien: el check-in por link (`WorkshopCheckinsController`,
la ÚNICA ruta pública de la app) o el toggle de cada integrante
(`WorkshopAttendancesController`). Con `registered`, convocar a mano deja el
asiento AUSENTE y el pool de idear deja de incluir a los `participant` de la
empresa — sin eso el escaneo es decorativo, porque el pool automático sienta
igual a quien no vino.

**El token y el modo son dos cosas.** `checkin_token` es la credencial y
`attendance_mode` la semántica: si el modo se derivara del token, rotarlo para
revocar un link filtrado devolvería la asistencia a presumida en medio de la
sesión. Rotar revoca; apagar el modo cambia cómo se cuenta.

**La «Mesa de llegada» (`workshop_groups.arrival`, con índice UNIQUE parcial)
es sala de espera, y son CUATRO puertas.** Cada sala tiene lectura y escritura,
y las cuatro preguntan `group.arrival?`. No es prolijidad:
`WorkshopIdeasController` escribe `idea_contributors` para toda la mesa, así que
un borrador creado desde una llegada de treinta personas nace con las treinta
ESCRITAS y repartir no lo deshace. Y `AssignGroups#seat!` la excluye de las
mesas reusables: es la primera creada, así que la habría convertido en «Mesa 1»
con `arrival: true` puesto y su sala habría quedado muda para siempre.
```

- [ ] **Step 6: La suite completa**

Run: `make spec`
Expected: 0 fallas, y más ejemplos que los 1468 de la rama anterior.

- [ ] **Step 7: Commit**

```bash
git add db/seeds.rb script/capture_screens.js CLAUDE.md
git commit -F - <<'MSG'
El seed siembra el taller del check-in, y el recorrido entra sin sesión

Un cuarto taller, sólo para estas capturas y sin nadie sentado: la captura tiene
que mostrar el estado vacío de la llegada, que es el que ve quien proyecta el QR
antes de que llegue nadie. Su nombre entra en el destroy_all de arriba, o la
segunda siembra lo duplica.

La captura pública va con salir() y NO con browser.newContext(): un contexto
nuevo trae una page sin los listeners de pageerror y de response, que se
registran una sola vez, y la captura quedaría ciega justo a lo que make screens
existe para cazar. El link se lee de la pantalla de admin, porque el token es
aleatorio por siembra.

Y son tres capturas y no dos: una del formulario sola no prueba que el registro
funcione. 30b entra de verdad y exige que la sala anuncie la espera.
MSG
```

---

## Cierre de la rama

- [ ] **`make spec` y `make screens` en verde, con los números a la vista.** No
  se afirma nada sin el output.
- [ ] **Revisión de rama entera** con `superpowers:requesting-code-review`.
- [ ] **Merge `--no-ff` con mensaje «Merge: …»**, que es la convención del repo.
- [ ] **Handoff** de cinco secciones, incluidos los intentos fallidos.
