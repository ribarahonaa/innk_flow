# frozen_string_literal: true

class EnableExtensionsAndUuidV7 < ActiveRecord::Migration[7.1]
  def up
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")

    # UUIDv7: timestamp-ordenado, a diferencia de v4.
    #
    # Dos razones para no usar bigint secuencial: (a) un id secuencial es un
    # oráculo de enumeración cross-tenant — la mitad del vector de fuga clásico;
    # (b) v4 puro fragmenta los índices B-tree porque las inserciones caen en
    # posiciones aleatorias. v7 da las dos cosas: no adivinable e insert-ordenado.
    #
    # Postgres 18 trae uuidv7() nativo. Acá corre 17, así que va en plpgsql.
    execute <<~SQL
      CREATE OR REPLACE FUNCTION uuid_generate_v7() RETURNS uuid AS $$
      DECLARE
        unix_ts_ms bytea;
        uuid_bytes bytea;
      BEGIN
        unix_ts_ms := substring(
          int8send((extract(epoch from clock_timestamp()) * 1000)::bigint) from 3
        );
        uuid_bytes := unix_ts_ms || gen_random_bytes(10);
        -- nibble alto del byte 6 = version (7)
        uuid_bytes := set_byte(uuid_bytes, 6, ((get_byte(uuid_bytes, 6) & 15) | 112));
        -- dos bits altos del byte 8 = variant (RFC 4122)
        uuid_bytes := set_byte(uuid_bytes, 8, ((get_byte(uuid_bytes, 8) & 63) | 128));
        RETURN encode(uuid_bytes, 'hex')::uuid;
      END
      $$ LANGUAGE plpgsql VOLATILE;
    SQL
  end

  def down
    execute "DROP FUNCTION IF EXISTS uuid_generate_v7()"
  end
end
