# Asignación de mesas en el taller — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el taller arme sus mesas solo, por cabeza en idear y por trabajo compartido en evolución.

**Architecture:** Un servicio (`Flow::Workshops::AssignGroups`) arma la entrada según la fase y delega el reparto en un colaborador puro (`Flow::Workshops::Seating`) que no toca la base. Idear no es otro algoritmo: es el mismo con grupos de una persona. Una columna nueva (`workshop_group_members.attended`) y un invariante nuevo (un taller es de una sola fase, verificado en `Open`).

**Tech Stack:** Rails 7.1, PostgreSQL 17, RSpec, HAML. Sin JS nuevo.

**Spec:** `docs/superpowers/specs/2026-09-30-asignacion-de-mesas-design.md`

## Global Constraints

- **El código va en inglés; los comentarios y los mensajes de commit, en español.**
- **Toda tabla y toda columna nueva va en inglés**, sin excepción.
- Todo corre en Docker: `make spec`, `make spec-file FILE=…`, `make screens`, `make seed`. **Nunca `bundle exec` en el host.**
- Migraciones: `schema_format = :sql`. Después de migrar, commitear `db/structure.sql`.
- Toda lectura del dominio en un spec va dentro de `as_company(company) { … }`, incluido un `.new`.
- Los mensajes de commit **no** llevan `Co-Authored-By`.
- Una guarda que nadie vio fallar no es una guarda: cada una se rompe a mano y se corre. El backup va con `cp` al scratchpad, **nunca `git checkout <archivo>`**, que en una rama sin commit restaura el arreglo y no la mutación.

## Review Focus

Cinco clases de entrada que el spec implica y que ninguna tarea probaría por su cuenta. Cada una tiene su test asignado a la tarea que es dueña del código.

1. **Un racimo que cruza desafíos.** El pool de evolución sale de los `step_entries` de TODOS los vínculos, así que una persona en dos ideas de dos desafíos encadena los dos. → Task 4.
2. **Alguien sentado que no trabaja en ninguna idea** (en evolución). Por la regla de no evictar, entra como grupo de uno. → Task 4.
3. **`size` inválido o absurdo**: 0, negativo, o mayor que todo el pool. → Task 3.
4. **Una idea cuya gente ya está completa en otra idea** (solape total). Desprenderla no mueve a nadie: la mesa nueva quedaría vacía. → Task 3.
5. **El taller de modo `individual`.** Ahí cada mesa es de una persona por diseño; un reparto con `size > 1` contradiría el modo. → Task 5.

---

### Task 1: La columna `attended`

**Files:**
- Create: `db/migrate/20260930140000_add_attended_to_workshop_group_members.rb`
- Modify: `db/structure.sql` (lo regenera `db:migrate`)
- Modify: `app/models/workshop_group_member.rb`
- Test: `spec/models/workshop_group_member_spec.rb`

**Interfaces:**
- Consumes: nada.
- Produces: `WorkshopGroupMember.presentes` (scope), `workshop_group_members.attended` (boolean, NOT NULL, default true).

- [ ] **Step 1: Escribir el test que falla**

En `spec/models/workshop_group_member_spec.rb`, dentro del `describe` existente (si no existe el archivo, crearlo con el idiom de `spec/models/step_test_spec.rb`: `let(:company)` + `around { |example| as_company(company) { example.run } }`):

```ruby
  # `attended` y NO `present`: una columna `present` genera `present?`, que
  # choca con `Object#present?` de ActiveSupport. El choque no da error —
  # devuelve otra cosa—, que es la peor forma de romperse.
  describe "la asistencia" do
    it "nace presente, sin que nadie lo diga" do
      expect(miembro.attended).to be(true)
    end

    it "y el scope deja sólo a los presentes" do
      ausente = miembro(email: "ausente@test.dev")
      ausente.update!(attended: false)

      expect(WorkshopGroupMember.presentes).to include(miembro)
      expect(WorkshopGroupMember.presentes).not_to include(ausente)
    end
  end
```

- [ ] **Step 2: Correrlo y verlo fallar**

Run: `make spec-file FILE=spec/models/workshop_group_member_spec.rb`
Expected: FAIL con `undefined method 'attended'` (y `undefined method 'presentes'`).

- [ ] **Step 3: La migración**

```ruby
# frozen_string_literal: true

# La asistencia de una persona a su mesa.
#
# `attended` y NO `present`: en Rails una columna `present` genera `present?`,
# que choca con `Object#present?` de ActiveSupport —el choque no da error,
# devuelve otra cosa—.
#
# Default `true` es lo que evita un paso extra: el reparto automático sienta al
# pool completo y marcar ausentes es la excepción, no el trámite. Cuelga de la
# membresía de la mesa y no de un padrón aparte, para no crear la segunda fuente
# de «quién está en este taller» que `Flow::Workshops::Convoke` advierte.
class AddAttendedToWorkshopGroupMembers < ActiveRecord::Migration[7.1]
  def change
    add_column :workshop_group_members, :attended, :boolean, null: false, default: true
  end
end
```

Y en `app/models/workshop_group_member.rb`, junto a las asociaciones:

```ruby
  # Quiénes vinieron. Lo consume el reparto automático
  # (`Flow::Workshops::AssignGroups`): rearmar mueve sólo a los presentes, y un
  # ausente conserva su asiento en vez de desaparecer.
  scope :presentes, -> { where(attended: true) }
```

- [ ] **Step 4: Migrar, correr y verlo pasar**

```bash
docker compose exec -T app bin/rails db:migrate
make spec-file FILE=spec/models/workshop_group_member_spec.rb
```
Expected: PASS. Y `git status` tiene que mostrar `db/structure.sql` modificado.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/20260930140000_add_attended_to_workshop_group_members.rb db/structure.sql \
        app/models/workshop_group_member.rb spec/models/workshop_group_member_spec.rb
git commit -m "La asistencia a una mesa, en una columna

attended y no present: una columna present genera present?, que choca con
Object#present? de ActiveSupport, y el choque no da error sino que devuelve otra
cosa. Default true porque el reparto sienta al pool completo y marcar ausentes es
la excepción. Cuelga de la membresía y no de un padrón aparte, para no crear la
segunda fuente de «quién está en este taller» que Convoke advierte."
```

