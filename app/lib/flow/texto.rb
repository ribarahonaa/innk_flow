# frozen_string_literal: true

module Flow
  # Texto en español para la pantalla.
  #
  # `String#pluralize` usa el juego de inflexiones inglés salvo que se le pase
  # el locale, y olvidarse es exactamente cómo aparecieron «condicións» y
  # «evaluacións» en producción de la maqueta. Acá se pasa una sola vez.
  module Texto
    module_function

    # "3 ideas" · "1 idea"
    def contar(cantidad, palabra) = "#{cantidad} #{plural(palabra, cantidad)}"

    def plural(palabra, cantidad = 2) = palabra.pluralize(cantidad, :es)
  end
end
