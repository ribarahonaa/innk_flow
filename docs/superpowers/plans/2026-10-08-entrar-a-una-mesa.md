# Entrar a una mesa — plan de implementación

> **Para quien ejecute esto con agentes:** SUB-SKILL REQUERIDA: usá
> `superpowers:subagent-driven-development` (recomendada) o
> `superpowers:executing-plans` para implementar tarea por tarea. Los pasos usan
> casillas (`- [ ]`) para seguimiento.

**Goal:** Quien administra un desafío entra a cualquier mesa de su taller y la
trabaja como si fuera la suya, **sin ocupar un asiento**.

**Architecture:** `Workshop#group_of(user)` se queda significando «mi mesa». Al
lado aparece la pregunta nueva —«sobre qué mesa estoy actuando»— resuelta en UN
lugar y consultada por los cinco caminos que la necesitan. El asiento propio
gana siempre; el parámetro sólo lo puede usar quien administra ESE desafío, y
para el resto se **ignora** en vez de rechazarse, para no volverlo un oráculo de
existencia.

**Tech Stack:** Rails 7.1, Pundit, HAML, Postgres con `structure.sql`.

**Spec:** `docs/superpowers/specs/2026-10-08-entrar-a-una-mesa-design.md`

## Global Constraints

- **El código va en inglés; los comentarios y los mensajes de commit, en
  español.**
- **Todo corre en Docker. Nunca `bundle exec` en el host.** Los specs van por
  `make spec*`, que usa `app_test`; `docker compose exec app bundle exec rspec`
  devuelve 403 «Blocked hosts» en todos los request specs.
- **Lo que no se ve da 404, no 403.** Un 403 es un oráculo de existencia.
- **Toda lectura del dominio en un spec va dentro de `as_company(company)`**,
  incluido un `.new` o un `build`.
- El helper de sesión es **`sign_in(user, company: company)`**
  (`spec/support/tenant_helpers.rb`).
- **Pundit, no CanCanCan.** Cada policy declara su `Scope` explícitamente.
- **Zeitwerk: una constante por archivo.**
- **Sin migraciones.** Esta feature no agrega ni cambia ninguna columna.
- **Baseline medido hoy: `make spec` da 1770 ejemplos, 0 fallas.** Cada tarea
  dice cuántos suma. Si el total no cuadra, decilo en el reporte en vez de
  ajustar el número.
- Los commits van **sin línea `Co-Authored-By`**, y no se pushea.
- Rama: `entrar-a-una-mesa`, ya creada, con la spec en `eb62105`.

## Hechos del repo verificados antes de escribir esto

Están acá porque tres de ellos **desmienten** lo que este plan decía en su
primera versión, y uno es un identificador inventado de la misma familia que el
`sign_in_as` que ya costó una ronda en la sesión anterior:

- **No existe una factory `:challenge_gestor`.** Los ocho specs que asignan un
  gestor usan `ChallengeGestor.create!(challenge: …, user: …)` directo
  (`spec/policies/gestor_administra_spec.rb:48`). Usá eso.
- **`arrival` es un TRAIT, no un atributo**: `create(:workshop_group, :arrival,
  workshop: w)`, y el trait además fija `name { "Mesa de llegada" }`.
- **La factory `:workshop_group` numera `sequence(:name) { |n| "Mesa #{n}" }`.**
  Una aserción `include("Mesa 3")` puede pasar **sola**, por el nombre que la
  secuencia le puso a cualquier otra mesa. Es la familia del `ideas` sin columna
  `title` que `CLAUDE.md` documenta. **Todas las mesas de estos specs llevan
  nombre distintivo** (`"Mesa del fondo"`, `"Mesa de la ventana"`), nunca
  `"Mesa N"`.
- **`WorkshopChallenge#workable?` existe** (`app/models/workshop_challenge.rb:37`).
- **Los helpers de ruta son** `workshop_sala_path`, `workshop_sala_ideas_path`,
  `workshop_sala_proposals_path`, `workshop_sala_draft_path` (singular),
  `workshop_sala_recordings_path` y `workshop_sala_recording_path`.
- **`@link` ya existe en los cuatro controllers de escritura**, puesto por su
  propio `find_by!` sobre `@workshop.workshop_challenges`.
- **`grep -rni "tu mesa" app/views` da 10 líneas, pero una es un COMENTARIO**
  (`workshops/_group_body.html.haml:6`). Los textos son **nueve**.

## Review Focus

Seis entradas que la spec implica y que ninguna tarea cubriría si no se
dijeran. Cada una tiene su test asignado:

1. **Un `participant` que manda el parámetro nombrando otra mesa.** Tiene que
   escribir en LA SUYA — ignorado, no rechazado. → Tareas 1 y 3.
2. **Un gestor que administra OTRO desafío del mismo taller.**
   `administers_any?` le daría true y no tiene que alcanzar: el permiso es por
   desafío. → Tareas 1, 3bis y 4.
3. **Un id de mesa de otro taller, o de otra empresa.** Cae al asiento propio, y
   sin 403. → Tarea 1.
4. **La mesa de llegada nombrada por parámetro.** Entrar a mirarla puede estar
   bien; **trabajar** desde ella no se abre para nadie — y el texto «Tu mesa
   todavía no se armó» mentiría. → Tareas 2 y 3.
5. **Basura en el parámetro** —cadena, array, clave ausente—. La columna es
   `uuid`, así que castea a `nil`; tiene que caer al asiento propio y no
   levantar. → Tarea 1.
