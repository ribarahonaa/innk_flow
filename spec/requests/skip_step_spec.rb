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
  # `continue!` se niega. Se avisa en vez de decir sólo «Módulo salteado»: el
  # salteo se guardó igual, y eso sube el piso de inserción del flujo —los
  # pendientes anteriores dejan de poder moverse o borrarse—, que es demasiado
  # para dejarlo sin decir nada.
  it "saltear uno pendiente no mueve el que está en curso, y lo dice" do
    challenge = arrancado(%w[ideation evaluation reporting])
    pendiente = as_company(company) { challenge.steps.ordered.last }

    post skip_challenge_step_path(challenge, pendiente)

    expect(flash[:alert]).to include("el flujo no avanzó")
    as_company(company) do
      pasos = challenge.steps.ordered.reload
      expect(pasos.first).to be_active
      expect(pasos.last).to be_skipped
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

    # `skip!` no mira el estado del DESAFÍO y `continue!` se niega fuera de
    # curso: sobre un borrador el salteo se guardaría igual, y un módulo
    # `skipped` primero en el flujo deja el desafío arrancando sin nadie
    # activo, porque `activate!` no toca un módulo ya tocado.
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
