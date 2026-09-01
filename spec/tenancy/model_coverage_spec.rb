# frozen_string_literal: true

require "rails_helper"

# El spec más valioso del repo: un modelo nuevo SIN decisión explícita de
# tenencia rompe la suite. Es la diferencia entre "nos acordamos de scopear" y
# "el sistema no te deja olvidarte".
#
# innk_r5 acumuló ~50 fugas cross-tenant justamente porque el scoping era una
# convención que había que recordar en cada query.
RSpec.describe "cobertura de tenancy en modelos" do
  # Modelos deliberadamente globales. Cada uno con su razón escrita: agregar
  # algo acá tiene que costar una justificación, no un impulso.
  GLOBAL_MODELS = {
    "Company"  => "es el tenant mismo",
    "User"     => "identidad global: el email es único en toda la instalación y el login ocurre antes de saber la empresa",
    "Identity" => "credencial de un User global; el lookup de login precede a Current.company",
    "Session"  => "se resuelve ANTES de que exista Current.company — es lo que la establece"
  }.freeze

  before { Rails.application.eager_load! }

  let(:domain_models) do
    ApplicationRecord.descendants.reject(&:abstract_class?).reject do |model|
      model.name.nil? || model.name.start_with?("ActiveRecord::", "ActiveStorage::", "ActionText::")
    end
  end

  it "todo modelo de dominio incluye TenantScoped o está en la allowlist" do
    unscoped = domain_models.reject { |m| m.include?(TenantScoped) || GLOBAL_MODELS.key?(m.name) }

    expect(unscoped).to be_empty, lambda {
      "Estos modelos no declaran tenencia:\n" \
      "#{unscoped.map { |m| "  - #{m.name}" }.join("\n")}\n\n" \
      "Incluí TenantScoped, o sumalo a GLOBAL_MODELS con la razón escrita."
    }
  end

  it "todo modelo tenant-scoped tiene la columna company_id" do
    missing = domain_models.select { |m| m.include?(TenantScoped) }
                           .reject { |m| m.column_names.include?("company_id") }

    expect(missing.map(&:name)).to be_empty
  end

  it "ningún modelo de la allowlist incluye TenantScoped por accidente" do
    contradictory = domain_models.select { |m| GLOBAL_MODELS.key?(m.name) && m.include?(TenantScoped) }

    expect(contradictory.map(&:name)).to be_empty
  end
end
