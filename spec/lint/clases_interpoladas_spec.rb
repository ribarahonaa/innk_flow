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
RSpec.describe "clases CSS interpoladas", type: :lint do
  VISTAS = Rails.root.glob("app/views/**/*.haml")

  it "ninguna vista arma una clase con interpolación" do
    culpables = VISTAS.filter_map do |ruta|
      lineas = ruta.read.lines.each_with_index.filter_map do |linea, i|
        "#{ruta.relative_path_from(Rails.root)}:#{i + 1}  #{linea.strip}" if
          linea =~ /class[:=][^,)]*"[^"]*\#\{/
      end
      lineas.presence
    end.flatten

    expect(culpables).to be_empty, <<~TXT
      Estas líneas arman una clase con #{'#'}{}: Tailwind no las ve y las descarta.
      Usá un helper de EstilosHelper que devuelva el nombre completo.

      #{culpables.join("\n")}
    TXT
  end
end