---

### Task 2: Un taller es de una sola fase, y el seed partido

**Files:**
- Modify: `app/lib/flow/workshops/open.rb`
- Modify: `app/models/workshop.rb`
- Modify: `db/seeds.rb:810-816` (el taller abierto)
- Modify: `script/capture_screens.js` (el recorrido del taller)
- Test: `spec/lib/flow/workshops/open_spec.rb`

**Interfaces:**
- Consumes: nada de Task 1.
- Produces: `Workshop#phase` → `"ideation"` | `"evolution"` | `nil`.

- [ ] **Step 1: Escribir el test que falla**

En `spec/lib/flow/workshops/open_spec.rb` (existe; si no, copiar el setup de `spec/requests/workshops_spec.rb`):

```ruby
  # Un taller es de UNA fase. Se verifica acá y no en `WorkshopChallenge`
  # porque en borrador `challenge_step` es nil: la fase todavía no existe.
  describe "fase mixta" do
    it "no abre, y nada cambia" do
      mixto = as_company(company) do
        w = Workshop.create!(name: "Mixto", mode: "group", created_by: admin)
        w.workshop_challenges.create!(challenge: en_idear)
        w.workshop_challenges.create!(challenge: en_evolucion)
        w
      end

      result = as_company(company) { described_class.new(mixto).call }

      expect(result).not_to be_ok
      as_company(company) do
        expect(mixto.reload).to be_draft
        expect(mixto.workshop_challenges.reload.map(&:status).uniq).to eq(["open"])
        expect(mixto.workshop_challenges.map(&:challenge_step_id).compact).to be_empty
      end
    end

    it "y el error nombra qué desafío está en cuál fase" do
      # …mismo armado…
      expect(result.errors.join).to include(en_idear.name, en_evolucion.name, "Idear", "Evolución")
    end
  end
```

- [ ] **Step 2: Correrlo y verlo fallar**

Run: `make spec-file FILE=spec/lib/flow/workshops/open_spec.rb`
Expected: FAIL — hoy abre igual, así que `result` es `ok?` y el taller queda `open`.

- [ ] **Step 3: La regla en `Open`**

Reemplazar el cuerpo del `with_lock` de `Flow::Workshops::Open#call`. Primero se resuelve todo, después se decide:

```ruby
        @workshop.with_lock do
          resueltos = @workshop.workshop_challenges.includes(:challenge).map do |link|
            [link, link.challenge.pipeline.active_step]
          end

          # La fase se verifica ACÁ y sobre TODO junto, que es lo que ningún
          # otro lugar puede hacer: en borrador `challenge_step` es nil, así que
          # una validación de modelo no tiene fase con la que comparar.
          #
          # Va antes de escribir nada: rechazar después de cerrar vínculos
          # dejaría el taller a medio abrir hasta que el rollback lo deshaga, y
          # el motivo del rechazo se leería sobre un estado que ya no existe.
          trabajables = resueltos.select { |_, step| step && WorkshopChallenge::WORKABLE_KINDS.include?(step.kind) }
          if trabajables.map { |_, step| step.kind }.uniq.size > 1
            @error = mixed_phases(trabajables)
            raise ActiveRecord::Rollback
          end

          resueltos.each do |link, step|
            if trabajables.any? { |l, _| l.id == link.id }
              link.update!(challenge_step: step, status: "open")
            else
              link.update!(status: "closed", closed_at: Time.current, closed_reason: self.class.reason_for(step))
              rejected << link
            end
          end

          raise ActiveRecord::Rollback if @workshop.workshop_challenges.reload.none?(&:open?)

          @workshop.update!(status: "open")
        end

        return Result.new(ok: false, rejected: [], errors: [@error || no_workable_challenges]) unless @workshop.reload.open?
```

Y el mensaje, privado:

```ruby
      # Nombra qué desafío está en cuál fase: «el taller mezcla fases» sin los
      # nombres deja a quien lo lee abriendo los desafíos de a uno.
      def mixed_phases(trabajables)
        por_fase = trabajables.group_by { |_, step| step.kind }
        detalle = por_fase.map do |kind, pares|
          "#{I18n.t("flow.kinds.#{kind}")}: #{pares.map { |link, _| "«#{link.challenge.name}»" }.to_sentence}"
        end
        "Un taller trabaja sobre una sola fase, y este mezcla dos. #{detalle.join(' · ')}."
      end
```

En `app/models/workshop.rb`:

```ruby
  # La fase del taller: el `kind` de sus vínculos abiertos, homogéneo por la
  # regla de `Flow::Workshops::Open`. Se DERIVA y no se guarda: una columna
  # sería la segunda fuente que el día que difiera de los vínculos miente.
  def phase = workshop_challenges.select(&:open?).map(&:kind).compact.uniq.first
```

- [ ] **Step 4: Correr y verlo pasar**

Run: `make spec-file FILE=spec/lib/flow/workshops/open_spec.rb`
Expected: PASS, y el resto del archivo sigue verde (los vínculos rechazados por fase no trabajable no cambiaron de comportamiento).

- [ ] **Step 5: Partir los dos talleres sembrados**

El seed **ya revienta solo** con la regla nueva: `db/seeds.rb:820` hace
`raise "El taller no abrió: …" unless opening.ok?`. Hay que partir el abierto Y
el borrador, y **mover la mesa que tiene la propuesta**, porque su
`challenge_step` es la ronda de evolución y su mesa tiene que estar en el taller
que se queda con ese desafío.

