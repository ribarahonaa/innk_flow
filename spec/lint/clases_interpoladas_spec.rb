# frozen_string_literal: true

require "rails_helper"

# Tailwind escanea TEXTO. Una clase construida así:
#
#     %span{ class: "status-chip--#{step.status}" }
#
# no existe para el escáner: no la ve, no la genera, y la pantalla queda con
# un elemento sin estilos. En el DOM se ve bien; en pantalla, no.
#
# La regla es que el nombre completo esté escrito en algún lado. Los helpers
# de EstilosHelper lo hacen, y de paso dejan la traducción estado -> estilo en
# un solo lugar en vez de repartida en ternarios por 24 archivos.
#
# LAS ISLAS CUENTAN. Tailwind escanea `app/javascript` igual que `app/views`
# (los `@source` de la hoja lo declaran explícito), así que un componente Vue
# que arme la clase con un template literal tiene el mismo problema y ninguna
# otra prueba lo dice. La guarda miraba solo el HAML y en el builder había una
# viva: `:class="\`status-chip--${step.status}\`"`. Ahí la clase la manda el
# server —`PipelinePresenter` la resuelve con el mismo `chip_de_estado` que las
# vistas— y la isla solo la liga.
RSpec.describe "clases CSS interpoladas", type: :lint do
  # Un patrón por lenguaje: HAML interpola con `#{}` adentro de comillas y Vue
  # con `${}` adentro de un template literal.
  #
  # El de Vue arranca en la palabra `class` y no en `:class=`, así que cubre
  # las cuatro formas de nombrar una clase en un componente: el binding
  # (`:class` / `v-bind:class`), la sintaxis de arreglo, la de objeto con clave
  # calculada, y una `class`/`className` armada en el `<script>` y ligada
  # después. Lo que va entre medio no puede tener `>` ni pasar de 40 caracteres:
  # sin ese tope, un `<div class="x">{{ `${a}` }}</div>` —donde el literal no
  # arma ninguna clase— se marcaba igual.
  # El de `.js` usa el mismo patrón que `.vue`: un `.js` plano no tiene sintaxis
  # de binding propia, pero arma clases del mismo modo —un template literal— y
  # con la misma trampa.
  PATRONES = {
    ".haml" => /class[:=][^,)]*"[^"]*\#\{/,
    ".vue" => /class[^`\n>]{0,40}`[^`]*\$\{/,
    ".js" => /class[^`\n>]{0,40}`[^`]*\$\{/
  }.freeze

  ARCHIVOS = Rails.root.glob("app/views/**/*.haml") +
             Rails.root.glob("app/javascript/**/*.vue") +
             Rails.root.glob("app/javascript/**/*.js")

  it "ninguna vista ni isla arma una clase con interpolación" do
    culpables = ARCHIVOS.filter_map do |ruta|
      patron = PATRONES.fetch(ruta.extname)
      lineas = ruta.read.lines.each_with_index.filter_map do |linea, i|
        "#{ruta.relative_path_from(Rails.root)}:#{i + 1}  #{linea.strip}" if linea =~ patron
      end
      lineas.presence
    end.flatten

    expect(culpables).to be_empty, <<~TXT
      Estas líneas arman una clase interpolando: Tailwind no las ve y las descarta.
      En HAML, usá un helper de EstilosHelper que devuelva el nombre completo.
      En una isla Vue, que el nombre completo lo mande el presenter en las props.

      #{culpables.join("\n")}
    TXT
  end
end
