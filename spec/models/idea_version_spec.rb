# frozen_string_literal: true

require "rails_helper"

RSpec.describe IdeaVersion do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  # El CHECK de Postgres es una segunda puerta: sin la migración, el modelo
  # valida y la base rechaza igual, con un error truncado.
  it "acepta una versión escrita por un taller" do
    as_company(company) do
      idea = create(:idea)
      version = idea.versions.new(number: 1, title: "T", payload: {}, actor_type: "workshop")

      expect(version).to be_valid
      expect { version.save! }.not_to raise_error
    end
  end
end