El reparto: `open_workshop` se queda con **idear** y con el avanzado —que se
rechaza al abrir y es lo que le da a `28-taller-vinculo-cerrado` su vínculo
cerrado con motivo—; el taller nuevo se queda con **evolución**, con
`bodega_group` y con la propuesta.

En `db/seeds.rb:747`, el `destroy_all` (si no, el seed deja de ser idempotente):

```ruby
    Workshop.where(company: demo, name: ["Taller de mejora continua", "Taller de evolución",
                                         "Taller de planificación (borrador)"]).destroy_all
```

Reemplazar de `db/seeds.rb:813` a la creación de la propuesta por:

```ruby
    # DOS talleres abiertos y no uno: un taller trabaja sobre una sola fase
    # (`Flow::Workshops::Open`), así que idear y evolución no conviven.
    #
    # El del manual va con el de IDEAR porque se rechaza al abrir —no está en
    # ninguna de las dos fases— y es lo que le da a la pantalla un vínculo
    # cerrado con su motivo. La mesa con la propuesta va con el de EVOLUCIÓN:
    # su `challenge_step` es la ronda, y una propuesta cuya mesa vive en otro
    # taller no tendría sala donde mostrarse.
    open_workshop = Workshop.create!(name: "Taller de mejora continua", mode: "group", created_by: workshop_admin,
                                     scheduled_at: Time.zone.now.change(hour: 15, min: 0) + 2.days)
    [ideation_challenge, advanced_challenge].each { |c| open_workshop.workshop_challenges.create!(challenge: c) }
    despacho_group = open_workshop.workshop_groups.create!(name: "Mesa Despacho")
    WorkshopGroupMember.create!(workshop_group: despacho_group, user: workshop_part2)
    opening = Flow::Workshops::Open.new(open_workshop).call
    raise "El taller de idear no abrió: #{opening.errors.to_sentence}" unless opening.ok?

    evolution_workshop = Workshop.create!(name: "Taller de evolución", mode: "group", created_by: workshop_admin,
                                          scheduled_at: Time.zone.now.change(hour: 17, min: 0) + 2.days)
    evolution_workshop.workshop_challenges.create!(challenge: evolution_challenge)
    bodega_group = evolution_workshop.workshop_groups.create!(name: "Mesa Bodega")
    [workshop_admin, workshop_part1].each { |u| WorkshopGroupMember.create!(workshop_group: bodega_group, user: u) }
    evolving = Flow::Workshops::Open.new(evolution_workshop).call
    raise "El taller de evolución no abrió: #{evolving.errors.to_sentence}" unless evolving.ok?

    # La propuesta pendiente de la mesa sobre la idea de Paula: es lo que
    # fotografía `27-taller-propuesta-en-la-idea`.
    WorkshopProposal.create!(
      workshop_group: bodega_group, idea: workshop_ideas[0], challenge_step: workshop_round,
      status: "pending",
      payload: { "titulo" => "Un buddy para la primera semana",
                 "descripcion" => "Cada persona nueva tiene un compañero asignado, con dos horas por semana " \
                                  "reservadas para sus dudas." }
    )
```

Y el **borrador** también se parte. Hoy linkea los dos desafíos, y dejarlo mixto
sería ofrecer un «Abrir taller» que siempre falla — el control fantasma que este
repo persigue. `db/seeds.rb:836`:

```ruby
    [ideation_challenge].each { |c| draft_workshop.workshop_challenges.create!(challenge: c) }
```

**Verificar que la sala de evolución siga ofreciendo DOS propuestas**: la guarda
`[TALLER]` de `26-taller-sala-evolucion` lo exige, y salen de
`workable_ideas` sobre los integrantes de `bodega_group` (admin y part1).

- [ ] **Step 6: Correr el seed y ver que abre**

```bash
make seed
```
Expected: sin excepciones, y la salida nombra los dos talleres. Si `Open` rechaza alguno, `move!` no interviene acá —el seed abre el taller con `Flow::Workshops::Open`— así que revisar a mano que los dos queden `open`.

- [ ] **Step 7: Arreglar el recorrido del taller**

`script/capture_screens.js:2727-2765` camina UN taller y saca de él `24-taller-armado`, `25-taller-sala-idear`, `26-taller-sala-evolucion` y `28-taller-vinculo-cerrado`. Ahora `26` sale de otro taller.

Navegar **por link** desde el índice de talleres al segundo taller (Turbo no dispara `DOMContentLoaded` con `goto`), y esperar `waitForURL` o un selector después del clic. **No apuntar a un taller que también se use a mano.**

- [ ] **Step 8: Correr el recorrido**

```bash
make screens > /tmp/screens.log 2>&1; echo "exit=$?"; grep -E "^\[|capturas|Sin errores" /tmp/screens.log
```
Expected: 71 capturas, 0 errores. **Guardar la salida a archivo y filtrar después**: filtrar con `| tail` ya tapó un error una vez.

- [ ] **Step 9: Ver fallar la regla**

Con `cp` al scratchpad, sacar el `if trabajables.…uniq.size > 1` de `Open` y correr `make spec-file FILE=spec/lib/flow/workshops/open_spec.rb`. Tiene que fallar nombrando los dos ejemplos nuevos. Restaurar con `cp`.

- [ ] **Step 10: Commit**

```bash
git add app/lib/flow/workshops/open.rb app/models/workshop.rb db/seeds.rb \
        script/capture_screens.js spec/lib/flow/workshops/open_spec.rb
git commit -m "Un taller trabaja sobre una sola fase

Idear y evolución no conviven en un taller: el reparto de mesas usa un criterio
distinto para cada una, y un taller mixto no tendría cuál elegir. Se verifica en
Open, que es el único lugar que conoce todas las fases a la vez —en borrador
challenge_step es nil, así que una validación de modelo no tiene con qué
comparar— y antes de escribir nada, para no dejar el taller a medio abrir.

El error nombra qué desafío está en cuál fase: sin los nombres hay que abrirlos
de a uno.

El taller sembrado tenía ideation y evolution abiertos, así que dejaba de poder
abrirse: se partió en dos, y el recorrido de capturas ahora visita los dos."
```

