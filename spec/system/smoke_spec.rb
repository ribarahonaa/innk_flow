# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("spec/system_support/driver")

# Verifica que la infraestructura de system specs funciona: rack_test y
# Chromium real.
#
# LÍMITE CONOCIDO — por qué el recorrido completo NO vive acá:
#
# Los servicios del motor usan `with_lock` (SELECT FOR UPDATE) —PublishVersion,
# Pipeline#start!, Selection#decide!. En un system spec, Rails comparte el pool
# de conexiones entre el hilo del test y el del servidor, y ese lock deadlockea:
# el spec se cuelga SIN dar error, que es lo más caro de diagnosticar.
#
# Desactivar las transacciones (DatabaseCleaner con :deletion) no lo resuelve.
# El recorrido está cubierto en dos lugares que sí funcionan:
#
#   · spec/requests/*  — el flujo completo a nivel HTTP, en milisegundos.
#   · script/capture_screens.js — Playwright contra la app corriendo de verdad,
#     que además deja las capturas en tmp/screenshots/.
RSpec.describe "smoke", type: :system do
  it "carga la pantalla de login" do
    visit login_path

    expect(page).to have_content("innk flow")
    expect(page).to have_field("email")
  end

  it "carga la pantalla de login en un navegador real", :js do
    visit login_path

    expect(page).to have_content("innk flow")
    expect(page).to have_button("Entrar")
  end
end
