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