---

### Task 3: `Seating`, el reparto puro

**Files:**
- Create: `app/lib/flow/workshops/seating.rb`
- Test: `spec/lib/flow/workshops/seating_spec.rb`

**Interfaces:**
- Consumes: nada. No toca la base.
- Produces:
  - `Flow::Workshops::Seating.new(groups:, size:).call` → `Result`
  - `groups`: `Hash` de `clave => Array<user_id>`. La clave es el id de la idea (evolución) o el del usuario (idear).
  - `Result = Data.define(:tables, :splits)`; `tables` es `Array<Array<user_id>>`; `splits` es `Array<Split>`.
  - `Split = Data.define(:group_key, :shared_user_ids, :inside)`. `inside: true` es el caso extremo (se partió gente de UNA idea).

- [ ] **Step 1: Escribir los tests que fallan**

```ruby
# frozen_string_literal: true

require "rails_helper"

# El reparto, sin base de datos: grupos indivisibles y un tamaño.
#
# Idear no es otro algoritmo: es este con grupos de una persona.
RSpec.describe Flow::Workshops::Seating do
  def repartir(groups, size) = described_class.new(groups: groups, size: size).call

  describe "sin nada compartido (el caso de idear)" do
    it "reparte por cabeza hasta el tamaño" do
      grupos = (1..5).to_h { |i| ["g#{i}", ["u#{i}"]] }

      result = repartir(grupos, 2)

      expect(result.tables.map(&:size)).to eq([2, 2, 1])
      expect(result.tables.flatten.sort).to eq(%w[u1 u2 u3 u4 u5])
      expect(result.splits).to be_empty
    end
  end

  describe "con gente compartida" do
    it "deja el racimo junto si entra" do
      # i1 y i2 comparten a b: un solo racimo de tres personas.
      result = repartir({ "i1" => %w[a b], "i2" => %w[b c] }, 4)

      expect(result.tables).to eq([%w[a b c]])
      expect(result.splits).to be_empty
    end

    it "desprende la idea de menor solape, y la compartida se queda" do
      # i1 y i2 comparten a y b; i3 comparte sólo a c. Con tamaño 3, i3 se va.
      result = repartir({ "i1" => %w[a b c], "i2" => %w[a b d], "i3" => %w[c e] }, 3)

      expect(result.tables).to include(%w[e])
      expect(result.tables.find { |t| t.include?("c") }).to include("a", "b")
      expect(result.splits.map(&:group_key)).to eq(["i3"])
      expect(result.splits.first.shared_user_ids).to eq(["c"])
      expect(result.splits.first.inside).to be(false)
    end

    it "no arma una mesa vacía cuando la idea desprendida no tiene gente propia" do
      # Review Focus 4: la gente de i2 está toda en i1.
      result = repartir({ "i1" => %w[a b c], "i2" => %w[a b] }, 2)

      expect(result.tables).to all(be_present)
    end
  end

  describe "el caso extremo: una sola idea más grande que el tamaño" do
    it "la parte, y lo dice con su propio aviso" do
      result = repartir({ "i1" => %w[a b c d e] }, 2)

      expect(result.tables.map(&:size)).to eq([2, 2, 1])
      expect(result.splits.map(&:inside)).to eq([true])
      expect(result.splits.first.group_key).to eq("i1")
    end
  end

  describe "el tamaño" do
    # Review Focus 3.
    it "menor que 1 se trata como 1" do
      expect(repartir({ "i1" => %w[a b] }, 0).tables).to eq([%w[a], %w[b]])
    end

    it "mayor que todo el pool da una sola mesa" do
      expect(repartir({ "i1" => %w[a], "i2" => %w[b] }, 99).tables).to eq([%w[a b]])
    end
  end

  # Los desempates existen para esto. Sin medirlo se pueden romper sin que nada
  # se queje, y dos corridas del mismo taller darían mesas distintas.
  it "es determinista" do
    grupos = { "i3" => %w[c e], "i1" => %w[a b c], "i2" => %w[a b d] }

    expect(repartir(grupos, 3).tables).to eq(repartir(grupos, 3).tables)
    expect(repartir(grupos.to_a.reverse.to_h, 3).tables).to eq(repartir(grupos, 3).tables)
  end
end
```

- [ ] **Step 2: Correrlos y verlos fallar**

Run: `make spec-file FILE=spec/lib/flow/workshops/seating_spec.rb`
Expected: FAIL con `uninitialized constant Flow::Workshops::Seating`.

- [ ] **Step 3: Implementar**

