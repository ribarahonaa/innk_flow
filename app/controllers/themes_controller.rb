# frozen_string_literal: true

# Escribe —o borra— la cookie del tema.
#
# No hereda ninguna regla de tenencia ni de sesión: la preferencia es del
# navegador y no del dominio, y el control también se sirve en el login, donde
# todavía no hay sesión ni empresa. Con `require_authentication` el botón del
# login rebotaba al login sin hacer nada.
class ThemesController < ApplicationController
  skip_before_action :require_authentication, :require_company

  def update
    if params[:theme] == "auto"
      # BORRAR, no escribir "flow". Escribir el nombre del tema claro dejaría
      # `data-theme` puesto, y con el atributo presente
      # `:root:not([data-theme])` no matchea nunca: el modo oscuro automático
      # quedaría muerto para siempre, en silencio.
      cookies.delete(:theme)
    elsif Flow::Themes::NAMES.include?(params[:theme])
      cookies.permanent[:theme] = { value: params[:theme], same_site: :lax }
    end
    # Un valor fuera de la lista no hace nada: ni escribe ni borra.

    redirect_back fallback_location: root_path
  end
end
