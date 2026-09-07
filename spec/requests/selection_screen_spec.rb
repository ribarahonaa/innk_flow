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
end

