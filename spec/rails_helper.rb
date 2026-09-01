# frozen_string_literal: true

require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"

abort("El entorno de Rails está corriendo en modo producción!") if Rails.env.production?

require "rspec/rails"

Rails.root.glob("spec/support/**/*.rb").sort.each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.fixture_paths = [Rails.root.join("spec/fixtures")]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods
  config.include TenantHelpers
  config.include ActiveJob::TestHelper

  # Cada ejemplo arranca sin tenant. Es deliberado: obliga a que los specs
  # declaren en qué empresa corren (`as_company`) o usen bypass explícito,
  # igual que el código de producción.
  #
  # Va como `around` y no como `before`: los hooks `before` corren DENTRO de
  # los `around` de cada spec, así que un `config.before { Current.reset }`
  # pisaría el `as_company(...)` que el ejemplo acaba de establecer. Los
  # `around` se anidan en orden de registro, así que este envuelve a los demás.
  config.around do |example|
    Current.reset
    example.run
  ensure
    Current.reset
  end
end
