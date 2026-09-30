# frozen_string_literal: true

require "rails_helper"

RSpec.describe CriteriaSet do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:challenge) { create(:challenge) }
  let!(:paso) { challenge.steps.create!(kind: "evaluation", position: 1, slug: "evaluacion") }

  # `inline` significa «de ESTE módulo». Sin módulo no significa nada, y el
  # estado era representable: `belongs_to :owner_step, optional: true` y ninguna
  # validación mirando el scope.
  #
  # Lo que costaba: `CriteriaSetPolicy#update?` cae en
  # `administers?(record.owner_step&.challenge)`, y con el módulo en `nil` eso es
  # `administers?(nil)` — que un gestor no pasa nunca y quien administra la
  # empresa pasa siempre, por el `manager?` que corta antes. O sea que un set
  # inline huérfano quedaba editable sólo por una mitad de quienes deberían,
  # decidido por una rama que nadie escribió a propósito.
  #
  # Ningún camino vivo lo produce —los seis lugares que crean un set inline
  # pasan `owner_step_id` en la misma llamada—, así que esto cierra la puerta
  # antes de que alguien la abra, no arregla datos existentes.
  describe "un set inline es de un módulo" do
    it "no se guarda sin el módulo del que es" do
      set = described_class.new(name: "Criterios", scope: "inline")

      expect(set).not_to be_valid
      expect(set.errors[:owner_step].join).to be_present
    end

    it "se guarda con él" do
      set = described_class.new(name: "Criterios", scope: "inline", owner_step: paso)

      expect(set).to be_valid
    end

    # La biblioteca es de la empresa y no cuelga de ningún módulo: pedirle un
    # `owner_step` rompería el camino normal de creación, que es el único que
    # tiene la API (`CriteriaSet.new(scope: "library")`, con el scope
    # hardcodeado y nunca desde params).
    it "y uno de biblioteca no necesita ninguno" do
      set = described_class.new(name: "Vara común", scope: "library")

      expect(set).to be_valid
    end
  end

  # Lo que hace que la validación ALCANCE: si borrar el módulo dejara el
  # `owner_step_id` en `nil` —como hace `ON DELETE SET NULL`, que es lo que usan
  # otras FKs de este esquema— el estado huérfano volvería a ser alcanzable por
  # el costado, sin pasar por ninguna validación. La FK es CASCADE, así que el
  # set se va con su módulo. Es una afirmación sobre la BASE, no sobre el modelo.
  it "borrar el módulo se lleva su set inline, así que no queda huérfano" do
    set = described_class.create!(name: "Criterios", scope: "inline", owner_step: paso)

    paso.destroy!

    expect(described_class.where(id: set.id)).to be_empty
  end
end
