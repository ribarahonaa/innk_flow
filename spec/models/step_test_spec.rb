# frozen_string_literal: true

require "rails_helper"

RSpec.describe StepTest do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:challenge) { create(:challenge) }
  let!(:paso) { challenge.steps.create!(kind: "testing", position: 1, slug: "testeo") }
  let(:idea) do
    i = create(:idea, challenge: challenge, status: "active")
    Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" }).call
    i.reload
  end

  def testear(atributos = {})
    described_class.create!({ challenge_step: paso, idea: idea,
                              idea_version_id: idea.current_version_id,
                              verdict: "factible", tested_at: Time.current }.merge(atributos))
  end

  it "acepta los tres veredictos" do
    %w[factible con_reservas no_factible].each do |veredicto|
      expect { testear(verdict: veredicto) }.not_to raise_error
      described_class.delete_all
    end
  end

  # La unicidad del vigente NO es una validación de Rails: es un índice parcial.
  # Se prueba contra la base porque es ahí donde vive la garantía — una
  # validación se saltea con `save(validate: false)` o con un camino de
  # escritura nuevo, el índice no.
  it "la base rechaza dos testeos vigentes para la misma idea" do
    testear

    expect { testear }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "pero acepta otro si el anterior quedó superado" do
    primero = testear
    primero.update!(superseded_at: Time.current)

    expect { testear(verdict: "no_factible") }.not_to raise_error
    expect(described_class.vigentes.count).to eq(1)
  end

  it "el nombre de quien testeó dice «IA» cuando la dejó la IA" do
    expect(testear(actor_type: "ai").tested_by_name).to eq("IA")
  end
end
