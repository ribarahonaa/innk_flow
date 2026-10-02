# frozen_string_literal: true

module CheckinHelper
  # El QR del taller, como SVG servido por el server.
  #
  # Va NEGRO SOBRE BLANCO en los DOS temas, y el color es un literal y no un
  # token: un lector de QR no es un elemento de la hoja, y un QR invertido
  # —módulos claros sobre fondo oscuro— lo leen mal muchos teléfonos. El fondo
  # blanco lo pone el contenedor en la vista.
  #
  # `viewbox: true` es lo que deja que el tamaño lo decida el contenedor, así
  # que acá no hay medidas.
  #
  # Se saca el prólogo XML que trae `as_svg`: dentro de un documento HTML es
  # basura y además una declaración falsa (`standalone="yes"`).
  def qr_svg(url)
    svg = RQRCode::QRCode.new(url, level: :m)
                         .as_svg(use_path: true, viewbox: true, color: "000000")
    svg.sub(/\A<\?xml[^>]*\?>/, "").html_safe
  end
end
