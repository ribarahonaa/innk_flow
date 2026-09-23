# El gestor administra sus desafíos — Plan de implementación

> **Para quien ejecute esto:** SUB-SKILL REQUERIDA: usá
> `superpowers:subagent-driven-development` (recomendado) o
> `superpowers:executing-plans` para ejecutar tarea por tarea. Los pasos usan
> checkbox (`- [ ]`) para seguimiento.

**Objetivo:** Que el rol `gestor` pueda, dentro de los desafíos que le
asignaron, lo mismo que un `admin` — sin ganar nada de lo que es de la empresa.

**Arquitectura:** Un predicado nuevo en `ApplicationPolicy`,
`administra?(challenge)`, que es `manager? || (gestor? && le asignaron ese
desafío)`. Se aplica puerta por puerta en seis policies. `manager?` se queda
donde protege lo que no cuelga de ningún desafío, así que una puerta futura que
lo escriba nace cerrada para el gestor. Ninguna vista cambia salvo una: los 45
usos de permisos en HAML ya preguntan por `policy(...)`.

**Stack:** Rails, Pundit (no CanCanCan), RSpec, HAML. Todo corre en Docker.

**Spec:** `docs/superpowers/specs/2026-09-23-gestor-administra-sus-desafios-design.md`

## Restricciones globales

- **Código, comentarios y mensajes de commit en español.**
- **Los specs corren en `app_test`**: siempre `make spec`, `make spec-file
  FILE=…`, `make spec-line FILE=… LINE=…`. Nunca `docker compose exec app
  bundle exec rspec` — devuelve 403 «Blocked hosts» en todos los request specs
  y parece que la app está rota.
- **Los commits no llevan línea `Co-Authored-By`.**
- **Nadie pushea.** Las ramas se quedan locales hasta que Raúl lo pida.
- **Toda lectura del dominio en un spec va dentro de `as_company(company) { … }`**,
  incluido un `.new` y cualquier asociación leída fuera del bloque. Sin tenant,
  `TenantScoped` revienta con `MissingTenant`.
- **Pundit no hereda el `Scope`**: si una policy necesita uno, se declara
  explícito (`class Scope < ApplicationPolicy::Scope; end`). Este plan no crea
  ninguno nuevo.
- **No se toca ninguna vista** salvo `app/views/steps/_criterios_editor.html.haml`
  en la Tarea 3.
- **El riesgo es abrir de más, y es silencioso.** Un permiso que se abre de más
  no rompe ningún test: deja pasar. Por eso cada tarea suma filas a la tabla de
  `spec/policies/gestor_administra_spec.rb` y **siempre** incluye al gestor **no
  asignado**, que es el sujeto donde un error se ve.

---

## Estructura de archivos

| Archivo | Responsabilidad | Tarea |
|---|---|---|
| `app/policies/application_policy.rb` | El predicado `administra?`, escrito una vez | 1 |
| `app/policies/challenge_policy.rb` | Las puertas del desafío + `create?` | 1, 4 |
| `app/policies/challenge_step_policy.rb` | Las puertas del módulo | 1 |
| `app/policies/idea_policy.rb` | Editar y borrar una idea | 2 |
| `app/policies/assessment_policy.rb` | Evaluar | 2 |
| `app/policies/feedback_item_policy.rb` | Cerrar un comentario | 2 |
| `app/policies/criteria_set_policy.rb` | Guardar un set `inline` | 3 |
| `app/controllers/challenges_controller.rb` | Auto-asignación al crear | 4 |
| `app/controllers/challenge_gestores_controller.rb` | No sacarse a uno mismo | 5 |
| `app/views/steps/_criterios_editor.html.haml` | Esconder el botón de promover | 3 |
| `spec/policies/gestor_administra_spec.rb` | La tabla del reparto entero | 1–4 |
| `spec/requests/gestor_spec.rb` | Dar vuelta lo que afirmaba lo contrario | 1, 2, 6 |

---

### Tarea 1: El predicado y las puertas del desafío y del módulo

**Archivos:**
- Modificar: `app/policies/application_policy.rb` (el bloque `private`, después
  de `reaches_challenge?`)
- Modificar: `app/policies/challenge_policy.rb:28-43`
- Modificar: `app/policies/challenge_step_policy.rb:10-29`
- Modificar: `spec/requests/gestor_spec.rb` (dos ejemplos)
- Crear: `spec/policies/gestor_administra_spec.rb`

**Interfaces:**
- Produce: `ApplicationPolicy#administra?(challenge)` → `Boolean`. Privado.
  Acepta `nil` sin reventar. Lo consumen las Tareas 2, 3 y 4.
- Produce: `spec/policies/gestor_administra_spec.rb`, con los helpers
  `usuario(rol, email)`, `desafio_con(*rasgos)` y `responde?(persona, clase,
  puerta)`, y los sujetos `admin`, `asignada` y `ajena`. Las Tareas 2, 3 y 4
  le suman `describe`s nuevos que reusan esos sujetos.

- [ ] **Paso 1: Escribir la tabla que falla**

