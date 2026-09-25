# frozen_string_literal: true

require "rails_helper"

# La previsualización.
#
# Hasta acá el dueño configuraba a ciegas: el formulario de postulación y la
# ficha de evaluación recién se veían con el desafío ya en curso, cuando la
# ventana para cambiarlos estaba cerrada.
RSpec.describe "previsualizar el desafío", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  let!(:owner) do
    without_tenant do
      u = create(:user, email: "owner@test.dev")
      create(:membership, :owner, company: company, user: u)
      u
    end
  end

  let!(:participant) do
    without_tenant do
      u = create(:user, email: "part@test.dev")
      create(:membership, company: company, user: u)
      u
    end
  end

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma")
      seed_form!(c.steps.create!(kind: "ideation", position: 1, name: "Postulación"))
      c.steps.create!(kind: "evaluation", position: 2, name: "Técnica")
      c.steps.create!(kind: "selection", position: 3, name: "Corte",
                      config: { "cut" => { "mode" => "top_n", "value" => 5 } })
      c
    end
  end

  before { sign_in(owner, company: company) }

  it "muestra el formulario real que responde quien postula" do
    get challenge_preview_path(challenge)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Título", "¿Qué problema resuelve?", "¿Cómo funcionaría?")
    # No es una maqueta: son los mismos campos, con sus names reales.
    expect(response.body).to include('name="payload[titulo]"')
  end

  # Sin esto el preview sería una pantalla que se puede completar, y alguien
  # va a intentarlo.
  it "y no se puede escribir en él" do
    get challenge_preview_path(challenge)
    expect(response.body).to include("<fieldset class=\"preview-surface\" disabled>")
  end

  # `criteria_snapshot` solo existe una vez congelado el módulo. Sin resolver
  # los genéricos, la ficha se vería vacía justo cuando todavía se puede
  # cambiar.
  it "muestra la ficha de evaluación con los criterios genéricos si el módulo no tiene los suyos" do
    get challenge_preview_path(challenge)

    expect(response.body).to include("Impacto", "Factibilidad", "Esfuerzo")
    expect(response.body).to include("criterios genéricos")
    expect(response.body).to include('name="scores[impacto]"')
  end

  it "y con los propios cuando el módulo los tiene" do
    as_company(company) do
      set = CriteriaSet.create!(name: "Propios", scope: "library")
      set.criteria.create!(name: "Riesgo legal", key: "riesgo", weight: 1, source: "manual",
                           scale_type: "boolean", scale_config: { "true_label" => "Hay riesgo",
                                                                  "false_label" => "No hay" })
      set.refresh_status!
      challenge.steps.find_by(kind: "evaluation").update!(criteria_set: set)
    end

    get challenge_preview_path(challenge)

    expect(response.body).to include("Riesgo legal", "Hay riesgo")
    expect(response.body).not_to include("criterios genéricos")
  end

  # Con el módulo ya tocado la ficha sale del SNAPSHOT congelado, y de ahí cada
  # criterio traía su fila viva con un `find_by` propio: una consulta por
  # criterio.
  #
  # Este conteo SÍ muerde, a diferencia del de los filtros de selección: los ids
  # son distintos por criterio, así que el SQL también, y la caché de consultas
  # no lo esconde. Tres criterios para que el número pueda crecer con las filas
  # —con uno solo, un fan-out y un memo miden igual—.
  it "no pide una consulta por criterio para la ficha de un módulo ya tocado" do
    as_company(company) do
      set = CriteriaSet.create!(name: "Propios", scope: "library")
      [["Impacto", "impacto", 0.5], ["Riesgo", "riesgo", 0.3], ["Costo", "costo", 0.2]].each_with_index do |(name, key, weight), i|
        set.criteria.create!(name: name, key: key, weight: weight, source: "manual",
                             scale_type: "numeric", scale_config: { "min" => 1, "max" => 10 },
                             position: i)
      end
      set.refresh_status!
      step = challenge.steps.find_by(kind: "evaluation")
      step.update!(criteria_set: set)
      Flow::Handlers::Base.for(step).activate!
    end

    consultas = consultas_a("criteria") { get challenge_preview_path(challenge) }

    # El NOMBRE lo pinta el snapshot, así que con el memo devolviendo un hash
    # vacío las consultas desaparecen y esa aserción sigue verde mientras la
    # ficha se degrada a «Criterio sin escala resoluble.» en los tres. El input
    # sólo existe si la fila viva resolvió su escala (`_criterion_field:9`), y
    # es lo que ata el memo a lo que se ve.
    expect(response.body).to include("Impacto", "Riesgo", "Costo")
    expect(response.body).to include('name="scores[impacto]"', 'name="scores[riesgo]"')
    expect(consultas.size).to be <= 2, "#{consultas.size} consultas a criteria:\n  #{consultas.join("\n  ")}"
  end

  it "explica el corte de una selección en palabras" do
    get challenge_preview_path(challenge)

    expect(response.body).to include("avanzan las 5 mejores")
  end

  it "avisa cuando «Idear» no tiene formulario, con el link para resolverlo" do
    ideation = as_company(company) do
      step = challenge.pipeline.ideation_step
      step.form_fields.destroy_all
      step
    end

    get challenge_preview_path(challenge)

    expect(response.body).to include("Sin campos: nadie puede postular")
    expect(response.body).to include(challenge_step_path(challenge, ideation))
  end

  it "un desafío sin módulos lo dice, en vez de mostrar una página vacía" do
    vacio = as_company(company) { create(:challenge, name: "Vacío") }

    get challenge_preview_path(vacio)

    expect(response.body).to include("todavía no tiene módulos")
  end

  describe "quién puede" do
    it "quien participa, no: es la pantalla de quien configura" do
      sign_in(participant, company: company)
      get challenge_preview_path(challenge)

      expect(response).to have_http_status(:forbidden).or have_http_status(:found)
    end

    it "el desafío de otra empresa da 404" do
      other = without_tenant { create(:company, slug: "otra") }
      ajeno = as_company(other) { create(:challenge) }

      get challenge_preview_path(ajeno)
      expect(response).to have_http_status(:not_found)
    end
  end
end