6. **El audio de una mesa de un desafío que quien pide NO administra.** Es el
   paso 3bis: un permiso por TALLER sobre contenido de UN desafío. → Tarea 3.

---

## Estructura de archivos

| Archivo | Responsabilidad | Tarea |
|---|---|---|
| `app/policies/challenge_policy.rb` | suma `enter_any_group?` | 1 |
| `app/models/workshop.rb` | suma `group_named(id)` | 1 |
| `app/controllers/concerns/acts_on_a_group.rb` | **nuevo** · `acting_group` / `own_group` | 1 |
| `app/controllers/workshop_rooms_controller.rb` | usa el concern y publica `@mesa_propia` | 2 |
| `config/locales/es.yml` | el texto del aviso | 2 |
| `app/views/workshop_rooms/_aviso_mesa_ajena.html.haml` | **nuevo** · el aviso | 2 |
| `app/views/workshops/_my_group.html.haml` | el título deja de ser fijo | 2 |
| `app/views/workshop_rooms/_ideation.html.haml`, `_evolution.html.haml` | los nueve textos usan la variable | 2 |
| `app/controllers/workshop_ideas_controller.rb`, `workshop_proposals_controller.rb`, `workshop_drafts_controller.rb`, `workshop_recordings_controller.rb` | los cuatro usan el concern; recordings además arregla `alcanzables` | 3 |
| `app/views/workshops/_groups.html.haml` | el «Entrar» por mesa y por vínculo | 4 |
| `CLAUDE.md`, `handoff.md` | la documentación | 5 |

---

## Tarea 1: El mecanismo

**Files:**
- Modify: `app/policies/challenge_policy.rb`
- Modify: `app/models/workshop.rb`
- Create: `app/controllers/concerns/acts_on_a_group.rb`
- Test: `spec/models/workshop_acting_group_spec.rb` (nuevo)

**Interfaces:**
- Produces: `ChallengePolicy#enter_any_group?` → `Boolean`.
  `Workshop#group_named(id)` → `WorkshopGroup` o `nil`, acotado a ese taller.
  `ActsOnAGroup#acting_group(workshop, link)` → `WorkshopGroup` o `nil`, para
  usar desde un controller; lee `params[:mesa]`.
  `ActsOnAGroup#own_group(workshop)` → el asiento propio, **memoizado**: lo
  consulta el aviso de la Tarea 2 sin pagar una segunda consulta.
- Consumes: `ApplicationPolicy#administers?(challenge)` (`:57-59`), que ya existe.

**Por qué un predicado nuevo y no uno prestado:** `ChallengePolicy#builder?` y
`#curate_pool?` son los dos, hoy, exactamente `administers?(record)`. Reusar uno
ahorra una línea y crea una dependencia falsa: el día que alguien haga
`curate_pool?` más estricto o más laxo, el acceso a las mesas se movería con él
sin que nadie lo haya decidido. **Un nombre prestado es cómo un permiso se
ensancha en silencio.**

- [ ] **Paso 1: Escribir el spec que falla**

Crear `spec/models/workshop_acting_group_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# «Sobre qué mesa estoy actuando» es una pregunta distinta de «cuál es mi mesa»,
# y vive en un solo lugar. El asiento propio gana siempre: es lo que hace que
# nada de lo que ya funciona cambie de comportamiento.
RSpec.describe "la mesa sobre la que se actúa" do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email, rol = :participant)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, rol, company: company, user: u)
      u
    end
  end

  let!(:ana)   { member("ana@test.dev") }
  let!(:admin) { member("admin@test.dev", :admin) }

  # Un taller con dos desafíos y dos mesas. Ana se sienta en la primera.
  # Los nombres son distintivos a propósito: la factory numera «Mesa N», así
  # que aseverar sobre «Mesa 3» puede pasar solo por la secuencia.
  let!(:setup) do
    as_company(company) do
      uno = create(:challenge)
      otro = create(:challenge)
      paso_uno = create(:challenge_step, challenge: uno, kind: "ideation", status: "active")
      paso_otro = create(:challenge_step, challenge: otro, kind: "ideation", status: "active")
      workshop = create(:workshop, status: "open")
      link_uno = create(:workshop_challenge, workshop: workshop, challenge: uno,
                                             challenge_step: paso_uno)
      link_otro = create(:workshop_challenge, workshop: workshop, challenge: otro,
                                              challenge_step: paso_otro)
      mesa_de_ana = create(:workshop_group, workshop: workshop, name: "Mesa del fondo")
      otra_mesa = create(:workshop_group, workshop: workshop, name: "Mesa de la ventana")
      create(:workshop_group_member, workshop_group: mesa_de_ana, user: ana)
      { workshop: workshop, link_uno: link_uno, link_otro: link_otro,
        mesa_de_ana: mesa_de_ana, otra_mesa: otra_mesa, uno: uno, otro: otro }
    end
  end

  describe "Workshop#group_named" do
    it "encuentra una mesa de ESTE taller" do
      as_company(company) do
        expect(setup[:workshop].group_named(setup[:otra_mesa].id)).to eq(setup[:otra_mesa])
      end
    end

    it "no encuentra una mesa de OTRO taller" do
      # La búsqueda cuelga de `workshop_groups`, que filtra por taller y —vía
      # `TenantScoped`— por empresa: dos exclusiones independientes.
      as_company(company) do
        ajena = create(:workshop_group, workshop: create(:workshop, status: "open"))

        expect(setup[:workshop].group_named(ajena.id)).to be_nil
      end
    end

    it "no revienta con basura: la columna es uuid y castea a nil" do
      as_company(company) do
        expect(setup[:workshop].group_named("no-es-un-uuid")).to be_nil
        expect(setup[:workshop].group_named(nil)).to be_nil
        expect(setup[:workshop].group_named([1, 2])).to be_nil
      end
    end
  end

  describe "ChallengePolicy#enter_any_group?" do
    it "es true para quien administra la empresa" do
      as_company(company) do
        m = Membership.find_by(user: admin)

        expect(ChallengePolicy.new(m, setup[:uno]).enter_any_group?).to be(true)
      end
    end

    it "es false para quien participa" do
      as_company(company) do
        m = Membership.find_by(user: ana)

        expect(ChallengePolicy.new(m, setup[:uno]).enter_any_group?).to be(false)
      end
    end

    it "para un gestor es por DESAFÍO y no por taller" do
      # `administers_any?` le daría true por administrar ALGUNO del taller. Acá
      # no alcanza: el permiso tiene que ser del desafío de esta sala, porque la
      # sala ya le da 404 en el brief de un desafío que no le asignaron.
      #
      # No hay factory `:challenge_gestor`: los specs que ya existen usan
      # `ChallengeGestor.create!` directo.
      gestor = member("gestor@test.dev", :gestor)
      as_company(company) do
        ChallengeGestor.create!(challenge: setup[:uno], user: gestor)
        m = Membership.find_by(user: gestor)

        expect(ChallengePolicy.new(m, setup[:uno]).enter_any_group?).to be(true)
        expect(ChallengePolicy.new(m, setup[:otro]).enter_any_group?).to be(false)
      end
    end
  end
end
```