Crear `spec/policies/gestor_administra_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# El reparto de permisos del gestor, entero y en un solo lugar.
#
# Existe porque abrir un permiso de más NO rompe ningún test: simplemente deja
# pasar. Por eso la tabla pregunta siempre por tres sujetos, y el que caza el
# error es el gestor NO asignado: para él toda puerta tiene que dar `false`.
RSpec.describe "qué administra el gestor" do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def usuario(rol, email)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, rol, company: company, user: u)
      u
    end
  end

  let!(:admin) { usuario(:admin, "admin@test.dev") }
  let!(:asignada) { usuario(:gestor, "asignada@test.dev") }
  let!(:ajena) { usuario(:gestor, "ajena@test.dev") }

  def desafio_con(*rasgos)
    as_company(company) do
      c = create(:challenge, *rasgos)
      c.steps.create!(kind: "ideation", position: 1)
      c
    end
  end

  let!(:borrador) { desafio_con }
  let!(:corriendo) { desafio_con(:running) }

  before do
    as_company(company) do
      ChallengeGestor.create!(challenge: borrador, user: asignada)
      ChallengeGestor.create!(challenge: corriendo, user: asignada)
    end
  end

  # `close?` sólo tiene sentido sobre un desafío en curso; el resto se
  # pregunta sobre el borrador, que es donde casi todas están vivas.
  def desafio_de(puerta) = puerta == :close? ? corriendo : borrador

  def responde?(persona, clase, puerta)
    as_company(company) do
      membresia = Membership.find_by!(user_id: persona.id)
      desafio = desafio_de(puerta).reload
      objetivo = clase == ChallengeStepPolicy ? desafio.steps.first : desafio

      clase.new(membresia, objetivo).public_send(puerta)
    end
  end

  # Variable local y no constante: un `PUERTAS = …` adentro del bloque de
  # `describe` se define sobre Object y se filtra a toda la suite.
  puertas = {
    ChallengePolicy => %i[builder? start? close? update_pipeline? curate_pool?],
    ChallengeStepPolicy => %i[advance? skip? manage_form? manage_criteria?
                              manage_assignments? report?]
  }

  puertas.each do |clase, lista|
    lista.each do |puerta|
      describe "#{clase}##{puerta}" do
        # El control: sin esto, un `false` parejo para los tres haría pasar la
        # fila entera sin que nadie pueda nada.
        it "la abre quien administra la empresa" do
          expect(responde?(admin, clase, puerta)).to be(true)
        end

        it "la abre el gestor al que le asignaron el desafío" do
          expect(responde?(asignada, clase, puerta)).to be(true)
        end

        it "se la niega al gestor al que no se lo asignaron" do
          expect(responde?(ajena, clase, puerta)).to be(false)
        end
      end
    end
  end
end
```

- [ ] **Paso 2: Correr y verificar que falla**

Correr: `make spec-file FILE=spec/policies/gestor_administra_spec.rb`
Esperado: FALLA. Las 11 filas de «la abre el gestor al que le asignaron»
fallan con `expected true, got false`. Las de admin y las de la gestora no
asignada ya pasan.

- [ ] **Paso 3: Escribir el predicado**

En `app/policies/application_policy.rb`, dentro del bloque `private`, justo
después de `reaches_challenge?`:

```ruby
  # Administrar ESTE desafío: quien administra la empresa, y el gestor al que
  # se lo asignaron.
  #
  # `manager?` se queda significando «administra la empresa», y es lo que
  # protege lo que no cuelga de ningún desafío: la gente, la biblioteca de
  # criterios y la auditoría de IA. De rebote, una puerta nueva escrita con
  # `manager?` nace cerrada para el gestor, que es el lado seguro.
  #
  # El desafío llega por cadenas opcionales (`record.challenge_step&.challenge`),
  # así que tiene que aceptar `nil` sin reventar: para un gestor eso es `false`
  # y un admin ya salió antes por `manager?`.
  def administra?(challenge)
    manager? || (membership.present? && membership.gestor? && reaches_challenge?(challenge))
  end
```

- [ ] **Paso 4: Abrir las puertas del desafío**

En `app/policies/challenge_policy.rb`, reemplazar los cinco predicados:

```ruby
  # Cualquiera de la empresa ve los desafíos; los arma quien los administra
  # —quien administra la empresa, y el gestor al que se lo asignaron—.
  def builder? = administra?(record)
  def start?   = administra?(record) && record.draft?
  def close?   = administra?(record) && record.running?

  # El pipeline solo se edita libremente en borrador; una vez arrancado, la
  # regla del insertion floor limita qué se puede tocar (Flow::Pipeline).
  def update_pipeline? = administra?(record) && !record.closed? && !record.archived?

  # Mirar el pool entero de ideas para decidir qué se fusiona o se descarta
  # —hoy, detectar duplicados—.
  #
  # Quien participa no: la comparación devuelve títulos y resúmenes de ideas
  # ajenas, y quien participa ve sólo las suyas. Quien evalúa tampoco: puntúa
  # lo que se le asigna, no decide qué se fusiona. Y no mira si hay una ronda
  # de evolución abierta, porque comparar no edita ninguna idea.
  def curate_pool? = administra?(record)
```

- [ ] **Paso 5: Abrir las puertas del módulo**

En `app/policies/challenge_step_policy.rb`, reemplazar los seis predicados
(dejando `configure?` como está — delega en `update_pipeline?` y se abre solo):

```ruby
  # Avanzar el flujo o saltear un módulo: quien administra ese desafío.
  def advance? = administra?(record&.challenge)
  def skip? = administra?(record&.challenge)

  # Reescribir la configuración de un módulo, que es más que ajustarlo en
  # curso: `update_pipeline?` suma `&& !closed? && !archived?`. Con el desafío
  # cerrado, cambiar el modo de IA sigue siendo legítimo —es política
  # operativa— y reescribir el corte no.
  def configure? = ChallengePolicy.new(membership, record.challenge).update_pipeline?

  # Editar el formulario de postulación.
  def manage_form? = administra?(record&.challenge)
  def manage_criteria? = administra?(record&.challenge)

  # Quién evalúa y cuánto pesa su voto: es política del desafío, no del
  # módulo. Un evaluador no se asigna solo ni se sube el peso.
  def manage_assignments? = administra?(record&.challenge)

  # El reporte incluye el ranking con los puntajes de todas las ideas: es
  # justo lo que un participante no ve en pantalla.
  def report? = administra?(record&.challenge)
```

- [ ] **Paso 6: Correr la tabla y verificar que pasa**

Correr: `make spec-file FILE=spec/policies/gestor_administra_spec.rb`
Esperado: PASA, 33 ejemplos.

- [ ] **Paso 7: Dar vuelta los dos ejemplos que afirmaban lo contrario**

En `spec/requests/gestor_spec.rb`, reemplazar el ejemplo «ni configura el
flujo» (está alrededor de la línea 172, dentro de `describe "lo que sí puede
hacer"`):

