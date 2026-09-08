# frozen_string_literal: true

require "rails_helper"

# Qué decide el shell: si hay un desafío en contexto se dibuja el flujo, y si
# no, no. La regla mira el CONTEXTO y no el controller — por eso se prueba
# poniendo las ivars a mano, que es exactamente lo que ve el layout.
RSpec.describe ShellHelper, type: :helper do
  let(:company) { without_tenant { create(:company, slug: "acme") } }

  it "sin nada en contexto no hay desafío" do
    as_company(company) { expect(helper.desafio_del_shell).to be_nil }
  end

  it "lo toma de @challenge" do
    as_company(company) do
      desafio = create(:challenge)
      assign(:challenge, desafio)

      expect(helper.desafio_del_shell).to eq(desafio)
    end
  end

  # Dentro de un módulo el desafío no está en una ivar propia: se llega por el
  # paso. Es el caso que importa, porque es donde más falta hace saber en qué
  # parte del flujo estás.
  it "lo deduce del módulo" do
    as_company(company) do
      desafio = create(:challenge)
      paso = desafio.steps.create!(kind: "ideation", position: 1)
      assign(:step, paso)

      expect(helper.desafio_del_shell).to eq(desafio)
    end
  end

  it "y de la idea" do
    as_company(company) do
      desafio = create(:challenge)
      idea = create(:idea, challenge: desafio)
      assign(:idea, idea)

      expect(helper.desafio_del_shell).to eq(desafio)
    end
  end

  # Las pantallas de error se pintan después del `Current.reset`: ahí el
  # drawer no puede consultar los módulos del desafío. Sin este guard, todo
  # 404 adentro de un desafío se cae con MissingTenant.
  it "sin tenant en contexto no dibuja nada, aunque haya desafío" do
    desafio = as_company(company) { create(:challenge) }
    assign(:challenge, desafio)

    # Afuera del `as_company`: es el estado en el que se pinta un 404.
    expect(helper.desafio_del_shell).to be_nil
  end

  # `/challenges/new` deja un `Challenge.new` en @challenge. Sin este guard el
  # drawer le pide `challenge_path` a un desafío sin slug y la pantalla de
  # crear un desafío se cae con UrlGenerationError — un 500 en la primera
  # pantalla del recorrido.
  it "ignora un desafío que todavía no existe" do
    as_company(company) do
      assign(:challenge, Challenge.new(name: "Sin guardar"))

      expect(helper.desafio_del_shell).to be_nil
    end
  end
end
