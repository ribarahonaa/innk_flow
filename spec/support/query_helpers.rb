# frozen_string_literal: true

module QueryHelpers
  # Cuenta las consultas a una tabla durante el bloque. Para los N+1: el número
  # que importa no es cuántas consultas hace la pantalla sino si CRECE con las
  # filas, así que los ejemplos siembran varias y fijan un tope que no depende
  # de cuántas haya.
  #
  # `payload[:cached]` se saltea, y eso ACOTA lo que esto puede medir: la caché
  # de consultas de Rails sirve la repetición IDÉNTICA sin ir a la base, así que
  # un fan-out que repite el mismo SQL —un `find_by` con el mismo id, una
  # asociación leída dos veces— es invisible para este contador. Lo que sí mide
  # es el fan-out con SQL distinto por fila, que es el caso de un `find_by(id:)`
  # por criterio.
  def consultas_a(tabla)
    sql = []
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      next if payload[:name] == "SCHEMA" || payload[:cached]

      next unless payload[:sql].include?(%(FROM "#{tabla}"))

      # Con el origen: el número solo dice que sobran consultas, no cuál de
      # las tres lecturas de la misma lista las hace. Encontrar ESTE N+1 llevó
      # a `evaluation.html.haml:13` y no a donde el reporte decía.
      origen = caller.grep(%r{/app/}).first(2)
      sql << "#{payload[:sql][0, 70]}\n      <- #{origen.join("\n      <- ")}"
    end
    yield
    sql
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end
end

RSpec.configure { |config| config.include QueryHelpers }
