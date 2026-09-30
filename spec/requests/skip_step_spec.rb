# frozen_string_literal: true

require "rails_helper"

# Saltear un módulo fue mucho tiempo una capacidad del dominio SIN ninguna
# vista que la ofreciera —la ruta y la policy existían y nada las usaba—, y
# por eso el defecto sobrevivió: `skip` llamaba a `advance!` para seguir el
# flujo, y `advance!` corta con `failure` justo cuando no hay módulo en curso,
# que es el estado que el salteo acaba de dejar. Saltear trababa el flujo sin
# avisar.
#
# Ahora hay control (`steps/_saltear`), y su parte está al final del archivo:
# la ruta sigue llegando a estados que el botón no ofrece, así que los
# ejemplos del POST se quedan igual de necesarios.
RSpec.describe "saltear un módulo", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }
  let!(:admin) do
    without_tenant do
      u = create(:user, email: "admin@test.dev")
      create(:membership, :admin, company: company, user: u)
      u
    end
  end

  def arrancado(kinds)
    as_company(company) do
      challenge = create(:challenge, name: "Merma", ai_default_mode: "human")
      kinds.each_with_index do |kind, i|
        step = challenge.steps.create!(kind: kind, position: i + 1)
        seed_form!(step) if kind == "ideation"
      end
      challenge.pipeline.start!
      challenge.steps.reset
      challenge
    end
  end

  before { sign_in(admin, company: company) }

  # Saltear un módulo ACTIVO le deja sus `step_entries` como estaban: `skip!`
  # sólo escribe el estado del módulo. Y `skipped` cuenta como tocado
  # (`TOUCHED_STATUSES`), así que el módulo sigue apareciendo en «Cómo le fue»
  # de cada idea — diciendo «Pendiente» sobre algo que no va a correr nunca.
  #
  # El label ya existía y no lo usaba nadie: `flow.entry_statuses.skipped` estaba
  # fichado como clave huérfana del locale. No sobraba la clave; faltaba el
  # cableado.
  it "una idea de un módulo salteado dice «Salteado» y no «Pendiente»" do
    challenge = arrancado(%w[ideation evaluation reporting])
    idea = as_company(company) do
      i = create(:idea, challenge: challenge, author: admin, status: "active")
      Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" }, author: admin).call
      i.update!(submitted_at: Time.current)
      i
    end
    as_company(company) { challenge.pipeline.advance! }
    evaluacion = as_company(company) { challenge.steps.ordered.reload.second }

    post skip_challenge_step_path(challenge, evaluacion)
    get challenge_idea_path(challenge, idea)

    # Apretado al markup de la FILA a propósito: el nombre del módulo también
    # sale en el mapa del flujo de la izquierda, donde «Salteado» sí aparece, así
    # que un match suelto sobre el body pasa sin haber mirado «Cómo le fue». La
    # primera versión de este ejemplo daba verde por eso.
    etiqueta = response.body[%r{result__step">#{Regexp.escape(evaluacion.name)}</span>\s*<span[^>]*>\s*([^<]+?)\s*<}m, 1]

    expect(etiqueta).to eq("Salteado")
  end

  it "abre el siguiente módulo en vez de dejar el flujo trabado" do
    challenge = arrancado(%w[ideation evaluation reporting])
    activo = as_company(company) { challenge.steps.ordered.first }

    post skip_challenge_step_path(challenge, activo)

    as_company(company) do
      pasos = challenge.steps.ordered.reload
      expect(pasos.first).to be_skipped
      expect(pasos.second).to be_active
      expect(challenge.reload).to be_running
    end
  end

  it "cierra el desafío al saltear el último" do
    challenge = arrancado(%w[ideation reporting])
    primero = as_company(company) { challenge.steps.ordered.first }
    post skip_challenge_step_path(challenge, primero)
    segundo = as_company(company) { challenge.steps.ordered.second }
    post skip_challenge_step_path(challenge, segundo)

    as_company(company) do
      expect(challenge.steps.ordered.reload.map(&:status)).to eq(%w[skipped skipped])
      expect(challenge.reload).to be_closed
    end
  end

  # Saltear uno PENDIENTE más adelante no tiene nada que abrir, así que
  # `continue!` se niega — y ESA negativa es el resultado correcto de lo que se
  # pidió, no una falla: el módulo en curso sigue donde estaba.
  #
  # Decía «Módulo salteado, pero el flujo no avanzó» en un `alert` rojo y
  # mandaba a la ficha del desafío. Desde que la pantalla ofrece «Saltear» —y
  # el control exige el desafío EN CURSO, o sea con un módulo activo— ése pasó
  # a ser el 100% del camino: salteaba bien y contestaba en rojo, justo lo que
  # la confirmación acababa de prometer. La anomalía de verdad es la otra rama
  # (abajo), donde no queda nadie en curso y el flujo igual no se movió.
  it "saltear uno pendiente no mueve el que está en curso, y lo dice sin alarmar" do
    challenge = arrancado(%w[ideation evaluation reporting])
    pendiente = as_company(company) { challenge.steps.ordered.last }

    post skip_challenge_step_path(challenge, pendiente)

    expect(flash[:alert]).to be_nil
    expect(flash[:notice]).to include("«Reportería» queda salteado", "el flujo sigue en «Idear»")
    # Y vuelve a la pantalla del módulo que se acaba de tocar, no a la ficha.
    expect(response).to redirect_to(challenge_step_path(challenge, pendiente))
    as_company(company) do
      pasos = challenge.steps.ordered.reload
      expect(pasos.first).to be_active
      expect(pasos.last).to be_skipped
    end
  end

  # `skip!` no miraba el estado del DESAFÍO, así que sobre un BORRADOR el
  # salteo se guardaba y `continue!` se negaba: quedaba un módulo `skipped`
  # que `activate!` no vuelve a tocar nunca —sale por `return step if
  # step.touched?`—, o sea que `start!` después dejaba el desafío `running`
  # sin NINGÚN módulo activo. Y salteando «Idear» encima silenciaba el error
  # de arranque, porque `Pipeline#validate` sólo exige formulario mientras
  # `ideation.pending?`.
  #
  # El control de la pantalla ya no lo ofrecía; esto cierra la ruta.
  it "no saltea nada en un desafío que todavía no arrancó" do
    challenge = as_company(company) do
      c = create(:challenge, name: "Sin arrancar", ai_default_mode: "human")
      seed_form!(c.steps.create!(kind: "ideation", position: 1))
      c.steps.create!(kind: "reporting", position: 2)
      c
    end
    paso = as_company(company) { challenge.steps.ordered.first }

    post skip_challenge_step_path(challenge, paso)

    # Ni «ya terminó» ni «ya está salteado»: no hizo ninguna de las dos cosas.
    expect(flash[:alert]).to include("no está en curso", "desde el builder")
    expect(flash[:alert]).not_to include("ya terminó")
    as_company(company) do
      expect(challenge.steps.ordered.first.reload).to be_pending
      expect(challenge.reload).to be_draft
    end
  end

  # Y el arranque sigue funcionando después: sin la guarda, el salteo de arriba
  # dejaba el primer módulo intocable y `start!` abría un desafío sin nadie
  # adentro.
  it "y por eso el desafío sigue arrancando con su primer módulo" do
    challenge = as_company(company) do
      c = create(:challenge, name: "Sin arrancar", ai_default_mode: "human")
      seed_form!(c.steps.create!(kind: "ideation", position: 1))
      c.steps.create!(kind: "reporting", position: 2)
      c
    end
    paso = as_company(company) { challenge.steps.ordered.first }
    post skip_challenge_step_path(challenge, paso)

    post start_challenge_path(challenge)

    as_company(company) do
      expect(challenge.reload).to be_running
      expect(challenge.steps.ordered.first.reload).to be_active
    end
  end

  # `ChallengeStepPolicy#skip?` es `administers?(challenge)` y no mira el estado
  # del módulo, así que la ruta llega a uno ya COMPLETADO: `skip!` le pisaba el
  # `status`, le reescribía el `completed_at` y respondía «Módulo salteado.».
  # Un módulo que corrió entero pasaba a decir que nunca corrió, con sus
  # evaluaciones intactas debajo.
  #
  # Es la misma superficie que el defecto del salteo: sin control en ninguna
  # vista, pero la ruta y la policy sí llegan.
  it "no reescribe uno que ya terminó, y lo dice" do
    challenge = arrancado(%w[ideation reporting])
    # Por el dominio y no por `advance`: completar «Idear» desde la ruta pide
    # el mínimo de ideas postuladas, y lo que este ejemplo prueba es el POST de
    # abajo.
    completado = as_company(company) do
      paso = challenge.steps.ordered.first
      Flow::Handlers::Base.for(paso).complete!
      challenge.pipeline.continue!
      paso.reload
    end
    expect(completado).to be_completed
    cerrado_en = completado.completed_at

    post skip_challenge_step_path(challenge, completado)

    expect(flash[:alert]).to include("ya terminó")
    as_company(company) do
      quedo = challenge.steps.ordered.first.reload
      expect(quedo).to be_completed
      expect(quedo.completed_at).to eq(cerrado_en)
      expect(quedo.settings).not_to have_key("skip_reason")
    end
  end

  # Y lo mismo con uno ya salteado: un segundo POST le reescribía el motivo y
  # la fecha.
  it "ni uno ya salteado" do
    challenge = arrancado(%w[ideation evaluation reporting])
    primero = as_company(company) { challenge.steps.ordered.first }
    post skip_challenge_step_path(challenge, primero), params: { reason: "el primero" }
    salteado = as_company(company) { challenge.steps.ordered.first.reload }
    cerrado_en = salteado.completed_at

    post skip_challenge_step_path(challenge, salteado), params: { reason: "otro motivo" }

    # «ya está salteado» y no «ya terminó»: son dos motivos distintos y el
    # aviso los distingue.
    expect(flash[:alert]).to include("ya está salteado")
    as_company(company) do
      quedo = challenge.steps.ordered.first.reload
      expect(quedo.completed_at).to eq(cerrado_en)
      expect(quedo.settings["skip_reason"]).to eq("el primero")
    end
  end

  # El defecto se veía acá: `activate!` levanta `StepNotReady` y nadie lo
  # rescataba, así que el POST moría con un 500 DESPUÉS de que el salteo ya se
  # había guardado. Quien lo pedía veía la pantalla de error y no se enteraba de
  # que el módulo había quedado salteado.
  it "no revienta si el siguiente no puede arrancar: el salteo queda y lo dice" do
    challenge = arrancado(%w[ideation evaluation])
    activo = as_company(company) do
      paso = challenge.steps.ordered.first
      # Un set sin criterios activos: es lo único que `validate` no mira, así
      # que llega hasta `activate!`.
      set = CriteriaSet.create!(name: "Roto", scope: "library")
      set.refresh_status!
      challenge.steps.ordered.last.update!(criteria_set: set)
      paso
    end

    post skip_challenge_step_path(challenge, activo)

    expect(response).to have_http_status(:found)
    # Con el nombre: que el Result lo traiga no prueba que llegue a la pantalla.
    expect(flash[:alert]).to include("el flujo no avanzó", "«Evaluación»",
                                     "al menos un criterio activo")
    as_company(company) do
      expect(challenge.steps.ordered.first.reload).to be_skipped
      expect(challenge.steps.ordered.last.reload).to be_pending
      expect(challenge.reload).to be_running
    end
  end

  it "quien participa no puede saltear" do
    challenge = arrancado(%w[ideation evaluation])
    participante = without_tenant do
      u = create(:user, email: "part@test.dev")
      create(:membership, company: company, user: u, role: "participant")
      u
    end
    sign_in(participante, company: company)
    activo = as_company(company) { challenge.steps.ordered.first }

    post skip_challenge_step_path(challenge, activo)

    expect(response).to have_http_status(:forbidden)
    as_company(company) { expect(challenge.steps.ordered.first.reload).to be_active }
  end

  # ── El control ────────────────────────────────────────────────────────────
  #
  # Hasta acá saltear era una capacidad del dominio sin interfaz: la ruta, el
  # servicio y la policy existían y ninguna vista los ofrecía. El control vive
  # en «Ajustes del módulo» de la cara de ejecución y suelto en la de
  # configuración —se usa poco y no es el trabajo del módulo—, y su guarda son
  # DOS preguntas, no una: `ChallengeStepPolicy#skip?` (que es `administers?` a
  # secas) Y el estado, porque `skip!` se niega sobre uno `completed` o
  # `skipped` y `continue!` no se mueve sin el desafío en curso.
  describe "el control en la pantalla del módulo" do
    def boton(challenge, step)
      Nokogiri::HTML(response.body).at_css("form[action=\"#{skip_challenge_step_path(challenge, step)}\"]")
    end

    # Cuenta la anidación de <form> en el HTML SERVIDO: en el DOM no se ve,
    # porque el navegador descarta el interno al parsear y sus botones pasan a
    # pertenecer al externo. Mismo chequeo que `selection_screen_spec`.
    # Lo que anuncia el plegado de «Ajustes del módulo».
    def resumen_de_los_ajustes
      Nokogiri::HTML(response.body).at_css(".ajustes__titulo")&.text.to_s
    end

    def profundidad_maxima_de_forms(html)
      maxima = 0
      actual = 0
      html.scan(%r{<form\b|</form>}) do |etiqueta|
        actual += etiqueta == "</form>" ? -1 : 1
        maxima = [maxima, actual].max
      end
      maxima
    end

    it "quien administra lo ve sobre el módulo en curso, y el aviso dice a dónde pasa el flujo" do
      challenge = arrancado(%w[ideation evaluation reporting])
      activo = as_company(company) { challenge.steps.ordered.first }

      get challenge_step_path(challenge, activo)

      form = boton(challenge, activo)
      expect(form).not_to be_nil
      expect(form.text).to include("Saltear el módulo")
      expect(form["data-turbo-confirm"]).to include("«Idear»", "sin terminar",
                                                    "el flujo pasa a «Evaluación»")
      # El resumen del plegable se arma con la MISMA guarda que el bloque: si
      # no, el plegado anuncia algo que adentro no está, o lo esconde.
      expect(resumen_de_los_ajustes).to include("saltear el módulo")
    end

    it "y el formulario del salteo no queda adentro de otro" do
      challenge = arrancado(%w[ideation evaluation reporting])
      activo = as_company(company) { challenge.steps.ordered.first }

      get challenge_step_path(challenge, activo)

      expect(boton(challenge, activo)).not_to be_nil
      expect(profundidad_maxima_de_forms(response.body)).to eq(1)
    end

    it "quien participa no lo ve" do
      challenge = arrancado(%w[ideation evaluation reporting])
      participante = without_tenant do
        u = create(:user, email: "mira@test.dev")
        create(:membership, company: company, user: u, role: "participant")
        u
      end
      activo = as_company(company) { challenge.steps.ordered.first }
      sign_in(participante, company: company)

      get challenge_step_path(challenge, activo)

      expect(response).to have_http_status(:ok)
      expect(boton(challenge, activo)).to be_nil
    end

    # La mitad que la policy NO contesta: `skip?` dice que sí sobre un módulo
    # ya cerrado. Sin esta guarda el botón aparecía igual y el `alert` del
    # controller era el que avisaba — el control que no responde.
    it "no aparece sobre un módulo que ya terminó" do
      challenge = arrancado(%w[ideation reporting])
      completado = as_company(company) do
        paso = challenge.steps.ordered.first
        Flow::Handlers::Base.for(paso).complete!
        challenge.pipeline.continue!
        paso.reload
      end

      get challenge_step_path(challenge, completado)

      expect(response).to have_http_status(:ok)
      expect(as_company(company) { challenge.steps.ordered.first.reload }).to be_completed
      expect(boton(challenge, completado)).to be_nil
      # Y el plegable tampoco lo anuncia: sigue abriéndose por el nombre y el
      # modo de IA, que ahí sí se pueden tocar.
      expect(resumen_de_los_ajustes).to include("nombre")
      expect(resumen_de_los_ajustes).not_to include("saltear")
    end

    it "ni sobre uno ya salteado" do
      challenge = arrancado(%w[ideation evaluation reporting])
      primero = as_company(company) { challenge.steps.ordered.first }
      post skip_challenge_step_path(challenge, primero)
      salteado = as_company(company) { challenge.steps.ordered.first.reload }
      expect(salteado).to be_skipped

      get challenge_step_path(challenge, salteado)

      expect(boton(challenge, salteado)).to be_nil
    end

    # Saltear uno PENDIENTE sube el piso de inserción: los pendientes que
    # quedan antes dejan de poder moverse o borrarse. Es lo que el aviso tiene
    # que decir, porque no se ve por ningún lado.
    it "sobre uno pendiente, el aviso nombra el piso de inserción" do
      challenge = arrancado(%w[ideation evaluation reporting])
      pendiente = as_company(company) { challenge.steps.ordered.last }

      get challenge_step_path(challenge, pendiente)

      form = boton(challenge, pendiente)
      expect(form).not_to be_nil
      expect(form["data-turbo-confirm"]).to include("No se va a ejecutar", "sube el piso del flujo",
                                                    "1 módulo pendiente")
      # En la cara de configuración el bloque convive con el `form_with` que
      # guarda nombre, modo de IA y ajustes: tiene que quedar a su lado y no
      # adentro.
      expect(profundidad_maxima_de_forms(response.body)).to eq(1)
    end

    # ── Los doce renders ──────────────────────────────────────────────────
    #
    # El bloque se renderiza en DOCE lugares: los seis `steps/<kind>` (adentro
    # de los ajustes, con su línea en el resumen) y las seis
    # `steps/config/<kind>` (suelto, al pie). Con un solo ejemplo por cara,
    # borrar cualquiera de los otros diez dejaba `make spec` en verde — la
    # misma ceguera que CLAUDE.md documenta en `df0681d` y `2029528`, donde el
    # render huérfano de `setup_nav` pasó dos veces sin que nada avisara.

    # Un desafío EN CURSO con `kind` como módulo ACTIVO: es la cara de
    # ejecución. «Idear» va detrás porque `Pipeline#validate` lo exige, y la
    # selección necesita además su fuente de puntaje en manual, que es lo
    # único que la deja arrancar sin una evaluación delante.
    def con_activo(kind)
      as_company(company) do
        challenge = create(:challenge, name: "Con #{kind}", ai_default_mode: "human")
        config = kind == "selection" ? { "score_source" => { "type" => "manual" } } : {}
        paso = challenge.steps.create!(kind: kind, position: 1, config: config)
        seed_form!(challenge.steps.create!(kind: "ideation", position: 2))
        challenge.pipeline.start!
        [challenge, paso.reload]
      end
    end

    it "la cara de ejecución lo ofrece en los seis kinds, y el plegable lo anuncia" do
      fallan = ChallengeStep::KINDS.filter_map do |kind|
        # «Idear» no puede ser el segundo de su propio desafío (es único), y ya
        # tiene su ejemplo propio arriba, con el texto del aviso.
        next if kind == "ideation"

        challenge, paso = con_activo(kind)
        get challenge_step_path(challenge, paso)
        next if response.ok? && boton(challenge, paso) && resumen_de_los_ajustes.include?("saltear el módulo")

        "#{kind} (#{response.status})"
      end

      expect(fallan).to be_empty
    end

    # Un módulo PENDIENTE de cada kind dentro de un desafío EN CURSO: ésa es la
    # cara de configuración. Son DOS desafíos porque `ideation` es único por
    # desafío, así que el kind que arranca en uno tiene que ser el que falta
    # del otro.
    def pendientes_de_cada_kind
      as_company(company) do
        uno = create(:challenge, name: "Los cinco", ai_default_mode: "human")
        uno.steps.create!(kind: "evolution", position: 1)
        seed_form!(uno.steps.create!(kind: "ideation", position: 2))
        %w[evaluation selection reporting testing].each_with_index do |kind, i|
          uno.steps.create!(kind: kind, position: i + 3)
        end
        uno.pipeline.start!

        otro = create(:challenge, name: "El que falta", ai_default_mode: "human")
        seed_form!(otro.steps.create!(kind: "ideation", position: 1))
        otro.steps.create!(kind: "evolution", position: 2)
        otro.pipeline.start!

        pasos = uno.steps.reload.reject(&:evolution?).map { |paso| [uno, paso] }
        pasos << [otro, otro.steps.reload.find(&:evolution?)]
        pasos.index_by { |_challenge, paso| paso.kind }
      end
    end

    it "la cara de configuración lo ofrece en los seis kinds" do
      pendientes = pendientes_de_cada_kind
      # Que estén los seis: si uno se cayera del armado, el barrido pasaría
      # sin mirarlo.
      expect(pendientes.keys).to match_array(ChallengeStep::KINDS)

      fallan = pendientes.filter_map do |kind, (challenge, paso)|
        expect(paso).to be_pending
        get challenge_step_path(challenge, paso)
        next if response.ok? && boton(challenge, paso)

        "#{kind} (#{response.status})"
      end

      expect(fallan).to be_empty
    end

    # La otra mitad del estado: fuera del flujo en curso no se saltea. La regla
    # es de `Handlers::Base#skip!`, que la pide desde la revisión de esta misma
    # rama —antes NO miraba el estado del desafío y el salteo de un borrador se
    # guardaba igual, dejando un módulo `skipped` que `activate!` no vuelve a
    # tocar—; acá lo que se prueba es que el control no lo OFRECE, que es la
    # mitad de la vista. Lo que pasa por la ruta lo prueba «no saltea nada en
    # un desafío que todavía no arrancó», más arriba.
    it "no aparece en un desafío en borrador" do
      challenge = as_company(company) do
        c = create(:challenge, name: "Sin arrancar", ai_default_mode: "human")
        seed_form!(c.steps.create!(kind: "ideation", position: 1))
        c.steps.create!(kind: "reporting", position: 2)
        c
      end
      paso = as_company(company) { challenge.steps.ordered.last }

      get challenge_step_path(challenge, paso)

      expect(response).to have_http_status(:ok)
      expect(boton(challenge, paso)).to be_nil
    end
  end
end
