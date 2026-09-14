# frozen_string_literal: true

require "rails_helper"

# El camino de configurar un desafío, dibujado en UN solo lugar: el flujo de la
# izquierda.
#
# Estuvo en dos: la barra lateral con los módulos y una tarjeta arriba con los
# pasos. Cuando los pasos pasaron a ser los módulos, las dos listas mostraban
# lo mismo y la de arriba —con siete módulos— se partía en dos filas y se comía
# la pantalla. Se fue la tarjeta y el flujo absorbió lo que ella sabía: el ✓ de
# cada módulo y la pista de qué le falta.
#
# Mientras el desafío está EN BORRADOR el flujo es el camino de configuración;
# una vez arrancado vuelve a ser el mapa de lo que está corriendo.
RSpec.describe "el camino de configuración", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  let!(:admin) do
    without_tenant do
      u = create(:user, email: "admin@test.dev")
      create(:membership, company: company, user: u, role: "admin")
      u
    end
  end

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma", brief: "Bajar la merma.")
      seed_form!(c.steps.create!(kind: "ideation", position: 1, name: "Postulación"))
      c.steps.create!(kind: "evolution", position: 2, name: "Ronda")
      c.steps.create!(kind: "evaluation", position: 3, name: "Técnica")
      c.steps.create!(kind: "selection", position: 4, name: "Corte")
      c.steps.create!(kind: "evaluation", position: 5, name: "Comité")
      c.steps.create!(kind: "reporting", position: 6, name: "Cierre")
      c
    end
  end

  def modulo(nombre) = as_company(company) { challenge.steps.reload.find { |s| s.name == nombre } }
  def drawer = response.body[/<aside class="flow-drawer.*?<\/aside>/m]
  def resaltado = drawer[/<a[^>]*menu-active[^>]*>.*?<\/a>/m]

  before { sign_in(admin, company: company) }

  describe "en borrador" do
    it "el flujo es el camino entero: el desafío, los módulos y el cierre" do
      get challenge_path(challenge)

      expect(drawer).to include("El desafío", "El flujo")
      expect(drawer).to include("Postulación", "Ronda", "Técnica", "Corte", "Comité", "Cierre")
      expect(drawer).to include("Revisar y arrancar")
    end

    it "dice qué le falta a cada módulo, que es lo que sabía la tarjeta" do
      get challenge_path(challenge)

      expect(drawer).to include("usa los criterios genéricos")
      expect(drawer).to include("sin regla de corte")
    end

    it "y cuánto del camino está hecho" do
      get challenge_path(challenge)

      expect(drawer).to match(/\d+ de \d+/)
    end

    # La tarjeta de arriba se fue de TODAS las pantallas: mostrar el mismo
    # camino dos veces en la misma pantalla era el problema.
    %w[Postulación Técnica Cierre].each do |nombre|
      it "la pantalla de «#{nombre}» ya no repite el camino arriba" do
        get challenge_step_path(challenge, modulo(nombre))

        expect(response.body).not_to include("setup__step")
      end
    end

    it "la ficha del desafío tampoco lo repite" do
      get challenge_path(challenge)

      expect(response.body).not_to include("setup__step")
    end

    %w[Postulación Ronda Técnica Corte Comité Cierre].each do |nombre|
      it "la pantalla de «#{nombre}» se resalta a sí misma en el flujo" do
        get challenge_step_path(challenge, modulo(nombre))

        expect(resaltado).to include(nombre)
      end
    end

    # El caso que la lista fija anterior no podía representar: dos módulos que
    # puntúan compartían un solo casillero.
    it "dos evaluaciones se resaltan por separado" do
      get challenge_step_path(challenge, modulo("Técnica"))
      tecnica = resaltado

      get challenge_step_path(challenge, modulo("Comité"))
      comite = resaltado

      expect(tecnica).to include("Técnica")
      expect(comite).to include("Comité")
      expect(tecnica).not_to eq(comite)
    end

    it "el builder se resalta en «El flujo»" do
      get builder_challenge_path(challenge)

      expect(resaltado).to include("El flujo")
    end

    it "la previsualización se resalta en el cierre" do
      get challenge_preview_path(challenge)

      expect(resaltado).to include("Revisar y arrancar")
    end

    # `setup_nav` es lo único que queda para avanzar: sin su render en una
    # pantalla, ahí se corta el recorrido y la suite no lo detecta sola.
    %w[Postulación Ronda Técnica Corte Comité Cierre].each do |nombre|
      it "la pantalla de «#{nombre}» ofrece cómo seguir" do
        get challenge_step_path(challenge, modulo(nombre))

        expect(response.body).to include("setup-nav")
      end
    end
  end

  describe "con el desafío arrancado" do
    before { as_company(company) { challenge.pipeline.start! } }

    it "el flujo vuelve a ser el mapa de lo que corre: sin el cierre ni el camino" do
      get challenge_path(challenge)

      expect(drawer).to include("Postulación", "Técnica")
      expect(drawer).not_to include("Revisar y arrancar")
      expect(drawer).not_to include("El desafío")
    end
  end
end
