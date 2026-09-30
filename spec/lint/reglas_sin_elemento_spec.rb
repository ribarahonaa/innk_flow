# frozen_string_literal: true

require "rails_helper"

# La mitad que faltaba de una simetría.
#
# `[CLASES]` en `make screens` caza un ELEMENTO que se quedó sin regla: una clase
# que Tailwind no vio al escanear, o una que perdió la regla que la pintaba por un
# renombre. Nada cazaba lo contrario —una REGLA que se quedó sin elemento— y por
# eso se juntaron siete en silencio: los cuatro `criterion-row__*` del markup
# anterior del editor de criterios, `btn-link` con su comentario prometiendo una
# migración pantalla por pantalla que ya no tenía pantallas, y `checks-help` e
# `inline-label`.
#
# CSS muerto no rompe nada, y ahí está el problema: no se ve, no falla, y la hoja
# crece. Peor con `btn-link`, que COLISIONA con DaisyUI —la de la app gana por
# estar sin capa— así que dejarla era conservar una trampa para nadie.
RSpec.describe "reglas de CSS sin ningún elemento", type: :lint do
  HOJA = Rails.root.join("app/assets/stylesheets/application.css")

  # Dos, y las dos con el porqué. Si esta lista crece, la pregunta es por qué la
  # regla existe, no cómo callar la guarda: una lista blanca larga es donde las
  # cosas se esconden, y es exactamente el motivo por el que las siete se
  # borraron en vez de declararse.
  EXCEPCIONES = {
    "btn-disabled" => "no la usa el markup: la usan los selectores de la propia hoja " \
                      "(`.btn-ghost:not(…, .btn-disabled)`), que es donde DaisyUI la pone",
    "woff2" => "no es una clase: sale del `format(\"woff2\")` de un `@font-face`"
  }.freeze

  # Sin `spec/`: una clase cuyo único uso es una aserción de spec está muerta en
  # la app. Hoy da lo mismo —comprobado, la lista no cambia— y esto es lo
  # estricto. Sin `app/assets/builds`, que es la hoja COMPILADA: buscar ahí haría
  # que toda clase se encuentre a sí misma y la guarda no reportaría nunca nada.
  def self.fuente
    @fuente ||= begin
      patrones = ["app/**/*.haml", "app/**/*.vue", "app/**/*.js", "app/**/*.rb", "script/*.js"]
      patrones.flat_map { |p| Rails.root.glob(p) }
              .reject { |f| f.to_s.include?("assets/builds") }
              .map { |f| f.read }
              .join("\n")
    end
  end

  def self.declaradas
    @declaradas ||= begin
      css = HOJA.read.gsub(%r{/\*.*?\*/}m, "")
      css.scan(/\.([a-zA-Z][a-zA-Z0-9_-]*)/).flatten.uniq.sort
    end
  end

  # Token EXACTO: ni prefijo ni sufijo de otro nombre, para que `card` no se dé
  # por usada porque existe `challenge-card`.
  def usada?(clase)
    self.class.fuente.match?(/(?<![\w-])#{Regexp.escape(clase)}(?![\w-])/)
  end

  # El detector se prueba a sí mismo, y no es ceremonia: el primero que escribí
  # reportó 267 de 402 «sin uso», con `app-main` y `card-body` adentro. HAML no
  # escribe `class="x"` sino `.x`, y ese regex sólo miraba el atributo. Un
  # detector roto reporta de más —ruidoso, se nota— pero uno mal ACOTADO reporta
  # cero y da verde, que no se nota.
  describe "el detector" do
    it "lee la hoja: encuentra las clases que la app usa en todas partes" do
      expect(self.class.declaradas).to include("card", "app-main", "flow-drawer", "empty-state")
      expect(self.class.declaradas.size).to be >= 300
    end

    it "ve una clase escrita con la taquigrafía de HAML, que es donde ya falló" do
      # `.app-main` y `.page-title` no aparecen NUNCA como `class="…"`: se
      # escriben `%main.app-main` y `%h1.page-title`.
      expect(usada?("app-main")).to be(true)
      expect(usada?("page-title")).to be(true)
    end

    it "y sabe decir que no" do
      expect(usada?("clase-que-no-existe-en-ninguna-parte")).to be(false)
    end
  end

  it "toda clase declarada en la hoja la usa alguien" do
    huerfanas = self.class.declaradas.reject { |c| EXCEPCIONES.key?(c) || usada?(c) }

    expect(huerfanas).to be_empty, lambda {
      "Reglas en `application.css` que ningún elemento usa:\n" +
        huerfanas.map { |c| "  - .#{c}" }.join("\n") +
        "\n\nO se borra la regla, o —si de verdad tiene que quedarse— se declara en\n" \
        "`EXCEPCIONES` con el motivo. Una lista blanca larga es donde las cosas se esconden."
    }
  end
end
