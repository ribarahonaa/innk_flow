# frozen_string_literal: true

require "rails_helper"

# La pantalla del corte.
RSpec.describe "la pantalla de una selección", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  let!(:admin) do
    without_tenant do
      u = create(:user, email: "admin@test.dev", name: "Ana Admin")
      create(:membership, :admin, company: company, user: u)
      u
    end
  end

  let!(:paula) do
    without_tenant do
      u = create(:user, email: "paula@test.dev", name: "Paula Participante")
      create(:membership, company: company, user: u, role: "participant")
      u
    end
  end

  let!(:filtros) do
    as_company(company) do
      set = CriteriaSet.create!(name: "Filtros", scope: "library")
      set.criteria.create!(name: "¿Está claro?", key: "claro", weight: 1, source: "manual",
                           scale_type: "boolean")
      set.refresh_status!
      set
    end
  end

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma", ai_default_mode: "human")
      seed_form!(c.steps.create!(kind: "ideation", position: 1))
      c.steps.create!(kind: "selection", position: 2, name: "Corte", criteria_set: filtros,
                      config: { "score_source" => { "type" => "manual" },
                                "cut" => { "mode" => "top_n", "value" => 1 } })
      c
    end
  end

  def paso = as_company(company) { challenge.steps.reload.find(&:selection?) }

  # «Top N» es el NOMBRE de la regla, con la N como marcador. Impreso tal cual
  # en la línea de corte se lee como el literal «TOP N» en vez del número que
  # decide. La previsualización ya lo decía bien —«avanzan las 3 mejores»—, así
  # que la app sabía; la pantalla de ejecución no.
  it "la regla de corte se nombra con su número, no con la N" do
    get challenge_step_path(challenge, paso)

    expect(response.body).to include("línea de corte · Top 1")
    expect(response.body).not_to include("Top N")
  end

  let!(:ideas) do
    as_company(company) do
      %w[Sensores Cámaras].map do |titulo|
        i = create(:idea, challenge: challenge, author: paula, status: "active")
        Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => titulo }, author: paula).call
        i.update!(submitted_at: Time.current)
        i
      end
    end
  end

  before do
    as_company(company) do
      challenge.pipeline.start!
      challenge.pipeline.advance!
    end
    sign_in(admin, company: company)
  end

  # Cuenta la anidación de <form> en el HTML SERVIDO. En el DOM no se puede
  # mirar: el navegador descarta el form interno al parsear, y sus botones
  # pasan a pertenecer al externo.
  def profundidad_maxima_de_forms(html)
    maxima = 0
    actual = 0
    html.scan(%r{<form\b|</form>}) do |etiqueta|
      actual += etiqueta == "</form>" ? -1 : 1
      maxima = [maxima, actual].max
    end
    maxima
  end

  # Los botones ✓/✗ de veredicto son `button_to` —o sea, un form—. Estaban
  # dentro del formulario del corte, así que el navegador los adoptaba: apretar
  # un veredicto enviaba el corte con lo que hubiera tildado.
  it "no sirve un formulario dentro de otro" do
    get challenge_step_path(challenge, paso)

    expect(response.body).to include("veredicto por idea")
    expect(profundidad_maxima_de_forms(response.body)).to eq(1)
  end

  it "ata los checkboxes al formulario del corte por id" do
    get challenge_step_path(challenge, paso)

    expect(response.body).to match(/name="advancing_idea_ids\[\]"[^>]*form="corte-/)
  end

  describe "con el módulo ya cerrado" do
    before do
      as_company(company) do
        handler = paso.handler
        ideas.each { |i| handler.record_verdict!(idea: i, criterion_key: "claro", passed: true, decided_by: admin) }
        handler.decide!([ideas.first.id], decided_by: admin, reason: "Entra una sola")
        # `decide!` registra el corte pero no cierra el módulo: mientras siga
        # activo se puede volver a decidir, y por eso las casillas siguen.
        handler.complete!
      end
    end

    # La casilla se podía tildar y no hacía nada: no hay formulario que enviar.
    it "muestra el resultado en vez de una casilla que no hace nada" do
      get challenge_step_path(challenge, paso)

      expect(response.body).to include("Resultado")
      expect(response.body).not_to include('name="advancing_idea_ids[]"')
    end

    # Había una tarjeta «No avanzaron» que repetía las mismas filas de la tabla
    # de arriba, solo para colgarles el botón.
    it "repesca desde la fila de la idea, sin repetir la lista" do
      get challenge_step_path(challenge, paso)

      expect(response.body).to include("Repescar")
      expect(response.body).not_to include("No avanzaron")
    end

    # Quién, motivo y cuándo eran iguales en las dos filas: tres de seis
    # columnas idénticas de arriba abajo.
    it "el registro dice el motivo una vez por tanda, no una por idea" do
      get challenge_step_path(challenge, paso)

      expect(response.body.scan("Entra una sola").size).to eq(1)
      expect(response.body).to include("2 ideas")
    end
  end

  # Era el único de los cinco módulos sin la tarjeta, y es donde más importa:
  # con «Solo personas» los veredictos los responde alguien uno por uno.
  describe "el modo de IA" do
    it "se puede cambiar desde el módulo, como en los otros cuatro" do
      get challenge_step_path(challenge, paso)

      expect(response.body).to include("Modo de IA")
      expect(response.body).to match(/name="challenge_step\[ai_mode\]"/)
    end

    # El texto decía «para pedirle que te guíe en cada evaluación» en las
    # cuatro pantallas donde se renderiza. Solo era cierto en una.
    it "dice qué se le puede pedir a la IA en ESTE módulo" do
      get challenge_step_path(challenge, paso)

      expect(response.body).to include("responda los filtros de sí/no")
      expect(response.body).not_to include("te guíe en cada evaluación")
    end
  end

  # El corte vive en `config`, que se congela al arrancar el módulo. Mientras el
  # módulo está pendiente NO está congelado: se edita, pero desde la pantalla
  # del propio módulo —el builder ya no tiene panel para eso; sus tarjetas son
  # links a acá—.
  describe "el corte, con el módulo todavía pendiente" do
    let!(:pendiente) do
      as_company(company) do
        c = create(:challenge, name: "Onboarding", ai_default_mode: "human")
        seed_form!(c.steps.create!(kind: "ideation", position: 1))
        c.steps.create!(kind: "evaluation", position: 2, name: "Comité")
        c.steps.create!(kind: "selection", position: 3, name: "Corte final",
                        config: { "cut" => { "mode" => "top_n", "value" => 3 } })
        c
      end
    end

    def corte = as_company(company) { pendiente.steps.reload.find(&:selection?) }

    it "se cambia en la propia pantalla del módulo, no en un link al builder" do
      get challenge_step_path(pendiente, corte)

      expect(response.body).to include('data-island="step-settings"')
      expect(response.body).not_to include("Cambiar el corte")
    end

    # `source_steps` sale de `resolved_config`, que recién se escribe en
    # `activate!`. Leerlo en un módulo pendiente daba siempre vacío, así que la
    # pantalla anunciaba «el orden es manual» aunque hubiera una evaluación
    # antes a la que el corte se va a atar solo.
    it "nombra la evaluación a la que se va a atar en vez de decir que no hay" do
      get challenge_step_path(pendiente, corte)

      expect(response.body).to include("Comité")
      expect(response.body).not_to include("sin fuente de puntaje")
    end
  end

  describe "el corte, con el módulo ya arrancado" do
    it "dice que quedó fijado, en vez de ofrecer un cambio que el server rechaza" do
      get challenge_step_path(challenge, paso)

      expect(response.body).not_to include("Cambiar el corte")
      expect(response.body).to include("quedó fijado")
    end
  end
  # El piso GANA sobre la regla, así que existe el caso de una idea arriba de la
  # línea de corte con un puntaje que no la alcanza. Sin decirlo en la pantalla,
  # eso se lee como un error de la app.
  describe "cuando el mínimo de ideas levanta el corte" do
    let!(:otro) do
      as_company(company) do
        c = create(:challenge, name: "Piso", ai_default_mode: "human")
        seed_form!(c.steps.create!(kind: "ideation", position: 1))
        evaluacion = c.steps.create!(kind: "evaluation", position: 2, name: "Técnica", slug: "tecnica")
        c.steps.create!(kind: "selection", position: 3, name: "Corte",
                        config: { "cut" => { "mode" => "threshold", "value" => 0.95, "min" => 2 } })

        %w[Alta Media Baja].each_with_index do |titulo, index|
          idea = create(:idea, challenge: c, author: paula, status: "active")
          Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => titulo }, author: paula).call
          idea.update!(submitted_at: Time.current)
          evaluacion.step_entries.create!(idea: idea, status: "done",
                                          result: { "score" => 0.6 - (index * 0.2) })
        end

        c.update!(status: "running")
        evaluacion.update!(status: "completed")
        c
      end
    end

    def corte
      as_company(company) do
        paso = otro.steps.reload.find(&:selection?)
        Flow::Handlers::Base.for(paso).activate!
        paso.reload
      end
    end

    it "la pantalla dice que pasaron por el mínimo y no por el puntaje" do
      get challenge_step_path(otro, corte)

      expect(response.body).to include("Pasan por el mínimo")
      expect(response.body).to include("mínimo 2 ideas")
    end

    it "y no lo dice cuando la regla ya alcanzaba" do
      as_company(company) do
        paso = otro.steps.reload.find(&:selection?)
        paso.update!(config: { "cut" => { "mode" => "top_n", "value" => 3, "min" => 2 } })
      end

      get challenge_step_path(otro, corte)

      expect(response.body).not_to include("Pasan por el mínimo")
    end
  end
  # El piso gana también sobre los filtros, así que existe la idea que avanza
  # CON un filtro fallado. Dos cosas se rompen si la pantalla no se entera: la
  # casilla iba `disabled` por no pasar el filtro —y una casilla deshabilitada
  # no se envía, así que confirmar el corte la dejaba afuera igual—, y la fila
  # no decía por qué una idea con ✗ estaba arriba de la línea.
  describe "cuando el piso sube una idea que no pasa un filtro" do
    let!(:verificable) do
      as_company(company) do
        set = CriteriaSet.create!(name: "Filtros verificables", scope: "library")
        set.criteria.create!(name: "Tiene costo", key: "costo_presente", weight: 1,
                             source: "automatic",
                             source_config: { "check" => "field_present", "field_key" => "costo" })
        set.refresh_status!
        set
      end
    end

    # Ninguna idea declara el costo: las dos fallan el filtro, así que sin el
    # piso no avanzaría ninguna.
    let!(:otro) do
      as_company(company) do
        c = create(:challenge, name: "Piso con filtros", ai_default_mode: "human")
        seed_form!(c.steps.create!(kind: "ideation", position: 1))
        evaluacion = c.steps.create!(kind: "evaluation", position: 2, name: "Técnica", slug: "tecnica")
        c.steps.create!(kind: "selection", position: 3, name: "Corte", criteria_set: verificable,
                        config: { "cut" => { "mode" => "threshold", "value" => 0.95, "min" => 1 } })

        %w[Alta Baja].each_with_index do |titulo, index|
          idea = create(:idea, challenge: c, author: paula, status: "active")
          Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => titulo }, author: paula).call
          idea.update!(submitted_at: Time.current)
          evaluacion.step_entries.create!(idea: idea, status: "done",
                                          result: { "score" => 0.6 - (index * 0.2) })
        end

        c.update!(status: "running")
        evaluacion.update!(status: "completed")
        c
      end
    end

    def corte_con_filtro
      as_company(company) do
        paso = otro.steps.reload.find(&:selection?)
        Flow::Handlers::Base.for(paso).activate!
        paso.reload
      end
    end

    def idea_llamada(titulo) = as_company(company) { otro.ideas.detect { |i| i.title == titulo } }
    def casilla(html, idea) = html[/<input[^>]*id="advance_#{idea.id}"[^>]*>/]

    it "deja tildar la que sube por el piso: deshabilitada no se enviaba" do
      get challenge_step_path(otro, corte_con_filtro)

      marcada = casilla(response.body, idea_llamada("Alta"))
      expect(marcada).to include("checked")
      expect(marcada).not_to include("disabled")
    end

    it "sigue sin dejar tildar la que ni el piso alcanzó" do
      get challenge_step_path(otro, corte_con_filtro)

      expect(casilla(response.body, idea_llamada("Baja"))).to include("disabled")
    end

    it "dice en la fila por qué avanza una idea con un filtro fallado" do
      get challenge_step_path(otro, corte_con_filtro)

      expect(response.body).to include("pasa por el mínimo")
    end
  end
end
