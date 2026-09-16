# frozen_string_literal: true

require "rails_helper"

# Ningún controller busca una idea por fuera de `policy_scope`.
#
# Quien participa ve sólo las ideas en las que participa, y lo que no ve da
# 404, no 403: un 403 confirma que la idea existe. Buscarla con
# `@challenge.ideas.find` y autorizar DESPUÉS rompe eso sin que nada lo
# muestre —la idea ajena rebota igual, sólo que con el código equivocado—.
# Pasó en cuatro de los seis lugares que buscaban una idea, y en cada uno
# alguien había escrito el `authorize`: el defecto no es olvidarse de
# autorizar, es el orden.
#
# Donde el `authorize` va primero (`SelectionsController`) no había oráculo,
# pero la guarda no mira el orden: pedir `policy_scope` siempre es más barato
# que auditar a mano en qué orden quedó cada controller.
RSpec.describe "las ideas se buscan por policy_scope", type: :lint do
  BUSCA_UNA_IDEA = /\bideas\.find(_by!?)?\b|\bIdea\.find(_by!?)?\b/.freeze

  it "ningún controller busca una idea sin policy_scope" do
    infractores = Dir[Rails.root.join("app/controllers/**/*.rb")].sort.flat_map do |archivo|
      File.readlines(archivo).each_with_index.filter_map do |linea, indice|
        next if linea.lstrip.start_with?("#")
        next unless linea.match?(BUSCA_UNA_IDEA)
        next if linea.include?("policy_scope(")

        "#{archivo.delete_prefix("#{Rails.root}/")}:#{indice + 1}  #{linea.strip}"
      end
    end

    expect(infractores).to be_empty,
                           "Busca una idea sin policy_scope (a quien participa le confirma que existe):\n  " \
                           "#{infractores.join("\n  ")}"
  end
end
