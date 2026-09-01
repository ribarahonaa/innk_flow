# frozen_string_literal: true

# Costura de autenticación. Hoy todas las filas son provider="password".
#
# Cuando se delegue el login en innk_r5 (SSO), se agregan filas
# provider="innk_r5" con el uid remoto y User no cambia. Tener la tabla desde
# el día 1 evita una migración de datos sobre usuarios vivos.
class Identity < ApplicationRecord
  PASSWORD = "password"

  belongs_to :user

  validates :provider, presence: true
  validates :uid, presence: true, uniqueness: { scope: :provider }
end
