# frozen_string_literal: true

require "rails_helper"

# El paso a paso de configuración, dibujado.
#
# Los pasos son los módulos del flujo, así que cada pantalla de configuración
# tiene que resaltar EL SUYO. Con la lista fija anterior las cinco pantallas
# pasaban una clave escrita a mano y sólo había cuatro para repartir: evolución
# y reportería decían ser «El flujo», y los dos módulos que puntúan decían ser
# «Los criterios» —o sea que en un desafío con dos evaluaciones, configurar
# cualquiera de las dos resaltaba el mismo casillero—.
#
# Y las de evolución y reportería dibujaban el paso a paso sin su pie, así que
# el recorrido se cortaba ahí. Con la lista fija eso era el final del camino;
# con un paso por módulo es un agujero en el medio.
RSpec.describe "el paso a paso de configuración", type: :request do
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

  # El casillero resaltado, tal como lo marca `shared/_setup_progress`.
  def resaltado(html)
    html[/<li[^>]*setup__step--current[^>]*>.*?<\/li>/m]
  end

  before { sign_in(admin, company: company) }

  it "lista los módulos del flujo como pasos, con sus nombres" do
    get challenge_path(challenge)

    expect(response.body).to include("Postulación", "Ronda", "Técnica", "Corte", "Comité", "Cierre")
    expect(response.body).to include("Revisar y arrancar")
  end

  %w[Postulación Ronda Técnica Corte Comité Cierre].each do |nombre|
    it "la pantalla de «#{nombre}» resalta su propio módulo" do
      paso = modulo(nombre)
      get challenge_step_path(challenge, paso)

      expect(resaltado(response.body)).to include(nombre)
    end
  end

  # El caso que la lista fija no podía representar.
  it "dos evaluaciones resaltan casilleros distintos" do
    get challenge_step_path(challenge, modulo("Técnica"))
    tecnica = resaltado(response.body)

    get challenge_step_path(challenge, modulo("Comité"))
    comite = resaltado(response.body)

    expect(tecnica).to include("Técnica")
    expect(comite).to include("Comité")
    expect(tecnica).not_to eq(comite)
  end

  # `setup_nav` necesita que quien lo renderiza le pase el `current` que le
  # toca: sin ese render no hay ningún «siguiente →» que ofrecer, y la suite no
  # lo detecta sola —pasó de verdad con el paso del formulario—.
  %w[Postulación Ronda Técnica Corte Comité Cierre].each do |nombre|
    it "la pantalla de «#{nombre}» ofrece cómo seguir" do
      get challenge_step_path(challenge, modulo(nombre))

      expect(response.body).to include("setup-nav")
    end
  end

  it "el flujo de la izquierda termina en el mismo cierre que el paso a paso" do
    get challenge_path(challenge)

    drawer = response.body[/<aside class="flow-drawer.*?<\/aside>/m]
    expect(drawer).to include("Revisar y arrancar")
  end
end