```ruby
    # Era al revés: el gestor no configuraba nada. Desde que administra los
    # desafíos que le asignaron, el builder es suyo.
    it "y configura el flujo del desafío que le asignaron" do
      get builder_challenge_path(acompanado)
      expect(response).to have_http_status(:ok)
    end

    it "pero no el del desafío que no le asignaron" do
      get builder_challenge_path(otro_de_demo)
      expect(response).to have_http_status(:not_found)
    end

    # Pedir y aceptar son el MISMO método (`AiSuggestionPolicy#request?` es
    # `accept?`) y los dos caen en `update_pipeline?`. Se prueban los dos
    # igual: divergieron dos veces mientras la tabla estuvo copiada en los dos
    # lados, y un ejemplo solo no lo habría visto.
    it "y acepta lo que la IA propuso para el flujo" do
      sugerencia = as_company(demo) do
        Flow::AI::Runner.call(
          Flow::AI::Tasks::ProposePipeline.new(challenge: acompanado),
          mode: "ai_assisted", challenge: acompanado
        ).suggestion
      end

      post accept_ai_suggestion_path(sugerencia)

      expect(as_company(demo) { sugerencia.reload }).to be_accepted
    end
```

Y el ejemplo «pero no puede pedirle que arme el flujo» (al final del archivo,
alrededor de la línea 380):

```ruby
    # También era al revés. `AiSuggestionPolicy#accept?` cae en
    # `update_pipeline?` para las tareas de alcance `:challenge`, así que esto
    # se abrió solo al abrir la policy: por eso tiene ejemplo propio.
    it "y puede pedirle que arme el flujo" do
      expect do
        post challenge_ai_requests_path(acompanado, purpose: "propose_pipeline")
      end.to change { as_company(demo) { AiRun.count } }.by(1)
    end
```

- [ ] **Paso 8: Correr el spec del gestor**

Correr: `make spec-file FILE=spec/requests/gestor_spec.rb`
Esperado: PASA. Si falla «pero no con la ronda cerrada», dejalo: lo arregla la
Tarea 2. Cualquier otra falla se resuelve acá.

- [ ] **Paso 9: Correr la suite entera**

Correr: `make spec`
Esperado: 0 fallas, salvo las que vengan de `IdeaPolicy` / `AssessmentPolicy` /
`FeedbackItemPolicy`, que son de la Tarea 2. Anotá cuáles son y seguí; no
arregles nada de esas tres policies acá.

- [ ] **Paso 10: Commit**

```bash
git add app/policies/application_policy.rb app/policies/challenge_policy.rb \
        app/policies/challenge_step_policy.rb spec/policies/gestor_administra_spec.rb \
        spec/requests/gestor_spec.rb
git commit -m "El gestor administra el desafío que le asignaron

`administra?(challenge)` generaliza la expresión que `curate_pool?` ya tenía
escrita a mano: quien administra la empresa, y el gestor al que le asignaron
ESE desafío. `manager?` se queda para lo que no cuelga de ningún desafío, así
que una puerta nueva que lo escriba nace cerrada.

Se abren las cinco del desafío y las seis del módulo. `configure?` y pedirle a
la IA que arme el flujo se abrieron solos, por delegación: por eso tienen
ejemplo propio.

La tabla de spec/policies/gestor_administra_spec.rb existe porque abrir un
permiso de más no rompe ningún test. Pregunta siempre por el gestor NO
asignado, que es el sujeto donde el error se ve."
```

---

### Tarea 2: Las puertas sobre ideas, evaluaciones y feedback

**Archivos:**
- Modificar: `app/policies/idea_policy.rb:38-68`
- Modificar: `app/policies/assessment_policy.rb:8-30`
- Modificar: `app/policies/feedback_item_policy.rb:22-31`
- Modificar: `spec/policies/gestor_administra_spec.rb` (filas nuevas)
- Modificar: `spec/requests/gestor_spec.rb` (un ejemplo)

**Interfaces:**
- Consume: `ApplicationPolicy#administra?(challenge)` de la Tarea 1.
- Produce: nada que otra tarea use.

- [ ] **Paso 1: Escribir las filas que fallan**

En `spec/policies/gestor_administra_spec.rb`, agregar al final, **dentro** del
`RSpec.describe`:

```ruby
  describe "sobre una idea, una evaluación y un comentario" do
    let!(:autora) { usuario(:participant, "autora@test.dev") }

    let!(:idea) do
      as_company(company) do
        i = create(:idea, challenge: borrador, author: autora)
        Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" },
                                        author: autora).call
        i.update!(submitted_at: Time.current)
        i.reload
      end
    end

    def puede?(persona)
      as_company(company) do
        membresia = Membership.find_by!(user_id: persona.id)
        yield(membresia)
      end
    end

    # Editar una idea postulada SIN ronda de evolución abierta: era la ventana
    # que acotaba al gestor y ahora no lo acota.
    it "editar la idea: la abre quien administra" do
      expect(puede?(admin) { |m| IdeaPolicy.new(m, idea).update? }).to be(true)
    end

    it "editar la idea: la abre el gestor asignado, sin ronda abierta" do
      expect(puede?(asignada) { |m| IdeaPolicy.new(m, idea).update? }).to be(true)
    end

    it "editar la idea: se la niega al gestor no asignado" do
      expect(puede?(ajena) { |m| IdeaPolicy.new(m, idea).update? }).to be(false)
    end

    # La exclusión que NO se toca: postular es del autor. `submit?` es
    # `update? && !acompana?`, así que sigue cerrado aunque `update?` se abra.
    it "postular por el autor: sigue cerrado para el gestor asignado" do
      expect(puede?(asignada) { |m| IdeaPolicy.new(m, idea).submit? }).to be(false)
    end

    it "postular ideas propias: sigue cerrado para el gestor asignado" do
      expect(puede?(asignada) { |m| IdeaPolicy.new(m, Idea.new(challenge: borrador)).create? })
        .to be(false)
    end

    it "borrar la idea: la abre el gestor asignado" do
      expect(puede?(asignada) { |m| IdeaPolicy.new(m, idea).destroy? }).to be(true)
    end

    it "borrar la idea: se la niega al gestor no asignado" do
      expect(puede?(ajena) { |m| IdeaPolicy.new(m, idea).destroy? }).to be(false)
    end

    describe "evaluar sin asignación" do
      let!(:evaluacion) do
        as_company(company) { borrador.steps.create!(kind: "evaluation", position: 2) }
      end

      def evalua?(persona, sobre: nil)
        puede?(persona) do |m|
          AssessmentPolicy.new(m, Assessment.new(challenge_step: evaluacion, idea: sobre)).create?
        end
      end

      it "la abre quien administra" do
        expect(evalua?(admin)).to be(true)
      end

      it "la abre el gestor asignado, sin estar asignado al módulo" do
        expect(evalua?(asignada)).to be(true)
      end

      it "se la niega al gestor no asignado" do
        expect(evalua?(ajena)).to be(false)
      end

      # El orden de `create?` no se toca: primero llegar al desafío, después el
      # conflicto de interés, y recién ahí el rol. Si `administra?` se pone
      # antes, quien administra vuelve a poder puntuarse a sí mismo.
      it "y nadie puntúa una idea de la que participa, ni quien administra" do
        propia = as_company(company) { create(:idea, challenge: borrador, author: admin) }
        expect(evalua?(admin, sobre: propia)).to be(false)
      end
    end

    it "cerrar un comentario: la abre el gestor asignado" do
      comentario = as_company(company) do
        FeedbackItem.new(idea: idea, challenge_step: borrador.steps.first)
      end
      expect(puede?(asignada) { |m| FeedbackItemPolicy.new(m, comentario).resolve? }).to be(true)
    end

    it "cerrar un comentario: se la niega al gestor no asignado" do
      comentario = as_company(company) do
        FeedbackItem.new(idea: idea, challenge_step: borrador.steps.first)
      end
      expect(puede?(ajena) { |m| FeedbackItemPolicy.new(m, comentario).resolve? }).to be(false)
    end
  end
```