- [ ] **Paso 2: Correr el spec y verificar que falla**

```bash
make spec-file FILE=spec/models/workshop_acting_group_spec.rb
```

Esperado: FAIL con `NoMethodError: undefined method 'group_named'`.

- [ ] **Paso 3: Sumar el predicado**

En `app/policies/challenge_policy.rb`, junto a `curate_pool?`:

```ruby
  # Entrar a cualquier mesa de un taller que trabaja este desafío, y trabajarla
  # sin estar sentado.
  #
  # Predicado propio y NO `builder?` ni `curate_pool?`, que hoy son los dos
  # exactamente `administers?(record)`: reusar uno ahorra una línea y ata el
  # acceso a las mesas al significado de otra cosa. El día que alguien mueva
  # `curate_pool?`, esto se movería con él sin que nadie lo decida.
  #
  # Y es por DESAFÍO y no por taller (`WorkshopPolicy#administers_any?`): la
  # sala ya le esconde a un gestor el brief de un desafío que no le asignaron
  # —`alcanza = policy(link.challenge).show?`—, así que dejarlo ESCRIBIR ahí
  # sería abrir escritura sobre algo que no puede leer.
  def enter_any_group? = administers?(record)
```

- [ ] **Paso 4: Sumar la búsqueda al modelo**

En `app/models/workshop.rb`, junto a `group_of`:

```ruby
  # Una mesa de ESTE taller, por id. Lo que la hace segura son dos cosas
  # independientes: cuelga de `workshop_groups` —que filtra por taller y, vía
  # `TenantScoped`, por empresa— y la columna es `uuid`, así que basura, un
  # no-entero o un array castean a `nil` antes del SQL. Es el mismo par que
  # `CLAUDE.md` documenta como portante para `base_version_id`.
  #
  # No pregunta permisos: quién puede nombrar una mesa lo decide el controller,
  # porque es una pregunta de Pundit y el modelo no la tiene.
  def group_named(id) = workshop_groups.find_by(id: id)
```

- [ ] **Paso 5: Escribir el concern**

Crear `app/controllers/concerns/acts_on_a_group.rb`:

```ruby
# frozen_string_literal: true

# «Sobre qué mesa estoy actuando»: una pregunta, un lugar.
#
# `Workshop#group_of` se queda significando «mi mesa» y la siguen preguntando
# los dos lugares donde eso es lo correcto —el panel «Mi mesa» de la pantalla
# del taller (`workshops_controller:84`) y el camino sin administrar de las
# grabaciones alcanzables (`workshop_recordings_controller:72`)—. Esto contesta
# la otra, y la consultan los cinco caminos de la sala.
#
# Escrita una vez a propósito: cinco caminos que resuelvan la mesa por su cuenta
# es la forma en que uno queda con `group_of(current_user)` y, sin fallar,
# **escribe en la mesa equivocada**.
module ActsOnAGroup
  extend ActiveSupport::Concern

  private

  # El asiento propio GANA SIEMPRE, y no es un detalle: es lo que hace que nada
  # de lo que ya funciona cambie de comportamiento —incluido el recorrido, cuyo
  # admin está sentado a propósito en el seed (`db/seeds.rb:857` y `:888`), de
  # lo que dependen `[DRAFT] 2` y `[GRABAR] 2`—.
  #
  # Si no hay asiento y quien mira administra ESE desafío, vale la mesa que
  # nombra el parámetro. Para todos los demás el parámetro se **ignora**, no se
  # rechaza: un 403 confirmaría que esa mesa existe.
  def acting_group(workshop, link)
    own_group(workshop) || named_group(workshop, link)
  end

  # Memoizado porque lo preguntan dos veces por render: `acting_group` y el
  # aviso de mesa ajena, que compara una contra la otra.
  def own_group(workshop)
    @own_group = workshop.group_of(current_user) unless defined?(@own_group)
    @own_group
  end

  def named_group(workshop, link)
    return nil if params[:mesa].blank?
    return nil unless policy(link.challenge).enter_any_group?

    workshop.group_named(params[:mesa])
  end
