# frozen_string_literal: true

require "rails_helper"

# La cadena del sello del borrador tiene TRES eslabones y sólo uno de ellos
# puede fallar en la suite.
#
# El servidor sella `based_on_version_id` una vez, al crear la fila, y desde la
# revisión final lo hace con la versión que dice el CLIENTE: entre el render y
# la primera tecla la versión puede avanzar, y sellar la nueva sobre contenido
# de la vieja apagaba el aviso de base vieja para siempre. Así que el dato viaja
# así:
#
#   `_evolution.html.haml`  →  `data-draft-base` en el form
#   `workshop_draft.js`     →  lo lee de `form.dataset.draftBase` y lo manda
#                              como `base_version_id`
#   `WorkshopDraftsController#write!`  →  lo busca en `idea.versions` y sella
#
# El tercer eslabón está cubierto y rojo por mutación
# (`spec/requests/workshop_drafts_spec.rb`, el ejemplo del sello contra una
# versión que avanzó en el medio). Los dos primeros NO los cubre nada en
# runtime: los request specs mandan `base_version_id` a mano, así que nunca
# ejecutan el JS, y `[DRAFT]` en `make screens` no publica ninguna versión entre
# el render y el tipeo, así que con el atributo o el envío borrados el sello cae
# a `current_version_id` y la guarda no nota la diferencia. Medido: borrar las
# tres líneas de `cuerpo()` dejaba `make spec` y `[DRAFT] 2` en verde.
#
# LO QUE ESTA GUARDA SÍ HACE Y LO QUE NO. Caza la BORRADURA de un eslabón —que
# es el modo de falla real: las dos veces que esto se rompió fue alguien
# «simplificando» una línea que parecía no hacer nada—. NO caza un cambio de
# lógica: si el JS mandara el valor equivocado, el texto seguiría estando y esto
# seguiría verde. El discriminador de lógica es un ejemplo de request —el de la
# versión de otra idea de la misma empresa—, no esto.
#
# Es texto porque no hay otra opción: no hay infra de test de JavaScript en el
# repo (`package.json` tiene `build` y `build:css` y nada más), y montar una
# para tres líneas cuesta más de lo que rinde. Es el mismo trato que
# `clases_interpoladas_spec.rb`, que también grepea `app/javascript`.
RSpec.describe "la cadena del sello del borrador", type: :lint do
  JS = Rails.root.join("app/javascript/workshop_draft.js")
  VISTA = Rails.root.join("app/views/workshop_rooms/_evolution.html.haml")

  # Cada eslabón con el porqué de su regex. Los tres son deliberadamente laxos
  # en el espaciado y estrictos en el NOMBRE: lo que se protege es que el dato
  # siga viajando con la clave que la otra punta espera, no cómo está escrito.
  ESLABONES = {
    "la vista publica la versión del render en el form" => {
      archivo: VISTA,
      patron: /draft_base:/,
      porque: "sin `draft_base` el JS no tiene qué mandar y el servidor sella " \
              "`current_version_id`: el aviso de base vieja no dispara nunca"
    },
    "el JS lee ese atributo" => {
      archivo: JS,
      patron: /dataset\.draftBase/,
      porque: "`data-draft-base` se vuelve `dataset.draftBase`: si el JS deja " \
              "de leerlo, el atributo queda decorativo"
    },
    "y lo manda con la clave que el controller lee" => {
      archivo: JS,
      patron: /base_version_id/,
      porque: "`WorkshopDraftsController#write!` lee `params[:base_version_id]`: " \
              "con otra clave el valor se descarta en silencio y se cae a la vigente"
    }
  }.freeze

  # El detector se prueba a sí mismo. No es ceremonia: una guarda de texto mal
  # acotada reporta cero y da verde, que es indistinguible de una que funciona
  # —el mismo motivo por el que `reglas_sin_elemento_spec.rb` tiene autotest y
  # por el que `[MONO]` lo tiene en las capturas—. Acá el riesgo concreto es un
  # regex que matchee el COMENTARIO que explica la línea en vez de la línea:
  # los tres nombres aparecen también en prosa, así que un detector que sólo
  # buscara la palabra seguiría verde con el código borrado.
  describe "el detector" do
    it "los tres archivos existen y se leen" do
      ESLABONES.each_value do |e|
        expect(e[:archivo]).to exist, "#{e[:archivo]} no está: ¿se renombró?"
        expect(e[:archivo].read).not_to be_empty
      end
    end

    it "sabe decir que no: ninguno de los patrones matchea un archivo cualquiera" do
      ajeno = Rails.root.join("app/models/workshop_draft.rb").read
      ESLABONES.each do |nombre, e|
        expect(ajeno).not_to match(e[:patron]), "«#{nombre}» matchea el modelo: el patrón es demasiado laxo"
      end
    end

    # Lo que hay que probar es el STRIPPER, no que los patrones matcheen: de eso
    # ya se encargan los tres ejemplos de abajo, que comparan contra el código
    # desnudo. Pero si `sin_comentarios` devolviera el archivo entero —un regex
    # de más, un `sub` que no matchea— esos tres seguirían verdes mientras la
    # protección se volvió vacía: pasarían leyendo la prosa que explica cada
    # línea. Un stripper roto no se nota; por eso se mide con frases que viven
    # SÓLO en un comentario.
    it "el stripper saca de verdad los comentarios de las dos sintaxis" do
      js = sin_comentarios(JS)
      expect(JS.read).to include("El fallo se dice y se REINTENTA")
      expect(js).not_to include("El fallo se dice y se REINTENTA"), "no sacó un `//` del JS"
      expect(js).to include("datos.append"), "se llevó puesto el código"

      haml = sin_comentarios(VISTA)
      expect(VISTA.read).to include("El borrador le gana a la versión vigente")
      expect(haml).not_to include("El borrador le gana a la versión vigente"), "no sacó un `-#` del HAML"
      expect(haml).to include("form_with"), "se llevó puesto el markup"
    end
  end

  ESLABONES.each do |nombre, e|
    it nombre do
      expect(sin_comentarios(e[:archivo])).to match(e[:patron]), <<~TXT
        Se cortó un eslabón de la cadena del sello del borrador, en
        #{e[:archivo].relative_path_from(Rails.root)}.

        #{e[:porque]}.

        El efecto no lo ve ninguna otra verificación: `make spec` y `[DRAFT]` en
        `make screens` siguen en verde, y el aviso de base vieja deja de
        dispararse sin que nada lo diga. Si el cambio es a propósito, acá hay que
        decir con qué se reemplazó.
      TXT
    end
  end

  # Los comentarios de las dos puntas se escriben distinto: `//` y `-#` (más el
  # `/* */` que el JS no usa hoy pero podría). No se intenta parsear: alcanza
  # con sacar lo que es comentario de línea entera o de cola.
  def sin_comentarios(ruta)
    cuerpo = ruta.read.gsub(%r{/\*.*?\*/}m, "")
    cuerpo.lines.filter_map do |linea|
      sin = linea.sub(%r{//.*}, "").sub(/-#.*/, "")
      sin unless sin.strip.empty?
    end.join("\n")
  end
end
