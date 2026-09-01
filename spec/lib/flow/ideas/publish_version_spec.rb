# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flow::Ideas::PublishVersion do
  let(:company) { without_tenant { create(:company) } }
  let(:user) { without_tenant { create(:user) } }

  around { |example| as_company(company) { example.run } }

  let(:challenge) { create(:challenge) }
  let!(:step) do
    s = challenge.steps.create!(kind: "ideation", position: 1)
    s.form_fields.create!(key: "titulo", label: "Título", field_type: "text", config: { "is_title" => true })
    s.form_fields.create!(key: "problema", label: "Problema", field_type: "textarea")
    s
  end
  let(:idea) { create(:idea, challenge: challenge, author: user) }

  def publish(payload, **options)
    described_class.new(idea, payload: payload, author: user, **options).call
  end

  it "crea la v1 y la deja como versión vigente" do
    result = publish({"titulo" => "Sensores IoT", "problema" => "No sabemos dónde se pierde"})

    expect(result).to be_ok
    expect(result.version.number).to eq(1)
    expect(idea.reload.current_version_id).to eq(result.version.id)
    expect(idea.title).to eq("Sensores IoT")
  end

  it "numera las versiones en orden" do
    publish({"titulo" => "A"})
    publish({"titulo" => "B"})
    result = publish({"titulo" => "C"})

    expect(result.version.number).to eq(3)
    expect(idea.reload.versions.map(&:number)).to eq([1, 2, 3])
  end

  it "guarda el snapshot COMPLETO, no un diff" do
    publish({"titulo" => "A", "problema" => "X"})
    publish({"titulo" => "B", "problema" => "X"})

    expect(idea.reload.versions.map(&:payload)).to eq(
      [{ "titulo" => "A", "problema" => "X" }, { "titulo" => "B", "problema" => "X" }]
    )
  end

  it "NO crea una versión si el contenido no cambió" do
    # El historial tiene que significar algo, no llenarse de guardados iguales.
    publish({"titulo" => "A", "problema" => "X"})

    expect { publish({"titulo" => "A", "problema" => "X"}) }
      .not_to change { idea.reload.versions.count }
  end

  it "registra quién y desde qué módulo" do
    result = publish({ "titulo" => "A" }, source_step: step, change_note: "Ajusté el alcance")

    expect(result.version.created_by_id).to eq(user.id)
    expect(result.version.source_step_id).to eq(step.id)
    expect(result.version.change_note).to eq("Ajusté el alcance")
    expect(result.version.actor_type).to eq("human")
  end

  it "marca las versiones generadas por IA" do
    result = described_class.new(idea, payload: { "titulo" => "A" }, actor_type: "ai").call

    expect(result.version).to be_by_ai
    expect(result.version.author_name).to eq("IA")
  end

  describe "inmutabilidad" do
    it "una versión publicada no se puede editar" do
      version = publish({"titulo" => "Original"}).version

      version.title = "Alterada"
      expect(version).not_to be_valid
      expect(version.errors.full_messages.join).to match(/inmutable/)
    end

    it "la unicidad de número está en la base" do
      publish({"titulo" => "A"})

      expect do
        idea.versions.new(number: 1, payload: {}).save!(validate: false)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
