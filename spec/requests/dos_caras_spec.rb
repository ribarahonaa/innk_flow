# frozen_string_literal: true

require "rails_helper"

# La pantalla de un módulo tiene dos caras y la decide `step.touched?`, no el
# estado del desafío: un desafío en curso sigue teniendo módulos pendientes
# más adelante, y ésos son configurables.
RSpec.describe "las dos caras de un módulo", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  let!(:admin) do
    without_tenant do
      u = create(:user, email: "admin@test.dev", name: "Ana Admin")
      create(:membership, :admin, company: company, user: u)
      u
    end
  end

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma", ai_default_mode: "human")
      seed_form!(c.steps.create!(kind: "ideation", position: 1))
      c.steps.create!(kind: "evaluation", position: 2, name: "Comité")
      c.steps.create!(kind: "selection", position: 3, name: "Corte")
      c.steps.create!(kind: "reporting", position: 4, name: "Informe")
      c.steps.create!(kind: "evolution", position: 5, name: "Mejorar")
      c.steps.create!(kind: "testing", position: 6, name: "Prueba")
      c
    end
  end

  def paso(kind) = as_company(company) { challenge.steps.reload.find { |s| s.kind == kind } }

  before { sign_in(admin, company: company) }

  describe "cara A: el módulo está pendiente" do
    it "monta la isla de ajustes en los seis kinds" do
      ChallengeStep::KINDS.each do |kind|
        get challenge_step_path(challenge, paso(kind))

        expect(response.body).to include('data-island="step-settings"'),
                                 "faltó la isla en #{kind}"
      end
    end

    it "trae el form del módulo, con nombre y modo de IA" do
      get challenge_step_path(challenge, paso("selection"))

      expect(response.body).to include('name="challenge_step[name]"')
      expect(response.body).to include('name="challenge_step[ai_mode]"')
    end

    # «Confirmar el corte» está detrás de `decidible = @step.active? &&
    # policy(@step).advance?`, así que un módulo pendiente nunca lo mostró, ni
    # antes de esta tarea: no probaba nada. «Cómo se decide» sí es exclusivo
    # de la cara de ejecución (`steps/selection.html.haml`) — la de
    # configuración no la renderiza.
    it "no muestra el trabajo del módulo, que todavía no existe" do
      get challenge_step_path(challenge, paso("selection"))

      expect(response.body).not_to include("Cómo se decide")
      expect(response.body).not_to include("Confirmar el corte")
    end

    # La cara de configuración se sirve sin ninguna policy propia:
    # `ChallengeStepPolicy#show?` es «cualquiera de la empresa», así que sin
    # esta guarda un participante o evaluador recibía el form entero —con el
    # botón «Guardar el módulo»— y el PATCH le rebotaba en 403 al enviarlo.
    it "sin `configure?` no ofrece el form, sólo la vista de sólo lectura" do
      participante = without_tenant do
        u = create(:user, email: "part@test.dev", name: "Paula Participante")
        create(:membership, company: company, user: u, role: "participant")
        u
      end
      sign_in(participante, company: company)

      get challenge_step_path(challenge, paso("selection"))

      expect(response.body).not_to include('name="challenge_step[name]"')
      expect(response.body).not_to include("Guardar el módulo")
      expect(response.body).to include("Cómo está configurado")
      # Mismo criterio que el form del módulo: sin `configure?`, el bloque de
      # criterios tampoco ofrece sus controles de edición.
      expect(response.body).not_to include("Usar los tres genéricos y editarlos")
      expect(response.body).not_to include("Proponer criterios con IA")
    end

    it "trae el editor de criterios en los dos kinds que puntúan o filtran" do
      %w[evaluation selection].each do |kind|
        get challenge_step_path(challenge, paso(kind))

        expect(response.body).to include("Criterios propios de este módulo")
          .or include("todavía no tiene criterios propios")
      end
    end

    # `challenge_criteria/show` (el índice borrado) era la única pantalla que
    # renderizaba `shared/setup_nav` con `current: :criteria`. Embeber los
    # criterios en `steps/config/evaluation` y `.../selection` sin sumar ese
    # render dejaba el paso a paso sin «siguiente →» ahí también — el mismo
    # agujero que ya se pagó una vez para el formulario (ver el test de abajo
    # sobre Idear). El desafío de arriba ya tiene flujo Y formulario, así que
    # su paso a paso está `ready?` y el pie ofrece «Arrancar» en vez de un
    # link con flecha — se prueba sobre un desafío SIN formulario todavía,
    # donde sigue habiendo algo pendiente antes de arrancar y el pie tiene que
    # decir a dónde seguir.
    #
    # Corre en LOS DOS kinds que embeben el bloque de criterios, no solo en
    # evaluación: son dos renders distintos, uno por vista, y una ronda previa
    # dejó `selection.html.haml` sin guarda porque el ejemplo solo pasaba por
    # `evaluation.html.haml`. El texto del pie es el mismo en los dos —
    # `after(:criteria)` da «Revisar» sin importar en cuál de los dos módulos
    # que puntúan estés parado—, así que un solo `it` cubre ambos con el mismo
    # desafío.
    it "el pie del paso a paso sigue ofreciendo el siguiente paso en los criterios" do
      sin_formulario = as_company(company) do
        c = create(:challenge, name: "Sin formulario todavía")
        c.steps.create!(kind: "ideation", position: 1)
        c.steps.create!(kind: "evaluation", position: 2, name: "Técnica")
        c.steps.create!(kind: "selection", position: 3, name: "Corte")
        c
      end

      %w[evaluation selection].each do |kind|
        paso = as_company(company) { sin_formulario.steps.reload.find { |s| s.kind == kind } }

        get challenge_step_path(sin_formulario, paso)

        expect(response.body).to include('<div class="setup-nav">'), "faltó en #{kind}"
        expect(response.body).to include("→"), "faltó en #{kind}"
      end
    end

    it "la pantalla suelta de criterios redirige al módulo" do
      get challenge_step_criteria_path(challenge, paso("selection"))

      expect(response).to redirect_to(challenge_step_path(challenge, paso("selection")))
    end

    # `step_criteria/show` era una de las dos únicas pantallas que mostraban
    # `shared/ai_suggestions` para un módulo. Borrarla sin más dejaba una
    # sugerencia pendiente de revisión sobre un módulo pendiente sin ningún
    # lugar donde verse — con `@pending_suggestions` calculado en el
    # controller y nadie que lo renderizara.
    it "una sugerencia de IA pendiente de revisión aparece en la pantalla del módulo" do
      paso_seleccion = paso("selection")
      as_company(company) do
        run = AiRun.create!(challenge: challenge, challenge_step: paso_seleccion, purpose: "suggest_criteria",
                            mode: "ai_assisted", status: "succeeded", provider: "fixture",
                            idempotency_key: SecureRandom.uuid)
        AiSuggestion.create!(ai_run: run, challenge_step: paso_seleccion, status: "pending",
                             payload: { "name" => "Filtros propuestos",
                                        "criteria" => [{ "name" => "Formulario completo", "weight" => 100,
                                                         "source" => "manual" }] })
      end

      get challenge_step_path(challenge, paso_seleccion)

      expect(response.body).to include("Propuestas de la IA")
      expect(response.body).to include("Formulario completo")
    end

    it "trae el editor de campos en Idear" do
      get challenge_step_path(challenge, paso("ideation"))

      expect(response.body).to include('data-island="form-editor"')
    end

    # `form_fields/show` cerraba con `shared/setup_nav`. Embeber el editor en
    # `steps/config/ideation` sin sumar ese render dejaba el paso a paso sin
    # «siguiente →»: un indicador, no un recorrido. El desafío de arriba ya
    # tiene flujo Y formulario, así que su paso a paso está `ready?` y el pie
    # ofrece «Arrancar» en vez de un link con flecha — se prueba sobre un
    # desafío SIN campos todavía, donde sigue habiendo algo pendiente antes de
    # arrancar y el pie tiene que decir a dónde seguir.
    it "el pie del paso a paso sigue ofreciendo el siguiente paso en el formulario" do
      sin_campos = as_company(company) do
        c = create(:challenge, name: "Sin campos todavía")
        c.steps.create!(kind: "ideation", position: 1)
        c
      end
      ideacion = as_company(company) { sin_campos.steps.reload.find(&:ideation?) }

      get challenge_step_path(sin_campos, ideacion)

      expect(response.body).to include('<div class="setup-nav">')
      expect(response.body).to include("→")
    end

    it "la pantalla suelta del formulario redirige al módulo de idear" do
      get challenge_form_path(challenge)

      expect(response).to redirect_to(challenge_step_path(challenge, paso("ideation")))
    end

    # `form_fields/show` era la otra pantalla que mostraba
    # `shared/ai_suggestions` para un módulo. Borrarla sin más dejaba una
    # sugerencia de campos pendiente de revisión sobre un módulo pendiente sin
    # ningún lugar donde verse.
    it "una sugerencia de IA de campos pendiente de revisión aparece en el módulo de idear" do
      paso_ideacion = paso("ideation")
      as_company(company) do
        run = AiRun.create!(challenge: challenge, challenge_step: paso_ideacion, purpose: "suggest_form_fields",
                            mode: "ai_assisted", status: "succeeded", provider: "fixture",
                            idempotency_key: SecureRandom.uuid)
        AiSuggestion.create!(ai_run: run, challenge_step: paso_ideacion, status: "pending",
                             payload: { "fields" => [{ "key" => "titulo", "label" => "Campo nuevo propuesto",
                                                        "field_type" => "text" }] })
      end

      get challenge_step_path(challenge, paso_ideacion)

      expect(response.body).to include("Propuestas de la IA")
      expect(response.body).to include("Campo nuevo propuesto")
    end

    # Mismo criterio que el bloque de criterios: sin `manage_form?` el
    # participante recibía el editor completo —la isla y el botón «Usar los
    # tres básicos»— y clickearlo le rebotaba 403.
    it "sin `manage_form?`, el módulo de idear muestra los campos pero no ofrece editarlos" do
      participante = without_tenant do
        u = create(:user, email: "part-form@test.dev", name: "Pedro Participante")
        create(:membership, company: company, user: u, role: "participant")
        u
      end
      sign_in(participante, company: company)

      get challenge_step_path(challenge, paso("ideation"))

      expect(response.body).not_to include('data-island="form-editor"')
      expect(response.body).not_to include("Usar los tres básicos")
      expect(response.body).to include("Sólo quien administra el desafío puede cambiar esto")
    end

    # H1 de la ronda 1: el panel de sugerencias vivía ANTES de `puede_configurar`
    # en el partial, así que un participante recibía el payload propuesto
    # completo y los `button_to` de «Aplicar»/«Descartar» — que le rebotaban
    # 403 al apretarlos, porque aceptar pide el mismo permiso que configurar.
    it "sin `configure?`, la sugerencia pendiente no ofrece Aplicar ni Descartar" do
      paso_seleccion = paso("selection")
      as_company(company) do
        run = AiRun.create!(challenge: challenge, challenge_step: paso_seleccion, purpose: "suggest_criteria",
                            mode: "ai_assisted", status: "succeeded", provider: "fixture",
                            idempotency_key: SecureRandom.uuid)
        AiSuggestion.create!(ai_run: run, challenge_step: paso_seleccion, status: "pending",
                             payload: { "name" => "Filtros propuestos",
                                        "criteria" => [{ "name" => "Formulario completo", "weight" => 100,
                                                         "source" => "manual" }] })
      end
      participante = without_tenant do
        u = create(:user, email: "part-ia@test.dev", name: "Pía Participante")
        create(:membership, company: company, user: u, role: "participant")
        u
      end
      sign_in(participante, company: company)

      get challenge_step_path(challenge, paso_seleccion)

      expect(response.body).not_to include("Propuestas de la IA")
      expect(response.body).not_to include("Aplicar")
      expect(response.body).not_to include("Descartar")
    end

    # H2 de la ronda 1: el desafío de este spec nunca le da un set INLINE a
    # ningún módulo, así que la rama `- else` de `set.nil?` —isla completa,
    # «Rehacer los criterios con IA», «Guardarlos también en la
    # biblioteca»— no la ejercitaba nadie sin `configure?`. Por mutación:
    # poner en `true` el `if puede_configurar` que envuelve esa rama dejaba
    # esta suite en verde igual.
    it "sin `configure?`, un módulo con criterios propios muestra los criterios pero no la isla ni sus acciones" do
      seleccion = paso("selection")
      as_company(company) do
        set = CriteriaSet.create!(name: "Criterios propios de Corte", scope: "inline", owner_step_id: seleccion.id)
        set.criteria.create!(name: "Formulario completo", key: "completo", weight: 1, source: "manual",
                             scale_type: "boolean")
        set.refresh_status!
        ChallengeStep.find(seleccion.id).update!(criteria_set_id: set.id)
      end
      participante = without_tenant do
        u = create(:user, email: "part-set@test.dev", name: "Pablo Participante")
        create(:membership, company: company, user: u, role: "participant")
        u
      end
      sign_in(participante, company: company)

      get challenge_step_path(challenge, seleccion)

      expect(response.body).to include("Formulario completo")
      expect(response.body).not_to include('data-island="criteria-editor"')
      expect(response.body).not_to include("Rehacer los criterios con IA")
      expect(response.body).not_to include("Guardarlos también en la biblioteca")
    end

    # Sumar a alguien con el módulo en curso ya era legítimo; lo nuevo es que
    # también se puede ANTES de que arranque, para armar el comité sin
    # esperar. «Elegí a quién sumar» —el texto real del form— es de
    # GESTORES, no de evaluadores: el form de evaluadores usa «Sumar a
    # alguien…» y «Asignar». Se prueba el marcador real de cada bloque, no
    # sólo el título, porque el título solo no distingue mostrar la tabla de
    # ofrecer el form de sumar.
    it "deja asignar evaluadores antes de que el módulo arranque" do
      get challenge_step_path(challenge, paso("evaluation"))

      expect(response.body).to include("Quién evalúa")
      expect(response.body).to include("Sumar a alguien…")
      expect(response.body).to include('name="user_id"')
    end

    it "deja asignar gestores antes de que el módulo arranque" do
      without_tenant do
        u = create(:user, email: "gestora@test.dev", name: "Gina Gestora")
        create(:membership, company: company, user: u, role: "gestor")
      end

      get challenge_step_path(challenge, paso("evolution"))

      expect(response.body).to include("Quiénes acompañan")
      expect(response.body).to include("Elegí a quién sumar")
      expect(response.body).to include('name="user_id"')
    end

    # Fix round 1: el evaluador tenía cobertura simétrica
    # (`step_assignments_spec.rb`, «quien evalúa no la ve») y gestores no.
    # Importa más después de esta tarea que antes: la cara A se sirve detrás
    # de `ChallengeStepPolicy#show?` —cualquiera de la empresa—, así que sin
    # esta guarda quien participa recibía el form de sumar gestores en un
    # módulo todavía pendiente.
    it "sin `update_pipeline?`, la cara A de evolución no ofrece asignar gestores" do
      participante = without_tenant do
        u = create(:user, email: "part-evolution@test.dev", name: "Pilar Participante")
        create(:membership, company: company, user: u, role: "participant")
        u
      end
      sign_in(participante, company: company)

      get challenge_step_path(challenge, paso("evolution"))

      expect(response.body).not_to include("Quiénes acompañan")
    end
  end

  describe "cara B: el módulo ya arrancó" do
    before do
      as_company(company) do
        create(:idea, challenge: challenge, author: admin, status: "active")
          .update!(submitted_at: Time.current)
        challenge.pipeline.start!
      end
    end

    it "no monta la isla de ajustes" do
      get challenge_step_path(challenge, paso("ideation"))

      expect(response.body).not_to include('data-island="step-settings"')
    end

    it "muestra la configuración congelada" do
      get challenge_step_path(challenge, paso("ideation"))

      expect(response.body).to include("Quedó fijado")
    end

    # Las tres cosas que siguen vivas: modo de IA, nombre y asignaciones.
    it "deja ajustar el modo de IA" do
      get challenge_step_path(challenge, paso("ideation"))

      expect(response.body).to include('name="challenge_step[ai_mode]"')
    end

    it "los módulos de más adelante siguen en cara A" do
      get challenge_step_path(challenge, paso("selection"))

      expect(response.body).to include('data-island="step-settings"')
    end

    # El formulario NO se congela con `touched?`: su candado es
    # `ideas.submitted.exists?`, que es más fino. Con el módulo abierto pero
    # sin postulaciones, corregir el label de un campo es sano.
    it "en Idear sigue mostrando el editor de campos, con su propio candado" do
      get challenge_step_path(challenge, paso("ideation"))

      expect(response.body).to include('data-island="form-editor"')
    end

    # La guarda de `manage_form?` se probó en cara A. En cara B el editor vive
    # dentro de los ajustes plegados, y esos ni se dibujan sin `advance?` ni
    # `manage_form?`: quien participa no ve el bloque entero, ni su
    # `else` de sólo lectura, sino el formulario de lectura de la referencia
    # (`steps/campos_lectura`), igual que ve quien evalúa o acompaña.
    it "sin `manage_form?`, en Idear no hay editor ni ajustes: sólo el formulario de lectura" do
      participante = without_tenant do
        u = create(:user, email: "part-form-b@test.dev", name: "Priscila Participante")
        create(:membership, company: company, user: u, role: "participant")
        u
      end
      sign_in(participante, company: company)

      get challenge_step_path(challenge, paso("ideation"))

      expect(response.body).not_to include('data-island="form-editor"')
      expect(response.body).not_to include("Rehacer el formulario con IA")
      expect(response.body).not_to include("Ajustes del módulo")
      expect(response.body).to include("Formulario de postulación")
    end
  end

  # El `before` de "cara B" arriba sólo hace `pipeline.start!`, y eso deja
  # tocado ÚNICAMENTE a `ideation` — las `it` de ese describe corren sobre un
  # solo kind. Acá se activan los seis directo por el handler (sin pasar por
  # `pipeline.advance!`, que exigiría satisfacer el `can_complete?` de cada
  # uno en orden) para probar la tarjeta congelada en los seis, con `config`
  # explícito para que haya algo real que afirmar.
  describe "cara B en los seis kinds: la configuración congelada muestra algo real" do
    let!(:tocado) do
      as_company(company) do
        c = create(:challenge, name: "Recorrido completo", ai_default_mode: "human")
        seed_form!(c.steps.create!(kind: "ideation", position: 1, config: { "min_ideas" => 7 }))
        c.steps.create!(kind: "evaluation", position: 2, name: "Comité",
                        config: { "evaluator_aggregation" => "trimmed_mean" })
        c.steps.create!(kind: "selection", position: 3, name: "Corte",
                        config: { "cut" => { "mode" => "top_n", "value" => 2 } })
        c.steps.create!(kind: "reporting", position: 4, name: "Informe",
                        config: { "mode" => "latest", "step_slugs" => %w[ideation evaluation] })
        c.steps.create!(kind: "evolution", position: 5, name: "Mejorar",
                        config: { "require_response" => true })
        c.steps.create!(kind: "testing", position: 6, name: "Prueba",
                        config: { "min_situations" => 5 })
        create(:idea, challenge: c, author: admin, status: "active").update!(submitted_at: Time.current)
        c.steps.reload.ordered.each { |s| Flow::Handlers::Base.for(s).activate! }
        c
      end
    end

    def paso_tocado(kind) = as_company(company) { tocado.steps.reload.find { |s| s.kind == kind } }

    # «Quedó fijado» va con mayúscula en `_config_congelada`; `selection` no
    # lo usa —tiene su propia tarjeta «Cómo se decide», con el mismo aviso en
    # minúscula (ver el reporte de la Task 5)— así que el chequeo va sin
    # distinguir mayúsculas.
    it "queda tocado, con algún aviso de congelado, en los seis kinds" do
      ChallengeStep::KINDS.each do |kind|
        get challenge_step_path(tocado, paso_tocado(kind))

        expect(response.body).not_to include('data-island="step-settings"'), "#{kind} no debería estar en cara A"
        expect(response.body).to match(/quedó fijado/i), "#{kind} sin ningún aviso de congelado"
      end
    end

    it "un campo numérico muestra su número real, no un genérico" do
      get challenge_step_path(tocado, paso_tocado("ideation"))

      expect(response.body).to match(/Ideas mínimas para poder avanzar.*?7/m)
    end

    it "un select muestra la etiqueta legible, no el valor de máquina" do
      get challenge_step_path(tocado, paso_tocado("evaluation"))

      expect(response.body).to include("Promedio sin extremos")
      expect(response.body).not_to include("trimmed_mean")

      get challenge_step_path(tocado, paso_tocado("reporting"))

      expect(response.body).to include("Versión vigente, marcando lo desactualizado")
      expect(response.body).not_to include(">latest<")
    end

    # `step_slugs` es multi_select sin `options` estáticas (el `source:` es
    # dinámico): antes de este arreglo salía como `Array#inspect`, con
    # corchetes y comillas.
    it "un multi_select se junta con comas, no `Array#inspect`" do
      get challenge_step_path(tocado, paso_tocado("reporting"))

      expect(response.body).to include("ideation, evaluation")
      expect(response.body).not_to include('["ideation"')
    end

    it "un boolean dice Sí/No, no `true`/`false`" do
      get challenge_step_path(tocado, paso_tocado("evolution"))

      expect(response.body).to include("Sí")
      expect(response.body).not_to include(">true<")
    end
  end

  # Fix de la revisión final de la rama: el `describe` de arriba pone `config:`
  # a mano en los seis kinds, y ése es el caso que NO ocurre en la práctica.
  # `Api::V1::PipelinesController#create_added` siembra
  # `Flow::StepSettings.defaults`, pero `Flow::FlowTemplates` manda configs
  # PARCIALES y `db/seeds.rb` no manda ninguna: los dos caminos normales dejan
  # huecos. Con `_config_congelada` leyendo `step.settings` a secas, evolución
  # y reportería servían la tarjeta ENTERA vacía —encabezado, aviso del
  # candado y un `<ul>` sin una sola fila—, que es la misma pantalla que
  # anuncia un control y no lo muestra con la que empezó todo esto.
  describe "cara B de un módulo creado SIN config, como lo crean plantillas y seed" do
    let!(:sin_config) do
      as_company(company) do
        c = create(:challenge, name: "Sin config", ai_default_mode: "human")
        ChallengeStep::KINDS.each do |kind|
          c.pipeline.insert(kind: kind, after: :end)
        end
        seed_form!(c.steps.reload.find(&:ideation?))
        create(:idea, challenge: c, author: admin, status: "active").update!(submitted_at: Time.current)
        c.steps.reload.ordered.each { |s| Flow::Handlers::Base.for(s).activate! }
        c
      end
    end

    def paso_sin_config(kind) = as_company(company) { sin_config.steps.reload.find { |s| s.kind == kind } }

    it "nace sin nada escrito: es el estado que el fixture de arriba no cubría" do
      expect(paso_sin_config("evolution").settings).to eq({})
      expect(paso_sin_config("reporting").settings).to eq({})
    end

    # Un default del esquema no es un valor inventado: es con el que corre el
    # handler (`settings.fetch("min_ideas", 1)`, `settings["require_response"]
    # == true`). Mostrarlo es decir la verdad; saltearlo era callarla.
    it "los cuatro kinds que usan la tarjeta dicen con qué corren" do
      {
        "ideation" => "Ideas mínimas para poder avanzar",
        "evolution" => "Exigir que cada idea responda",
        "evaluation" => "Evaluaciones mínimas por idea",
        "reporting" => "Cómo trata las versiones"
      }.each do |kind, etiqueta|
        get challenge_step_path(sin_config, paso_sin_config(kind))

        expect(response.body).to include(etiqueta), "#{kind} sirvió la configuración sin esa fila"
      end
    end

    it "y con el valor del default, no con la etiqueta sola" do
      get challenge_step_path(sin_config, paso_sin_config("evolution"))
      expect(response.body).to match(/Exigir que cada idea responda.*?No/m)

      get challenge_step_path(sin_config, paso_sin_config("reporting"))
      expect(response.body).to include("Por versión: cada puntaje dice qué versión se evaluó")
    end
  end

  # La misma tarjeta sirve de fallback en cara A para quien no puede
  # configurar, así que ahí el hueco se veía igual.
  describe "cara A sin `configure?`: la tarjeta de sólo lectura tampoco queda vacía" do
    let!(:participante) do
      without_tenant do
        u = create(:user, email: "part-congelada@test.dev", name: "Pedro Participante")
        create(:membership, company: company, user: u, role: "participant")
        u
      end
    end

    before { sign_in(participante, company: company) }

    it "muestra los ajustes de un módulo creado sin config" do
      get challenge_step_path(challenge, paso("evolution"))

      expect(response.body).to include("Cómo está configurado")
      expect(response.body).to include("Exigir que cada idea responda")
    end

    # `depends_on` se respeta igual que en el editor: con la regla de corte en
    # «manual» el valor no describe nada, y anunciarlo sería un número que el
    # handler ni mira.
    it "no anuncia «Valor del corte» con la regla en manual" do
      get challenge_step_path(challenge, paso("selection"))

      expect(response.body).to include("Regla de corte")
      expect(response.body).to include("Manual: el dueño decide")
      expect(response.body).not_to include("Valor del corte")
    end
  end

  # Fix round 1: asignar en cara A es un camino nuevo y cambia cómo arranca el
  # módulo. `Flow::Handlers::Evaluation#assign_evaluators!` sólo autoasigna a
  # todo el que puede evaluar cuando arranca SIN ninguna asignación explícita
  # (`step.step_assignments.reload.any?`); nada probaba que sumar a alguien
  # ANTES de arrancar frena ese autoasignado.
  describe "asignar en cara A cambia cómo arranca el módulo" do
    it "activar ya no autoasigna a todo el que puede evaluar" do
      evaluadora = without_tenant do
        u = create(:user, email: "evaluadora@test.dev", name: "Elena Evaluadora")
        create(:membership, :evaluator, company: company, user: u)
        u
      end

      post challenge_step_step_assignments_path(challenge, paso("evaluation")),
           params: { user_id: evaluadora.id, weight: "2" }

      as_company(company) { Flow::Handlers::Base.for(paso("evaluation")).activate! }

      asignaciones = as_company(company) { paso("evaluation").step_assignments.to_a }
      # `admin` también puede evaluar (rol admin) y se habría autoasignado si
      # `assign_evaluators!` hubiera corrido: la única asignación tiene que
      # ser la que se sumó a mano en cara A, con su peso intacto.
      expect(asignaciones.map(&:user_id)).to contain_exactly(evaluadora.id)
      expect(asignaciones.first.weight.to_f).to eq(2.0)
    end
  end
end