```ruby
# frozen_string_literal: true

module Flow
  module Workshops
    # Reparte grupos INDIVISIBLES de personas en mesas de a lo sumo `size`.
    #
    # No toca la base a propósito: recibe un hash y devuelve arreglos, así que
    # se prueba con datos pelados y el servicio que lo usa
    # (`Flow::Workshops::AssignGroups`) se queda con los guardas y la
    # persistencia.
    #
    # Idear no es otro algoritmo: es éste con un grupo por persona. Un
    # mecanismo y un gancho, igual que la mesa de una sola persona del modo
    # individual.
    class Seating
      Split = Data.define(:group_key, :shared_user_ids, :inside)
      Result = Data.define(:tables, :splits)

      def initialize(groups:, size:)
        @groups = groups.transform_values { |ids| ids.uniq }
        # Un tamaño menor que 1 no puede sentar a nadie: una mesa por persona
        # es lo más cerca que se puede estar de lo que se pidió.
        @size = [size.to_i, 1].max
      end

      def call
        splits = []
        bloques = clusters.flat_map { |keys| fit(keys, splits) }
        Result.new(tables: pack(bloques), splits: splits)
      end

      private

      # Componentes conexos sobre «comparten una persona». En idear no hay
      # ninguno: cada grupo es una persona distinta.
      def clusters
        restantes = @groups.keys.sort_by(&:to_s)
        out = []

        until restantes.empty?
          cola = [restantes.shift]
          racimo = []

          until cola.empty?
            key = cola.shift
            next if racimo.include?(key)

            racimo << key
            vecinos = restantes.select { |otra| (@groups[key] & @groups[otra]).any? }
            restantes -= vecinos
            cola.concat(vecinos)
          end

          out << racimo.sort_by(&:to_s)
        end

        out
      end

      # Un racimo, en bloques que entren. Recursivo porque lo que se desprende
      # puede no entrar tampoco.
      def fit(keys, splits)
        return [] if keys.empty?

        gente = personas(keys)
        return [gente] if gente.size <= @size

        # Una sola idea más grande que el tamaño: no hay frontera por donde
        # cortar, así que se parte su gente. Es el único caso en que el
        # resultado no respeta «no partir grupos», y por eso tiene su propio
        # aviso.
        if keys.size == 1
          splits << Split.new(group_key: keys.first, shared_user_ids: [], inside: true)
          return gente.each_slice(@size).to_a
        end

        # Se desprende la de MENOR solape con el resto; empate por menos gente,
        # después por clave, para que dos corridas den lo mismo.
        suelta = keys.min_by { |k| [solape(k, keys - [k]), @groups[k].size, k.to_s] }
        resto = keys - [suelta]
        compartida = @groups[suelta] & personas(resto)
        exclusiva = @groups[suelta] - compartida

        splits << Split.new(group_key: suelta, shared_user_ids: compartida, inside: false)

        # `exclusiva` vacía no arma mesa: la idea desprendida no tenía gente
        # propia. El aviso igual sale, porque la idea SÍ se quedó sin mesa
        # aparte y quien mire tiene que poder entenderlo.
        fit(resto, splits) + fit_exclusiva(suelta, exclusiva, splits)
      end

      def fit_exclusiva(key, gente, splits)
        return [] if gente.empty?
        return [gente] if gente.size <= @size

        splits << Split.new(group_key: key, shared_user_ids: [], inside: true)
        gente.each_slice(@size).to_a
      end

      def personas(keys) = keys.flat_map { |k| @groups[k] }.uniq

      def solape(key, otras) = (@groups[key] & personas(otras)).size

      # Los bloques chicos comparten mesa: juntar gente que no trabaja junta no
      # parte ningún grupo, y es lo que respeta el tamaño pedido. Primero los
      # grandes (first-fit decreciente), que es lo que deja menos mesas.
      def pack(bloques)
        mesas = []

        bloques.sort_by { |b| [-b.size, b.first.to_s] }.each do |bloque|
          mesa = mesas.find { |m| m.size + bloque.size <= @size }
          mesa ? mesa.concat(bloque) : mesas << bloque.dup
        end

        mesas
      end
    end
  end
end
```

- [ ] **Step 4: Correr y verlos pasar**

Run: `make spec-file FILE=spec/lib/flow/workshops/seating_spec.rb`
Expected: PASS, los 9 ejemplos.

- [ ] **Step 5: Ver fallar el determinismo**

Con `cp` al scratchpad, cambiar `min_by { |k| [solape(k, keys - [k]), @groups[k].size, k.to_s] }` por `min_by { |k| solape(k, keys - [k]) }` —sacándole los desempates— y correr. El ejemplo de determinismo tiene que fallar con el orden invertido. Restaurar con `cp`.

- [ ] **Step 6: Commit**

```bash
git add app/lib/flow/workshops/seating.rb spec/lib/flow/workshops/seating_spec.rb
git commit -m "El reparto de mesas, sin base de datos

Grupos indivisibles y un tamaño; devuelve mesas y qué partió. Idear no es otro
algoritmo: es éste con un grupo por persona.

Cuando un racimo no entra se desprende la idea de MENOR solape, y la gente
compartida se queda: una persona se sienta en una mesa sola, así que desprender
su idea no puede llevársela. De ahí sale el aviso legible.

El caso extremo —una sola idea más grande que el tamaño— parte gente de una
misma idea, que es lo único que no respeta la regla, y por eso tiene su propio
aviso.

Los desempates existen para que dos corridas del mismo taller den las mismas
mesas, y hay un ejemplo que lo mide: sin él se rompen sin que nada se queje."
```

---

### Task 4: `AssignGroups`, los guardas y el pool

**Files:**
- Create: `app/lib/flow/workshops/assign_groups.rb`
- Test: `spec/lib/flow/workshops/assign_groups_spec.rb`

**Interfaces:**
- Consumes: `WorkshopGroupMember.presentes` (Task 1), `Workshop#phase` (Task 2), `Flow::Workshops::Seating` (Task 3).
- Produces: `Flow::Workshops::AssignGroups.new(workshop, size:).call` → `Result = Data.define(:ok, :tables, :splits, :errors)` con `ok?`.

- [ ] **Step 1: Escribir los tests que fallan**

