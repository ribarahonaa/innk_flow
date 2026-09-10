# frozen_string_literal: true

require "rails_helper"

# Requisito del diseño: un módulo se configura en UN solo lugar.
#
# No alcanza con haberlo hecho una vez. Configurar estaba repartido en seis
# pantallas que se fueron sumando de a una, cada una razonable por su cuenta.
# Esto cuenta declaraciones de isla en vez de confiar en que el diff se vea
# bien, que es lo que falló las seis veces.
RSpec.describe "una sola vista de configuración", type: :lint do
  def vistas_con(isla)
    # Busca declaraciones de isla en dos sintaxis HAML equivalentes:
    # - Explícita: %div{ "data-island": "form-editor" }
    # - Anidada:   %div{ data: { island: "form-editor" } }
    # (Rails renderiza ambas como data-island="..." en HTML)
    pattern = /"data-island":\s*"#{Regexp.escape(isla)}"|data:\s*\{.*?\bisland:\s*"#{Regexp.escape(isla)}"/m
    Dir[Rails.root.join("app/views/**/*.haml")].select do |archivo|
      File.read(archivo).match?(pattern)
    end.map { |a| a.sub("#{Rails.root}/", "") }
  end

  it "el editor de campos vive en una sola vista" do
    expect(vistas_con("form-editor")).to contain_exactly("app/views/steps/_campos_editor.html.haml")
  end

  # Dos: la cara de configuración del módulo, y el form de la biblioteca. La
  # biblioteca no es la configuración de un módulo: es el CRUD de otro objeto,
  # para reusar un set entre desafíos distintos.
  it "el editor de criterios vive en la cara del módulo y en la biblioteca" do
    expect(vistas_con("criteria-editor"))
      .to contain_exactly("app/views/steps/_criterios_editor.html.haml",
                          "app/views/criteria_sets/_form.html.haml")
  end

  it "los ajustes del módulo viven en una sola vista" do
    expect(vistas_con("step-settings"))
      .to contain_exactly("app/views/steps/config/_modulo.html.haml")
  end

  # El panel del builder era la primera de las seis. Esta guarda pide que no
  # haya vuelto a aparecer bajo esos nombres: detecta si quien escribió el código
  # reintrodujo la configuración con otros nombres de clase.
  it "el builder no volvió a tener panel de configuración" do
    builder = File.read(Rails.root.join("app/javascript/components/pipeline_builder/pipeline_builder.vue"))

    expect(builder).not_to include("builder__config")
    expect(builder).not_to include("step-config")
  end
end
