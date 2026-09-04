# frozen_string_literal: true

# El tipo `vector` de pgvector es desconocido para Rails: sin esto, cada
# proceso que toca `idea_versions` escupe «unknown OID … will be treated as
# String» antes de hacer exactamente eso.
#
# Se registra como string a propósito y no como un tipo propio: el vector nunca
# se lee como número en Ruby. Se escribe con SQL (`?::vector`) y se compara
# dentro de Postgres, que es lo que tiene el índice.
module PgvectorTypeMap
  def initialize_type_map(map = type_map)
    super
    map.register_type("vector") { ActiveRecord::Type::String.new }
  end
end

ActiveSupport.on_load(:active_record_postgresqladapter) do
  ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend(PgvectorTypeMap)
end