end
```

- [ ] **Paso 6: Correr el spec y verificar que pasa**

```bash
make spec-file FILE=spec/models/workshop_acting_group_spec.rb
```

Esperado: PASS, **6 ejemplos**. Si contás otro número, decilo en el reporte en
vez de ajustar nada.

- [ ] **Paso 7: Correr la suite**

```bash
make spec
```

Esperado: 1770 + 6 = **1776 ejemplos, 0 fallas**. Nada existente debería
moverse: el concern todavía no lo usa nadie.

- [ ] **Paso 8: Commit**

```bash
git add app/policies/challenge_policy.rb app/models/workshop.rb \
        app/controllers/concerns/acts_on_a_group.rb \
        spec/models/workshop_acting_group_spec.rb
git commit -m "La mesa sobre la que se actúa es una pregunta nueva, con un solo lugar donde vive"
```

---

## Tarea 2: La sala resuelve otra mesa, y lo dice

**Files:**
- Modify: `app/controllers/workshop_rooms_controller.rb`
- Modify: `config/locales/es.yml`
- Create: `app/views/workshop_rooms/_aviso_mesa_ajena.html.haml`
- Modify: `app/views/workshops/_my_group.html.haml`
- Modify: `app/views/workshop_rooms/_ideation.html.haml`
- Modify: `app/views/workshop_rooms/_evolution.html.haml`
- Test: `spec/requests/entrar_a_una_mesa_spec.rb` (nuevo)

**Interfaces:**
- Consumes: `acting_group(workshop, link)` y `own_group(workshop)` de la Tarea 1.
- Produces: `@group` resuelto con el concern, y **`@mesa_propia`** (`Boolean`),
  que las vistas usan para decidir el nombre y para dibujar el aviso.

**La variable es UNA, no nueve condicionales.** Son **nueve** textos que dicen
«tu mesa», en cuatro archivos (`grep -rni "tu mesa" app/views` da diez líneas y
la décima es un comentario en `_group_body.html.haml:6`):

```
app/views/workshops/_my_group.html.haml:10      %h2.section-title Tu mesa
app/views/workshops/_my_group.html.haml:14      …acá aparece tu mesa.
app/views/workshop_rooms/_evolution.html.haml:20  Tu mesa todavía no se armó…
app/views/workshop_rooms/_evolution.html.haml:34  Ninguna persona de tu mesa…
app/views/workshop_rooms/_evolution.html.haml:39  Las ideas de tu mesa
app/views/workshop_rooms/_evolution.html.haml:95  …lo que tecleó tu mesa sobre…
app/views/workshop_rooms/_ideation.html.haml:23   Tu mesa todavía no se armó…
app/views/workshop_rooms/_ideation.html.haml:55   Las ideas de tu mesa
app/views/workshop_rooms/_ideation.html.haml:56   Las que creó alguien de tu mesa…
```

El nombre se resuelve arriba y los nueve lo usan. Un `if` repetido nueve veces
son nueve lugares donde el día que cambie uno se olvida; es la forma que ya usan
`puede_configurar` y el `alcanza` de la sala.

**Ojo con los dos «todavía no se armó»** (`_evolution:20`, `_ideation:23`): ésos
son la rama de la mesa de llegada, y hoy sólo los ve quien está sentado ahí. Con
esta feature, quien administra puede nombrar la llegada por parámetro y caer en
esa rama — así que esos dos **también** usan la variable, o le dicen «tu mesa» a
una mesa que no es suya.

- [ ] **Paso 1: Escribir el spec que falla**

Crear `spec/requests/entrar_a_una_mesa_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# Quien administra entra a una mesa y la trabaja sin sentarse. El riesgo de la
# feature es que nueve textos digan «tu mesa» sobre contenido ajeno.
RSpec.describe "entrar a una mesa del taller", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email, rol = :participant)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, rol, company: company, user: u)
      u
    end
  end

  let!(:ana)   { member("ana@test.dev") }
  let!(:admin) { member("admin@test.dev", :admin) }

  let!(:idear) do
    as_company(company) do
      challenge = create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: "ideation", status: "active")
      create(:form_field, challenge_step: step, label: "Resumen", field_type: "text")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge,
                                         challenge_step: step)
      # Nombre distintivo: la factory numera «Mesa N» y una aserción sobre ése
      # podría pasar sola.
      mesa = create(:workshop_group, workshop: workshop, name: "Mesa del fondo")
      create(:workshop_group_member, workshop_group: mesa, user: ana)
      { workshop: workshop, link: link, mesa: mesa, challenge: challenge }
    end
  end

  def visitar(mesa: nil)
    get workshop_sala_path(idear[:workshop], idear[:link], mesa: mesa&.id)
  end

  context "quien administra y no está sentado" do
    before { sign_in(admin, company: company) }

    it "sin el parámetro sigue viendo que no tiene mesa" do
      # El comportamiento de hoy no cambia: entrar sin nombrar una mesa es lo
      # que era. Mirá la vista para el texto exacto y usá ése.
      visitar

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Mesa del fondo")
    end

    it "nombrando una mesa trabaja ESA mesa" do
      visitar(mesa: idear[:mesa])

      expect(response.body).to include("data-draft-url")
    end

    it "los títulos dicen el NOMBRE de la mesa y no «tu mesa»" do
      # Es el riesgo nº1 de la spec: nueve textos que mienten en cuanto la mesa
      # es ajena.
      visitar(mesa: idear[:mesa])

      expect(response.body).to include("Mesa del fondo")
      expect(response.body).not_to match(/ideas de tu mesa/i)
    end

    it "avisa que la mesa es ajena y que lo que escriba queda a su nombre" do
      visitar(mesa: idear[:mesa])

      expect(response.body).to include("sin estar sentado")
      expect(response.body).to include("queda a tu nombre")
    end

    it "nombrando la mesa de LLEGADA no dice «tu mesa»" do
      # La rama de la llegada hoy sólo la ve quien está sentado ahí. Quien
      # administra puede nombrarla, y el texto tiene que acompañar.
      llegada = as_company(company) { create(:workshop_group, :arrival, workshop: idear[:workshop]) }

      visitar(mesa: llegada)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to match(/tu mesa todavía no se armó/i)
    end
  end

  context "quien participa" do
    before { sign_in(ana, company: company) }

    it "ve «tu mesa» en su propia mesa, sin aviso" do
      visitar

      expect(response.body).to match(/ideas de tu mesa/i)
      expect(response.body).not_to include("sin estar sentado")
    end

    it "nombrando OTRA mesa sigue viendo la suya, sin 403" do
      # El parámetro se IGNORA, no se rechaza: un 403 confirmaría que esa mesa
      # existe.
      otra = as_company(company) do
        create(:workshop_group, workshop: idear[:workshop], name: "Mesa de la ventana")
      end

      visitar(mesa: otra)

      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/ideas de tu mesa/i)
      expect(response.body).not_to include("Mesa de la ventana")
    end
  end
