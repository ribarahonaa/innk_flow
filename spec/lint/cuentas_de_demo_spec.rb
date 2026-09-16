# frozen_string_literal: true

require "rails_helper"

# La pantalla de login lista las cuentas sembradas con su rol, y se entra por
# ahí a ver el producto desde cada uno. Una cuenta que se llama por un rol que
# no tiene manda a la persona al rol equivocado, y el nombre es lo único que
# tiene para elegir.
#
# Pasó: `gestor@demo.test` estaba sembrada con rol `admin` mientras
# `guia@demo.test` era la única con rol `gestor`. No lo atrapaba nada porque el
# seed no tiene specs y la pantalla muestra el rol REAL: el que miente es el
# nombre.
#
# Se lee el seed como texto a propósito: correrlo entero cuesta y lo que hay
# que auditar es lo que está escrito ahí, no lo que quedó en una base.
RSpec.describe "las cuentas de demo", type: :lint do
  # Las filas del hash `people`: "correo" => ["Nombre", "rol"].
  FILA_DE_CUENTA = /"([^"@]+)@demo\.test"\s*=>\s*\[[^\]]*"(\w+)"\s*\]/.freeze

  let(:cuentas) do
    File.read(Rails.root.join("db/seeds.rb")).scan(FILA_DE_CUENTA).map { |local, rol| [local, rol] }
  end

  it "el seed siembra cuentas de demo" do
    expect(cuentas).not_to be_empty
  end

  # La regla es sobre el nombre, no sobre el rol: `eval1` o `guia` no son
  # roles, así que no prometen ninguno. `gestor` sí.
  it "ninguna se llama por un rol que no tiene" do
    mentirosas = cuentas.filter_map do |local, rol|
      nombrado = local.sub(/\d+\z/, "")
      next unless Membership::ROLES.include?(nombrado)

      "#{local}@demo.test dice «#{nombrado}» y tiene rol «#{rol}»" unless nombrado == rol
    end

    expect(mentirosas).to be_empty, "Cuentas de demo con el rol cambiado:\n  #{mentirosas.join("\n  ")}"
  end

  # Cada rol que existe se puede probar entrando: si ninguna cuenta lo tiene,
  # esa parte del producto no se puede ver sin tocar la base a mano.
  it "hay una cuenta por cada rol" do
    expect(cuentas.map(&:last).uniq).to match_array(Membership::ROLES)
  end
end
