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

    # "Faltan 3 ideas" · "Falta 1 idea"
    #
    # `contar` acuerda el sustantivo y con eso no alcanza: la frase que lo
    # envuelve trae su propio verbo, y quien la escribe lo deja en plural
    # porque está pensando en el caso de varios. «Faltan 1 idea por testear»
    # llegó así a la pantalla.
    #
    # Cero es plural en español: «Faltan 0 ideas».
    def faltan(cantidad, palabra)
      "#{cantidad == 1 ? 'Falta' : 'Faltan'} #{contar(cantidad, palabra)}"
    end

    def plural(palabra, cantidad = 2) = palabra.pluralize(cantidad, :es)
  end
end