end
```

- [ ] **Paso 2: Correr el spec y verificar que falla**

```bash
make spec-file FILE=spec/requests/entrar_a_una_mesa_spec.rb
```

Esperado: FAIL. El de «nombrando una mesa trabaja ESA mesa» falla porque hoy
`@group` es nil para el admin.

- [ ] **Paso 3: Sumar el texto del aviso al locale**

En `config/locales/es.yml`, dentro de `flow:`:

```yaml
    rooms:
      foreign_group_html: "Estás trabajando <strong>%{group}</strong> sin estar sentado en ella. Lo que escribas, grabes o mandes queda a tu nombre."
```

- [ ] **Paso 4: El controller usa el concern**

En `app/controllers/workshop_rooms_controller.rb`:

```ruby
class WorkshopRoomsController < ApplicationController
  include ActsOnAGroup
```

y la línea 25 pasa a:

```ruby
    # «Sobre qué mesa actúo», no «cuál es mi mesa»: quien administra ESE desafío
    # puede nombrar una.
    @group = acting_group(@workshop, @link)
    # Si la mesa salió del parámetro y no del asiento, los títulos no pueden
    # decir «tu mesa»: es la misma fuga que `load_ideation` documenta, con el
    # título mintiendo en vez del scope. `own_group` está memoizado, así que
    # esto no paga una segunda consulta.
    @mesa_propia = @group.present? && @group == own_group(@workshop)
```

Y el comentario de `authorize @workshop, :work?` (líneas 13-15) se corrige:
sigue siendo cierto que `work?` incluye a quien administra sin asiento, pero ya
no es cierto que la cara «le dice que no tiene mesa» — eso pasa sólo si no
nombra una.

- [ ] **Paso 5: El aviso**

Crear `app/views/workshop_rooms/_aviso_mesa_ajena.html.haml`:

```haml
-# El título dice de quién es el contenido; esto dice qué estás haciendo. Son
-# cosas distintas, y la segunda es la que previene tipear creyendo que estás en
-# la propia. Va arriba de todo el trabajo.
-#
-# `alert` de DaisyUI es `display: grid` con `grid-auto-flow: column`, así que el
-# contenido va en UN solo `%div` o se reparte en columnas.
.alert.alert-soft.alert-warning
  %div= t("flow.rooms.foreign_group_html", group: group.name).html_safe
```

Se renderiza al principio de las dos caras, detrás de la misma pregunta
(`- unless mesa_propia`).

- [ ] **Paso 6: Los nueve textos**

Cada archivo calcula la variable una vez, arriba:

```haml
- de_la_mesa = mesa_propia ? "tu mesa" : group.name
```

y los textos la interpolan: `Las ideas de #{de_la_mesa}`,
`Ninguna persona de #{de_la_mesa} tiene ideas postuladas…`,
`#{de_la_mesa.capitalize} todavía no se armó: …`. **No un `if` por frase.**

En `workshops/_my_group.html.haml` el título «Tu mesa» pasa a ser el nombre
cuando la mesa es ajena. Ese partial lo renderizan DOS lugares —la sala y la
pantalla del taller—, así que recibe la variable **como local con default
`true`**: en la pantalla del taller (`workshops_controller:84`, que no cambia)
la mesa siempre es la propia.

- [ ] **Paso 7: Correr el spec y verificar que pasa**

```bash
make spec-file FILE=spec/requests/entrar_a_una_mesa_spec.rb
```

Esperado: PASS, **7 ejemplos**.

- [ ] **Paso 8: Ver fallar el riesgo nº1**

Mutación: en el controller, poné `@mesa_propia = true` fijo. El ejemplo de «los
títulos dicen el NOMBRE» tiene que ponerse **rojo**, y el de «ve tu mesa en su
propia mesa» seguir verde. **Pegá el output.**

Restaurá **editando la línea**, no con `git checkout` —que desharía el arreglo y
no la mutación—, y verificá con `git diff HEAD -- app` vacío.

