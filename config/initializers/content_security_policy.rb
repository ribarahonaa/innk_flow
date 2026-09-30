# frozen_string_literal: true

# El CSP de la app.
#
# Estuvo COMENTADO ENTERO mucho tiempo, y mientras tanto
# `shared/_reports_auto_refresh.html.haml` ya pedía
# `nonce: content_security_policy_nonce`: había código escrito para un CSP que no
# existía, así que ese nonce no hacía nada. Eso es lo que lo destrabó — no la
# amenaza, que es modesta, sino que media app ya lo daba por puesto.
#
# Se declara ACOTADO a propósito. Lo que está acá no puede romper esta app, y
# está verificado uno por uno:
#
#   · `object_src :none` — no hay un solo `<object>` ni `<embed>` en las vistas
#     ni en las islas. Cierra la inyección de plugins.
#   · `base_uri :self` — no hay ningún `<base>`. Cierra el secuestro de todas
#     las URLs relativas de la página con una sola etiqueta inyectada.
#   · `frame_ancestors :self` — la app no se embebe en ningún lado. Cierra el
#     clickjacking, y no lo tapa `X-Frame-Options` porque nadie lo declara.
#   · `script_src :self` + nonce — hay UN script inline en toda la app y ya trae
#     su nonce. Todo lo demás es bundle servido de `/assets`.
#
# Lo que NO se declara, y por qué:
#
#   · `style_src` se queda abierto. HAML emite atributos `style=` en varias
#     vistas y los popups de IA los arman en JS; declararlo sin
#     `unsafe-inline` los rompería y con `unsafe-inline` no protege de nada.
#   · `default_src` tampoco: sin él, lo que no está declarado no se restringe,
#     que es lo que hace que esto no pueda romper nada que no se haya revisado.
#     Ponerlo es la decisión siguiente, y es la que sí exige recorrer la app.
#
# El riesgo por el que este archivo estaba fichado —servir un adjunto inline,
# que lo sube cualquiera que postula— NO lo cierra esto: lo cierran las dos capas
# de `ApplicationController#send_attached_file` (`content_type_for_serving`
# fuerza octet-stream para html y svg, y `disposition: "attachment"` baja en vez
# de renderizar), y ahora también el spec que las sostiene.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.object_src :none
    policy.base_uri :self
    policy.frame_ancestors :self
    policy.script_src :self
  end

  # Aleatorio por pedido, y NO `request.session.id.to_s`, que es lo que sugiere
  # el archivo comentado que viene con Rails. Con el id de sesión el nonce sale
  # VACÍO —medido: el header decía `'nonce-'` y el tag `nonce=""`— porque la
  # sesión no siempre está cargada cuando se arma la cabecera, y un nonce vacío
  # no matchea: el navegador BLOQUEA el script inline. Que es el del polling de
  # reportes, o sea la pantalla que se queda sin refrescarse sola.
  #
  # `make screens` no podía cazarlo por dos motivos: sólo escucha `pageerror` y
  # una violación de CSP es un error de consola, y encima ese script sólo se
  # renderiza con un reporte PENDIENTE, que el recorrido no produce. Lo cazó el
  # spec de `spec/requests/pantalla_del_modulo_spec.rb`, que compara el nonce del
  # tag contra el del header.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
