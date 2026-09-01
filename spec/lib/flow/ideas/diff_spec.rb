# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flow::Ideas::Diff do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:challenge) { create(:challenge) }
  let(:step) { challenge.steps.create!(kind: "ideation", position: 1) }
  let!(:fields) do
    [
      step.form_fields.create!(key: "titulo", label: "Título", field_type: "text", position: 0),
      step.form_fields.create!(key: "problema", label: "Problema", field_type: "textarea", position: 1)
    ]
  end
  let(:idea) { create(:idea, challenge: challenge) }

  def version_with(payload)
    Flow::Ideas::PublishVersion.new(idea, payload: payload).call.version
  end

  it "detecta un campo modificado" do
    a = version_with({"titulo" => "Sensores", "problema" => "Merma alta"})
    b = version_with({"titulo" => "Sensores IoT", "problema" => "Merma alta"})

    changes = described_class.new(a, b, fields: fields).changes
    expect(changes.size).to eq(1)
    expect(changes.first).to have_attributes(key: "titulo", label: "Título",
                                             from: "Sensores", to: "Sensores IoT", kind: :changed)
  end

  it "distingue agregado de vaciado" do
    a = version_with({"titulo" => "T"})
    b = version_with({"titulo" => "T", "problema" => "Nuevo"})
    c = version_with({"titulo" => "T", "problema" => ""})

    expect(described_class.new(a, b, fields: fields).changes.first.kind).to eq(:added)
    expect(described_class.new(b, c, fields: fields).changes.first.kind).to eq(:removed)
  end

  it "no reporta nada entre versiones idénticas" do
    a = version_with({"titulo" => "T", "problema" => "P"})
    expect(described_class.new(a, a, fields: fields)).not_to be_any
  end

  it "resume los cambios en una frase" do
    a = version_with({"titulo" => "T"})
    b = version_with({"titulo" => "T2", "problema" => "P"})

    expect(described_class.new(a, b, fields: fields).summary).to eq("1 agregado, 1 modificado")
  end

  it "ordena los cambios según el formulario" do
    a = version_with({"titulo" => "A", "problema" => "A"})
    b = version_with({"titulo" => "B", "problema" => "B"})

    expect(described_class.new(a, b, fields: fields).changes.map(&:key)).to eq(%w[titulo problema])
  end

  it "incluye claves que ya no están en el formulario" do
    # Un campo eliminado del formulario después: el histórico igual lo muestra.
    a = version_with({"titulo" => "A", "campo_viejo" => "valor"})
    b = version_with({"titulo" => "A"})

    changes = described_class.new(a, b, fields: fields).changes
    expect(changes.map(&:key)).to include("campo_viejo")
  end
end