- [ ] **Paso 2: Correr y verificar que falla**

Correr: `make spec-file FILE=spec/policies/gestor_administra_spec.rb`
Esperado: FALLA en «editar la idea: la abre el gestor asignado, sin ronda
abierta», «borrar la idea: la abre el gestor asignado» y «evaluar: la abre el
gestor asignado». Los de admin y los de la gestora no asignada ya pasan.

- [ ] **Paso 3: Abrir `IdeaPolicy` y borrar la rama muerta**

En `app/policies/idea_policy.rb`, reemplazar `update?` y `destroy?`:

```ruby
  # Editar = publicar una versión nueva.
  #
  # El autor puede mientras la idea sigue en borrador, y también cuando hay un
  # módulo de EVOLUCIÓN abierto: responder al feedback actualizando la idea es
  # exactamente para lo que existe ese módulo. Fuera de esos dos momentos, una
  # idea postulada no se edita en caliente.
  #
  # Quien administra ese desafío no tiene esa ventana: es la misma llave que
  # abre todo lo demás del desafío. La rama propia que tenía el gestor —sólo
  # con la ronda abierta— desapareció acá, pero `acompana?` se queda: lo usa
  # `submit?`, que es la exclusión que NO cambió.
  def update?
    return false if record.nil?
    return true if administra?(record.challenge)

    # Participar es haberla creado o colaborar en ella, y son las dos formas
    # de trabajarla: quien colabora la ve —esa es la regla de visibilidad— y
    # no poder tocarla la dejaba a medias.
    return false unless record.participates?(membership&.user)

    record.draft? || evolution_open?
  end
```

y

```ruby
  def destroy? = administra?(record.challenge) || (record.author_id == membership.user_id && record.draft?)
```

`create?`, `submit?`, `manage_contributors?` y el privado `acompana?` **no se
tocan**.

- [ ] **Paso 4: Abrir `AssessmentPolicy` sin mover el orden**

En `app/policies/assessment_policy.rb`, reemplazar las dos líneas
`return true if manager?` por `administra?`, **sin cambiar el orden de las
guardas**:

```ruby
  def create?
    return false if membership.nil?
    # Llegar al desafío, que un gestor sólo hace con los que le asignaron. Los
    # controllers de evaluar ya lo filtraban con `policy_scope(Challenge)`,
    # pero aceptar una propuesta de evaluación de la IA pregunta esto sin pasar
    # por ningún scope, y una asignación que sobrevivió a la baja del gestor
    # alcanzaba para escribir una evaluación sobre un desafío que le da 404.
    return false unless reaches_challenge?(record.challenge_step&.challenge)
    return false if record.idea&.participates?(membership.user)
    return true if administra?(record.challenge_step&.challenge)

    record.challenge_step.step_assignments.exists?(user_id: membership.user_id)
  end

  def update?
    return false if record.nil?
    return true if administra?(record.challenge_step&.challenge)

    record.evaluator_id == membership.user_id && !record.submitted?
  end
```

El `reaches_challenge?` de arriba queda redundante para el gestor y se deja: es
la guarda que hace que lo no asignado dé 404 y no 403, y sacarla por
«redundante» la rompe para el resto de los roles.

- [ ] **Paso 5: Abrir `FeedbackItemPolicy` y borrar su rama muerta**

En `app/policies/feedback_item_policy.rb`, reemplazar `resolve?`:

```ruby
  # Cerrar un comentario: quien administra ese desafío o el autor de la idea.
  # Quien lo escribió no decide solo si quedó atendido.
  #
  # La rama propia del gestor se fue: `administra?` la cubre entera.
  def resolve?
    return false if membership.nil?
    return true if administra?(record.idea.challenge)

    record.idea.participates?(membership.user)
  end
```

`create?` **no se toca**: el gestor ya estaba adentro por su propia cláusula.

- [ ] **Paso 6: Correr la tabla y verificar que pasa**

Correr: `make spec-file FILE=spec/policies/gestor_administra_spec.rb`
Esperado: PASA, con las filas nuevas en verde.

- [ ] **Paso 7: Dar vuelta el ejemplo de la ronda cerrada**

En `spec/requests/gestor_spec.rb`, reemplazar «pero no con la ronda cerrada»
(alrededor de la línea 355):

