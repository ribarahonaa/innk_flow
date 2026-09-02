# frozen_string_literal: true

# Esperas para navegación con Turbo.
#
# EL BUG QUE ESTO EVITA: Turbo pinta la copia CACHEADA de una página mientras
# pide la definitiva. Si el clic cae en esa ventana, Capybara toma un elemento
# que Turbo está por reemplazar y Playwright falla con «Element is not attached
# to the DOM». Es intermitente por definición: depende de si la respuesta llegó
# antes o después del clic, así que aparece una de cada cinco corridas y solo
# con la suite completa, donde la máquina está más cargada.
#
# `<html data-turbo-preview>` es la señal que Turbo deja mientras muestra esa
# copia. Esperar a que se vaya es determinista; un `sleep` no lo sería.
module TurboWaits
  def click_link_settled(locator, **options)
    wait_for_turbo
    click_link(locator, **options)
  end

  def wait_for_turbo
    expect(page).to have_no_css("html[data-turbo-preview]", wait: 10)
  end
end

RSpec.configure do |config|
  config.include TurboWaits, type: :system
end
