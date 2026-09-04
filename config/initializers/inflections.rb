# frozen_string_literal: true

# Palabras del dominio que Rails no pluraliza como corresponde.
#
#   criteria → sin esto Rails singulariza "criteria" como "criterium" y la
#              asociación `has_many :criteria` busca una clase inexistente.
#   gestores → la pluraliza como "gestors" y singulariza "gestores" como
#              "challenge_gestore". El término es del producto, no del código:
#              es quien acompaña la evolución de las ideas.
ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.irregular "criterion", "criteria"
  inflect.irregular "gestor", "gestores"
end

# La app habla español y Rails pluraliza en inglés: «condición» salía
# «condicións» y «evaluación», «evaluacións», en pantalla y a la vista de todos.
#
# Va en un juego de inflexiones aparte (`:es`) y no sobre el inglés a propósito:
# el de inglés es el que Rails usa para deducir nombres de tabla y de clase, y
# una regla como «consonante → -es» ahí convertiría `user` en `useres`.
#
# Se usa vía Flow::Texto, que es quien pasa el locale. Cubre lo regular del
# español; los invariables (lunes, crisis) quedarían mal, pero no son palabras
# de este dominio.
ActiveSupport::Inflector.inflections(:es) do |inflect|
  inflect.clear

  # Las reglas se anteponen: la última definida es la primera en probarse.
  inflect.plural(/$/, "es")                      # consonante: gestor → gestores
  inflect.plural(/([aeiouáéíóú])$/i, '\1s')      # vocal: idea → ideas
  inflect.plural(/z$/i, "ces")                   # voz → voces

  # Aguda terminada en n, s o l: al sumar la sílaba la tilde deja de hacer
  # falta. condición → condiciones, interés → intereses.
  %w[a e i o u].zip(%w[á é í ó ú]).each do |plana, tildada|
    inflect.plural(/#{tildada}([nsl])$/i, "#{plana}\\1es")
  end
end
