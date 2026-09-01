require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "sprockets/railtie"

Bundler.require(*Rails.groups)

module InnkFlow
  class Application < Rails::Application
    config.load_defaults 7.1

    # `lib/` autoloadeado (Rails 7.1+). Ahí vive Flow::MigrationHelpers, que las
    # migraciones necesitan resolver.
    config.autoload_lib(ignore: %w[assets tasks])

    # ─────────────────────────────────────────────────────────────────────
    # DECISIÓN DE FASE 0, NO REVERSIBLE BARATO:
    #
    # La defensa de tenancy que sostiene todo el modelo son FKs COMPUESTAS
    # (idea_id, company_id) -> ideas(id, company_id). `schema.rb` no sabe
    # serializarlas: se perderían en cada `db:prepare` y la garantía se
    # evaporaría en silencio. Por eso el schema canónico es SQL.
    #
    # Costo aceptado: db/structure.sql genera más ruido en los diffs.
    # ─────────────────────────────────────────────────────────────────────
    config.active_record.schema_format = :sql

    config.time_zone = "America/Santiago"
    config.active_record.default_timezone = :utc

    config.i18n.default_locale = :es
    config.i18n.available_locales = %i[es en]
    config.i18n.fallbacks = [:es]

    config.active_job.queue_adapter = :sidekiq

    # `app/lib/flow/ai/` define Flow::AI, no Flow::Ai. Sin esto Zeitwerk
    # espera la constante mal capitalizada y falla al autoloadear.
    Rails.autoloaders.each do |loader|
      loader.inflector.inflect("ai" => "AI")
    end

    config.generators do |g|
      g.orm :active_record, primary_key_type: :uuid
      g.test_framework :rspec, fixture: false
      g.helper false
      g.assets false
      g.template_engine :haml
    end
  end
end
