# frozen_string_literal: true

# NO vive en spec/support/: rails_helper carga ese directorio entero, y cargar
# capybara/rspec + el driver de Playwright en TODA la suite hace que los specs
# de modelo y request se cuelguen. Se requiere solo desde spec/system/.
require "capybara/rspec"
require "capybara-playwright-driver"

# Chromium vive solo en Dockerfile.test.
#
# La versión del paquete npm DEBE coincidir con la de playwright-ruby-client
# (ver Dockerfile.test): con versiones distintas el driver igual "funciona",
# pero cada spec pierde ~2 minutos reintentando el handshake del protocolo.
Capybara.register_driver(:flow_chromium) do |app|
  Capybara::Playwright::Driver.new(
    app,
    browser_type: :chromium,
    headless: ENV["HEADLESS"] != "false",
    args: %w[--no-sandbox --disable-dev-shm-usage]
  )
end

Capybara.default_driver = :rack_test
Capybara.javascript_driver = :flow_chromium
Capybara.default_max_wait_time = 8
Capybara.server = :puma, { Silent: true }

RSpec.configure do |config|
  # Driver por defecto: rack_test. Es deliberado.
  #
  # Casi todas las pantallas de la maqueta son server-rendered, y rack_test
  # las verifica en milisegundos sin levantar un servidor en otro hilo — lo
  # que además evita el clásico deadlock de transactional fixtures + Puma.
  #
  # Solo lo marcado `js: true` (la isla Vue del builder) usa Chromium real.
  config.before(:each, type: :system) { driven_by :rack_test }
  config.before(:each, type: :system, js: true) { driven_by :flow_chromium }
end