- [ ] **Paso 9: Suite y commit**

```bash
make spec
```

Esperado: 1776 + 7 = **1783 ejemplos, 0 fallas**.

```bash
git add app/controllers/workshop_rooms_controller.rb app/views/workshop_rooms/ \
        app/views/workshops/_my_group.html.haml config/locales/es.yml \
        spec/requests/entrar_a_una_mesa_spec.rb
git commit -m "La sala resuelve la mesa sobre la que se actúa, y los títulos dejan de decir «tu mesa» cuando es ajena"
```

---

## Tarea 3: Los cuatro caminos de escritura (y el audio)

**Files:**
- Modify: `app/controllers/workshop_ideas_controller.rb` (:23)
- Modify: `app/controllers/workshop_proposals_controller.rb` (:15)
- Modify: `app/controllers/workshop_drafts_controller.rb` (:33)
- Modify: `app/controllers/workshop_recordings_controller.rb` (:24 y :70)
- Test: `spec/requests/escribir_en_una_mesa_ajena_spec.rb` (nuevo)

**Interfaces:**
- Consumes: `ActsOnAGroup` de la Tarea 1.
- Produces: nada nuevo. Los cuatro endpoints aceptan `mesa` en el **cuerpo**.

**Es un batch de cuatro cambios de la misma forma**, y aun así la verificación es
**por endpoint**: cada uno resuelve la mesa por su cuenta, y si uno queda con
`group_of(current_user)` **no falla — escribe en la mesa equivocada, en
silencio**. Ese es el riesgo nº2 de la spec.

**Y hay una fuga ya arreglada que no se puede reabrir.**
`workshop_ideas_controller:23` documenta: «quien administra un desafío del taller
creaba una idea a su nombre —sin pasar nunca por `IdeaPolicy#create?`— y podía
hacerlo en la sala de un desafío ajeno». El `authorize` de `IdeaPolicy#create?`
**se queda donde está**: lo que cambia es de qué mesa es la idea, no quién puede
firmarla.

- [ ] **Paso 1: Escribir el spec que falla**

Crear `spec/requests/escribir_en_una_mesa_ajena_spec.rb`. El esqueleto muestra
el bloque del borrador; **escribí los cuatro completos**, con los mismos tres
ejemplos adaptados al payload de cada uno. Mirá cada controller para su payload;
`spec/requests/workshop_recordings_spec.rb` es el molde para subir un archivo.

```ruby
# frozen_string_literal: true

require "rails_helper"

# Cuatro caminos que resuelven la mesa por separado. Si uno queda con
# `group_of(current_user)` no falla: escribe en la mesa equivocada, en silencio.
# Por eso hay un bloque por endpoint y no un ejemplo del mecanismo.
RSpec.describe "escribir sobre una mesa ajena", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email, rol = :participant)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, rol, company: company, user: u)
      u
    end
  end

  let!(:ana)   { member("ana@test.dev") }
  let!(:admin) { member("admin@test.dev", :admin) }

  let!(:idear) do
    as_company(company) do
      challenge = create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: "ideation", status: "active")
      field = create(:form_field, challenge_step: step, label: "Resumen", field_type: "text")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge,
                                         challenge_step: step)
      mesa = create(:workshop_group, workshop: workshop, name: "Mesa del fondo")
      otra = create(:workshop_group, workshop: workshop, name: "Mesa de la ventana")
      create(:workshop_group_member, workshop_group: mesa, user: ana)
      { workshop: workshop, link: link, mesa: mesa, otra: otra, field: field }
    end
  end

  describe "el borrador" do
    it "quien administra escribe sobre la mesa que nombra" do
      sign_in(admin, company: company)

      patch workshop_sala_draft_path(idear[:workshop], idear[:link]),
            params: { mesa: idear[:mesa].id, payload: { idear[:field].key => "texto" } }

      expect(response).to have_http_status(:no_content)
      draft = as_company(company) { WorkshopDraft.last }
      expect(draft.workshop_group).to eq(idear[:mesa])
      expect(draft.updated_by).to eq(admin)
    end

    it "quien participa nombrando otra mesa escribe en LA SUYA" do
      sign_in(ana, company: company)

      patch workshop_sala_draft_path(idear[:workshop], idear[:link]),
            params: { mesa: idear[:otra].id, payload: { idear[:field].key => "texto" } }

      expect(response).to have_http_status(:no_content)
      expect(as_company(company) { WorkshopDraft.last.workshop_group }).to eq(idear[:mesa])
    end

    it "desde la mesa de llegada nombrada por parámetro, no escribe" do
      # Trabajar desde la llegada no se abre para nadie: es sala de espera, y
      # eso no depende de quién mira. Mirá el controller para el código que
      # devuelve su `reject_arrival` y aseverá ÉSE.
      llegada = as_company(company) { create(:workshop_group, :arrival, workshop: idear[:workshop]) }
      sign_in(admin, company: company)

      patch workshop_sala_draft_path(idear[:workshop], idear[:link]),
            params: { mesa: llegada.id, payload: { idear[:field].key => "x" } }

      expect(as_company(company) { WorkshopDraft.count }).to eq(0)
    end
  end

  # … y lo mismo para `workshop_sala_ideas_path`, `workshop_sala_proposals_path`
  # y `workshop_sala_recordings_path`.
end
```

Si para algún endpoint un ejemplo no aplica —por ejemplo, el gestor y las
ideas—, **decilo en el reporte** en vez de omitirlo en silencio.

