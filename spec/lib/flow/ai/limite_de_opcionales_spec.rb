# frozen_string_literal: true

require "rails_helper"

# La API de Anthropic rechaza con 400 un schema con más de 24 parámetros
# OPCIONALES —toda `properties` que no esté en el `required` de su objeto—
# porque compilar esa gramática le sale caro:
#
#   "Schemas contains too many optional parameters (28), which would make
#    grammar compilation inefficient. Reduce the number of optional
#    parameters in your tool schemas (limit: 24)."
#
# Pasó de verdad, y llegó como un cartel rojo en la pantalla del builder
# cuando alguien le pidió a la IA que propusiera un flujo. Lo rompió sumar el
# sexto `kind`: el schema de `propose_pipeline` arma una variante por kind, y
# cada kind nuevo trae su `ai_mode`, su `config` y los campos de su config.
# Estaba en 23 —UNO por debajo del límite— y pasó a 28.
#
# **Ninguna de las dos suites lo vio**, y no podían: el proveedor por defecto
# es el fixture, que valida contra el mismo schema pero no tiene este límite,
# y el adapter real nunca corre en los tests porque cada llamada cuesta plata.
# Este spec es lo único que mira el número.
#
# Se vigila sólo `propose_pipeline` porque es la única tarea que CRECE con el
# dominio. Medidas las doce al escribir esto: `propose_pipeline` 16,
# `suggest_criteria` 10, `suggest_form_fields` 4, `summarize_challenge` 2, y el
# resto 0 ó 1. Las otras tienen un schema fijo: sumar un kind, un check o un
# criterio no las mueve.
RSpec.describe "el límite de parámetros opcionales de la API" do
  # Lo que cuenta la API: cada `properties` que no esté en el `required` de su
  # propio objeto, recursivo, incluidas las variantes de un `anyOf`.
  LIMITE = 24

  def opcionales(nodo, camino = "")
    return [] unless nodo.is_a?(Hash)

    encontrados = []
    if nodo["properties"].is_a?(Hash)
      obligatorios = Array(nodo["required"])
      nodo["properties"].each do |clave, hijo|
        encontrados << "#{camino}/#{clave}" unless obligatorios.include?(clave)
        encontrados.concat(opcionales(hijo, "#{camino}/#{clave}"))
      end
    end
    encontrados.concat(opcionales(nodo["items"], "#{camino}/items")) if nodo["items"]
    Array(nodo["anyOf"]).each_with_index do |variante, i|
      encontrados.concat(opcionales(variante, "#{camino}/anyOf[#{i}]"))
    end
    encontrados
  end

  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:challenge) { create(:challenge) }

  # Se prueba el detector contra un schema armado a mano: un contador que
  # devuelve siempre cero pasaría este archivo entero sin mirar nada.
  it "el contador encuentra los opcionales y saltea los obligatorios" do
    schema = {
      "type" => "object", "required" => %w[a],
      "properties" => {
        "a" => { "type" => "string" },
        "b" => { "type" => "string" },
        "c" => { "type" => "object", "properties" => { "d" => { "type" => "string" } } }
      }
    }

    expect(opcionales(schema)).to match_array(%w[/b /c /c/d])
  end

  it "el schema de proponer un flujo entra en el límite" do
    schema = Flow::AI::Tasks::ProposePipeline.new(challenge: challenge).schema
    encontrados = opcionales(schema)

    # El `max` no es defensivo de más: RSpec arma el mensaje **aunque la
    # aserción pase**, y `last` con un negativo revienta con ArgumentError —
    # o sea que el spec fallaba justo cuando el schema estaba bien.
    sobran = encontrados.last([encontrados.size - LIMITE, 0].max)

    expect(encontrados.size).to be <= LIMITE,
                                "#{encontrados.size} opcionales (límite #{LIMITE}). " \
                                "Sobran: #{sobran.join(', ')}"
  end

  # El que más crece: cada `kind` nuevo suma los campos de su `config`. Con
  # margen se ve venir; sin margen, el kind siguiente rompe la pantalla.
  it "deja margen para sumar un kind más" do
    schema = Flow::AI::Tasks::ProposePipeline.new(challenge: challenge).schema
    por_kind = opcionales(schema).count { |c| c.include?("/anyOf[0]/") }

    expect(opcionales(schema).size + por_kind).to be <= LIMITE
  end
end
