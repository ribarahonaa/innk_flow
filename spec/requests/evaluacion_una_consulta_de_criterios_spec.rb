# frozen_string_literal: true

require "rails_helper"

# Guardar una evaluación resolvía cada criterio del snapshot con su propio
# `Criterion.find_by(id:)`. Son CINCO lugares con la misma forma —dos en
# `ScoreAssessment`, dos en `Tasks::EvaluateIdea` y uno en
# `AssessmentsController#write_scores!`— y los ids son los mismos para todas las
# ideas del módulo, así que la lista se pide entera una vez o de a una por fila.
#
# Un POST solo ejercita cuatro de los cinco: `write_scores!` recorre los
# `scored_criteria`, y `ScoreAssessment` los automáticos y los de fórmula. El
# quinto (`criteria_prompt`, que arma el prompt de la IA) queda cubierto por
# lectura y por el mismo helper.
#
# El tope no depende de cuántos criterios haya, que es lo único que distingue un
# N+1 de «hace varias consultas»: con cinco criterios y el defecto, el número
# crece con las filas.
RSpec.describe "guardar una evaluación no pide un criterio por vez", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  let!(:admin) do
    without_tenant do
      u = create(:user, email: "admin@test.dev")
      create(:membership, :admin, company: company, user: u)
      u
    end
  end

  let!(:paula) do
    without_tenant do
      u = create(:user, email: "paula@test.dev")
      create(:membership, company: company, user: u, role: "participant")
      u
    end
  end

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma", ai_default_mode: "human")
      seed_form!(c.steps.create!(kind: "ideation", position: 1))
      c.steps.create!(kind: "evaluation", position: 2, name: "Técnica")
      c
    end
  end

  # Tres manuales, uno automático y uno de fórmula: los tres caminos que
  # resuelven un criterio al guardar.
  let!(:set) do
    as_company(company) do
      s = CriteriaSet.create!(name: "Vara", scope: "inline",
                              owner_step: challenge.steps.reload.find(&:evaluation?))
      %w[impacto factibilidad esfuerzo].each_with_index do |key, i|
        s.criteria.create!(name: key.capitalize, key: key, weight: 0.2, source: "manual",
                           scale_type: "numeric", position: i,
                           scale_config: { "min" => 1, "max" => 10, "step" => 1,
                                           "direction" => "higher_better" })
      end
      s.criteria.create!(name: "Título completo", key: "titulo_ok", weight: 0.2,
                         source: "automatic", scale_type: "boolean", position: 3,
                         source_config: { "check" => "field_present", "field_key" => "titulo" })
      s.criteria.create!(name: "Derivado", key: "derivado", weight: 0.2, source: "formula",
                         scale_type: "numeric", position: 4,
                         scale_config: { "expression" => "impacto * 2", "min" => 0, "max" => 20 })
      s.refresh_status!
      s
    end
  end

  let!(:idea) do
    as_company(company) do
      i = create(:idea, challenge: challenge, author: paula, status: "active")
      Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" }, author: paula).call
      i.update!(submitted_at: Time.current)
      i
    end
  end

  def paso
    as_company(company) do
      p = challenge.steps.reload.find(&:evaluation?)
      p.update!(criteria_set: set) if p.criteria_set_id.nil?
      challenge.pipeline.start! if challenge.reload.draft?
      challenge.pipeline.advance! unless p.reload.touched?
      p.reload
    end
  end

  it "resuelve el snapshot con un puñado de consultas y no una por criterio" do
    modulo = paso
    sign_in(admin, company: company)

    consultas = consultas_a("criteria") do
      post challenge_step_assessments_path(challenge, modulo),
           params: { idea_id: idea.id, overall_comment: "Va",
                     scores: { impacto: "8", factibilidad: "7", esfuerzo: "3" } }
    end

    expect(response).to have_http_status(:redirect)
    # Lo que ata el número a que la evaluación se haya escrito DE VERDAD: sin
    # esto, un memo que devuelva vacío hace desaparecer las consultas y la
    # aserción de arriba queda verde con los puntajes sin resolver.
    as_company(company) do
      guardada = modulo.assessments.find_by!(idea_id: idea.id)
      expect(guardada.assessment_scores.where.not(numeric_value: nil).count).to be >= 4
    end

    # Se descuentan las de `associations_within_tenant`: son la verificación de
    # tenencia que corre por FILA ESCRITA (una por `assessment_score`), o sea la
    # cuarta capa haciendo su trabajo. Crecen con los puntajes que se guardan, no
    # con el tamaño del snapshot, así que no son lo que esto mide. Contarlas
    # obligaba a un tope que crece con los criterios, que es justo lo que un tope
    # de N+1 no puede hacer.
    del_snapshot = consultas.reject { |q| q.include?("associations_within_tenant") }

    expect(del_snapshot.size).to be <= 2, lambda {
      "#{del_snapshot.size} consultas a `criteria` para resolver un snapshot de 5:\n" +
        del_snapshot.join("\n")
    }
  end
end