```ruby
  describe "los guardas" do
    it "no reparte un taller en borrador: sin fase no hay criterio" do
      result = as_company(company) { described_class.new(borrador, size: 3).call }

      expect(result).not_to be_ok
      expect(result.errors.join).to include("abierto")
    end

    it "no reparte si alguna mesa ya propuso algo" do
      as_company(company) do
        WorkshopProposal.create!(workshop_group: mesa, idea: idea_de_paula,
                                 challenge_step: paso_de_evolucion, status: "pending",
                                 payload: { "titulo" => "x" })
      end

      result = as_company(company) { described_class.new(taller, size: 3).call }

      expect(result).not_to be_ok
      expect(result.errors.join).to include("propuesta")
    end
  end

  describe "en evolución" do
    it "el pool sale de quien trabaja en las ideas del módulo" do
      result = as_company(company) { described_class.new(taller_evolucion, size: 4).call }

      expect(result).to be_ok
      expect(result.tables.flatten).to contain_exactly(paula.id, pedro.id)
    end

    # Review Focus 1.
    it "encadena dos ideas de desafíos DISTINTOS cuando comparten gente" do
      result = as_company(company) { described_class.new(taller_dos_desafios, size: 9).call }

      expect(result.tables.size).to eq(1)
    end

    # Review Focus 2: por la regla de no evictar.
    it "no saca a quien ya está sentado y no trabaja en ninguna idea" do
      as_company(company) { Flow::Workshops::Convoke.new(taller_evolucion, ana, group: mesa).call }

      result = as_company(company) { described_class.new(taller_evolucion, size: 4).call }

      expect(result.tables.flatten).to include(ana.id)
    end
  end

  describe "en idear" do
    it "reparte a los participantes presentes y no a los ausentes" do
      as_company(company) do
        WorkshopGroupMember.find_by!(user_id: pedro.id).update!(attended: false)
      end

      result = as_company(company) { described_class.new(taller_idear, size: 2).call }

      expect(result.tables.flatten).to include(paula.id)
      expect(result.tables.flatten).not_to include(pedro.id)
    end

    it "deja al ausente en su mesa en vez de sacarlo" do
      # …
      expect(as_company(company) { WorkshopGroupMember.find_by!(user_id: pedro.id) }).to be_present
    end
  end
```

- [ ] **Step 2: Correrlos y verlos fallar**

Run: `make spec-file FILE=spec/lib/flow/workshops/assign_groups_spec.rb`
Expected: FAIL con `uninitialized constant Flow::Workshops::AssignGroups`.

- [ ] **Step 3: Implementar**

```ruby
# frozen_string_literal: true

module Flow
  module Workshops
    # Arma las mesas del taller: elige la ENTRADA según la fase y delega el
    # reparto en `Seating`, que no toca la base.
    class AssignGroups
      Result = Data.define(:ok, :tables, :splits, :errors) do
        def ok? = ok
      end

      def initialize(workshop, size:)
        @workshop = workshop
        @size = size
      end

      def call
        # En borrador los vínculos no tienen módulo, así que no hay fase con la
        # que elegir el criterio.
        return failure("El taller tiene que estar abierto para armar las mesas.") unless @workshop.open?
        # Rearmar mueve gente entre mesas y borra las que queden vacías, y
        # `workshop_proposals.workshop_group_id` es ON DELETE CASCADE: una mesa
        # con propuestas se llevaría las aceptadas, que son la procedencia de
        # versiones ya publicadas. Con trabajo hecho, se mueve a mano.
        return failure("Ya hay propuestas en este taller: las mesas se mueven a mano.") if proposals?

        grupos = @workshop.phase == "evolution" ? groups_by_idea : groups_by_person
        return failure("No hay a quién sentar.") if grupos.empty?

        seating = Seating.new(groups: grupos, size: @size).call
        @workshop.transaction { seat!(seating.tables) }

        Result.new(ok: true, tables: seating.tables, splits: seating.splits, errors: [])
      end

      private

      def proposals?
        WorkshopProposal.joins(:workshop_group)
                        .where(workshop_groups: { workshop_id: @workshop.id })
                        .exists?
      end

      # Evolución: un grupo por idea del módulo, con su gente. Los `step_entries`
      # y no `challenge.ideas`, porque el módulo trabaja lo que entró en él.
      def groups_by_idea
        ideas = Idea.where(id: StepEntry.where(challenge_step_id: open_step_ids).select(:idea_id)).alive
        por_idea = ideas.to_h { |idea| [idea.id, people_of(idea)] }
        # La regla de no evictar: quien ya está sentado y presente entra, aunque
        # no trabaje en ninguna idea. Sacarlo sería deshacer una convocatoria
        # que alguien hizo a propósito.
        por_idea.merge(groups_by_person(seated_only: true))
      end

      # Idear: un grupo por persona. No hay ideas de las que deducir nada.
      def groups_by_person(seated_only: false)
        # `- absent_ids` también sobre `participant_ids`: ése no está filtrado por
        # asistencia, así que sin esto un participante marcado ausente volvía a
        # entrar por el pool automático.
        ids = seated_only ? seated_present_ids : ((participant_ids | seated_present_ids) - absent_ids)
        ids.to_h { |id| [id, [id]] }
      end

      # Los ausentes salen del pool en las DOS fases. En evolución no es un
      # extra: si alguien no vino, su idea pierde a esa persona y eso CAMBIA los
      # racimos. Ignorarlo dejaría mesas armadas alrededor de gente que no está.
      #
      # Sólo se descuenta a quien está marcado ausente: la asistencia existe
      # para quien está sentado, y a quien nunca se convocó se lo presume
      # presente.
      def people_of(idea)
        ([idea.author_id] + IdeaContributor.where(idea_id: idea.id).pluck(:user_id)) - absent_ids
      end

      def absent_ids
        @absent_ids ||= WorkshopGroupMember.where(attended: false).joins(:workshop_group)
                                           .where(workshop_groups: { workshop_id: @workshop.id })
                                           .pluck(:user_id)
      end

      def open_step_ids = @workshop.workshop_challenges.select(&:open?).map(&:challenge_step_id).compact

      def participant_ids
        Membership.where(company_id: @workshop.company_id, role: "participant").pluck(:user_id)
      end

      def seated_present_ids
        WorkshopGroupMember.presentes.joins(:workshop_group)
                            .where(workshop_groups: { workshop_id: @workshop.id })
                            .pluck(:user_id)
      end

      # Sienta a cada mesa. Mueve a los presentes, crea las mesas que falten y
      # borra SÓLO las que quedan vacías —seguro porque el guarda de propuestas
      # ya corrió—. Un ausente conserva su asiento, así que su mesa no queda
      # vacía y no se borra.
      def seat!(tables)
        existentes = @workshop.workshop_groups.order(:created_at).to_a

        tables.each_with_index do |user_ids, i|
          mesa = existentes[i] || @workshop.workshop_groups.create!(name: "Mesa #{i + 1}")
          WorkshopGroupMember.presentes.joins(:workshop_group)
                              .where(workshop_groups: { workshop_id: @workshop.id }, user_id: user_ids)
                              .destroy_all
          user_ids.each { |id| WorkshopGroupMember.create!(workshop_group: mesa, user_id: id) }
        end

        @workshop.workshop_groups.reload.each { |mesa| mesa.destroy! if mesa.workshop_group_members.empty? }
      end

      def failure(message) = Result.new(ok: false, tables: [], splits: [], errors: [message])
    end
  end
end
```

