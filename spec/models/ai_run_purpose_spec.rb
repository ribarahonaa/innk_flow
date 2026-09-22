# frozen_string_literal: true

require "rails_helper"

# El propósito vive en el modelo Y en un CHECK de Postgres. El spec prueba los
# dos: la validación de Rails con un `valid?`, y el CHECK saltándose la
# validación, porque es la única forma de ver si la base lo acepta.
RSpec.describe AiRun do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:challenge) { create(:challenge) }

  it "acepta el propósito test_idea" do
    run = described_class.new(challenge: challenge, purpose: "test_idea",
                              mode: "ai_assisted", status: "queued")

    expect(run).to be_valid
  end

  it "la base también lo acepta, no sólo la validación" do
    run = described_class.new(challenge: challenge, purpose: "test_idea",
                              mode: "ai_assisted", status: "queued")

    expect { run.save!(validate: false) }.not_to raise_error
  end
end
