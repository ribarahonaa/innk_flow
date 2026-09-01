# frozen_string_literal: true

# Sin esto, Rails singulariza "criteria" como "criterium" y la asociación
# `has_many :criteria` busca una clase Criterium inexistente.
ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.irregular "criterion", "criteria"
end
