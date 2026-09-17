# frozen_string_literal: true

require "rails_helper"

# La cara de ejecución de un módulo en tres zonas: el trabajo al centro, lo
# que se consulta a la derecha (`.app-aside`) y los ajustes plegados al final
# (`.ajustes`). Es markup, no permisos: mudar un bloque de lugar no puede
# sacarlo de atrás de su guarda, y un spec que solo mira a quien administra no
# lo ve. Por eso cada zona se prueba por rol.
RSpec.describe "la pantalla del módulo en tres zonas", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email, role)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, role.to_sym, company: company, user: u)
      u
    end
  end

  let!(:admin) { member("admin@test.dev", :admin) }
  let!(:elena) { member("elena@test.dev", :evaluator) }
  let!(:paula) { member("paula@test.dev", :participant) }

  def paso(kind) = as_company(company) { challenge.steps.reload.find { |s| s.kind == kind } }

  def documento = Nokogiri::HTML(response.body)

  # El texto de cada zona, leído del HTML servido.
  def zonas
    { referencia: documento.at_css(".app-aside")&.text.to_s,
      ajustes: documento.at_css(".ajustes")&.text.to_s }
  end

  def postular!(challenge, author:, titulo:)
    as_company(company) do
      i = create(:idea, challenge: challenge, author: author)
      Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => titulo }, author: author).call
      i.update!(submitted_at: Time.current)
      i
    end
  end

  describe "evaluación" do
    let!(:challenge) do
      as_company(company) do
        c = create(:challenge, name: "Merma", ai_default_mode: "human")
        seed_form!(c.steps.create!(kind: "ideation", position: 1))
        c.steps.create!(kind: "evaluation", position: 2, name: "Técnica", config: { "min_assessments" => 1 })
        c
      end
    end

    before do
      postular!(challenge, author: paula, titulo: "Sensores")
      as_company(company) do
        challenge.pipeline.start!
        challenge.pipeline.advance!
      end
    end

    it "quien administra: consulta a la derecha y los ajustes plegados" do
      sign_in(admin, company: company)
      get challenge_step_path(challenge, paso("evaluation"))

      expect(zonas[:referencia]).to include("Progreso", "Criterios", "Quién evalúa", elena.name, "Cómo quedó configurado")
      expect(zonas[:ajustes]).to include("Ajustes del módulo", "Modo de IA", "Peso")
      expect(documento.at_css(".ajustes details.ajustes__plegable")).not_to be_nil
    end

    it "quien evalúa: la referencia sin la lista de asignaciones, y sin ajustes" do
      sign_in(elena, company: company)
      get challenge_step_path(challenge, paso("evaluation"))

      expect(zonas[:referencia]).to include("Progreso", "Criterios", "Cómo quedó configurado")
      expect(zonas[:referencia]).not_to include("Quién evalúa")
      expect(documento.at_css(".ajustes")).to be_nil
    end

    it "quien participa: tampoco ve asignaciones ni ajustes" do
      sign_in(paula, company: company)
      get challenge_step_path(challenge, paso("evaluation"))

      expect(zonas[:referencia]).to include("Progreso", "Cómo quedó configurado")
      expect(zonas[:referencia]).not_to include("Quién evalúa")
      expect(documento.at_css(".ajustes")).to be_nil
    end

    # La pantalla del módulo terminó de migrar: ningún `.panel` servido. Las
    # tarjetas de adentro de una isla no están en el HTML del servidor.
    it "no sirve ningún panel viejo" do
      sign_in(admin, company: company)
      get challenge_step_path(challenge, paso("evaluation"))

      expect(documento.css(".panel").map { |n| n["class"] }).to eq([])
    end
  end
end