```ruby
    # Era la ventana que acotaba al gestor: sólo con la ronda abierta. Desde
    # que administra el desafío, trabajar la idea no depende de que haya una
    # ronda en curso.
    it "y también con la ronda cerrada" do
      as_company(demo) { evolucion.reload.update!(status: "completed", completed_at: Time.current) }

      expect do
        post challenge_ai_requests_path(acompanado, purpose: "evolve_idea",
                                        step_id: evolucion.id, idea_id: idea.id)
      end.to change { as_company(demo) { AiRun.count } }.by(1)
    end
```

- [ ] **Paso 8: Correr la suite entera**

Correr: `make spec`
Esperado: 0 fallas. Si aparece alguna en `pantalla_del_modulo_spec.rb`,
`dos_caras_spec.rb`, `duplicados_spec.rb`, `evaluator_rules_spec.rb`,
`ideas_spec.rb` o `participant_rules_spec.rb`, arreglala acá: son el coletazo
de estas tres policies. **Si una falla dice que un participante o un evaluador
ganó algo, es un bug de este plan, no un spec desactualizado — pará y decilo.**

- [ ] **Paso 9: Commit**

```bash
git add app/policies/idea_policy.rb app/policies/assessment_policy.rb \
        app/policies/feedback_item_policy.rb spec/policies/gestor_administra_spec.rb \
        spec/requests/gestor_spec.rb
git commit -m "El gestor trabaja las ideas de su desafío sin esperar la ronda

Editar una idea, borrarla, evaluar y cerrar un comentario pasan a `administra?`.
Con eso desaparecen dos ramas que el gestor tenía para sí: la ventana de
evolución en IdeaPolicy#update? y la línea propia de resolve?. El privado
`acompana?` se queda, porque `submit?` lo sigue usando: postular por el autor
sigue cerrado, y tiene ejemplo propio por eso.

El orden de AssessmentPolicy#create? no se movió. Primero llegar al desafío,
después el conflicto de interés, y recién ahí el rol: al revés, quien
administra vuelve a poder puntuarse a sí mismo."
```

---

### Tarea 3: Los sets `inline` y el botón que hay que esconder

**Archivos:**
- Modificar: `app/policies/criteria_set_policy.rb`
- Modificar: `app/views/steps/_criterios_editor.html.haml:102`
- Modificar: `spec/policies/gestor_administra_spec.rb` (filas nuevas)
- Modificar: `spec/requests/gestor_spec.rb` (dos ejemplos nuevos)

**Interfaces:**
- Consume: `ApplicationPolicy#administra?(challenge)` de la Tarea 1.

**Por qué esta tarea existe:** con `configure?` abierto (Tarea 1) el gestor ve
el editor de criterios de su módulo, pero `CriteriaSetPolicy` hereda
`create?/update? = manager?`. Sin esta tarea vería el editor y **no podría
guardar** — el control fantasma que esta app viene persiguiendo.

- [ ] **Paso 1: Escribir las filas que fallan**

En `spec/policies/gestor_administra_spec.rb`, agregar al final, dentro del
`RSpec.describe`:

```ruby
  describe "los criterios" do
    let!(:propio) do
      as_company(company) do
        modulo = borrador.steps.first
        CriteriaSet.create!(name: "Los del módulo", scope: "inline", owner_step: modulo)
      end
    end

    let!(:de_biblioteca) do
      as_company(company) { CriteriaSet.create!(name: "Compartidos", scope: "library") }
    end

    def guarda?(persona, set)
      as_company(company) do
        membresia = Membership.find_by!(user_id: persona.id)
        CriteriaSetPolicy.new(membresia, set.reload).update?
      end
    end

    it "el set propio del módulo: lo guarda quien administra" do
      expect(guarda?(admin, propio)).to be(true)
    end

    it "el set propio del módulo: lo guarda el gestor asignado" do
      expect(guarda?(asignada, propio)).to be(true)
    end

    it "el set propio del módulo: no el gestor no asignado" do
      expect(guarda?(ajena, propio)).to be(false)
    end

    # La biblioteca es de la empresa: se comparte con desafíos que el gestor
    # no ve, así que no la escribe ni el asignado.
    it "la biblioteca: la guarda quien administra" do
      expect(guarda?(admin, de_biblioteca)).to be(true)
    end

    it "la biblioteca: no la guarda el gestor asignado" do
      expect(guarda?(asignada, de_biblioteca)).to be(false)
    end

    it "ni la crea" do
      nuevo = as_company(company) { CriteriaSet.new(scope: "library") }
      creado = as_company(company) do
        membresia = Membership.find_by!(user_id: asignada.id)
        CriteriaSetPolicy.new(membresia, nuevo).create?
      end
      expect(creado).to be(false)
    end
  end
```

- [ ] **Paso 2: Correr y verificar que falla**

Correr: `make spec-file FILE=spec/policies/gestor_administra_spec.rb`
Esperado: FALLA en «el set propio del módulo: lo guarda el gestor asignado».

- [ ] **Paso 3: Escribir la policy**

En `app/policies/criteria_set_policy.rb`, agregar los tres predicados
**después** del bloque `class Scope … end` que ya está:

```ruby
  # Un set `inline` es de UN módulo: lo guarda quien administra ese desafío, y
  # desde que el gestor administra los suyos, también él. Sin esto el editor de
  # criterios se le renderiza por `configure?` y el guardado le rebota: el
  # control fantasma de siempre.
  #
  # Un set `library` se comparte entre TODOS los desafíos de la empresa,
  # incluidos los que el gestor no ve, así que sigue siendo de quien administra
  # la empresa.
  def update?
    return manager? if record.library?

    administra?(record.owner_step&.challenge)
  end

  # Un set nace de biblioteca: lo crea el editor (`scope: "library"`) o el
  # botón de promover, que copia uno `inline` a la biblioteca. Las dos cosas
  # escriben patrimonio común.
  def create? = manager?

  # Borrar es una acción de las pantallas de biblioteca; un set `inline` se va
  # solo con su módulo.
  def destroy? = manager?
```