- [ ] **Paso 2: Correr y verificar que falla**

```bash
make spec-file FILE=spec/requests/escribir_en_una_mesa_ajena_spec.rb
```

Esperado: los ejemplos de «quien administra escribe sobre la mesa que nombra»
fallan en los cuatro (hoy `group` es nil y responden 403 / `:conflict`).

- [ ] **Paso 3: Los cuatro usan el concern**

En cada uno: `include ActsOnAGroup`, y la línea
`group = @workshop.group_of(current_user)` pasa a
`group = acting_group(@workshop, @link)`.

**Nada más.** El orden de las guardas no se toca, el rechazo sin mesa y el de la
llegada siguen donde están, y el `authorize` de `IdeaPolicy#create?` en el
controller de ideas se queda: cambia **de qué mesa es** la idea, no **quién
puede firmarla**.

- [ ] **Paso 3bis: El audio — un permiso por TALLER sobre contenido de UN desafío**

Esto **no** estaba en la spec y sale de medir el repo mientras se escribía este
plan. `workshop_recordings_controller#alcanzables` (:70) abre con:

```ruby
    return @link.workshop_recordings if policy(@workshop).update?
```

`WorkshopPolicy#update?` es `administers_any?`, o sea **administrar ALGÚN
desafío del taller**. Así que un gestor asignado al desafío A puede pedir por
URL el audio de una grabación hecha en la sala del desafío B —la conversación de
una mesa sobre un desafío cuyo brief la sala le esconde y cuyo
`GET /challenges/:id` le da 404—. La lista de la sala nunca se lo ofrece
(`load_recordings` filtra por `@group`), así que sólo se llega escribiendo la
URL. **Es anterior a esta rama**, y entra acá porque es exactamente la decisión
central de esta feature —el permiso es por desafío, no por taller— contradicha
en el quinto lugar:

```ruby
    return @link.workshop_recordings if policy(@link.challenge).enter_any_group?
```

Quien administra la empresa no cambia (`manager?` pasa igual) y quien administra
ESTE desafío tampoco. Lo único que se cierra es el caso del gestor de otro
desafío del mismo taller. **La línea 72 sigue con `group_of(current_user)`**, que
ahí es lo correcto: a ese camino sólo llega quien no administra, y quien no
administra siempre está sentado.

Sumá su ejemplo al bloque de grabaciones: un gestor asignado a OTRO desafío del
taller pide `workshop_sala_recording_path` de una grabación de esta sala y
recibe **404**.

- [ ] **Paso 4: Correr y verificar que pasa**

```bash
make spec-file FILE=spec/requests/escribir_en_una_mesa_ajena_spec.rb
make spec
```

- [ ] **Paso 5: Ver fallar cada endpoint por separado**

Esto es el riesgo nº2 y la mutación es **una por endpoint**: devolvé **uno** de
los cuatro a `group_of(current_user)` y confirmá que falla **sólo su** bloque.
Repetilo para los cuatro y **pegá los cuatro outputs**. Si al mutar uno falla
también el bloque de otro, decilo: significaría que los bloques no son
independientes, y la verificación por endpoint sería una ilusión.

Una quinta mutación para el paso 3bis: volvé `alcanzables` a
`policy(@workshop).update?` y mirá que su ejemplo se ponga rojo.

Restaurá editando, y verificá con `git diff HEAD -- app` vacío.

- [ ] **Paso 6: Commit**

```bash
git add app/controllers/workshop_ideas_controller.rb \
        app/controllers/workshop_proposals_controller.rb \
        app/controllers/workshop_drafts_controller.rb \
        app/controllers/workshop_recordings_controller.rb \
        spec/requests/escribir_en_una_mesa_ajena_spec.rb
git commit -m "Los cuatro caminos de escritura de la sala actúan sobre la mesa nombrada, y el audio deja de abrirse por taller"
```

---

## Tarea 4: El «Entrar» en la lista de mesas

**Files:**
- Modify: `app/views/workshops/_groups.html.haml`
- Test: `spec/requests/entrar_a_una_mesa_spec.rb` (se le suman ejemplos)

**Interfaces:** ninguna nueva. Usa
`workshop_sala_path(workshop, link, mesa: group.id)`.

**La matriz que nadie nota:** las mesas son del **taller**, las salas son por
**vínculo**. Con 3 vínculos y 4 mesas hay 12 salas. Así que el «Entrar» es **por
vínculo trabajable**, rotulado con el nombre del desafío, y colapsa a un
«Entrar» pelado cuando hay un solo vínculo trabajable — la misma forma que ya
tiene el selector de `workshops#show`.

El partial ya está detrás de `can_assemble` (= `WorkshopPolicy#update?` =
`administers_any?`), así que lo ve quien administra algún desafío del taller.
El filtro por desafío del «Entrar» es lo que lo ata al permiso real.

- [ ] **Paso 1: Escribir los ejemplos**

Sumar a `spec/requests/entrar_a_una_mesa_spec.rb`:

- quien administra ve un «Entrar» por mesa en la pantalla del taller, apuntando
  a `workshop_sala_path(…, mesa: <id>)`;
- **no** aparece en la mesa de llegada;
- con dos vínculos trabajables, cada mesa tiene dos «Entrar», rotulados con el
  nombre de cada desafío;
- quien participa **no** ve ninguno (la lista completa ya está detrás de
  `can_assemble`, así que esto verifica que no se filtre por otro lado);
- un gestor que administra **uno** de los dos desafíos ve el «Entrar» de ese y
  **no** el del otro.

