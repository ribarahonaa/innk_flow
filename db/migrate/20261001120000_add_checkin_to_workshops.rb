# frozen_string_literal: true

# El check-in del taller: cómo se establece la presencia, con qué credencial se
# entra, y dónde espera quien llegó.
#
# `attendance_mode` declara la SEMÁNTICA y no el gadget: `registered` no dice
# «QR», dice que la presencia se registra en vez de presumirse. El QR es una
# forma de registrarla y el toggle de la pantalla es la otra.
#
# `checkin_token` va SEPARADO del modo a propósito. La tentación es derivar uno
# del otro —«hay token, entonces hay QR»— y ahorrar una columna: no se hace,
# porque rotar el token para revocar un link filtrado devolvería la asistencia a
# presumida EN MEDIO de la sesión, y `Flow::Workshops::AssignGroups` volvería a
# sentar a toda la empresa sin que nadie lo pidiera.
#
# El índice de `arrival` es UNIQUE PARCIAL: una mesa de llegada por taller, y lo
# garantiza la base porque dos personas que escanean en el mismo segundo
# atraviesan cualquier `find_or_create_by`.
class AddCheckinToWorkshops < ActiveRecord::Migration[7.1]
  def up
    add_column :workshops, :attendance_mode, :string, null: false, default: "presumed"
    add_check_constraint :workshops,
                         "attendance_mode IN ('presumed', 'registered')",
                         name: "workshops_attendance_mode_check"

    # Nullable, backfill, y recién después NOT NULL: `has_secure_token` sólo
    # llena en el `create`, así que las filas que ya están no tendrían token.
    add_column :workshops, :checkin_token, :string
    execute "UPDATE workshops SET checkin_token = replace(uuid_generate_v7()::text, '-', '')"
    change_column_null :workshops, :checkin_token, false
    add_index :workshops, :checkin_token, unique: true

    add_column :workshop_groups, :arrival, :boolean, null: false, default: false
    add_index :workshop_groups, :workshop_id, unique: true, where: "arrival",
              name: "index_workshop_groups_on_workshop_id_arrival"
  end

  def down
    remove_index :workshop_groups, name: "index_workshop_groups_on_workshop_id_arrival"
    remove_column :workshop_groups, :arrival
    remove_index :workshops, :checkin_token
    remove_column :workshops, :checkin_token
    remove_check_constraint :workshops, name: "workshops_attendance_mode_check"
    remove_column :workshops, :attendance_mode
  end
end