- [ ] **Paso 4: Correr y verificar que pasa**

Correr: `make spec-file FILE=spec/policies/gestor_administra_spec.rb`
Esperado: PASA.

- [ ] **Paso 5: Probar el guardado de verdad, por la API**

La fila de policy prueba el predicado; esto prueba que el camino entero
responde. Es el único camino de escritura del editor de criterios.

En `spec/requests/gestor_spec.rb`, agregar un `describe` nuevo antes del `end`
que cierra el `RSpec.describe`:

```ruby
  describe "los criterios de su módulo" do
    before { sign_in(gina, company: demo) }

    def criterion_params(**overrides)
      { id: nil, name: "Impacto", description: nil, weight: 100,
        source: "manual", scale_type: "numeric",
        source_config: {}, scale_config: { min: 1, max: 10, step: 1, direction: "higher_better" },
        active: true }.merge(overrides)
    end

    it "los guarda por la API, que es el único camino de escritura del editor" do
      set = as_company(demo) do
        modulo = acompanado.steps.reload.first
        CriteriaSet.create!(name: "Los del módulo", scope: "inline", owner_step: modulo)
      end

      put api_v1_criteria_set_path(set), params: {
        name: "Los del módulo", criteria: [criterion_params]
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(as_company(demo) { set.reload.criteria.count }).to eq(1)
    end

    it "pero no crea uno de biblioteca, que se comparte con desafíos que no ve" do
      expect do
        post api_v1_criteria_sets_path, params: {
          name: "Compartidos", criteria: [criterion_params]
        }, as: :json
      end.not_to change { as_company(demo) { CriteriaSet.where(scope: "library").count } }
    end
  end
```

Correr: `make spec-file FILE=spec/requests/gestor_spec.rb`
Esperado: PASA. Si el primero da 403, la policy del Paso 3 no está llegando —
revisá que `record.owner_step` no venga `nil` fuera del bloque de tenencia.

- [ ] **Paso 6: Esconder el botón de promover**

En `app/views/steps/_criterios_editor.html.haml`, reemplazar el bloque del
aviso (alrededor de la línea 99):

```haml
      - else
        .alert.alert-soft.alert-success
          %div
            Estos criterios son de este módulo: no afectan a otros desafíos.
            -# La biblioteca es de la empresa: promover escribe ahí, así que el
            -# link pregunta por quién puede escribirla y no por `configure?`,
            -# que es lo que abre esta tarjeta. Sin esto el gestor ve un botón
            -# que le rebota con 403.
            - if policy(CriteriaSet).create?
              = link_to "Guardarlos también en la biblioteca", promote_criteria_set_path(set),
                        data: { turbo_method: :post }, class: "field-hint__link"
```

- [ ] **Paso 7: Verificar que el botón se esconde y el editor sigue**

Correr: `make spec-file FILE=spec/requests/step_criteria_spec.rb`
Esperado: PASA. Si algún ejemplo esperaba el texto «Guardarlos también en la
biblioteca» con un sujeto que no es admin, dalo vuelta acá.

- [ ] **Paso 8: Correr la suite entera**

Correr: `make spec`
Esperado: 0 fallas.

- [ ] **Paso 9: Commit**

```bash
git add app/policies/criteria_set_policy.rb app/views/steps/_criterios_editor.html.haml \
        spec/policies/gestor_administra_spec.rb spec/requests/gestor_spec.rb
git commit -m "El gestor guarda los criterios propios de su módulo

CriteriaSetPolicy no tenía nada propio salvo su Scope, así que heredaba
create?/update? = manager?. Con `configure?` ya abierto, el gestor veía el
editor de criterios y el guardado le rebotaba.

Un set `inline` es de un módulo y lo guarda quien administra ese desafío. La
biblioteca se comparte con desafíos que el gestor no ve, así que sigue siendo
de quien administra la empresa — y por eso el botón de promover pasa a
preguntar por `CriteriaSetPolicy#create?` y no por `configure?`, que es lo que
abre la tarjeta donde vive."
```

---

### Tarea 4: Crear un desafío, y quedar asignado a él

**Archivos:**
- Modificar: `app/policies/challenge_policy.rb` (agregar `create?`)
- Modificar: `app/controllers/challenges_controller.rb:17-28`
- Modificar: `spec/policies/gestor_administra_spec.rb` (filas nuevas)
- Modificar: `spec/requests/gestor_spec.rb` (ejemplo nuevo)

**Interfaces:**
- Consume: nada de tareas anteriores. `create?` **no** usa `administra?`: el
  desafío todavía no existe, así que nadie puede estar asignado a él.

- [ ] **Paso 1: Escribir el request spec que falla**

En `spec/requests/gestor_spec.rb`, agregar un `describe` nuevo al final del
archivo, antes del `end` que cierra el `RSpec.describe`:

```ruby
  # Crear es la única puerta que no puede preguntar por la asignación: el
  # desafío todavía no existe. Por eso se auto-asigna al crearlo — si no, lo
  # crea y desaparece de su lista en el mismo movimiento, porque el Scope
  # filtra por `challenge_gestores`.
  describe "creando un desafío" do
    before { sign_in(gina, company: demo) }

    it "puede, y queda acompañándolo" do
      expect do
        post challenges_path, params: { challenge: { name: "Nuevo", brief: "Probar." } }
      end.to change { as_company(demo) { Challenge.count } }.by(1)

      creado = as_company(demo) { Challenge.order(:created_at).last }
      asignados = as_company(demo) { creado.challenge_gestores.pluck(:user_id) }

      expect(asignados).to include(gina.id)
    end

    it "y lo sigue viendo en el índice" do
      post challenges_path, params: { challenge: { name: "Nuevo", brief: "Probar." } }

      get challenges_path

      expect(response.body).to include("Nuevo")
    end
  end
