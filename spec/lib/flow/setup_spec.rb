# frozen_string_literal: true

require "rails_helper"

# El paso a paso de dejar un desafío listo.
#
# Los pasos son los MÓDULOS del flujo, no una lista fija: eran dos listas
# distintas —la barra del flujo a la izquierda y los seis pasos de arriba— y
# eso obligaba a traducir mentalmente de una a la otra. «El formulario» y «Los
# criterios» eran además agregaciones de algo que hoy se configura adentro de
# cada módulo, así que dos módulos que puntúan compartían un solo casillero: al
# configurar cualquiera de los dos se resaltaba el mismo.
RSpec.describe Flow::Setup do
  include Rails.application.routes.url_helpers

  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:challenge) { create(:challenge, name: "Merma", brief: "Bajar la merma.") }

  def setup = described_class.new(challenge.reload)
  def step(key) = setup.steps.find { |s| s.key.to_s == key.to_s }
  def paso_de(modulo) = step(modulo.id)

  describe "un desafío recién creado" do
    it "es el brief, el flujo y el cierre: todavía no hay módulos que configurar" do
      expect(setup.steps.map(&:label)).to eq(["El desafío", "El flujo", "Revisar y arrancar"])
      expect(step(:brief)).to be_done
      expect(step(:flow)).not_to be_done
      expect(setup.done_count).to eq(1)
    end

    it "no está listo para arrancar, y dice por qué" do
      expect(setup).not_to be_ready
      expect(setup.blockers.map(&:label)).to eq(["El flujo"])
    end

    it "el paso actual es el primero sin hacer" do
      expect(setup.current.key).to eq(:flow)
    end
  end

  describe "con el flujo armado" do
    let!(:idear) { challenge.steps.create!(kind: "ideation", position: 1, name: "Postulación") }
    let!(:tecnica) { challenge.steps.create!(kind: "evaluation", position: 2, name: "Técnica") }

    it "cada módulo es un paso, con su nombre y en el orden del flujo" do
      expect(setup.steps.map(&:label)).to eq(
        ["El desafío", "El flujo", "Postulación", "Técnica", "Revisar y arrancar"]
      )
      expect(setup.total).to eq(5)
    end

    it "el paso de un módulo lleva a la pantalla de ese módulo" do
      expect(paso_de(idear).path).to eq(challenge_step_path(challenge, idear))
      expect(paso_de(tecnica).path).to eq(challenge_step_path(challenge, tecnica))
    end

    # Es lo que la lista fija no podía distinguir: los dos módulos que puntúan
    # compartían el casillero «Los criterios».
    it "dos módulos del mismo tipo son dos pasos distintos" do
      comite = challenge.steps.create!(kind: "evaluation", position: 3, name: "Comité")

      expect(paso_de(tecnica).key).not_to eq(paso_de(comite).key)
      expect(setup.steps.map(&:label)).to include("Técnica", "Comité")
    end

    it "sigue el orden del flujo y no el de creación" do
      corte = challenge.steps.create!(kind: "selection", position: 1.5, name: "Corte")

      expect(setup.steps.map(&:label)).to eq(
        ["El desafío", "El flujo", "Postulación", "Corte", "Técnica", "Revisar y arrancar"]
      )
      expect(corte).to be_present
    end
  end

  describe "cuándo un módulo cuenta como configurado" do
    let!(:idear) { challenge.steps.create!(kind: "ideation", position: 1, name: "Postulación") }

    # Sin campos nadie puede postular: es el único que traba el arranque, que
    # es exactamente lo que trababa antes el paso «El formulario».
    it "idear necesita campos, y sin ellos traba el arranque" do
      expect(paso_de(idear)).not_to be_done
      expect(paso_de(idear)).to be_blocked
      expect(paso_de(idear).hint).to eq("nadie puede postular")
      expect(setup.blockers.map(&:label)).to eq(["Postulación"])
    end

    it "con campos queda hecho y deja arrancar" do
      seed_form!(idear)

      expect(paso_de(idear.reload)).to be_done
      expect(setup.blockers).to be_empty
      expect(setup).to be_ready
    end

    # Sin set propio se usan los genéricos: es una decisión válida, no un
    # bloqueo. El paso existe para que sea una decisión y no un descubrimiento
    # a mitad de la evaluación.
    it "una evaluación sin criterios propios queda pendiente pero no traba" do
      tecnica = challenge.steps.create!(kind: "evaluation", position: 2, name: "Técnica")
      seed_form!(idear)

      expect(paso_de(tecnica)).not_to be_done
      expect(paso_de(tecnica)).not_to be_blocked
      expect(paso_de(tecnica).hint).to eq("usa los criterios genéricos")
      expect(setup).to be_ready
    end

    it "con criterios propios queda hecha" do
      set = CriteriaSet.create!(name: "Técnicos", scope: "library")
      set.criteria.create!(name: "Impacto", key: "impacto", weight: 1, source: "manual", scale_type: "numeric")
      set.refresh_status!
      tecnica = challenge.steps.create!(kind: "evaluation", position: 2, name: "Técnica", criteria_set: set)

      expect(paso_de(tecnica)).to be_done
      expect(paso_de(tecnica).hint).to eq("1 criterio propio")
    end

    # Los criterios de una selección NO son calificaciones: son filtros, y son
    # opcionales. Lo que hay que decidir es la REGLA DE CORTE.
    it "una selección está hecha cuando la regla de corte está decidida" do
      corte = challenge.steps.create!(kind: "selection", position: 2, name: "Corte")
      seed_form!(idear)

      expect(paso_de(corte)).not_to be_done
      expect(paso_de(corte).hint).to eq("sin regla de corte")
      expect(paso_de(corte)).not_to be_blocked

      corte.update!(config: { "cut" => { "mode" => "top_n", "value" => 3 } })
      expect(paso_de(corte.reload)).to be_done
      # Con la N sin reemplazar, la pista del drawer decía «corte: Top N».
      expect(paso_de(corte.reload).hint).to eq("corte: Top 3")
    end

    # «Manual: el dueño decide» ES una decisión, y una válida.
    it "elegir el corte manual también cuenta como decidido" do
      corte = challenge.steps.create!(kind: "selection", position: 2, name: "Corte",
                                      config: { "cut" => { "mode" => "manual" } })

      expect(paso_de(corte)).to be_done
    end

    it "evolución y reportería nacen hechas: no tienen nada obligatorio" do
      ronda = challenge.steps.create!(kind: "evolution", position: 2, name: "Ronda")
      reporte = challenge.steps.create!(kind: "reporting", position: 3, name: "Cierre")

      expect(paso_de(ronda)).to be_done
      expect(paso_de(reporte)).to be_done
      expect(paso_de(ronda).hint).to eq("nada obligatorio que configurar")
    end

    # Las tres claves del esquema de testing tienen default, así que no hay
    # nada obligatorio que decidir: nace configurado y no traba el arranque.
    # El hint tiene que salir de `dimensiones_de` (vía `StepSettings.efectivo`)
    # y no del `else` genérico: sin config corre con las cinco del default, y
    # con menos elegidas el número baja — así el ejemplo no puede pasar por
    # casualidad con la rama de `estado_de` sacada.
    it "un módulo de testing nace configurado y no traba el arranque" do
      prueba = challenge.steps.create!(kind: "testing", position: 2, name: "Prueba")

      expect(paso_de(prueba)).to be_done
      expect(paso_de(prueba)).not_to be_blocked
      expect(paso_de(prueba).hint).to eq("5 dimensiones a cubrir")
    end

    it "con menos dimensiones elegidas el hint cuenta las que quedaron" do
      prueba = challenge.steps.create!(kind: "testing", position: 2, name: "Prueba",
                                       config: { "dimensions" => %w[tecnica legal] })

      expect(paso_de(prueba)).to be_done
      expect(paso_de(prueba).hint).to eq("2 dimensiones a cubrir")
    end
  end

  describe "moverse por el camino" do
    let!(:idear) { seed_form!(challenge.steps.create!(kind: "ideation", position: 1, name: "Postulación")) }
    let!(:tecnica) { challenge.steps.create!(kind: "evaluation", position: 2, name: "Técnica") }

    it "«siguiente» salta lo que ya está hecho" do
      expect(setup.after(:flow).key).to eq(tecnica.id)
    end

    it "«anterior» es el de al lado, esté hecho o no" do
      expect(setup.before(tecnica.id).key).to eq(idear.id)
    end

    it "numera los pasos contando los módulos" do
      expect(setup.number_of(tecnica.id)).to eq(4)
    end
  end

  describe "con el desafío arrancado" do
    before do
      seed_form!(challenge.steps.create!(kind: "ideation", position: 1, name: "Postulación"))
      challenge.pipeline.start!
    end

    it "«Revisar y arrancar» queda hecho: el camino terminó" do
      expect(step(:finish)).to be_done
      expect(setup.done_count).to eq(setup.total)
    end

    # La pista de este paso tiene una rama para el desafío ya arrancado que NO
    # se renderiza —las dos vistas que instancian `Flow::Setup` guardan por
    # `draft?`— y por eso una revisión la propuso como código muerto. No lo es:
    # la clase sirve este caso, y sin esta línea el único argumento a favor de
    # conservarla era un comentario.
    it "y su pista dice el estado del desafío, no qué van a ver las personas" do
      expect(step(:finish).hint).to eq("En curso")
    end
  end

  # La pantalla de creación dibuja el camino antes de que el desafío exista,
  # así que no puede listar módulos que todavía no hay.
  describe ".outline" do
    it "nombra el tramo de los módulos sin poder listarlos, y termina en el cierre" do
      expect(described_class.outline.map(&:first))
        .to eq(["El desafío", "El flujo", "Cada módulo", "Revisar y arrancar"])
    end
  end
end
