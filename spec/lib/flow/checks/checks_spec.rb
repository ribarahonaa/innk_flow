# frozen_string_literal: true

require "rails_helper"

# Criterios que verifica el sistema, sin que nadie los puntúe.
RSpec.describe Flow::Checks do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:author) { without_tenant { create(:user) } }
  let(:challenge) { create(:challenge) }
  let!(:ideation) do
    step = challenge.steps.create!(kind: "ideation", position: 1)
    step.form_fields.create!(key: "titulo", label: "Título", field_type: "text")
    step.form_fields.create!(key: "costo", label: "Costo estimado", field_type: "textarea")
    step
  end
  let(:set) { CriteriaSet.create!(name: "Filtros", scope: "inline", owner_step_id: ideation.id) }

  let(:idea) do
    i = create(:idea, challenge: challenge, author: author, status: "active")
    Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" }, author: author).call
    i
  end

  def check(type, config = {})
    set.criteria.create!(name: "Check", key: "c_#{type}", weight: 1,
                         source: "automatic", source_config: { "check" => type }.merge(config))
  end

  describe "field_present" do
    it "pasa cuando el campo tiene contenido" do
      criterion = check("field_present", "field_key" => "titulo")
      expect(criterion.verify(idea)).to be_passed
    end

    it "falla cuando el campo está vacío, y dice por qué" do
      criterion = check("field_present", "field_key" => "costo")
      result = criterion.verify(idea)

      expect(result).not_to be_passed
      expect(result.detail).to eq("sin contenido")
    end

    it "puede exigir un largo mínimo" do
      criterion = check("field_present", "field_key" => "titulo", "min_length" => 50)
      result = criterion.verify(idea)

      expect(result).not_to be_passed
      expect(result.detail).to eq("8 de 50 caracteres")
    end

    it "describe lo que verifica con el label del formulario" do
      criterion = check("field_present", "field_key" => "costo")
      expect(criterion.check.description).to eq("«Costo estimado» está completo")
    end

    it "exige saber qué campo verifica" do
      criterion = set.criteria.new(name: "Roto", key: "roto", weight: 1,
                                   source: "automatic", source_config: { "check" => "field_present" })
      expect(criterion).not_to be_valid
      expect(criterion.errors[:source_config].join).to match(/qué campo/)
    end
  end

  describe "contributors_count" do
    it "cuenta al autor más los colaboradores" do
      criterion = check("contributors_count", "minimum" => 2)
      expect(criterion.verify(idea)).not_to be_passed

      IdeaContributor.create!(idea: idea, user: without_tenant { create(:user) })
      expect(criterion.verify(idea.reload)).to be_passed
    end

    it "no cuenta dos veces a quien creó la idea" do
      contributor = IdeaContributor.new(idea: idea, user: author)
      expect(contributor).not_to be_valid
      expect(contributor.errors[:user_id].join).to match(/ya es quien creó la idea/)
    end
  end

  describe "version_count" do
    it "exige que la idea haya evolucionado" do
      criterion = check("version_count", "minimum" => 2)
      expect(criterion.verify(idea)).not_to be_passed

      Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => "Sensores v2" }, author: author).call
      expect(criterion.verify(idea.reload)).to be_passed
    end
  end

  describe "feedback_addressed" do
    let(:evolution) { challenge.steps.create!(kind: "evolution", position: 2) }

    it "pasa si no recibió feedback" do
      expect(check("feedback_addressed").verify(idea)).to be_passed
    end

    it "falla mientras quede feedback sin atender" do
      FeedbackItem.create!(challenge_step: evolution, idea: idea,
                           idea_version_id: idea.current_version_id,
                           author: author, kind: "question", body: "¿Y el costo?")

      result = check("feedback_addressed").verify(idea.reload)
      expect(result).not_to be_passed
      expect(result.detail).to eq("1 sin atender")
    end
  end

  describe "un check desconocido" do
    it "no deja guardar el criterio" do
      criterion = set.criteria.new(name: "X", key: "x", weight: 1,
                                   source: "automatic", source_config: { "check" => "inventado" })

      expect(criterion).not_to be_valid
      expect(criterion.errors[:source_config].join).to match(/verificación desconocida: inventado/)
    end
  end

  describe "la escala la decide el origen" do
    it "un criterio automático siempre es sí/no" do
      criterion = check("field_present", "field_key" => "titulo")

      expect(criterion.scale_type).to eq("boolean")
      expect(criterion).to be_derived
      expect(criterion).not_to be_answerable
    end

    it "un criterio de fórmula siempre es numérico" do
      criterion = set.criteria.create!(name: "F", key: "f", weight: 0, source: "formula",
                                       scale_type: "letter",
                                       scale_config: { "expression" => "1 + 1", "output" => { "min" => 0, "max" => 10 } })

      expect(criterion.reload.scale_type).to eq("numeric")
      expect(criterion.scale).to be_a(Flow::Scales::Formula)
    end
  end
end
