# frozen_string_literal: true

require "rails_helper"

# El paso a paso de dejar un desafío listo.
#
# Configurar estaba repartido en cinco pantallas que no se anunciaban entre sí:
# armabas el flujo y nada decía «ahora falta el formulario».
RSpec.describe Flow::Setup do
  include Rails.application.routes.url_helpers

  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:challenge) { create(:challenge, name: "Merma", brief: "Bajar la merma.") }

  def setup = described_class.new(challenge.reload)
  def step(key) = setup.steps.find { |s| s.key == key }

  describe "un desafío recién creado" do
    it "tiene el brief hecho y todo lo demás pendiente" do
      expect(step(:brief)).to be_done
      expect(step(:flow)).not_to be_done
      # Los criterios NO cuentan como hechos: sin flujo el paso ni siquiera se
      # puede contestar —los criterios son de los módulos que puntúan— y darlo
      # por hecho es aprobarlo por vacío. Se veía raro en pantalla: «2 de 6»
      # con el paso 4 en verde y el 2 en rojo.
      expect(step(:criteria)).not_to be_done
      expect(step(:criteria).hint).to eq("cuando el flujo tenga módulos")
      expect(setup.done_count).to eq(1)
      expect(setup.total).to eq(6)
    end

    # Con módulos SÍ es una decisión: este flujo no puntúa nada, y está bien.
    it "con un flujo que no puntúa nada, los criterios sí quedan resueltos" do
      seed_form!(challenge.steps.create!(kind: "ideation", position: 1))
      challenge.steps.create!(kind: "reporting", position: 2)

      expect(step(:criteria)).to be_done
      expect(step(:criteria).hint).to eq("ningún módulo puntúa ni filtra")
    end

    it "no está listo para arrancar, y dice por qué" do
      expect(setup).not_to be_ready
      expect(setup.blockers.map(&:label)).to eq(["El flujo"])
    end

    # Es lo que hace que la pantalla pueda decir «seguí por acá».
    it "el paso actual es el primero sin hacer" do
      expect(setup.current.key).to eq(:flow)
    end
  end

  describe "con el flujo armado" do
    before do
      challenge.steps.create!(kind: "ideation", position: 1, name: "Postulación")
      challenge.steps.create!(kind: "evaluation", position: 2, name: "Técnica")
    end

    it "el flujo pasa a hecho y el formulario queda bloqueando" do
      expect(step(:flow)).to be_done
      expect(step(:flow).hint).to eq("2 módulos")
      expect(step(:form)).to be_blocked
      expect(setup.blockers.map(&:key)).to eq([:form])
    end

    it "el paso del formulario lleva a su pantalla" do
      expect(step(:form).path).to eq(challenge_form_path(challenge))
    end

    # Sin set propio se usan los genéricos: es una decisión válida, no un
    # bloqueo. Pero el paso existe para que sea una decisión y no un
    # descubrimiento a mitad de la evaluación.
    it "los criterios aparecen pendientes pero NO bloquean" do
      expect(step(:criteria)).not_to be_done
      expect(step(:criteria)).not_to be_blocked
      expect(step(:criteria).hint).to eq("0 de 1 módulos definidos")
    end

    # Antes llevaba al PRIMER módulo sin criterios. No se veía cuántos módulos
    # puntúan ni en cuál estabas, y al volver atrás aterrizabas en otro porque
    # «el primero sin resolver» había cambiado.
    it "el paso de criterios lleva al índice de los módulos, no a uno" do
      expect(step(:criteria).path).to eq(challenge_criteria_path(challenge))
    end

    it "y la pista habla de MÓDULOS, que es lo que se cuenta" do
      expect(step(:criteria).hint).to eq("0 de 1 módulos definidos")
    end
  end

  describe "con el formulario definido" do
    before do
      seed_form!(challenge.steps.create!(kind: "ideation", position: 1))
      challenge.steps.create!(kind: "evaluation", position: 2)
    end

    it "queda listo para arrancar aunque los criterios sigan genéricos" do
      expect(step(:form)).to be_done
      expect(setup.blockers).to be_empty
      expect(setup).to be_ready
    end

    it "«Siguiente» salta lo que ya está hecho" do
      expect(setup.after(:flow).key).to eq(:criteria)
    end
  end

  describe "con el desafío arrancado" do
    before do
      seed_form!(challenge.steps.create!(kind: "ideation", position: 1))
      challenge.pipeline.start!
    end

    it "revisar y arrancar quedan hechos: el camino terminó" do
      expect(step(:review)).to be_done
      expect(step(:start)).to be_done
      expect(setup.done_count).to eq(setup.total)
    end
  end

  # Un desafío que todavía no tiene «Idear» no puede llevar al formulario:
  # no hay módulo del que colgarlo.
  describe "sin módulo de ideación" do
    before { challenge.steps.create!(kind: "reporting", position: 1) }

    it "el paso del formulario manda al builder y no bloquea" do
      expect(step(:form).path).to eq(builder_challenge_path(challenge))
      expect(step(:form)).not_to be_blocked
    end
  end
end
