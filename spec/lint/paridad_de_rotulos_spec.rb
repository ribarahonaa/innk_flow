# frozen_string_literal: true

require "rails_helper"

# Cada enum del dominio tiene su lista de rótulos en `es.yml`, escrita a mano.
# Las dos se desalinean sin que nada avise: `I18n.t` con `default:` se cae al
# `humanize` y muestra el nombre técnico en inglés, y sin `default:` escupe
# «translation missing» — las dos cosas en una pantalla, no en un test.
#
# Pasó, y bloqueó un merge: al sumar el propósito de IA `test_idea` se tocaron
# las tres puertas que CLAUDE.md nombraba —la clase, `AiRun::PURPOSES` y el
# CHECK de Postgres— y quedó una cuarta sin tocar, `flow.ai_purposes`. El
# rótulo salía «Test idea», en inglés, justo en la tarjeta de propuesta, que es
# donde una persona se encuentra con la tarea. Atravesó 1001 ejemplos y dos
# corridas limpias de `make screens`: ningún spec afirmaba la paridad y ninguna
# captura llegaba a renderizar esa tarjeta.
#
# Son siete listas y el peligro es el mismo en las siete, así que se cuidan
# todas: cubrir una sola dejaría seis trampas idénticas armadas.
RSpec.describe "la paridad entre los enums y sus rótulos", type: :lint do
  # Clave de i18n => la constante que manda. La constante es la fuente: si
  # sobra un rótulo es porque alguien sacó un valor del enum y se olvidó del
  # locale, que es igual de confuso que si faltara.
  PARES = {
    "flow.kinds" => -> { ChallengeStep::KINDS },
    "flow.kind_descriptions" => -> { ChallengeStep::KINDS },
    "flow.ai_mode_invites" => -> { ChallengeStep::KINDS },
    "flow.checks" => -> { Flow::Checks::Base::TYPES },
    "flow.ai_purposes" => -> { AiRun::PURPOSES },
    "flow.verdicts" => -> { StepTest::VERDICTS },
    "flow.dimensions" => -> { Flow::Handlers::Testing::DIMENSIONS }
  }.freeze

  PARES.each do |clave, constante|
    it "«#{clave}» tiene un rótulo por cada valor del enum, y ninguno de más" do
      traducidos = I18n.t(clave).keys.map(&:to_s)

      expect(traducidos).to match_array(constante.call)
    end
  end

  # Sin esto, renombrar una clave de i18n dejaría el bloque entero sin mirar y
  # los ejemplos de arriba pasarían sobre una lista vacía.
  it "las siete claves existen de verdad" do
    ausentes = PARES.keys.reject { |clave| I18n.exists?(clave) }

    expect(ausentes).to be_empty
  end
end