El último es el que ata la Tarea 4 con el permiso por desafío de la Tarea 1.

- [ ] **Paso 2: Correr y verificar que falla**

- [ ] **Paso 3: El «Entrar»**

En `app/views/workshops/_groups.html.haml`, **dentro del `%div` de la línea 58**,
después del `render` de `group_body`/`arrival_frame` (línea 66) y antes del form
de convocar (línea 68):

```haml
              -# Entrar a trabajar ESTA mesa sin sentarse. Uno por vínculo
              -# trabajable, porque las mesas son del TALLER y las salas son por
              -# vínculo: con tres desafíos y cuatro mesas hay doce salas. Con un
              -# solo vínculo el rótulo sobra, igual que en el selector de
              -# `workshops#show`.
              -#
              -# En la llegada no va: de ahí no se trabaja, y eso no depende de
              -# quién mire. Y sólo los vínculos cuyo desafío quien mira
              -# administra — el MISMO predicado que autoriza el POST, no
              -# `can_assemble`, que es por taller.
              - unless group.arrival?
                - entrables = workshop.workshop_challenges.select { |l| l.workable? && policy(l.challenge).enter_any_group? }
                - if entrables.any?
                  .form-actions
                    - entrables.each do |link|
                      = link_to workshop_sala_path(workshop, link, mesa: group.id), class: "btn btn-ghost btn-sm" do
                        - if entrables.one?
                          Entrar
                        - else
                          = "Entrar · #{link.challenge.name}"
```

- [ ] **Paso 4: Correr, verificar que pasa, y ver fallar el permiso**

Mutación: cambiá `policy(l.challenge).enter_any_group?` por `true`. El ejemplo
del gestor con dos desafíos tiene que ponerse rojo. **Pegá el output.**

- [ ] **Paso 5: Compilar y recorrer**

**Antes de correr, verificá el proveedor:** el stack tiene que estar en
`FLOW_AI_PROVIDER=fixture` o la corrida factura.

```bash
docker compose exec app env | grep "^FLOW_AI_PROVIDER"
make yarn-build
make seed
make screens
```

**No se tocó JavaScript**, así que `yarn-build` es por las clases nuevas de
Tailwind del aviso y del botón — y es obligatorio: la hoja compilada vive sólo
en el contenedor y está gitignoreada, así que sin eso `make screens` valida una
pantalla distinta de la que escribiste, en verde.

El recorrido tiene que quedar **verde con las once cifras** — y en particular
**`[DRAFT] 2` y `[GRABAR] 2`**, que dependen de que el admin del seed siga
resolviendo **su** asiento. Si alguno cae a 0, el asiento propio dejó de ganar y
el concern está al revés.

- [ ] **Paso 6: Commit**

---

## Tarea 5: La documentación

**Files:**
- Modify: `CLAUDE.md`
- Create/Modify: `handoff.md`

**Interfaces:** ninguna.

- [ ] **Paso 1: `CLAUDE.md`**

En la sección del taller, sumar lo que no se lee del código:

- **«Mi mesa» y «la mesa sobre la que actúo» son dos preguntas distintas**, y por
  qué `group_of` no se tocó: dos de sus siete llamadores preguntan legítimamente
  por la propia (`workshops_controller:84` y `workshop_recordings_controller:72`).
  Un método con dos significados es cómo se abren las fugas que este archivo ya
  documenta.
- **El asiento propio gana siempre**, y de eso depende que el recorrido no cambie
  de significado: el seed sienta al admin a propósito, y `[DRAFT]` y `[GRABAR]`
  lo miden.
- **El parámetro se ignora, no se rechaza**, y por qué: un 403 sería un oráculo.
- **El permiso es por desafío** (`ChallengePolicy#enter_any_group?`) y no por
  taller, con el motivo: la sala ya le esconde a un gestor el brief de un desafío
  ajeno. **Y `alcanzables` lo contradecía**: abría el audio por
  `administers_any?`. Anotar que la línea 72 sigue con `group_of` a propósito.
- **Las dos reglas del gestor con las ideas no se abrieron**, y no hizo falta
  escribir nada: el formulario ya vive detrás de `IdeaPolicy#create?`.
- **Los nueve textos «tu mesa» salen de UNA variable.** Si alguien agrega un
  texto nuevo con «tu mesa» fijo, miente en cuanto la mesa es ajena. **No hay
  guarda**: ni un spec ni `make screens` lo cazarían. El grep es
  `grep -rni "tu mesa" app/views`, y una de sus líneas es un comentario.

- [ ] **Paso 2: El handoff**

Las cinco secciones de siempre, **incluidos los intentos fallidos**. Lo que más
cuesta reconstruir: qué mutación puso en rojo a qué, por endpoint.

- [ ] **Paso 3: Verificación final y commit**

```bash
make spec
make screens
```

---

## Verificación final de la rama

- [ ] `make spec` en 0 fallas
- [ ] `make screens` verde, once cifras, **`[DRAFT] 2` y `[GRABAR] 2`**
- [ ] Las mutaciones vistas en rojo: `@mesa_propia` fijo, los cuatro endpoints
      uno por uno, `alcanzables`, y el permiso del «Entrar»
- [ ] `grep -rni "tu mesa" app/views` no devuelve ningún texto fijo que quede
      fuera de la variable (la línea de `_group_body:6` es un comentario)
- [ ] `grep -rn "group_of(current_user)" app` devuelve **sólo**
      `workshops_controller:84` y `workshop_recordings_controller:72`
