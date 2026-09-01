# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flow::Reports::Builder do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:author) { without_tenant { create(:user, name: "Ana") } }
  let(:evaluator) { without_tenant { create(:user, name: "Eva") } }
  let(:challenge) { create(:challenge, name: "Merma") }

  let!(:ideation) { challenge.steps.create!(kind: "ideation", position: 1, slug: "ideation", name: "Postulación") }
  let!(:tecnica) { challenge.steps.create!(kind: "evaluation", position: 2, slug: "eval_tecnica", name: "Técnica") }
  let!(:seleccion) { challenge.steps.create!(kind: "selection", position: 3, slug: "corte", name: "Corte") }
  let!(:reporte) { challenge.steps.create!(kind: "reporting", position: 4, slug: "reporte", name: "Cierre") }

  let!(:ideas) do
    %w[Alta Media Baja].map.with_index do |name, index|
      idea = create(:idea, challenge: challenge, author: author, status: "active")
      Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => "Idea #{name}" }, author: author).call
      idea.update!(submitted_at: Time.current)

      ideation.step_entries.create!(idea: idea, status: "advanced", input_version_id: idea.current_version_id)
      tecnica.step_entries.create!(idea: idea, status: "done", input_version_id: idea.current_version_id,
                                   result: { "score" => 0.9 - (index * 0.3), "assessments_count" => 2 })
      idea
    end
  end

  subject(:data) { described_class.new(reporte).call }

  describe "embudo" do
    it "cuenta la participación real por módulo" do
      seleccion.step_entries.create!(idea: ideas[0], status: "advanced")
      seleccion.step_entries.create!(idea: ideas[1], status: "eliminated")

      funnel = data["funnel"]
      expect(funnel.map { _1["name"] }).to eq(["Postulación", "Técnica", "Corte", "Cierre"])
      expect(funnel[0]["entered"]).to eq(3)
      expect(funnel[2]["entered"]).to eq(2)
      expect(funnel[2]["eliminated"]).to eq(1)
    end

    it "no incluye módulos posteriores al que genera el reporte" do
      posterior = challenge.steps.create!(kind: "evaluation", position: 5, name: "Después")
      posterior.step_entries.create!(idea: ideas[0], status: "done")

      expect(data["funnel"].map { _1["name"] }).not_to include("Después")
    end
  end

  describe "ranking" do
    it "ordena por puntaje y numera" do
      expect(data["ranking"].map { _1["title"] }).to eq(["Idea Alta", "Idea Media", "Idea Baja"])
      expect(data["ranking"].map { _1["rank"] }).to eq([1, 2, 3])
      expect(data["ranking"].first["score"]).to eq(0.9)
    end

    it "marca cuando la idea cambió después de evaluarse" do
      Flow::Ideas::PublishVersion.new(ideas[0], payload: { "titulo" => "Cambiada" }, author: author).call

      row = data["ranking"].find { _1["idea_id"] == ideas[0].id }
      expect(row["stale"]).to be(true)
      expect(row["version"]).to eq("v1")
      expect(row["current_version"]).to eq("v2")
    end

    it "puede excluir las eliminadas" do
      ideas[2].update!(status: "eliminated", eliminated_at_step_id: seleccion.id)

      scoped = described_class.new(reporte, scope: { "include_eliminated" => "false" }).call
      expect(scoped["ranking"].map { _1["title"] }).not_to include("Idea Baja")
    end
  end

  describe "modo by_version" do
    it "cada celda de la matriz dice sobre qué versión se evaluó" do
      cell = data["matrix"]["rows"].first["cells"].first
      expect(cell["version"]).to eq("v1")
    end

    it "en modo latest la matriz no lleva versión por celda" do
      latest = described_class.new(reporte, scope: { "mode" => "latest" }).call
      expect(latest["matrix"]["rows"].first["cells"].first).not_to have_key("version")
      expect(latest["mode"]).to eq("latest")
    end

    it "NUNCA promedia entre versiones sin decirlo: marca el desfase" do
      Flow::Ideas::PublishVersion.new(ideas[0], payload: { "titulo" => "v2" }, author: author).call

      cell = data["matrix"]["rows"].find { _1["idea_id"] == ideas[0].id }["cells"].first
      expect(cell["stale"]).to be(true)
      expect(cell["version"]).to eq("v1")
    end
  end

  describe "distribución" do
    it "arma un histograma en tramos de 10%" do
      buckets = data["distribution"]
      expect(buckets.size).to eq(10)
      expect(buckets.sum { _1["count"] }).to eq(3)
    end
  end

  describe "participación de evaluadores" do
    it "compara asignados contra los que efectivamente evaluaron" do
      tecnica.step_assignments.create!(user: evaluator, role: "evaluator")
      tecnica.assessments.create!(idea: ideas[0], idea_version_id: ideas[0].current_version_id,
                                  evaluator: evaluator, status: "submitted")

      row = data["evaluators"].first
      expect(row["step"]).to eq("Técnica")
      expect(row["expected"]).to eq(1)
      expect(row["submitted"]).to eq(1)
    end
  end

  describe "el mismo cómputo alimenta el Excel" do
    it "genera un xlsx no vacío" do
      bytes = Flow::Reports::XlsxWriter.new(data).call

      expect(bytes).to be_present
      expect(bytes[0, 2]).to eq("PK"), "un .xlsx es un zip: debe empezar con PK"
    end
  end
end