```

- [ ] **Paso 2: Correr y verificar que falla**

Correr: `make spec-file FILE=spec/requests/gestor_spec.rb`
Esperado: FALLA — el POST no crea nada, porque `create?` todavía es `manager?`.

- [ ] **Paso 3: Abrir `create?`**

En `app/policies/challenge_policy.rb`, agregar junto a los demás predicados:

```ruby
  # Crear no puede preguntar por la asignación —el desafío todavía no existe—,
  # así que alcanza con ser gestor de la empresa. Lo que lo acota es que
  # `ChallengesController#create` lo asigna al desafío que acaba de crear: sin
  # eso lo crearía y desaparecería de su lista en el mismo movimiento.
  def create? = manager? || (membership.present? && membership.gestor?)
```

- [ ] **Paso 4: Auto-asignar al crear**

En `app/controllers/challenges_controller.rb`, reemplazar `create`:

```ruby
  def create
    @challenge = Challenge.new(challenge_params)
    authorize @challenge

    guardado = ActiveRecord::Base.transaction do
      next false unless @challenge.save

      # Quien administra la empresa ve todos los desafíos; el gestor sólo los
      # que tiene asignados, así que el que acaba de crear tiene que quedar
      # entre ellos o lo pierde apenas lo crea. Va en la misma transacción: un
      # desafío que el gestor no ve es peor que no haberlo creado.
      @challenge.challenge_gestores.create!(user: current_user) if current_membership.gestor?
      true
    end

    return render(:new, status: :unprocessable_content) unless guardado
    return proponer_flujo_con_ia if params[:template] == "ai"

    redirect_to builder_challenge_path(@challenge), notice: start_from(params[:template])
  end
```

- [ ] **Paso 5: Correr y verificar que pasa**

Correr: `make spec-file FILE=spec/requests/gestor_spec.rb`
Esperado: PASA.

- [ ] **Paso 6: Sumar la fila a la tabla**

En `spec/policies/gestor_administra_spec.rb`, agregar dentro del
`RSpec.describe`:

```ruby
  describe "create? del desafío" do
    def crea?(persona)
      as_company(company) do
        membresia = Membership.find_by!(user_id: persona.id)
        ChallengePolicy.new(membresia, Challenge.new).create?
      end
    end

    it "la abre quien administra" do
      expect(crea?(admin)).to be(true)
    end

    # Ojo: acá el gestor NO asignado también puede, y está bien. Es la única
    # puerta que no pregunta por la asignación, porque el desafío todavía no
    # existe; lo que la acota es la auto-asignación del controller.
    it "la abre cualquier gestor de la empresa" do
      expect(crea?(ajena)).to be(true)
    end

    it "y no quien participa" do
      participa = usuario(:participant, "participa@test.dev")
      expect(crea?(participa)).to be(false)
    end
  end
```

- [ ] **Paso 7: Correr la suite entera**

Correr: `make spec`
Esperado: 0 fallas. Prestá atención a `spec/requests/challenges_spec.rb`: la
transacción nueva cambia el camino del `save` fallido.

- [ ] **Paso 8: Commit**

```bash
git add app/policies/challenge_policy.rb app/controllers/challenges_controller.rb \
        spec/policies/gestor_administra_spec.rb spec/requests/gestor_spec.rb
git commit -m "El gestor crea desafíos, y queda acompañando el que crea

`create?` es la única puerta que no puede preguntar por la asignación: el
desafío todavía no existe. Lo que la acota es el controller, que le crea su
ChallengeGestor en la misma transacción que el save — sin eso lo crearía y
desaparecería de su lista en el mismo movimiento, porque el Scope filtra por
challenge_gestores."
```

---

### Tarea 5: Nadie se saca a sí mismo

**Archivos:**
- Modificar: `app/controllers/challenge_gestores_controller.rb:25-31`
- Modificar: `spec/requests/gestor_spec.rb` (dos ejemplos nuevos)

**Interfaces:**
- Consume: `update_pipeline?` abierto en la Tarea 1.

- [ ] **Paso 1: Escribir los ejemplos que fallan**

En `spec/requests/gestor_spec.rb`, dentro del `describe "asignar gestores"` que
ya existe (alrededor de la línea 202), agregar:

```ruby
    # Con `update_pipeline?` abierto, el gestor administra quién acompaña su
    # desafío. Sacarse a sí mismo lo deja afuera en el acto, sin forma de
    # volver salvo que un admin lo reasigne.
    it "el gestor no se saca a sí mismo" do
      sign_in(gina, company: demo)
      asignacion = as_company(demo) { acompanado.challenge_gestores.find_by!(user_id: gina.id) }

      delete challenge_gestor_path(acompanado, asignacion)

      expect(as_company(demo) { ChallengeGestor.exists?(asignacion.id) }).to be(true)
    end

    it "pero sí saca a otro, que es parte de administrar el desafío" do
      otra_gestora = without_tenant do
        u = create(:user, email: "otra@test.dev")
        create(:membership, :gestor, company: demo, user: u)
        u
      end
      asignacion = as_company(demo) do
        ChallengeGestor.create!(challenge: acompanado, user: otra_gestora)
      end

      sign_in(gina, company: demo)
      delete challenge_gestor_path(acompanado, asignacion)

      expect(as_company(demo) { ChallengeGestor.exists?(asignacion.id) }).to be(false)
    end
```

- [ ] **Paso 2: Correr y verificar que falla**

Correr: `make spec-file FILE=spec/requests/gestor_spec.rb`
Esperado: FALLA «el gestor no se saca a sí mismo» — hoy se saca.

- [ ] **Paso 3: Escribir la guarda**

En `app/controllers/challenge_gestores_controller.rb`, reemplazar `destroy`:

```ruby
  def destroy
    authorize @challenge, :update_pipeline?

    asignacion = @challenge.challenge_gestores.find(params[:id])

    # Sacarse a uno mismo deja afuera en el acto y sin vuelta: el Scope filtra
    # por esta tabla, así que después del redirect el desafío ya da 404 y sólo
    # un admin puede reasignar. Sacar a OTRO sigue permitido — es parte de
    # administrar el desafío. Quien administra la empresa no puede caer acá:
    # `user_must_be_gestor` impide que esté en la tabla.
    if asignacion.user_id == current_user.id
      return volver alert: "No podés dejar de acompañar un desafío vos mismo."
    end

    asignacion.destroy!
    volver notice: "Ya no acompaña este desafío."
  end