- [ ] **Step 4: Correr y verlos pasar**

Run: `make spec-file FILE=spec/lib/flow/workshops/assign_groups_spec.rb`
Expected: PASS. Después `make spec` completo: `seat!` toca `workshop_group_members`, que tiene `UNIQUE (workshop_id, user_id)`, así que un reparto que deje a alguien dos veces revienta y lo dirían los specs del taller.

- [ ] **Step 5: Ver fallar los dos guardas**

Con `cp` al scratchpad, sacar la línea de `proposals?` y correr: el ejemplo de propuestas tiene que fallar. Restaurar. Repetir con la de `open?`.

- [ ] **Step 6: Commit**

```bash
git add app/lib/flow/workshops/assign_groups.rb spec/lib/flow/workshops/assign_groups_spec.rb
git commit -m "Armar las mesas del taller

Elige la entrada según la fase y delega el reparto en Seating. En evolución los
grupos son las ideas del módulo con su gente; en idear, una persona por grupo.

Tres guardas: taller abierto —en borrador no hay fase con la que elegir—, ninguna
mesa con propuestas —workshop_group_id es ON DELETE CASCADE y se llevaría las
aceptadas, que son la procedencia de versiones publicadas— y pool no vacío.

No evicta a nadie: quien ya está sentado y presente entra al reparto aunque su
rol no esté en el pool automático. Sacarlo sería deshacer una convocatoria que
alguien hizo a propósito. Y borra sólo las mesas que quedan vacías."
```

---

### Task 5: El control en la sala

**Files:**
- Modify: `config/routes.rb:97` (el bloque de `workshop_groups`)
- Modify: `app/controllers/workshop_groups_controller.rb`
- Modify: `app/views/workshops/_groups.html.haml`
- Test: `spec/requests/workshop_mesas_spec.rb`

**Interfaces:**
- Consumes: `Flow::Workshops::AssignGroups` (Task 4), `Workshop#phase` (Task 2).
- Produces: `POST /workshops/:workshop_id/mesas/assign` → `workshop_groups#assign`.

- [ ] **Step 1: Escribir los tests que fallan**

```ruby
  describe "el control de armar mesas" do
    it "lo ve quien administra, con el taller abierto y sin propuestas" do
      sign_in(admin, company: company)
      get workshop_path(taller)

      expect(response.body).to include(assign_workshop_workshop_groups_path(taller))
    end

    # La lección de la tanda D: un control sin su ejemplo negativo deja sacarle
    # la guarda sin que nada se ponga rojo.
    it "no lo ve quien no administra" do
      sign_in(paula, company: company)
      get workshop_path(taller)

      expect(response.body).not_to include(assign_workshop_workshop_groups_path(taller))
    end

    it "no se ofrece en borrador: el servicio lo rechazaría" do
      sign_in(admin, company: company)
      get workshop_path(borrador)

      expect(response.body).not_to include(assign_workshop_workshop_groups_path(borrador))
    end

    it "no se ofrece si ya hay propuestas" do
      # …crear una propuesta…
      expect(response.body).not_to include(assign_workshop_workshop_groups_path(taller))
    end

    # Review Focus 5.
    it "no se ofrece en modo individual: ahí una mesa es una persona" do
      sign_in(admin, company: company)
      get workshop_path(taller_individual)

      expect(response.body).not_to include(assign_workshop_workshop_groups_path(taller_individual))
    end

    it "arma las mesas y cuenta qué hizo" do
      sign_in(admin, company: company)
      post assign_workshop_workshop_groups_path(taller), params: { size: 2 }

      expect(response).to redirect_to(workshop_path(taller))
      expect(flash[:notice]).to include("mesa")
    end
  end
```

- [ ] **Step 2: Correrlos y verlos fallar**

Run: `make spec-file FILE=spec/requests/workshop_mesas_spec.rb`
Expected: FAIL con `undefined method 'assign_workshop_workshop_groups_path'`.

- [ ] **Step 3: La ruta, el controller y el helper**

`config/routes.rb`, en el bloque de `workshop_groups`:

```ruby
    resources :workshop_groups, only: %i[create destroy], path: "mesas" do
      post :assign, on: :collection
    end
```

En `app/controllers/workshop_groups_controller.rb`:

```ruby
  def assign
    authorize @workshop, :manage_groups?
    result = Flow::Workshops::AssignGroups.new(@workshop, size: params[:size]).call

    if result.ok?
      redirect_to workshop_path(@workshop), notice: assigned_notice(result)
    else
      redirect_to workshop_path(@workshop), alert: result.errors.to_sentence
    end
  end
```

y, privado:

