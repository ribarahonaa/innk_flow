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

    # Las iniciales de una persona, largas lo justo para no repetirse dentro
    # del grupo con el que van a convivir.
    #
    # «Elena Evaluadora» y «Emilio Evaluador» daban las dos «EE»: en la tabla
    # de evaluación el chip no distinguía a dos personas, y el nombre completo
    # estaba sólo en el `title`, que es de hover.
    #
    # Se estira el nombre de PILA, sólo él y sólo cuando choca —«ElE» y «EmE»,
    # con «GG» quieto al lado—: así la tabla no se ensancha por las dudas.
    # Quién entra en `among` importa: tiene que ser el grupo del MÓDULO y no el
    # de la fila, o la misma persona saldría «EE» en una idea y «ElE» en otra.
    #
    # Lo que NO resuelve: dos personas con el mismo nombre de pila y la misma
    # inicial de apellido —«Ana Admin» y «Ana Álvarez»— siguen chocando. Ahí ya
    # no alcanza con estirar el nombre de pila.
    def initials(name, among: [])
      partes = name.to_s.split
      return "" if partes.empty?

      rivales = among.map { |otro| otro.to_s.split }
                     .reject { |otro| otro.empty? || otro == partes }
      largo = (1..partes.first.length).find do |n|
        rivales.none? { |otro| sigla(otro, n) == sigla(partes, n) }
      end
      sigla(partes, largo || partes.first.length)
    end

    # Una letra por palabra, con `largo` letras para la primera.
    def sigla(partes, largo)
      partes.first[0, largo].capitalize + partes.drop(1).map { |p| p[0] }.join.upcase
    end
    private_class_method :sigla
  end
end