```

- [ ] **Paso 4: Correr y verificar que pasa**

Correr: `make spec-file FILE=spec/requests/gestor_spec.rb`
Esperado: PASA.

- [ ] **Paso 5: Correr la suite entera**

Correr: `make spec`
Esperado: 0 fallas.

- [ ] **Paso 6: Commit**

```bash
git add app/controllers/challenge_gestores_controller.rb spec/requests/gestor_spec.rb
git commit -m "Nadie deja de acompañar un desafío por su propia mano

Con `update_pipeline?` abierto, el gestor administra quién acompaña su desafío.
Sacarse a sí mismo lo deja afuera en el acto: el Scope filtra por esa tabla, y
después del redirect el desafío ya le da 404. Sacar a otro sigue permitido.

Quien administra la empresa no puede caer en el caso: `user_must_be_gestor`
impide que esté en la tabla."
```

---

### Tarea 6: Barrer la suite y el recorrido

**Archivos:**
- Modificar: los specs que hayan quedado desactualizados (se descubren
  corriendo, no se adivinan)
- Modificar: `CLAUDE.md` (la sección «Los cuatro roles»)

- [ ] **Paso 1: Correr la suite entera y leerla**

Correr: `make spec`
Esperado: 0 fallas. Si hay alguna, arreglala **dando vuelta la afirmación con
su motivo nuevo**, no borrando el ejemplo.

- [ ] **Paso 2: Revisar a mano los specs que nombran al gestor**

Correr: `grep -rln "gestor" spec/`
Para cada archivo de la lista, leer los ejemplos y preguntarse si lo que
afirman sigue siendo cierto **por el motivo que dice el comentario**. Un
ejemplo puede pasar por la razón equivocada: `pantalla_del_modulo_spec.rb`
enumera bloques por rol, y un bloque que ahora se le muestra al gestor tiene
que estar en la lista de lo que ve, no pasar de casualidad.

- [ ] **Paso 3: Verificar que el gestor no ganó lo que no debía**

Correr:
```bash
make spec-file FILE=spec/requests/memberships_spec.rb
make spec-file FILE=spec/requests/participant_rules_spec.rb
make spec-file FILE=spec/requests/evaluator_rules_spec.rb
make spec-file FILE=spec/tenancy/sin_membresia_spec.rb
```
Esperado: PASA los cuatro. Son los que prueban que las otras tres puertas
—membresías, auditoría de IA, biblioteca— y los otros tres roles quedaron
donde estaban.

- [ ] **Paso 4: Correr el recorrido**

Correr: `make up && make screens`
Esperado: 66 capturas, 0 errores. Importa acá aunque no haya CSS de por medio:
el recorrido entra a las pantallas de módulo y falla con cualquier HTTP >= 400,
que es la forma exacta de un permiso mal repartido.

Si la base no tiene los desafíos sembrados, `make seed` antes.

- [ ] **Paso 5: Actualizar CLAUDE.md**

En la sección «Los cuatro roles», reemplazar la línea que describe al gestor y
agregar el párrafo del reparto. El texto actual dice «`gestor` acompaña la
evolución»; pasa a decir que administra los desafíos que le asignaron. Agregar
después de la lista de reglas:

```markdown
- **El gestor administra los desafíos que le asignaron.** Dentro de uno, puede
  lo mismo que quien administra la empresa: armarlo, arrancarlo, configurarlo,
  testear, avanzar, reportar, asignar, y trabajar sus ideas sin esperar una
  ronda de evolución. La regla es `ApplicationPolicy#administra?(challenge)`,
  que es `manager? || (gestor? && le asignaron ESE desafío)`.
  **`manager?` quedó significando «administra la empresa»** y es lo que protege
  lo que no cuelga de ningún desafío: las membresías, la auditoría de IA y la
  biblioteca de criterios. De rebote, una puerta nueva escrita con `manager?`
  nace cerrada para el gestor, que es el lado seguro; abrirla es una decisión
  que se toma, no un default.
  Dos cosas no se abrieron, y son de otro eje: **no postula ideas propias** ni
  **postula por el autor** (`IdeaPolicy#create?` y `#submit?`). Son conflicto
  de interés, no permisos. `submit?` es `update? && !acompana?`, así que sigue
  cerrado aunque `update?` se haya abierto — por eso `acompana?` se quedó
  aunque su otra rama murió.
  Y **crear** es la única puerta que no pregunta por la asignación: el desafío
  todavía no existe. Lo que la acota es que `ChallengesController#create`
  auto-asigna al gestor que lo crea, en la misma transacción que el `save`.
  El reparto entero se lee en `spec/policies/gestor_administra_spec.rb`, que
  existe porque **abrir un permiso de más no rompe ningún test**.
```

- [ ] **Paso 6: Commit**

```bash
git add -A
git commit -m "El reparto del gestor, anotado en CLAUDE.md

Lo que no se deduce leyendo las policies: que `manager?` pasó a significar
«administra la empresa» y por eso una puerta nueva nace cerrada para el gestor;
que las dos exclusiones que quedaron son conflicto de interés y no permisos; y
que crear es la única que no pregunta por la asignación porque el desafío
todavía no existe."
```

---

## Qué NO entra en este plan

- **Las membresías, la auditoría de IA y crear o editar sets de biblioteca.**
  Siguen en `manager?`, por decisión tomada en la spec.
- **`ChallengePolicy#update?` y `#destroy?`.** No se tocan porque no existen
  como ruta: `resources :challenges, only: %i[index new create show]`. Son
  código muerto.
- **La fuga preexistente de `/criteria_sets`.** `CriteriaSetPolicy::Scope`
  achica sólo para el gestor, así que un participante lista y abre los sets
  `inline` de desafíos que no ve. Está anotada en §5 de la spec y **merece rama
  propia**: meterla acá ensucia el diff de permisos.
- **Una guarda de lint que obligue a decidir cada `manager?` nuevo.** Sería el
  equivalente de `paridad_de_rotulos_spec.rb` para permisos. Vale la pena y no
  es de esta rama.
