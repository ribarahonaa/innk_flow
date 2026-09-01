# frozen_string_literal: true

require "rails_helper"

# Rubocop custom, pero corriendo en la suite.
#
# `Flow::Tenant.bypass!` y `.unscoped` levantan el aislamiento. Son legítimos en
# jobs, seeds y tasks (donde no hay request que establezca el tenant), y son un
# agujero en cualquier otro lado. Este spec fija dónde pueden aparecer.
RSpec.describe "lint: uso de bypass de tenancy" do
  SCANNED_DIRS = %w[app lib].freeze

  # Rutas donde levantar el scoping es esperable. Cada excepción, con su razón.
  ALLOWED = {
    "app/lib/flow/tenant.rb" => "define el mecanismo",
    "app/models/concerns/tenant_scoped.rb" => "lo consulta para decidir el scope",
    "app/jobs/" => "los jobs entran sin request: reciben company_id y abren el tenant a mano",
    "app/controllers/sessions_controller.rb" => "login y selector de empresa ocurren ANTES de que exista un tenant",
    "app/models/user.rb" => "User es global: \"¿en qué empresas está esta persona?\" es cross-tenant por definición",
    "spec/" => "los specs necesitan montar datos de varias empresas"
  }.freeze

  def ruby_files
    SCANNED_DIRS.flat_map { |dir| Rails.root.glob("#{dir}/**/*.rb") }
  end

  def allowed?(relative_path)
    ALLOWED.keys.any? { |prefix| relative_path.start_with?(prefix) }
  end

  it "bypass! solo aparece donde está autorizado" do
    offenders = ruby_files.filter_map do |path|
      relative = path.relative_path_from(Rails.root).to_s
      next if allowed?(relative)

      lines = path.read.lines.each_with_index.select { |line, _| line.include?("Tenant.bypass") }
      next if lines.empty?

      "#{relative}:#{lines.map { |_, i| i + 1 }.join(',')}"
    end

    expect(offenders).to be_empty, lambda {
      "bypass! fuera de las rutas autorizadas:\n#{offenders.map { |o| "  - #{o}" }.join("\n")}\n\n" \
      "Si el caso es legítimo, sumalo a ALLOWED con la razón escrita."
    }
  end

  it "nadie usa .unscoped para saltar el tenant" do
    # `.unscoped` es peor que bypass!: es invisible en un grep de tenancy y
    # además remueve los scopes de dominio, no solo el de empresa.
    offenders = ruby_files.filter_map do |path|
      relative = path.relative_path_from(Rails.root).to_s
      next if allowed?(relative)

      lines = path.read.lines.each_with_index.select { |line, _| line.match?(/\.unscoped\b/) }
      next if lines.empty?

      "#{relative}:#{lines.map { |_, i| i + 1 }.join(',')}"
    end

    expect(offenders).to be_empty, lambda {
      "Uso de .unscoped:\n#{offenders.map { |o| "  - #{o}" }.join("\n")}\n\n" \
      "Usá Flow::Tenant.bypass! — es explícito y greppable."
    }
  end

  it "ningún modelo declara un default_scope propio que pise el de tenancy" do
    offenders = Rails.root.glob("app/models/**/*.rb").filter_map do |path|
      relative = path.relative_path_from(Rails.root).to_s
      next if relative == "app/models/concerns/tenant_scoped.rb"

      path.read.include?("default_scope") ? relative : nil
    end

    expect(offenders).to be_empty
  end
end