```ruby
  # Qué hizo, y qué partió. Los cortes se cuentan aparte de las mesas: son la
  # única parte del resultado que no respeta «no partir grupos», así que
  # esconderlos en el mismo número sería no decirlo.
  def assigned_notice(result)
    base = "#{Flow::Texto.contar(result.tables.size, 'mesa')} con " \
           "#{Flow::Texto.contar(result.tables.flatten.size, 'persona')}."
    return base if result.splits.empty?

    "#{base} #{Flow::Texto.contar(result.splits.size, 'grupo')} " \
      "#{Flow::Texto.agree(result.splits.size, 'quedó', 'quedaron')} partido por el tamaño de mesa."
  end
```

En `app/views/workshops/_groups.html.haml`, dentro del `.card-body` y **antes** de la lista de mesas. La variable se calcula UNA vez y el controller pregunta lo mismo:

```haml
    -# Más angosto que el `can_edit` de alrededor a propósito: ese vive con el
    -# taller en borrador, y el reparto necesita la fase (que en borrador no
    -# existe) y ninguna propuesta hecha. Ofrecerlo con la condición ancha
    -# sería un control que rebota.
    -# En modo individual no va: ahí una mesa es una persona por diseño.
    - puede_repartir = can_edit && workshop.open? && !workshop.individual? && groups.none? { |g| g.workshop_proposals.exists? }
    - if puede_repartir
      = form_with url: assign_workshop_workshop_groups_path(workshop), method: :post, class: "assignment-add" do |f|
        %div
          = f.label :size, "Personas por mesa", class: "inline-label"
          = f.number_field :size, value: 4, min: 1, max: 20
          = f.submit "Armar mesas", class: "btn btn-primary btn-sm"
```

**Ojo:** `.inline-label` **se borró** en el plan 2c (era CSS muerto). Usar la clase que la hoja tenga viva para una etiqueta en línea, o ninguna — y si hace falta una nueva, agregarla a la hoja, porque `spec/lint/reglas_sin_elemento_spec.rb` falla con una regla sin uso y `[CLASES]` falla con un elemento sin regla.

- [ ] **Step 4: Correr y verlos pasar**

Run: `make spec-file FILE=spec/requests/workshop_mesas_spec.rb`
Expected: PASS.

- [ ] **Step 5: Ver fallar la guarda de la vista**

Con `cp`, sacar `&& workshop.open?` de `puede_repartir` y correr: el ejemplo del borrador tiene que fallar. Restaurar. Repetir sacando `!workshop.individual?`.

- [ ] **Step 6: Correr todo**

```bash
make spec > /tmp/spec.log 2>&1; echo "exit=$?"; tail -3 /tmp/spec.log
make screens > /tmp/screens.log 2>&1; echo "exit=$?"; grep -E "^\[|capturas|Sin errores" /tmp/screens.log
```
Expected: suite verde y 71 capturas / 0 errores. Si `[CLASES]` se queja, es la clase del formulario.

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/workshop_groups_controller.rb \
        app/views/workshops/_groups.html.haml spec/requests/workshop_mesas_spec.rb
git commit -m "El control para armar las mesas

Va detrás del can_assemble que ya existe, pero con su propia variable de estado,
más angosta que la de alrededor: ese bloque vive con el taller en borrador y el
reparto necesita la fase, que en borrador no existe, más ninguna propuesta hecha.
En modo individual no se ofrece: ahí una mesa es una persona por diseño.

El aviso cuenta los cortes aparte de las mesas: son la única parte del resultado
que no respeta «no partir grupos», y meterlos en el mismo número sería no
decirlo.

Con las dos polaridades probadas, que es lo que deja ver si a la guarda le sacan
una condición."
```

---

### Task 6: Los docs y los diagramas

**Files:**
- Modify: `CLAUDE.md` (la sección del taller)
- Modify: `docs/proceso.workflow.json`, `docs/arquitectura.architecture.json`
- Modify: `docs/proceso.html`, `docs/arquitectura.html` (los regenera `deliver`)

**Interfaces:** ninguna.

- [ ] **Step 1: `CLAUDE.md`**

En la sección del taller, sumar: un taller es de una sola fase y se verifica en `Open`; el reparto automático con sus dos entradas; que `attended` no se llama `present` por el choque con `Object#present?`; y que el reparto se niega con propuestas hechas por el CASCADE de `workshop_group_id`.

Corregir la línea que hoy dice que la mesa no se programa: sigue siendo cierto que sus integrantes nacen colaboradores de la idea, pero ahora **hay** una forma de programarla.

- [ ] **Step 2: Los dos diagramas**

`docs/proceso.workflow.json`, tarjeta «El taller, que no es una etapa»: el ítem «La mesa no se programa: sus integrantes nacen colaboradores de la idea» pasa a decir que el taller arma sus mesas —por cabeza en idear, por trabajo compartido en evolución— y sumar que un taller es de una sola fase.

- [ ] **Step 3: Validar, entregar y medir**

```bash
A=~/.claude/skills/archify/bin/archify.mjs
node $A validate workflow docs/proceso.workflow.json --quality showcase --json
node $A deliver workflow docs/proceso.workflow.json docs/proceso.html --quality showcase --json
export ARCHIFY_CHROME=~/.cache/ms-playwright/chromium-1223/chrome-linux64/chrome
node $A visual-check docs/proceso.html --json
```
Expected: 9 checks, 0 errores, 0 warnings en `validate`; `deliver` ok. **`visual-check` va a seguir fallando el contenido vertical**: ya fallaba antes de esta tanda (proceso medía 1688px de alto en un viewport de 900). No es una regresión de este plan; medir y comparar contra ese número.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md docs/proceso.workflow.json docs/proceso.html docs/arquitectura.architecture.json docs/arquitectura.html
git commit -m "Docs: el taller arma sus mesas, y es de una sola fase

La tarjeta del proceso decía «la mesa no se programa». Sigue siendo cierto que
sus integrantes nacen colaboradores de la idea, pero ahora hay una forma de
programarla, y un taller es de una sola fase.

visual-check sigue fallando el contenido vertical de los dos diagramas: venía
fallando desde antes y está medido en CLAUDE.md."
```
